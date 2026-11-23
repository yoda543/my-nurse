import 'rules.dart';
import 'rules.dart' as rules;

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

enum VerificationStatus { pending, verified, rejected, suspended }

extension VerificationStatusLabel on VerificationStatus {
  String get label => switch (this) {
    VerificationStatus.pending => 'En attente de vérification',
    VerificationStatus.verified => 'Vérifié',
    VerificationStatus.rejected => 'Refusé',
    VerificationStatus.suspended => 'Suspendu',
  };
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

  /// Gains disponibles, retirables vers Mobile Money.
  final Wallet wallet = Wallet();
  String rejectionReason;

  /// Fin de l'abonnement Pro Premium (null s'il n'y en a jamais eu).
  DateTime? premiumUntil;

  /// Soignant qui a parrainé celui-ci.
  final Pro? referredBy;

  /// Le parrainage n'est récompensé qu'à la première validation.
  bool referralRewarded = false;

  /// Dates des soins confirmés que ce soignant a annulés.
  final List<DateTime> cancellations = [];

  /// Code à donner aux collègues : un mois Premium offert par filleul vérifié.
  String get referralCode =>
      '${name.replaceFirst('Dr ', '').split(' ').first.toUpperCase()}-${id.replaceAll(RegExp(r'[^0-9]'), '')}';

  bool get verified => status == VerificationStatus.verified;
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

/// Personne soignée : le titulaire du compte ou un proche qu'il gère.
class Patient {
  Patient({
    required this.id,
    required this.name,
    this.relation = 'Moi',
    this.birthYear,
    this.allergies = '',
    this.history = '',
    this.treatments = '',
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
    this.mine = false,
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
  });

  final String id;
  final Patient patient;

  /// Vrai si la réservation a été faite depuis le compte patient connecté.
  final bool mine;
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

  /// Montant rendu au patient après une annulation.
  int get refundAmount => refunded ? price - cancellationFee : 0;

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
