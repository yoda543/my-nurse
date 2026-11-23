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

## Règles métier

Toutes les valeurs sont dans `lib/rules.dart` et appliquées aussi côté serveur
(`supabase/migrations/0004_business_rules.sql`).

| Règle | Valeur |
| --- | --- |
| Commission | 15 % par soin ; 10 % sur un suivi régulier |
| Soin de nuit (21 h – 6 h) | +50 %, seulement chez les soignants disponibles la nuit |
| Délai de réservation | au moins 1 h avant, au plus 60 jours |
| Réponse du soignant | 2 h (jamais après l'heure du soin), sinon la demande est annulée |
| Paiement après confirmation | 2 h, sinon le rendez-vous est annulé |
| Créneaux | pas deux soins confirmés qui se chevauchent pour un même soignant (durée par soin) |
| Annulation par le patient | gratuite jusqu'à 2 h avant ; ensuite 50 % versés au soignant (commission déduite) |
| Annulation par le soignant | patient remboursé en totalité ; alerte à partir de 2 annulations en 30 jours |
| Compte rendu | à partir de 30 min avant le soin ; il débloque le paiement du soignant et un reçu numéroté |
| Suivi régulier | 2 à 30 séances (tous les jours, un jour sur deux, chaque semaine), même soignant, accepté et payé en une fois |
| Pro Premium | 5 000 FCFA / 30 jours payés avec le solde : en tête des résultats, statistiques |
| Parrainage soignant | 30 jours de Premium offerts au parrain quand le filleul est vérifié (une fois) |
| Qualité | alerte sous 4/5 après 3 notes |

Un paiement Mobile Money qui arrive après l'expiration du rendez-vous est crédité sur le
solde du patient : l'argent n'est jamais perdu.

## Localisation

À l'ouverture, l'app lit la position du patient et choisit la commune toute seule. Quand
il touche le champ d'adresse, l'adresse se remplit (quartier, rue, commune) ; il n'a plus
qu'à ajouter un repère. La position GPS part avec la réservation et le soignant a un bouton
« Itinéraire ». Si la position est refusée ou hors des communes desservies, un message
l'explique et la saisie reste possible.

L'adresse lisible vient d'OpenStreetMap (Nominatim). Son service public limite l'usage
(1 requête par seconde, pas d'usage commercial intensif) : avant le lancement, passer à un
Nominatim auto-hébergé ou à un service comme LocationIQ (offre gratuite).

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
- `supabase/migrations/0004_business_rules.sql` : délais, créneaux, annulation, suivis,
  Premium, parrainage, reçus ; expiration automatique chaque minute si `pg_cron` est activé.

Le prix, le statut d'un soin, le paiement et la vérification des soignants sont fixés côté
serveur, jamais par l'app. Le paiement n'est confirmé que par `confirm_payment`, appelable
uniquement avec la clé serveur, comme `confirm_topup`. Un solde ne peut jamais devenir
négatif et une même recharge ne peut pas être créditée deux fois. `0001`, `0003` et `0004` ont
été testés sur PostgreSQL 16 avec des scénarios complets ; `0002` n'a pas pu l'être hors de
Supabase.

## Organisation du code

- `lib/rules.dart` : toutes les règles métier et leurs valeurs
- `lib/models.dart` : modèles (soins, suivis, soignants, soldes)
- `lib/app_state.dart` : état et actions de l'app, à remplacer par les appels Supabase
- `lib/screens/patient/`, `lib/screens/pro/`, `lib/screens/admin/` : écrans des trois espaces
