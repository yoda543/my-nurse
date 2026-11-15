# MyNurse

Des soignants vérifiés, des soins suivis, partout à Abidjan.

Application Flutter (Android d'abord, puis iOS) : mise en relation entre patients et
professionnels de santé pour des soins à domicile.

## État actuel

L'app tourne en **mode démo** : les données sont en mémoire (`lib/data/demo_data.dart`),
rien n'est encore enregistré sur un serveur. Code SMS de démo : `123456`.

Parcours en place :

- **Patient** : connexion par téléphone, choix du soin et de la commune, liste des soignants
  vérifiés, fiche soignant, réservation (ordonnance, majoration de nuit), suivi des soins,
  compte rendu, note.
- **Proches** : un compte peut réserver pour un parent (nom, lien, allergies) ; le soignant
  voit les allergies sur la demande.
- **Soignant** : demandes à accepter ou refuser, planning, compte rendu de soin, revenus
  nets de commission, profil.

Pas encore fait : branchement Supabase, paiement Mobile Money, envoi des SMS, dépôt des
pièces justificatives, back-office de vérification, contrats récurrents, carnet de santé,
téléconsultation, pharmacies.

## Lancer

```bash
flutter pub get
flutter run
```

```bash
flutter test
```

## Base de données

`supabase/migrations/0001_init.sql` contient le schéma et les règles d'accès. Il n'est pas
encore appliqué sur un projet Supabase. Les prix, les statuts et la vérification des
soignants sont fixés côté serveur, jamais par l'app.

## Organisation du code

- `lib/models.dart` : modèles et règles tarifaires (commission 15 %, nuit +50 %)
- `lib/app_state.dart` : état de l'app, à remplacer par les appels Supabase
- `lib/screens/patient/`, `lib/screens/pro/` : écrans des deux espaces
