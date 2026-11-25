import 'dart:typed_data';

import 'rules.dart';
import 'location.dart';
import 'rules.dart' as rules;

export 'location.dart' show GeoPoint, DetectedPlace;
export 'rules.dart';

/// Modèles métier MyNurse (V1).
enum UserRole { patient, pro, admin }

enum ProType { infirmier, aideSoignant, medecin, kine, sageFemme }

extension ProTypeLabel on ProType {
  String get label => switch (this) {
    ProType.infirmier => 'Infirmier(ère)',
    ProType.aideSoignant => 'Aide-soignant(e)',
    ProType.medecin => 'Médecin',
    ProType.kine => 'Kinésithérapeute',
    ProType.sageFemme => 'Sage-femme',
  };

  /// Les professions inscrites à un Ordre doivent fournir leur numéro.
  bool get hasOrder =>
      this == ProType.infirmier ||
      this == ProType.medecin ||
      this == ProType.sageFemme;
}

/// Cycle de vérification d'un soignant. Seul « vérifié » reçoit des
/// demandes de soin.
enum VerificationStatus {
  pending,
  incomplete,
  underReview,
  verified,
  expired,
  suspended,
  rejected,
}

extension VerificationStatusLabel on VerificationStatus {
  String get label => switch (this) {
    VerificationStatus.pending => 'En attente',
    VerificationStatus.incomplete => 'Dossier incomplet',
    VerificationStatus.underReview => 'En cours d’examen',
    VerificationStatus.verified => 'Vérifié',
    VerificationStatus.expired => 'Pièce expirée',
    VerificationStatus.suspended => 'Suspendu',
    VerificationStatus.rejected => 'Refusé',
  };

  /// Ce que le soignant doit savoir ou faire, en une phrase.
  String get help => switch (this) {
    VerificationStatus.pending =>
      'Dossier reçu. Un vérificateur MyNurse va l’ouvrir sous 48 h ouvrées.',
    VerificationStatus.incomplete =>
      'Il manque des pièces. Ajoutez-les : l’examen commence dès que le '
          'dossier est complet.',
    VerificationStatus.underReview =>
      'Un vérificateur contrôle vos pièces et votre inscription à l’Ordre. '
          'Il peut vous appeler.',
    VerificationStatus.verified =>
      'Vous recevez les demandes des patients de vos communes.',
    VerificationStatus.expired =>
      'Une pièce obligatoire a expiré : plus aucune demande ne vous est '
          'envoyée. Déposez la nouvelle version.',
    VerificationStatus.suspended =>
      'Compte suspendu par MyNurse. Contactez le support.',
    VerificationStatus.rejected =>
      'Dossier refusé. Corrigez ce qui est indiqué puis renvoyez-le.',
  };

  /// Nom utilisé par la base.
  String get dbName => switch (this) {
    VerificationStatus.underReview => 'under_review',
    _ => name,
  };

  static VerificationStatus fromDb(String v) =>
      VerificationStatus.values.firstWhere(
        (s) => s.dbName == v,
        orElse: () => VerificationStatus.pending,
      );
}

/// Pièces demandées à chaque professionnel avant activation.
enum DocType { diplome, autorisation, ordre, cni, rcPro }

extension DocTypeLabel on DocType {
  String get label => switch (this) {
    DocType.diplome => "Diplôme d'État",
    DocType.autorisation => "Autorisation d'exercer",
    DocType.ordre => "Attestation d'inscription à l'Ordre",
    DocType.cni => "Pièce d'identité (CNI)",
    DocType.rcPro => 'Assurance responsabilité civile pro',
  };
}

List<DocType> requiredDocs(ProType t) => [
  DocType.diplome,
  DocType.autorisation,
  if (t.hasOrder) DocType.ordre,
  DocType.cni,
  DocType.rcPro,
];

enum BookingStatus { pending, accepted, refused, cancelled, done }

extension BookingStatusLabel on BookingStatus {
  String get label => switch (this) {
    BookingStatus.pending => 'En attente',
    BookingStatus.accepted => 'Confirmé',
    BookingStatus.refused => 'Refusé',
    BookingStatus.cancelled => 'Annulé',
    BookingStatus.done => 'Terminé',
  };
}

enum PaymentMethod { wallet, orange, mtn, moov, wave }

extension PaymentMethodLabel on PaymentMethod {
  String get label => switch (this) {
    PaymentMethod.wallet => 'Solde MyNurse',
    PaymentMethod.orange => 'Orange Money',
    PaymentMethod.mtn => 'MTN MoMo',
    PaymentMethod.moov => 'Moov Money',
    PaymentMethod.wave => 'Wave',
  };
}

/// Moyens de paiement externes (recharge, paiement direct, retrait).
final mobileMoneyMethods = PaymentMethod.values
    .where((m) => m != PaymentMethod.wallet)
    .toList();

/// Limites du porte-monnaie.
const minTopUp = 500;
const maxTopUp = 500000;
const minWithdrawal = 1000;

enum WalletTxKind { topUp, payment, refund, earning, withdrawal, subscription }

