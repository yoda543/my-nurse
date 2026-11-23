# MyNurse

Des soignants vérifiés, des soins suivis, partout à Abidjan.

Application Flutter (Android d'abord, puis iOS) : mise en relation entre patients et
professionnels de santé pour des soins à domicile.

## État actuel

L'app tourne en **mode démo** : les données sont en mémoire (`lib/data/demo_data.dart`),
rien n'est enregistré sur un serveur, aucun SMS n'est envoyé, aucun argent n'est débité.

Comptes de démonstration (code SMS : `123456`) :

| Espace | Numéro |
| --- | --- |
| Patient | n'importe quel numéro à 10 chiffres |
| Soignant déjà vérifié | `0500000000` |
| Nouveau soignant (inscription) | tout autre numéro |
| Administration | lien « Administration MyNurse » sur l'accueil, n'importe quel numéro |

### Patient
Recherche par soin et commune, fiches des soignants vérifiés, réservation (ordonnance,
majoration de nuit), réservation pour un proche, **solde MyNurse rechargeable** par Mobile
Money, paiement après confirmation du soignant avec le solde ou en Mobile Money (argent
bloqué jusqu'à la fin du soin), annulation remboursée tout de suite sur le solde, compte
rendu de chaque soin, note, carnet de santé (allergies, antécédents, traitements,
historique des soins).

### Soignant
Inscription (profession, communes, prix dans la fourchette, pièces justificatives, charte),
attente de vérification, renvoi du dossier après refus, demandes à accepter ou refuser,
planning (pas de déplacement avant paiement), compte rendu de soin, **solde visible en
permanence** (crédité à chaque soin terminé, commission déduite), retrait vers Mobile
Money, historique des gains, zones et disponibilité de nuit modifiables.

### Administration
Vérification des dossiers (validation impossible si une pièce manque, refus avec motif),
liste des soignants avec alerte sous 4/5, suspension (soins à venir annulés et
remboursés), tableau de bord : volume, commissions, argent bloqué, remboursements, soldes
des clients et des soignants.

## Pas encore fait

- Branchement de l'app à Supabase (le schéma est prêt, voir plus bas).
- Envoi réel des SMS de connexion (fournisseur SMS à choisir).
- Paiement réel : agrégateur CinetPay ou PayDunya, avec une fonction serveur qui reçoit
  ses confirmations et appelle `confirm_payment` (soin payé en Mobile Money) ou
  `confirm_topup` (recharge), et qui exécute les retraits de la table `withdrawals`.
- Cadre légal du solde prépayé : conserver l'argent des clients relève de la monnaie
  électronique (BCEAO). À faire valider par un juriste, ou passer par un agrégateur qui
  détient l'agrément.
- Envoi réel des pièces justificatives (photo ou PDF vers le stockage Supabase).
- Prévus en V1.1 / V1.2 : contrats récurrents, téléconsultation, pharmacies de garde.

## Lancer

```bash
flutter pub get
flutter run
```

```bash
flutter test
```

## Base de données

- `supabase/migrations/0001_init.sql` : tables, règles d'accès, actions contrôlées.
- `supabase/migrations/0002_storage.sql` : stockage privé des pièces justificatives.
- `supabase/migrations/0003_wallets.sql` : soldes, historique des mouvements, retraits.

Le prix, le statut d'un soin, le paiement et la vérification des soignants sont fixés côté
serveur, jamais par l'app. Le paiement n'est confirmé que par `confirm_payment`, appelable
uniquement avec la clé serveur, comme `confirm_topup`. Un solde ne peut jamais devenir
négatif et une même recharge ne peut pas être créditée deux fois. `0001` et `0003` ont été
testés sur PostgreSQL 16 avec des scénarios complets ; `0002` n'a pas pu l'être hors de
Supabase.

## Organisation du code

- `lib/models.dart` : modèles et règles (commission 15 %, nuit +50 %, pièces demandées)
- `lib/app_state.dart` : état et actions de l'app, à remplacer par les appels Supabase
- `lib/screens/patient/`, `lib/screens/pro/`, `lib/screens/admin/` : écrans des trois espaces
