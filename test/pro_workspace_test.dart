import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mynurse/app_state.dart';
import 'package:mynurse/main.dart';
import 'package:mynurse/models.dart';

/// Espace soignant (données de démonstration : Aya Kouamé, infirmière).
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late DateTime now;
  late AppState app;
  Pro aya() => app.pros.firstWhere((p) => p.id == 'pro1');
  Pro estelle() => app.pros.firstWhere((p) => p.id == 'pro4'); // aide-soignante
  CareService svc(String id) => app.services.firstWhere((s) => s.id == id);
  Booking adjoua() =>
      app.bookings.firstWhere((b) => b.patient.name == 'Adjoua Brou');
  Booking jean() =>
      app.bookings.firstWhere((b) => b.patient.name == 'Jean Kouassi');

  setUp(() {
    now = DateTime(2030, 1, 1, 8);
    app = AppState(clock: () => now)..loginDemo(AppState.demoProPhone);
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(420, 2000),
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MyNurseApp(state: app));
    await tester.pumpAndSettle();
  }

  /// Awa réserve pour sa mère avec Aya, Aya accepte, Awa paie.
  Future<Booking> familyVisit({DateTime? at}) async {
    app.loginDemo(AppState.demoPatientPhone);
    final b = await app.book(
      service: svc('pansement'),
      pro: aya(),
      commune: 'Cocody',
      address: 'Angré 7e tranche, villa 24',
      scheduledAt: at ?? DateTime(2030, 1, 2, 11),
      hasPrescription: false,
      patient: app.patients.firstWhere((p) => p.name == 'Mariam Bamba'),
    );
    app.loginDemo(AppState.demoProPhone);
    await app.respond(b, accept: true);
    app.loginDemo(AppState.demoPatientPhone);
    await app.pay(b, PaymentMethod.wallet);
    app.loginDemo(AppState.demoProPhone);
    return b;
  }

  // ========================================================= vérification
  group('vérification', () {
    Future<Pro> register({Set<DocType>? docs}) => app.registerPro(
      name: 'Moussa Diallo',
      phone: '0102030499',
      type: ProType.infirmier,
      communes: ['Cocody'],
      prices: {'pansement': 7000},
      yearsExperience: 3,
      bio: 'Infirmier',
      orderNumber: 'ONII-9',
      nightAvailable: false,
      documents: docs ?? {DocType.diplome, DocType.cni},
    );

    test('incomplet → en attente → en examen → vérifié', () async {
      final p = await register();
      expect(p.status, VerificationStatus.incomplete);
      expect(app.verificationQueue, isNot(contains(p)));
      app.currentPro = p;
      await app.submitProDocuments({
        DocType.autorisation: null,
        DocType.ordre: DateTime(2031, 1, 1),
        DocType.rcPro: DateTime(2030, 12, 31),
      });
      expect(p.status, VerificationStatus.pending);
      expect(app.verificationQueue, contains(p));
      await app.startReview(p);
      expect(p.status, VerificationStatus.underReview);
      await app.verifyPro(p);
      expect(p.status, VerificationStatus.verified);
      expect(p.activeAt(now), isTrue);
    });

    test(
      'pièce expirée : plus de demande, renouvellement puis contrôle',
      () async {
        final p = aya();
        now = DateTime(2030, 1, 25); // l'assurance d'Aya expire le 21/01
        expect(p.statusAt(now), VerificationStatus.expired);
        expect(p.activeAt(now), isFalse);
        expect(
          app
              .searchPros(const SearchFilters(commune: 'Cocody'))
              .map((m) => m.pro),
          isNot(contains(p)),
        );
        await expectLater(
          app.respond(jean(), accept: true),
          throwsA(isA<BusinessRuleError>()),
        );
        await app.submitProDocuments({DocType.rcPro: DateTime(2031, 1, 25)});
        expect(p.status, VerificationStatus.underReview);
        await app.verifyPro(p);
        expect(p.activeAt(now), isTrue);
      },
    );

    test('un soignant non vérifié ne reçoit aucune demande', () async {
      final p = await register();
      p.prices = {'pansement': 7000};
      app.loginDemo(AppState.demoPatientPhone);
      expect(
        app
            .searchPros(const SearchFilters(commune: 'Cocody'))
            .map((m) => m.pro),
        isNot(contains(p)),
      );
      await expectLater(
        app.book(
          service: svc('pansement'),
          pro: p,
          commune: 'Cocody',
          address: 'Angré 8e tranche',
          scheduledAt: DateTime(2030, 1, 3, 10),
          hasPrescription: false,
        ),
        throwsA(isA<BusinessRuleError>()),
      );
    });

    testWidgets('écran bloquant tant que le compte n’est pas actif', (
      tester,
    ) async {
      now = DateTime(2030, 1, 25);
      await pumpApp(tester);
      expect(find.text('Pièce expirée'), findsOneWidget);
      expect(find.text('Assurance responsabilité civile pro'), findsOneWidget);
      expect(find.text('Renouveler'), findsOneWidget);
      expect(find.textContaining('ne recevez aucune demande'), findsOneWidget);
    });
  });

  // ===================================================== champ d'exercice
  group('champ d’exercice', () {
    test('aide-soignant(e) : actes, constantes et dossier limités', () async {
      final s = estelle().scope;
      expect(s.vitals, isNot(contains(VitalKind.glycemia)));
      expect(s.documents, isFalse);
      expect(app.servicesAllowedFor(estelle()).map((x) => x.id), ['toilette']);
      app.currentPro = estelle();
      await expectLater(
        app.updateProServices({'injection': 6000}),
        throwsA(isA<BusinessRuleError>()),
      );
    });

    test('une infirmière ne relève pas une mesure hors champ… mais Estelle oui la température', () async {
      app.currentPro = estelle();
      final b = await app.book(
        service: svc('toilette'),
        pro: estelle(),
        commune: 'Cocody',
        address: 'Angré 8e tranche',
        scheduledAt: DateTime(2030, 1, 1, 10),
        hasPrescription: false,
        patient: app.accounts.first.patients.first,
      );
      await app.respond(b, accept: true);
      app.loginDemo(AppState.demoPatientPhone);
      await app.pay(b, PaymentMethod.wallet);
      app.currentPro = estelle();
      app.role = UserRole.pro;
      await expectLater(
        app.recordVital(b, VitalKind.glycemia, 1.2),
        throwsA(isA<BusinessRuleError>()),
      );
      final v = await app.recordVital(b, VitalKind.temperature, 37.2);
      expect(v.display, '37,2 °C');
    });
  });

  // ================================================ 1. tableau de bord
  group('1. tableau de bord', () {
    testWidgets('disponibilité, chiffres, soin en cours, rappels', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('Bonjour Aya'), findsOneWidget);
      expect(find.text('Disponible aujourd’hui'), findsOneWidget);
      expect(find.text('Soin en cours'), findsOneWidget);
      expect(find.textContaining('Adjoua Brou'), findsWidgets);
      expect(
        find.textContaining('Assurance responsabilité civile pro expire'),
        findsOneWidget,
      );
      expect(find.text('Je pars'), findsOneWidget);
    });
  });

  // ======================================================== 2. agenda
  group('2. agenda', () {
    test('les soins du jour, triés par heure', () {
      expect(app.proDay(now).map((b) => b.patientName), ['Adjoua Brou']);
    });

    testWidgets('bande des 14 jours et soins du jour', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Agenda').last); // onglet du bas
      await tester.pumpAndSettle();
      expect(find.text('auj.'), findsOneWidget);
      expect(find.textContaining('Injection · Adjoua Brou'), findsOneWidget);
    });
  });

  // ================================================ 3. disponibilités
  group('3. disponibilités', () {
    test('hors des plages déclarées : réservation refusée', () async {
      await app.setAvailability([
        for (var d = 1; d <= 5; d++) AvailabilityRule(d, 8 * 60, 18 * 60),
      ]);
      app.loginDemo(AppState.demoPatientPhone);
      // 05/01/2030 est un samedi.
      await expectLater(
        app.book(
          service: svc('pansement'),
          pro: aya(),
          commune: 'Cocody',
          address: 'Angré 8e tranche',
          scheduledAt: DateTime(2030, 1, 5, 10),
          hasPrescription: false,
        ),
        throwsA(isA<BusinessRuleError>()),
      );
      final ok = await app.book(
        service: svc('pansement'),
        pro: aya(),
        commune: 'Cocody',
        address: 'Angré 8e tranche',
        scheduledAt: DateTime(2030, 1, 3, 10),
        hasPrescription: false,
      );
      expect(ok.status, BookingStatus.pending);
    });

    test(
      'indisponible aujourd’hui : refusé s’il reste un soin confirmé',
      () async {
        await expectLater(
          app.setAvailableToday(false),
          throwsA(isA<BusinessRuleError>()),
        );
        app.currentPro = app.pros.firstWhere((p) => p.id == 'pro2');
        await app.setAvailableToday(false);
        expect(app.availableToday, isFalse);
        await app.setAvailableToday(true);
        expect(app.availableToday, isTrue);
      },
    );
  });

  // ============================================== 4. soins et tarifs
  group('4. soins et tarifs', () {
    test('prix dans la fourchette, actes de la profession seulement', () async {
      await expectLater(
        app.updateProServices({'pansement': 40000}),
        throwsA(isA<BusinessRuleError>()),
      );
      await expectLater(
        app.updateProServices({'kine': 12000}),
        throwsA(isA<BusinessRuleError>()),
      );
      await app.updateProServices({'pansement': 9000, 'injection': 6000});
      expect(aya().prices, {'pansement': 9000, 'injection': 6000});
    });
  });

  // =================================== 5-6. demandes, acceptation, refus
  group('5-6. demandes', () {
    test('refus motivé : le patient reçoit le motif', () async {
      final b = await () async {
        app.loginDemo(AppState.demoPatientPhone);
        final x = await app.book(
          service: svc('pansement'),
          pro: aya(),
          commune: 'Cocody',
          address: 'Angré 8e tranche',
          scheduledAt: DateTime(2030, 1, 3, 10),
          hasPrescription: false,
        );
        app.loginDemo(AppState.demoProPhone);
        return x;
      }();
      await app.respond(b, accept: false, reason: 'Trop loin de ma zone');
      expect(b.status, BookingStatus.refused);
      expect(
        app.notifications.any(
          (n) =>
              n.recipient == 'A1' &&
              n.body.contains('Motif : Trop loin de ma zone'),
        ),
        isTrue,
      );
    });

    testWidgets('refuser en un geste depuis la liste', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Demandes').last);
      await tester.pumpAndSettle();
      expect(find.text('Suivi · 6 séances'), findsOneWidget);
      await tester.tap(find.text('Refuser').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pas disponible à cette heure'));
      await tester.pumpAndSettle();
      expect(
        find.text('Demande refusée. Le patient est prévenu.'),
        findsOneWidget,
      );
      expect(jean().status, BookingStatus.refused);
    });
  });

  // ============================================== 7. suivis réguliers
  group('7. suivis', () {
    test('un suivi accepté apparaît avec ses séances', () async {
      final c = app.bookings.firstWhere((b) => b.contract != null).contract!;
      await app.respond(c.sessions.first, accept: true);
      expect(app.proContracts, contains(c));
      expect(
        c.sessions.every((s) => s.status == BookingStatus.accepted),
        isTrue,
      );
    });
  });

  // ================================= 8. dossier patient (autorisé)
  group('8. dossier du patient', () {
    test('demande en attente : l’essentiel seulement', () async {
      final chart = await app.patientChart(jean());
      expect(chart.scopeLabel, contains('Demande en attente'));
      expect(chart.history, isEmpty);
      expect(chart.documents, isEmpty);
    });

    test('soin confirmé : carnet complet ; accès retiré : fermé', () async {
      final b = await familyVisit();
      final chart = await app.patientChart(b);
      expect(chart.allergies, 'Pénicilline');
      expect(chart.history, contains('diabète'));
      expect(chart.documents, isNotEmpty);
      // La fille retire l'accès.
      app.loginDemo(AppState.demoPatientPhone);
      final mariam = app.patients.firstWhere((p) => p.name == 'Mariam Bamba');
      final access = app
          .recordAccessFor(mariam)
          .firstWhere((a) => a.booking == b);
      await app.revokeRecordAccess(mariam, access);
      app.loginDemo(AppState.demoProPhone);
      await expectLater(app.patientChart(b), throwsA(isA<BusinessRuleError>()));
    });
  });

  // ============================ 9-11. journal, constantes, compte rendu
  group('9-11. visite', () {
    test('« Je pars » et « arrivé » préviennent la famille', () async {
      final b = await familyVisit();
      now = DateTime(2030, 1, 2, 10, 15);
      await app.markOnTheWay(b);
      expect(b.onTheWay, isTrue);
      final titles = app.notifications
          .where((n) => n.booking == b)
          .map((n) => (n.recipient, n.title))
          .toSet();
      expect(titles, contains(('A1', 'Aya Kouamé est en route')));
      expect(titles, contains(('A2', 'Aya Kouamé est en route')));
      now = DateTime(2030, 1, 2, 10, 50);
      await app.markArrived(b);
      expect(b.arrivedAt, now);
    });

    test('constantes : plausibles, alertes, puis dans le carnet', () async {
      final b = await familyVisit();
      await expectLater(
        app.recordVital(b, VitalKind.temperature, 52),
        throwsA(isA<BusinessRuleError>()),
      );
      await expectLater(
        app.recordVital(b, VitalKind.bloodPressure, 130),
        throwsA(isA<BusinessRuleError>()),
      );
      final bp = await app.recordVital(
        b,
        VitalKind.bloodPressure,
        170,
        value2: 95,
      );
      expect(bp.alert, isTrue);
      expect(bp.display, '170/95 mmHg');
      now = DateTime(2030, 1, 2, 11);
      await app.addJournalNote(b, 'Plaie propre, pas de signe d’infection');
      await app.submitCareLog(
        b,
        CareLog(
          arrivedAt: now,
          leftAt: now.add(const Duration(minutes: 30)),
          acts: 'Pansement',
        ),
      );
      expect(b.status, BookingStatus.done);
      app.loginDemo(AppState.demoPatientPhone);
      final mariam = app.patients.firstWhere((p) => p.name == 'Mariam Bamba');
      expect(app.vitalsFor(mariam).first.value, '170/95 mmHg');
    });

    testWidgets('saisie d’une mesure : seulement celles du champ d’exercice', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.textContaining('Injection (IM').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mesure'));
      await tester.pumpAndSettle();
      expect(find.text('Glycémie'), findsOneWidget); // infirmière : tout
      await tester.tap(find.text('Température'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '38,9');
      await tester.tap(find.text('Enregistrer la mesure'));
      await tester.pumpAndSettle();
      expect(find.textContaining('valeur à surveiller'), findsOneWidget);
      expect(find.text('Température 38,9 °C'), findsOneWidget);
    });
  });

  // ======================================== 12. historique de suivi
  group('12. historique', () {
    test('patients suivis et mes soins pour chacun', () {
      expect(
        app.proPatients.map((p) => p.name),
        containsAll(['Adjoua Brou', 'Awa Bamba']),
      );
      final awa = app.proPatients.firstWhere((p) => p.name == 'Awa Bamba');
      expect(app.proHistory(awa).single.careLog, isNotNull);
    });
  });

  // =============================== 13-15. revenus, commissions, retraits
  group('13-15. revenus', () {
    test('gains, commissions de 10 %, retraits', () async {
      expect(app.proDone, isNotEmpty);
      final b = app.proDone.first;
      expect(b.commission, (b.price * 0.10).round());
      expect(app.proWeeklyEarnings, hasLength(6));
      final before = aya().wallet.balance;
      await app.withdraw(aya(), 1000, PaymentMethod.wave, phone: '0500000000');
      expect(aya().wallet.balance, before - 1000);
      expect(app.proWithdrawals.first.amount, -1000);
    });

    testWidgets('onglet Revenus', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Revenus').last);
      await tester.pumpAndSettle();
      expect(find.text('Solde disponible'), findsOneWidget);
      expect(find.text('6 dernières semaines'), findsOneWidget);
      expect(find.text('Commissions'), findsOneWidget);
      expect(find.textContaining('commission'), findsWidgets);
    });
  });

  // ========================================== 16. avis et réputation
  group('16. réputation', () {
    test('répartition des notes', () {
      expect(app.ratingDistribution(aya()), [0, 0, 0, 1, 2]);
    });
  });

  // ============================================== 17. notifications
  group('17. rappels', () {
    test('pièce qui expire, demande qui arrive à échéance', () {
      now = DateTime(
        2030,
        1,
        1,
        9,
        45,
      ); // la demande de Jean expire à 9 h 40… celle du suivi à 9 h 15
      final titles = app.proReminders.map((r) => r.title).toList();
      expect(titles.first, contains('expire'));
    });
  });

  // ================================================== 18. incidents
  group('18. incidents', () {
    test('incident grave : l’équipe est alertée en urgence', () async {
      await app.reportIncident(
        category: IncidentCategory.insecurity,
        description: 'Menaces d’un voisin à l’arrivée chez la patiente.',
        booking: adjoua(),
      );
      expect(app.incidents.first.category, IncidentCategory.insecurity);
      expect(
        app.notifications.any(
          (n) => n.recipient == 'admin' && n.title.startsWith('Urgent'),
        ),
        isTrue,
      );
    });
  });
}