/// Un mouvement sur un solde MyNurse (montant positif = crédit).
class WalletTx {
  const WalletTx({
    required this.at,
    required this.kind,
    required this.amount,
    required this.label,
  });

  final DateTime at;
  final WalletTxKind kind;
  final int amount;
  final String label;
}

/// Solde et historique d'un compte (patient ou soignant).
class Wallet {
  int balance = 0;
  final List<WalletTx> history = [];

  /// Remplace le contenu par ce que renvoie le serveur.
  void replaceWith(int newBalance, List<WalletTx> txs) {
    balance = newBalance;
    history
      ..clear()
      ..addAll(txs)
      ..sort((a, b) => b.at.compareTo(a.at));
  }

  /// Applique un mouvement ; refuse tout solde négatif.
  bool move(WalletTxKind kind, int amount, String label, {DateTime? at}) {
    if (amount == 0 || balance + amount < 0) return false;
    balance += amount;
    final tx = WalletTx(
      at: at ?? DateTime.now(),
      kind: kind,
      amount: amount,
      label: label,
    );
    // Du plus récent au plus ancien ; à date égale, le dernier en tête.
    final i = history.indexWhere((t) => !t.at.isAfter(tx.at));
    history.insert(i == -1 ? history.length : i, tx);
    return true;
  }
}

/// Communes de lancement.
const communes = [
  'Cocody',
  'Riviera',
  'Bingerville',
  'Marcory',
  'Plateau',
  'Yopougon',
];

class CareService {
  const CareService({
    required this.id,
    required this.name,
    required this.proType,
    required this.minPrice,
    required this.maxPrice,
    this.needsPrescription = false,
    this.durationMinutes = 60,
  });

  final String id;
  final String name;
  final ProType proType;
  final int minPrice;
  final int maxPrice;
  final bool needsPrescription;

  /// Durée du soin, déplacement compris : sert à éviter les doubles
  /// réservations d'un même soignant.
  final int durationMinutes;
}

class Pro {
  Pro({
    required this.id,
    required this.name,
    required this.type,
    required this.communes,
    required this.prices,
    required this.yearsExperience,
    required this.bio,
    this.phone = '',
    this.orderNumber = '',
    this.rating = 0,
    this.ratingCount = 0,
    this.careCount = 0,
    this.status = VerificationStatus.verified,
    this.nightAvailable = false,
    Set<DocType>? documents,
    this.rejectionReason = '',
    this.premiumUntil,
    this.referredBy,
  }) : documents = documents ?? requiredDocs(type).toSet();

  final String id;
  String name;
  final ProType type;
  List<String> communes;

  /// Prix fixé par le pro pour chaque service (id du service -> FCFA).
  Map<String, int> prices;
  int yearsExperience;
  String bio;
  final String phone;
  final String orderNumber;
  double rating;
  int ratingCount;
  int careCount;
  VerificationStatus status;
  bool nightAvailable;

  /// Pièces justificatives déposées.
  final Set<DocType> documents;

  /// Emplacement des fichiers déposés (base en ligne).
  final Map<DocType, String> documentPaths = {};

  /// Date de fin de validité d'une pièce (CNI, assurance, inscription…).
  final Map<DocType, DateTime> documentExpiry = {};

  /// Plages de travail habituelles et jours d'absence.
  final List<AvailabilityRule> availability = [];
  final List<({DateTime from, DateTime to, String reason})> daysOff = [];

  /// Gains disponibles, retirables vers Mobile Money.
  final Wallet wallet = Wallet();
  String rejectionReason;

  /// Fin de l'abonnement Pro Premium (null s'il n'y en a jamais eu).
  DateTime? premiumUntil;

  /// Soignant qui a parrainé celui-ci.
  Pro? referredBy;

  /// Le parrainage n'est récompensé qu'à la première validation.
  bool referralRewarded = false;

  /// Dates des soins confirmés que ce soignant a annulés.
  final List<DateTime> cancellations = [];

  /// Avis publiés par les patients, du plus récent au plus ancien.
  final List<ProReview> reviews = [];

  /// Prix le plus bas proposé (pour la recherche).
  int get fromPrice =>
      prices.values.isEmpty ? 0 : prices.values.reduce((a, b) => a < b ? a : b);

  /// Code à donner aux collègues : un mois Premium offert par filleul vérifié.
  String get referralCode {
    final first = name.replaceFirst('Dr ', '').split(' ').first.toUpperCase();
    // Démo : « pro1 » → AYA-1 ; base en ligne : 6 premiers caractères de l'id.
    final suffix = id.startsWith('pro')
        ? id.replaceAll(RegExp(r'[^0-9]'), '')
        : id.replaceAll('-', '').substring(0, 6).toUpperCase();
    return '$first-$suffix';
  }

  bool get verified => status == VerificationStatus.verified;

  /// Pièces obligatoires expirées à [now].
  List<DocType> expiredDocs(DateTime now) => [
    for (final d in requiredDocs(type))
      if (documentExpiry[d] case final e? when !e.isAfter(now)) d,
  ];

  /// Pièces qui expirent dans les 30 jours.
  List<DocType> expiringDocs(DateTime now) => [
    for (final d in requiredDocs(type))
      if (documentExpiry[d] case final e?
          when e.isAfter(now) && e.difference(now) <= const Duration(days: 30))
        d,
  ];

