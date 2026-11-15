/// Modèles métier MyNurse (V1).
enum UserRole { patient, pro }

enum ProType { infirmier, aideSoignant, medecin, kine, sageFemme }

extension ProTypeLabel on ProType {
  String get label => switch (this) {
        ProType.infirmier => 'Infirmier(ère)',
        ProType.aideSoignant => 'Aide-soignant(e)',
        ProType.medecin => 'Médecin',
        ProType.kine => 'Kinésithérapeute',
        ProType.sageFemme => 'Sage-femme',
      };
}

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
    this.rating = 0,
    this.ratingCount = 0,
    this.careCount = 0,
    this.verified = true,
    this.nightAvailable = false,
  });

  final String id;
  final String name;
  final ProType type;
  final List<String> communes;

  /// Prix fixé par le pro pour chaque service (id du service -> FCFA).
  final Map<String, int> prices;
  final int yearsExperience;
  final String bio;
  double rating;
  int ratingCount;
  int careCount;
  final bool verified;
  final bool nightAvailable;
}

/// Personne soignée : le titulaire du compte ou un proche qu'il gère.
class Patient {
  Patient({
    required this.id,
    required this.name,
    this.relation = 'Moi',
    this.allergies = '',
  });

  final String id;
  final String name;
  final String relation;
  final String allergies;
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
    required this.patientName,
    this.patientAllergies = '',
    this.mine = false,
    required this.service,
    required this.pro,
    required this.commune,
    required this.address,
    required this.scheduledAt,
    required this.basePrice,
    this.hasPrescription = false,
    this.note = '',
    this.status = BookingStatus.pending,
    this.careLog,
    this.rating,
    this.review = '',
  });

  final String id;
  final String patientName;
  final String patientAllergies;

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

  bool get night => isNight(scheduledAt);

  /// Prix payé par le patient (majoration de nuit incluse).
  int get price =>
      night ? (basePrice * (1 + nightSurchargeRate)).round() : basePrice;

  int get commission => (price * commissionRate).round();

  /// Montant reversé au professionnel.
  int get proEarnings => price - commission;
}
