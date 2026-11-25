/// Assistant MyNurse.
///
/// Architecture modulaire :
/// - [AssistantBackend] : qui produit la réponse. Par défaut
///   [LocalAssistant], entièrement sur l'appareil (règles, base de
///   connaissances, moteur de mise en relation). Un modèle externe pourra
///   s'y brancher plus tard derrière [AiDataPolicy], sans changer l'écran.
/// - [SafetyGuard] passe AVANT tout backend : urgence → SAMU, demande
///   clinique → refus et orientation. Aucun backend ne peut contourner ce
///   filtre.
/// - [AssistantContext] : ce que l'app expose à l'assistant (rôle, soins,
///   recherche de soignants, agenda), jamais le dossier médical.
library;

import '../../models.dart';
import 'knowledge.dart';
import 'pro_tools.dart';
import 'safety.dart';

export 'knowledge.dart' show AssistantDestination;

enum AssistantRole { patient, pro, admin }

/// Ce que l'app met à disposition de l'assistant.
class AssistantContext {
  const AssistantContext({
    required this.role,
    required this.services,
    required this.commune,
    required this.now,
    this.userName = '',
    this.findPros,
    this.proDay,
    this.showUnreviewedArticles = true,
  });

  final AssistantRole role;
  final List<CareService> services;

  /// Commune par défaut (celle du patient ou du soignant).
  final String commune;
  final DateTime now;
  final String userName;

  /// Recherche de soignants (moteur de mise en relation).
  final List<ProMatch> Function(CareService service, String commune)? findPros;

  /// Soins confirmés du soignant pour un jour.
  final List<Booking> Function(DateTime day)? proDay;

  /// Démo : montre aussi les fiches santé pas encore validées, avec une
  /// mention. Production : false.
  final bool showUnreviewedArticles;
}

class AssistantAction {
  const AssistantAction(
    this.label,
    this.destination, {
    this.service,
    this.commune,
  });

  final String label;
  final AssistantDestination destination;
  final CareService? service;
  final String? commune;
}

enum ReplyKind { answer, emergency, refusal, education, unknown }

class AssistantReply {
  const AssistantReply(
    this.text, {
    this.kind = ReplyKind.answer,
    this.actions = const [],
    this.source,
    this.suggestions = const [],
  });

  final String text;
  final ReplyKind kind;
  final List<AssistantAction> actions;

  /// Source d'une fiche d'éducation à la santé.
  final String? source;

  /// Questions proposées pour continuer.
  final List<String> suggestions;
}

/// Produit une réponse (local ou, plus tard, modèle externe encadré).
abstract class AssistantBackend {
  Future<AssistantReply> reply(String question, AssistantContext ctx);
}

/// Point d'entrée : garde-fous, puis backend.
class MyNurseAssistant {
  MyNurseAssistant({AssistantBackend? backend})
    : backend = backend ?? LocalAssistant();

  final AssistantBackend backend;
  final SafetyGuard _guard = const SafetyGuard();

  Future<AssistantReply> ask(String question, AssistantContext ctx) async {
    final q = question.trim();
    if (q.isEmpty) {
      return const AssistantReply('Posez votre question en quelques mots.');
    }
    switch (_guard.check(q)) {
      case SafetyVerdict.emergency:
        return const AssistantReply(
          SafetyGuard.emergencyMessage,
          kind: ReplyKind.emergency,
        );
      case SafetyVerdict.clinical:
        return AssistantReply(
          SafetyGuard.clinicalMessage,
          kind: ReplyKind.refusal,
          actions: [
            if (ctx.role == AssistantRole.patient) ...[
              AssistantAction(
                'Consultation à domicile',
                AssistantDestination.search,
                service: ctx.services
                    .where((s) => s.id == 'consultation')
                    .firstOrNull,
              ),
              const AssistantAction(
                'Pharmacies de garde',
                AssistantDestination.pharmacies,
              ),
            ],
          ],
        );
      case SafetyVerdict.ok:
        return backend.reply(q, ctx);
    }
  }

