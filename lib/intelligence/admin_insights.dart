/// Intelligence administrative : signaux d'activité suspecte, pics de
/// réservations inhabituels, comptes en double, rapport d'activité et
/// analyse des retours patients.
///
/// Principes :
/// - le module ne reçoit qu'une projection des données ([BookingFact],
///   [AccountFact], [ComplaintFact], [ReviewFact]) : aucun champ médical
///   (antécédents, traitements, constantes, comptes rendus) n'y entre ;
/// - tout est calculé sur place, par des règles lisibles : rien n'est
///   envoyé à un service d'IA ;
/// - chaque signal est expliqué (preuves) et ne déclenche aucune sanction :
///   un membre de l'équipe vérifie puis décide.
library;

import 'dart:math' as math;

import 'assistant/safety.dart' show fold;

// ================================================================ entrées

enum CancelledBy { patient, pro, platform }

class BookingFact {
  const BookingFact({
    required this.id,
    required this.ownerId,
    required this.proId,
    required this.proName,
    required this.commune,
    required this.serviceName,
    required this.createdAt,
    required this.scheduledAt,
    required this.status,
    this.cancelledBy,
    this.price = 0,
    this.paid = false,
    this.refundAmount = 0,
    this.rating,
    this.night = false,
  });

  final String id;

  /// Compte patient qui a réservé (null : patient extérieur).
  final String? ownerId;
  final String proId;
  final String proName;
  final String commune;
  final String serviceName;
  final DateTime createdAt;
  final DateTime scheduledAt;

  /// pending, accepted, refused, cancelled, done.
  final String status;
  final CancelledBy? cancelledBy;
  final int price;
  final bool paid;
  final int refundAmount;
  final int? rating;
  final bool night;
}

enum AccountKind { patient, pro, staff }

class AccountFact {
  const AccountFact({
    required this.id,
    required this.kind,
    required this.name,
    required this.phone,
    this.email = '',
  });

  final String id;
  final AccountKind kind;
  final String name;
  final String phone;
  final String email;

  String get kindLabel => switch (kind) {
    AccountKind.patient => 'Patient',
    AccountKind.pro => 'Soignant',
    AccountKind.staff => 'Équipe',
  };
}

class ComplaintFact {
  const ComplaintFact({
    required this.category,
    required this.text,
    required this.createdAt,
    this.proId,
    this.open = true,
  });

  final String category;
  final String text;
  final DateTime createdAt;
  final String? proId;
  final bool open;
}

class ReviewFact {
  const ReviewFact({
    required this.proId,
    required this.proName,
    required this.rating,
    required this.text,
    required this.at,
  });

  final String proId;
  final String proName;
  final int rating;
  final String text;
  final DateTime at;
}

// ================================================================ sorties

enum InsightSeverity { info, watch, high }

extension InsightSeverityLabel on InsightSeverity {
  String get label => switch (this) {
    InsightSeverity.info => 'Information',
    InsightSeverity.watch => 'À surveiller',
    InsightSeverity.high => 'Prioritaire',
  };
}

/// Signal d'activité suspecte, toujours accompagné de ses preuves.
class InsightAlert {
  const InsightAlert({
    required this.code,
    required this.severity,
    required this.title,
    required this.detail,
    required this.evidence,
    required this.suggestedCheck,
    required this.subject,
  });

  /// Type de règle (pour filtrer et tester).
  final String code;
  final InsightSeverity severity;
  final String title;
  final String detail;
  final List<String> evidence;

  /// Vérification proposée à l'équipe (jamais une sanction automatique).
  final String suggestedCheck;

  /// Compte ou soignant concerné.
  final String subject;
}

class DayCount {
  const DayCount(this.day, this.count);
  final DateTime day;
  final int count;
}

/// Journée dont le volume de réservations sort nettement de l'habitude.
class BookingAnomaly {
  const BookingAnomaly({
    required this.day,
    required this.count,
    required this.expected,
    required this.zScore,
    required this.topCommune,
    required this.topService,
  });

  final DateTime day;
  final int count;
  final double expected;
  final double zScore;
  final String topCommune;
  final String topService;
}

