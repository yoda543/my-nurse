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

enum PaymentMethod { orange, mtn, moov, wave }

extension PaymentMethodLabel on PaymentMethod {
  String get label => switch (this) {
    PaymentMethod.orange => 'Orange Money',
    PaymentMethod.mtn => 'MTN MoMo',
    PaymentMethod.moov => 'Moov Money',
    PaymentMethod.wave => 'Wave',
  };
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

/// Règles tarifaires de la plateforme.
const commissionRate = 0.15;
const nightSurchargeRate = 0.5;

/// Un pro dont la note passe sous ce seuil est signalé à l'administration.
const ratingAlertThreshold = 4.0;

/// Un soin est « de nuit » entre 21 h et 6 h.
bool isNight(DateTime d) => d.hour >= 21 || d.hour < 6;

class CareService {
  const CareService({
    required this.id,
    required this.name,
    required this.proType,
    required this.minPrice,
    required this.maxPrice,
    this.needsPrescription = false,
  });

  final String id;
  final String name;
  final ProType proType;
  final int minPrice;
  final int maxPrice;
  final bool needsPrescription;
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
  String rejectionReason;

  bool get verified => status == VerificationStatus.verified;
  bool get ratingAlert => ratingCount >= 3 && rating < ratingAlertThreshold;
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

  /// Paiement : l'argent est bloqué jusqu'à la fin du soin, puis reversé.
  PaymentMethod? paymentMethod;
  DateTime? paidAt;
  bool refunded = false;
  String cancelReason = '';

  String get patientName => patient.name;
  bool get paid => paidAt != null;
  bool get night => isNight(scheduledAt);

  /// Un soin confirmé et payé peut être réalisé.
  bool get readyForCare => status == BookingStatus.accepted && paid;
  bool get awaitingPayment => status == BookingStatus.accepted && !paid;

  /// Prix payé par le patient (majoration de nuit incluse).
  int get price =>
      night ? (basePrice * (1 + nightSurchargeRate)).round() : basePrice;

  int get commission => (price * commissionRate).round();

  /// Montant reversé au professionnel.
  int get proEarnings => price - commission;
}
