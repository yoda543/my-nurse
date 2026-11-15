import 'package:material_ui/material_ui.dart';

import 'data/demo_data.dart';
import 'models.dart';

/// État de l'application en mode démo (en mémoire).
/// Les mêmes méthodes seront branchées sur Supabase.
class AppState extends ChangeNotifier {
  AppState() {
    _seed();
  }

  final List<CareService> services = demoServices;
  final List<Pro> pros = buildDemoPros();
  final List<Booking> bookings = [];

  UserRole? role;
  String patientName = 'Awa Bamba';

  /// Le titulaire du compte et les proches qu'il gère.
  late final List<Patient> patients = [Patient(id: 'P0', name: patientName)];
  String commune = communes.first;
  int _nextId = 1;

  /// En démo, l'espace soignant est celui du premier infirmier.
  Pro get currentPro => pros.first;

  bool get loggedIn => role != null;

  void login(UserRole r) {
    role = r;
    notifyListeners();
  }

  void logout() {
    role = null;
    notifyListeners();
  }

  void setCommune(String c) {
    commune = c;
    notifyListeners();
  }

  Patient addPatient({
    required String name,
    required String relation,
    String allergies = '',
  }) {
    final p = Patient(
      id: 'P${patients.length}',
      name: name,
      relation: relation,
      allergies: allergies,
    );
    patients.add(p);
    notifyListeners();
    return p;
  }

  /// Pros vérifiés proposant ce service dans la commune, meilleurs d'abord.
  List<Pro> prosFor(CareService s, String commune) {
    final list = pros
        .where((p) =>
            p.verified &&
            p.prices.containsKey(s.id) &&
            p.communes.contains(commune))
        .toList();
    list.sort((a, b) => b.rating.compareTo(a.rating));
    return list;
  }

  Booking book({
    required CareService service,
    required Pro pro,
    required String commune,
    required String address,
    required DateTime scheduledAt,
    required bool hasPrescription,
    String note = '',
    Patient? patient,
    String? otherPatientName,
  }) {
    final who = patient ?? patients.first;
    final b = Booking(
      id: 'R${_nextId++}',
      patientName: otherPatientName ?? who.name,
      patientAllergies: otherPatientName == null ? who.allergies : '',
      mine: otherPatientName == null,
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

  void cancel(Booking b) {
    if (b.status != BookingStatus.pending &&
        b.status != BookingStatus.accepted) {
      return;
    }
    b.status = BookingStatus.cancelled;
    notifyListeners();
  }

  void submitCareLog(Booking b, CareLog log) {
    if (b.status != BookingStatus.accepted) return;
    b.careLog = log;
    b.status = BookingStatus.done;
    b.pro.careCount++;
    notifyListeners();
  }

  void rate(Booking b, int stars, String review) {
    if (b.status != BookingStatus.done || b.rating != null) return;
    b.rating = stars;
    b.review = review;
    final p = b.pro;
    p.rating = (p.rating * p.ratingCount + stars) / (p.ratingCount + 1);
    p.ratingCount++;
    notifyListeners();
  }

  List<Booking> get patientBookings =>
      bookings.where((b) => b.mine).toList();

  List<Booking> proBookings(BookingStatus status) => bookings
      .where((b) => b.pro.id == currentPro.id && b.status == status)
      .toList();

  void _seed() {
    final now = DateTime.now();
    DateTime at(int days, int hour) =>
        DateTime(now.year, now.month, now.day + days, hour);
    final aya = pros.first;
    CareService s(String id) => services.firstWhere((e) => e.id == id);

    // Une demande en attente et un soin confirmé pour l'espace soignant.
    book(
      service: s('pansement'),
      pro: aya,
      commune: 'Riviera',
      address: 'Riviera Palmeraie, résidence Les Orchidées, villa 12',
      scheduledAt: at(1, 9),
      hasPrescription: false,
      note: 'Pansement après opération du genou.',
      otherPatientName: 'Jean Kouassi',
    );
    final confirmed = book(
      service: s('injection'),
      pro: aya,
      commune: 'Cocody',
      address: 'Cocody Angré, 8e tranche, immeuble Sika, 2e étage',
      scheduledAt: at(0, 17),
      hasPrescription: true,
      otherPatientName: 'Adjoua Brou',
    );
    confirmed.status = BookingStatus.accepted;

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
    past.careLog = CareLog(
      arrivedAt: at(-3, 10),
      leftAt: at(-3, 10).add(const Duration(minutes: 35)),
      acts: 'Nettoyage de la plaie, pansement refait.',
      bloodPressure: '13/8',
      temperature: '37,1',
      pulse: '76',
      observations: 'Plaie propre, cicatrisation normale. Prochain pansement dans 2 jours.',
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