/// Comptes qui semblent appartenir à la même personne.
class DuplicateGroup {
  const DuplicateGroup({
    required this.accounts,
    required this.reason,
    required this.confidence,
  });

  final List<AccountFact> accounts;
  final String reason;

  /// 0..1 : 1 = même numéro, 0,6 = même nom.
  final double confidence;
}

class TopicStat {
  TopicStat(this.topic);

  final String topic;
  int mentions = 0;
  int positive = 0;
  int negative = 0;
  final List<String> examples = [];
}

class FeedbackAnalysis {
  const FeedbackAnalysis({
    required this.reviewCount,
    required this.averageRating,
    required this.positiveShare,
    required this.negativeShare,
    required this.topics,
    required this.complaintsByCategory,
    required this.prosToWatch,
  });

  final int reviewCount;
  final double averageRating;
  final double positiveShare;
  final double negativeShare;

  /// Sujets cités, du plus au moins mentionné.
  final List<TopicStat> topics;
  final Map<String, int> complaintsByCategory;

  /// Soignants dont les retours récents se dégradent.
  final List<String> prosToWatch;
}

class InsightsReport {
  const InsightsReport({
    required this.from,
    required this.to,
    required this.alerts,
    required this.daily,
    required this.anomalies,
    required this.duplicates,
    required this.feedback,
    required this.text,
  });

  final DateTime from;
  final DateTime to;
  final List<InsightAlert> alerts;
  final List<DayCount> daily;
  final List<BookingAnomaly> anomalies;
  final List<DuplicateGroup> duplicates;
  final FeedbackAnalysis feedback;

  /// Rapport d'activité rédigé, prêt à copier.
  final String text;
}

// =============================================================== réglages

class InsightThresholds {
  const InsightThresholds({
    this.window = const Duration(days: 30),
    this.proCancellations = 3,
    this.patientCancellations = 3,
    this.refundShare = 0.5,
    this.burstBookings = 4,
    this.repeatedFiveStars = 3,
    this.complaintsPerPro = 2,
    this.spikeZ = 2.5,
    this.spikeMinExtra = 3,
  });

  final Duration window;
  final int proCancellations;
  final int patientCancellations;
  final double refundShare;

  /// Réservations d'un même compte en 24 h.
  final int burstBookings;

  /// Avis 5 étoiles d'un même compte pour un même soignant en 7 jours.
  final int repeatedFiveStars;
  final int complaintsPerPro;
  final double spikeZ;

  /// Écart minimal (en réservations) pour signaler un pic.
  final int spikeMinExtra;
}

// ================================================================= moteur

/// Analyse purement locale et déterministe.
class AdminInsightsEngine {
  const AdminInsightsEngine({this.thresholds = const InsightThresholds()});

  final InsightThresholds thresholds;

  InsightsReport analyze({
    required DateTime from,
    required DateTime to,
    required DateTime now,
    required List<BookingFact> bookings,
    required List<AccountFact> accounts,
    required List<ComplaintFact> complaints,
    required List<ReviewFact> reviews,
    Map<String, List<DateTime>> proCancellations = const {},
  }) {
    final alerts = suspiciousActivity(
      now: now,
      bookings: bookings,
      accounts: accounts,
      complaints: complaints,
      proCancellations: proCancellations,
    );
    final daily = dailyCounts(bookings, from, to);
    final anomalies = bookingAnomalies(bookings, from, to);
    final duplicates = duplicateAccounts(accounts);
    bool inPeriod(DateTime d) => !d.isBefore(from) && d.isBefore(to);
    final feedback = analyzeFeedback(
      reviews: reviews.where((r) => inPeriod(r.at)).toList(),
      complaints: complaints.where((c) => inPeriod(c.createdAt)).toList(),
      now: now,
    );
    return InsightsReport(
      from: from,
      to: to,
      alerts: alerts,
      daily: daily,
      anomalies: anomalies,
      duplicates: duplicates,
      feedback: feedback,
      text: operationalReport(
        from: from,
        to: to,
        bookings: bookings.where((b) => inPeriod(b.createdAt)).toList(),
        alerts: alerts,
        anomalies: anomalies,
        duplicates: duplicates,
        feedback: feedback,
      ),
    );
  }

