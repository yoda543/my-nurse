import '../models.dart';

/// Données de démonstration : elles seront remplacées par Supabase.
const demoServices = <CareService>[
  CareService(
    id: 'injection',
    name: 'Injection (IM, sous-cutanée, IV)',
    proType: ProType.infirmier,
    minPrice: 5000,
    maxPrice: 8000,
    needsPrescription: true,
    durationMinutes: 30,
  ),
  CareService(
    id: 'perfusion',
    name: 'Perfusion (pose + surveillance)',
    proType: ProType.infirmier,
    minPrice: 15000,
    maxPrice: 25000,
    needsPrescription: true,
    durationMinutes: 120,
  ),
  CareService(
    id: 'pansement',
    name: 'Pansement simple ou complexe',
    proType: ProType.infirmier,
    minPrice: 5000,
    maxPrice: 15000,
    durationMinutes: 45,
  ),
  CareService(
    id: 'sonde',
    name: 'Pose ou changement de sonde urinaire',
    proType: ProType.infirmier,
    minPrice: 10000,
    maxPrice: 15000,
    needsPrescription: true,
    durationMinutes: 45,
  ),
  CareService(
    id: 'toilette',
    name: 'Toilette au lit, aide à la mobilisation',
    proType: ProType.aideSoignant,
    minPrice: 5000,
    maxPrice: 12000,
    durationMinutes: 60,
  ),
  CareService(
    id: 'consultation',
    name: 'Consultation à domicile',
    proType: ProType.medecin,
    minPrice: 15000,
    maxPrice: 30000,
    durationMinutes: 45,
  ),
  CareService(
    id: 'kine',
    name: 'Séance de kinésithérapie à domicile',
    proType: ProType.kine,
    minPrice: 10000,
    maxPrice: 15000,
    needsPrescription: true,
    durationMinutes: 60,
  ),
  CareService(
    id: 'suivi_grossesse',
    name: 'Suivi de grossesse à domicile',
    proType: ProType.sageFemme,
    minPrice: 10000,
    maxPrice: 15000,
    durationMinutes: 60,
  ),
];

List<Pro> buildDemoPros() => [
  Pro(
    id: 'pro1',
    name: 'Aya Kouamé',
    type: ProType.infirmier,
    communes: ['Cocody', 'Riviera', 'Bingerville'],
    prices: {
      'injection': 6000,
      'perfusion': 18000,
      'pansement': 8000,
      'sonde': 12000,
    },
    yearsExperience: 8,
    bio: "Infirmière diplômée d'État, 8 ans en chirurgie au CHU de Cocody. Pansements complexes et suivi post-opératoire.",
    rating: 4.9,
    ratingCount: 41,
    careCount: 132,
    nightAvailable: true,
  ),
  Pro(
    id: 'pro2',
    name: 'Ibrahim Traoré',
    type: ProType.infirmier,
    communes: ['Marcory', 'Plateau', 'Cocody'],
    prices: {'injection': 5000, 'perfusion': 15000, 'pansement': 6000},
    yearsExperience: 5,
    bio: "Infirmier diplômé d'État. Suivi des patients diabétiques et hypertendus.",
    rating: 4.7,
    ratingCount: 23,
    careCount: 64,
  ),
  Pro(
    id: 'pro3',
    name: 'Mariam Koné',
    type: ProType.infirmier,
    communes: ['Yopougon'],
    prices: {'injection': 5000, 'pansement': 5000, 'sonde': 10000},
    yearsExperience: 12,
    bio: 'Infirmière, 12 ans en médecine générale. Disponible la nuit et le week-end.',
    rating: 4.8,
    ratingCount: 35,
    careCount: 98,
    nightAvailable: true,
  ),
  Pro(
    id: 'pro4',
    name: 'Estelle Yao',
    type: ProType.aideSoignant,
    communes: ['Cocody', 'Riviera', 'Bingerville'],
    prices: {'toilette': 7000},
    yearsExperience: 6,
    bio: 'Aide-soignante, accompagnement des personnes âgées et dépendantes.',
    rating: 4.8,
    ratingCount: 19,
    careCount: 210,
  ),
  Pro(
    id: 'pro5',
    name: 'Dr Serge Aka',
    type: ProType.medecin,
    communes: ['Cocody', 'Riviera', 'Plateau', 'Marcory'],
    prices: {'consultation': 20000},
    yearsExperience: 10,
    bio: "Médecin généraliste inscrit à l'Ordre. Consultations à domicile, suivi des maladies chroniques.",
    rating: 4.9,
    ratingCount: 27,
    careCount: 75,
  ),
  Pro(
    id: 'pro6',
    name: 'Koffi N’Guessan',
    type: ProType.kine,
    communes: ['Cocody', 'Riviera', 'Bingerville', 'Marcory'],
    prices: {'kine': 12000},
    yearsExperience: 7,
    bio: 'Kinésithérapeute. Rééducation post-opératoire et après AVC.',
    rating: 4.6,
    ratingCount: 14,
    careCount: 52,
  ),
  Pro(
    id: 'pro7',
    name: 'Fatou Diabaté',
    type: ProType.sageFemme,
    communes: ['Yopougon', 'Plateau', 'Cocody'],
    prices: {'suivi_grossesse': 12000},
    yearsExperience: 9,
    bio: 'Sage-femme. Suivi de grossesse et soins après accouchement.',
    rating: 4.9,
    ratingCount: 31,
    careCount: 88,
  ),
];

