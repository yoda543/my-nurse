import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../intelligence/admin_insights.dart';
import '../../models.dart';
import 'admin_widgets.dart';

/// Intelligence : signaux à vérifier, pics de réservations, comptes en
/// double, retours patients, rapport d'activité. Aucune donnée médicale ;
/// aucun signal ne déclenche de sanction : l'équipe vérifie et décide.
class IntelligenceModule extends StatelessWidget {
  const IntelligenceModule({super.key, required this.period});

  final Period period;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final r = app.adminInsights(period);
    final high = r.alerts.where((a) => a.severity == InsightSeverity.high);
    Widget card(String title, Widget child, {String? hint}) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (hint != null)
                Text(
                  hint,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
    const muted = TextStyle(color: Colors.black54);
    final f = r.feedback;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ModuleHeader(
          title: 'Intelligence',
          subtitle: period.label,
          actions: [
            ExportButton(title: 'Rapport d’activité', csv: () => r.text),
          ],
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE6EDFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Signaux calculés par des règles, sur les données d’activité '
            'seulement (aucune donnée médicale, rien n’est envoyé à un '
            'service d’IA). Un signal n’est pas une preuve : vérifiez avant '
            'toute décision.',
            style: TextStyle(fontSize: 13, color: Color(0xFF1E3A8A)),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: MetricGrid(
            children: [
              MetricCard(
                label: 'Signaux à vérifier',
                value: '${r.alerts.length}',
                hint: '${high.length} prioritaire(s)',
                icon: Icons.policy_outlined,
                alert: high.isNotEmpty,
              ),
              MetricCard(
                label: 'Jours inhabituels',
                value: '${r.anomalies.length}',
                icon: Icons.show_chart,
              ),
              MetricCard(
                label: 'Comptes en double possibles',
                value: '${r.duplicates.length}',
                icon: Icons.people_alt_outlined,
              ),
              MetricCard(
                label: 'Satisfaction',
                value: f.reviewCount == 0
                    ? '–'
                    : '${f.averageRating.toStringAsFixed(1)}/5',
                hint: f.reviewCount == 0
                    ? 'Aucun avis'
                    : '${(100 * f.positiveShare).round()} % d’avis positifs',
                icon: Icons.sentiment_satisfied_alt_outlined,
              ),
            ],
          ),
        ),
        card(
          'Activité suspecte',
          r.alerts.isEmpty
              ? const Text('Aucun signal sur la période.', style: muted)
              : Column(
                  children: [for (final a in r.alerts) _AlertTile(alert: a)],
                ),
        ),
        card(
          'Réservations par jour',
          hint:
              'Un jour est inhabituel quand il dépasse nettement les 28 jours '
              'précédents.',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DailyBars(
                values: [for (final d in r.daily) d.count],
                labels: [
                  for (final d in r.daily) '${d.day.day}/${d.day.month}',
                ],
              ),
              for (final a in r.anomalies)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.trending_up,
                    color: Color(0xFF9C2B12),
                  ),
                  title: Text(
                    '${a.day.day}/${a.day.month} : ${a.count} demandes '
                    '(habituellement ${a.expected.toStringAsFixed(1)})',
                  ),
                  subtitle: Text('Surtout ${a.topCommune} · ${a.topService}'),
                ),
            ],
          ),
        ),
        card(
          'Comptes en double possibles',
          r.duplicates.isEmpty
              ? const Text('Aucun doublon détecté.', style: muted)
              : Column(
                  children: [
                    for (final g in r.duplicates)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Pill(
                          '${(g.confidence * 100).round()} %',
                          color: g.confidence >= 0.9
                              ? const Color(0xFF9C2B12)
                              : adminBlue,
                        ),
                        title: Text(g.reason),
                        subtitle: Text(
                          g.accounts
                              .map(
                                (a) =>
                                    '${a.kindLabel} · ${a.name} · '
                                    '${a.phone.isEmpty ? 'sans numéro' : a.phone}',
                              )
                              .join('\n'),
                        ),
                      ),
                  ],
                ),
        ),
        card(
          'Retours patients',
          hint: 'Sujets repérés dans les avis et les réclamations.',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (f.topics.isEmpty)
                const Text('Aucun avis sur la période.', style: muted),
              for (final t in f.topics)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(t.topic),
                  subtitle: Text(
                    '${t.mentions} mention(s) · ${t.positive} positive(s) · '
                    '${t.negative} négative(s)',
                  ),
                  children: [
                    for (final e in t.examples)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('« $e »', style: muted),
                        ),
                      ),
                  ],
                ),
              if (f.complaintsByCategory.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Réclamations par motif',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                BarList(data: f.complaintsByCategory),
              ],
              if (f.prosToWatch.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Soignants à accompagner (avis récents en baisse) : '
                  '${f.prosToWatch.join(', ')}',
                ),
              ],
            ],
          ),
        ),
        card(
          'Rapport d’activité',
          SelectableText(
            r.text,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});

  final InsightAlert alert;

  @override
  Widget build(BuildContext context) {
    final a = alert;
    final color = switch (a.severity) {
      InsightSeverity.high => const Color(0xFF9C2B12),
      InsightSeverity.watch => const Color(0xFF8A5A00),
      InsightSeverity.info => adminBlue,
    };
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: Icon(Icons.flag_outlined, color: color),
      title: Text(
        '${a.title} · ${a.subject}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Pill(a.severity.label, color: color),
          Text(a.detail),
        ],
      ),
      childrenPadding: const EdgeInsets.only(left: 40, bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in a.evidence) Text('• $e'),
        const SizedBox(height: 6),
        Text(
          'À vérifier : ${a.suggestedCheck}',
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}