  /// Statut réel : un dossier vérifié dont une pièce a expiré est « expiré ».
  VerificationStatus statusAt(DateTime now) =>
      status == VerificationStatus.verified && expiredDocs(now).isNotEmpty
      ? VerificationStatus.expired
      : status;

  /// Peut recevoir des demandes de soin (vérifié, pièces à jour).
  bool activeAt(DateTime now) => statusAt(now) == VerificationStatus.verified;

  /// Ce que sa profession l'autorise à faire.
  ScopeOfPractice get scope => ScopeOfPractice.of(type);
  bool isPremium(DateTime now) =>
      premiumUntil != null && premiumUntil!.isAfter(now);
  bool get ratingAlert => ratingCount >= 3 && rating < ratingAlertThreshold;
  int recentCancellations(DateTime now) => cancellations
      .where((d) => now.difference(d) <= proCancellationAlertPeriod)
      .length;
  bool reliabilityAlert(DateTime now) =>
      recentCancellations(now) >= proCancellationAlertCount;
  List<DocType> get missingDocs =>
      requiredDocs(type).where((d) => !documents.contains(d)).toList();
}

/// Compte patient : le titulaire, les proches qu'il gère et son solde.
class PatientAccount {
  PatientAccount({required this.id, required this.phone, this.name = ''});

  final String id;

  /// Numéro de connexion (démo) ; vide pour un compte en ligne.
  final String phone;
  String name;
  final List<Patient> patients = [];
  final Wallet wallet = Wallet();
}

/// Notification affichée sous la cloche.
class AppNotification {
  AppNotification({
    required this.id,
    required this.recipient,
    required this.at,
    required this.title,
    required this.body,
    this.booking,
    this.read = false,
  });

  final String id;

  /// Compte destinataire : compte patient, soignant ou « admin ».
  final String recipient;
  final DateTime at;
  final String title;
  final String body;
  final Booking? booking;
  bool read;
}

/// Ce qu'un proche autorisé peut faire pour un patient.
enum FamilyPermission { viewRecords, manageRecords, bookCare, viewReports }

extension FamilyPermissionLabel on FamilyPermission {
  String get label => switch (this) {
    FamilyPermission.viewReports => 'Suivre les soins',
    FamilyPermission.bookCare => 'Réserver et payer des soins',
    FamilyPermission.viewRecords => 'Lire le carnet de santé',
    FamilyPermission.manageRecords =>
      'Modifier le carnet et ajouter des documents',
  };

  String get help => switch (this) {
    FamilyPermission.viewReports =>
      'Voit les rendez-vous, leur avancement et les comptes rendus.',
    FamilyPermission.bookCare =>
      'Peut demander un soin pour ce patient et le payer avec son solde.',
    FamilyPermission.viewRecords =>
      'Voit les allergies, traitements, antécédents et documents.',
    FamilyPermission.manageRecords =>
      'Peut corriger le carnet et déposer une ordonnance ou un résultat.',
  };

  /// Nom utilisé par la base (patient_members.permissions).
  String get dbName => switch (this) {
    FamilyPermission.viewRecords => 'view_records',
    FamilyPermission.manageRecords => 'manage_records',
    FamilyPermission.bookCare => 'book_care',
    FamilyPermission.viewReports => 'view_reports',
  };
}

/// Un proche autorisé par le titulaire à aider pour un patient.
class FamilyMember {
  FamilyMember({
    required this.id,
    required this.name,
    required this.contact,
    required this.relation,
    required this.permissions,
    required this.addedAt,
    this.accountId,
    this.expiresAt,
  });

  final String id;
  final String name;

  /// Téléphone ou e-mail utilisé pour l'inviter.
  final String contact;

  /// Lien avec le patient (« Fille », « Frère »…).
  final String relation;
  Set<FamilyPermission> permissions;
  final DateTime addedAt;

  /// Compte MyNurse du proche.
  final String? accountId;
  DateTime? expiresAt;
  DateTime? revokedAt;

  bool activeAt(DateTime now) =>
      revokedAt == null && (expiresAt == null || expiresAt!.isAfter(now));
}

/// Type de document médical.
enum MedicalDocKind {
  prescription,
  labResult,
  imaging,
  report,
  certificate,
  other,
}

extension MedicalDocKindLabel on MedicalDocKind {
  String get label => switch (this) {
    MedicalDocKind.prescription => 'Ordonnance',
    MedicalDocKind.labResult => "Résultat d'analyse",
    MedicalDocKind.imaging => 'Imagerie',
    MedicalDocKind.report => 'Compte rendu',
    MedicalDocKind.certificate => 'Certificat',
    MedicalDocKind.other => 'Autre document',
  };

  String get dbName => switch (this) {
    MedicalDocKind.prescription => 'prescription',
    MedicalDocKind.labResult => 'lab_result',
    MedicalDocKind.imaging => 'imaging',
    MedicalDocKind.report => 'report',
    MedicalDocKind.certificate => 'certificate',
    MedicalDocKind.other => 'other',
  };
}

