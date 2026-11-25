import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'admin_widgets.dart';

// ============================================================== rendez-vous
class AppointmentsModule extends StatefulWidget {
  const AppointmentsModule({super.key, required this.period});

  final Period period;

  @override
  State<AppointmentsModule> createState() => _AppointmentsModuleState();
}

class _AppointmentsModuleState extends State<AppointmentsModule> {
  String _q = '';
  BookingStatus? _status;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.adminBookings(widget.period, query: _q, status: _status);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ModuleHeader(
          title: 'Rendez-vous',
          subtitle: '${list.length} sur la période · ${widget.period.label}',
          actions: [
            ExportButton(
              title: 'Rendez-vous',
              csv: () => app.adminBookingsCsv(list),
            ),
          ],
        ),
        SearchBox(
          hint: 'Patient, soignant, soin, commune ou référence',
          onChanged: (v) => setState(() => _q = v),
        ),
        FilterRow<BookingStatus>(
          values: BookingStatus.values,
          selected: _status,
          label: (s) => s.label,
          onSelected: (s) => setState(() => _status = s),
        ),
        if (list.isEmpty)
          const EmptyState(
            icon: Icons.event_note_outlined,
            text: 'Aucun rendez-vous.',
          ),
        for (final b in list)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(
              '${b.service.name.split(' (').first} · ${b.patientName}',
            ),
            subtitle: Text(
              '${dateTimeLabel(b.scheduledAt)} · ${b.pro.name} · ${b.commune}\n'
              '${fcfa(b.price)}${b.paid ? ' · payé' : ''}${b.refunded ? ' · remboursé ${fcfa(b.refundAmount)}' : ''}',
            ),
            isThreeLine: true,
            trailing: StatusChip(b.status),
            onTap: () => showBookingAdmin(context, b),
          ),
      ],
    );
  }
}

/// Détail d'un rendez-vous et actions de l'équipe (sans données médicales).
Future<void> showBookingAdmin(
  BuildContext context,
  Booking b,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  builder: (context) {
    final app = AppScope.of(context);
    final open =
        b.status == BookingStatus.pending || b.status == BookingStatus.accepted;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              b.service.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text('Réf. ${b.id}', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 10),
            for (final (k, v) in [
              ('Patient', b.patientName),
              ('Soignant', '${b.pro.name} · ${b.pro.type.label}'),
              ('Date', dateTimeLabel(b.scheduledAt)),
              ('Lieu', '${b.commune} · ${b.address}'),
              ('Statut', b.status.label),
              ('Prix', fcfa(b.price)),
              (
                'Commission',
                '${fcfa(b.commission)} (${(b.commissionRate * 100).round()} %)',
              ),
              ('Net soignant', fcfa(b.proEarnings)),
              if (paymentLabel(b) case final p?) ('Paiement', p),
              if (b.refusalReason.isNotEmpty)
                ('Motif de refus', b.refusalReason),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        k,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                    Expanded(child: Text(v)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            if (open && app.hasAdminPerm(AdminPermission.manageBookings))
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () async {
                  final r = await askReason(
                    context,
                    'Annuler ce rendez-vous',
                    label: 'Motif (vu par la famille et le soignant)',
                    help: b.paid
                        ? 'La famille est remboursée en totalité.'
                        : null,
                    minLength: 5,
                  );
                  if (r == null || !context.mounted) return;
                  final ok = await runAction(
                    context,
                    () => app.adminCancelBooking(b, r),
                  );
                  if (ok && context.mounted) Navigator.pop(context);
                },
                child: const Text('Annuler le rendez-vous'),
              ),
            if (b.paid &&
                b.refundAmount < b.price &&
                app.hasAdminPerm(AdminPermission.finance)) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  final ok = await showRefundDialog(context, b);
                  if (ok && context.mounted) Navigator.pop(context);
                },
                child: const Text('Rembourser'),
              ),
            ],
          ],
        ),
      ),
    );
  },
);

Future<bool> showRefundDialog(BuildContext context, Booking b) async {
  final app = AppScope.of(context);
  final max = b.price - b.refundAmount;
  final amount = TextEditingController(text: '$max');
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remboursement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Crédité sur le solde MyNurse de la famille (jusqu’à ${fcfa(max)}).',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Montant',
              suffixText: 'FCFA',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: reason,
            decoration: const InputDecoration(
              labelText: 'Motif (vu par la famille)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Retour'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Rembourser'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) {
    amount.dispose();
    reason.dispose();
    return false;
  }
  final done = await runAction(
    context,
    () =>
        app.adminRefund(b, int.tryParse(amount.text.trim()) ?? 0, reason.text),
  );
  amount.dispose();
  reason.dispose();
  if (done && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Remboursement effectué, famille prévenue.'),
      ),
    );
  }
  return done;
}

