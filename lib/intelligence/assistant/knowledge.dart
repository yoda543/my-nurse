/// Base de connaissances de l'assistant.
///
/// Deux familles de contenus :
/// - l'aide à l'usage de MyNurse et les questions administratives
///   (rédigées par MyNurse, à partir des règles réelles de l'app) ;
/// - l'éducation à la santé : messages généraux de prévention, chacun avec
///   sa source. Aucun ne donne de diagnostic, de dose ou de traitement.
///   Chaque fiche porte un statut de validation : seules les fiches
///   validées par le médecin coordinateur sont proposées en production
///   (voir [HealthArticle.approved]).
library;

import '../../rules.dart';

/// Où l'assistant peut emmener l'utilisateur dans l'app.
enum AssistantDestination {
  search,
  bookings,
  family,
  records,
  pharmacies,
  wallet,
  complaints,
  proAgenda,
  proAvailability,
  proServices,
  proVerification,
  proEarnings,
}

class FaqEntry {
  const FaqEntry({
    required this.keywords,
    required this.answer,
    this.destination,
    this.actionLabel,
    this.forPros = false,
  });

  /// Mots qui déclenchent la réponse (sans accents, minuscules).
  final List<String> keywords;
  final String answer;
  final AssistantDestination? destination;
  final String? actionLabel;

  /// Réponse destinée aux soignants.
  final bool forPros;
}

class HealthArticle {
  const HealthArticle({
    required this.title,
    required this.keywords,
    required this.text,
    required this.source,
    this.approved = false,
  });

  final String title;
  final List<String> keywords;
  final String text;

  /// Organisme d'origine du message de prévention.
  final String source;

  /// Validé par le médecin coordinateur MyNurse.
  final bool approved;
}

final faq = <FaqEntry>[
  FaqEntry(
    keywords: [
      'reserver',
      'reservation',
      'prendre rendez',
      'rendez-vous',
      'trouver',
      'cherche',
      'besoin d\'un',
      'besoin d\'une',
    ],
    answer:
        'Pour réserver : choisissez le soin, la commune du patient, puis un '
        'soignant vérifié. Il a ${responseWindow.inHours} h pour accepter ; vous '
        'payez ensuite, et l’argent reste bloqué jusqu’à la fin du soin.',
    destination: AssistantDestination.search,
    actionLabel: 'Trouver un soignant',
  ),
  FaqEntry(
    keywords: ['annuler', 'annulation', 'rembourse'],
    answer:
        'Annulation gratuite jusqu’à ${freeCancellationWindow.inHours} h avant le '
        'soin : vous êtes remboursé sur votre solde MyNurse. Plus tard, la moitié '
        'du prix revient au soignant qui s’était libéré. Si le soignant annule, '
        'vous êtes remboursé en totalité.',
    destination: AssistantDestination.bookings,
    actionLabel: 'Mes soins',
  ),
  FaqEntry(
    keywords: [
      'payer',
      'paiement',
      'mobile money',
      'orange money',
      'wave',
      'mtn',
      'moov',
      'solde',
      'recharger',
      'recharge',
    ],
    answer:
        'Vous payez avec votre solde MyNurse, rechargé par Mobile Money (Orange, '
        'MTN, Moov, Wave). Le paiement se fait après la confirmation du soignant, '
        'dans les ${paymentWindow.inHours} h.',
    destination: AssistantDestination.wallet,
    actionLabel: 'Mon solde',
  ),
  FaqEntry(
    keywords: [
      'proche',
      'famille',
      'parent',
      'mere',
      'pere',
      'maman',
      'papa',
      'distance',
      'etranger',
      'pour ma',
      'pour mon',
      'diaspora',
      'frere',
      'soeur',
    ],
    answer:
        'Depuis l’onglet Famille, ajoutez un proche à soigner (sa commune sert '
        'à proposer les bons soignants), réservez pour lui et suivez chaque '
        'étape. Vous pouvez autoriser un autre membre de la famille, avec des '
        'droits précis et limités dans le temps.',
    destination: AssistantDestination.family,
    actionLabel: 'Ma famille',
  ),
  FaqEntry(
    keywords: [
      'carnet',
      'dossier',
      'allergie',
      'ordonnance',
      'document',
      'resultat',
    ],
    answer:
        'Le carnet de santé regroupe allergies, traitements, documents et '
        'comptes rendus. Un soignant n’y accède que pendant un soin (jusqu’à '
        '24 h après), et vous pouvez retirer son accès à tout moment.',
    destination: AssistantDestination.records,
    actionLabel: 'Carnet de santé',
  ),
  FaqEntry(
    keywords: ['pharmacie', 'garde', 'medicaments a acheter'],
    answer:
        'L’onglet Proximité liste les pharmacies de votre commune, celles de '
        'garde en premier, avec un bouton pour appeler.',
    destination: AssistantDestination.pharmacies,
    actionLabel: 'Pharmacies de garde',
  ),
  FaqEntry(
    keywords: [
      'verifie',
      'verification',
      'confiance',
      'diplome',
      'serieux',
      'qualifi',
    ],
    answer:
        'Chaque soignant est vérifié par MyNurse : diplôme, autorisation '
        'd’exercer, inscription à l’Ordre quand elle existe, pièce d’identité et '
        'assurance. Une pièce expirée suspend automatiquement les demandes.',
  ),
  FaqEntry(
    keywords: ['plainte', 'reclamation', 'probleme', 'retard', 'pas venu'],
    answer:
        'Ouvrez le soin puis « Signaler un problème ». Le support répond sous '
        '24 h ; un remboursement justifié arrive sur votre solde.',
    destination: AssistantDestination.complaints,
    actionLabel: 'Mes réclamations',
  ),
  FaqEntry(
    keywords: ['nuit', 'soir', 'tard'],
    answer:
        'Les soins de nuit (21 h – 6 h) sont majorés de 50 %, et seuls les '
        'soignants qui l’acceptent sont proposés.',
  ),
  FaqEntry(
    keywords: [
      'suivi',
      'regulier',
      'plusieurs seances',
      'chaque jour',
      'tous les jours',
    ],
    answer:
        'Un suivi régulier réserve de $contractMinSessions à $contractMaxSessions séances '
        'avec le même soignant (tous les jours, un jour sur deux ou chaque '
        'semaine), acceptées et payées en une fois.',
    destination: AssistantDestination.search,
    actionLabel: 'Réserver un suivi',
  ),
  // ---------------------------------------------------------- soignants
  FaqEntry(
    forPros: true,
    keywords: ['disponibilit', 'horaire', 'conge', 'absent'],
    answer:
        'Dans Agenda → Disponibilités, choisissez vos jours et horaires. '
        'L’interrupteur « Disponible aujourd’hui » bloque les nouvelles '
        'demandes du jour.',
    destination: AssistantDestination.proAvailability,
    actionLabel: 'Mes disponibilités',
  ),
  FaqEntry(
    forPros: true,
    keywords: ['prix', 'tarif', 'soins proposes', 'ajouter un soin'],
    answer:
        'Profil → Soins et tarifs : seuls les actes de votre profession, dans '
        'la fourchette MyNurse. Vous touchez le prix moins ${(commissionRate * 100).round()} %.',
    destination: AssistantDestination.proServices,
    actionLabel: 'Soins et tarifs',
  ),
  FaqEntry(
    forPros: true,
    keywords: ['piece', 'expire', 'renouvel', 'verification', 'dossier'],
    answer:
        'Profil → Vérification montre chaque pièce et sa date de fin. '
        'MyNurse vous prévient 30 jours avant ; une pièce expirée bloque les '
        'demandes jusqu’au renouvellement.',
    destination: AssistantDestination.proVerification,
    actionLabel: 'Ma vérification',
  ),
  FaqEntry(
    forPros: true,
    keywords: ['retrait', 'retirer', 'gain', 'argent', 'commission', 'solde'],
    answer:
        'Vos gains arrivent sur votre solde à l’envoi du compte rendu, '
        'commission déduite. Retrait vers Mobile Money dès '
        '1 000 FCFA, depuis l’onglet Revenus.',
    destination: AssistantDestination.proEarnings,
    actionLabel: 'Revenus',
  ),
];