/// Ordonnance, résultat ou compte rendu rangé dans le carnet.
class MedicalDocument {
  MedicalDocument({
    required this.id,
    required this.kind,
    required this.title,
    required this.addedAt,
    required this.addedBy,
    required this.fileName,
    this.bytes,
    this.storagePath,
    this.documentDate,
  });

  final String id;
  final MedicalDocKind kind;
  final String title;
  final DateTime addedAt;

  /// Nom de la personne qui l'a déposé.
  final String addedBy;
  final String fileName;

  /// Contenu (démo) ou emplacement dans le stockage privé (en ligne).
  final Uint8List? bytes;
  final String? storagePath;
  final DateTime? documentDate;

  bool get isImage {
    final n = fileName.toLowerCase();
    return n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png');
  }
}

/// Personne soignée : le titulaire du compte, un proche qu'il gère, ou le
/// proche d'un autre compte qui l'a autorisé à aider.
class Patient {
  Patient({
    required this.id,
    required this.name,
    this.relation = 'Moi',
    this.birthYear,
    this.allergies = '',
    this.history = '',
    this.treatments = '',
    this.bloodGroup = '',
    this.emergencyContact = '',
    this.commune = '',
    this.ownerName = '',
  });

  final String id;
  String name;
  final String relation;
  int? birthYear;
  String allergies;

  /// Antécédents (maladies chroniques, opérations…).
  String history;

  /// Traitements en cours.
  String treatments;
  String bloodGroup;

  /// Personne à prévenir sur place (nom et téléphone).
  String emergencyContact;

  /// Commune habituelle des soins (proche en Côte d'Ivoire).
  String commune;

  /// Titulaire du dossier, quand ce n'est pas le compte connecté.
  String ownerName;

  /// Proches autorisés par le titulaire.
  final List<FamilyMember> members = [];
  final List<MedicalDocument> documents = [];

  int? ageAt(DateTime now) => birthYear == null ? null : now.year - birthYear!;
}

/// Pharmacie, éventuellement de garde.
class Pharmacy {
  const Pharmacy({
    required this.id,
    required this.name,
    required this.commune,
    required this.address,
    this.phone = '',
    this.location,
    this.hours = '',
    this.onDutyFrom,
    this.onDutyUntil,
  });

  final String id;
  final String name;
  final String commune;
  final String address;
  final String phone;
  final GeoPoint? location;

  /// Horaires habituels, en clair.
  final String hours;
  final DateTime? onDutyFrom;
  final DateTime? onDutyUntil;

  bool onDutyAt(DateTime now) =>
      onDutyFrom != null &&
      onDutyUntil != null &&
      !now.isBefore(onDutyFrom!) &&
      now.isBefore(onDutyUntil!);
}

enum ComplaintCategory {
  delay,
  noShow,
  quality,
  behavior,
  billing,
  safety,
  other,
}

extension ComplaintCategoryLabel on ComplaintCategory {
  String get label => switch (this) {
    ComplaintCategory.delay => 'Retard',
    ComplaintCategory.noShow => 'Le soignant n’est pas venu',
    ComplaintCategory.quality => 'Qualité du soin',
    ComplaintCategory.behavior => 'Comportement',
    ComplaintCategory.billing => 'Paiement ou remboursement',
    ComplaintCategory.safety => 'Sécurité du patient',
    ComplaintCategory.other => 'Autre',
  };

  String get dbName => switch (this) {
    ComplaintCategory.noShow => 'no_show',
    _ => name,
  };
}

enum ComplaintStatus { open, inReview, resolved, rejected }

extension ComplaintStatusLabel on ComplaintStatus {
  String get label => switch (this) {
    ComplaintStatus.open => 'Envoyée',
    ComplaintStatus.inReview => 'En cours d’examen',
    ComplaintStatus.resolved => 'Traitée',
    ComplaintStatus.rejected => 'Close sans suite',
  };
}

/// Réclamation envoyée au support MyNurse.
class Complaint {
  Complaint({
    required this.id,
    required this.category,
    required this.description,
    required this.createdAt,
    this.booking,
    this.status = ComplaintStatus.open,
    this.resolution = '',
  });

  final String id;
  final ComplaintCategory category;
  final String description;
  final DateTime createdAt;
  final Booking? booking;
  ComplaintStatus status;
  String resolution;
}

/// Accès d'un soignant au carnet d'un patient : ouvert par une demande de
/// soin, il expire 24 h après le soin et le titulaire peut le retirer.
class RecordAccess {
  RecordAccess({
    required this.id,
    required this.who,
    required this.scope,
    required this.until,
    this.booking,
  });

  final String id;
  final String who;

  /// Ce qui est visible, en clair.
  final String scope;
  final DateTime until;
  final Booking? booking;
}

class CareLog {
  const CareLog({
    required this.arrivedAt,
    required this.leftAt,
    required this.acts,
    this.bloodPressure = '',
    this.temperature = '',
    this.pulse = '',
    this.glycemia = '',
    this.observations = '',
  });

  final DateTime arrivedAt;
  final DateTime leftAt;
  final String acts;
  final String bloodPressure;
  final String temperature;
  final String pulse;
  final String glycemia;
  final String observations;
}

