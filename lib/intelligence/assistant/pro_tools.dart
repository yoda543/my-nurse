/// Outils de l'assistant pour les soignants : organisation de la journée
/// et mise en forme du compte rendu. Calculs locaux, sur l'appareil.
library;

import '../../models.dart';
import '../matching.dart' show communeCenters, distanceKm;

/// Vitesse moyenne retenue pour les trajets en ville (km/h, embouteillages
/// compris).
const _cityKmh = 18.0;

class DayPlanStep {
  const DayPlanStep({required this.booking, this.travelMinutes, this.warning});

  final Booking booking;

  /// Trajet estimé depuis le soin précédent.
  final int? travelMinutes;
  final String? warning;
}

class DayPlan {
  const DayPlan({required this.steps, required this.tips});

  final List<DayPlanStep> steps;

  /// Conseils pratiques (trajets serrés, paiements en attente…).
  final List<String> tips;
}

/// Organise la journée : ordre des visites, trajets, temps serrés.
/// L'assistant ne décide de rien : il signale, le soignant arbitre.
DayPlan organizeDay(List<Booking> day, DateTime now) {
  final list = [...day]..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  final steps = <DayPlanStep>[];
  final tips = <String>[];
  for (var i = 0; i < list.length; i++) {
    final b = list[i];
    int? travel;
    String? warning;
    if (i > 0) {
      final prev = list[i - 1];
      final a = prev.location ?? communeCenters[prev.commune];
      final c = b.location ?? communeCenters[b.commune];
      if (a != null && c != null) {
        travel = (distanceKm(a, c) / _cityKmh * 60).round() + 10;
        final gap = b.scheduledAt.difference(prev.endsAt).inMinutes;
        if (gap < travel) {
          warning =
              'Trajet serré : environ $travel min depuis ${prev.commune}, '
              '${gap < 0 ? 'les soins se chevauchent' : 'seulement $gap min de battement'}.';
        }
      }
    }
    if (b.status == BookingStatus.accepted && !b.paid) {
      warning = [
        ?warning,
        'Pas encore payé : ne partez pas avant la confirmation.',
      ].join(' ');
    }
    steps.add(DayPlanStep(booking: b, travelMinutes: travel, warning: warning));
  }
  if (list.isEmpty) {
    tips.add(
      'Aucun soin confirmé ce jour. Vérifiez vos disponibilités pour '
      'recevoir des demandes.',
    );
  } else {
    final communes = {for (final b in list) b.commune};
    if (communes.length > 2) {
      tips.add(
        'Journée sur ${communes.length} communes : regroupez les '
        'prochaines demandes par zone quand c’est possible.',
      );
    }
    final first = list.first;
    final leave = first.scheduledAt.subtract(const Duration(minutes: 30));
    if (leave.isAfter(now)) {
      tips.add(
        'Premier soin à ${_t(first.scheduledAt)} (${first.commune}) : '
        'partez vers ${_t(leave)}.',
      );
    }
    final prescriptions = list.where((b) => b.service.needsPrescription).length;
    if (prescriptions > 0) {
      tips.add(
        '$prescriptions soin(s) sur ordonnance : vérifiez-la sur place.',
      );
    }
    final reports = list
        .where((b) => b.readyForCare && b.endsAt.isBefore(now))
        .length;
    if (reports > 0) {
      tips.add(
        '$reports compte(s) rendu(s) à rédiger : votre paiement est '
        'versé dès l’envoi.',
      );
    }
  }
  return DayPlan(steps: steps, tips: tips);
}

String _t(DateTime d) =>
    '${d.hour} h${d.minute == 0 ? '' : d.minute.toString().padLeft(2, '0')}';

/// Brouillon de compte rendu, à relire et corriger par le soignant.
class CareReportDraft {
  const CareReportDraft({
    this.acts = '',
    this.observations = '',
    this.followUp = '',
    this.bloodPressure = '',
    this.temperature = '',
    this.pulse = '',
    this.glycemia = '',
    this.toReview = const [],
  });

  final String acts;
  final String observations;
  final String followUp;
  final String bloodPressure;
  final String temperature;
  final String pulse;
  final String glycemia;

  /// Phrases qui ressemblent à un diagnostic ou à une prescription : le
  /// soignant doit vérifier qu'elles relèvent bien de son rôle.
  final List<String> toReview;
}