// ====================================================== suivis réguliers
class ContractsModule extends StatefulWidget {
  const ContractsModule({super.key});

  @override
  State<ContractsModule> createState() => _ContractsModuleState();
}

class _ContractsModuleState extends State<ContractsModule> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.adminContracts(_q);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ModuleHeader(
          title: 'Suivis réguliers',
          subtitle: '${list.length} suivi(s)',
          actions: [
            ExportButton(
              title: 'Suivis réguliers',
              csv: () => app.toCsv(
                [
                  'Patient',
                  'Soignant',
                  'Soin',
                  'Fréquence',
                  'Séances',
                  'Réalisées',
                  'Total',
                ],
                [
                  for (final c in list)
                    [
                      c.sessions.first.patientName,
                      c.sessions.first.pro.name,
                      c.sessions.first.service.name,
                      c.frequency.label,
                      c.sessions.length,
                      c.doneCount,
                      c.total,
                    ],
                ],
              ),
            ),
          ],
        ),
        SearchBox(
          hint: 'Patient, soignant ou soin',
          onChanged: (v) => setState(() => _q = v),
        ),
        if (list.isEmpty)
          const EmptyState(icon: Icons.repeat, text: 'Aucun suivi régulier.'),
        for (final c in list)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Card(
              child: ListTile(
                title: Text(
                  '${c.sessions.first.patientName} · ${c.sessions.first.service.name.split(' (').first}',
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.sessions.first.pro.name} · ${c.frequency.label.toLowerCase()} · '
                      'du ${dateTimeLabel(c.start).split(' à ').first} au ${dateTimeLabel(c.end).split(' à ').first}',
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: c.doneCount / c.sessions.length,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                      backgroundColor: const Color(0xFFE4E8EA),
                      color: brandGreen,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${c.doneCount}/${c.sessions.length} séances · ${fcfa(c.total)}',
                    ),
                  ],
                ),
                trailing: StatusChip(c.sessions.first.status),
                onTap: () => showBookingAdmin(
                  context,
                  c.sessions.firstWhere(
                    (s) =>
                        s.status == BookingStatus.pending ||
                        s.status == BookingStatus.accepted,
                    orElse: () => c.sessions.first,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================ réclamations
class ComplaintsModule extends StatefulWidget {
  const ComplaintsModule({super.key});

  @override
  State<ComplaintsModule> createState() => _ComplaintsModuleState();
}

class _ComplaintsModuleState extends State<ComplaintsModule> {
  ComplaintStatus? _status;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list =
        app.complaints
            .where((c) => _status == null || c.status == _status)
            .toList()
          ..sort((a, b) {
            final u =
                (b.category == ComplaintCategory.safety ? 1 : 0) -
                (a.category == ComplaintCategory.safety ? 1 : 0);
            return u != 0 ? u : b.createdAt.compareTo(a.createdAt);
          });
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ModuleHeader(
          title: 'Réclamations',
          subtitle: 'Réponse sous 24 h · sécurité en priorité',
          actions: [
            ExportButton(
              title: 'Réclamations',
              csv: () => app.toCsv(
                ['Date', 'Type', 'Statut', 'Soin', 'Description', 'Réponse'],
                [
                  for (final c in list)
                    [
                      c.createdAt.toIso8601String().substring(0, 16),
                      c.category.label,
                      c.status.label,
                      c.booking == null
                          ? ''
                          : '${c.booking!.service.name} · ${c.booking!.pro.name}',
                      c.description,
                      c.resolution,
                    ],
                ],
              ),
            ),
          ],
        ),
        FilterRow<ComplaintStatus>(
          values: ComplaintStatus.values,
          selected: _status,
          label: (s) => s.label,
          onSelected: (s) => setState(() => _status = s),
        ),
        if (list.isEmpty)
          const EmptyState(
            icon: Icons.support_agent_outlined,
            text: 'Aucune réclamation.',
          ),
        for (final c in list)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.category.label,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Pill(
                          c.status.label,
                          color: c.status == ComplaintStatus.resolved
                              ? brandGreen
                              : adminBlue,
                        ),
                      ],
                    ),
                    Text(
                      [
                        dateTimeLabel(c.createdAt),
                        if (c.booking != null)
                          '${c.booking!.service.name} · ${c.booking!.pro.name}',
                      ].join(' · '),
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    Text(c.description),
                    if (c.resolution.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Réponse : ${c.resolution}',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                    if (c.status == ComplaintStatus.open ||
                        c.status == ComplaintStatus.inReview)
                      Wrap(
                        spacing: 8,
                        children: [
                          if (c.status == ComplaintStatus.open)
                            TextButton(
                              onPressed: () => runAction(
                                context,
                                () => app.adminUpdateComplaint(
                                  c,
                                  ComplaintStatus.inReview,
                                ),
                              ),
                              child: const Text('Prendre en charge'),
                            ),
                          TextButton(
                            onPressed: () =>
                                _resolve(context, c, ComplaintStatus.resolved),
                            child: const Text('Répondre et clore'),
                          ),
                          TextButton(
                            onPressed: () =>
                                _resolve(context, c, ComplaintStatus.rejected),
                            child: const Text('Sans suite'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _resolve(
    BuildContext context,
    Complaint c,
    ComplaintStatus status,
  ) async {
    final app = AppScope.of(context);
    final text = TextEditingController();
    final refund = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          status == ComplaintStatus.resolved
              ? 'Réponse à la famille'
              : 'Clore sans suite',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: text,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Réponse (envoyée à la famille)',
              ),
            ),
            if (status == ComplaintStatus.resolved &&
                app.hasAdminPerm(AdminPermission.finance)) ...[
              const SizedBox(height: 10),
              TextField(
                controller: refund,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Geste commercial (facultatif)',
                  suffixText: 'FCFA',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retour'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await runAction(
        context,
        () => app.adminUpdateComplaint(
          c,
          status,
          resolution: text.text,
          refund: int.tryParse(refund.text.trim()) ?? 0,
        ),
      );
    }
    text.dispose();
    refund.dispose();
  }
}

// ================================================================ incidents
class IncidentsModule extends StatelessWidget {
  const IncidentsModule({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = [...app.incidents]
      ..sort((a, b) {
        final u = (b.category.urgent ? 1 : 0) - (a.category.urgent ? 1 : 0);
        return u != 0 ? u : b.at.compareTo(a.at);
      });
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ModuleHeader(
          title: 'Incidents',
          subtitle: 'Signalés par les soignants · graves en premier',
          actions: [
            ExportButton(
              title: 'Incidents',
              csv: () => app.toCsv(
                ['Date', 'Type', 'Grave', 'Statut', 'Soin', 'Description'],
                [
                  for (final i in list)
                    [
                      i.at.toIso8601String().substring(0, 16),
                      i.category.label,
                      i.category.urgent ? 'oui' : 'non',
                      i.status,
                      i.booking == null
                          ? ''
                          : '${i.booking!.service.name} · ${i.booking!.pro.name}',
                      i.description,
                    ],
                ],
              ),
            ),
          ],
        ),
        if (list.isEmpty)
          const EmptyState(
            icon: Icons.health_and_safety_outlined,
            text: 'Aucun incident.',
          ),
        for (final i in list)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Card(
              color: i.category.urgent && i.status != 'Traité'
                  ? const Color(0xFFFFF4F2)
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (i.category.urgent)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.priority_high_rounded,
                              color: Color(0xFF9C2B12),
                              size: 20,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            i.category.label,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Pill(
                          i.status,
                          color: i.status == 'Traité' ? brandGreen : adminBlue,
                        ),
                      ],
                    ),
                    Text(
                      [
                        dateTimeLabel(i.at),
                        if (i.booking != null)
                          '${i.booking!.service.name} · ${i.booking!.pro.name}',
                      ].join(' · '),
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    Text(i.description),
                    if (i.status != 'Traité')
                      Wrap(
                        spacing: 8,
                        children: [
                          if (i.status == 'Envoyé')
                            TextButton(
                              onPressed: () => runAction(
                                context,
                                () => app.adminUpdateIncident(
                                  i,
                                  'En cours',
                                  'Pris en charge par l’équipe.',
                                ),
                              ),
                              child: const Text('Prendre en charge'),
                            ),
                          TextButton(
                            onPressed: () async {
                              final r = await askReason(
                                context,
                                'Clore l’incident',
                                label: 'Ce qui a été fait (envoyé au soignant)',
                                minLength: 5,
                              );
                              if (r != null && context.mounted) {
                                await runAction(
                                  context,
                                  () => app.adminUpdateIncident(i, 'Traité', r),
                                );
                              }
                            },
                            child: const Text('Clore'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
