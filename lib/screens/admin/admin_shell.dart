import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../widgets.dart';

/// Back-office MyNurse : vérification des soignants, suivi de l'activité.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pending = AppScope.of(context)
        .prosWithStatus(VerificationStatus.pending)
        .length;
    return Scaffold(
      body: SafeArea(
        child: switch (_tab) {
          0 => const _PendingTab(),
          1 => const _ProsTab(),
          _ => const _ActivityTab(),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.fact_check_outlined),
            ),
            label: 'Dossiers',
          ),
          const NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            label: 'Soignants',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            label: 'Activité',
          ),
        ],
      ),
    );
  }
}

Future<String?> _askReason(BuildContext context, String title) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Motif (vu par le soignant)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Retour'),
        ),
        TextButton(
          onPressed: () {
            final r = ctrl.text.trim();
            if (r.isNotEmpty) Navigator.pop(context, r);
          },
          child: const Text('Confirmer'),
        ),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}

class _PendingTab extends StatelessWidget {
  const _PendingTab();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.prosWithStatus(VerificationStatus.pending);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Row(
          children: [
            const Expanded(child: SectionTitle('Dossiers à vérifier')),
            IconButton(
              tooltip: 'Se déconnecter',
              onPressed: app.logout,
              icon: const Icon(Icons.logout),
            ),
            const SizedBox(width: 8),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: InfoBanner(
            icon: Icons.checklist,
            text:
                'Avant de valider : comparer chaque pièce à l’original, '
                'vérifier le numéro sur la liste de l’Ordre, puis faire '
                'l’entretien vidéo.',
          ),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const EmptyState(
            icon: Icons.fact_check_outlined,
            text: 'Aucun dossier en attente.',
          ),
        for (final p in list)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _PendingCard(pro: p),
          ),
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.pro});

  final Pro pro;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = pro;
    final missing = p.missingDocs;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProAvatar(p),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${p.type.label} · ${p.yearsExperience} ans · '
                        '+225 ${p.phone}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (p.orderNumber.isNotEmpty) Text('Ordre : ${p.orderNumber}'),
            Text('Communes : ${p.communes.join(', ')}'),
            Text(
              'Soins : ${p.prices.entries.map((e) => '${app.services.firstWhere((s) => s.id == e.key).name} '
                  '(${fcfa(e.value)})').join(' ; ')}',
            ),
            const SizedBox(height: 10),
            for (final d in requiredDocs(p.type))
              Row(
                children: [
                  Icon(
                    p.documents.contains(d) ? Icons.check_circle : Icons.cancel,
                    size: 18,
                    color: p.documents.contains(d)
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(d.label)),
                ],
              ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Dossier incomplet : impossible de valider.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final r = await _askReason(context, 'Refuser le dossier');
                      if (r != null) app.rejectPro(p, r);
                    },
                    child: const Text('Refuser'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: missing.isEmpty ? () => app.verifyPro(p) : null,
                    child: const Text('Valider'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProsTab extends StatelessWidget {
  const _ProsTab();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list =
        app.pros.where((p) => p.status != VerificationStatus.pending).toList()
          ..sort((a, b) {
            // Alertes de note d'abord, puis par nom.
            final byAlert = (b.ratingAlert ? 1 : 0) - (a.ratingAlert ? 1 : 0);
            return byAlert != 0 ? byAlert : a.name.compareTo(b.name);
          });
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionTitle('Soignants'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '${app.prosWithStatus(VerificationStatus.verified).length} '
            'vérifiés · ${app.prosWithStatus(VerificationStatus.suspended).length} '
            'suspendus · ${app.prosWithStatus(VerificationStatus.rejected).length} '
            'refusés',
            style: const TextStyle(color: Colors.black54),
          ),
        ),
        const SizedBox(height: 8),
        for (final p in list)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: ProAvatar(p, radius: 22),
            title: Text(p.name),
            subtitle: Text(
              '${p.type.label} · ${p.status.label}'
              '${p.ratingCount > 0 ? ' · ${p.rating.toStringAsFixed(1).replaceAll('.', ',')}/5' : ''}'
              '${p.ratingAlert ? ' · note sous 4/5, à revoir' : ''}',
              style: TextStyle(
                color: p.ratingAlert
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
            trailing: switch (p.status) {
              VerificationStatus.verified => TextButton(
                onPressed: () async {
                  final r = await _askReason(context, 'Suspendre ${p.name}');
                  if (r != null) app.suspendPro(p, r);
                },
                child: const Text('Suspendre'),
              ),
              VerificationStatus.suspended => TextButton(
                onPressed: () => app.verifyPro(p),
                child: const Text('Réactiver'),
              ),
              _ => null,
            },
          ),
      ],
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final rated = app.pros.where((p) => p.ratingCount > 0);
    final avg = rated.isEmpty
        ? 0.0
        : rated.fold<double>(0, (s, p) => s + p.rating) / rated.length;
    final disputes = app.bookings
        .where((b) => b.status == BookingStatus.cancelled)
        .toList();
    final tiles = [
      ('Soins réservés', '${app.bookings.length}'),
      ('Soins terminés', '${app.doneBookings.length}'),
      ('Volume payé', fcfa(app.grossVolume)),
      ('Commissions', fcfa(app.commissionTotal)),
      ('Argent bloqué', fcfa(app.escrowTotal)),
      ('Remboursements', fcfa(app.refundTotal)),
      ('Soldes clients', fcfa(app.clientBalances)),
      ('Soldes soignants', fcfa(app.proBalances)),
      (
        'Soignants vérifiés',
        '${app.prosWithStatus(VerificationStatus.verified).length}',
      ),
      ('Note moyenne', avg.toStringAsFixed(1).replaceAll('.', ',')),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionTitle('Activité'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: LayoutBuilder(
            builder: (context, c) {
              final w = (c.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (label, value) in tiles)
                    SizedBox(
                      width: w,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: const TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  value,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Text(
            'Annulations et remboursements',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        if (disputes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Aucune annulation.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        for (final b in disputes)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text('${b.service.name} · ${b.pro.name}'),
            subtitle: Text(
              '${b.patientName} · ${dateTimeLabel(b.scheduledAt)}\n'
              '${b.cancelReason}${b.refunded ? ' · remboursé ${fcfa(b.price)}' : ''}',
            ),
            isThreeLine: true,
          ),
      ],
    );
  }
}