/// Range les notes du soignant dans les rubriques du compte rendu.
///
/// Ne crée aucun contenu clinique : chaque phrase vient du soignant, elle
/// est seulement classée (actes, observations, suite à donner) et les
/// constantes notées sont reprises. Rien ne quitte l'appareil.
CareReportDraft structureCareNotes(
  String notes, {
  List<VitalSign> vitals = const [],
}) {
  String last(VitalKind k) {
    final v = vitals.where((v) => v.kind == k).lastOrNull;
    if (v == null) return '';
    return k == VitalKind.bloodPressure
        ? '${v.value.round()}/${(v.value2 ?? 0).round()}'
        : v.display.split(' ').first;
  }

  var bp = last(VitalKind.bloodPressure);
  var temp = last(VitalKind.temperature);
  var pulse = last(VitalKind.heartRate);
  var gly = last(VitalKind.glycemia);

  final acts = <String>[];
  final obs = <String>[];
  final follow = <String>[];
  final review = <String>[];
  const actWords = [
    'pansement',
    'refait',
    'nettoy',
    'injection',
    'injecte',
    'administr',
    'perfusion',
    'pose',
    'retire',
    'change',
    'toilette',
    'massage',
    'reeducation',
    'exercice',
    'prise de sang',
    'prelev',
    'sonde',
    'aide au',
    'mobilis',
    'mesure',
    'surveillance',
  ];
  const followWords = [
    'prochain',
    'revoir',
    'a surveiller',
    'rappeler',
    'controle',
    'demain',
    'dans 2 jours',
    'a prevoir',
    'a renouveler',
    'orienter',
    'consulter',
  ];
  const clinicalWords = [
    'diagnostic',
    'je pense que',
    'probablement',
    'prescri',
    'augmenter la dose',
    'diminuer la dose',
    'arreter le traitement',
    ' mg',
    'comprime',
  ];
  final bpRe = RegExp(
    r'(ta|tension)\s*[:=]?\s*(\d{2,3}\s*/\s*\d{1,3})',
    caseSensitive: false,
  );
  final tRe = RegExp(
    r'(t°|temp(erature|érature)?)\s*[:=]?\s*(\d{2}([.,]\d)?)',
    caseSensitive: false,
  );
  final pRe = RegExp(r'(pouls|fc)\s*[:=]?\s*(\d{2,3})', caseSensitive: false);
  final gRe = RegExp(
    r'(glyc(emie|émie)?)\s*[:=]?\s*(\d([.,]\d+)?)',
    caseSensitive: false,
  );

  for (final raw in notes.split(RegExp(r'[\n.;]+'))) {
    final s = raw.trim();
    if (s.isEmpty) continue;
    final low = s.toLowerCase();
    final f = low
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('à', 'a')
        .replaceAll('ô', 'o');
    var rest = s;
    if (bpRe.firstMatch(s) case final m?) {
      if (bp.isEmpty) bp = m.group(2)!.replaceAll(' ', '');
      rest = rest.replaceFirst(m.group(0)!, '');
    }
    if (tRe.firstMatch(s) case final m?) {
      if (temp.isEmpty) temp = m.group(3)!;
      rest = rest.replaceFirst(m.group(0)!, '');
    }
    if (pRe.firstMatch(s) case final m?) {
      if (pulse.isEmpty) pulse = m.group(2)!;
      rest = rest.replaceFirst(m.group(0)!, '');
    }
    if (gRe.firstMatch(s) case final m?) {
      if (gly.isEmpty) gly = m.group(3)!;
      rest = rest.replaceFirst(m.group(0)!, '');
    }
    rest = rest.replaceAll(RegExp(r'^[\s,:-]+|[\s,:-]+$'), '');
    if (rest.length < 3) continue;
    final sentence = rest[0].toUpperCase() + rest.substring(1);
    if (clinicalWords.any(f.contains)) review.add(sentence);
    if (followWords.any(f.contains)) {
      follow.add(sentence);
    } else if (actWords.any(f.contains)) {
      acts.add(sentence);
    } else {
      obs.add(sentence);
    }
  }
  String join(List<String> l) => l.map((e) => '$e.').join('\n');
  return CareReportDraft(
    acts: join(acts),
    observations: join(obs),
    followUp: join(follow),
    bloodPressure: bp,
    temperature: temp,
    pulse: pulse,
    glycemia: gly,
    toReview: review,
  );
}
