import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'admin_widgets.dart';

// ================================================================ pharmacies
class PharmaciesModule extends StatefulWidget {
  const PharmaciesModule({super.key});

  @override
  State<PharmaciesModule> createState() => _PharmaciesModuleState();
}

class _PharmaciesModuleState extends State<PharmaciesModule> {
  String? _commune;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list =
        app.pharmacies
            .where((p) => _commune == null || p.commune == _commune)
            .toList()
          ..sort((a, b) {
            final c = a.commune.compareTo(b.commune);
            return c != 0 ? c : a.name.compareTo(b.name);
          });
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ModuleHeader(
          title: 'Pharmacies',
          subtitle:
              '${app.pharmacies.where((p) => p.onDutyAt(app.now)).length} de garde maintenant',
          actions: [
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => _edit(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
            ExportButton(
              title: 'Pharmacies',
              csv: () => app.toCsv(
                ['Nom', 'Commune', 'Adresse', 'Téléphone', 'De garde jusqu’au'],
                [
                  for (final p in list)
                    [
                      p.name,
                      p.commune,
                      p.address,
                      p.phone,
                      p.onDutyUntil?.toIso8601String().substring(0, 16) ?? '',
                    ],
                ],
              ),
            ),
          ],
        ),
        FilterRow<String>(
          values: communes,
          selected: _commune,
          label: (c) => c,
          allLabel: 'Toutes',
          onSelected: (c) => setState(() => _commune = c),
        ),
        for (final p in list)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(
              Icons.local_pharmacy,
              color: p.onDutyAt(app.now) ? brandGreen : Colors.black38,
            ),
            title: Text(p.name),
            subtitle: Text(
              '${p.commune} · ${p.address}'
              '${p.onDutyAt(app.now) ? '\nDe garde jusqu’au ${dateTimeLabel(p.onDutyUntil!)}' : ''}',
            ),
            isThreeLine: p.onDutyAt(app.now),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') return _edit(context, p);
                if (v == 'duty') {
                  final today = DateTime(
                    app.now.year,
                    app.now.month,
                    app.now.day,
                  );
                  await runAction(
                    context,
                    () => app.adminSavePharmacy(
                      Pharmacy(
                        id: p.id,
                        name: p.name,
                        commune: p.commune,
                        address: p.address,
                        phone: p.phone,
                        location: p.location,
                        hours: p.hours,
                        onDutyFrom: p.onDutyAt(app.now)
                            ? null
                            : today.subtract(const Duration(hours: 4)),
                        onDutyUntil: p.onDutyAt(app.now)
                            ? null
                            : today.add(const Duration(days: 7, hours: 8)),
                      ),
                      replacing: p,
                    ),
                  );
                }
                if (v == 'remove' && context.mounted) {
                  await runAction(context, () => app.adminRemovePharmacy(p));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                PopupMenuItem(
                  value: 'duty',
                  child: Text(
                    p.onDutyAt(app.now)
                        ? 'Fin de garde'
                        : 'De garde cette semaine',
                  ),
                ),
                const PopupMenuItem(value: 'remove', child: Text('Retirer')),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, Pharmacy? p) async {
    final app = AppScope.of(context);
    final name = TextEditingController(text: p?.name);
    final address = TextEditingController(text: p?.address);
    final phone = TextEditingController(text: p?.phone);
    var commune = p?.commune ?? communes.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            p == null ? 'Nouvelle pharmacie' : 'Modifier la pharmacie',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: commune,
                  decoration: const InputDecoration(labelText: 'Commune'),
                  items: [
                    for (final c in communes)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (c) => setState(() => commune = c!),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(
                    labelText: 'Adresse et repère',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Téléphone'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await runAction(
        context,
        () => app.adminSavePharmacy(
          Pharmacy(
            id: p?.id ?? 'new-${app.now.millisecondsSinceEpoch}',
            name: name.text.trim(),
            commune: commune,
            address: address.text.trim(),
            phone: phone.text.trim(),
            location: p?.location,
            hours: p?.hours ?? '',
            onDutyFrom: p?.onDutyFrom,
            onDutyUntil: p?.onDutyUntil,
          ),
          replacing: p,
        ),
      );
    }
    name.dispose();
    address.dispose();
    phone.dispose();
  }
}

// =================================================================== messages
class BroadcastModule extends StatefulWidget {
  const BroadcastModule({super.key});

  @override
  State<BroadcastModule> createState() => _BroadcastModuleState();
}

class _BroadcastModuleState extends State<BroadcastModule> {
  BroadcastAudience _audience = BroadcastAudience.all;
  final _title = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final staffNotes =
        app.notifications.where((n) => n.recipient == 'admin').toList()
          ..sort((a, b) => b.at.compareTo(a.at));
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const ModuleHeader(
          title: 'Messages et notifications',
          subtitle: 'Message d’information aux patients ou aux soignants',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final a in BroadcastAudience.values)
                        ChoiceChip(
                          label: Text(a.label),
                          selected: _audience == a,
                          onSelected: (_) => setState(() => _audience = a),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Titre'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _body,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pas de donnée médicale ni d’information personnelle dans un '
                    'message collectif.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ActionButton(
                    label: 'Envoyer',
                    icon: Icons.send,
                    onPressed: () async {
                      final n = await app.adminBroadcast(
                        _audience,
                        _title.text,
                        _body.text,
                      );
                      _title.clear();
                      _body.clear();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Message envoyé à $n compte(s).'),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: BlockTitle('Messages envoyés'),
        ),
        if (app.broadcasts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Aucun message envoyé.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        for (final b in app.broadcasts)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.campaign_outlined),
            title: Text(b.title),
            subtitle: Text(
              '${b.audience.label} · ${b.recipients} destinataire(s) · ${dateTimeLabel(b.at)} · ${b.by}\n${b.body}',
            ),
            isThreeLine: true,
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: BlockTitle('Alertes reçues par l’équipe'),
        ),
        for (final n in staffNotes.take(30))
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            dense: true,
            leading: Icon(
              n.title.startsWith('Urgent')
                  ? Icons.priority_high_rounded
                  : Icons.notifications_none,
              color: n.title.startsWith('Urgent')
                  ? const Color(0xFF9C2B12)
                  : null,
            ),
            title: Text(n.title),
            subtitle: Text('${dateTimeLabel(n.at)} · ${n.body}'),
          ),
      ],
    );
  }
}