/// Suivi régulier : plusieurs séances réservées, acceptées et payées ensemble.
class Contract {
  Contract({required this.id, required this.frequency});

  final String id;
  final Frequency frequency;
  final List<Booking> sessions = [];

  int get total => sessions.fold(0, (s, b) => s + b.price);

  /// Séances confirmées pas encore payées.
  Iterable<Booking> get awaitingPayment =>
      sessions.where((b) => b.awaitingPayment);
  int get amountDue => awaitingPayment.fold(0, (s, b) => s + b.price);
  int get doneCount =>
      sessions.where((b) => b.status == BookingStatus.done).length;
  DateTime get start => sessions.first.scheduledAt;
  DateTime get end => sessions.last.scheduledAt;
}

class Booking {
  Booking({
    required this.id,
    required this.patient,
    required this.service,
    required this.pro,
    required this.commune,
    required this.address,
    required this.scheduledAt,
    required this.basePrice,
    this.ownerId,
    this.hasPrescription = false,
    this.note = '',
    this.status = BookingStatus.pending,
    this.careLog,
    this.rating,
    this.review = '',
    required this.createdAt,
    this.contract,
    this.sessionIndex = 0,
    this.commissionRate = rules.commissionRate,
    this.location,
  });

  final String id;
  final Patient patient;

  /// Compte patient qui a réservé (null pour les patients extérieurs de la
  /// démonstration).
  final String? ownerId;
  final CareService service;
  final Pro pro;
  final String commune;
  final String address;
  final DateTime scheduledAt;
  final int basePrice;
  final bool hasPrescription;
  final String note;
  BookingStatus status;
  CareLog? careLog;
  int? rating;
  String review;

  final DateTime createdAt;
  DateTime? acceptedAt;

  /// Position GPS du lieu du soin, partagée avec le soignant.
  final GeoPoint? location;

  /// Suivi régulier dont cette séance fait partie.
  final Contract? contract;
  final int sessionIndex;
  final double commissionRate;

  /// Paiement : l'argent est bloqué jusqu'à la fin du soin, puis reversé.
  PaymentMethod? paymentMethod;
  DateTime? paidAt;
  bool refunded = false;
  String cancelReason = '';

  /// Part retenue sur une annulation tardive, versée au soignant.
  int cancellationFee = 0;

  /// Numéro du reçu, attribué quand le soin est terminé.
  String? receiptNumber;

  /// Journal de visite (en route, arrivée, notes).
  final List<JournalEntry> journal = [];

  /// Constantes relevées pendant ce soin.
  final List<VitalSign> vitals = [];

  /// Motif de refus donné par le soignant.
  String refusalReason = '';

  bool get onTheWay =>
      journal.any((j) => j.kind == JournalKind.onTheWay) &&
      !journal.any((j) => j.kind == JournalKind.arrived);
  DateTime? get arrivedAt =>
      journal.where((j) => j.kind == JournalKind.arrived).firstOrNull?.at;

  DateTime get endsAt =>
      scheduledAt.add(Duration(minutes: service.durationMinutes));

  /// Date limite de réponse du soignant.
  DateTime get responseDeadline =>
      earliest(createdAt.add(responseWindow), scheduledAt);

  /// Date limite de paiement après la confirmation.
  DateTime? get paymentDeadline => acceptedAt == null
      ? null
      : earliest(acceptedAt!.add(paymentWindow), scheduledAt);

  /// Le compte rendu peut être rédigé à partir de cette heure.
  DateTime get careLogOpensAt => scheduledAt.subtract(careLogEarliest);

  /// Remboursements accordés par l'équipe (geste, litige), en plus de
  /// celui d'une annulation.
  int adminRefunded = 0;

  /// Montant rendu au patient (annulation et gestes de l'équipe).
  int get refundAmount =>
      (refunded ? price - cancellationFee : 0) + adminRefunded;

  String? get sessionLabel => contract == null
      ? null
      : 'Séance ${sessionIndex + 1}/${contract!.sessions.length} · '
            '${contract!.frequency.label.toLowerCase()}';

  String get patientName => patient.name;
  bool get paid => paidAt != null;
  bool get night => isNight(scheduledAt);

  /// Un soin confirmé et payé peut être réalisé.
  bool get readyForCare => status == BookingStatus.accepted && paid;
  bool get awaitingPayment => status == BookingStatus.accepted && !paid;

  /// Prix payé par le patient (majoration de nuit incluse).
  int get price => careFee(basePrice, scheduledAt);

  int get commission => (price * commissionRate).round();

  /// Montant reversé au professionnel.
  int get proEarnings => price - commission;
}

/// Avis d'un patient sur un soignant.
class ProReview {
  const ProReview({
    required this.rating,
    required this.comment,
    required this.at,
    this.serviceName = '',
    this.author = '',
  });

  final int rating;
  final String comment;
  final DateTime at;
  final String serviceName;

  /// Prénom et initiale (« Awa B. »), jamais le nom complet.
  final String author;
}

