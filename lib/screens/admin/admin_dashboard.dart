import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import 'admin_shell.dart';
import 'admin_widgets.dart';

/// Tableau de bord : les indicateurs clés de la période, l'évolution, et
/// ce qui attend une action de l'équipe.
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key, required this.period, required this.onOpen});

  final Period period;
  final ValueChanged<AdminModule> onOpen;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.adminMetrics(period);
    final daily = app.adminDaily(period);
    final queue = app.verificationQueue;
    final urgent = app.incidents
        .where((i) => i.category.urgent && i.status != 'Traité')
        .toList();
    final openComplaints = app.complaints
        .where(
          (c) =>
              c.status == ComplaintStatus.open ||
              c.status == ComplaintStatus.inReview,
        )
        .toList();
    void go(AdminModule mod) {
      if (mod.permission == null || app.hasAdminPerm(mod.permission!)) {
        onOpen(mod);
      }
    }

    final cancelRate = m.appointments == 0
        ? 0
        : (m.cancelled * 100 / m.appointments).round();
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        ModuleHeader(
          title: 'Vue d’ensemble',
          subtitle: '${period.label} · données de démonstration en mode démo',
          actions: [
            ExportButton(
              title: 'Rapport d’activité',
              csv: () => app.adminReportCsv(period),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: MetricGrid(
            children: [
              MetricCard(
                icon: Icons.groups_outlined,
                label: 'Patients inscrits',
                value: '${m.patients}',
                hint: 'total',
                onTap: () => go(AdminModule.patients),
              ),
              MetricCard(
                icon: Icons.verified_outlined,
                label: 'Soignants vérifiés',
                value: '${m.verifiedPros}',
                hint: 'pièces à jour',
                onTap: () => go(AdminModule.pros),
              ),
              MetricCard(
                icon: Icons.fact_check_outlined,
                label: 'Vérifications en attente',
                value: '${m.pendingVerifications}',
                alert: m.pendingVerifications > 0,
                hint: 'dossiers à examiner',
                onTap: () => go(AdminModule.documents),
              ),
              MetricCard(
                icon: Icons.event_note_outlined,
                label: 'Rendez-vous',
                value: '${m.appointments}',
                hint: 'créés sur la période',
                onTap: () => go(AdminModule.appointments),
              ),
              MetricCard(
                icon: Icons.task_alt,
                label: 'Soins réalisés',
                value: '${m.completed}',
              ),
              MetricCard(
                icon: Icons.event_busy,
                label: 'Annulés ou refusés',
                value: '${m.cancelled}',
                hint: '$cancelRate % des rendez-vous',
                alert: cancelRate >= 20,
              ),
              MetricCard(
                icon: Icons.payments_outlined,
                label: 'Volume des transactions',
                value: fcfa(m.volume),
                hint: 'soins réalisés',
                onTap: () => go(AdminModule.finance),
              ),
              MetricCard(
                icon: Icons.percent,
                label: 'Commissions MyNurse',
                value: fcfa(m.commissions),
                onTap: () => go(AdminModule.commissions),
              ),
              MetricCard(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Gains des soignants',
                value: fcfa(m.proEarnings),
              ),
              MetricCard(
                icon: Icons.timer_outlined,
                label: 'Délai moyen de réponse',
                value: m.responseMinutes == null
                    ? '–'
                    : '${m.responseMinutes} min',
                alert: (m.responseMinutes ?? 0) > 90,
              ),
              MetricCard(
                icon: Icons.star_outline,
                label: 'Satisfaction',
                value: m.satisfaction == null
                    ? '–'
                    : '${m.satisfaction!.toStringAsFixed(1).replaceAll('.', ',')}/5',
                hint: '${m.ratings} note(s) sur la période',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rendez-vous créés par jour',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  DailyBars(
                    values: [for (final d in daily) d.count],
                    labels: [
                      for (final d in daily) '${d.day.day}/${d.day.month}',
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 900;
              final cards = [
                _QueueCard(
                  title: 'Dossiers à vérifier',
                  empty: 'Aucun dossier en attente.',
                  items: [
                    for (final p in queue)
                      (
                        p.name,
                        '${p.type.label} · ${p.statusAt(app.now).label}',
                      ),
                  ],
                  onOpen: () => go(AdminModule.documents),
                ),
                _QueueCard(
                  title: 'Incidents graves',
                  empty: 'Aucun incident grave ouvert.',
                  danger: true,
                  items: [
                    for (final i in urgent)
                      (
                        i.category.label,
                        '${dateTimeLabel(i.at)} · ${i.status}',
                      ),
                  ],
                  onOpen: () => go(AdminModule.incidents),
                ),
                _QueueCard(
                  title: 'Réclamations ouvertes',
                  empty: 'Aucune réclamation ouverte.',
                  items: [
                    for (final c in openComplaints)
                      (
                        c.category.label,
                        '${c.status.label} · ${dateTimeLabel(c.createdAt)}',
                      ),
                  ],
                  onOpen: () => go(AdminModule.complaints),
                ),
              ];
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final c in cards)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: c,
                            ),
                          ),
                      ],
                    )
                  : Column(
                      children: [
                        for (final c in cards)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: c,
                          ),
                      ],
                    );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            'Les indicateurs ne contiennent aucune donnée médicale. L’équipe '
            'n’accède à un dossier qu’en urgence, avec un motif enregistré et '
            'communiqué à la famille.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.title,
    required this.empty,
    required this.items,
    required this.onOpen,
    this.danger = false,
  });

  final String title;
  final String empty;
  final List<(String, String)> items;
  final VoidCallback onOpen;
  final bool danger;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (items.isNotEmpty)
                Pill(
                  '${items.length}',
                  color: danger ? const Color(0xFF9C2B12) : adminBlue,
                ),
              TextButton(onPressed: onOpen, child: const Text('Ouvrir')),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(empty, style: const TextStyle(color: Colors.black54)),
            ),
          for (final (a, b) in items.take(4))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(a),
              subtitle: Text(b),
            ),
        ],
      ),
    ),
  );
}