/// Pharmacies de démonstration (noms et numéros fictifs). La garde tourne :
/// une pharmacie de garde par commune autour de [now].
List<Pharmacy> buildDemoPharmacies(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final dutyFrom = today.subtract(const Duration(hours: 4)); // la veille 20 h
  final dutyUntil = today.add(const Duration(days: 1, hours: 8));
  Pharmacy p(
    String id,
    String name,
    String commune,
    String address,
    String phone, {
    bool duty = false,
    String hours = 'Lun.–sam. 8 h – 20 h',
    GeoPoint? at,
  }) => Pharmacy(
    id: id,
    name: name,
    commune: commune,
    address: address,
    phone: phone,
    hours: hours,
    location: at,
    onDutyFrom: duty ? dutyFrom : null,
    onDutyUntil: duty ? dutyUntil : null,
  );
  return [
    p(
      'ph1',
      'Pharmacie des Deux-Plateaux (démo)',
      'Cocody',
      'Boulevard Latrille, face à la station',
      '0700000101',
      duty: true,
      at: const GeoPoint(5.3712, -3.9921),
    ),
    p(
      'ph2',
      'Pharmacie Angré Château (démo)',
      'Cocody',
      'Angré 8e tranche, carrefour Château',
      '0700000102',
      at: const GeoPoint(5.3954, -3.9853),
    ),
    p(
      'ph3',
      'Pharmacie de la Palmeraie (démo)',
      'Riviera',
      'Riviera Palmeraie, rue Ministre',
      '0700000103',
      duty: true,
      at: const GeoPoint(5.3746, -3.9405),
    ),
    p(
      'ph4',
      'Pharmacie Riviera 3 (démo)',
      'Riviera',
      'Riviera 3, près du marché',
      '0700000104',
    ),
    p(
      'ph5',
      'Pharmacie du Centre (démo)',
      'Bingerville',
      'Route de Bingerville, centre-ville',
      '0700000105',
      duty: true,
      at: const GeoPoint(5.3550, -3.8857),
    ),
    p(
      'ph6',
      'Pharmacie Zone 4 (démo)',
      'Marcory',
      'Zone 4, rue du Docteur Blanchard',
      '0700000106',
      duty: true,
    ),
    p(
      'ph7',
      'Pharmacie du Commerce (démo)',
      'Plateau',
      'Avenue Chardy',
      '0700000107',
      duty: true,
    ),
    p(
      'ph8',
      'Pharmacie Siporex (démo)',
      'Yopougon',
      'Yopougon Siporex, voie express',
      '0700000108',
      duty: true,
    ),
  ];
}

/// Avis de démonstration (prénom et initiale seulement).
void addDemoReviews(List<Pro> pros, DateTime now) {
  DateTime ago(int days) => now.subtract(Duration(days: days));
  final byId = {for (final p in pros) p.id: p};
  byId['pro1']?.reviews.addAll([
    ProReview(
      rating: 5,
      comment:
          'Très douce avec ma mère, ponctuelle et '
          'elle nous envoie le compte rendu tout de suite.',
      at: ago(4),
      serviceName: 'Pansement',
      author: 'Awa B.',
    ),
    ProReview(
      rating: 5,
      comment:
          'Perfusion bien posée, explications '
          'claires.',
      at: ago(11),
      serviceName: 'Perfusion',
      author: 'Jean K.',
    ),
    ProReview(
      rating: 4,
      comment:
          'Arrivée avec 15 minutes de retard mais '
          'elle a prévenu.',
      at: ago(20),
      serviceName: 'Injection',
      author: 'Mariam T.',
    ),
  ]);
  byId['pro2']?.reviews.addAll([
    ProReview(
      rating: 5,
      comment:
          'Suit le diabète de mon père depuis 3 '
          'mois, très sérieux.',
      at: ago(6),
      serviceName: 'Injection',
      author: 'Koffi B.',
    ),
    ProReview(
      rating: 4,
      comment: 'Bon soignant, un peu pressé.',
      at: ago(30),
      serviceName: 'Pansement',
      author: 'Aminata D.',
    ),
  ]);
  byId['pro5']?.reviews.add(
    ProReview(
      rating: 5,
      comment:
          'Consultation complète à la maison, il a '
          'pris le temps.',
      at: ago(9),
      serviceName: 'Consultation',
      author: 'Estelle A.',
    ),
  );
}
