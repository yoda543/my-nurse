import 'package:flutter_test/flutter_test.dart';
import 'package:mynurse/app_state.dart';
import 'package:mynurse/models.dart';

/// Horloge que les tests font avancer.
class Clock {
  DateTime now = DateTime(2030, 1, 1, 8);
  void advance(Duration d) => now = now.add(d);
}

final _day = DateTime(2030, 1, 10, 10);

void main() {
  late Clock clock;
  late AppState app;
  late Pro aya;
  CareService service(String id) => app.services.firstWhere((s) => s.id == id);

  Future<Booking> book({String s = 'pansement', DateTime? at, Pro? pro}) =>
      app.book(
        service: service(s),
        pro: pro ?? aya,
        commune: 'Cocody',
        address: 'Angré 8e tranche',
        scheduledAt: at ?? _day,
        hasPrescription: true,
      );

  CareLog log(Booking b) => CareLog(
    arrivedAt: b.scheduledAt,
    leftAt: b.scheduledAt.add(const Duration(minutes: 30)),
    acts: 'Soin réalisé',
  );

  setUp(() {
    clock = Clock();
    app = AppState(clock: () => clock.now);
    aya = app.pros.first;
  });

  group('règles pures', () {
    test(
      'pénalité d’annulation : gratuite à plus de 2 h, 50 % en deçà',
      () async {
        final at = DateTime(2030, 1, 10, 10);
        expect(
          lateCancellationFee(
            price: 8000,
            scheduledAt: at,
            now: DateTime(2030, 1, 10, 8),
          ),
          0,
        );
        expect(
          lateCancellationFee(
            price: 8000,
            scheduledAt: at,
            now: DateTime(2030, 1, 10, 8, 1),
          ),
          4000,
        );
      },
    );

    test('dates d’un suivi', () async {
      final first = DateTime(2030, 1, 30, 9);
      expect(sessionDates(first, Frequency.everyOtherDay, 3), [
        DateTime(2030, 1, 30, 9),
        DateTime(2030, 2, 1, 9),
        DateTime(2030, 2, 3, 9),
      ]);
      expect(
        sessionDates(first, Frequency.weekly, 2).last,
        DateTime(2030, 2, 6, 9),
      );
    });

    test('prolongation Premium depuis la fin ou depuis maintenant', () async {
      final now = DateTime(2030, 1, 1);
      expect(extendPremium(null, now, premiumPeriod), DateTime(2030, 1, 31));
      expect(
        extendPremium(DateTime(2030, 1, 11), now, premiumPeriod),
        DateTime(2030, 2, 10),
      );
      expect(
        extendPremium(DateTime(2029, 12, 1), now, premiumPeriod),
        DateTime(2030, 1, 31),
      );
    });
  });

  group('réservation', () {
    test('délai minimum d’1 h et maximum de 60 jours', () async {
      expect(
        () => book(at: clock.now.add(const Duration(minutes: 30))),
        throwsA(isA<BusinessRuleError>()),
      );
      expect(
        () => book(at: clock.now.add(const Duration(days: 61))),
        throwsA(isA<BusinessRuleError>()),
      );
      expect(
        (await book(at: clock.now.add(const Duration(hours: 2)))).status,
        BookingStatus.pending,
      );
    });

    test('pas de soin de nuit chez un soignant qui n’en fait pas', () async {
      final ibrahim = app.pros.firstWhere((p) => p.name == 'Ibrahim Traoré');
      expect(
        () => book(pro: ibrahim, at: DateTime(2030, 1, 10, 22)),
        throwsA(isA<BusinessRuleError>()),
      );
    });

    test('ordonnance obligatoire pour les actes techniques', () async {
      expect(
        () => app.book(
          service: service('injection'),
          pro: aya,
          commune: 'Cocody',
          address: 'Angré 8e tranche',
          scheduledAt: _day,
          hasPrescription: false,
        ),
        throwsA(isA<BusinessRuleError>()),
      );
    });

    test('pas de double réservation sur un créneau confirmé', () async {
      final first = await book(s: 'perfusion'); // 2 h : 10 h – 12 h
      await app.respond(first, accept: true);
      expect(
        () => book(at: _day.add(const Duration(hours: 1))),
        throwsA(isA<BusinessRuleError>()),
      );
      // Juste après, c'est possible.
      expect(
        await book(at: _day.add(const Duration(hours: 2))),
        isA<Booking>(),
      );
    });

    test('accepter deux demandes au même moment est refusé', () async {
      final a = await book();
      final b = await book(at: _day.add(const Duration(minutes: 30)));
      await app.respond(a, accept: true);
      expect(
        () => app.respond(b, accept: true),
        throwsA(isA<BusinessRuleError>()),
      );
      expect(b.status, BookingStatus.pending);
    });
  });

  group('délais', () {
    test('demande sans réponse en 2 h : annulée', () async {
      final b = await book();
      clock.advance(const Duration(hours: 1, minutes: 59));
      app.expireStale();
      expect(b.status, BookingStatus.pending);
      clock.advance(const Duration(minutes: 1));
      app.expireStale();
      expect(b.status, BookingStatus.cancelled);
      expect(
        () => app.respond(b, accept: true),
        throwsA(isA<BusinessRuleError>()),
      );
    });

    test('rendez-vous non payé 2 h après la confirmation : annulé', () async {
      final b = await book();
      await app.respond(b, accept: true);
      clock.advance(paymentWindow);
      expect(await app.pay(b, PaymentMethod.wave), isFalse);
      expect(b.status, BookingStatus.cancelled);
      expect(b.cancelReason, 'Non payé à temps');
    });

    test('le délai ne dépasse jamais l’heure du soin', () async {
      final b = await book(
        at: clock.now.add(const Duration(hours: 1, minutes: 30)),
      );
      expect(b.responseDeadline, b.scheduledAt);
    });

    test('compte rendu possible à partir de 30 min avant le soin', () async {
      final b = await book();
      await app.respond(b, accept: true);
      await app.pay(b, PaymentMethod.wave);
      expect(app.canLogCare(b), isFalse);
      expect(
        () => app.submitCareLog(b, log(b)),
        throwsA(isA<BusinessRuleError>()),
      );
      clock.now = _day.subtract(careLogEarliest);
      expect(app.canLogCare(b), isTrue);
      await app.submitCareLog(b, log(b));
      expect(b.status, BookingStatus.done);
      expect(b.receiptNumber, matches(RegExp(r'^MN-2030-\d{5}$')));
    });
  });

  group('annulation', () {
    Future<Booking> paid() async {
      final b = await book();
      await app.respond(b, accept: true);
      await app.pay(b, PaymentMethod.mtn);
      return b;
    }

    test('plus de 2 h avant : remboursement complet', () async {
      final b = await paid();
      final before = app.wallet.balance;
      expect(app.cancellationQuote(b).fee, 0);
      await app.cancel(b);
      expect(app.wallet.balance, before + b.price);
      expect(b.cancellationFee, 0);
    });

    test(
      'moins de 2 h avant : 50 % pour le soignant, commission déduite',
      () async {
        final b = await paid();
        clock.now = _day.subtract(const Duration(hours: 1));
        final wallet = app.wallet.balance;
        final pro = aya.wallet.balance;
        final q = app.cancellationQuote(b);
        expect(q.fee, 4000);
        expect(q.refund, 4000);
        await app.cancel(b);
        expect(app.wallet.balance, wallet + 4000);
        expect(aya.wallet.balance, pro + 4000 - 600);
        expect(app.refundTotal, greaterThanOrEqualTo(4000));
      },
    );

    test(
      'annulation par le soignant : remboursement complet et alerte',
      () async {
        final first = await paid();
        final before = app.wallet.balance;
        await app.cancelByPro(first, 'Malade');
        expect(app.wallet.balance, before + first.price);
        expect(aya.reliabilityAlert(clock.now), isFalse);

        final second = await book(at: _day.add(const Duration(days: 1)));
        await app.respond(second, accept: true);
        await app.cancelByPro(second, 'Imprévu');
        expect(aya.reliabilityAlert(clock.now), isTrue);

        clock.advance(const Duration(days: 31));
        expect(aya.reliabilityAlert(clock.now), isFalse);
      },
    );

    test('le soignant doit donner un motif', () async {
      final b = await paid();
      expect(() => app.cancelByPro(b, '  '), throwsA(isA<BusinessRuleError>()));
    });
  });

  group('suivi régulier', () {
    Future<Contract> contract({int sessions = 3}) => app.bookContract(
      service: service('pansement'),
      pro: aya,
      commune: 'Cocody',
      address: 'Angré 8e tranche',
      firstAt: _day,
      frequency: Frequency.daily,
      sessions: sessions,
      hasPrescription: false,
    );

    test('nombre de séances limité', () async {
      expect(() => contract(sessions: 1), throwsA(isA<BusinessRuleError>()));
      expect(() => contract(sessions: 31), throwsA(isA<BusinessRuleError>()));
    });

    test('commission réduite, acceptation et paiement en une fois', () async {
      app.loginPro(AppState.demoProPhone);
      final c = await contract();
      expect(c.sessions, hasLength(3));
      expect(c.sessions.first.commission, 800); // 10 % de 8 000
      expect(app.proRequests.where((b) => b.contract == c), hasLength(1));

      await app.respond(c.sessions.first, accept: true);
      expect(
        c.sessions.every((s) => s.status == BookingStatus.accepted),
        isTrue,
      );
      expect(app.amountDue(c.sessions.last), 24000);

      final before = app.wallet.balance;
      await app.topUp(24000, PaymentMethod.wave);
      expect(await app.pay(c.sessions[1], PaymentMethod.wallet), isTrue);
      expect(app.wallet.balance, before);
      expect(c.sessions.every((s) => s.readyForCare), isTrue);
    });

    test(
      'chaque séance terminée crédite le soignant ; le reste est remboursé',
      () async {
        final c = await contract();
        await app.respond(c.sessions.first, accept: true);
        await app.pay(c.sessions.first, PaymentMethod.orange);

        clock.now = _day;
        final pro = aya.wallet.balance;
        await app.submitCareLog(c.sessions.first, log(c.sessions.first));
        expect(aya.wallet.balance, pro + 7200);

        final before = app.wallet.balance;
        final q = app.cancellationQuote(c.sessions.first);
        expect(q.sessions, 2);
        expect(q.refund, 16000);
        await app.cancel(c.sessions[1]);
        expect(app.wallet.balance, before + 16000);
        expect(c.doneCount, 1);
      },
    );

    test('un créneau déjà pris bloque tout le suivi', () async {
      final other = await book(at: _day.add(const Duration(days: 1)));
      await app.respond(other, accept: true);
      expect(() => contract(), throwsA(isA<BusinessRuleError>()));
    });
  });

  group('Pro Premium et parrainage', () {
    test(
      'abonnement payé avec le solde, refusé s’il est insuffisant',
      () async {
        final before = aya.wallet.balance;
        await app.subscribePremium(aya);
        expect(aya.wallet.balance, before - premiumPrice);
        expect(aya.premiumUntil, clock.now.add(premiumPeriod));
        expect(app.premiumRevenue, premiumPrice);

        final koffi = app.pros.firstWhere((p) => p.type == ProType.kine);
        expect(
          () => app.subscribePremium(koffi),
          throwsA(isA<BusinessRuleError>()),
        );
      },
    );

    test('les Pro Premium apparaissent en tête', () async {
      final pansement = service('pansement');
      final ibrahim = app.pros.firstWhere((p) => p.name == 'Ibrahim Traoré');
      // Ibrahim (4,7) est Premium dans la démo, Aya (4,9) non.
      expect(app.prosFor(pansement, 'Cocody').first, ibrahim);
      ibrahim.premiumUntil = null;
      expect(app.prosFor(pansement, 'Cocody').first, aya);
    });

    test('parrainage : un mois offert au parrain, une seule fois', () async {
      final filleule = app.pros.firstWhere(
        (p) => p.name == 'Bernadette Ouattara',
      );
      expect(filleule.referredBy, aya);
      await app.verifyPro(filleule);
      expect(aya.premiumUntil, clock.now.add(referralBonus));
      await app.suspendPro(filleule, 'Test');
      await app.verifyPro(filleule);
      expect(aya.premiumUntil, clock.now.add(referralBonus));
    });

    test('code de parrainage inconnu refusé à l’inscription', () async {
      expect(
        () => app.registerPro(
          name: 'Test',
          phone: '0102030405',
          type: ProType.infirmier,
          communes: ['Cocody'],
          prices: {'pansement': 7000},
          yearsExperience: 1,
          bio: 'Bio',
          orderNumber: 'ONII',
          nightAvailable: false,
          documents: requiredDocs(ProType.infirmier).toSet(),
          referralCode: 'XYZ-99',
        ),
        throwsA(isA<BusinessRuleError>()),
      );
      final p = await app.registerPro(
        name: 'Test',
        phone: '0102030405',
        type: ProType.infirmier,
        communes: ['Cocody'],
        prices: {'pansement': 7000},
        yearsExperience: 1,
        bio: 'Bio',
        orderNumber: 'ONII',
        nightAvailable: false,
        documents: requiredDocs(ProType.infirmier).toSet(),
        referralCode: aya.referralCode.toLowerCase(),
      );
      expect(p.referredBy, aya);
    });
  });

  group('comptes et notifications', () {
    test('se reconnecter à un compte créé, sans en recréer un', () async {
      app.signUpDemo('0722222222', UserRole.patient);
      expect(app.needsProfile, isTrue);
      await app.completeProfile('Yao Kouadio');
      final id = app.account!.id;
      app.logout();
      expect(
        () => app.signUpDemo('0722222222', UserRole.patient),
        throwsA(isA<BusinessRuleError>()),
      );
      app.loginDemo('0722222222');
      expect(app.role, UserRole.patient);
      expect(app.account!.id, id);
      expect(app.patientName, 'Yao Kouadio');
      // Ses données ne se mélangent pas avec celles d'Awa.
      expect(app.patientBookings, isEmpty);
      expect(app.wallet.balance, 0);
    });

    test('un numéro inconnu ne crée pas de compte à la connexion', () {
      expect(
        () => app.loginDemo('0799999999'),
        throwsA(isA<BusinessRuleError>()),
      );
      expect(app.role, isNull);
    });

    test('le rôle vient du compte', () {
      app.loginDemo(AppState.demoProPhone);
      expect(app.role, UserRole.pro);
      app.logout();
      app.loginDemo(AppState.demoAdminPhone);
      expect(app.role, UserRole.admin);
    });

    test('chaque étape notifie la bonne personne', () async {
      app.loginDemo(AppState.demoPatientPhone);
      final b = await book();
      app.logout();
      app.loginDemo(AppState.demoProPhone);
      final forPro = app.myNotifications.first;
      expect(forPro.title, 'Nouvelle demande de soin');
      expect(forPro.read, isFalse);
      await app.respond(b, accept: true);
      app.logout();

      app.loginDemo(AppState.demoPatientPhone);
      expect(
        app.myNotifications.first.title,
        '${aya.name} a confirmé votre soin',
      );
      await app.pay(b, PaymentMethod.wallet);
      app.logout();

      app.loginDemo(AppState.demoProPhone);
      expect(app.myNotifications.first.title, 'Paiement reçu');
      clock.now = _day;
      await app.submitCareLog(b, log(b));
      app.logout();

      app.loginDemo(AppState.demoPatientPhone);
      final last = app.myNotifications.first;
      expect(last.title, 'Compte rendu disponible');
      expect(last.booking, b);
      final unread = app.unreadCount;
      await app.markRead(last);
      expect(app.unreadCount, unread - 1);
      await app.markAllRead();
      expect(app.unreadCount, 0);
    });

    test('un suivi ne notifie qu’une fois', () async {
      await app.bookContract(
        service: service('pansement'),
        pro: aya,
        commune: 'Cocody',
        address: 'Angré 8e tranche',
        firstAt: _day,
        frequency: Frequency.daily,
        sessions: 4,
        hasPrescription: false,
      );
      app.loginDemo(AppState.demoProPhone);
      expect(
        app.myNotifications.where(
          (n) => n.title == 'Nouveau suivi demandé' && n.at == clock.now,
        ),
        hasLength(1),
      );
    });
  });
}
