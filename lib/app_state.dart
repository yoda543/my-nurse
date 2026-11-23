import 'package:material_ui/material_ui.dart';

import 'data/demo_data.dart';
import 'location.dart';
import 'models.dart';

/// Refus d'une action pour une raison métier, avec un message à afficher.
class BusinessRuleError implements Exception {
  const BusinessRuleError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// État de l'application en mode démo (en mémoire).
/// Chaque méthode correspond à une écriture contrôlée côté serveur
/// (voir supabase/migrations) : mêmes règles, mêmes refus.
class AppState extends ChangeNotifier {
  AppState({bool seed = true, DateTime Function()? clock, Locator? locator})
    : _clock = clock ?? DateTime.now,
      locator = locator ?? DeviceLocator(demoFallback: true) {
    if (seed) _seed();
  }

  final DateTime Function() _clock;

  /// Donne la position du patient.
  final Locator locator;

  /// Dernier lieu détecté, et l'état de la détection en cours.
  DetectedPlace? place;
  bool locating = false;
  String? locationError;
  DateTime get now => _clock();

  /// Numéro du soignant de démonstration déjà inscrit.
  static const demoProPhone = '0500000000';

  final List<CareService> services = demoServices;
  final List<Pro> pros = buildDemoPros();
  final List<Booking> bookings = [];

  UserRole? role;
  String patientName = 'Awa Bamba';
  String commune = communes.first;
  int _nextId = 1;
  int _nextContract = 1;
  int _nextReceipt = 1;

  /// Chiffre d'affaires des abonnements Pro Premium.
  int premiumRevenue = 0;

  /// Le titulaire du compte et les proches qu'il gère.
  late final List<Patient> patients = [
    Patient(id: 'P0', name: patientName, birthYear: 1988),
  ];

  /// Porte-monnaie du compte patient connecté.
  final Wallet wallet = Wallet();

  /// Soignant connecté (null tant que le dossier n'est pas créé).
  Pro? currentPro;

  /// Numéro utilisé pour se connecter.
  String sessionPhone = '';

  bool get loggedIn => role != null;

  // ------------------------------------------------------------- session
  void login(UserRole r, {String phone = ''}) {
    role = r;
    sessionPhone = phone;
    expireStale();
    notifyListeners();
  }