  // -------------------------------------------------- activité suspecte
  List<InsightAlert> suspiciousActivity({
    required DateTime now,
    required List<BookingFact> bookings,
    required List<AccountFact> accounts,
    required List<ComplaintFact> complaints,
    Map<String, List<DateTime>> proCancellations = const {},
  }) {
    final t = thresholds;
    final since = now.subtract(t.window);
    final days = t.window.inDays;
    final alerts = <InsightAlert>[];
    final byId = {for (final a in accounts) a.id: a};
    String accountName(String id) => byId[id]?.name.isNotEmpty == true
        ? '${byId[id]!.name} ($id)'
        : 'Compte $id';
    String proName(String id) =>
        bookings.where((b) => b.proId == id).firstOrNull?.proName ??
        byId[id]?.name ??
        id;

    // 1. Soignant qui annule souvent des soins confirmés.
    final proCancel = <String, List<DateTime>>{};
    proCancellations.forEach((id, list) {
      proCancel[id] = [...list.where((d) => d.isAfter(since))];
    });
    for (final b in bookings) {
      if (b.cancelledBy == CancelledBy.pro &&
          b.createdAt.isAfter(since) &&
          !proCancellations.containsKey(b.proId)) {
        (proCancel[b.proId] ??= []).add(b.scheduledAt);
      }
    }
    proCancel.forEach((id, list) {
      if (list.length >= t.proCancellations) {
        alerts.add(
          InsightAlert(
            code: 'pro_cancellations',
            severity: list.length >= t.proCancellations * 2
                ? InsightSeverity.high
                : InsightSeverity.watch,
            title: 'Annulations répétées par un soignant',
            subject: proName(id),
            detail:
                '${list.length} soins confirmés annulés par le soignant en '
                '$days jours.',
            evidence: [for (final d in list.take(5)) 'Annulation du ${_d(d)}'],
            suggestedCheck:
                'Appeler le soignant pour comprendre (charge, trajet, '
                'santé) avant toute décision.',
          ),
        );
      }
    });

    // 2. Patient qui réserve puis annule souvent.
    final byOwner = <String, List<BookingFact>>{};
    for (final b in bookings) {
      if (b.ownerId != null && b.createdAt.isAfter(since)) {
        (byOwner[b.ownerId!] ??= []).add(b);
      }
    }
    byOwner.forEach((owner, list) {
      final cancelled = list
          .where((b) => b.cancelledBy == CancelledBy.patient)
          .toList();
      if (cancelled.length >= t.patientCancellations) {
        alerts.add(
          InsightAlert(
            code: 'patient_cancellations',
            severity: InsightSeverity.watch,
            title: 'Annulations répétées par un patient',
            subject: accountName(owner),
            detail:
                '${cancelled.length} annulations sur ${list.length} '
                'réservations en $days jours.',
            evidence: [
              for (final b in cancelled.take(5))
                '${b.serviceName} · ${b.proName} · ${_d(b.scheduledAt)}',
            ],
            suggestedCheck:
                'Vérifier si les soignants concernés ont été bloqués à tort '
                'et contacter le patient si besoin.',
          ),
        );
      }

      // 3. Part des remboursements anormalement élevée.
      final paid = list.where((b) => b.paid).toList();
      final paidSum = paid.fold<int>(0, (s, b) => s + b.price);
      final refunded = paid.fold<int>(0, (s, b) => s + b.refundAmount);
      if (paid.length >= 2 &&
          paidSum > 0 &&
          refunded / paidSum >= t.refundShare) {
        alerts.add(
          InsightAlert(
            code: 'refund_share',
            severity: InsightSeverity.watch,
            title: 'Remboursements élevés',
            subject: accountName(owner),
            detail:
                '${(100 * refunded / paidSum).round()} % des montants payés '
                'ont été remboursés ($refunded FCFA sur $paidSum FCFA).',
            evidence: [
              for (final b in paid.where((b) => b.refundAmount > 0).take(5))
                '${b.serviceName} · ${_d(b.scheduledAt)} · '
                    '${b.refundAmount} FCFA',
            ],
            suggestedCheck:
                'Relire les réclamations et gestes commerciaux de ce compte.',
          ),
        );
      }

      // 4. Rafale de réservations en 24 h.
      final sorted = [...list]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      var start = 0;
      var best = 0;
      DateTime? burstAt;
      for (var i = 0; i < sorted.length; i++) {
        while (sorted[i].createdAt.difference(sorted[start].createdAt) >
            const Duration(hours: 24)) {
          start++;
        }
        // Les séances d'un même suivi sont créées ensemble : ne comptent
        // qu'une fois (même soignant, même service, même minute).
        final window = sorted.sublist(start, i + 1);
        final distinct = {
          for (final b in window)
            '${b.proId}|${b.serviceName}|${b.createdAt.millisecondsSinceEpoch ~/ 60000}',
        }.length;
        if (distinct > best) {
          best = distinct;
          burstAt = sorted[i].createdAt;
        }
      }
      if (best >= t.burstBookings) {
        alerts.add(
          InsightAlert(
            code: 'booking_burst',
            severity: InsightSeverity.watch,
            title: 'Beaucoup de réservations en peu de temps',
            subject: accountName(owner),
            detail: '$best réservations distinctes en 24 h.',
            evidence: ['Dernière le ${_dt(burstAt!)}'],
            suggestedCheck:
                'Vérifier qu’il ne s’agit pas d’un compte partagé ou '
                'd’essais de paiement.',
          ),
        );
      }

      // 5. Avis 5 étoiles répétés d'un même compte pour un même soignant.
      final fives = <String, List<BookingFact>>{};
      for (final b in list.where((b) => b.rating == 5)) {
        (fives[b.proId] ??= []).add(b);
      }
      fives.forEach((proId, rated) {
        rated.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
        for (var i = 0; i + t.repeatedFiveStars - 1 < rated.length; i++) {
          final span = rated[i + t.repeatedFiveStars - 1].scheduledAt
              .difference(rated[i].scheduledAt);
          if (span <= const Duration(days: 7)) {
            alerts.add(
              InsightAlert(
                code: 'repeated_reviews',
                severity: InsightSeverity.info,
                title: 'Avis 5 étoiles répétés',
                subject: '${accountName(owner)} → ${proName(proId)}',
                detail:
                    '${rated.length} avis 5 étoiles du même compte pour le '
                    'même soignant, dont ${t.repeatedFiveStars} en 7 jours.',
                evidence: [
                  for (final b in rated.take(5))
                    '${b.serviceName} · ${_d(b.scheduledAt)}',
                ],
                suggestedCheck:
                    'Souvent un suivi régulier normal ; vérifier que les '
                    'soins ont bien eu lieu (journal de visite).',
              ),
            );
            break;
          }
        }
      });
    });

    // 6. Un soignant qui réserve chez lui-même (même numéro).
    final proPhones = <String, AccountFact>{
      for (final a in accounts.where((a) => a.kind == AccountKind.pro))
        if (normalizePhone(a.phone).isNotEmpty) normalizePhone(a.phone): a,
    };
    final selfBooked = <String, List<BookingFact>>{};
    for (final b in bookings) {
      final owner = b.ownerId == null ? null : byId[b.ownerId!];
      if (owner == null) continue;
      final pro = proPhones[normalizePhone(owner.phone)];
      if (pro != null && pro.id == b.proId) {
        (selfBooked[b.proId] ??= []).add(b);
      }
    }
    selfBooked.forEach((proId, list) {
      alerts.add(
        InsightAlert(
          code: 'self_booking',
          severity: InsightSeverity.high,
          title: 'Soignant réservé depuis son propre numéro',
          subject: proName(proId),
          detail:
              '${list.length} réservation(s) passée(s) par un compte patient '
              'qui a le même numéro que le soignant.',
          evidence: [
            for (final b in list.take(5))
              '${b.serviceName} · ${_d(b.scheduledAt)} · ${b.status}',
          ],
          suggestedCheck:
              'Peut gonfler les avis ou les revenus : vérifier les soins et '
              'les avis concernés.',
        ),
      );
    });

    // 7. Plusieurs réclamations récentes contre un même soignant.
    final complaintsByPro = <String, List<ComplaintFact>>{};
    for (final c in complaints) {
      if (c.proId != null && c.createdAt.isAfter(since)) {
        (complaintsByPro[c.proId!] ??= []).add(c);
      }
    }
    complaintsByPro.forEach((proId, list) {
      if (list.length >= t.complaintsPerPro) {
        final safety = list.any((c) => c.category == 'Sécurité du patient');
        alerts.add(
          InsightAlert(
            code: 'pro_complaints',
            severity: safety ? InsightSeverity.high : InsightSeverity.watch,
            title: 'Réclamations répétées',
            subject: proName(proId),
            detail: '${list.length} réclamations en $days jours.',
            evidence: [
              for (final c in list.take(5))
                '${c.category} · ${_d(c.createdAt)}',
            ],
            suggestedCheck: safety
                ? 'Sécurité du patient en cause : examen prioritaire par le '
                      'médecin coordinateur.'
                : 'Relire les réclamations et en parler au soignant.',
          ),
        );
      }
    });

    alerts.sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return alerts;
  }

