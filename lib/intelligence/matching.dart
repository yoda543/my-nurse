/// Mise en relation patient–soignant.
///
/// Moteur pur (sans état ni réseau) : il classe les soignants pour une
/// demande et explique chaque recommandation. Il ne remplace pas le choix
/// du patient et ne juge aucune compétence clinique : il croise des
/// critères factuels (qualification déclarée et vérifiée, zone, agenda,
/// prix, avis, continuité des soins).
///
/// Aucune priorité n'est donnée aux abonnés Premium : l'abonnement n'entre
/// pas dans le calcul.
library;

import 'dart:math' as math;

import '../models.dart';

/// Ce que le patient demande.
class MatchRequest {
  const MatchRequest({
    required this.service,
    required this.commune,
    this.at,
    this.patient,
    this.location,
  });

  final CareService service;

  /// Commune du soin (lieu du patient, pas celui de la personne qui réserve).
  final String commune;

  /// Heure souhaitée, si elle est connue.
  final DateTime? at;
  final Patient? patient;

  /// Position précise du lieu du soin, si elle est partagée.
  final GeoPoint? location;
}

/// Un critère du score, avec son explication pour le patient.
class MatchFactor {
  const MatchFactor(this.label, this.score, this.weight, {this.reason});

  final String label;

  /// Note du critère entre 0 et 1.
  final double score;
  final double weight;

  /// Phrase courte montrée au patient (null : rien de notable).
  final String? reason;
}

class Recommendation {
  const Recommendation({
    required this.pro,
    required this.price,
    required this.score,
    required this.factors,
    this.distanceKm,
  });

  final Pro pro;
  final int price;

  /// Score global sur 100.
  final int score;
  final List<MatchFactor> factors;
  final double? distanceKm;

  /// Les raisons les plus parlantes, dans l'ordre d'importance.
  List<String> get reasons => [
    for (final f in [
      ...factors,
    ]..sort((a, b) => (b.score * b.weight).compareTo(a.score * a.weight)))
      if (f.reason != null && f.score >= 0.6) f.reason!,
  ];
}

/// Centres approximatifs des communes desservies (distances indicatives).
const communeCenters = <String, GeoPoint>{
  'Cocody': GeoPoint(5.3600, -3.9900),
  'Riviera': GeoPoint(5.3700, -3.9450),
  'Bingerville': GeoPoint(5.3550, -3.8850),
  'Marcory': GeoPoint(5.3020, -3.9800),
  'Plateau': GeoPoint(5.3220, -4.0200),
  'Yopougon': GeoPoint(5.3400, -4.0800),
};

