import 'package:material_ui/material_ui.dart';

import 'data/demo_data.dart';
import 'models.dart';

/// État de l'application en mode démo (en mémoire).
/// Chaque méthode correspond à une écriture contrôlée côté serveur
/// (voir supabase/migrations) : mêmes règles, mêmes refus.
class AppState extends ChangeNotifier {
  AppState({bool seed = true}) {
    if (seed) _seed();
  }

  /// Numéro du soignant de démonstration déjà inscrit.
  static const demoProPhone = '0500000000';

  final List<CareService> services = demoServices;
  final List<Pro> pros = buildDemoPros();
  final List<Booking> bookings = [];

  UserRole? role;
  String patientName = 'Awa Bamba';
  String commune = communes.first;
  int _nextId = 1;

  /// Le titulaire du compte et les proches qu'il gère.
  late final List<Patient> patients = [
    Patient(
      id: 'P0',
      name: patientName,
      birthYear: 1988,
      allergies: '',
      history: '',
    ),
  ];

  /// Soignant connecté (null tant que le dossier n'est pas créé).
  Pro? currentPro;

  /// Numéro utilisé pour se connecter.
  String sessionPhone = '';

  bool get loggedIn => role != null;

  // ------------------------------------------------------------- session
  void login(UserRole r, {String phone = ''}) {
    role = r;
    sessionPhone = phone;
    notifyListeners();
  }

  /// Connexion soignant : retrouve le compte par numéro, sinon inscription.
  void loginPro(String phone) {
    sessionPhone = phone;
    currentPro = phone == demoProPhone
        ? pros.first
        : pros.where((p) => p.phone == phone).firstOrNull;
    role = UserRole.pro;
    notifyListeners();
  }

  void logout() {
    role = null;
    sessionPhone = '';
    currentPro = null;
    notifyListeners();
  }

  void setCommune(String c) {
    commune = c;
    notifyListeners();
  }

  // --------------------------------------------------------- inscription pro
  Pro registerPro({
    required String name,
    required String phone,
    required ProType type,
    required List<String> communes,
    required Map<String, int> prices,
    required int yearsExperience,
    required String bio,
    required String orderNumber,
    required bool nightAvailable,
    required Set<DocType> documents,
  }) {
    for (final e in prices.entries) {
      final s = services.firstWhere((s) => s.id == e.key);
      if (s.proType != type) {
        throw ArgumentError('${s.name} ne correspond pas à votre profession.');
      }
      if (e.value < s.minPrice || e.value > s.maxPrice) {
        throw ArgumentError('Prix hors de la fourchette pour ${s.name}.');
      }
    }
    final p = Pro(
      id: 'pro${pros.length + 1}',
      name: name,
      phone: phone,
      type: type,
      communes: communes,
      prices: prices,
      yearsExperience: yearsExperience,
      bio: bio,
      orderNumber: orderNumber,
      nightAvailable: nightAvailable,
      documents: documents,
      status: VerificationStatus.pending,
    );
    pros.add(p);
    currentPro = p;
    notifyListeners();
    return p;
  }

  /// Après un refus, le pro complète son dossier et le renvoie.
  void resubmitPro(Pro p, Set<DocType> documents) {
    if (p.status != VerificationStatus.rejected) return;
    p.documents
      ..clear()
      ..addAll(documents);
    p.rejectionReason = '';
    p.status = VerificationStatus.pending;
    notifyListeners();
  }

  void updateProAvailability(
    Pro p, {
    required List<String> communes,
    required bool nightAvailable,
  }) {
    if (communes.isEmpty) return;
    p.communes = communes;
    p.nightAvailable = nightAvailable;
    notifyListeners();
  }

  // ------------------------------------------------------------ administration
  List<Pro> prosWithStatus(VerificationStatus s) =>
      pros.where((p) => p.status == s).toList();

  void verifyPro(Pro p) {
    if (p.status != VerificationStatus.pending &&
        p.status != VerificationStatus.suspended) {
      return;
    }
    if (p.missingDocs.isNotEmpty) {
      throw StateError('Dossier incomplet.');
    }
    p.status = VerificationStatus.verified;
    p.rejectionReason = '';
    notifyListeners();
  }

