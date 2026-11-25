import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'settings.dart';
import 'verification.dart';
import 'visit.dart';

/// Profil professionnel : statut de vérification, activité, réputation,
/// réglages.
class ProProfileTab extends StatelessWidget {
  const ProProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.currentPro!;
    final status = p.statusAt(app.now);
    void open(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionTitle('Profil'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      ProAvatar(p, radius: 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text('${p.type.label} · ${p.yearsExperience} ans'),
                            const SizedBox(height: 6),
                            RatingLine(p),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        status == VerificationStatus.verified
                            ? Icons.verified
                            : Icons.error_outline,
                        color: status == VerificationStatus.verified
                            ? brandGreen
                            : const Color(0xFF8A5A00),
                      ),
                      title: const Text('Vérification'),
                      subtitle: Text(
                        p.expiringDocs(app.now).isEmpty
                            ? status.label
                            : '${status.label} · ${p.expiringDocs(app.now).length} pièce(s) à renouveler',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => open(const VerificationScreen()),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.sell_outlined),
                      title: const Text('Soins et tarifs'),
                      subtitle: Text(
                        '${p.prices.length} soin${p.prices.length > 1 ? 's' : ''} proposé${p.prices.length > 1 ? 's' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => open(const ServicesScreen()),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: const Text('Disponibilités'),
                      subtitle: Text(app.availabilitySummary(p)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => open(const AvailabilityScreen()),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text('Mes patients'),
                      subtitle: Text('${app.proPatients.length} suivis'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => open(const ProPatientsScreen()),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.star_outline),
                      title: const Text('Avis et réputation'),
                      subtitle: Text(
                        '${p.rating.toStringAsFixed(1).replaceAll('.', ',')}/5 · ${p.ratingCount} notes',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => open(const ReputationScreen()),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.report_gmailerrorred_outlined),
                      title: const Text('Incidents signalés'),
                      subtitle: Text(
                        app.incidents.isEmpty
                            ? 'Aucun'
                            : '${app.incidents.length} envoyé(s)',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => open(const IncidentsScreen()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Zones couvertes',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in communes)
                            FilterChip(
                              label: Text(c),
                              selected: p.communes.contains(c),
                              onSelected: (on) {
                                final next = communes
                                    .where(
                                      (x) =>
                                          x == c ? on : p.communes.contains(x),
                                    )
                                    .toList();
                                if (next.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Gardez au moins une commune.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                runAction(
                                  context,
                                  () => app.updateProAvailability(
                                    p,
                                    communes: next,
                                    nightAvailable: p.nightAvailable,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: p.nightAvailable,
                        onChanged: (v) => runAction(
                          context,
                          () => app.updateProAvailability(
                            p,
                            communes: p.communes,
                            nightAvailable: v,
                          ),
                        ),
                        title: const Text('Disponible la nuit'),
                        subtitle: const Text('21 h – 6 h, majoration de 50 %'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _PremiumCard(pro: p),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.group_add_outlined),
                  title: Text('Mon code de parrainage : ${p.referralCode}'),
                  subtitle: Text(
                    'Donnez-le à un collègue soignant : ${referralBonus.inDays} '
                    'jours de Premium offerts dès que son compte est vérifié.',
                  ),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: app.logout,
                icon: const Icon(Icons.logout),
                label: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Patients suivis et historique de mes soins pour chacun.
class ProPatientsScreen extends StatelessWidget {
  const ProPatientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.proPatients;
    return Scaffold(
      appBar: AppBar(title: const Text('Mes patients')),
      body: ContentWidth(
        child: list.isEmpty
            ? const EmptyState(
                icon: Icons.people_outline,
                text: 'Vos patients apparaissent ici après un soin accepté.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  const Text(
                    'Le dossier de chaque patient s’ouvre seulement pendant un '
                    'soin en cours (jusqu’à 24 h après). Votre propre historique '
                    'de soins reste visible.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  for (final pt in list)
                    Builder(
                      builder: (context) {
                        final h = app.proHistory(pt);
                        final done = h.where(
                          (b) => b.status == BookingStatus.done,
                        );
                        final next = h
                            .where((b) => b.status == BookingStatus.accepted)
                            .lastOrNull;
                        return Card(
                          child: ExpansionTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person),
                            ),
                            title: Text(pt.name),
                            subtitle: Text(
                              '${done.length} soin${done.length > 1 ? 's' : ''} réalisé${done.length > 1 ? 's' : ''}'
                              '${next == null ? '' : ' · prochain ${dateTimeLabel(next.scheduledAt)}'}',
                            ),
                            children: [
                              for (final b in h)
                                ListTile(
                                  dense: true,
                                  title: Text(
                                    '${b.service.name.split(' (').first} · ${dateTimeLabel(b.scheduledAt)}',
                                  ),
                                  subtitle: Text(
                                    b.careLog?.acts ?? b.status.label,
                                  ),
                                  trailing: b.vitals.isEmpty
                                      ? null
                                      : Text('${b.vitals.length} mesure(s)'),
                                  onTap: () => openBooking(context, b),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
      ),
    );
  }
}

/// Avis, note moyenne et indicateurs de fiabilité.
class ReputationScreen extends StatelessWidget {
  const ReputationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.currentPro!;
    final dist = app.ratingDistribution(p);
    final maxD = dist.fold<int>(1, (m, v) => v > m ? v : m);
    final stats = app.proStats(p);
    final response = app.proResponseTime(p);
    final cancels = p.recentCancellations(app.now);
    return Scaffold(
      appBar: AppBar(title: const Text('Avis et réputation')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Row(
              children: [
                Text(
                  p.rating.toStringAsFixed(1).replaceAll('.', ','),
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 4; i >= 0; i--)
                        Row(
                          children: [
                            SizedBox(width: 18, child: Text('${i + 1}')),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: dist[i] / maxD,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(3),
                                backgroundColor: const Color(0xFFE4E8EA),
                                color: const Color(0xFFE8A317),
                              ),
                            ),
                            SizedBox(
                              width: 28,
                              child: Text(
                                '${dist[i]}',
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Text(
              '${p.ratingCount} notes de patients ayant eu un soin terminé.',
              style: const TextStyle(color: Colors.black54),
            ),
            const BlockTitle('Fiabilité (30 jours)'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.task_alt),
                    title: const Text('Taux d’acceptation'),
                    trailing: Text('${stats.acceptance} %'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Délai moyen de réponse'),
                    trailing: Text(
                      response == null ? '–' : '${response.inMinutes} min',
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.event_busy,
                      color: cancels >= proCancellationAlertCount
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    title: const Text('Soins annulés par vous'),
                    subtitle: cancels >= proCancellationAlertCount
                        ? const Text(
                            'Au-delà de ce seuil, MyNurse revoit votre compte.',
                          )
                        : null,
                    trailing: Text('$cancels'),
                  ),
                ],
              ),
            ),
            if (p.ratingAlert)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: InfoBanner(
                  icon: Icons.trending_down,
                  warning: true,
                  text:
                      'Votre note passe sous 4/5 : l’équipe MyNurse vous '
                      'contactera pour en parler.',
                ),
              ),
            const BlockTitle('Derniers avis'),
            if (p.reviews.isEmpty)
              const Text(
                'Pas encore d’avis.',
                style: TextStyle(color: Colors.black54),
              ),
            for (final r in p.reviews.take(20))
              Card(
                child: ListTile(
                  title: Row(
                    children: [
                      for (var i = 0; i < 5; i++)
                        Icon(
                          i < r.rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 16,
                          color: const Color(0xFFE8A317),
                        ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          [
                            r.serviceName,
                            dateTimeLabel(r.at).split(' à ').first,
                          ].where((e) => e.isNotEmpty).join(' · '),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  subtitle: r.comment.isEmpty ? null : Text('« ${r.comment} »'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Incidents signalés et nouveau signalement.
class IncidentsScreen extends StatelessWidget {
  const IncidentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Incidents')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showIncidentSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Signaler'),
      ),
      body: ContentWidth(
        child: app.incidents.isEmpty
            ? const EmptyState(
                icon: Icons.health_and_safety_outlined,
                text:
                    'Aucun incident. Patient en danger, agression, erreur de '
                    'soin, matériel : signalez-le, l’équipe MyNurse vous aide.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                children: [
                  for (final i in app.incidents)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          i.category.urgent
                              ? Icons.priority_high_rounded
                              : Icons.report_outlined,
                          color: i.category.urgent
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                        title: Text(i.category.label),
                        subtitle: Text(
                          [
                            '${i.status} · ${dateTimeLabel(i.at)}',
                            if (i.booking != null)
                              '${i.booking!.service.name} · ${i.booking!.patientName}',
                            i.description,
                          ].join('\n'),
                        ),
                        isThreeLine: true,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.pro});

  final Pro pro;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final active = pro.isPremium(app.now);
    final stats = app.proStats(pro);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.workspace_premium_outlined,
                  color: Color(0xFFB8860B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active
                        ? 'Pro Premium jusqu’au ${dateTimeLabel(pro.premiumUntil!)}'
                        : 'Pro Premium',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Suivez vos chiffres (acceptation, gains, tendance). Le '
              'classement des patients ne dépend pas de l’abonnement : il suit '
              'la qualité, la disponibilité et la proximité. ${fcfa(premiumPrice)} pour '
              '${premiumPeriod.inDays} jours, payés avec votre solde.',
              style: const TextStyle(color: Colors.black54),
            ),
            if (active) ...[
              const Divider(height: 24),
              const Text(
                'Vos 30 derniers jours',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '${stats.cares} soin${stats.cares > 1 ? 's' : ''} terminé${stats.cares > 1 ? 's' : ''} · ${fcfa(stats.earnings)} gagnés',
              ),
              Text('Taux d’acceptation : ${stats.acceptance} %'),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await runAction(
                  context,
                  () => app.subscribePremium(pro),
                );
                if (ok) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Pro Premium activé jusqu’au ${dateTimeLabel(pro.premiumUntil!)}.',
                      ),
                    ),
                  );
                }
              },
              child: Text(
                active
                    ? 'Prolonger de ${premiumPeriod.inDays} jours (${fcfa(premiumPrice)})'
                    : 'Passer Premium (${fcfa(premiumPrice)})',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