/// Ce qui attend le patient ou sa famille (calculé sur l'appareil : visible
/// même sans connexion).
class CareReminder {
  const CareReminder({
    required this.title,
    required this.body,
    this.booking,
    this.urgent = false,
  });

  final String title;
  final String body;
  final Booking? booking;
  final bool urgent;
}

enum SearchSort { recommended, priceAsc, ratingDesc, experienceDesc }

extension SearchSortLabel on SearchSort {
  String get label => switch (this) {
    SearchSort.recommended => 'Recommandés',
    SearchSort.priceAsc => 'Prix croissant',
    SearchSort.ratingDesc => 'Mieux notés',
    SearchSort.experienceDesc => 'Plus expérimentés',
  };
}

/// Critères de recherche d'un soignant. Tous facultatifs sauf la commune.
class SearchFilters {
  const SearchFilters({
    required this.commune,
    this.query = '',
    this.serviceId,
    this.proType,
    this.maxPrice,
    this.minRating = 0,
    this.nightOnly = false,
    this.sort = SearchSort.recommended,
  });

  final String commune;
  final String query;
  final String? serviceId;
  final ProType? proType;
  final int? maxPrice;
  final double minRating;
  final bool nightOnly;
  final SearchSort sort;

  /// Nombre de filtres avancés actifs (pour le badge du bouton Filtres).
  int get activeCount =>
      (proType != null ? 1 : 0) +
      (maxPrice != null ? 1 : 0) +
      (minRating > 0 ? 1 : 0) +
      (nightOnly ? 1 : 0);

  SearchFilters copyWith({
    String? commune,
    String? query,
    String? Function()? serviceId,
    ProType? Function()? proType,
    int? Function()? maxPrice,
    double? minRating,
    bool? nightOnly,
    SearchSort? sort,
  }) => SearchFilters(
    commune: commune ?? this.commune,
    query: query ?? this.query,
    serviceId: serviceId != null ? serviceId() : this.serviceId,
    proType: proType != null ? proType() : this.proType,
    maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
    minRating: minRating ?? this.minRating,
    nightOnly: nightOnly ?? this.nightOnly,
    sort: sort ?? this.sort,
  );

  SearchFilters cleared() =>
      SearchFilters(commune: commune, query: query, serviceId: serviceId);
}

/// Un soignant trouvé, avec le prix du soin cherché (ou son prix le plus bas).
class ProMatch {
  const ProMatch(
    this.pro,
    this.price, {
    this.service,
    this.score,
    this.reasons = const [],
  });

  final Pro pro;
  final int price;
  final CareService? service;

  /// Score de pertinence sur 100 (moteur de mise en relation), si un soin
  /// est choisi.
  final int? score;

  /// Pourquoi ce soignant est proposé (« A déjà soigné Mariam »…).
  final List<String> reasons;
}

/// Plage de travail hebdomadaire (heure d'Abidjan). [weekday] : 1 = lundi.
class AvailabilityRule {
  const AvailabilityRule(this.weekday, this.startMinute, this.endMinute);

  final int weekday;
  final int startMinute;
  final int endMinute;

  bool covers(DateTime start, DateTime end) =>
      start.weekday == weekday &&
      start.day == end.day &&
      start.hour * 60 + start.minute >= startMinute &&
      end.hour * 60 + end.minute <= endMinute;

  String get label {
    String t(int m) =>
        '${m ~/ 60} h${m % 60 == 0 ? '' : (m % 60).toString().padLeft(2, '0')}';
    return '${t(startMinute)} – ${t(endMinute)}';
  }
}

const weekdayNames = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];

/// Constante mesurée pendant un soin.
enum VitalKind {
  bloodPressure,
  heartRate,
  temperature,
  glycemia,
  spo2,
  respiratoryRate,
  weight,
  pain,
}

extension VitalKindInfo on VitalKind {
  String get label => switch (this) {
    VitalKind.bloodPressure => 'Tension',
    VitalKind.heartRate => 'Pouls',
    VitalKind.temperature => 'Température',
    VitalKind.glycemia => 'Glycémie',
    VitalKind.spo2 => 'Saturation O₂',
    VitalKind.respiratoryRate => 'Fréquence respiratoire',
    VitalKind.weight => 'Poids',
    VitalKind.pain => 'Douleur',
  };

  String get unit => switch (this) {
    VitalKind.bloodPressure => 'mmHg',
    VitalKind.heartRate => 'bpm',
    VitalKind.temperature => '°C',
    VitalKind.glycemia => 'g/L',
    VitalKind.spo2 => '%',
    VitalKind.respiratoryRate => '/min',
    VitalKind.weight => 'kg',
    VitalKind.pain => '/10',
  };

  /// Valeurs plausibles (mêmes bornes que la base, 0010).
  (double, double) get range => switch (this) {
    VitalKind.bloodPressure => (40, 300),
    VitalKind.heartRate => (20, 250),
    VitalKind.temperature => (30, 45),
    VitalKind.glycemia => (0.2, 6),
    VitalKind.spo2 => (50, 100),
    VitalKind.respiratoryRate => (4, 80),
    VitalKind.weight => (0.5, 400),
    VitalKind.pain => (0, 10),
  };

