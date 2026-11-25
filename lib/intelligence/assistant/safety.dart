/// Garde-fous de l'assistant.
///
/// 1. Urgence vitale : l'assistant s'arrête et oriente vers le SAMU (185).
/// 2. Diagnostic, prescription, décision clinique : refus explicite et
///    orientation vers un professionnel (médecin, infirmier, pharmacien).
/// 3. Données de santé : détectées et masquées ; elles ne quittent jamais
///    l'appareil vers un service d'IA externe sans base légale et garanties
///    (voir [AiDataPolicy]).
library;

enum SafetyVerdict { ok, emergency, clinical }

/// Texte normalisé (minuscules, sans accents) pour la détection.
String fold(String s) {
  const from = 'àâäéèêëîïôöùûüç’';
  const to = 'aaaeeeeiioouuuc\'';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i == -1 ? ch : to[i]);
  }
  return b.toString();
}

class SafetyGuard {
  const SafetyGuard();

  /// Signes d'urgence vitale (liste volontairement large : en cas de
  /// doute, on oriente vers le SAMU).
  static const _emergency = [
    'ne respire',
    'respire mal',
    'respire plus',
    'etouffe',
    'inconscient',
    'evanoui',
    'ne se reveille',
    'douleur thoracique',
    'douleur poitrine',
    'mal a la poitrine',
    'convulsion',
    'crise d\'epilepsie',
    'saigne beaucoup',
    'hemorragie',
    'avc',
    'paralysie',
    'bouche de travers',
    'suicide',
    'me tuer',
    'overdose',
    'intoxication',
    'empoisonn',
    'brulure grave',
    'accident',
    'perte de connaissance',
  ];

  /// Demandes qui relèvent d'un acte médical (diagnostic, prescription,
  /// adaptation de traitement, décision clinique).
  static const _clinical = [
    'diagnostic',
    'diagnostique',
    'quelle maladie',
    'est-ce grave',
    'c\'est grave',
    'j\'ai quoi',
    'il a quoi',
    'elle a quoi',
    'qu\'est-ce que j\'ai',
    'quel medicament',
    'quels medicaments',
    'quelle dose',
    'posologie',
    'combien de comprim',
    'combien de mg',
    'je peux prendre',
    'peut-il prendre',
    'peut-elle prendre',
    'antibiotique',
    'arreter son traitement',
    'arreter le traitement',
    'augmenter la dose',
    'diminuer la dose',
    'prescri',
    'ordonnance pour',
    'remplacer le medicament',
    'interpreter',
    'resultat d\'analyse',
    'est-ce normal',
    'faut-il operer',
  ];

  SafetyVerdict check(String text) {
    final t = fold(text);
    if (_emergency.any(t.contains)) return SafetyVerdict.emergency;
    if (_clinical.any(t.contains)) return SafetyVerdict.clinical;
    return SafetyVerdict.ok;
  }

  static const emergencyMessage =
      'Cela ressemble à une urgence. Appelez tout de suite le SAMU au 185 '
      '(ou les pompiers au 180). MyNurse n’est pas un service d’urgence. '
      'Restez auprès de la personne en attendant les secours.';

  static const clinicalMessage =
      'Je ne peux pas poser de diagnostic, conseiller un médicament ni '
      'modifier un traitement : seul un professionnel de santé le peut, après '
      'avoir examiné la personne. Je peux vous aider à réserver une '
      'consultation à domicile avec un médecin vérifié, ou à trouver une '
      'pharmacie de garde pour demander conseil.';
}

/// Données de santé et données personnelles dans un texte.
class HealthDataGuard {
  const HealthDataGuard();

  static final _phone = RegExp(r'(\+?225)?\s?0?[0-9](\s?[0-9]{2}){4}');
  static final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+');
  static final _vitals = RegExp(
    r'(\b\d{2,3}\s?/\s?\d{1,3}\b)|(\b\d{2}[.,]\d\s?°)|(\b\d+([.,]\d+)?\s?(mg|ml|g/l|mmhg|bpm|%))',
    caseSensitive: false,
  );
  static const _healthWords = [
    'diabet',
    'hypertens',
    'cancer',
    'vih',
    'sida',
    'hepatite',
    'allergi',
    'traitement',
    'medicament',
    'ordonnance',
    'analyse',
    'tension',
    'glycemie',
    'temperature',
    'fievre',
    'plaie',
    'pansement',
    'operation',
    'grossesse',
    'enceinte',
    'depression',
    'psychiatr',
    'handicap',
    'antecedent',
    'maladie',
    'symptome',
    'douleur',
    'injection',
    'perfusion',
  ];

  /// Le texte parle-t-il de la santé d'une personne ?
  bool containsHealthData(String text) {
    final t = fold(text);
    return _vitals.hasMatch(text) || _healthWords.any(t.contains);
  }

  /// Masque les coordonnées, les mesures et les noms connus.
  String redact(String text, {Iterable<String> knownNames = const []}) {
    var out = text
        .replaceAll(_email, '[e-mail]')
        .replaceAll(_phone, '[téléphone]')
        .replaceAll(_vitals, '[mesure]');
    for (final n in knownNames) {
      for (final part in n.split(RegExp(r'\s+')).where((p) => p.length > 2)) {
        out = out.replaceAll(
          RegExp('\\b${RegExp.escape(part)}\\b', caseSensitive: false),
          '[nom]',
        );
      }
    }
    return out;
  }
}

/// Règles d'envoi à un service d'IA externe (modèle de langage hébergé).
///
/// Par défaut, rien n'est envoyé : l'assistant fonctionne sur l'appareil.
/// Un service externe ne peut être activé qu'avec :
/// - une base légale pour les données de santé (consentement explicite,
///   déclaration ou autorisation de l'ARTCI) ;
/// - un contrat de sous-traitance (non-réutilisation des données,
///   hébergement, effacement) ;
/// - la minimisation : texte masqué par [HealthDataGuard], jamais le
///   dossier médical.
class AiDataPolicy {
  const AiDataPolicy({
    this.externalEnabled = false,
    this.healthDataLegalBasis = false,
    this.processorAgreement = false,
  });

  final bool externalEnabled;
  final bool healthDataLegalBasis;
  final bool processorAgreement;

  /// Peut-on envoyer ce texte (déjà masqué) à un service externe ?
  bool mayTransmit(String redacted, {required bool containsHealth}) {
    if (!externalEnabled || !processorAgreement) return false;
    if (containsHealth && !healthDataLegalBasis) return false;
    return true;
  }
}
