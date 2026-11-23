import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mynurse/app_state.dart';
import 'package:mynurse/location.dart';

class FakeLocator implements Locator {
  FakeLocator(this.result);

  final Object result;
  int calls = 0;

  @override
  Future<DetectedPlace> locate() async {
    calls++;
    if (result is DetectedPlace) return result as DetectedPlace;
    throw result;
  }
}

/// Réponse type de Nominatim pour Angré (Cocody).
const _nominatim = {
  'display_name': 'Rue L125, Angré 8e tranche, Cocody, Abidjan, Côte d’Ivoire',
  'address': {
    'road': 'Rue L125',
    'neighbourhood': 'Angré 8e tranche',
    'suburb': 'Cocody',
    'city': 'Abidjan',
    'country': 'Côte d’Ivoire',
  },
};

void main() {
  group('commune à partir de la position', () {
    test('la commune la plus proche', () {
      expect(nearestCommune(const GeoPoint(5.3220, -4.0200)), 'Plateau');
      expect(nearestCommune(const GeoPoint(5.3450, -4.0800)), 'Yopougon');
      expect(nearestCommune(const GeoPoint(5.3560, -3.8800)), 'Bingerville');
    });

    test('hors zone au-delà de 8 km (Grand-Bassam)', () {
      expect(nearestCommune(const GeoPoint(5.2118, -3.7388)), isNull);
    });

    test('la commune citée dans l’adresse, Riviera avant Cocody', () {
      expect(communeFromText('Riviera Palmeraie, Cocody'), 'Riviera');
      expect(communeFromText('Angré 8e tranche, Cocody'), 'Cocody');
      expect(communeFromText('Rue sans nom'), isNull);
    });

    test('distance entre Plateau et Cocody : environ 5 km', () {
      final d = distanceKm(
        communeCenters['Plateau']!,
        communeCenters['Cocody']!,
      );
      expect(d, closeTo(5, 1.5));
    });
  });

  group('adresse lisible', () {
    test('quartier, rue et commune, sans doublon', () {
      expect(
        formatNominatim(_nominatim),
        'Angré 8e tranche, Rue L125, Cocody, Abidjan',
      );
    });

    test('numéro de rue si connu', () {
      expect(
        formatNominatim({
          'address': {
            'house_number': '12',
            'road': 'Boulevard Latrille',
            'suburb': 'Cocody',
          },
        }),
        '12 Boulevard Latrille, Cocody',
      );
    });

    test('appel au service d’adresses', () async {
      Uri? called;
      final client = MockClient((req) async {
        called = req.url;
        return http.Response.bytes(utf8.encode(jsonEncode(_nominatim)), 200);
      });
      final address = await DeviceLocator(client: client)
          .reverseGeocode(const GeoPoint(5.3967, -3.989));
      expect(address, 'Angré 8e tranche, Rue L125, Cocody, Abidjan');
      expect(called!.host, 'nominatim.openstreetmap.org');
      expect(called!.queryParameters['lat'], '5.3967');
    });

    test('service en panne : pas d’adresse, sans erreur', () async {
      final client = MockClient((_) async => http.Response('', 503));
      expect(
        await DeviceLocator(client: client)
            .reverseGeocode(const GeoPoint(5, -4)),
        isNull,
      );
    });
  });

  group('dans l’app', () {
    const angre = DetectedPlace(
      point: GeoPoint(5.3967, -3.989),
      address: 'Angré 8e tranche, Cocody',
      commune: 'Cocody',
    );
    const yop = DetectedPlace(
      point: GeoPoint(5.345, -4.075),
      address: 'Niangon, Yopougon',
      commune: 'Yopougon',
    );

    test('la commune est choisie toute seule', () async {
      final app = AppState(locator: FakeLocator(yop));
      expect(app.commune, 'Cocody');
      await app.detectPlace();
      expect(app.commune, 'Yopougon');
      expect(app.place, yop);
      expect(app.locating, isFalse);
    });

    test(
      'hors zone : la commune ne change pas et un message l’explique',
      () async {
        final app = AppState(
          locator: FakeLocator(
            const DetectedPlace(
              point: GeoPoint(5.21, -3.74),
              address: 'Grand-Bassam',
              commune: null,
            ),
          ),
        );
        await app.detectPlace();
        expect(app.commune, 'Cocody');
        expect(app.locationError, contains('hors de nos communes'));
      },
    );

    test(
      'localisation refusée : message, et la saisie reste possible',
      () async {
        final app = AppState(
          locator: FakeLocator(const LocationError('Autorisez MyNurse')),
        );
        expect(await app.detectPlace(), isNull);
        expect(app.locationError, 'Autorisez MyNurse');
      },
    );

    test('la position GPS accompagne la réservation', () async {
      final app = AppState(
        clock: () => DateTime(2030, 1, 1, 8),
        locator: FakeLocator(angre),
      );
      final place = await app.detectPlace();
      final b = app.book(
        service: app.services.firstWhere((s) => s.id == 'pansement'),
        pro: app.pros.first,
        commune: app.commune,
        address: place!.address,
        scheduledAt: DateTime(2030, 1, 10, 10),
        hasPrescription: false,
        location: place.point,
      );
      expect(
        b.location!.directionsUrl.toString(),
        contains('destination=5.3967,-3.989'),
      );
    });

    test('un soignant qui n’intervient pas dans la commune est refusé', () {
      final app = AppState(clock: () => DateTime(2030, 1, 1, 8));
      expect(
        () => app.book(
          service: app.services.firstWhere((s) => s.id == 'pansement'),
          pro: app.pros.first, // Aya : Cocody, Riviera, Bingerville
          commune: 'Yopougon',
          address: 'Niangon, Yopougon',
          scheduledAt: DateTime(2030, 1, 10, 10),
          hasPrescription: false,
        ),
        throwsA(isA<BusinessRuleError>()),
      );
    });
  });
}
