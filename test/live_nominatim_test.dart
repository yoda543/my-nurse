@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mynurse/location.dart';

/// Appelle le vrai service OpenStreetMap : `flutter test --tags live`.
void main() {
  test('adresse réelle d’un point d’Angré', () async {
    final address = await DeviceLocator().reverseGeocode(
      const GeoPoint(5.3967, -3.9890),
    );
    // ignore: avoid_print
    print('Adresse : $address');
    expect(address, isNotNull);
    expect(communeFromText(address!), 'Cocody');
  });
}