  /// Connexion soignant : retrouve le compte par numéro, sinon inscription.
  void loginPro(String phone) {
    sessionPhone = phone;
    currentPro = phone == demoProPhone
        ? pros.first
        : pros.where((p) => p.phone == phone).firstOrNull;
    role = UserRole.pro;
    expireStale();
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

  /// Détecte le lieu du patient et choisit la commune automatiquement.
  /// Renvoie null si la position n'a pas pu être obtenue.
  Future<DetectedPlace?> detectPlace() async {
    if (locating) return place;
    locating = true;
    locationError = null;
    notifyListeners();
    try {
      final p = await locator.locate();
      place = p;
      if (p.commune != null) commune = p.commune!;
      if (p.commune == null) {
        locationError =
            'Vous semblez hors de nos communes (${communes.join(', ')}). '
            'Choisissez la commune du soin.';
      }
      return p;
    } on LocationError catch (e) {
      locationError = e.message;
      return null;
    } finally {
      locating = false;
      notifyListeners();
    }
  }

  // --------------------------------------------------------- inscription pro
  /// Retrouve un parrain vérifié à partir de son code.
  Pro? findReferrer(String code) {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return null;
    return pros.where((p) => p.verified && p.referralCode == c).firstOrNull;
  }

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
    String referralCode = '',
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
    final referrer = findReferrer(referralCode);
    if (referralCode.trim().isNotEmpty && referrer == null) {
      throw const BusinessRuleError('Code de parrainage inconnu.');
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
      referredBy: referrer,
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

  // ------------------------------------------------------------- Premium
  /// Abonnement Pro Premium, payé avec le solde du soignant.
  void subscribePremium(Pro p) {
    if (!p.verified) {
      throw const BusinessRuleError('Réservé aux soignants vérifiés.');
    }
    if (!p.wallet.move(
      WalletTxKind.subscription,
      -premiumPrice,
      'Abonnement Pro Premium (30 jours)',
      at: now,
    )) {
      throw const BusinessRuleError(
        'Solde insuffisant : il faut $premiumPrice FCFA sur votre solde.',
      );
    }
    p.premiumUntil = extendPremium(p.premiumUntil, now, premiumPeriod);
    premiumRevenue += premiumPrice;
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
    // Parrainage : un mois Premium offert au parrain, une seule fois.
    final referrer = p.referredBy;
    if (referrer != null && !p.referralRewarded) {
      p.referralRewarded = true;
      referrer.premiumUntil = extendPremium(
        referrer.premiumUntil,
        now,
        referralBonus,
      );
    }
    notifyListeners();
  }

  void rejectPro(Pro p, String reason) {
    if (p.status != VerificationStatus.pending) return;
    p.status = VerificationStatus.rejected;
    p.rejectionReason = reason;
    notifyListeners();
  }

  /// Suspend un pro : ses soins à venir sont annulés et remboursés en totalité.
  void suspendPro(Pro p, String reason) {
    if (p.status != VerificationStatus.verified) return;
    p.status = VerificationStatus.suspended;
    p.rejectionReason = reason;
    for (final b in bookings.where((b) => b.pro == p && _isOpen(b))) {
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
  /// Pros vérifiés proposant ce service dans la commune : les Pro Premium
  /// d'abord, puis les mieux notés.
  List<Pro> prosFor(CareService s, String commune) {
    final list = pros
        .where(
          (p) =>
              p.verified &&
              p.prices.containsKey(s.id) &&
              p.communes.contains(commune),
        )
        .toList();
    list.sort((a, b) {
      final byPremium = (b.isPremium(now) ? 1 : 0) - (a.isPremium(now) ? 1 : 0);
      return byPremium != 0 ? byPremium : b.rating.compareTo(a.rating);
    });
    return list;
  }

  /// Soin confirmé du soignant qui chevauche ce créneau, s'il y en a un.
  Booking? conflictFor(
    Pro pro,
    DateTime start,
    DateTime end, {
    Booking? except,
  }) => bookings
      .where(
        (b) =>
            b != except &&
            b.pro == pro &&
            b.status == BookingStatus.accepted &&
            overlaps(start, end, b.scheduledAt, b.endsAt),
      )
      .firstOrNull;

  // --------------------------------------------------------- réservations
  /// Contrôles communs à toute nouvelle réservation.
  void _checkSlot(
    CareService service,
    Pro pro,
    DateTime at,
    bool prescription, {
    required String commune,
  }) {
    if (!pro.verified || !pro.prices.containsKey(service.id)) {
      throw const BusinessRuleError(
        "Ce soignant n'est pas disponible pour ce soin.",
      );
    }
    if (!pro.communes.contains(commune)) {
      throw BusinessRuleError(
        '${pro.name} n’intervient pas à $commune. Choisissez un soignant '
        'de cette commune.',
      );
    }
    if (at.isBefore(now.add(minNotice))) {
      throw BusinessRuleError(
        'Réservez au moins ${minNotice.inHours} h à l’avance, le temps que '
        'le soignant se déplace.',
      );
    }
    if (at.isAfter(now.add(maxAdvance))) {
      throw BusinessRuleError(
        'On ne réserve pas plus de ${maxAdvance.inDays} jours à l’avance.',
      );
    }
    if (isNight(at) && !pro.nightAvailable) {
      throw BusinessRuleError(
        '${pro.name} ne fait pas de soins de nuit (21 h – 6 h).',
      );
    }
    if (service.needsPrescription && !prescription) {
      throw const BusinessRuleError(
        'Ce soin se fait uniquement sur ordonnance.',
      );
    }
    final end = at.add(Duration(minutes: service.durationMinutes));
    if (conflictFor(pro, at, end) != null) {
      throw BusinessRuleError(
        '${pro.name} a déjà un soin à cette heure. Choisissez un autre '
        'créneau.',
      );
    }
  }

  Booking _create({
    required CareService service,
    required Pro pro,
    required String commune,
    required String address,
    required DateTime scheduledAt,
    required bool hasPrescription,
    required Patient patient,
    required bool mine,
    String note = '',
    DateTime? createdAt,
    Contract? contract,
    int sessionIndex = 0,
    GeoPoint? location,
  }) {
    final b = Booking(
      id: 'R${_nextId++}',
      patient: patient,
      mine: mine,
      service: service,
      pro: pro,
      commune: commune,
      address: address,
      scheduledAt: scheduledAt,
      basePrice: pro.prices[service.id]!,
      hasPrescription: hasPrescription,
      note: note,
      createdAt: createdAt ?? now,
      contract: contract,
      sessionIndex: sessionIndex,
      commissionRate: contract == null
          ? commissionRate
          : contractCommissionRate,
      location: location,
    );
    bookings.insert(0, b);
    contract?.sessions.add(b);
    return b;
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
    bool mine = true,
    GeoPoint? location,
  }) {
    _checkSlot(service, pro, scheduledAt, hasPrescription, commune: commune);
    final b = _create(
      service: service,
      pro: pro,
      commune: commune,
      address: address,
      scheduledAt: scheduledAt,
      hasPrescription: hasPrescription,
      patient: patient ?? patients.first,
      mine: mine,
      note: note,
      location: location,
    );
    notifyListeners();
    return b;
  }

  /// Suivi régulier : plusieurs séances à la même heure, commission réduite.
  Contract bookContract({
    required CareService service,
    required Pro pro,
    required String commune,
    required String address,
    required DateTime firstAt,
    required Frequency frequency,
    required int sessions,
    required bool hasPrescription,
    String note = '',
    Patient? patient,
    GeoPoint? location,
  }) {
    if (sessions < contractMinSessions || sessions > contractMaxSessions) {
      throw const BusinessRuleError(
        'Un suivi compte de $contractMinSessions à $contractMaxSessions '
        'séances.',
      );
    }
    final dates = sessionDates(firstAt, frequency, sessions);
    for (final d in dates) {
      _checkSlot(service, pro, d, hasPrescription, commune: commune);
    }
    final c = Contract(id: 'C${_nextContract++}', frequency: frequency);
    for (var i = 0; i < dates.length; i++) {
      _create(
        service: service,
        pro: pro,
        commune: commune,
        address: address,
        scheduledAt: dates[i],
        hasPrescription: hasPrescription,
        patient: patient ?? patients.first,
        mine: true,
        note: note,
        contract: c,
        sessionIndex: i,
        location: location,
      );
    }
    notifyListeners();
    return c;
  }

  /// Réponse du soignant. Pour un suivi, la réponse vaut pour toutes les
  /// séances.
  void respond(Booking b, {required bool accept}) {
    expireStale();
    final group =
        b.contract?.sessions
            .where((s) => s.status == BookingStatus.pending)
            .toList() ??
        [b];
    if (group.isEmpty || group.any((s) => s.status != BookingStatus.pending)) {
      throw const BusinessRuleError('Cette demande a expiré ou a été traitée.');
    }
    if (accept) {
      for (final s in group) {
        if (conflictFor(s.pro, s.scheduledAt, s.endsAt, except: s) != null) {
          throw BusinessRuleError(
            'Vous avez déjà un soin le ${_shortDate(s.scheduledAt)}. '
            'Refusez cette demande ou libérez ce créneau.',
          );
        }
      }
    }
    for (final s in group) {
      s.status = accept ? BookingStatus.accepted : BookingStatus.refused;
      if (accept) s.acceptedAt = now;
    }
    notifyListeners();
  }

  /// Montant à payer pour ce soin (tout le suivi s'il en fait partie).
  int amountDue(Booking b) => b.contract?.amountDue ?? b.price;

  /// Paiement avec le solde ou en Mobile Money. En production, un paiement
  /// Mobile Money est confirmé par le webhook de l'agrégateur, jamais par
  /// l'app. Renvoie false si le solde ne suffit pas.
  bool pay(Booking b, PaymentMethod method) {
    expireStale();
    if (!b.awaitingPayment) return false;
    final group = b.contract?.awaitingPayment.toList() ?? [b];
    final total = group.fold(0, (s, x) => s + x.price);
    if (method == PaymentMethod.wallet &&
        !wallet.move(
          WalletTxKind.payment,
          -total,
          b.contract == null
              ? '${b.service.name} · ${b.pro.name}'
              : 'Suivi ${b.service.name} (${group.length} séances)',
          at: now,
        )) {
      return false;
    }
    for (final s in group) {
      s.paymentMethod = method;
      s.paidAt = now;
    }
    notifyListeners();
    return true;
  }

  /// Annule les demandes restées sans réponse et les rendez-vous non payés
  /// à temps. Renvoie le nombre de séances annulées.
  int expireStale() {
    var count = 0;
    for (final b in bookings) {
      if (b.status == BookingStatus.pending &&
          !now.isBefore(b.responseDeadline)) {
        _cancel(b, 'Sans réponse du soignant à temps');
        count++;
      } else if (b.awaitingPayment && !now.isBefore(b.paymentDeadline!)) {
        _cancel(b, 'Non payé à temps');
        count++;
      }
    }
    if (count > 0) notifyListeners();
    return count;
  }

  // ---------------------------------------------------------- porte-monnaie
  /// Recharge du solde patient. En production : confirmée par le webhook
  /// de l'agrégateur, jamais par l'app.
  void topUp(int amount, PaymentMethod method) {
    if (method == PaymentMethod.wallet) {
      throw ArgumentError('Rechargez avec un compte Mobile Money.');
    }
    if (amount < minTopUp || amount > maxTopUp) {
      throw ArgumentError('Montant hors limites.');
    }
    wallet.move(
      WalletTxKind.topUp,
      amount,
      'Recharge ${method.label}',
      at: now,
    );
    notifyListeners();
  }

  /// Retrait des gains d'un soignant vers Mobile Money.
  void withdraw(Pro p, int amount, PaymentMethod method) {
    if (method == PaymentMethod.wallet) {
      throw ArgumentError('Choisissez un compte Mobile Money.');
    }
    if (amount < minWithdrawal) {
      throw ArgumentError('Montant minimum : $minWithdrawal FCFA.');
    }
    if (!p.wallet.move(
      WalletTxKind.withdrawal,
      -amount,
      'Retrait ${method.label}',
      at: now,
    )) {
      throw ArgumentError('Solde insuffisant.');
    }
    notifyListeners();
  }

  /// Gains déjà payés par les patients, versés à la fin des soins.
  int upcomingEarnings(Pro p) => bookings
      .where((b) => b.pro == p && b.readyForCare)
      .fold(0, (s, b) => s + b.proEarnings);

  // ------------------------------------------------------------ annulation
  bool _isOpen(Booking b) =>
      b.status == BookingStatus.pending || b.status == BookingStatus.accepted;

  /// Séances concernées par une annulation (tout ce qui reste d'un suivi).
  List<Booking> _cancellable(Booking b) =>
      (b.contract?.sessions ?? [b]).where(_isOpen).toList();

  /// Ce que le patient récupère et ce qui revient au soignant s'il annule
  /// maintenant.
  ({int refund, int fee, int sessions}) cancellationQuote(Booking b) {
    var refund = 0, fee = 0;
    final group = _cancellable(b);
    for (final s in group) {
      if (!s.paid) continue;
      final f = lateCancellationFee(
        price: s.price,
        scheduledAt: s.scheduledAt,
        now: now,
      );
      fee += f;
      refund += s.price - f;
    }
    return (refund: refund, fee: fee, sessions: group.length);
  }

  /// Annulation par le patient : gratuite jusqu'à 2 h avant le soin, sinon la
  /// moitié du prix est versée au soignant.
  void cancel(Booking b, {String reason = 'Annulé par le patient'}) {
    for (final s in _cancellable(b)) {
      final fee = s.paid
          ? lateCancellationFee(
              price: s.price,
              scheduledAt: s.scheduledAt,
              now: now,
            )
          : 0;
      _cancel(
        s,
        fee > 0 ? '$reason moins de 2 h avant le soin' : reason,
        fee: fee,
      );
    }
    notifyListeners();
  }

  /// Annulation par le soignant d'un soin confirmé : le patient est remboursé
  /// en totalité et l'annulation compte pour la fiabilité du soignant.
  void cancelByPro(Booking b, String reason) {
    if (b.status != BookingStatus.accepted) {
      throw const BusinessRuleError('Seul un soin confirmé peut être annulé.');
    }
    if (reason.trim().isEmpty) {
      throw const BusinessRuleError('Indiquez le motif au patient.');
    }
    for (final s in _cancellable(b)) {
      _cancel(s, 'Annulé par le soignant : $reason');
    }
    b.pro.cancellations.add(now);
    notifyListeners();
  }

  /// Les remboursements reviennent sur le solde MyNurse du patient ; une
  /// pénalité d'annulation tardive revient au soignant, commission déduite.
  void _cancel(Booking b, String reason, {int fee = 0}) {
    b.status = BookingStatus.cancelled;
    b.cancelReason = reason;
    if (!b.paid) return;
    b.refunded = true;
    b.cancellationFee = fee;
    if (b.mine && b.price - fee > 0) {
      wallet.move(
        WalletTxKind.refund,
        b.price - fee,
        'Remboursement · ${b.service.name}',
        at: now,
      );
    }
    if (fee > 0) {
      b.pro.wallet.move(
        WalletTxKind.earning,
        fee - (fee * b.commissionRate).round(),
        'Annulation tardive · ${b.patientName}',
        at: now,
      );
    }
  }

  // ------------------------------------------------------------- fin de soin
  /// Peut-on rédiger le compte rendu maintenant ?
  bool canLogCare(Booking b) =>
      b.readyForCare && !now.isBefore(b.careLogOpensAt);

  void submitCareLog(Booking b, CareLog log) {
    if (!b.readyForCare) {
      throw const BusinessRuleError('Ce soin n’est pas confirmé et payé.');
    }
    if (now.isBefore(b.careLogOpensAt)) {
      throw BusinessRuleError(
        'Le compte rendu s’écrit à partir de '
        '${_time(b.careLogOpensAt)}, le jour du soin.',
      );
    }
    b.careLog = log;
    b.status = BookingStatus.done;
    b.receiptNumber =
        'MN-${now.year}-${(_nextReceipt++).toString().padLeft(5, '0')}';
    b.pro.careCount++;
    b.pro.wallet.move(
      WalletTxKind.earning,
      b.proEarnings,
      '${b.service.name} · ${b.patientName}',
      at: now,
    );
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

  /// Soins du patient : à venir d'abord (du plus proche au plus lointain),
  /// puis l'historique (du plus récent au plus ancien).
  List<Booking> get patientBookings {
    final open = bookings.where((b) => b.mine && _isOpen(b)).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final past = bookings.where((b) => b.mine && !_isOpen(b)).toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    return [...open, ...past];
  }

  List<Booking> proBookings(BookingStatus status) =>
      bookings.where((b) => b.pro == currentPro && b.status == status).toList();

  /// Demandes à traiter : une carte par soin ponctuel ou par suivi.
  List<Booking> get proRequests =>
      proBookings(BookingStatus.pending)
          .where((b) => b.contract == null || b == _firstPending(b.contract!))
          .toList();

  Booking? _firstPending(Contract c) =>
      c.sessions.where((s) => s.status == BookingStatus.pending).firstOrNull;

  // ------------------------------------------------------------- chiffres
  /// Statistiques d'un soignant sur les 30 derniers jours.
  ({int cares, int earnings, int acceptance}) proStats(Pro p) {
    final since = now.subtract(const Duration(days: 30));
    final mine = bookings.where(
      (b) => b.pro == p && b.createdAt.isAfter(since),
    );
    final done = mine.where((b) => b.status == BookingStatus.done);
    final answered = mine.where(
      (b) => b.acceptedAt != null || b.status == BookingStatus.refused,
    );
    final accepted = answered.where((b) => b.acceptedAt != null).length;
    return (
      cares: done.length,
      earnings: done.fold(0, (s, b) => s + b.proEarnings),
      acceptance: answered.isEmpty
          ? 100
          : (accepted * 100 / answered.length).round(),
    );
  }

  /// Soins terminés : l'argent a été reversé au pro, commission encaissée.
  Iterable<Booking> get doneBookings =>
      bookings.where((b) => b.status == BookingStatus.done);
  int get grossVolume => doneBookings.fold(0, (s, b) => s + b.price);
  int get commissionTotal =>
      doneBookings.fold(0, (s, b) => s + b.commission) +
      bookings.fold(
        0,
        (s, b) => s + (b.cancellationFee * b.commissionRate).round(),
      );

  /// Argent payé, bloqué en attendant la fin du soin.
  int get escrowTotal =>
      bookings.where((b) => b.readyForCare).fold(0, (s, b) => s + b.price);
  int get refundTotal => bookings.fold(0, (s, b) => s + b.refundAmount);

  /// Argent des clients et des soignants conservé par MyNurse.
  int get clientBalances => wallet.balance;
  int get proBalances => pros.fold(0, (s, p) => s + p.wallet.balance);

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _time(DateTime d) => '${_two(d.hour)}h${_two(d.minute)}';
  static String _shortDate(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)} à ${_time(d)}';

  void _seed() {
    final start = now;
    DateTime at(int days, int hour) =>
        DateTime(start.year, start.month, start.day + days, hour);
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
    final marie = Patient(
      id: 'X3',
      name: 'Marie Kouadio',
      birthYear: 1949,
      history: 'Opérée de la hanche',
    );

    // Une demande ponctuelle, reçue il y a 20 minutes.
    _create(
      service: s('pansement'),
      pro: aya,
      commune: 'Riviera',
      address: 'Riviera Palmeraie, résidence Les Orchidées, villa 12',
      scheduledAt: at(1, 9),
      hasPrescription: false,
      note: 'Pansement après opération du genou.',
      patient: jean,
      mine: false,
      createdAt: start.subtract(const Duration(minutes: 20)),
    );

    // Une demande de suivi : pansement un jour sur deux, 6 séances.
    final contract = Contract(
      id: 'C${_nextContract++}',
      frequency: Frequency.everyOtherDay,
    );
    final dates = sessionDates(at(2, 16), Frequency.everyOtherDay, 6);
    for (var i = 0; i < dates.length; i++) {
      _create(
        service: s('pansement'),
        pro: aya,
        commune: 'Cocody',
        address: 'Cocody Ambassades, rue du Lycée technique',
        scheduledAt: dates[i],
        hasPrescription: false,
        note: 'Ulcère de jambe, pansement complexe.',
        patient: marie,
        mine: false,
        createdAt: start.subtract(const Duration(minutes: 45)),
        contract: contract,
        sessionIndex: i,
      );
    }

    // Un soin confirmé et payé, qui commence maintenant.
    final soon = DateTime(
      start.year,
      start.month,
      start.day,
      start.hour,
      start.minute - start.minute % 15,
    );
    final confirmed = _create(
      service: s('injection'),
      pro: aya,
      commune: 'Cocody',
      address: 'Cocody Angré, 8e tranche, immeuble Sika, 2e étage',
      scheduledAt: soon,
      hasPrescription: true,
      patient: adjoua,
      mine: false,
      createdAt: start.subtract(const Duration(days: 1)),
    );
    confirmed.status = BookingStatus.accepted;
    confirmed.acceptedAt = start.subtract(const Duration(hours: 23));
    confirmed.paymentMethod = PaymentMethod.wave;
    confirmed.paidAt = start.subtract(const Duration(hours: 22));

    // Un soin terminé dans l'historique du patient.
    final past = _create(
      service: s('pansement'),
      pro: aya,
      commune: 'Cocody',
      address: 'Cocody Danga, rue des Jardins',
      scheduledAt: at(-3, 10),
      hasPrescription: false,
      patient: patients.first,
      mine: true,
      createdAt: at(-4, 17),
    );
    wallet.move(
      WalletTxKind.topUp,
      25000,
      'Recharge Orange Money',
      at: at(-5, 19),
    );
    wallet.move(
      WalletTxKind.payment,
      -past.price,
      '${past.service.name} · ${aya.name}',
      at: at(-4, 18),
    );
    past.status = BookingStatus.done;
    past.acceptedAt = at(-4, 17);
    past.paymentMethod = PaymentMethod.wallet;
    past.paidAt = at(-4, 18);
    past.receiptNumber =
        'MN-${start.year}-${(_nextReceipt++).toString().padLeft(5, '0')}';
    aya.wallet.move(
      WalletTxKind.earning,
      5100,
      'Injection · Koffi Yao',
      at: at(-6, 11),
    );
    aya.wallet.move(
      WalletTxKind.earning,
      12750,
      'Perfusion · Marie Kouadio',
      at: at(-5, 15),
    );
    aya.wallet.move(
      WalletTxKind.withdrawal,
      -15000,
      'Retrait Wave',
      at: at(-5, 20),
    );
    aya.wallet.move(
      WalletTxKind.earning,
      past.proEarnings,
      '${past.service.name} · ${past.patientName}',
      at: at(-3, 11),
    );
    past.careLog = CareLog(
      arrivedAt: at(-3, 10),
      leftAt: at(-3, 10).add(const Duration(minutes: 35)),
      acts: 'Nettoyage de la plaie, pansement refait.',
      bloodPressure: '13/8',
      temperature: '37,1',
      pulse: '76',
      observations: 'Plaie propre, cicatrisation normale. Prochain pansement dans 2 jours.',
    );

    // Un soignant Premium dans la démo.
    pros.firstWhere((p) => p.name == 'Ibrahim Traoré').premiumUntil = start.add(
      const Duration(days: 12),
    );

    // Un dossier soignant à vérifier, parrainé par Aya.
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
        referredBy: aya,
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
