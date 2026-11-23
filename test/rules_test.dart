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

  Booking book({String s = 'pansement', DateTime? at, Pro? pro}) => app.book(
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
    test('pénalité d’annulation : gratuite à plus de 2 h, 50 % en deçà', () {
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
    });

    test('dates d’un suivi', () {
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

    test('prolongation Premium depuis la fin ou depuis maintenant', () {
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
    test('délai minimum d’1 h et maximum de 60 jours', () {
      expect(
        () => book(at: clock.now.add(const Duration(minutes: 30))),
        throwsA(isA<BusinessRuleError>()),
      );
      expect(
        () => book(at: clock.now.add(const Duration(days: 61))),
        throwsA(isA<BusinessRuleError>()),
      );
      expect(
        book(at: clock.now.add(const Duration(hours: 2))).status,
        BookingStatus.pending,
      );
    });

    test('pas de soin de nuit chez un soignant qui n’en fait pas', () {
      final ibrahim = app.pros.firstWhere((p) => p.name == 'Ibrahim Traoré');
      expect(
        () => book(pro: ibrahim, at: DateTime(2030, 1, 10, 22)),
        throwsA(isA<BusinessRuleError>()),
      );
    });

    test('ordonnance obligatoire pour les actes techniques', () {
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

    test('pas de double réservation sur un créneau confirmé', () {
      final first = book(s: 'perfusion'); // 2 h : 10 h – 12 h
      app.respond(first, accept: true);
      expect(
        () => book(at: _day.add(const Duration(hours: 1))),
        throwsA(isA<BusinessRuleError>()),
      );
      // Juste après, c'est possible.
      expect(book(at: _day.add(const Duration(hours: 2))), isA<Booking>());
    });

    test('accepter deux demandes au même moment est refusé', () {
      final a = book();
      final b = book(at: _day.add(const Duration(minutes: 30)));
      app.respond(a, accept: true);
      expect(
        () => app.respond(b, accept: true),
        throwsA(isA<BusinessRuleError>()),
      );
      expect(b.status, BookingStatus.pending);
    });
  });

  group('délais', () {
    test('demande sans réponse en 2 h : annulée', () {
      final b = book();
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

    test('rendez-vous non payé 2 h après la confirmation : annulé', () {
      final b = book();
      app.respond(b, accept: true);
      clock.advance(paymentWindow);
      expect(app.pay(b, PaymentMethod.wave), isFalse);
      expect(b.status, BookingStatus.cancelled);
      expect(b.cancelReason, 'Non payé à temps');
    });

    test('le délai ne dépasse jamais l’heure du soin', () {
      final b = book(at: clock.now.add(const Duration(hours: 1, minutes: 30)));
      expect(b.responseDeadline, b.scheduledAt);
    });

    test('compte rendu possible à partir de 30 min avant le soin', () {
      final b = book();
      app.respond(b, accept: true);
      app.pay(b, PaymentMethod.wave);
      expect(app.canLogCare(b), isFalse);
      expect(
        () => app.submitCareLog(b, log(b)),
        throwsA(isA<BusinessRuleError>()),
      );
      clock.now = _day.subtract(careLogEarliest);
      expect(app.canLogCare(b), isTrue);
      app.submitCareLog(b, log(b));
      expect(b.status, BookingStatus.done);
      expect(b.receiptNumber, matches(RegExp(r'^MN-2030-\d{5}$')));
    });
  });

  group('annulation', () {
    Booking paid() {
      final b = book();
      app.respond(b, accept: true);
      app.pay(b, PaymentMethod.mtn);
      return b;
    }

    test('plus de 2 h avant : remboursement complet', () {
      final b = paid();
      final before = app.wallet.balance;
      expect(app.cancellationQuote(b).fee, 0);
      app.cancel(b);
      expect(app.wallet.balance, before + b.price);
      expect(b.cancellationFee, 0);
    });

    test('moins de 2 h avant : 50 % pour le soignant, commission déduite', () {
      final b = paid();
      clock.now = _day.subtract(const Duration(hours: 1));
      final wallet = app.wallet.balance;
      final pro = aya.wallet.balance;
      final q = app.cancellationQuote(b);
      expect(q.fee, 4000);
      expect(q.refund, 4000);
      app.cancel(b);
      expect(app.wallet.balance, wallet + 4000);
      expect(aya.wallet.balance, pro + 4000 - 600);
      expect(app.refundTotal, greaterThanOrEqualTo(4000));
    });

    test('annulation par le soignant : remboursement complet et alerte', () {
      final first = paid();
      final before = app.wallet.balance;
      app.cancelByPro(first, 'Malade');
      expect(app.wallet.balance, before + first.price);
      expect(aya.reliabilityAlert(clock.now), isFalse);

      final second = book(at: _day.add(const Duration(days: 1)));
      app.respond(second, accept: true);
      app.cancelByPro(second, 'Imprévu');
      expect(aya.reliabilityAlert(clock.now), isTrue);

      clock.advance(const Duration(days: 31));
      expect(aya.reliabilityAlert(clock.now), isFalse);
    });

    test('le soignant doit donner un motif', () {
      final b = paid();
      expect(() => app.cancelByPro(b, '  '), throwsA(isA<BusinessRuleError>()));
    });
  });

  group('suivi régulier', () {
    Contract contract({int sessions = 3}) => app.bookContract(
      service: service('pansement'),
      pro: aya,
      commune: 'Cocody',
      address: 'Angré 8e tranche',
      firstAt: _day,
      frequency: Frequency.daily,
      sessions: sessions,
      hasPrescription: false,
    );

    test('nombre de séances limité', () {
      expect(() => contract(sessions: 1), throwsA(isA<BusinessRuleError>()));
      expect(() => contract(sessions: 31), throwsA(isA<BusinessRuleError>()));
    });

    test('commission réduite, acceptation et paiement en une fois', () {
      app.loginPro(AppState.demoProPhone);
      final c = contract();
      expect(c.sessions, hasLength(3));
      expect(c.sessions.first.commission, 800); // 10 % de 8 000
      expect(app.proRequests.where((b) => b.contract == c), hasLength(1));

      app.respond(c.sessions.first, accept: true);
      expect(
        c.sessions.every((s) => s.status == BookingStatus.accepted),
        isTrue,
      );
      expect(app.amountDue(c.sessions.last), 24000);

      final before = app.wallet.balance;
      app.topUp(24000, PaymentMethod.wave);
      expect(app.pay(c.sessions[1], PaymentMethod.wallet), isTrue);
      expect(app.wallet.balance, before);
      expect(c.sessions.every((s) => s.readyForCare), isTrue);
    });

    test(
      'chaque séance terminée crédite le soignant ; le reste est remboursé',
      () {
        final c = contract();
        app.respond(c.sessions.first, accept: true);
        app.pay(c.sessions.first, PaymentMethod.orange);

        clock.now = _day;
        final pro = aya.wallet.balance;
        app.submitCareLog(c.sessions.first, log(c.sessions.first));
        expect(aya.wallet.balance, pro + 7200);

        final before = app.wallet.balance;
        final q = app.cancellationQuote(c.sessions.first);
        expect(q.sessions, 2);
        expect(q.refund, 16000);
        app.cancel(c.sessions[1]);
        expect(app.wallet.balance, before + 16000);
        expect(c.doneCount, 1);
      },
    );

    test('un créneau déjà pris bloque tout le suivi', () {
      final other = book(at: _day.add(const Duration(days: 1)));
      app.respond(other, accept: true);
      expect(() => contract(), throwsA(isA<BusinessRuleError>()));
    });
  });

  group('Pro Premium et parrainage', () {
    test('abonnement payé avec le solde, refusé s’il est insuffisant', () {
      final before = aya.wallet.balance;
      app.subscribePremium(aya);
      expect(aya.wallet.balance, before - premiumPrice);
      expect(aya.premiumUntil, clock.now.add(premiumPeriod));
      expect(app.premiumRevenue, premiumPrice);

      final koffi = app.pros.firstWhere((p) => p.type == ProType.kine);
      expect(
        () => app.subscribePremium(koffi),
        throwsA(isA<BusinessRuleError>()),
      );
    });

    test('les Pro Premium apparaissent en tête', () {
      final pansement = service('pansement');
      final ibrahim = app.pros.firstWhere((p) => p.name == 'Ibrahim Traoré');
      // Ibrahim (4,7) est Premium dans la démo, Aya (4,9) non.
      expect(app.prosFor(pansement, 'Cocody').first, ibrahim);
      ibrahim.premiumUntil = null;
      expect(app.prosFor(pansement, 'Cocody').first, aya);
    });

    test('parrainage : un mois offert au parrain, une seule fois', () {
      final filleule = app.pros.firstWhere(
        (p) => p.name == 'Bernadette Ouattara',
      );
      expect(filleule.referredBy, aya);
      app.verifyPro(filleule);
      expect(aya.premiumUntil, clock.now.add(referralBonus));
      app.suspendPro(filleule, 'Test');
      app.verifyPro(filleule);
      expect(aya.premiumUntil, clock.now.add(referralBonus));
    });

    test('code de parrainage inconnu refusé à l’inscription', () {
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
      final p = app.registerPro(
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
}