  // ---------------------------------------------- réservations inhabituelles
  List<DayCount> dailyCounts(
    List<BookingFact> bookings,
    DateTime from,
    DateTime to,
  ) {
    final counts = <DateTime, int>{};
    for (final b in bookings) {
      final d = _day(b.createdAt);
      counts[d] = (counts[d] ?? 0) + 1;
    }
    return [
      for (var d = _day(from); d.isBefore(to); d = _next(d))
        DayCount(d, counts[d] ?? 0),
    ];
  }

  /// Compare chaque jour aux 28 jours précédents (moyenne, écart type) :
  /// un pic doit dépasser à la fois le seuil statistique et un écart
  /// minimal en nombre de réservations.
  List<BookingAnomaly> bookingAnomalies(
    List<BookingFact> bookings,
    DateTime from,
    DateTime to,
  ) {
    final all = dailyCounts(
      bookings,
      _day(from).subtract(const Duration(days: 28)),
      to,
    );
    final out = <BookingAnomaly>[];
    for (var i = 28; i < all.length; i++) {
      final history = all.sublist(i - 28, i).map((d) => d.count).toList();
      final mean = history.reduce((a, b) => a + b) / history.length;
      final variance =
          history.map((c) => (c - mean) * (c - mean)).reduce((a, b) => a + b) /
          history.length;
      final sd = math.max(math.sqrt(variance), 1.0);
      final c = all[i].count;
      final z = (c - mean) / sd;
      if (z >= thresholds.spikeZ && c - mean >= thresholds.spikeMinExtra) {
        final ofDay = bookings
            .where((b) => _day(b.createdAt) == all[i].day)
            .toList();
        out.add(
          BookingAnomaly(
            day: all[i].day,
            count: c,
            expected: mean,
            zScore: z,
            topCommune: _mostCommon(ofDay.map((b) => b.commune)),
            topService: _mostCommon(ofDay.map((b) => b.serviceName)),
          ),
        );
      }
    }
    return out;
  }