  /// Questions de départ selon le rôle.
  static List<String> starters(AssistantRole role) => switch (role) {
    AssistantRole.patient => const [
      'Je cherche une infirmière à Cocody pour un pansement',
      'Comment réserver pour ma mère ?',
      'Comment annuler un soin ?',
      'Comment payer ?',
      'Se protéger du paludisme',
    ],
    AssistantRole.pro => const [
      'Organise ma journée',
      'Comment changer mes disponibilités ?',
      'Comment retirer mes gains ?',
      'Ma pièce va expirer',
    ],
    AssistantRole.admin => const [
      'Comment fonctionne la vérification ?',
      'Comment fonctionnent les remboursements ?',
    ],
  };
}

/// Assistant local : règles et base de connaissances, sur l'appareil.
class LocalAssistant implements AssistantBackend {
  @override
  Future<AssistantReply> reply(String question, AssistantContext ctx) async {
    final q = fold(question);

    if (RegExp(r'^(bonjour|bonsoir|salut|hello|coucou)\b').hasMatch(q)) {
      return AssistantReply(
        'Bonjour${ctx.userName.isEmpty ? '' : ' ${ctx.userName.split(' ').first}'} ! '
        'Je vous aide à utiliser MyNurse : trouver un soignant, réserver, '
        'payer, suivre un soin. Je ne donne pas d’avis médical.',
        suggestions: MyNurseAssistant.starters(ctx.role),
      );
    }

    // Soignant : organiser la journée.
    if (ctx.role == AssistantRole.pro &&
        ctx.proDay != null &&
        [
          'organis',
          'planning',
          'ma journee',
          'aujourd',
          'demain',
          'tournee',
        ].any(q.contains)) {
      final day = q.contains('demain')
          ? ctx.now.add(const Duration(days: 1))
          : ctx.now;
      final plan = organizeDay(ctx.proDay!(day), ctx.now);
      final lines = [
        for (final s in plan.steps)
          '• ${_t(s.booking.scheduledAt)} — ${s.booking.service.name.split(' (').first}, '
              '${s.booking.patientName} (${s.booking.commune})'
              '${s.travelMinutes == null ? '' : ', trajet ≈ ${s.travelMinutes} min'}'
              '${s.warning == null ? '' : '\n  ⚠ ${s.warning}'}',
        ...plan.tips.map((t) => '→ $t'),
      ];
      return AssistantReply(
        '${q.contains('demain') ? 'Demain' : 'Aujourd’hui'} : '
        '${plan.steps.length} soin${plan.steps.length > 1 ? 's' : ''}.\n${lines.join('\n')}',
        actions: const [
          AssistantAction('Ouvrir l’agenda', AssistantDestination.proAgenda),
        ],
      );
    }

    // Patient : trouver un soignant (« infirmière à Cocody pour pansement »).
    if (ctx.role == AssistantRole.patient && ctx.findPros != null) {
      final service = _service(q, ctx.services);
      final commune = _commune(q) ?? ctx.commune;
      final wantsSearch = [
        'cherche',
        'trouver',
        'besoin',
        'infirmi',
        'medecin',
        'kine',
        'sage-femme',
        'aide-soignant',
        'soignant',
        'reserver',
      ].any(q.contains);
      if (service != null && wantsSearch) {
        final list = ctx.findPros!(service, commune).take(3).toList();
        if (list.isEmpty) {
          return AssistantReply(
            'Aucun soignant vérifié ne propose « ${service.name} » à $commune '
            'pour le moment. Essayez une commune voisine.',
            actions: [
              AssistantAction(
                'Changer de commune',
                AssistantDestination.search,
                service: service,
              ),
            ],
          );
        }
        return AssistantReply(
          'Voici les soignants vérifiés les plus adaptés pour « ${service.name} » '
          'à $commune (classés selon la proximité, la disponibilité, les avis, '
          'le prix et la continuité des soins, jamais selon un abonnement) :\n'
          '${list.map((m) => '• ${m.pro.name} — ${_money(m.price)}'
              '${m.reasons.isEmpty ? '' : ' · ${m.reasons.first}'}').join('\n')}',
          actions: [
            AssistantAction(
              'Voir et réserver',
              AssistantDestination.search,
              service: service,
              commune: commune,
            ),
          ],
        );
      }
    }

