import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mynurse/app_state.dart';
import 'package:mynurse/main.dart';
import 'package:mynurse/models.dart';
import 'package:mynurse/screens/patient/health_record.dart';

/// Parcours patient, module par module (données de démonstration).
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late DateTime now;
  late AppState app;
  setUp(() {
    now = DateTime(2030, 1, 1, 8);
    app = AppState(clock: () => now)..loginDemo(AppState.demoPatientPhone);
  });

  Future<void> pumpApp(WidgetTester tester, {Size? size}) async {
    if (size != null) {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(MyNurseApp(state: app));
    await tester.pumpAndSettle();
  }

  // ===================================================== 1. tableau de bord
  group('1. tableau de bord', () {
    test('rappels : le soin de demain de la mère, le plus urgent d’abord', () {
      final r = app.reminders;
      expect(r.first.title, contains('Demain à 15h00'));
      expect(r.first.body, contains('Mariam Bamba'));
    });

    test('un paiement en attente passe en tête des rappels', () async {
      final b = await app.book(
        service: app.services.firstWhere((s) => s.id == 'pansement'),
        pro: app.pros.firstWhere((p) => p.id == 'pro2'),
        commune: 'Cocody',
        address: 'Angré 7e tranche, villa 24',
        scheduledAt: DateTime(2030, 1, 6, 10),
        hasPrescription: false,
      );
      await app.respond(b, accept: true);
      expect(app.reminders.first.urgent, isTrue);
      expect(app.reminders.first.title, startsWith('Paiement à faire'));
    });

    testWidgets('affiche le prochain soin, les rappels et les raccourcis', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('Bonjour Awa,'), findsOneWidget);
      expect(find.text('De quel soin avez-vous besoin ?'), findsOneWidget);
      expect(find.text('À faire'), findsOneWidget);
      expect(find.textContaining('pour Mariam Bamba'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Pharmacies de garde'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Ma famille'), findsOneWidget);
    });

    testWidgets('le choix d’un proche personnalise l’accueil', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Yao (Père)'));
      await tester.pumpAndSettle();
      expect(find.text('Aucun soin prévu'), findsOneWidget);
      expect(find.text('Réservez un soin pour Yao.'), findsOneWidget);
      await tester.tap(find.text('Mariam (Mère)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('pour Mariam Bamba'), findsWidgets);
    });

    testWidgets('grand écran : navigation latérale', (tester) async {
      await pumpApp(tester, size: const Size(1280, 900));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('hors connexion : bandeau explicatif', (tester) async {
      await pumpApp(tester);
      app.noteNetworkFailure();
      await tester.pumpAndSettle();
      expect(find.textContaining('Connexion instable'), findsOneWidget);
      expect(find.text('Réessayer'), findsWidgets);
    });
  });

  // ======================================================== 2. recherche
  group('2. recherche', () {
    test('par mot-clé, sans accent ni majuscule', () {
      final r = app.searchPros(
        const SearchFilters(commune: 'Cocody', query: 'KINE'),
      );
      expect(r.single.pro.type, ProType.kine);
      final p = app.searchPros(
        const SearchFilters(commune: 'Cocody', query: 'pansement'),
      );
      expect(
        p.map((m) => m.pro.name),
        containsAll(['Aya Kouamé', 'Ibrahim Traoré']),
      );
    });

    test('jamais de soignant non vérifié ni hors commune', () {
      final all = app.searchPros(const SearchFilters(commune: 'Marcory'));
      expect(all.every((m) => m.pro.verified), isTrue);
      expect(all.every((m) => m.pro.communes.contains('Marcory')), isTrue);
      expect(
        all.map((m) => m.pro.name),
        isNot(contains('Bernadette Ouattara')),
      );
    });

    testWidgets('on tape, la liste se met à jour', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Infirmier, pansement, kiné…'));
      await tester.pumpAndSettle();
      expect(find.text('Trouver un soignant'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'sage');
      await tester.pumpAndSettle();
      expect(find.text('Fatou Diabaté'), findsOneWidget);
      expect(find.text('Aya Kouamé'), findsNothing);
    });

    testWidgets('aucun résultat : on propose d’effacer les critères', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.text('Infirmier, pansement, kiné…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'chirurgien');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Aucun soignant ne correspond'),
        findsOneWidget,
      );
      await tester.tap(find.text('Effacer les critères'));
      await tester.pumpAndSettle();
      expect(find.text('Aya Kouamé'), findsOneWidget);
    });
  });

  // ================================================ 3. filtres avancés
  group('3. filtres avancés', () {
    test('profession, prix, note, nuit et tri', () {
      var f = const SearchFilters(commune: 'Cocody', serviceId: 'pansement');
      expect(app.searchPros(f), hasLength(2));
      f = f.copyWith(maxPrice: () => 7000);
      expect(app.searchPros(f).single.pro.name, 'Ibrahim Traoré');
      f = f.copyWith(maxPrice: () => null, nightOnly: true);
      expect(app.searchPros(f).single.pro.name, 'Aya Kouamé');
      f = const SearchFilters(commune: 'Cocody', sort: SearchSort.priceAsc);
      final prices = app.searchPros(f).map((m) => m.price).toList();
      expect(prices, orderedEquals([...prices]..sort()));
      f = const SearchFilters(commune: 'Cocody', minRating: 4.8);
      expect(app.searchPros(f).every((m) => m.pro.rating >= 4.8), isTrue);
      f = const SearchFilters(commune: 'Cocody', proType: ProType.medecin);
      expect(app.searchPros(f).single.pro.name, 'Dr Serge Aka');
    });

    testWidgets('la feuille de filtres annonce le nombre de résultats', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.text('Infirmier, pansement, kiné…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filtres'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Médecin'));
      await tester.pumpAndSettle();
      expect(find.text('Voir 1 soignant'), findsOneWidget);
      await tester.ensureVisible(find.text('Voir 1 soignant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voir 1 soignant'));
      await tester.pumpAndSettle();
      expect(find.text('Filtres (1)'), findsOneWidget);
      expect(find.text('Dr Serge Aka'), findsOneWidget);
    });
  });

  // ================================================ 4. fiche soignant
  group('4. fiche soignant', () {
    testWidgets('soins, tarifs, zones, avis ; on choisit puis on réserve', (
      tester,
    ) async {
      // Écran haut : toute la fiche est visible sans défilement.
      await pumpApp(tester, size: const Size(420, 2400));
      await tester.tap(find.text('Infirmier, pansement, kiné…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aya Kouamé'));
      await tester.pumpAndSettle();
      expect(find.text('Profil du soignant'), findsOneWidget);
      expect(find.textContaining('Se déplace à Cocody'), findsOneWidget);
      expect(find.text('Avis des familles'), findsOneWidget);
      expect(find.textContaining('Très douce avec ma mère'), findsOneWidget);
      expect(find.text('Choisissez un soin ci-dessus'), findsOneWidget);
      await tester.tap(find.text('Pansement simple ou complexe'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Réserver · 8'));
      await tester.pumpAndSettle();
      expect(find.text('Réserver'), findsOneWidget);
    });

    test(
      'un avis donné apparaît sur la fiche, avec prénom et initiale',
      () async {
        final past = app.patientBookings.firstWhere(
          (b) => b.status == BookingStatus.done,
        );
        await app.rate(past, 5, 'Parfait');
        expect(past.pro.reviews.first.comment, 'Parfait');
        expect(past.pro.reviews.first.author, 'Awa B.');
      },
    );
  });

  // ====================================================== 5. réservation
  group('5. réservation', () {
    test(
      'pour un proche : sa commune, pas la position de celui qui réserve',
      () {
        app.commune = 'Yopougon'; // Awa est loin de chez sa mère
        final mariam = app.patients.firstWhere((p) => p.name == 'Mariam Bamba');
        final yao = app.familyPatients.firstWhere((p) => p.name == 'Yao Bamba');
        expect(app.communeFor(mariam), 'Cocody');
        expect(app.communeFor(yao), 'Bingerville');
        expect(app.lastPlaceFor(mariam)!.address, contains('portail bleu'));
        expect(app.bookablePatients.map((p) => p.name), contains('Yao Bamba'));
      },
    );

    testWidgets('depuis la famille : réserver pour sa mère, adresse reprise', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(420, 2200));
      await tester.tap(find.text('Famille'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réserver un soin').at(1)); // Mariam
      await tester.pumpAndSettle();
      expect(find.text('Soignant pour Mariam'), findsOneWidget);
      await tester.tap(find.text('Ibrahim Traoré'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pansement simple ou complexe'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Réserver · '));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mariam Bamba (Mère)'), findsOneWidget);
      expect(find.textContaining('portail bleu'), findsOneWidget);
      expect(find.text('Ensuite'), findsOneWidget);
      // Un autre jour que le soin déjà prévu demain.
      await tester.tap(find.text('Envoyer la demande'));
      await tester.pumpAndSettle();
      expect(find.text('Demande envoyée'), findsOneWidget);
      expect(find.textContaining('pour Mariam Bamba'), findsOneWidget);
    });

    testWidgets('soignant qui ne vient pas dans la commune : expliqué', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(420, 2200));
      await tester.tap(find.text('Famille'));
      await tester.pumpAndSettle();
      // Yao vit à Bingerville ; Ibrahim ne s'y déplace pas.
      await tester.tap(find.text('Réserver un soin').at(2));
      await tester.pumpAndSettle();
      expect(find.text('Soignant pour Yao'), findsOneWidget);
      expect(find.text('Ibrahim Traoré'), findsNothing);
      expect(find.text('Aya Kouamé'), findsOneWidget);
    });
  });

  // =================================================== 6. suivis réguliers
  group('6. suivis réguliers', () {
    testWidgets('un suivi pour le père apparaît avec son avancement', (
      tester,
    ) async {
      final yao = app.familyPatients.firstWhere((p) => p.name == 'Yao Bamba');
      final c = await app.bookContract(
        service: app.services.firstWhere((s) => s.id == 'pansement'),
        pro: app.pros.first,
        commune: 'Bingerville',
        address: 'Bingerville, quartier Château, maison jaune',
        firstAt: DateTime(2030, 1, 3, 10),
        frequency: Frequency.everyOtherDay,
        sessions: 4,
        hasPrescription: false,
        patient: yao,
      );
      expect(app.activeContracts, contains(c));
      await pumpApp(tester, size: const Size(420, 2000));
      await tester.tap(find.text('Mes soins'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Suivi pansement simple ou complexe · Yao Bamba'),
        findsOneWidget,
      );
      expect(find.text('Séance 0/4 réalisée'), findsOneWidget);
      expect(find.textContaining('Prochaine séance'), findsOneWidget);
    });
  });

  // ================================================ 7. gestion familiale
  group('7. famille', () {
    testWidgets('chaque proche, ses droits, et le dossier confié par Koffi', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(420, 2000));
      await tester.tap(find.text('Famille'));
      await tester.pumpAndSettle();
      expect(find.text('Ma famille'), findsOneWidget);
      expect(find.text('Awa Bamba (moi)'), findsOneWidget);
      expect(find.text('Mariam Bamba'), findsOneWidget);
      expect(find.textContaining('Dossier de Koffi Bamba'), findsOneWidget);
      expect(find.text('1 proche autorisé à aider.'), findsOneWidget);
    });

    testWidgets('le titulaire autorise un proche et choisit ses droits', (
      tester,
    ) async {
      app.signUpDemo('0788888888', UserRole.patient);
      await app.completeProfile('Adjoua Bamba');
      app.loginDemo(AppState.demoPatientPhone);
      await pumpApp(tester, size: const Size(420, 2000));
      await tester.tap(find.text('Famille'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Qui a accès').at(1)); // Mariam
      await tester.pumpAndSettle();
      expect(find.text('Accès au dossier de Mariam'), findsOneWidget);
      expect(find.text('Koffi Bamba · Fils'), findsOneWidget);
      await tester.tap(find.text('Autoriser'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Adjoua Bamba');
      await tester.enterText(find.byType(TextFormField).at(1), '0788888888');
      await tester.tap(find.text('Lire le carnet de santé'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Autoriser ce proche'));
      await tester.pumpAndSettle();
      expect(find.text('Proche autorisé et prévenu.'), findsOneWidget);
      expect(find.text('Adjoua Bamba · Fils'), findsOneWidget);
    });

    testWidgets('le titulaire ferme l’accès d’un soignant au carnet', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(420, 2000));
      await tester.tap(find.text('Famille'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Qui a accès').at(1));
      await tester.pumpAndSettle();
      expect(find.text('Ibrahim Traoré · Infirmier(ère)'), findsOneWidget);
      await tester.tap(find.text('Retirer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Retirer'));
      await tester.pumpAndSettle();
      expect(find.text('Accès retiré.'), findsOneWidget);
      expect(find.text('Ibrahim Traoré · Infirmier(ère)'), findsNothing);
    });

    testWidgets('un proche voit ses droits et peut se retirer', (tester) async {
      await pumpApp(tester, size: const Size(420, 2000));
      await tester.tap(find.text('Famille'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mes droits'));
      await tester.pumpAndSettle();
      expect(find.text('Vos droits'), findsOneWidget);
      await tester.tap(find.text('Me retirer de ce dossier'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Me retirer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Dossier de Koffi Bamba'), findsNothing);
    });
  });

  // ================================================ 8. suivi des soins
  group('8. suivi des soins', () {
    testWidgets('chronologie et proches prévenus', (tester) async {
      await pumpApp(tester, size: const Size(420, 2200));
      await tester.tap(find.text('Mes soins'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mariam'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Pour Mariam Bamba'));
      await tester.pumpAndSettle();
      expect(find.text('Suivi du soin'), findsOneWidget);
      expect(find.text('Demande envoyée par vous'), findsOneWidget);
      expect(find.text('Confirmé par Ibrahim Traoré'), findsOneWidget);
      expect(
        find.textContaining('Prévenus à chaque étape : vous, Koffi Bamba'),
        findsOneWidget,
      );
    });

    testWidgets('soin réservé par un autre proche : suivi sans paiement', (
      tester,
    ) async {
      app.loginDemo('0711223344'); // Koffi suit les soins de sa mère
      await pumpApp(tester, size: const Size(420, 2200));
      await tester.tap(find.text('Mes soins'));
      await tester.pumpAndSettle();
      expect(find.text('Réservé par Awa Bamba'), findsOneWidget);
      await tester.tap(find.textContaining('Pour Mariam Bamba'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Soin réservé par Awa Bamba'), findsOneWidget);
      expect(find.text('Annuler le soin'), findsNothing);
    });

    test('historique : les soins terminés et annulés', () {
      final past = app.patientBookings.where(
        (b) => b.status == BookingStatus.done,
      );
      expect(past, isNotEmpty);
    });
  });

  // ===================================================== 9. carnet de santé
  group('9. carnet de santé', () {
    Future<void> openCarnet(WidgetTester tester, int index) async {
      await pumpApp(tester, size: const Size(420, 2600));
      await tester.tap(find.text('Famille'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carnet').at(index));
      await tester.pumpAndSettle();
    }

    testWidgets('titulaire : allergies en évidence, modification enregistrée', (
      tester,
    ) async {
      await openCarnet(tester, 1); // Mariam
      expect(find.text('Carnet de Mariam'), findsOneWidget);
      expect(find.text('Allergies : Pénicilline'), findsOneWidget);
      expect(find.textContaining('groupe O+'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Allergies'),
        'Pénicilline, latex',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer le carnet'));
      await tester.pumpAndSettle();
      expect(find.text('Carnet enregistré.'), findsOneWidget);
      expect(
        app.patients.firstWhere((p) => p.name == 'Mariam Bamba').allergies,
        'Pénicilline, latex',
      );
    });

    testWidgets('proche avec lecture seule : rien n’est modifiable', (
      tester,
    ) async {
      await openCarnet(tester, 2); // Yao, dossier de Koffi
      expect(
        find.textContaining('Lecture seule : Koffi Bamba'),
        findsOneWidget,
      );
      expect(find.text('Enregistrer le carnet'), findsNothing);
      expect(find.text('Ajouter'), findsNothing);
    });

    testWidgets('constantes relevées par les soignants', (tester) async {
      await openCarnet(tester, 0); // Awa : un soin terminé
      expect(find.text('Constantes relevées'), findsOneWidget);
      expect(find.text('130/80 mmHg'), findsOneWidget);
      expect(find.text('37,1 °C'), findsOneWidget);
    });

    test('sans le droit de lecture, le carnet est fermé', () {
      final yao = app.familyPatients.firstWhere((p) => p.name == 'Yao Bamba');
      yao.members.single.permissions = {FamilyPermission.viewReports};
      expect(app.can(yao, FamilyPermission.viewRecords), isFalse);
    });
  });

  // ============================================= 10. ordonnances, documents
  group('10. documents', () {
    test('ajout, formats refusés, retrait', () async {
      final mariam = app.patients.firstWhere((p) => p.name == 'Mariam Bamba');
      final before = mariam.documents.length;
      final d = await app.addDocument(
        mariam,
        kind: MedicalDocKind.labResult,
        title: '',
        file: (name: 'glycemie.jpg', bytes: Uint8List(2048)),
      );
      expect(mariam.documents.first, d);
      expect(d.title, "Résultat d'analyse");
      expect(d.isImage, isTrue);
      await expectLater(
        app.addDocument(
          mariam,
          kind: MedicalDocKind.other,
          title: 'x',
          file: (name: 'virus.exe', bytes: Uint8List(10)),
        ),
        throwsA(isA<BusinessRuleError>()),
      );
      await expectLater(
        app.addDocument(
          mariam,
          kind: MedicalDocKind.other,
          title: 'x',
          file: (name: 'scan.pdf', bytes: Uint8List(11 * 1024 * 1024)),
        ),
        throwsA(isA<BusinessRuleError>()),
      );
      await app.removeDocument(mariam, d);
      expect(mariam.documents.length, before);
    });

    test('un proche qui ajoute un document prévient le titulaire', () async {
      final mariam = app.patients.firstWhere((p) => p.name == 'Mariam Bamba');
      mariam.members.single.permissions.add(FamilyPermission.manageRecords);
      app.loginDemo('0711223344');
      final shared = app.familyPatients.firstWhere((p) => p.id == mariam.id);
      await app.addDocument(
        shared,
        kind: MedicalDocKind.prescription,
        title: 'Ordonnance pharmacie',
        file: (name: 'ordo.png', bytes: Uint8List(100)),
      );
      expect(
        app.notifications.any(
          (n) =>
              n.recipient == 'A1' &&
              n.title == 'Nouveau document dans le carnet',
        ),
        isTrue,
      );
    });

    testWidgets('ajout depuis le carnet, avec un fichier choisi', (
      tester,
    ) async {
      final mariam = app.patients.firstWhere((p) => p.name == 'Mariam Bamba');
      tester.view.physicalSize = const Size(840, 5200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            home: HealthRecordScreen(
              patient: mariam,
              picker: () async =>
                  (name: 'resultat.pdf', bytes: Uint8List(4096)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ordonnance du Dr Koné (diabète)'), findsOneWidget);
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Résultat d'analyse"));
      await tester.tap(find.text('Choisir une photo ou un PDF'));
      await tester.pumpAndSettle();
      expect(find.textContaining('resultat.pdf'), findsOneWidget);
      await tester.tap(find.text('Envoyer dans le carnet'));
      await tester.pumpAndSettle();
      expect(find.text('Document ajouté au carnet.'), findsOneWidget);
      expect(mariam.documents.first.fileName, 'resultat.pdf');
    });
  });

  // ================================================== 11. pharmacies
  group('11. pharmacies', () {
    test('de garde en premier, filtre par commune', () {
      final all = app.pharmaciesIn('Cocody');
      expect(all, hasLength(2));
      expect(all.first.onDutyAt(now), isTrue);
      final duty = app.pharmaciesIn('Cocody', onDutyOnly: true);
      expect(duty.single.name, startsWith('Pharmacie des Deux-Plateaux'));
      now = now.add(const Duration(days: 3));
      expect(app.pharmaciesIn('Cocody', onDutyOnly: true), isEmpty);
    });

    testWidgets('onglet Proximité : garde, appel, itinéraire', (tester) async {
      app.commune = 'Cocody';
      await pumpApp(tester, size: const Size(420, 1600));
      await tester.tap(find.text('Proximité'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Deux-Plateaux'), findsOneWidget);
      expect(find.textContaining('Angré Château'), findsNothing);
      expect(find.text('Appeler'), findsOneWidget);
      expect(find.text('Itinéraire'), findsOneWidget);
      await tester.tap(find.text('De garde maintenant'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Angré Château'), findsOneWidget);
    });
  });

  // ================================================ 12. rappels, notifications
  group('12. notifications et rappels', () {
    testWidgets('les rappels en tête des notifications', (tester) async {
      await pumpApp(tester, size: const Size(420, 1600));
      await tester.tap(find.byType(IconButton).first); // la cloche
      await tester.pumpAndSettle();
      expect(find.text('Rappels'), findsOneWidget);
      expect(find.textContaining('Demain à 15h00'), findsWidgets);
    });

    test('fin du soin de la mère : Awa et Koffi prévenus', () async {
      final visit = app.patientBookings.firstWhere(
        (b) => b.patient.name == 'Mariam Bamba' && b.readyForCare,
      );
      now = visit.scheduledAt;
      await app.submitCareLog(
        visit,
        CareLog(
          arrivedAt: now,
          leftAt: now.add(const Duration(minutes: 40)),
          acts: 'Pansement du pied',
        ),
      );
      final titles = {
        for (final n in app.notifications.where((n) => n.booking == visit))
          (n.recipient, n.title),
      };
      expect(titles, contains(('A1', 'Compte rendu disponible')));
      expect(titles, contains(('A2', 'Compte rendu disponible')));
    });
  });

  // ============================================ 13. avis et réclamations
  group('13. avis et réclamations', () {
    test('une réclamation trop courte est refusée, expliquée', () async {
      await expectLater(
        app.openComplaint(
          category: ComplaintCategory.delay,
          description: 'nul',
        ),
        throwsA(isA<BusinessRuleError>()),
      );
    });

    test('signalement de sécurité : urgent pour l’équipe', () async {
      await app.openComplaint(
        category: ComplaintCategory.safety,
        description: 'Le soignant a laissé une aiguille usagée au sol.',
        booking: app.patientBookings.first,
      );
      expect(
        app.notifications.any(
          (n) => n.recipient == 'admin' && n.title.startsWith('Urgent'),
        ),
        isTrue,
      );
    });

    testWidgets('depuis un soin, puis suivi dans « Mes réclamations »', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(420, 2600));
      await tester.tap(find.text('Mes soins'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Pour Mariam Bamba'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Signaler un problème'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retard'));
      await tester.enterText(
        find.byType(TextField).last,
        'Le soignant est arrivé avec une heure de retard.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Envoyer au support'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Réclamation envoyée'), findsOneWidget);
      Navigator.of(tester.element(find.text('Détail du soin'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mes réclamations'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Le soignant est arrivé avec une heure de retard.'),
        findsOneWidget,
      );
      expect(find.textContaining('Envoyée'), findsWidgets);
    });
  });
}
