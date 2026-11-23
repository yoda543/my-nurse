import 'dart:convert';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Coordonnées GPS.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  /// Lien d'itinéraire pour le soignant.
  Uri get directionsUrl =>
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');

  @override
  String toString() => '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}

/// Lieu détecté à partir de la position du téléphone.
class DetectedPlace {
  const DetectedPlace({
    required this.point,
    required this.address,
    required this.commune,
    this.simulated = false,
  });

  final GeoPoint point;

  /// Adresse lisible (quartier, rue, commune) ou coordonnées à défaut.
  final String address;

  /// Commune de lancement la plus probable, null hors zone.
  final String? commune;

  /// Vrai quand la position est une position de démonstration.
  final bool simulated;
}

class LocationError implements Exception {
  const LocationError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Centre approximatif de chaque commune de lancement.
const communeCenters = <String, GeoPoint>{
  'Plateau': GeoPoint(5.3220, -4.0200),
  'Cocody': GeoPoint(5.3600, -3.9900),
  'Riviera': GeoPoint(5.3700, -3.9550),
  'Bingerville': GeoPoint(5.3550, -3.8850),
  'Marcory': GeoPoint(5.3000, -3.9800),
  'Yopougon': GeoPoint(5.3450, -4.0750),
};

/// Au-delà, la position est hors de la zone desservie.
const maxCommuneDistanceKm = 8.0;

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

/// Commune de lancement la plus proche, ou null si la position est hors zone.
String? nearestCommune(GeoPoint p) {
  String? best;
  var bestKm = double.infinity;
  communeCenters.forEach((name, center) {
    final d = distanceKm(p, center);
    if (d < bestKm) {
      bestKm = d;
      best = name;
    }
  });
  return bestKm <= maxCommuneDistanceKm ? best : null;
}

/// Commune citée dans une adresse (Riviera avant Cocody, qui la contient).
String? communeFromText(String text) {
  final t = text.toLowerCase();
  for (final name in [
    'Riviera',
    'Bingerville',
    'Yopougon',
    'Marcory',
    'Plateau',
    'Cocody',
  ]) {
    if (t.contains(name.toLowerCase())) return name;
  }
  return null;
}

/// Met en forme la réponse d'OpenStreetMap (Nominatim) : « quartier, rue, commune ».
String formatNominatim(Map<String, dynamic> json) {
  final a = (json['address'] as Map?)?.cast<String, dynamic>() ?? const {};
  String? field(List<String> keys) {
    for (final k in keys) {
      final v = a[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  final road = field(['road', 'pedestrian', 'footway']);
  final number = field(['house_number']);
  final parts = <String>[
    ?field(['neighbourhood', 'quarter', 'residential', 'hamlet']),
    ?(road == null ? null : (number == null ? road : '$number $road')),
    ?field(['suburb']),
    ?field(['city_district', 'town', 'village', 'city']),
  ];
  // La commune n'est pas toujours dans les champs (Angré → Cocody) : on la
  // reprend du libellé complet. « Abidjan » n'apporte rien au soignant.
  final commune = communeFromText((json['display_name'] as String?) ?? '');
  if (commune != null &&
      !parts.any((p) => p.toLowerCase() == commune.toLowerCase())) {
    final i = parts.indexWhere((p) => p.toLowerCase() == 'abidjan');
    i == -1 ? parts.add(commune) : parts.insert(i, commune);
  }
  parts.removeWhere((p) => p.toLowerCase() == 'abidjan');
  final unique = <String>[];
  for (final p in parts) {
    if (!unique.any((u) => u.toLowerCase() == p.toLowerCase())) unique.add(p);
  }
  if (unique.isEmpty) return (json['display_name'] as String?) ?? '';
  return unique.join(', ');
}

/// Donne le lieu où se trouve l'utilisateur.
abstract class Locator {
  Future<DetectedPlace> locate();
}

/// Position du téléphone (GPS) puis adresse via OpenStreetMap.
class DeviceLocator implements Locator {
  DeviceLocator({http.Client? client, this.demoFallback = false})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// En démonstration, une position d'exemple remplace une position
  /// indisponible (navigateur qui la refuse, par exemple).
  final bool demoFallback;

  static const demoPlace = DetectedPlace(
    point: GeoPoint(5.3967, -3.9890),
    address: 'Angré 8e tranche, Cocody',
    commune: 'Cocody',
    simulated: true,
  );

  @override
  Future<DetectedPlace> locate() async {
    try {
      final point = await _position();
      final address = await reverseGeocode(point);
      final commune =
          (address == null ? null : communeFromText(address)) ??
          nearestCommune(point);
      return DetectedPlace(
        point: point,
        // Sans service d'adresses, la commune suffit : la position exacte
        // part quand même au soignant.
        address:
            address ??
            (commune == null
                ? 'Position GPS ($point)'
                : '$commune, position GPS'),
        commune: commune,
      );
    } on Object catch (e) {
      if (demoFallback) return demoPlace;
      if (e is LocationError) rethrow;
      throw const LocationError(
        'Position introuvable pour le moment. Saisissez l’adresse.',
      );
    }
  }

  Future<GeoPoint> _position() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationError('Activez la localisation de votre téléphone.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationError(
        'Autorisez MyNurse à utiliser votre position, ou saisissez l’adresse.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationError(
        'La localisation est bloquée pour MyNurse : autorisez-la dans les '
        'réglages du téléphone, ou saisissez l’adresse.',
      );
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return GeoPoint(p.latitude, p.longitude);
  }

  /// Adresse lisible d'une position, ou null si le service ne répond pas.
  /// En production, passer par un service dont les conditions autorisent un
  /// usage commercial (Nominatim auto-hébergé, LocationIQ…).
  Future<String?> reverseGeocode(GeoPoint p) async {
    try {
      final res = await _client
          .get(
            Uri.https('nominatim.openstreetmap.org', '/reverse', {
              'format': 'jsonv2',
              'lat': '${p.lat}',
              'lon': '${p.lng}',
              'zoom': '18',
              'addressdetails': '1',
              'accept-language': 'fr',
            }),
            headers: const {'User-Agent': 'MyNurse/1.0'},
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final text = formatNominatim(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      );
      return text.isEmpty ? null : text;
    } on Object {
      return null;
    }
  }
}