/// Distance à vol d'oiseau en km.
double distanceKm(GeoPoint a, GeoPoint b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) *
          math.cos(rad(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// Pondération des critères (somme = 1). Modifiable sans toucher au calcul.
class MatchWeights {
  const MatchWeights({
    this.proximity = 0.20,
    this.availability = 0.20,
    this.rating = 0.20,
    this.price = 0.15,
    this.continuity = 0.15,
    this.experience = 0.10,
  });

  final double proximity;
  final double availability;
  final double rating;
  final double price;
  final double continuity;
  final double experience;
}

class MatchingEngine {
  const MatchingEngine({this.weights = const MatchWeights()});

  final MatchWeights weights;

  /// Soignants recommandés, du plus pertinent au moins pertinent.
  ///
  /// Filtres stricts (jamais compensés par un bon score) : compte vérifié
  /// et pièces à jour, soin proposé et autorisé par sa profession, commune
  /// desservie (soin à domicile), nuit acceptée si l'heure est de nuit,
  /// pas d'absence déclarée à l'heure demandée.
  List<Recommendation> recommend({
    required MatchRequest request,
    required List<Pro> pros,
    required List<Booking> bookings,
    required DateTime now,
  }) {
    final s = request.service;
    final out = <Recommendation>[];
    for (final p in pros) {
      if (!p.activeAt(now)) continue;
      final price = p.prices[s.id];
      if (price == null || s.proType != p.type) continue; // qualification
      if (!p.communes.contains(request.commune)) continue; // à domicile ici
      final at = request.at;
      if (at != null && isNight(at) && !p.nightAvailable) continue;
      final avail = _availability(p, request, bookings, now);
      if (avail == null) continue; // absent ou déjà pris à cette heure
      final dist = _distance(p, request);
      final factors = [
        _proximity(dist, request.commune),
        avail,
        _rating(p),
        _price(price, s),
        _continuity(p, request.patient, bookings),
        _experience(p),
        if (at != null && isNight(at))
          const MatchFactor('Nuit', 1, 0, reason: 'Se déplace la nuit'),
      ];
      final score = factors.fold<double>(0, (t, f) => t + f.score * f.weight);
      out.add(
        Recommendation(
          pro: p,
          price: price,
          score: (score * 100).round().clamp(0, 100),
          factors: factors,
          distanceKm: dist,
        ),
      );
    }
    out.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.price.compareTo(b.price);
    });
    return out;
  }

  // -------------------------------------------------------------- critères
  /// Distance entre la zone du soignant et le lieu du soin. Le soignant
  /// n'a pas de position publique : on prend le centre de la commune la
  /// plus proche qu'il dessert.
  double? _distance(Pro p, MatchRequest r) {
    final target = r.location ?? communeCenters[r.commune];
    if (target == null) return null;
    double? best;
    for (final c in p.communes) {
      final center = communeCenters[c];
      if (center == null) continue;
      final d = distanceKm(center, target);
      if (best == null || d < best) best = d;
    }
    return best;
  }

  MatchFactor _proximity(double? km, String commune) {
    if (km == null) {
      return MatchFactor('Proximité', 0.5, weights.proximity);
    }
    final score = (1 - km / 15).clamp(0.0, 1.0);
    return MatchFactor(
      'Proximité',
      score,
      weights.proximity,
      reason: km < 2 ? 'Intervient à $commune' : 'À environ ${km.round()} km',
    );
  }

  /// Disponibilité réelle : plages déclarées, absences, soins déjà
  /// confirmés. null = indisponible à l'heure demandée (filtre).
  MatchFactor? _availability(
    Pro p,
    MatchRequest r,
    List<Booking> bookings,
    DateTime now,
  ) {
    final at = r.at;
    final duration = Duration(minutes: r.service.durationMinutes);
    bool busy(DateTime start) => bookings.any(
      (b) =>
          b.pro == p &&
          b.status == BookingStatus.accepted &&
          overlaps(start, start.add(duration), b.scheduledAt, b.endsAt),
    );
    bool off(DateTime start) => p.daysOff.any(
      (o) => overlaps(start, start.add(duration), o.from, o.to),
    );
    bool inHours(DateTime start) =>
        p.availability.isEmpty ||
        p.availability.any((a) => a.covers(start, start.add(duration)));
    if (at != null) {
      if (off(at) || busy(at)) return null;
      if (!inHours(at)) return null;
      return MatchFactor(
        'Disponibilité',
        1,
        weights.availability,
        reason:
            'Libre le ${at.day}/${at.month} à ${at.hour} h${at.minute == 0 ? '' : at.minute.toString().padLeft(2, '0')}',
      );
    }
    // Sans heure : part de créneaux libres sur les 48 prochaines heures
    // (de 8 h à 18 h, toutes les 2 h).
    var free = 0, total = 0;
    final day0 = DateTime(now.year, now.month, now.day);
    for (var d = 0; d < 2; d++) {
      for (var h = 8; h <= 18; h += 2) {
        final t = day0.add(Duration(days: d, hours: h));
        if (t.isBefore(now.add(minNotice))) continue;
        total++;
        if (!off(t) && !busy(t) && inHours(t)) free++;
      }
    }
    final score = total == 0 ? 0.5 : free / total;
    return MatchFactor(
      'Disponibilité',
      score,
      weights.availability,
      reason: score >= 0.6 ? 'Disponible dans les 48 h' : null,
    );
  }

  /// Note bayésienne : un soignant avec 2 avis à 5/5 ne passe pas devant un
  /// soignant avec 40 avis à 4,8/5.
  MatchFactor _rating(Pro p) {
    const prior = 4.0, weight = 5;
    final avg =
        (p.rating * p.ratingCount + prior * weight) / (p.ratingCount + weight);
    final score = ((avg - 3) / 2).clamp(0.0, 1.0);
    return MatchFactor(
      'Avis des patients',
      score,
      weights.rating,
      reason: p.ratingCount >= 5
          ? '${p.rating.toStringAsFixed(1).replaceAll('.', ',')}/5 sur ${p.ratingCount} avis'
          : null,
    );
  }

  MatchFactor _price(int price, CareService s) {
    final span = (s.maxPrice - s.minPrice).toDouble();
    final score = span <= 0
        ? 1.0
        : (1 - (price - s.minPrice) / span).clamp(0.0, 1.0);
    return MatchFactor(
      'Prix',
      score,
      weights.price,
      reason: score >= 0.6 ? 'Prix dans le bas de la fourchette' : null,
    );
  }

  /// Continuité des soins : le soignant connaît déjà ce patient.
  MatchFactor _continuity(Pro p, Patient? patient, List<Booking> bookings) {
    if (patient == null) {
      return MatchFactor('Continuité', 0, weights.continuity);
    }
    final past = bookings.where(
      (b) =>
          b.pro == p && b.patient == patient && b.status == BookingStatus.done,
    );
    final rated = past.where((b) => b.rating != null);
    final bad = rated.any((b) => b.rating! <= 2);
    if (past.isEmpty || bad) {
      return MatchFactor('Continuité', 0, weights.continuity);
    }
    return MatchFactor(
      'Continuité',
      math.min(1.0, 0.6 + 0.2 * past.length),
      weights.continuity,
      reason:
          'A déjà soigné ${patient.name.split(' ').first} '
          '(${past.length} soin${past.length > 1 ? 's' : ''})',
    );
  }

  MatchFactor _experience(Pro p) {
    final score =
        (p.yearsExperience / 10).clamp(0.0, 1.0) * 0.6 +
        (p.careCount / 100).clamp(0.0, 1.0) * 0.4;
    return MatchFactor(
      'Expérience',
      score,
      weights.experience,
      reason: p.yearsExperience >= 8
          ? '${p.yearsExperience} ans d’expérience'
          : null,
    );
  }
}