  // --------------------------------------------------------- doublons
  List<DuplicateGroup> duplicateAccounts(List<AccountFact> accounts) {
    final groups = <DuplicateGroup>[];
    final grouped = <String>{};
    final byPhone = <String, List<AccountFact>>{};
    for (final a in accounts) {
      final p = normalizePhone(a.phone);
      if (p.length >= 8) (byPhone[p] ??= []).add(a);
    }
    byPhone.forEach((phone, list) {
      // Un soignant peut aussi être patient : seul un doublon dans la même
      // catégorie est un vrai doublon ; l'autre cas est signalé à part
      // (réservation chez soi-même).
      final kinds = <AccountKind, List<AccountFact>>{};
      for (final a in list) {
        (kinds[a.kind] ??= []).add(a);
      }
      kinds.forEach((kind, same) {
        if (same.length > 1) {
          groups.add(
            DuplicateGroup(
              accounts: same,
              reason: 'Même numéro de téléphone',
              confidence: 1,
            ),
          );
          grouped.addAll(same.map((a) => a.id));
        }
      });
    });
    final byEmail = <String, List<AccountFact>>{};
    for (final a in accounts) {
      final e = a.email.trim().toLowerCase();
      if (e.contains('@')) (byEmail[e] ??= []).add(a);
    }
    byEmail.forEach((_, list) {
      final fresh = list.where((a) => !grouped.contains(a.id)).toList();
      if (list.length > 1 && fresh.isNotEmpty) {
        groups.add(
          DuplicateGroup(
            accounts: list,
            reason: 'Même adresse e-mail',
            confidence: 0.9,
          ),
        );
        grouped.addAll(list.map((a) => a.id));
      }
    });
    final byName = <String, List<AccountFact>>{};
    for (final a in accounts) {
      final n = normalizeName(a.name);
      if (n.split(' ').length >= 2) (byName['${a.kind.name}|$n'] ??= []).add(a);
    }
    byName.forEach((_, list) {
      if (list.length > 1 && list.any((a) => !grouped.contains(a.id))) {
        groups.add(
          DuplicateGroup(
            accounts: list,
            reason: 'Même nom, numéros différents',
            confidence: 0.6,
          ),
        );
      }
    });
    groups.sort((a, b) => b.confidence.compareTo(a.confidence));
    return groups;
  }

