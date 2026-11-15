import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mynurse/app_state.dart';
import 'package:mynurse/main.dart';
import 'package:mynurse/models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('prix : majoration de nuit de 50 % et commission de 15 %', () {
    final app = AppState();
    final pro = app.pros.first;
    final service = app.services.firstWhere((s) => s.id == 'pansement');
    final day = app.book(
      service: service,
      pro: pro,
      commune: 'Cocody',
      address: 'Angré 8e tranche',
      scheduledAt: DateTime(2030, 1, 10, 10),
      hasPrescription: false,
    );
    expect(day.price, 8000);
    expect(day.commission, 1200);
    expect(day.proEarnings, 6800);

    final night = app.book(
      service: service,
      pro: pro,
      commune: 'Cocody',
      address: 'Angré 8e tranche',
      scheduledAt: DateTime(2030, 1, 10, 22),
      hasPrescription: false,
    );
    expect(night.price, 12000);
    expect(night.proEarnings, 10200);
  });

  test('cycle complet : demande, acceptation, compte rendu, note', () {
    final app = AppState();
    final pro = app.pros.first;
    final before = pro.careCount;
    final b = app.book(
      service: app.services.first,
      pro: pro,
      commune: 'Cocody',
      address: 'Angré 8e tranche',
      scheduledAt: DateTime(2030, 1, 10, 10),
      hasPrescription: true,
    );
    expect(b.status, BookingStatus.pending);

    // Pas de compte rendu ni de note avant l'acceptation.
    final log = CareLog(
      arrivedAt: DateTime(2030, 1, 10, 10),
      leftAt: DateTime(2030, 1, 10, 10, 30),
      acts: 'Injection IM',
    );
    app.submitCareLog(b, log);
    expect(b.status, BookingStatus.pending);

    app.respond(b, accept: true);
    app.submitCareLog(b, log);
    expect(b.status, BookingStatus.done);
    expect(pro.careCount, before + 1);

    app.rate(b, 5, 'Très bien');
    app.rate(b, 1, 'Deuxième note ignorée');
    expect(b.rating, 5);
  });

  test('recherche : seuls les pros de la commune qui font ce soin', () {
    final app = AppState();
    final kine = app.services.firstWhere((s) => s.id == 'kine');
    expect(app.prosFor(kine, 'Yopougon'), isEmpty);
    expect(app.prosFor(kine, 'Cocody').single.type, ProType.kine);
  });

  testWidgets('accueil puis connexion patient', (tester) async {
    await tester.pumpWidget(MyNurseApp(state: AppState()));
    await tester.pumpAndSettle();
    expect(find.text('MyNurse'), findsOneWidget);

    await tester.tap(find.text('Je cherche un soignant'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0700000000');
    await tester.tap(find.text('Recevoir le code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(find.text('De quel soin avez-vous besoin ?'), findsOneWidget);
  });
}
