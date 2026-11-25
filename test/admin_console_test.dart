import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mynurse/app_state.dart';
import 'package:mynurse/main.dart';
import 'package:mynurse/models.dart';

/// Console d'administration (données de démonstration).
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late DateTime now;
  late AppState app;
  const principal = AppState.demoAdminPhone; // tous droits sauf urgence
  const support = '0100000002';
  const coordinator = '0100000003'; // accès d'urgence

  setUp(() {
    now = DateTime(2030, 1, 1, 8);
    app = AppState(clock: () => now)..loginDemo(principal);
  });

  Period month() => Period.lastDays(now, 30);
  Patient mariam() =>
      app.accounts.first.patients.firstWhere((p) => p.name == 'Mariam Bamba');
  Booking paidVisit() => app.bookings.firstWhere(
    (b) => b.patient.name == 'Mariam Bamba' && b.readyForCare,
  );

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(420, 2400),
  }) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MyNurseApp(state: app));
    await tester.pumpAndSettle();
  }

  group('indicateurs', () {
    test('les 11 indicateurs du tableau de bord', () {
      final m = app.adminMetrics(month());
      expect(m.patients, greaterThanOrEqualTo(6));
      expect(m.verifiedPros, 7);
      expect(m.pendingVerifications, 1); // Bernadette
      expect(m.appointments, greaterThan(0));
      expect(m.completed, 1);
      expect(m.volume, 8000);
      expect(m.commissions, 800);
      expect(m.proEarnings, 7200);
      expect(m.responseMinutes, isNotNull);
      expect(m.cancelled, 0);
    });

    test('le filtre de dates change les chiffres', () {
      final week = Period.lastDays(now, 2);
      expect(app.adminMetrics(week).completed, 0);
      expect(app.adminMetrics(month()).completed, 1);
    });

    test('export du rapport : CSV lisible par Excel, inscrit au journal', () {
      final csv = app.adminReportCsv(month());
      expect(csv.split('\n').first, 'Indicateur;Valeur');
      expect(csv, contains('Commissions MyNurse (FCFA);800'));
      expect(app.adminLog.first.action, 'Export');
    });
  });

  group('permissions par rôle', () {
    test('l’agent support ne touche pas aux finances', () async {
      app.loginDemo(support);
      expect(app.hasAdminPerm(AdminPermission.finance), isFalse);
      await expectLater(
        app.adminRefund(paidVisit(), 1000, 'Geste commercial'),
        throwsA(isA<BusinessRuleError>()),
      );
      await expectLater(
        app.verifyPro(app.verificationQueue.first),
        throwsA(isA<BusinessRuleError>()),
      );
    });

    test('personne ne s’attribue l’accès d’urgence', () async {
      final me = app.adminMe!;
      await expectLater(
        app.setStaffPermission(me, AdminPermission.medicalBreakGlass, true),
        throwsA(isA<BusinessRuleError>()),
      );
      final agent = app.staff.firstWhere((m) => m.phone == support);
      await app.setStaffPermission(agent, AdminPermission.finance, true);
      expect(agent.permissions, contains(AdminPermission.finance));
      expect(app.adminLog.first.action, 'Permission attribuée');
    });

    testWidgets('chacun ne voit que ses modules', (tester) async {
      app.loginDemo(support);
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Ouvrir le menu de navigation'));
      await tester.pumpAndSettle();
      expect(find.text('Réclamations'), findsOneWidget);
      expect(find.text('Rendez-vous'), findsWidgets);
      expect(find.text('Finances'), findsNothing);
      expect(find.text('Journal d’activité'), findsNothing);
      expect(find.text('Équipe et droits'), findsNothing);
    });
  });

  group('dossier médical : jamais sans motif légitime', () {
    test('aucun accès par défaut, même pour l’admin principal', () async {
      expect(app.adminChart(mariam()), isNull);
      await expectLater(
        app.adminBreakGlass(mariam(), 'Vérification de routine du dossier'),
        throwsA(isA<BusinessRuleError>()),
      );
    });

    test(
      'accès d’urgence : motif détaillé, 4 h, journalisé, famille prévenue',
      () async {
        app.loginDemo(coordinator);
        await expectLater(
          app.adminBreakGlass(mariam(), 'urgent'),
          throwsA(isA<BusinessRuleError>()),
        );
        final chart = await app.adminBreakGlass(
          mariam(),
          'Appel du SAMU : patiente inconsciente, allergies demandées',
        );
        expect(chart.allergies, 'Pénicilline');
        expect(app.adminLog.first.patientId, mariam().id);
        expect(
          app.notifications.any(
            (n) =>
                n.recipient == 'A1' &&
                n.title == 'Accès d’urgence à un dossier',
          ),
          isTrue,
        );
        now = now.add(const Duration(hours: 5));
        expect(app.adminChart(mariam()), isNull);
      },
    );

    testWidgets('fiche patient : identité et activité seulement', (
      tester,
    ) async {
      app.loginDemo(support);
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Ouvrir le menu de navigation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Patients'));
      await tester.pumpAndSettle();
      expect(find.textContaining('sans données médicales'), findsOneWidget);
      await tester.tap(find.text('Mariam Bamba').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Pénicilline'), findsNothing);
      expect(find.textContaining('Non accessible à l’équipe'), findsOneWidget);
      expect(
        find.textContaining('pas la permission d’accès d’urgence'),
        findsOneWidget,
      );
    });
  });

  group('actions de l’équipe (journalisées)', () {
    test('annulation d’un rendez-vous payé : remboursement intégral', () async {
      final b = paidVisit();
      final wallet = app.accounts.first.wallet.balance;
      await app.adminCancelBooking(b, 'Soignant hospitalisé');
      expect(b.status, BookingStatus.cancelled);
      expect(app.accounts.first.wallet.balance, wallet + b.price);
      expect(app.adminLog.first.action, 'Rendez-vous annulé');
    });

    test('remboursement partiel puis plafonné', () async {
      final b = paidVisit();
      await app.adminRefund(b, 2000, 'Retard important');
      expect(b.refundAmount, 2000);
      await expectLater(
        app.adminRefund(b, b.price, 'Trop'),
        throwsA(isA<BusinessRuleError>()),
      );
    });

    test('réclamation traitée avec geste commercial', () async {
      final c = app.complaints.first;
      final wallet = app.accounts.first.wallet.balance;
      await app.adminUpdateComplaint(
        c,
        ComplaintStatus.resolved,
        resolution: 'Excuses présentées, soignante avertie.',
        refund: 1500,
      );
      expect(c.status, ComplaintStatus.resolved);
      expect(app.accounts.first.wallet.balance, wallet + 1500);
    });

    test('incident, pharmacie, message, commission', () async {
      final i = app.incidents.first;
      await app.adminUpdateIncident(i, 'Traité', 'Stock commandé.');
      expect(i.status, 'Traité');

      await app.adminSavePharmacy(
        const Pharmacy(
          id: 'ph9',
          name: 'Pharmacie Test',
          commune: 'Plateau',
          address: 'Rue 12',
        ),
      );
      expect(app.pharmacies.any((p) => p.name == 'Pharmacie Test'), isTrue);

      final n = await app.adminBroadcast(
        BroadcastAudience.pros,
        'Formation',
        'Atelier gestes d’urgence samedi.',
      );
      expect(n, app.pros.where((p) => p.activeAt(now)).length);

      await app.adminSetCommission(0.12);
      app.loginDemo(AppState.demoPatientPhone);
      final b = await app.book(
        service: app.services.firstWhere((s) => s.id == 'pansement'),
        pro: app.pros.first,
        commune: 'Cocody',
        address: 'Angré 8e tranche',
        scheduledAt: DateTime(2030, 1, 4, 10),
        hasPrescription: false,
      );
      expect(b.commissionRate, 0.12);
    });

    test('recherche et filtres', () {
      expect(
        app.adminUsers('koffi').map((u) => u.name),
        contains('Koffi Bamba'),
      );
      expect(
        app.adminPros('', status: VerificationStatus.pending).single.name,
        'Bernadette Ouattara',
      );
      expect(
        app
            .adminBookings(month(), query: 'mariam')
            .every((b) => b.patientName == 'Mariam Bamba'),
        isTrue,
      );
    });
  });

  group('interface', () {
    testWidgets('tableau de bord sur téléphone : indicateurs et files', (
      tester,
    ) async {
      await pumpApp(tester);
      for (final label in [
        'Patients inscrits',
        'Soignants vérifiés',
        'Vérifications en attente',
        'Rendez-vous',
        'Soins réalisés',
        'Annulés ou refusés',
        'Volume des transactions',
        'Commissions MyNurse',
        'Gains des soignants',
        'Délai moyen de réponse',
        'Satisfaction',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Dossiers à vérifier'), findsOneWidget);
      expect(find.text('30 derniers jours'), findsOneWidget);
    });

    testWidgets('grand écran : menu latéral permanent', (tester) async {
      await pumpApp(tester, size: const Size(1366, 1600));
      expect(find.text('MyNurse Admin'), findsOneWidget);
      expect(find.text('Statistiques'), findsOneWidget);
      await tester.tap(find.text('Journal d’activité'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Soignant validé'), findsOneWidget);
    });

    testWidgets('export depuis les rendez-vous', (tester) async {
      await pumpApp(tester, size: const Size(1366, 1600));
      await tester.tap(find.text('Rendez-vous').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exporter'));
      await tester.pumpAndSettle();
      expect(find.textContaining('format CSV'), findsOneWidget);
      expect(find.text('Copier'), findsOneWidget);
    });
  });
}