  // -------------------------------------------------- retours patients
  FeedbackAnalysis analyzeFeedback({
    required List<ReviewFact> reviews,
    required List<ComplaintFact> complaints,
    required DateTime now,
  }) {
    final topics = {for (final t in _topics.keys) t: TopicStat(t)};
    var pos = 0;
    var neg = 0;
    for (final r in reviews) {
      final s = sentiment(r.text, rating: r.rating);
      if (s > 0) pos++;
      if (s < 0) neg++;
      _tagTopics(r.text, s, topics);
    }
    for (final c in complaints) {
      _tagTopics(c.text, -1, topics);
    }
    final byCategory = <String, int>{};
    for (final c in complaints) {
      byCategory[c.category] = (byCategory[c.category] ?? 0) + 1;
    }
    // Soignants à suivre : moyenne des 30 derniers jours inférieure d'au
    // moins 0,7 point à leur moyenne générale (3 avis récents minimum).
    final watch = <String>[];
    final byPro = <String, List<ReviewFact>>{};
    for (final r in reviews) {
      (byPro[r.proId] ??= []).add(r);
    }
    byPro.forEach((_, list) {
      final recent = list
          .where((r) => now.difference(r.at).inDays <= 30)
          .toList();
      if (recent.length < 3) return;
      double avg(List<ReviewFact> l) =>
          l.fold<int>(0, (s, r) => s + r.rating) / l.length;
      if (avg(list) - avg(recent) >= 0.7 || avg(recent) < 3.5) {
        watch.add(list.first.proName);
      }
    });
    final total = reviews.length;
    return FeedbackAnalysis(
      reviewCount: total,
      averageRating: total == 0
          ? 0
          : reviews.fold<int>(0, (s, r) => s + r.rating) / total,
      positiveShare: total == 0 ? 0 : pos / total,
      negativeShare: total == 0 ? 0 : neg / total,
      topics: topics.values.where((t) => t.mentions > 0).toList()
        ..sort((a, b) => b.mentions.compareTo(a.mentions)),
      complaintsByCategory: byCategory,
      prosToWatch: watch,
    );
  }

  /// Sentiment par lexique : +1, 0 ou -1. La note, si elle existe, pèse
  /// autant que le texte.
  static int sentiment(String text, {int? rating}) {
    final t = ' ${fold(text)} ';
    var score = 0;
    for (final w in _positive) {
      if (t.contains(w)) score++;
    }
    for (final w in _negative) {
      if (t.contains(w)) score--;
    }
    // « pas ponctuel », « pas gentil » : la négation inverse un mot positif.
    for (final w in _positive) {
      if (t.contains('pas $w') ||
          t.contains('pas tres $w') ||
          t.contains('peu $w')) {
        score -= 2;
      }
    }
    if (rating != null) score += rating >= 4 ? 1 : (rating <= 2 ? -2 : 0);
    return score.sign;
  }

