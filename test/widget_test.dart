import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mynurse/app_state.dart';
import 'package:mynurse/main.dart';
import 'package:mynurse/models.dart';

final _day = DateTime(2030, 1, 10, 10);
DateTime _now = DateTime(2030, 1, 1, 8);
DateTime _clock() => _now;
AppState _app() => AppState(clock: _clock);

Future<Booking> _book(
  AppState app, {
  String service = 'pansement',
  DateTime? at,
  Patient? patient,
}) => app.book(
  service: app.services.firstWhere((s) => s.id == service),
  pro: app.pros.first,
  commune: 'Cocody',
  address: 'Angré 8e tranche',
  scheduledAt: at ?? _day,
  hasPrescription: true,
  patient: patient,
);

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => _now = DateTime(2030, 1, 1, 8));

  group('prix', () {
    test('majoration de nuit de 50 % et commission de 10 %', () async {
      final app = _app();
      final day = await _book(app);
      expect(day.price, 8000);
      expect(day.commission, 800);
      expect(day.proEarnings, 7200);

      final night = await _book(app, at: DateTime(2030, 1, 10, 22));
      expect(night.price, 12000);
      expect(night.proEarnings, 10800);
    });
  });

  group('cycle d’un soin', () {
    test('demande, acceptation, paiement, compte rendu, note', () async {
      final app = _app();
      final pro = app.pros.first;
      final before = pro.careCount;
      final log = CareLog(
        arrivedAt: _day,
        leftAt: _day.add(const Duration(minutes: 30)),
        acts: 'Pansement refait',
      );
      final b = await _book(app);
      expect(b.status, BookingStatus.pending);

      // Pas de paiement avant l'acceptation.
      await app.pay(b, PaymentMethod.wave);
      expect(b.paid, isFalse);

      await app.respond(b, accept: true);
      expect(b.awaitingPayment, isTrue);

      // Pas de compte rendu tant que le patient n'a pas payé.
      expect(
        () => app.submitCareLog(b, log),
        throwsA(isA<BusinessRuleError>()),
      );
      expect(b.status, BookingStatus.accepted);

      await app.pay(b, PaymentMethod.wave);
      expect(b.readyForCare, isTrue);
      expect(app.escrowTotal, greaterThanOrEqualTo(b.price));

      _now = _day;
      await app.submitCareLog(b, log);
      expect(b.status, BookingStatus.done);
      expect(pro.careCount, before + 1);

      await app.rate(b, 5, 'Très bien');
      await app.rate(b, 1, 'Deuxième note ignorée');
      expect(b.rating, 5);
    });

    test('annulation après paiement : remboursement', () async {
      final app = _app();
      final b = await _book(app);
      await app.respond(b, accept: true);
      await app.pay(b, PaymentMethod.orange);
      await app.cancel(b);
      expect(b.status, BookingStatus.cancelled);
      expect(b.refunded, isTrue);
      expect(app.refundTotal, b.price);
    });

    test('annulation avant paiement : rien à rembourser', () async {
      final app = _app();
      final b = await _book(app);
      await app.cancel(b);
      expect(b.refunded, isFalse);
    });

    test('un soin terminé ne peut plus être annulé', () async {
      final app = _app();
      final done = app.patientBookings.firstWhere(
        (b) => b.status == BookingStatus.done,
      );
      await app.cancel(done);
      expect(done.status, BookingStatus.done);
    });
  });

  group('porte-monnaie', () {
    test('recharge : limites et moyens acceptés', () async {
      final app = _app();
      final before = app.wallet.balance;
      await app.topUp(10000, PaymentMethod.orange);
      expect(app.wallet.balance, before + 10000);
      expect(app.wallet.history.first.kind, WalletTxKind.topUp);
      expect(() => app.topUp(100, PaymentMethod.wave), throwsArgumentError);
      expect(() => app.topUp(1000000, PaymentMethod.wave), throwsArgumentError);
      expect(() => app.topUp(5000, PaymentMethod.wallet), throwsArgumentError);
    });

    test('payer avec le solde : refusé si insuffisant, débité sinon', () async {
      final app = _app();
      final b = await _book(app);
      await app.respond(b, accept: true);
      app.wallet.move(WalletTxKind.payment, -app.wallet.balance, 'vider');
      expect(await app.pay(b, PaymentMethod.wallet), isFalse);
      expect(b.paid, isFalse);

      await app.topUp(10000, PaymentMethod.wave);
      expect(await app.pay(b, PaymentMethod.wallet), isTrue);
      expect(app.wallet.balance, 10000 - b.price);
      expect(b.readyForCare, isTrue);
    });

    test('annulation : remboursement immédiat sur le solde', () async {
      final app = _app();
      final b = await _book(app);
      await app.respond(b, accept: true);
      await app.pay(b, PaymentMethod.mtn);
      final before = app.wallet.balance;
      await app.cancel(b);
      expect(app.wallet.balance, before + b.price);
      expect(app.wallet.history.first.kind, WalletTxKind.refund);
    });

    test('le soignant est crédité à la fin du soin, puis retire', () async {
      final app = _app();
      final aya = app.pros.first;
      final b = await _book(app);
      await app.respond(b, accept: true);
      await app.pay(b, PaymentMethod.wave);
      final before = aya.wallet.balance;
      expect(app.upcomingEarnings(aya), greaterThanOrEqualTo(b.proEarnings));

      _now = _day;
      await app.submitCareLog(
        b,
        CareLog(
          arrivedAt: _day,
          leftAt: _day.add(const Duration(minutes: 30)),
          acts: 'Pansement',
        ),
      );
      expect(aya.wallet.balance, before + b.proEarnings);

      expect(
        () => app.withdraw(aya, 500, PaymentMethod.wave),
        throwsArgumentError,
      );
      expect(
        () => app.withdraw(aya, aya.wallet.balance + 1, PaymentMethod.wave),
        throwsArgumentError,
      );
      await app.withdraw(aya, aya.wallet.balance, PaymentMethod.orange);
      expect(aya.wallet.balance, 0);
      expect(aya.wallet.history.first.kind, WalletTxKind.withdrawal);
    });

    test('démo : soldes de départ cohérents avec l’historique', () async {
      final app = _app();
      int sum(Wallet w) => w.history.fold(0, (s, t) => s + t.amount);
      expect(app.wallet.balance, sum(app.wallet));
      expect(app.pros.first.wallet.balance, sum(app.pros.first.wallet));
      expect(app.pros.first.wallet.balance, greaterThan(0));
    });
  });

  group('soignants', () {
    test(
      'un nouveau soignant reste invisible jusqu’à la vérification',
      () async {
        final app = _app();
        final pansement = app.services.firstWhere((s) => s.id == 'pansement');
        final before = app.prosFor(pansement, 'Yopougon').length;
        final p = await app.registerPro(
          name: 'Test Soignant',
          phone: '0102030405',
          type: ProType.infirmier,
          communes: ['Yopougon'],
          prices: {'pansement': 7000},
          yearsExperience: 3,
          bio: 'Infirmier diplômé.',
          orderNumber: 'ONII-1',
          nightAvailable: false,
          documents: requiredDocs(ProType.infirmier).toSet(),
        );
        expect(p.status, VerificationStatus.pending);
        expect(app.prosFor(pansement, 'Yopougon').length, before);

        await app.verifyPro(p);
        expect(app.prosFor(pansement, 'Yopougon').length, before + 1);
      },
    );

    test(
      'prix hors fourchette ou soin d’une autre profession refusés',
      () async {
        final app = _app();
        Future<Pro> reg(Map<String, int> prices) => app.registerPro(
          name: 'X',
          phone: '0102030405',
          type: ProType.infirmier,
          communes: ['Cocody'],
          prices: prices,
          yearsExperience: 1,
          bio: 'Bio',
          orderNumber: 'ONII-2',
          nightAvailable: false,
          documents: requiredDocs(ProType.infirmier).toSet(),
        );
        expect(() => reg({'pansement': 100000}), throwsArgumentError);
        expect(() => reg({'consultation': 20000}), throwsArgumentError);
      },
    );

    test('dossier incomplet : validation impossible', () async {
      final app = _app();
      final p = await app.registerPro(
        name: 'Incomplet',
        phone: '0102030406',
        type: ProType.infirmier,
        communes: ['Cocody'],
        prices: {'pansement': 7000},
        yearsExperience: 1,
        bio: 'Bio',
        orderNumber: 'ONII-3',
        nightAvailable: false,
        documents: {DocType.diplome},
      );
      // Pièces manquantes : « dossier incomplet », hors de la file des
      // vérificateurs, et aucune validation possible.
      expect(p.status, VerificationStatus.incomplete);
      expect(app.verificationQueue, isNot(contains(p)));
      await app.verifyPro(p);
      expect(p.status, VerificationStatus.incomplete);
      expect(p.activeAt(app.now), isFalse);
    });

    test('suspension : soins à venir annulés et remboursés', () async {
      final app = _app();
      final aya = app.pros.first;
      final paid = app.bookings.firstWhere(
        (b) => b.pro == aya && b.readyForCare,
      );
      await app.suspendPro(aya, 'Plainte en cours');
      expect(aya.status, VerificationStatus.suspended);
      expect(paid.status, BookingStatus.cancelled);
      expect(paid.refunded, isTrue);
      final pansement = app.services.firstWhere((s) => s.id == 'pansement');
      expect(app.prosFor(pansement, 'Cocody').contains(aya), isFalse);
    });

    test('connexion : numéro connu ou inscription', () async {
      final app = _app();
      app.loginPro(AppState.demoProPhone);
      expect(app.currentPro, app.pros.first);
      app.logout();
      app.loginPro('0999999999');
      expect(app.currentPro, isNull);
    });
  });

  group('patients', () {
    test('réserver pour un proche : ses allergies suivent', () async {
      final app = _app();
      final mother = await app.addPatient(
        name: 'Maman Bamba',
        relation: 'Mère',
        allergies: 'Pénicilline',
      );
      final b = await _book(app, service: 'injection', patient: mother);
      expect(b.patientName, 'Maman Bamba');
      expect(b.patient.allergies, 'Pénicilline');
      expect(
        app.patientBookings.every((e) => e.ownerId == app.account!.id),
        isTrue,
      );
    });

    test('le carnet regroupe les comptes rendus de la personne', () async {
      final app = _app();
      final me = app.patients.first;
      expect(app.careHistory(me), hasLength(1));
      expect(app.careHistory(me).first.careLog!.acts, contains('pansement'));
    });

    test('recherche : seuls les pros vérifiés de la commune', () async {
      final app = _app();
      final kine = app.services.firstWhere((s) => s.id == 'kine');
      expect(app.prosFor(kine, 'Yopougon'), isEmpty);
      expect(app.prosFor(kine, 'Cocody').single.type, ProType.kine);
      // Le dossier en attente de démonstration n'apparaît pas.
      final injection = app.services.firstWhere((s) => s.id == 'injection');
      expect(
        app.prosFor(injection, 'Marcory').any((p) => !p.verified),
        isFalse,
      );
    });
  });

  testWidgets('accueil puis connexion patient', (tester) async {
    await tester.pumpWidget(MyNurseApp(state: AppState()));
    await tester.pumpAndSettle();
    expect(find.text('MyNurse'), findsOneWidget);

    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0700000000');
    await tester.tap(find.text('Recevoir le code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(find.text('De quel soin avez-vous besoin ?'), findsOneWidget);
    // La cloche affiche la notification non lue du compte rendu.
    expect(find.byTooltip('1 notification non lue'), findsOneWidget);
  });

  testWidgets('connexion : un numéro inconnu est refusé avant le code', (
    tester,
  ) async {
    await tester.pumpWidget(MyNurseApp(state: AppState()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0799999999');
    await tester.tap(find.text('Recevoir le code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun compte avec ce numéro'), findsOneWidget);
  });

  testWidgets('création de compte patient puis nom', (tester) async {
    await tester.pumpWidget(MyNurseApp(state: AppState()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Je cherche un soignant'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0711111111');
    await tester.tap(find.text('Recevoir le code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    expect(find.text('Bienvenue sur MyNurse'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Kouadio Yao');
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text('Bonjour Kouadio,'), findsOneWidget);
  });

  testWidgets('un nouveau soignant arrive sur l’inscription', (tester) async {
    final app = AppState()..loginPro('0999999999');
    await tester.pumpWidget(MyNurseApp(state: app));
    await tester.pumpAndSettle();
    expect(find.text('Créer mon compte soignant'), findsOneWidget);
  });

  testWidgets('inscription : les champs vides du haut bloquent l’envoi', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppState()..loginPro('0999999999');
    await tester.pumpWidget(MyNurseApp(state: app));
    await tester.pumpAndSettle();
    final send = find.text('Envoyer mon dossier');
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text('Corrigez les champs en rouge.'), findsOneWidget);
    expect(app.currentPro, isNull);
  });

  testWidgets('l’administration voit le dossier en attente', (tester) async {
    final app = AppState()..login(UserRole.admin);
    await tester.pumpWidget(MyNurseApp(state: app));
    await tester.pumpAndSettle();
    // Tableau de bord : les indicateurs, puis la file des dossiers.
    expect(find.text('Patients inscrits'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Bernadette Ouattara'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Dossiers à vérifier'), findsOneWidget);
    expect(find.text('Bernadette Ouattara'), findsOneWidget);
  });
}
