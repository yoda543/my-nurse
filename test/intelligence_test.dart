import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mynurse/app_state.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:mynurse/intelligence/admin_insights.dart';
import 'package:mynurse/intelligence/assistant/assistant.dart';
import 'package:mynurse/intelligence/assistant/pro_tools.dart';
import 'package:mynurse/intelligence/assistant/safety.dart';
import 'package:mynurse/intelligence/matching.dart';
import 'package:mynurse/screens/assistant_screen.dart';
import 'package:mynurse/main.dart';
import 'package:mynurse/models.dart';

/// Services intelligents : mise en relation, assistant, intelligence
/// administrative.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late DateTime now;
  late AppState app;
  setUp(() {
    now = DateTime(2030, 1, 1, 8);
    app = AppState(clock: () => now)..loginDemo(AppState.demoPatientPhone);
  });

  CareService svc(String id) => app.services.firstWhere((s) => s.id == id);
  Pro pro(String id) => app.pros.firstWhere((p) => p.id == id);
  List<Recommendation> rec(
    String service,
    String commune, {
    DateTime? at,
    Patient? patient,
  }) => const MatchingEngine().recommend(
    request: MatchRequest(
      service: svc(service),
      commune: commune,
      at: at,
      patient: patient,
    ),
    pros: app.pros,
    bookings: app.bookings,
    now: now,
  );

  group('mise en relation', () {
    test('qualification : seuls les soignants vérifiés qui font ce soin', () {
      final r = rec('pansement', 'Cocody');
      expect(r.every((x) => x.pro.type == ProType.infirmier), isTrue);
      expect(r.every((x) => x.pro.activeAt(now)), isTrue);
      expect(rec('kine', 'Cocody').single.pro.type, ProType.kine);
      expect(rec('kine', 'Yopougon'), isEmpty); // pas de kiné à domicile ici
    });

    test('continuité des soins : le soignant qui connaît déjà le patient', () {
      final awa = app.patients.first;
      final r = rec('pansement', 'Cocody', patient: awa);
      expect(r.first.pro.id, 'pro1');
      expect(r.first.reasons, contains('A déjà soigné Awa (1 soin)'));
    });

    test('Premium ne donne aucune priorité', () {
      final with_ = rec(
        'pansement',
        'Cocody',
      ).map((r) => (r.pro.id, r.score)).toList();
      pro('pro2').premiumUntil = null;
      final without = rec(
        'pansement',
        'Cocody',
      ).map((r) => (r.pro.id, r.score)).toList();
      expect(with_, without);
    });

    test('disponibilité réelle à l’heure demandée', () {
      // Aya a un soin confirmé à 8 h aujourd'hui (Adjoua) : exclue à 8 h 15.
      final at = DateTime(2030, 1, 1, 9);
      final busy = DateTime(now.year, now.month, now.day, now.hour, 15);
      expect(
        rec('injection', 'Cocody', at: busy).map((r) => r.pro.id),
        isNot(contains('pro1')),
      );
      expect(
        rec(
          'injection',
          'Cocody',
          at: at.add(const Duration(days: 2)),
        ).map((r) => r.pro.id),
        contains('pro1'),
      );
      // Jour d'absence déclaré.
      pro('pro2').daysOff.add((
        from: DateTime(2030, 1, 3),
        to: DateTime(2030, 1, 4),
        reason: 'Congé',
      ));
      expect(
        rec(
          'pansement',
          'Cocody',
          at: DateTime(2030, 1, 3, 10),
        ).map((r) => r.pro.id),
        isNot(contains('pro2')),
      );
    });

    test('la nuit : seulement ceux qui se déplacent la nuit', () {
      final r = rec('pansement', 'Cocody', at: DateTime(2030, 1, 4, 22));
      expect(r.every((x) => x.pro.nightAvailable), isTrue);
      expect(r.first.reasons, contains('Se déplace la nuit'));
    });

    test('note bayésienne : 2 avis parfaits ne battent pas 40 très bons', () {
      final a = pro('pro1'); // 4,9 sur 41 avis
      final b = pro('pro2')
        ..rating = 5
        ..ratingCount = 2;
      final r = rec('pansement', 'Cocody');
      double ratingOf(Pro p) => r
          .firstWhere((x) => x.pro == p)
          .factors
          .firstWhere((f) => f.label == 'Avis des patients')
          .score;
      expect(ratingOf(a), greaterThan(ratingOf(b)));
    });

    test('distance indicative entre communes', () {
      final d = distanceKm(
        communeCenters['Cocody']!,
        communeCenters['Yopougon']!,
      );
      expect(d, inInclusiveRange(8, 12));
    });

    test('la recherche « recommandés » suit le moteur et explique', () {
      final r = app.searchPros(
        const SearchFilters(commune: 'Cocody', serviceId: 'pansement'),
        patient: app.patients.first,
      );
      expect(r.first.pro.id, 'pro1');
      expect(r.first.score, isNotNull);
      expect(r.first.reasons, isNotEmpty);
    });
  });

  group('assistant : garde-fous', () {
    final assistant = MyNurseAssistant();
    AssistantContext ctx(AssistantRole role) => assistantContextFor(app, role);

    test('urgence vitale : SAMU, rien d’autre', () async {
      final r = await assistant.ask(
        'Ma mère ne respire plus bien, que faire ?',
        ctx(AssistantRole.patient),
      );
      expect(r.kind, ReplyKind.emergency);
      expect(r.text, contains('185'));
    });

    test('jamais de diagnostic ni de médicament', () async {
      for (final q in [
        'Quel médicament donner pour la fièvre ?',
        'Est-ce grave si la plaie est rouge ?',
        'Je peux prendre du paracétamol avec mon traitement ?',
        'Combien de mg d’amoxicilline ?',
      ]) {
        final r = await assistant.ask(q, ctx(AssistantRole.patient));
        expect(r.kind, ReplyKind.refusal, reason: q);
        expect(r.text, contains('professionnel de santé'), reason: q);
      }
    });

    test('données de santé : détectées, masquées, jamais envoyées sans base légale', () {
      const guard = HealthDataGuard();
      const q = 'Mariam Bamba, diabétique, tension 16/9, appelez le 0711223344';
      expect(guard.containsHealthData(q), isTrue);
      final red = guard.redact(q, knownNames: ['Mariam Bamba']);
      expect(red, isNot(contains('Mariam')));
      expect(red, isNot(contains('0711223344')));
      expect(red, isNot(contains('16/9')));
      expect(
        const AiDataPolicy().mayTransmit(red, containsHealth: false),
        isFalse,
      );
      expect(
        const AiDataPolicy(
          externalEnabled: true,
          processorAgreement: true,
        ).mayTransmit(red, containsHealth: true),
        isFalse,
      );
    });

    test('un service externe n’est jamais appelé sans autorisation', () async {
      var called = false;
      final external = MyNurseAssistant(
        backend: GuardedExternalAssistant(
          policy: const AiDataPolicy(
            externalEnabled: true,
            processorAgreement: true,
          ),
          send: (_) async {
            called = true;
            return 'réponse';
          },
        ),
      );
      await external.ask(
        'Comment soigner la plaie diabétique de ma mère ?',
        ctx(AssistantRole.patient),
      );
      expect(called, isFalse);
    });
  });

  group('assistant : aide', () {
    final assistant = MyNurseAssistant();
    AssistantContext ctx(AssistantRole role) => assistantContextFor(app, role);

    test('trouver un soignant : recommandations expliquées', () async {
      final r = await assistant.ask(
        'Je cherche une infirmière à Cocody pour un pansement',
        ctx(AssistantRole.patient),
      );
      expect(r.text, contains('Aya Kouamé'));
      expect(r.text, contains('jamais selon un abonnement'));
      expect(r.actions.single.destination, AssistantDestination.search);
      expect(r.actions.single.service?.id, 'pansement');
    });

    test('questions d’usage et administratives', () async {
      final family = await assistant.ask(
        'Comment réserver pour ma mère ?',
        ctx(AssistantRole.patient),
      );
      expect(family.actions.single.destination, AssistantDestination.family);
      final cancel = await assistant.ask(
        'Comment annuler ?',
        ctx(AssistantRole.patient),
      );
      expect(cancel.text, contains('gratuite'));
      final pay = await assistant.ask(
        'Comment payer avec Wave ?',
        ctx(AssistantRole.patient),
      );
      expect(pay.actions.single.destination, AssistantDestination.wallet);
    });

    test('éducation à la santé : générale et sourcée', () async {
      final r = await assistant.ask(
        'Comment se protéger du paludisme ?',
        ctx(AssistantRole.patient),
      );
      expect(r.kind, ReplyKind.education);
      expect(r.source, contains('OMS'));
      expect(r.text, contains('ne remplace pas l’avis'));
    });

    test('soignant : organiser la journée', () async {
      app.loginDemo(AppState.demoProPhone);
      final r = await assistant.ask(
        'Organise ma journée',
        ctx(AssistantRole.pro),
      );
      expect(r.text, contains('Adjoua Brou'));
      expect(r.actions.single.destination, AssistantDestination.proAgenda);
    });

    test('compte rendu : les notes du soignant rangées, rien d’inventé', () {
      final d = structureCareNotes(
        'TA 13/8. T° 37,5. Pansement refait au pied gauche. Plaie propre, '
        'peu de suintement. Revoir dans 2 jours. Je pense que c’est une infection.',
      );
      expect(d.bloodPressure, '13/8');
      expect(d.temperature, '37,5');
      expect(d.acts, contains('Pansement refait au pied gauche'));
      expect(d.observations, contains('Plaie propre'));
      expect(d.followUp, contains('Revoir dans 2 jours'));
      expect(d.toReview.single, contains('Je pense que'));
    });

    test('journée serrée : trajet signalé', () {
      final cocody = app.bookings.firstWhere(
        (b) => b.patient.name == 'Adjoua Brou',
      );
      final plan = organizeDay([cocody], now);
      expect(plan.steps, hasLength(1));
      expect(plan.tips, isNotEmpty);
    });
  });

  group('intelligence administrative', () {
    const engine = AdminInsightsEngine();
    final t0 = DateTime(2030, 1, 1, 8);
    BookingFact b(
      String id, {
      String owner = 'A9',
      String pro = 'pro1',
      DateTime? created,
      DateTime? at,
      String status = 'done',
      CancelledBy? by,
      int price = 10000,
      bool paid = true,
      int refund = 0,
      int? rating,
      String commune = 'Cocody',
    }) => BookingFact(
      id: id,
      ownerId: owner,
      proId: pro,
      proName: pro == 'pro1' ? 'Aya Kouamé' : 'Autre',
      commune: commune,
      serviceName: 'Pansement',
      createdAt: created ?? t0.subtract(const Duration(days: 2)),
      scheduledAt: at ?? t0.subtract(const Duration(days: 1)),
      status: status,
      cancelledBy: by,
      price: price,
      paid: paid,
      refundAmount: refund,
      rating: rating,
    );

    test(
      'annulations répétées et remboursements élevés, preuves à l’appui',
      () {
        final list = [
          for (var i = 0; i < 3; i++)
            b(
              'c$i',
              status: 'cancelled',
              by: CancelledBy.patient,
              refund: 10000,
              created: t0.subtract(Duration(days: 3 + 2 * i)),
            ),
          b('d1'),
        ];
        final alerts = engine.suspiciousActivity(
          now: t0,
          bookings: list,
          accounts: const [],
          complaints: const [],
        );
        final codes = alerts.map((a) => a.code).toSet();
        expect(codes, containsAll(['patient_cancellations', 'refund_share']));
        final c = alerts.firstWhere((a) => a.code == 'patient_cancellations');
        expect(c.evidence, hasLength(3));
        expect(c.suggestedCheck, isNotEmpty);
      },
    );

    test('soignant qui annule souvent, réservé depuis son propre numéro', () {
      final alerts = engine.suspiciousActivity(
        now: t0,
        bookings: [b('s1', owner: 'A7')],
        accounts: const [
          AccountFact(
            id: 'A7',
            kind: AccountKind.patient,
            name: 'X',
            phone: '+225 05 00 00 00 00',
          ),
          AccountFact(
            id: 'pro1',
            kind: AccountKind.pro,
            name: 'Aya Kouamé',
            phone: '0500000000',
          ),
        ],
        complaints: const [],
        proCancellations: {
          'pro1': [for (var i = 1; i <= 3; i++) t0.subtract(Duration(days: i))],
        },
      );
      expect(alerts.first.code, 'self_booking'); // prioritaire en tête
      expect(alerts.first.severity, InsightSeverity.high);
      expect(alerts.map((a) => a.code), contains('pro_cancellations'));
    });

    test(
      'rafale de réservations ; un suivi créé d’un coup ne compte qu’une fois',
      () {
        final burst = [
          for (var i = 0; i < 4; i++)
            b(
              'r$i',
              pro: 'pro$i',
              created: t0.subtract(Duration(hours: i * 3)),
            ),
        ];
        expect(
          engine
              .suspiciousActivity(
                now: t0,
                bookings: burst,
                accounts: const [],
                complaints: const [],
              )
              .map((a) => a.code),
          contains('booking_burst'),
        );
        final contract = [
          for (var i = 0; i < 10; i++)
            b(
              'k$i',
              created: t0.subtract(const Duration(hours: 1)),
              at: t0.add(Duration(days: i)),
            ),
        ];
        expect(
          engine
              .suspiciousActivity(
                now: t0,
                bookings: contract,
                accounts: const [],
                complaints: const [],
              )
              .map((a) => a.code),
          isNot(contains('booking_burst')),
        );
      },
    );

    test('pic inhabituel de réservations', () {
      final list = <BookingFact>[];
      var n = 0;
      for (var d = 1; d <= 40; d++) {
        final day = DateTime(2030, 1, d, 9);
        final count = d == 35 ? 12 : (d.isEven ? 2 : 1);
        for (var i = 0; i < count; i++) {
          list.add(
            b(
              'p${n++}',
              owner: 'O$n',
              created: day,
              commune: d == 35 ? 'Yopougon' : 'Cocody',
            ),
          );
        }
      }
      final a = engine.bookingAnomalies(
        list,
        DateTime(2030, 1, 30),
        DateTime(2030, 2, 10),
      );
      expect(a, hasLength(1));
      expect(a.single.day, DateTime(2030, 2, 4));
      expect(a.single.topCommune, 'Yopougon');
    });

    test(
      'comptes en double : numéro, nom, mais pas un soignant aussi patient',
      () {
        final groups = engine.duplicateAccounts(const [
          AccountFact(
            id: 'A1',
            kind: AccountKind.patient,
            name: 'Awa Bamba',
            phone: '0700000000',
          ),
          AccountFact(
            id: 'A5',
            kind: AccountKind.patient,
            name: 'A. B.',
            phone: '+225 07 00 00 00 00',
          ),
          AccountFact(
            id: 'A6',
            kind: AccountKind.patient,
            name: 'Bamba Awa',
            phone: '0102030405',
          ),
          AccountFact(
            id: 'pro9',
            kind: AccountKind.pro,
            name: 'Moussa T',
            phone: '0711111111',
          ),
          AccountFact(
            id: 'A8',
            kind: AccountKind.patient,
            name: 'Moussa T',
            phone: '0711111111',
          ),
        ]);
        expect(groups.first.reason, 'Même numéro de téléphone');
        expect(groups.first.accounts.map((a) => a.id), ['A1', 'A5']);
        expect(groups.any((g) => g.reason.startsWith('Même nom')), isTrue);
        expect(
          groups.any((g) => g.accounts.any((a) => a.id == 'pro9')),
          isFalse,
        );
        expect(normalizeName('Dr Koné Ibrahim'), 'ibrahim kone');
      },
    );

    test('analyse des retours : sentiment, sujets, négation', () {
      expect(AdminInsightsEngine.sentiment('Très douce et ponctuelle'), 1);
      expect(
        AdminInsightsEngine.sentiment('Pas ponctuel du tout', rating: 3),
        -1,
      );
      final f = engine.analyzeFeedback(
        now: t0,
        reviews: [
          ReviewFact(
            proId: 'p',
            proName: 'Aya',
            rating: 5,
            text: 'Très douce, ponctuelle',
            at: t0,
          ),
          ReviewFact(
            proId: 'p',
            proName: 'Aya',
            rating: 2,
            text: 'Une heure de retard',
            at: t0,
          ),
        ],
        complaints: [
          ComplaintFact(
            category: 'Retard',
            text: 'Arrivé en retard',
            createdAt: t0,
          ),
        ],
      );
      final punct = f.topics.firstWhere((t) => t.topic == 'Ponctualité');
      expect(punct.mentions, 3);
      expect(punct.negative, 2);
      expect(f.complaintsByCategory, {'Retard': 1});
      expect(f.averageRating, 3.5);
    });

    test('démo : rapport complet, sans aucune donnée médicale', () {
      app.loginDemo(AppState.demoAdminPhone);
      final r = app.adminInsights(Period.lastDays(now, 30));
      expect(r.text, contains('RAPPORT D’ACTIVITÉ'));
      expect(r.feedback.reviewCount, greaterThan(0));
      final all = [
        r.text,
        for (final a in r.alerts) ...[a.detail, ...a.evidence],
        for (final t in r.feedback.topics) ...t.examples,
      ].join(' ');
      for (final medical in [
        'Pénicilline',
        'Metformine',
        'Hypertension',
        'diabète de type',
        'prostate',
      ]) {
        expect(all, isNot(contains(medical)));
      }
    });

    testWidgets('module Intelligence dans la console', (tester) async {
      app.loginDemo(AppState.demoAdminPhone);
      tester.view.physicalSize = const Size(1400, 2400) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MyNurseApp(state: app));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intelligence').first);
      await tester.pumpAndSettle();
      expect(find.text('Activité suspecte'), findsOneWidget);
      expect(find.text('Comptes en double possibles'), findsWidgets);
      expect(find.textContaining('aucune donnée médicale'), findsOneWidget);
    });
  });
}