  void _tagTopics(String text, int s, Map<String, TopicStat> topics) {
    final t = ' ${fold(text)} ';
    _topics.forEach((topic, words) {
      if (words.any(t.contains)) {
        final stat = topics[topic]!;
        stat.mentions++;
        if (s > 0) stat.positive++;
        if (s < 0) stat.negative++;
        if (stat.examples.length < 3) stat.examples.add(_excerpt(text));
      }
    });
  }

  // ------------------------------------------------------------- rapport
  String operationalReport({
    required DateTime from,
    required DateTime to,
    required List<BookingFact> bookings,
    required List<InsightAlert> alerts,
    required List<BookingAnomaly> anomalies,
    required List<DuplicateGroup> duplicates,
    required FeedbackAnalysis feedback,
  }) {
    final n = bookings.length;
    int count(String s) => bookings.where((b) => b.status == s).length;
    final done = count('done');
    final cancelled = count('cancelled');
    final refused = count('refused');
    final byPro = bookings
        .where((b) => b.cancelledBy == CancelledBy.pro)
        .length;
    final volume = bookings
        .where((b) => b.status == 'done')
        .fold<int>(0, (s, b) => s + b.price);
    final night = bookings.where((b) => b.night).length;
    String pct(int x) => n == 0 ? '0 %' : '${(100 * x / n).round()} %';
    String top(Iterable<String> xs) {
      final c = <String, int>{};
      for (final x in xs) {
        c[x] = (c[x] ?? 0) + 1;
      }
      final e = c.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return e.take(3).map((e) => '${e.key} (${e.value})').join(', ');
    }

    final high = alerts.where((a) => a.severity == InsightSeverity.high);
    final b = StringBuffer()
      ..writeln('RAPPORT D’ACTIVITÉ MYNURSE')
      ..writeln('Du ${_d(from)} au ${_d(to.subtract(const Duration(days: 1)))}')
      ..writeln()
      ..writeln('1. Activité')
      ..writeln('- Demandes de soin : $n')
      ..writeln('- Soins réalisés : $done (${pct(done)})')
      ..writeln(
        '- Annulations : $cancelled (${pct(cancelled)}), dont $byPro par '
        'les soignants',
      )
      ..writeln('- Refus des soignants : $refused (${pct(refused)})')
      ..writeln('- Soins de nuit : $night')
      ..writeln('- Montant des soins réalisés : $volume FCFA');
    if (n > 0) {
      b
        ..writeln(
          '- Communes les plus actives : ${top(bookings.map((b) => b.commune))}',
        )
        ..writeln(
          '- Soins les plus demandés : ${top(bookings.map((b) => b.serviceName))}',
        );
    }
    b
      ..writeln()
      ..writeln('2. Points de vigilance')
      ..writeln(
        '- Signaux à vérifier : ${alerts.length}'
        '${high.isEmpty ? '' : ', dont ${high.length} prioritaires'}',
      );
    for (final a in alerts.take(5)) {
      b.writeln('  • ${a.title} — ${a.subject} : ${a.detail}');
    }
    b.writeln('- Jours inhabituels : ${anomalies.length}');
    for (final a in anomalies.take(3)) {
      b.writeln(
        '  • ${_d(a.day)} : ${a.count} demandes (habituel '
        '${a.expected.toStringAsFixed(1)}), surtout ${a.topCommune}',
      );
    }
    b
      ..writeln('- Comptes en double possibles : ${duplicates.length}')
      ..writeln()
      ..writeln('3. Satisfaction')
      ..writeln(
        '- Avis : ${feedback.reviewCount}'
        '${feedback.reviewCount == 0 ? '' : ', note moyenne ${feedback.averageRating.toStringAsFixed(1)}/5, '
                  '${(100 * feedback.positiveShare).round()} % positifs, '
                  '${(100 * feedback.negativeShare).round()} % négatifs'}',
      );
    for (final t in feedback.topics.take(4)) {
      b.writeln(
        '  • ${t.topic} : ${t.mentions} mention(s), ${t.positive} positive(s), '
        '${t.negative} négative(s)',
      );
    }
    if (feedback.complaintsByCategory.isNotEmpty) {
      b.writeln(
        '- Réclamations : ${feedback.complaintsByCategory.entries.map((e) => '${e.key} (${e.value})').join(', ')}',
      );
    }
    if (feedback.prosToWatch.isNotEmpty) {
      b.writeln(
        '- Soignants à accompagner : ${feedback.prosToWatch.join(', ')}',
      );
    }
    b
      ..writeln()
      ..writeln(
        'Signaux calculés automatiquement par des règles ; chaque cas doit '
        'être vérifié par l’équipe avant toute décision. Aucune donnée '
        'médicale n’est utilisée.',
      );
    return b.toString();
  }
}

