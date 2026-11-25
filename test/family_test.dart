import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mynurse/app_state.dart';
import 'package:mynurse/models.dart';

/// Gestion familiale : un proche à l'étranger organise les soins d'un parent
/// en Côte d'Ivoire, avec des droits donnés par le titulaire du dossier.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late DateTime now;
  late AppState app;
  setUp(() {
    now = DateTime(2030, 1, 1, 8);
    app = AppState(clock: () => now);
  });

  Patient mariam() => app.patients.firstWhere((p) => p.name == 'Mariam Bamba');
  Patient yao() => app.familyPatients.firstWhere((p) => p.name == 'Yao Bamba');
  PatientAccount koffi() => app.accounts.firstWhere((a) => a.id == 'A2');

  void loginAs(String phone) => app.loginDemo(phone);

  group('plusieurs patients sous un même compte', () {
    test('Awa gère sa mère et aide pour son père (dossier de Koffi)', () {
      expect(app.familyPatients.map((p) => p.name), [
        'Awa Bamba',
        'Mariam Bamba',
        'Yao Bamba',
      ]);
      expect(app.isOwner(mariam()), isTrue);
      expect(app.isOwner(yao()), isFalse);
      expect(yao().ownerName, 'Koffi Bamba');
    });

    test(
      'droits individuels : tout pour sa mère, ceux donnés pour son père',
      () {
        expect(app.permissionsFor(mariam()), FamilyPermission.values.toSet());
        expect(app.can(yao(), FamilyPermission.bookCare), isTrue);
        expect(app.can(yao(), FamilyPermission.viewRecords), isTrue);
        expect(app.can(yao(), FamilyPermission.manageRecords), isFalse);
      },
    );
  });

  group('réservation pour un proche', () {
    Future<Booking> bookFor(Patient p) => app.book(
      service: app.services.firstWhere((s) => s.id == 'pansement'),
      pro: app.pros.firstWhere((p) => p.id == 'pro2'),
      commune: 'Cocody',
      address: 'Angré 7e tranche, villa 24',
      scheduledAt: DateTime(2030, 1, 5, 10),
      hasPrescription: false,
      patient: p,
    );

    test('Awa réserve pour son père avec le droit « réserver »', () async {
      final b = await bookFor(yao());
      expect(b.patient, yao());
      expect(app.bookedByMe(b), isTrue);
      expect(app.patientBookings, contains(b));
    });

    test('sans le droit, la réservation est refusée et expliquée', () async {
      yao().members.single.permissions = {FamilyPermission.viewReports};
      await expectLater(
        bookFor(yao()),
        throwsA(
          isA<BusinessRuleError>().having(
            (e) => e.message,
            'message',
            contains('Koffi Bamba'),
          ),
        ),
      );
    });

    test('le titulaire et les proches qui suivent sont prévenus', () async {
      final b = await bookFor(yao());
      await app.respond(b, accept: true);
      final forKoffi = app.notifications.where(
        (n) => n.recipient == koffi().id && n.booking == b,
      );
      final forAwa = app.notifications.where(
        (n) => n.recipient == 'A1' && n.booking == b,
      );
      expect(forKoffi, hasLength(1));
      expect(forAwa, hasLength(1));
      expect(forKoffi.single.title, contains('a confirmé'));
    });

    test(
      'un soin réservé par un autre proche se suit mais ne se paie pas',
      () async {
        // Koffi réserve pour leur mère (il suit ses soins mais ne réserve pas
        // encore : Awa lui donne le droit).
        await app.updateFamilyMember(
          mariam(),
          mariam().members.single,
          permissions: {
            FamilyPermission.viewReports,
            FamilyPermission.bookCare,
          },
        );
        loginAs('0711223344');
        final b = await bookFor(
          app.familyPatients.firstWhere((p) => p.name == 'Mariam Bamba'),
        );
        await app.respond(b, accept: true);
        loginAs(AppState.demoPatientPhone);
        expect(app.patientBookings, contains(b));
        expect(app.bookedByMe(b), isFalse);
        await expectLater(
          app.pay(b, PaymentMethod.wallet),
          throwsA(isA<BusinessRuleError>()),
        );
      },
    );
  });

  group('proches autorisés', () {
    test('refus d’un doublon et d’un numéro sans compte', () async {
      await expectLater(
        app.addFamilyMember(
          mariam(),
          name: 'Koffi',
          contact: '0711223344',
          relation: 'Fils',
          permissions: {FamilyPermission.viewReports},
        ),
        throwsA(isA<BusinessRuleError>()),
      );
      await expectLater(
        app.addFamilyMember(
          mariam(),
          name: 'Tante Adjoua',
          contact: '0799999999',
          relation: 'Tante',
          permissions: {FamilyPermission.viewReports},
        ),
        throwsA(
          isA<BusinessRuleError>().having(
            (e) => e.message,
            'message',
            contains('créer son compte'),
          ),
        ),
      );
    });

    test(
      'nouveau proche : prévenu, puis voit le patient avec ses droits',
      () async {
        app.signUpDemo('0788888888', UserRole.patient);
        await app.completeProfile('Adjoua Bamba');
        loginAs(AppState.demoPatientPhone);
        await app.addFamilyMember(
          mariam(),
          name: 'Adjoua Bamba',
          contact: '0788888888',
          relation: 'Sœur',
          permissions: {FamilyPermission.viewReports},
        );
        expect(
          app.notifications.where((n) => n.title.contains('Mariam Bamba')),
          isNotEmpty,
        );
        loginAs('0788888888');
        final shared = app.familyPatients.firstWhere(
          (p) => p.name == 'Mariam Bamba',
        );
        expect(app.can(shared, FamilyPermission.viewReports), isTrue);
        expect(app.can(shared, FamilyPermission.viewRecords), isFalse);
        // Le soin de demain réservé par Awa est visible pour suivre son avancement.
        expect(app.patientBookings.any((b) => b.patient == shared), isTrue);
      },
    );

    test('accès limité dans le temps', () async {
      final m = yao().members.single;
      m.expiresAt = now.add(const Duration(days: 2));
      expect(app.familyPatients.map((p) => p.name), contains('Yao Bamba'));
      now = now.add(const Duration(days: 3));
      expect(
        app.familyPatients.map((p) => p.name),
        isNot(contains('Yao Bamba')),
      );
    });

    test(
      'retrait par le titulaire : le proche perd l’accès et est prévenu',
      () async {
        final m = mariam().members.single;
        await app.revokeFamilyMember(mariam(), m);
        loginAs('0711223344');
        expect(
          app.familyPatients.map((p) => p.name),
          isNot(contains('Mariam Bamba')),
        );
        expect(app.myNotifications.first.title, 'Accès retiré');
      },
    );

    test('un proche ne peut pas ajouter quelqu’un au dossier', () async {
      await expectLater(
        app.addFamilyMember(
          yao(),
          name: 'X',
          contact: '0700000000',
          relation: 'Ami',
          permissions: {FamilyPermission.viewReports},
        ),
        throwsA(isA<BusinessRuleError>()),
      );
    });

    test('modifier le carnet exige le droit correspondant', () async {
      await expectLater(
        app.updateHealthRecord(
          yao(),
          allergies: 'Aspirine',
          history: '',
          treatments: '',
        ),
        throwsA(isA<BusinessRuleError>()),
      );
      await app.updateHealthRecord(
        mariam(),
        allergies: 'Pénicilline, latex',
        history: mariam().history,
        treatments: mariam().treatments,
        bloodGroup: 'O+',
      );
      expect(mariam().allergies, 'Pénicilline, latex');
    });
  });

  group('connexion instable', () {
    test('un échec réseau est signalé, sans perdre les données', () {
      final before = app.patientBookings.length;
      app.noteNetworkFailure();
      expect(app.offline, isTrue);
      expect(app.patientBookings.length, before);
    });
  });

  test('accès au carnet retiré : le soignant ne le voit plus', () async {
    final mariam = app.patients.firstWhere((p) => p.name == 'Mariam Bamba');
    final access = app.recordAccessFor(mariam);
    expect(access.single.who, startsWith('Ibrahim Traoré'));
    final visit = access.single.booking!;
    expect(app.proCanSeeRecord(visit), isTrue);
    await app.revokeRecordAccess(mariam, access.single);
    expect(app.recordAccessFor(mariam), isEmpty);
    expect(app.proCanSeeRecord(visit), isFalse);
    expect(
      app.notifications.any(
        (n) => n.recipient == 'pro2' && n.title == 'Accès au carnet retiré',
      ),
      isTrue,
    );
  });
}
