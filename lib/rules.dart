/// Règles métier MyNurse, regroupées en un seul endroit.
///
/// Chaque règle a son équivalent côté serveur (supabase/migrations) : l'app
/// les applique pour guider l'utilisateur, le serveur les fait respecter.
library;

// ------------------------------------------------------------------ tarifs

/// Commission MyNurse prélevée sur chaque soin (10 %, décision de Jared du
/// 23/11/2026 ; avant : 15 %). Même taux côté serveur :
/// supabase/migrations/0007_commission_10.sql.
const commissionRate = 0.10;

/// Commission sur une séance de suivi régulier : identique à un soin ponctuel
/// depuis le 23/11/2026 (gardée à part si l'on veut la différencier un jour).
const contractCommissionRate = commissionRate;

/// Taux de commission en pourcentage entier, pour l'affichage (« 10 % »).
int get commissionPercent => (commissionRate * 100).round();

/// Majoration d'un soin de nuit (21 h – 6 h).
const nightSurchargeRate = 0.5;

/// Un soin est « de nuit » entre 21 h et 6 h.
bool isNight(DateTime d) => d.hour >= 21 || d.hour < 6;

/// Prix payé par le patient pour un soin.
int careFee(int basePrice, DateTime at) =>
    isNight(at) ? (basePrice * (1 + nightSurchargeRate)).round() : basePrice;

// --------------------------------------------------------------- calendrier

/// Délai minimum entre la réservation et le soin, pour que le soignant ait
/// le temps de se déplacer.
const minNotice = Duration(hours: 1);

/// On ne réserve pas plus de 60 jours à l'avance.
const maxAdvance = Duration(days: 60);

/// Le soignant a 2 heures pour répondre (et jamais après l'heure du soin).
const responseWindow = Duration(hours: 2);

/// Le patient a 2 heures pour payer après la confirmation.
const paymentWindow = Duration(hours: 2);

/// Le compte rendu peut être rédigé à partir de 30 minutes avant le soin.
const careLogEarliest = Duration(minutes: 30);

/// Deux créneaux se chevauchent-ils ?
bool overlaps(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) =>
    aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

DateTime earliest(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

// ---------------------------------------------------------------- annulation

/// Annulation gratuite jusqu'à 2 heures avant le soin.
const freeCancellationWindow = Duration(hours: 2);

/// En deçà, la moitié du prix revient au soignant qui s'était libéré.
const lateCancellationFeeRate = 0.5;

/// Part retenue sur un soin payé annulé par le patient à [now].
int lateCancellationFee({
  required int price,
  required DateTime scheduledAt,
  required DateTime now,
}) => scheduledAt.difference(now) >= freeCancellationWindow
    ? 0
    : (price * lateCancellationFeeRate).round();

/// Au-delà de 2 annulations par un soignant en 30 jours, l'administration
/// est alertée.
const proCancellationAlertCount = 2;
const proCancellationAlertPeriod = Duration(days: 30);

/// Un soignant noté sous 4/5 (après 3 notes) est signalé.
const ratingAlertThreshold = 4.0;

// ------------------------------------------------------------- suivi régulier

enum Frequency { daily, everyOtherDay, weekly }

extension FrequencyLabel on Frequency {
  String get label => switch (this) {
    Frequency.daily => 'Tous les jours',
    Frequency.everyOtherDay => 'Un jour sur deux',
    Frequency.weekly => 'Une fois par semaine',
  };

  Duration get step => switch (this) {
    Frequency.daily => const Duration(days: 1),
    Frequency.everyOtherDay => const Duration(days: 2),
    Frequency.weekly => const Duration(days: 7),
  };
}

const contractMinSessions = 2;
const contractMaxSessions = 30;

/// Dates des séances d'un suivi, à la même heure.
List<DateTime> sessionDates(DateTime first, Frequency f, int sessions) => [
  for (var i = 0; i < sessions; i++)
    DateTime(
      first.year,
      first.month,
      first.day + i * f.step.inDays,
      first.hour,
      first.minute,
    ),
];

// ---------------------------------------------------------------- Pro Premium

/// Abonnement Pro Premium : mise en avant dans les résultats et statistiques.
const premiumPrice = 5000;
const premiumPeriod = Duration(days: 30);

/// Un mois de Premium offert au parrain quand le filleul est vérifié.
const referralBonus = Duration(days: 30);

/// Prolonge un abonnement à partir de sa fin, ou de maintenant s'il a expiré.
DateTime extendPremium(DateTime? until, DateTime now, Duration by) =>
    (until != null && until.isAfter(now) ? until : now).add(by);