// ============================================================= utilitaires

/// Numéro ivoirien ramené à ses 10 chiffres (indicatif 225 retiré).
String normalizePhone(String phone) {
  var d = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00225')) d = d.substring(5);
  if (d.startsWith('225') && d.length > 10) d = d.substring(3);
  return d;
}

/// Nom sans accents, sans titre, mots triés (« Dr Koné Ibrahim » =
/// « ibrahim kone »).
String normalizeName(String name) {
  final words =
      fold(name)
          .replaceAll(RegExp(r"[^a-z ]"), ' ')
          .split(RegExp(r'\s+'))
          .where(
            (w) => w.isNotEmpty && !const {'dr', 'mme', 'm', 'mr'}.contains(w),
          )
          .toList()
        ..sort();
  return words.join(' ');
}

const _topics = <String, List<String>>{
  'Ponctualité': [
    'retard',
    'ponctuel',
    'a l\'heure',
    'attendu',
    'attendre',
    'en avance',
    'pas venu',
  ],
  'Comportement': [
    'gentil',
    'aimable',
    'poli',
    'impoli',
    'respect',
    'douce',
    'doux',
    'agressi',
    'presse',
    'patient ',
  ],
  'Qualité du soin': [
    'soin',
    'pansement',
    'perfusion',
    'injection',
    'professionnel',
    'competent',
    'serieux',
    'douleur',
    'propre',
    'bien pose',
  ],
  'Communication': [
    'explication',
    'explique',
    'prevenu',
    'previent',
    'compte rendu',
    'repond',
    'appel',
    'injoignable',
  ],
  'Prix et paiement': [
    'prix',
    'cher',
    'tarif',
    'rembourse',
    'paiement',
    'payer',
    'argent',
  ],
};

const _positive = [
  'tres bien',
  'excellent',
  'parfait',
  'merci',
  'douce',
  'doux ',
  'gentil',
  'aimable',
  'ponctuel',
  'serieux',
  'professionnel',
  'competent',
  'claire',
  'rassurant',
  'recommande',
  'pris le temps',
  'bien pose',
  'a l\'heure',
];

const _negative = [
  'retard',
  'impoli',
  'pas venu',
  'jamais venu',
  'brutal',
  'douleur',
  'mal fait',
  'sale',
  'cher',
  'decu',
  'mauvais',
  'injoignable',
  'presse',
  'agressi',
  'arnaque',
  'vole',
  'probleme',
  'annule',
];

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _next(DateTime d) => DateTime(d.year, d.month, d.day + 1);
String _two(int n) => n.toString().padLeft(2, '0');
String _d(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';
String _dt(DateTime d) => '${_d(d)} ${_two(d.hour)}:${_two(d.minute)}';

String _mostCommon(Iterable<String> xs) {
  final c = <String, int>{};
  for (final x in xs) {
    c[x] = (c[x] ?? 0) + 1;
  }
  if (c.isEmpty) return '—';
  return (c.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
      .first
      .key;
}

String _excerpt(String s) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length <= 90 ? t : '${t.substring(0, 87)}…';
}
