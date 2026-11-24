import 'package:material_ui/material_ui.dart';

import 'backend/remote.dart';
import 'data/demo_data.dart';
import 'location.dart';
import 'models.dart';

/// Le paiement Mobile Money attend le compte marchand chez l'agrégateur.
const _mobileMoneySoon =
    'Le paiement Mobile Money arrive bientôt. Pour l’instant, payez avec '
    'votre solde MyNurse.';

/// Refus d'une action pour une raison métier, avec un message à afficher.
class BusinessRuleError implements Exception {
  const BusinessRuleError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// État de l'application.
///
/// Sans [remote], tout se passe en mémoire avec des données de démonstration.
/// Avec [remote], chaque action est envoyée à la base Supabase, qui applique
/// les mêmes règles, puis les données sont rechargées depuis le serveur.
class AppState extends ChangeNotifier {
  AppState({
    bool seed = true,
    DateTime Function()? clock,
    Locator? locator,
    this.remote,
  }) : _clock = clock ?? DateTime.now,
       locator = locator ?? DeviceLocator(demoFallback: remote == null) {
    if (seed && remote == null) _seed();
  }

  /// Base en ligne (null en mode démo).
  final RemoteBackend? remote;
  bool get isRemote => remote != null;

  /// Nom du titulaire du compte (base en ligne).
  String fullName = '';
  int _remoteClientBalances = 0;
  int _remoteProBalances = 0;

  final DateTime Function() _clock;

  /// Donne la position du patient.
  final Locator locator;

  /// Dernier lieu détecté, et l'état de la détection en cours.
  DetectedPlace? place;
  bool locating = false;
  String? locationError;
  DateTime get now => _clock();

  /// Comptes de démonstration (code SMS : 123456).
  static const demoPatientPhone = '0700000000';
  static const demoProPhone = '0500000000';
  static const demoAdminPhone = '0100000000';

  final List<CareService> services = [...demoServices];
  late final List<Pro> pros = remote == null ? buildDemoPros() : <Pro>[];
  final List<Booking> bookings = [];

  UserRole? role;
  String commune = communes.first;
  int _nextId = 1;
  int _nextContract = 1;
  int _nextReceipt = 1;

  /// Chiffre d'affaires des abonnements Pro Premium.
  int premiumRevenue = 0;

  /// Comptes patients (démo : plusieurs ; en ligne : celui connecté).
  final List<PatientAccount> accounts = [];

  /// Compte patient en cours.
  PatientAccount? account;
  final _noAccount = PatientAccount(id: '', phone: '');

  /// Le titulaire du compte et les proches qu'il gère.
  List<Patient> get patients => (account ?? _noAccount).patients;

  /// Porte-monnaie du compte patient connecté.
  Wallet get wallet => (account ?? _noAccount).wallet;
  String get patientName => account?.name ?? '';

  /// Notifications de tous les comptes (démo) ou du compte connecté (en ligne).
  final List<AppNotification> notifications = [];
  int _nextNotification = 1;

  /// Soignant connecté (null tant que le dossier n'est pas créé).
  Pro? currentPro;

  /// Numéro utilisé pour se connecter.
  String sessionPhone = '';

  bool get loggedIn => role != null;