  String get dbName => switch (this) {
    VitalKind.bloodPressure => 'blood_pressure',
    VitalKind.heartRate => 'heart_rate',
    VitalKind.temperature => 'temperature',
    VitalKind.glycemia => 'glycemia',
    VitalKind.spo2 => 'spo2',
    VitalKind.respiratoryRate => 'respiratory_rate',
    VitalKind.weight => 'weight',
    VitalKind.pain => 'pain_score',
  };

  /// Seuil d'alerte simple, pour attirer l'œil (pas un diagnostic).
  bool alert(double v, [double? v2]) => switch (this) {
    VitalKind.bloodPressure => v >= 160 || v < 90 || (v2 ?? 80) >= 100,
    VitalKind.heartRate => v > 120 || v < 50,
    VitalKind.temperature => v >= 38.5 || v < 35.5,
    VitalKind.glycemia => v >= 2.5 || v < 0.7,
    VitalKind.spo2 => v < 92,
    VitalKind.respiratoryRate => v > 25 || v < 10,
    VitalKind.weight => false,
    VitalKind.pain => v >= 7,
  };
}

class VitalSign {
  const VitalSign({
    required this.kind,
    required this.value,
    required this.at,
    required this.by,
    this.value2,
    this.booking,
  });

  final VitalKind kind;
  final double value;

  /// Tension diastolique.
  final double? value2;
  final DateTime at;

  /// Nom du soignant ou du proche qui a mesuré.
  final String by;
  final Booking? booking;

  static String _n(double v) {
    final s = v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1);
    return s.replaceAll('.', ',');
  }

  String get display => kind == VitalKind.bloodPressure
      ? '${_n(value)}/${_n(value2 ?? 0)} ${kind.unit}'
      : '${_n(value)} ${kind.unit}';

  bool get alert => kind.alert(value, value2);
}

/// Ce qu'une profession est autorisée à faire sur MyNurse.
class ScopeOfPractice {
  const ScopeOfPractice({
    required this.vitals,
    required this.fullRecord,
    required this.documents,
  });

  /// Constantes qu'elle peut relever.
  final Set<VitalKind> vitals;

  /// Accès au carnet complet (sinon : identité, allergies, traitements).
  final bool fullRecord;

  /// Accès aux ordonnances et résultats.
  final bool documents;

  static ScopeOfPractice of(ProType t) => switch (t) {
    ProType.infirmier ||
    ProType.medecin ||
    ProType.sageFemme => const ScopeOfPractice(
      vitals: {...VitalKind.values},
      fullRecord: true,
      documents: true,
    ),
    ProType.kine => const ScopeOfPractice(
      vitals: {
        VitalKind.bloodPressure,
        VitalKind.heartRate,
        VitalKind.spo2,
        VitalKind.respiratoryRate,
        VitalKind.pain,
      },
      fullRecord: true,
      documents: true,
    ),
    ProType.aideSoignant => const ScopeOfPractice(
      vitals: {
        VitalKind.temperature,
        VitalKind.heartRate,
        VitalKind.weight,
        VitalKind.pain,
      },
      fullRecord: false,
      documents: false,
    ),
  };
}

/// Une ligne du journal de visite, horodatée au moment où elle est écrite.
enum JournalKind { onTheWay, arrived, note, left }

class JournalEntry {
  const JournalEntry(this.kind, this.at, [this.text = '']);

  final JournalKind kind;
  final DateTime at;
  final String text;

  String get label => switch (kind) {
    JournalKind.onTheWay => 'En route',
    JournalKind.arrived => 'Arrivé chez le patient',
    JournalKind.note => text,
    JournalKind.left => 'Départ',
  };
}

enum IncidentCategory {
  patientDanger,
  insecurity,
  adverseEvent,
  equipment,
  addressNotFound,
  other,
}

extension IncidentCategoryLabel on IncidentCategory {
  String get label => switch (this) {
    IncidentCategory.patientDanger => 'Patient en danger',
    IncidentCategory.insecurity => 'Insécurité, agression',
    IncidentCategory.adverseEvent => 'Effet indésirable, erreur de soin',
    IncidentCategory.equipment => 'Matériel manquant ou défectueux',
    IncidentCategory.addressNotFound => 'Adresse introuvable, patient absent',
    IncidentCategory.other => 'Autre',
  };

  bool get urgent =>
      this == IncidentCategory.patientDanger ||
      this == IncidentCategory.insecurity ||
      this == IncidentCategory.adverseEvent;

  String get dbName => switch (this) {
    IncidentCategory.patientDanger => 'patient_danger',
    IncidentCategory.insecurity => 'insecurity',
    IncidentCategory.adverseEvent => 'adverse_event',
    IncidentCategory.equipment => 'equipment',
    IncidentCategory.addressNotFound => 'address_not_found',
    IncidentCategory.other => 'other',
  };
}

/// Incident signalé par un soignant.
class Incident {
  Incident({
    required this.id,
    required this.category,
    required this.description,
    required this.at,
    this.booking,
    this.status = 'Envoyé',
  });

  final String id;
  final IncidentCategory category;
  final String description;
  final DateTime at;
  final Booking? booking;
  String status;
}