  void rejectPro(Pro p, String reason) {
    if (p.status != VerificationStatus.pending) return;
    p.status = VerificationStatus.rejected;
    p.rejectionReason = reason;
    notifyListeners();
  }

  /// Suspend un pro : ses soins à venir sont annulés et remboursés.
  void suspendPro(Pro p, String reason) {
    if (p.status != VerificationStatus.verified) return;
    p.status = VerificationStatus.suspended;
    p.rejectionReason = reason;
    for (final b in bookings.where(
      (b) =>
          b.pro == p &&
          (b.status == BookingStatus.pending ||
              b.status == BookingStatus.accepted),
    )) {
      _cancel(b, 'Soignant suspendu par MyNurse');
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- patients
  Patient addPatient({
    required String name,
    required String relation,
    String allergies = '',
    int? birthYear,
  }) {
    final p = Patient(
      id: 'P${patients.length}',
      name: name,
      relation: relation,
      allergies: allergies,
      birthYear: birthYear,
    );
    patients.add(p);
    notifyListeners();
    return p;
  }

  void updateHealthRecord(
    Patient p, {
    required String allergies,
    required String history,
    required String treatments,
  }) {
    p.allergies = allergies;
    p.history = history;
    p.treatments = treatments;
    notifyListeners();
  }

  /// Comptes rendus de soins d'une personne, du plus récent au plus ancien.
  List<Booking> careHistory(Patient p) =>
      bookings.where((b) => b.patient == p && b.careLog != null).toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  // ------------------------------------------------------------ recherche
  /// Pros vérifiés proposant ce service dans la commune, meilleurs d'abord.
  List<Pro> prosFor(CareService s, String commune) {
    final list = pros
        .where(
          (p) =>
              p.verified &&
              p.prices.containsKey(s.id) &&
              p.communes.contains(commune),
        )
        .toList();
    list.sort((a, b) => b.rating.compareTo(a.rating));
    return list;
  }

  // --------------------------------------------------------- réservations
  Booking book({
    required CareService service,
    required Pro pro,
    required String commune,
    required String address,
    required DateTime scheduledAt,
    required bool hasPrescription,
    String note = '',
    Patient? patient,
    bool mine = true,
  }) {
    if (!pro.verified || !pro.prices.containsKey(service.id)) {
      throw StateError("Ce soignant n'est pas disponible pour ce soin.");
    }
    final b = Booking(
      id: 'R${_nextId++}',
      patient: patient ?? patients.first,
      mine: mine,
      service: service,
      pro: pro,
      commune: commune,
      address: address,
      scheduledAt: scheduledAt,
      basePrice: pro.prices[service.id]!,
      hasPrescription: hasPrescription,
      note: note,
    );
    bookings.insert(0, b);
    notifyListeners();
    return b;
  }

  void respond(Booking b, {required bool accept}) {
    if (b.status != BookingStatus.pending) return;
    b.status = accept ? BookingStatus.accepted : BookingStatus.refused;
    notifyListeners();
  }

  /// Paiement Mobile Money. En production : agrégateur (CinetPay ou PayDunya),
  /// confirmé par son webhook, jamais par l'app.
  void pay(Booking b, PaymentMethod method) {
    if (!b.awaitingPayment) return;
    b.paymentMethod = method;
    b.paidAt = DateTime.now();
    notifyListeners();
  }

  void cancel(Booking b, {String reason = 'Annulé par le patient'}) {
    if (b.status != BookingStatus.pending &&
        b.status != BookingStatus.accepted) {
      return;
    }
    _cancel(b, reason);
    notifyListeners();
  }

  void _cancel(Booking b, String reason) {
    b.status = BookingStatus.cancelled;
    b.cancelReason = reason;
    if (b.paid) b.refunded = true;
  }

  void submitCareLog(Booking b, CareLog log) {
    if (!b.readyForCare) return;
    b.careLog = log;
    b.status = BookingStatus.done;
    b.pro.careCount++;
    notifyListeners();
  }

  void rate(Booking b, int stars, String review) {
    if (b.status != BookingStatus.done || b.rating != null) return;
    if (stars < 1 || stars > 5) return;
    b.rating = stars;
    b.review = review;
    final p = b.pro;
    p.rating = (p.rating * p.ratingCount + stars) / (p.ratingCount + 1);
    p.ratingCount++;
    notifyListeners();
  }

  List<Booking> get patientBookings => bookings.where((b) => b.mine).toList();

  List<Booking> proBookings(BookingStatus status) =>
      bookings.where((b) => b.pro == currentPro && b.status == status).toList();

  // ------------------------------------------------------------- chiffres
  /// Soins terminés : l'argent a été reversé au pro, commission encaissée.
  Iterable<Booking> get doneBookings =>
      bookings.where((b) => b.status == BookingStatus.done);
  int get grossVolume => doneBookings.fold(0, (s, b) => s + b.price);
  int get commissionTotal => doneBookings.fold(0, (s, b) => s + b.commission);

  /// Argent payé, bloqué en attendant la fin du soin.
  int get escrowTotal =>
      bookings.where((b) => b.readyForCare).fold(0, (s, b) => s + b.price);
  int get refundTotal =>
      bookings.where((b) => b.refunded).fold(0, (s, b) => s + b.price);

  void _seed() {
    final now = DateTime.now();
    DateTime at(int days, int hour) =>
        DateTime(now.year, now.month, now.day + days, hour);
    final aya = pros.first;
    CareService s(String id) => services.firstWhere((e) => e.id == id);
    final jean = Patient(id: 'X1', name: 'Jean Kouassi', birthYear: 1961);
    final adjoua = Patient(
      id: 'X2',
      name: 'Adjoua Brou',
      birthYear: 1954,
      allergies: 'Pénicilline',
      history: 'Diabète de type 2',
    );

    // Une demande en attente et un soin confirmé et payé pour l'espace soignant.
    book(
      service: s('pansement'),
      pro: aya,
      commune: 'Riviera',
      address: 'Riviera Palmeraie, résidence Les Orchidées, villa 12',
      scheduledAt: at(1, 9),
      hasPrescription: false,
      note: 'Pansement après opération du genou.',
      patient: jean,
      mine: false,
    );
    final confirmed = book(
      service: s('injection'),
      pro: aya,
      commune: 'Cocody',
      address: 'Cocody Angré, 8e tranche, immeuble Sika, 2e étage',
      scheduledAt: at(0, 17),
      hasPrescription: true,
      patient: adjoua,
      mine: false,
    );
    confirmed.status = BookingStatus.accepted;
    confirmed.paymentMethod = PaymentMethod.wave;
    confirmed.paidAt = at(-1, 12);

    // Un soin terminé dans l'historique du patient.
    final past = book(
      service: s('pansement'),
      pro: aya,
      commune: 'Cocody',
      address: 'Cocody Danga, rue des Jardins',
      scheduledAt: at(-3, 10),
      hasPrescription: false,
    );
    past.status = BookingStatus.done;
    past.paymentMethod = PaymentMethod.orange;
    past.paidAt = at(-4, 18);
    past.careLog = CareLog(
      arrivedAt: at(-3, 10),
      leftAt: at(-3, 10).add(const Duration(minutes: 35)),
      acts: 'Nettoyage de la plaie, pansement refait.',
      bloodPressure: '13/8',
      temperature: '37,1',
      pulse: '76',
      observations: 'Plaie propre, cicatrisation normale. Prochain pansement dans 2 jours.',
    );

    // Un dossier soignant à vérifier pour l'administration.
    pros.add(
      Pro(
        id: 'pro${pros.length + 1}',
        name: 'Bernadette Ouattara',
        phone: '0101010101',
        type: ProType.infirmier,
        communes: ['Marcory', 'Plateau'],
        prices: {'injection': 6000, 'pansement': 7000},
        yearsExperience: 4,
        bio: "Infirmière diplômée d'État, service de médecine interne.",
        orderNumber: 'ONII-CI 2021-0456',
        status: VerificationStatus.pending,
        documents: {
          DocType.diplome,
          DocType.autorisation,
          DocType.ordre,
          DocType.cni,
          DocType.rcPro,
        },
      ),
    );
  }
}

/// Donne accès à [AppState] dans l'arbre de widgets.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