  // ------------------------------------------------------------- session
  void login(UserRole r, {String phone = ''}) {
    role = r;
    sessionPhone = phone;
    final byPhone = accounts.where((a) => a.phone == phone).firstOrNull;
    if (r == UserRole.patient && byPhone != null) account = byPhone;
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

  /// Démo : connexion à un compte existant, retrouvé par son numéro.
  void loginDemo(String phone) {
    final patientAccount = accounts.where((a) => a.phone == phone).firstOrNull;
    final pro = phone == demoProPhone
        ? pros.first
        : pros.where((p) => p.phone == phone).firstOrNull;
    if (phone == demoAdminPhone) {
      role = UserRole.admin;
    } else if (patientAccount != null) {
      account = patientAccount;
      role = UserRole.patient;
    } else if (pro != null) {
      currentPro = pro;
      role = UserRole.pro;
    } else {
      throw const BusinessRuleError(
        'Aucun compte avec ce numéro. Vérifiez-le ou créez un compte.',
      );
    }
    sessionPhone = phone;
    expireStale();
    notifyListeners();
  }

  /// Démo : création d'un compte patient ou soignant.
  void signUpDemo(String phone, UserRole r) {
    if (demoAccountExists(phone)) {
      throw const BusinessRuleError(
        'Ce numéro a déjà un compte. Connectez-vous.',
      );
    }
    sessionPhone = phone;
    if (r == UserRole.pro) {
      currentPro = null;
    } else {
      final a = PatientAccount(id: 'A${accounts.length + 1}', phone: phone);
      accounts.add(a);
      account = a;
    }
    role = r;
    notifyListeners();
  }

  void logout() {
    role = null;
    sessionPhone = '';
    currentPro = null;
    if (remote != null) {
      remote!.signOut();
      pros.clear();
      bookings.clear();
      accounts.clear();
      notifications.clear();
      account = null;
      fullName = '';
    }
    notifyListeners();
  }

  // -------------------------------------------------------- notifications
  String? get _me => switch (role) {
    UserRole.patient => account?.id,
    UserRole.pro => currentPro?.id,
    UserRole.admin => 'admin',
    null => null,
  };

  /// Notifications du compte connecté, de la plus récente à la plus ancienne.
  List<AppNotification> get myNotifications {
    final me = _me;
    final indexed = [
      for (var i = 0; i < notifications.length; i++)
        if (notifications[i].recipient == me) (i, notifications[i]),
    ];
    // Plus récente d'abord ; à la même heure, la dernière créée d'abord.
    indexed.sort((a, b) {
      final c = b.$2.at.compareTo(a.$2.at);
      return c != 0 ? c : b.$1.compareTo(a.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  int get unreadCount => myNotifications.where((n) => !n.read).length;

  Future<void> markRead(AppNotification n) async {
    if (n.read) return;
    if (remote != null) await remote!.markRead([n.id]);
    n.read = true;
    notifyListeners();
  }

  /// Démo : ce numéro a-t-il déjà un compte ?
  bool demoAccountExists(String phone) =>
      phone == demoAdminPhone ||
      phone == demoProPhone ||
      accounts.any((a) => a.phone == phone) ||
      pros.any((p) => p.phone == phone);

  Future<void> markAllRead() async {
    final unread = myNotifications.where((n) => !n.read).toList();
    if (unread.isEmpty) return;
    if (remote != null) {
      await remote!.markRead(unread.map((n) => n.id).toList());
    }
    for (final n in unread) {
      n.read = true;
    }
    notifyListeners();
  }

  /// Démo : crée une notification (en ligne, le serveur s'en charge).
  void _notify(
    String? recipient,
    String title,
    String body, {
    Booking? booking,
    DateTime? at,
  }) {
    if (remote != null || recipient == null) return;
    notifications.add(
      AppNotification(
        id: 'N${_nextNotification++}',
        recipient: recipient,
        at: at ?? now,
        title: title,
        body: body,
        booking: booking,
      ),
    );
  }

  static String _money(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return '$b FCFA';
  }

  // --------------------------------------------------- base en ligne
  /// Envoie le code de connexion par e-mail. [wanted] null : connexion à un
  /// compte existant ; sinon création d'un compte de ce type.
  Future<void> sendCode(String email, UserRole? wanted) =>
      remote!.sendCode(email, role: wanted);

  /// Vérifie le code puis ouvre le compte. Le rôle vient de la base.
  Future<void> verifyCode(String email, String code, UserRole? wanted) async {
    await remote!.verifyCode(email, code);
    await _openSession(wanted);
  }

  /// Rouvre la session enregistrée sur le téléphone, s'il y en a une.
  Future<void> restoreSession() async {
    if (remote?.signedIn ?? false) await _openSession(null);
  }

  Future<void> _openSession(UserRole? wanted) async {
    final snap = await remote!.load();
    String? refusal;
    if (wanted == UserRole.admin && snap.role != UserRole.admin) {
      refusal = 'Ce compte n’a pas accès à l’administration.';
    } else if (wanted == UserRole.pro && snap.role == UserRole.patient) {
      refusal =
          'Cette adresse est déjà celle d’un compte patient. Utilisez une '
          'autre adresse pour votre compte soignant.';
    } else if (wanted == UserRole.patient && snap.role == UserRole.pro) {
      refusal =
          'Cette adresse est celle d’un compte soignant. Utilisez « Je suis '
          'professionnel de santé ».';
    }
    if (refusal != null) {
      await remote!.signOut();
      throw BusinessRuleError(refusal);
    }
    _apply(snap);
    role = snap.role;
    notifyListeners();
  }

  /// Recharge les données depuis le serveur.
  Future<void> refresh() async {
    final r = remote;
    if (r == null || !r.signedIn || role == null) return;
    _apply(await r.load());
    notifyListeners();
  }

  void _apply(RemoteSnapshot s) {
    services
      ..clear()
      ..addAll(s.services);
    pros
      ..clear()
      ..addAll(s.pros);
    final uid = remote!.userId!;
    if (account?.id != uid) {
      accounts
        ..clear()
        ..add(account = PatientAccount(id: uid, phone: ''));
    }
    account!.name = s.fullName;
    patients
      ..clear()
      ..addAll(s.myPatients);
    notifications
      ..clear()
      ..addAll(s.notifications);
    bookings
      ..clear()
      ..addAll(s.bookings);
    fullName = s.fullName;
    currentPro = pros.where((p) => p.id == remote!.userId).firstOrNull;
    wallet.replaceWith(s.walletBalance, s.walletHistory);
    _remoteClientBalances = s.clientBalances;
    _remoteProBalances = s.proBalances;
    premiumRevenue = s.premiumRevenue;
  }

  /// Un nouveau patient doit d'abord donner son nom.
  bool get needsProfile => role == UserRole.patient && patients.isEmpty;

  Future<void> completeProfile(String name) async {
    if (remote != null) {
      await remote!.completeProfile(name);
      return refresh();
    }
    final a = account!;
    a.name = name;
    a.patients.add(Patient(id: '${a.id}-P0', name: name));
    _notify(
      a.id,
      'Bienvenue sur MyNurse',
      'Rechargez votre solde, puis réservez un soignant vérifié près de chez '
          'vous.',
    );
    notifyListeners();
  }

  /// Exécute une action en ligne puis recharge les données.
  Future<void> _online(Future<void> Function(RemoteBackend r) action) async {
    await action(remote!);
    await refresh();
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

  Future<Pro> registerPro({
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
    Map<DocType, PickedFile> files = const {},
  }) async {
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
    if (remote != null) {
      final missing = requiredDocs(type).where((d) => !files.containsKey(d));
      if (missing.isNotEmpty) {
        throw BusinessRuleError(
          'Ajoutez : ${missing.map((d) => d.label).join(', ')}.',
        );
      }
      await _online(
        (r) => r.registerPro(
          name: name,
          type: type,
          communes: communes,
          prices: prices,
          yearsExperience: yearsExperience,
          bio: bio,
          orderNumber: orderNumber,
          nightAvailable: nightAvailable,
          files: files,
          referredBy: referrer?.id,
        ),
      );
      return currentPro!;
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
    _notify(
      'admin',
      'Nouveau dossier à vérifier',
      '${p.name}, ${p.type.label} · ${p.communes.join(', ')}.',
    );
    notifyListeners();
    return p;
  }

  /// Après un refus, le pro complète son dossier et le renvoie.
  Future<void> resubmitPro(
    Pro p,
    Set<DocType> documents, {
    Map<DocType, PickedFile> files = const {},
  }) async {
    if (p.status != VerificationStatus.rejected) return;
    if (remote != null) {
      return _online((r) async {
        if (files.isNotEmpty) await r.uploadDocuments(files);
        await r.resubmitPro();
      });
    }
    p.documents
      ..clear()
      ..addAll(documents);
    p.rejectionReason = '';
    p.status = VerificationStatus.pending;
    _notify('admin', 'Dossier renvoyé', '${p.name} a complété son dossier.');
    notifyListeners();
  }

  Future<void> updateProAvailability(
    Pro p, {
    required List<String> communes,
    required bool nightAvailable,
  }) async {
    if (communes.isEmpty) return;
    if (remote != null) {
      return _online((r) => r.updateAvailability(communes, nightAvailable));
    }
    p.communes = communes;
    p.nightAvailable = nightAvailable;
    notifyListeners();
  }

  // ------------------------------------------------------------- Premium
  /// Abonnement Pro Premium, payé avec le solde du soignant.
  Future<void> subscribePremium(Pro p) async {
    if (!p.verified) {
      throw const BusinessRuleError('Réservé aux soignants vérifiés.');
    }
    if (remote != null) return _online((r) => r.subscribePremium());
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
    _notify(
      p.id,
      'Pro Premium activé',
      'Vous êtes mis en avant jusqu’au ${_shortDate(p.premiumUntil!)}.',
    );
    notifyListeners();
  }

  // ------------------------------------------------------------ administration
  List<Pro> prosWithStatus(VerificationStatus s) =>
      pros.where((p) => p.status == s).toList();

  Future<void> verifyPro(Pro p) async {
    if (p.status != VerificationStatus.pending &&
        p.status != VerificationStatus.suspended) {
      return;
    }
    if (p.missingDocs.isNotEmpty) {
      throw StateError('Dossier incomplet.');
    }
    if (remote != null) return _online((r) => r.verifyPro(p.id));
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
      _notify(
        referrer.id,
        'Parrainage : ${referralBonus.inDays} jours de Premium offerts',
        '${p.name} est maintenant vérifié(e). Merci de faire connaître '
            'MyNurse.',
      );
    }
    _notify(
      p.id,
      'Votre compte est vérifié',
      'Vous apparaissez dans les recherches des patients de vos communes.',
    );
    notifyListeners();
  }

  Future<void> rejectPro(Pro p, String reason) async {
    if (p.status != VerificationStatus.pending) return;
    if (remote != null) return _online((r) => r.rejectPro(p.id, reason));
    p.status = VerificationStatus.rejected;
    p.rejectionReason = reason;
    _notify(p.id, 'Dossier à compléter', reason);
    notifyListeners();
  }

  /// Suspend un pro : ses soins à venir sont annulés et remboursés en totalité.
  Future<void> suspendPro(Pro p, String reason) async {
    if (p.status != VerificationStatus.verified) return;
    if (remote != null) return _online((r) => r.suspendPro(p.id, reason));
    p.status = VerificationStatus.suspended;
    p.rejectionReason = reason;
    for (final b in bookings.where((b) => b.pro == p && _isOpen(b))) {
      _cancel(b, 'Soignant suspendu par MyNurse');
      if (b.contract == null || b == b.contract!.sessions.first) {
        _notify(
          b.ownerId,
          'Soin annulé',
          '${p.name} n’est plus disponible sur MyNurse. '
              '${b.paid ? 'Vous êtes remboursé sur votre solde. ' : ''}'
              'Choisissez un autre soignant.',
          booking: b,
        );
      }
    }
    _notify(p.id, 'Compte suspendu', reason);
    notifyListeners();
  }

  // ------------------------------------------------------------- patients
  Future<Patient> addPatient({
    required String name,
    required String relation,
    String allergies = '',
    int? birthYear,
  }) async {
    if (remote != null) {
      final id = await remote!.addPatient(
        name: name,
        relation: relation,
        allergies: allergies,
        birthYear: birthYear,
      );
      await refresh();
      return patients.firstWhere((p) => p.id == id);
    }
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

  Future<void> updateHealthRecord(
    Patient p, {
    required String allergies,
    required String history,
    required String treatments,
  }) async {
    if (remote != null) {
      return _online(
        (r) => r.updatePatient(
          p.id,
          allergies: allergies,
          history: history,
          treatments: treatments,
        ),
      );
    }
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
      ownerId: mine ? account?.id : null,
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

  Future<Booking> book({
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
  }) async {
    _checkSlot(service, pro, scheduledAt, hasPrescription, commune: commune);
    if (remote != null) {
      final id = await remote!.book(
        patientId: (patient ?? patients.first).id,
        proId: pro.id,
        serviceId: service.id,
        commune: commune,
        address: address,
        at: scheduledAt,
        hasPrescription: hasPrescription,
        note: note,
        location: location,
      );
      await refresh();
      return bookings.firstWhere((b) => b.id == id);
    }
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
    _notify(
      pro.id,
      'Nouvelle demande de soin',
      '${service.name} pour ${b.patientName}, le ${_shortDate(scheduledAt)}. '
          'Répondez avant ${_time(b.responseDeadline)}.',
      booking: b,
    );
    notifyListeners();
    return b;
  }

  /// Suivi régulier : plusieurs séances à la même heure, commission réduite.
  Future<Contract> bookContract({
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
  }) async {
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
    if (remote != null) {
      final id = await remote!.bookContract(
        patientId: (patient ?? patients.first).id,
        proId: pro.id,
        serviceId: service.id,
        commune: commune,
        address: address,
        dates: dates,
        frequency: frequency,
        hasPrescription: hasPrescription,
        note: note,
        location: location,
      );
      await refresh();
      return bookings.firstWhere((b) => b.contract?.id == id).contract!;
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
    _notify(
      pro.id,
      'Nouveau suivi demandé',
      '${service.name} pour ${c.sessions.first.patientName} : $sessions '
          'séances, ${frequency.label.toLowerCase()}, à partir du '
          '${_shortDate(firstAt)}.',
      booking: c.sessions.first,
    );
    notifyListeners();
    return c;
  }

  /// Réponse du soignant. Pour un suivi, la réponse vaut pour toutes les
  /// séances.
  Future<void> respond(Booking b, {required bool accept}) async {
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
    if (remote != null) return _online((r) => r.respond(b.id, accept));
    for (final s in group) {
      s.status = accept ? BookingStatus.accepted : BookingStatus.refused;
      if (accept) s.acceptedAt = now;
    }
    final first = group.first;
    _notify(
      first.ownerId,
      accept
          ? '${b.pro.name} a confirmé votre soin'
          : '${b.pro.name} n’est pas disponible',
      accept
          ? 'Payez ${_money(amountDue(first))} avant '
                '${_time(first.paymentDeadline!)} pour valider le rendez-vous.'
          : 'Choisissez un autre soignant pour ${first.service.name}.',
      booking: first,
    );
    notifyListeners();
  }

  /// Montant à payer pour ce soin (tout le suivi s'il en fait partie).
  int amountDue(Booking b) => b.contract?.amountDue ?? b.price;

  /// Paiement avec le solde ou en Mobile Money. En production, un paiement
  /// Mobile Money est confirmé par le webhook de l'agrégateur, jamais par
  /// l'app. Renvoie false si le solde ne suffit pas.
  Future<bool> pay(Booking b, PaymentMethod method) async {
    expireStale();
    if (!b.awaitingPayment) return false;
    final group = b.contract?.awaitingPayment.toList() ?? [b];
    final total = group.fold(0, (s, x) => s + x.price);
    if (remote != null) {
      if (method != PaymentMethod.wallet) {
        throw const BusinessRuleError(_mobileMoneySoon);
      }
      if (wallet.balance < total) return false;
      await _online((r) => r.payWithWallet(b.id));
      return true;
    }
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
    _notify(
      b.pro.id,
      'Paiement reçu',
      '${b.patientName} a payé '
          '${b.contract == null ? b.service.name : 'le suivi (${group.length} séances)'}. '
          'Vous pouvez vous déplacer le ${_shortDate(group.first.scheduledAt)}.',
      booking: group.first,
    );
    notifyListeners();
    return true;
  }

  /// Annule les demandes restées sans réponse et les rendez-vous non payés
  /// à temps. Renvoie le nombre de séances annulées.
  int expireStale() {
    // En ligne, le serveur s'en charge chaque minute.
    if (remote != null) return 0;
    var count = 0;
    for (final b in bookings) {
      if (b.status == BookingStatus.pending &&
          !now.isBefore(b.responseDeadline)) {
        _cancel(b, 'Sans réponse du soignant à temps');
        count++;
        if (b.contract == null || b == b.contract!.sessions.first) {
          _notify(
            b.ownerId,
            'Demande sans réponse',
            '${b.pro.name} n’a pas répondu à temps. Choisissez un autre '
                'soignant pour ${b.service.name}.',
            booking: b,
          );
          _notify(
            b.pro.id,
            'Demande expirée',
            '${b.service.name} pour ${b.patientName} : délai de réponse '
                'dépassé.',
            booking: b,
          );
        }
      } else if (b.awaitingPayment && !now.isBefore(b.paymentDeadline!)) {
        _cancel(b, 'Non payé à temps');
        count++;
        if (b.contract == null || b == b.contract!.sessions.first) {
          _notify(
            b.ownerId,
            'Rendez-vous annulé',
            '${b.service.name} avec ${b.pro.name} n’a pas été payé à temps.',
            booking: b,
          );
          _notify(
            b.pro.id,
            'Rendez-vous annulé',
            '${b.patientName} n’a pas payé à temps : ne vous déplacez pas.',
            booking: b,
          );
        }
      }
    }
    if (count > 0) notifyListeners();
    return count;
  }

  // ---------------------------------------------------------- porte-monnaie
  /// Recharge du solde patient. En production : confirmée par le webhook
  /// de l'agrégateur, jamais par l'app.
  Future<void> topUp(int amount, PaymentMethod method) async {
    if (remote != null) throw const BusinessRuleError(_mobileMoneySoon);
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
    _notify(
      account?.id,
      'Recharge confirmée',
      '${_money(amount)} ajoutés à votre solde. Nouveau solde : '
          '${_money(wallet.balance)}.',
    );
    notifyListeners();
  }

  /// Retrait des gains d'un soignant vers Mobile Money.
  Future<void> withdraw(
    Pro p,
    int amount,
    PaymentMethod method, {
    String phone = '',
  }) async {
    if (method == PaymentMethod.wallet) {
      throw ArgumentError('Choisissez un compte Mobile Money.');
    }
    if (amount < minWithdrawal) {
      throw ArgumentError('Montant minimum : $minWithdrawal FCFA.');
    }
    if (remote != null) {
      if (amount > p.wallet.balance) throw ArgumentError('Solde insuffisant.');
      return _online((r) => r.withdraw(amount, method, phone));
    }
    if (!p.wallet.move(
      WalletTxKind.withdrawal,
      -amount,
      'Retrait ${method.label}',
      at: now,
    )) {
      throw ArgumentError('Solde insuffisant.');
    }
    _notify(
      p.id,
      'Retrait envoyé',
      '${_money(amount)} vers votre compte ${method.label}.',
    );
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
  Future<void> cancel(
    Booking b, {
    String reason = 'Annulé par le patient',
  }) async {
    if (remote != null) return _online((r) => r.cancel(b.id));
    final group = _cancellable(b);
    var fees = 0;
    for (final s in group) {
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
      fees += fee;
    }
    if (group.isNotEmpty) {
      _notify(
        b.pro.id,
        'Soin annulé par le patient',
        '${b.patientName} a annulé '
            '${group.length > 1 ? 'le suivi (${group.length} séances restantes)' : '${b.service.name} du ${_shortDate(group.first.scheduledAt)}'}.'
            '${fees > 0 ? ' Dédommagement de ${_money(fees - (fees * b.commissionRate).round())} versé sur votre solde.' : ''}',
        booking: group.first,
      );
    }
    notifyListeners();
  }

  /// Annulation par le soignant d'un soin confirmé : le patient est remboursé
  /// en totalité et l'annulation compte pour la fiabilité du soignant.
  Future<void> cancelByPro(Booking b, String reason) async {
    if (b.status != BookingStatus.accepted) {
      throw const BusinessRuleError('Seul un soin confirmé peut être annulé.');
    }
    if (reason.trim().isEmpty) {
      throw const BusinessRuleError('Indiquez le motif au patient.');
    }
    if (remote != null) return _online((r) => r.cancelByPro(b.id, reason));
    for (final s in _cancellable(b)) {
      _cancel(s, 'Annulé par le soignant : $reason');
    }
    b.pro.cancellations.add(now);
    _notify(
      b.ownerId,
      'Soin annulé par le soignant',
      '${b.pro.name} : $reason. '
          '${b.paid ? 'Vous êtes remboursé sur votre solde MyNurse. ' : ''}'
          'Choisissez un autre soignant.',
      booking: b,
    );
    if (b.pro.recentCancellations(now) == proCancellationAlertCount) {
      _notify(
        'admin',
        'Alerte fiabilité',
        '${b.pro.name} a annulé $proCancellationAlertCount soins confirmés en '
            '${proCancellationAlertPeriod.inDays} jours.',
      );
    }
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
    final owner = _ownerOf(b);
    if (owner != null && b.price - fee > 0) {
      owner.wallet.move(
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

  Future<void> submitCareLog(Booking b, CareLog log) async {
    if (!b.readyForCare) {
      throw const BusinessRuleError('Ce soin n’est pas confirmé et payé.');
    }
    if (now.isBefore(b.careLogOpensAt)) {
      throw BusinessRuleError(
        'Le compte rendu s’écrit à partir de '
        '${_time(b.careLogOpensAt)}, le jour du soin.',
      );
    }
    if (remote != null) return _online((r) => r.submitCareLog(b.id, log));
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
    _notify(
      b.ownerId,
      'Compte rendu disponible',
      '${b.pro.name} a terminé ${b.service.name} pour ${b.patientName}. '
          'Pensez à noter le soin.',
      booking: b,
    );
    _notify(
      b.pro.id,
      'Paiement versé',
      '${_money(b.proEarnings)} ajoutés à votre solde pour '
          '${b.service.name}.',
      booking: b,
    );
    notifyListeners();
  }

  Future<void> rate(Booking b, int stars, String review) async {
    if (b.status != BookingStatus.done || b.rating != null) return;
    if (stars < 1 || stars > 5) return;
    if (remote != null) {
      return _online((r) => r.rate(b.id, b.pro.id, stars, review));
    }
    b.rating = stars;
    b.review = review;
    final p = b.pro;
    p.rating = (p.rating * p.ratingCount + stars) / (p.ratingCount + 1);
    p.ratingCount++;
    _notify(
      p.id,
      'Nouvelle note : $stars/5',
      review.isEmpty
          ? '${b.service.name} pour ${b.patientName}.'
          : '« $review »',
      booking: b,
    );
    notifyListeners();
  }

  bool _isMine(Booking b) => b.ownerId != null && b.ownerId == account?.id;

  PatientAccount? _ownerOf(Booking b) =>
      accounts.where((a) => a.id == b.ownerId).firstOrNull;

  /// Soins du patient : à venir d'abord (du plus proche au plus lointain),
  /// puis l'historique (du plus récent au plus ancien).
  List<Booking> get patientBookings {
    final open = bookings.where((b) => _isMine(b) && _isOpen(b)).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final past = bookings.where((b) => _isMine(b) && !_isOpen(b)).toList()
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
  int get clientBalances => isRemote ? _remoteClientBalances : wallet.balance;
  int get proBalances => isRemote
      ? _remoteProBalances
      : pros.fold(0, (s, p) => s + p.wallet.balance);

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _time(DateTime d) => '${_two(d.hour)}h${_two(d.minute)}';
  static String _shortDate(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)} à ${_time(d)}';

  void _seed() {
    final start = now;
    DateTime at(int days, int hour) =>
        DateTime(start.year, start.month, start.day + days, hour);
    final aya = pros.first;
    final awa = PatientAccount(
      id: 'A1',
      phone: demoPatientPhone,
      name: 'Awa Bamba',
    );
    awa.patients.add(Patient(id: 'P0', name: 'Awa Bamba', birthYear: 1988));
    accounts.add(awa);
    account = awa;
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

    // Notifications de départ.
    final requests = bookings.where((b) => b.status == BookingStatus.pending);
    final single = requests.firstWhere((b) => b.contract == null);
    _notify(
      aya.id,
      'Paiement reçu',
      '${confirmed.patientName} a payé ${confirmed.service.name}. Vous pouvez '
          'vous déplacer.',
      booking: confirmed,
      at: start.subtract(const Duration(hours: 22)),
    );
    _notify(
      aya.id,
      'Nouveau suivi demandé',
      'Pansement pour Marie Kouadio : 6 séances, un jour sur deux.',
      booking: contract.sessions.first,
      at: start.subtract(const Duration(minutes: 45)),
    );
    _notify(
      aya.id,
      'Nouvelle demande de soin',
      '${single.service.name} pour ${single.patientName}, le '
          '${_shortDate(single.scheduledAt)}.',
      booking: single,
      at: start.subtract(const Duration(minutes: 20)),
    );
    _notify(
      awa.id,
      'Recharge confirmée',
      '25 000 FCFA ajoutés à votre solde.',
      at: at(-5, 19),
    );
    _notify(
      awa.id,
      'Compte rendu disponible',
      'Aya Kouamé a terminé votre pansement. Pensez à noter le soin.',
      booking: past,
      at: at(-3, 11),
    );
    _notify(
      'admin',
      'Nouveau dossier à vérifier',
      'Bernadette Ouattara, Infirmier(ère) · Marcory, Plateau.',
      at: start.subtract(const Duration(hours: 3)),
    );
    for (final n in notifications) {
      // Les plus anciennes sont déjà lues, sauf le compte rendu pas encore noté.
      n.read =
          now.difference(n.at) > const Duration(hours: 12) && n.booking != past;
    }
  }
}

/// Donne accès à [AppState] dans l'arbre de widgets.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