    // Éducation à la santé.
    for (final a in healthArticles) {
      if (!a.approved && !ctx.showUnreviewedArticles) continue;
      if (a.keywords.any(q.contains)) {
        return AssistantReply(
          '${a.title}\n${a.text}\n\nInformation générale de prévention : elle ne '
          'remplace pas l’avis d’un professionnel de santé.'
          '${a.approved ? '' : '\n(Contenu en cours de validation par le médecin coordinateur.)'}',
          kind: ReplyKind.education,
          source: a.source,
        );
      }
    }

    // Aide à l'usage et questions administratives.
    FaqEntry? best;
    var bestHits = 0;
    for (final f in faq) {
      if (f.forPros != (ctx.role == AssistantRole.pro) &&
          ctx.role != AssistantRole.admin) {
        continue;
      }
      final hits = f.keywords.where(q.contains).length;
      if (hits > bestHits) {
        best = f;
        bestHits = hits;
      }
    }
    if (best != null) {
      return AssistantReply(
        best.answer,
        actions: [
          if (best.destination != null)
            AssistantAction(best.actionLabel ?? 'Ouvrir', best.destination!),
        ],
      );
    }

    return AssistantReply(
      'Je n’ai pas compris. Je peux vous aider à trouver un soignant, '
      'réserver, payer, annuler, gérer votre famille ou votre carnet. Pour '
      'une question médicale, adressez-vous à un professionnel de santé.',
      kind: ReplyKind.unknown,
      suggestions: MyNurseAssistant.starters(ctx.role),
    );
  }

  static String _t(DateTime d) =>
      '${d.hour} h${d.minute == 0 ? '' : d.minute.toString().padLeft(2, '0')}';

  static String _money(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return '$b FCFA';
  }

  static const _serviceWords = {
    'injection': ['injection', 'piqure'],
    'perfusion': ['perfusion', 'perf'],
    'pansement': ['pansement', 'plaie'],
    'sonde': ['sonde'],
    'toilette': [
      'toilette',
      'aide-soignant',
      'aide soignant',
      'personne agee',
      'mobilisation',
    ],
    'consultation': ['consultation', 'medecin', 'docteur', 'generaliste'],
    'kine': ['kine', 'reeducation', 'kinesitherapeute'],
    'suivi_grossesse': ['grossesse', 'sage-femme', 'sage femme', 'enceinte'],
  };

  static CareService? _service(String q, List<CareService> services) {
    for (final e in _serviceWords.entries) {
      if (e.value.any(q.contains)) {
        return services.where((s) => s.id == e.key).firstOrNull;
      }
    }
    return null;
  }

  static String? _commune(String q) {
    for (final c in communes) {
      if (q.contains(fold(c))) return c;
    }
    return null;
  }
}

/// Branchement futur d'un modèle externe. Désactivé : ne transmet rien tant
/// que [policy] ne l'autorise pas, et seulement un texte masqué.
class GuardedExternalAssistant implements AssistantBackend {
  GuardedExternalAssistant({
    required this.policy,
    required this.send,
    AssistantBackend? fallback,
  }) : fallback = fallback ?? LocalAssistant();

  final AiDataPolicy policy;

  /// Appel au service (par exemple via une fonction serveur MyNurse, jamais
  /// avec une clé dans l'app).
  final Future<String> Function(String redactedQuestion) send;
  final AssistantBackend fallback;
  final HealthDataGuard _data = const HealthDataGuard();

  @override
  Future<AssistantReply> reply(String question, AssistantContext ctx) async {
    final health = _data.containsHealthData(question);
    final redacted = _data.redact(question, knownNames: [ctx.userName]);
    if (!policy.mayTransmit(redacted, containsHealth: health)) {
      return fallback.reply(question, ctx);
    }
    final text = await send(redacted);
    // La réponse externe repasse par les garde-fous.
    if (const SafetyGuard().check(text) == SafetyVerdict.clinical) {
      return const AssistantReply(
        SafetyGuard.clinicalMessage,
        kind: ReplyKind.refusal,
      );
    }
    return AssistantReply(text);
  }
}