/// Messages généraux de prévention. Statut « non validé » tant que le
/// médecin coordinateur ne les a pas relus : l'assistant les montre alors
/// avec la mention « contenu en cours de validation » (démo) et ne les
/// montre pas en production.
final healthArticles = <HealthArticle>[
  HealthArticle(
    title: 'Se laver les mains',
    keywords: ['main', 'hygiene', 'microbe', 'lavage'],
    text:
        'Se laver les mains à l’eau et au savon (environ 40 secondes) avant de '
        'manger, avant un soin, après les toilettes et en rentrant à la maison '
        'réduit la transmission de nombreuses infections.',
    source: 'Organisation mondiale de la santé (OMS)',
  ),
  HealthArticle(
    title: 'Paludisme : se protéger des moustiques',
    keywords: ['palu', 'paludisme', 'moustique', 'moustiquaire'],
    text:
        'Dormir sous une moustiquaire imprégnée d’insecticide, chaque nuit, '
        'protège du paludisme. Une fièvre doit faire consulter rapidement, '
        'surtout chez l’enfant, la femme enceinte et la personne âgée.',
    source:
        'OMS · Programme national de lutte contre le paludisme (Côte d’Ivoire)',
  ),
  HealthArticle(
    title: 'Diarrhée : prévenir la déshydratation',
    keywords: ['diarrhee', 'deshydrat', 'boire', 'sro'],
    text:
        'En cas de diarrhée, boire souvent et en petites quantités ; les sels '
        'de réhydratation orale (SRO) vendus en pharmacie sont recommandés. '
        'Consulter si la personne ne boit plus, vomit tout, a du sang dans les '
        'selles ou semble très fatiguée.',
    source: 'Organisation mondiale de la santé (OMS)',
  ),
  HealthArticle(
    title: 'Personnes âgées : prévenir les chutes',
    keywords: ['chute', 'tomber', 'personne agee', 'equilibre'],
    text:
        'Dégager les passages, éclairer la nuit, porter des chaussures fermées '
        'et garder les objets usuels à portée de main limitent les chutes. '
        'Une chute doit être signalée au médecin, même sans blessure visible.',
    source: 'Organisation mondiale de la santé (OMS)',
  ),
  HealthArticle(
    title: 'Diabète : surveiller ses pieds',
    keywords: ['diabete', 'diabetique', 'pied'],
    text:
        'Une personne diabétique doit regarder ses pieds chaque jour, les '
        'garder propres et secs, et montrer toute plaie, même petite, à un '
        'soignant sans attendre.',
    source: 'Organisation mondiale de la santé (OMS) · Fédération internationale du diabète',
  ),
];