/// Ce qu'un soignant voit du dossier d'un patient pour un soin, selon
/// l'autorisation en cours et sa profession.
class PatientChart {
  const PatientChart({
    required this.name,
    required this.scopeLabel,
    this.age,
    this.allergies = '',
    this.treatments = '',
    this.history = '',
    this.bloodGroup = '',
    this.emergencyContact = '',
    this.documents = const [],
    this.vitals = const [],
    this.reports = const [],
  });

  final String name;
  final int? age;

  /// Ce que l'accès permet de voir, en clair.
  final String scopeLabel;
  final String allergies;
  final String treatments;
  final String history;
  final String bloodGroup;
  final String emergencyContact;
  final List<MedicalDocument> documents;
  final List<VitalSign> vitals;
  final List<({DateTime at, String pro, String acts, String observations})>
  reports;
}

/// Permission d'un membre de l'équipe MyNurse (miroir de la base, 0009).
enum AdminPermission {
  verifyPros,
  manageBookings,
  finance,
  support,
  moderate,
  auditRead,
  manageSettings,
  manageStaff,
  medicalBreakGlass,
}

extension AdminPermissionInfo on AdminPermission {
  String get label => switch (this) {
    AdminPermission.verifyPros => 'Vérification des soignants',
    AdminPermission.manageBookings => 'Rendez-vous et suivis',
    AdminPermission.finance => 'Finances',
    AdminPermission.support => 'Support (comptes, réclamations, incidents)',
    AdminPermission.moderate => 'Modération des avis',
    AdminPermission.auditRead => 'Journal d’activité',
    AdminPermission.manageSettings => 'Paramètres, pharmacies, messages',
    AdminPermission.manageStaff => 'Équipe et permissions',
    AdminPermission.medicalBreakGlass => 'Accès d’urgence au dossier médical',
  };

  String get dbName => switch (this) {
    AdminPermission.verifyPros => 'verify_pros',
    AdminPermission.manageBookings => 'manage_bookings',
    AdminPermission.finance => 'finance',
    AdminPermission.support => 'support',
    AdminPermission.moderate => 'moderate',
    AdminPermission.auditRead => 'audit_read',
    AdminPermission.manageSettings => 'manage_settings',
    AdminPermission.manageStaff => 'manage_staff',
    AdminPermission.medicalBreakGlass => 'medical_break_glass',
  };
}

/// Membre de l'équipe d'administration.
class StaffMember {
  StaffMember({
    required this.id,
    required this.name,
    required this.phone,
    required this.permissions,
  });

  final String id;
  final String name;
  final String phone;
  final Set<AdminPermission> permissions;
}

/// Ligne du journal d'activité de l'administration.
class AdminLogEntry {
  const AdminLogEntry({
    required this.at,
    required this.actor,
    required this.action,
    required this.target,
    this.details = '',
    this.patientId,
  });

  final DateTime at;
  final String actor;
  final String action;
  final String target;
  final String details;

  /// Renseigné pour toute action touchant une donnée de santé.
  final String? patientId;
}

/// Période d'analyse [from, to[.
class Period {
  const Period(this.from, this.to, this.label);

  final DateTime from;
  final DateTime to;
  final String label;

  bool contains(DateTime d) => !d.isBefore(from) && d.isBefore(to);

  static Period lastDays(DateTime now, int days) {
    final end = DateTime(now.year, now.month, now.day + 1);
    return Period(
      end.subtract(Duration(days: days)),
      end,
      '$days derniers jours',
    );
  }

  static Period thisMonth(DateTime now) => Period(
    DateTime(now.year, now.month),
    DateTime(now.year, now.month + 1),
    'Ce mois-ci',
  );
}

/// Destinataires d'un message de l'équipe.
enum BroadcastAudience { all, patients, pros }

extension BroadcastAudienceLabel on BroadcastAudience {
  String get label => switch (this) {
    BroadcastAudience.all => 'Tout le monde',
    BroadcastAudience.patients => 'Patients et familles',
    BroadcastAudience.pros => 'Soignants',
  };
}

class Broadcast {
  const Broadcast({
    required this.at,
    required this.audience,
    required this.title,
    required this.body,
    required this.recipients,
    required this.by,
  });

  final DateTime at;
  final BroadcastAudience audience;
  final String title;
  final String body;
  final int recipients;
  final String by;
}

/// Indicateurs du tableau de bord sur une période.
class AdminMetrics {
  const AdminMetrics({
    required this.patients,
    required this.verifiedPros,
    required this.pendingVerifications,
    required this.appointments,
    required this.completed,
    required this.cancelled,
    required this.volume,
    required this.commissions,
    required this.proEarnings,
    required this.responseMinutes,
    required this.satisfaction,
    required this.ratings,
  });

  final int patients;
  final int verifiedPros;
  final int pendingVerifications;
  final int appointments;
  final int completed;
  final int cancelled;
  final int volume;
  final int commissions;
  final int proEarnings;

  /// Délai moyen de réponse des soignants (null si aucune réponse).
  final int? responseMinutes;

  /// Note moyenne des soins notés sur la période (sur 5).
  final double? satisfaction;
  final int ratings;
}