// ============================================================== statistiques
class AnalyticsModule extends StatelessWidget {
  const AnalyticsModule({super.key, required this.period});

  final Period period;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.adminMetrics(period);
    final daily = app.adminDaily(period);
    final created = app.bookings
        .where((b) => period.contains(b.createdAt))
        .toList();
    final accepted = created.where((b) => b.acceptedAt != null).length;
    final pros = app.pros.where((p) => p.activeAt(app.now)).toList()
      ..sort((a, b) => b.careCount.compareTo(a.careCount));
    Widget card(String title, Widget child) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ModuleHeader(
          title: 'Statistiques',
          subtitle: period.label,
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
                label: 'Taux d’acceptation',
                value: created.isEmpty
                    ? '–'
                    : '${(accepted * 100 / created.length).round()} %',
                hint: '$accepted / ${created.length} demandes',
              ),
              MetricCard(
                label: 'Panier moyen',
                value: m.completed == 0 ? '–' : fcfa(m.volume ~/ m.completed),
              ),
              MetricCard(
                label: 'Satisfaction',
                value: m.satisfaction == null
                    ? '–'
                    : '${m.satisfaction!.toStringAsFixed(1).replaceAll('.', ',')}/5',
              ),
            ],
          ),
        ),
        card(
          'Volume réalisé par jour (FCFA)',
          DailyBars(
            values: [for (final d in daily) d.volume],
            labels: [for (final d in daily) '${d.day.day}/${d.day.month}'],
          ),
        ),
        card(
          'Rendez-vous par soin',
          BarList(data: app.adminBreakdown(period, byCommune: false)),
        ),
        card(
          'Rendez-vous par commune',
          BarList(data: app.adminBreakdown(period, byCommune: true)),
        ),
        card(
          'Soignants les plus actifs',
          Column(
            children: [
              for (final p in pros.take(5))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: ProAvatar(p, radius: 16),
                  title: Text(p.name),
                  subtitle: Text(p.type.label),
                  trailing: Text(
                    '${p.careCount} soins · ${p.rating.toStringAsFixed(1).replaceAll('.', ',')}/5',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ======================================================== journal d'activité
class LogsModule extends StatefulWidget {
  const LogsModule({super.key, required this.period});

  final Period period;

  @override
  State<LogsModule> createState() => _LogsModuleState();
}

class _LogsModuleState extends State<LogsModule> {
  String _q = '';
  bool _healthOnly = false;
  Future<List<AdminLogEntry>>? _remote;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (app.isRemote) {
      _remote ??= app.remote!.adminAuditEvents(widget.period.from);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    Widget list(List<AdminLogEntry> all) {
      final rows = all
          .where((e) => widget.period.contains(e.at))
          .where((e) => !_healthOnly || e.patientId != null)
          .where((e) {
            final q = _q.trim().toLowerCase();
            return q.isEmpty ||
                '${e.actor} ${e.action} ${e.target} ${e.details}'
                    .toLowerCase()
                    .contains(q);
          })
          .toList();
      return Column(
        children: [
          ModuleHeader(
            title: 'Journal d’activité',
            subtitle:
                '${rows.length} action(s) · conservé sans modification possible',
            actions: [
              ExportButton(
                title: 'Journal d’activité',
                csv: () => app.toCsv(
                  [
                    'Date',
                    'Auteur',
                    'Action',
                    'Cible',
                    'Détail',
                    'Donnée de santé',
                  ],
                  [
                    for (final e in rows)
                      [
                        e.at.toIso8601String().substring(0, 16),
                        e.actor,
                        e.action,
                        e.target,
                        e.details,
                        e.patientId == null ? 'non' : 'oui',
                      ],
                  ],
                ),
              ),
            ],
          ),
          SearchBox(
            hint: 'Auteur, action, cible',
            onChanged: (v) => setState(() => _q = v),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            value: _healthOnly,
            onChanged: (v) => setState(() => _healthOnly = v),
            title: const Text('Accès aux données de santé seulement'),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aucune action sur la période.',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          for (final e in rows)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(
                e.patientId != null
                    ? Icons.health_and_safety_outlined
                    : Icons.history,
                color: e.patientId != null ? const Color(0xFF9C2B12) : null,
              ),
              title: Text('${e.action} · ${e.target}'),
              subtitle: Text(
                '${dateTimeLabel(e.at)} · ${e.actor}${e.details.isEmpty ? '' : '\n${e.details}'}',
              ),
              isThreeLine: e.details.isNotEmpty,
            ),
        ],
      );
    }

    if (!app.isRemote) return ListView(children: [list(app.adminLog)]);
    return FutureBuilder<List<AdminLogEntry>>(
      future: _remote,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.history,
            text: snap.error is BusinessRuleError
                ? (snap.error as BusinessRuleError).message
                : 'Journal indisponible : vérifiez votre connexion.',
          );
        }
        return ListView(children: [list(snap.data!)]);
      },
    );
  }
}
