import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../widgets.dart';
import 'visit.dart';

/// Demandes reçues : une carte par soin ponctuel ou par suivi, à accepter
/// ou refuser avant l'échéance.
class ProRequestsTab extends StatelessWidget {
  const ProRequestsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.proRequests
      ..sort((a, b) => a.responseDeadline.compareTo(b.responseDeadline));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OfflineBanner(),
        const SectionTitle('Demandes'),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(
                  icon: Icons.inbox_outlined,
                  text:
                      'Aucune demande en attente. Vous êtes prévenu dès qu’un '
                      'patient de vos communes vous choisit.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => RequestCard(booking: list[i]),
                ),
        ),
      ],
    );
  }
}

/// Une demande, avec tout ce qu'il faut pour décider vite.
class RequestCard extends StatelessWidget {
  const RequestCard({super.key, required this.booking, this.compact = true});

  final Booking booking;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = booking;
    final c = b.contract;
    final earnings =
        c?.sessions.fold<int>(0, (s, x) => s + x.proEarnings) ?? b.proEarnings;
    final left = b.responseDeadline.difference(app.now);
    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: compact
            ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RequestDetailScreen(booking: b),
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c == null
                          ? b.service.name
                          : 'Suivi · ${c.sessions.length} séances',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1D6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      left.inMinutes < 60
                          ? 'Encore ${left.inMinutes.clamp(0, 59)} min'
                          : 'Avant ${timeLabel(b.responseDeadline)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8A5A00),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  b.patientName,
                  if (b.patient.ageAt(app.now) case final a?) '$a ans',
                ].join(', '),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${b.commune} · ${c == null ? dateTimeLabel(b.scheduledAt) : '${c.frequency.label.toLowerCase()}, dès le ${dateTimeLabel(c.start)}'}',
                style: const TextStyle(color: Colors.black54),
              ),
              if (b.patient.allergies.isNotEmpty && app.proCanSeeRecord(b)) ...[
                const SizedBox(height: 8),
                InfoBanner(
                  icon: Icons.warning_amber_rounded,
                  warning: true,
                  text: 'Allergies : ${b.patient.allergies}',
                ),
              ],
              if (b.service.needsPrescription) ...[
                const SizedBox(height: 6),
                const Text(
                  'Sur ordonnance : vérifiez-la sur place avant le soin.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              if (!compact && b.note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('« ${b.note} »'),
              ],
              const SizedBox(height: 8),
              Text(
                '${fcfa(earnings)} pour vous'
                '${c == null ? '' : ' (${c.sessions.length} séances)'} · '
                'commission ${(b.commissionRate * 100).round()} % déduite',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () => refuseWithReason(context, b),
                      child: const Text('Refuser'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ActionButton(
                      label: c == null ? 'Accepter' : 'Accepter le suivi',
                      success:
                          'Accepté. Le patient a ${paymentWindow.inHours} h pour '
                          'payer ; vous êtes prévenu dès le paiement.',
                      onPressed: () => app.respond(b, accept: true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return card;
  }
}

/// Motifs de refus en un geste (envoyés au patient).
const refusalReasons = [
  'Pas disponible à cette heure',
  'Trop loin de ma zone',
  'Soin hors de mes compétences',
  'Ordonnance nécessaire',
];

Future<void> refuseWithReason(BuildContext context, Booking b) async {
  final app = AppScope.of(context);
  final reason = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Pourquoi refuser ?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Le patient voit le motif et peut choisir un autre soignant.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
          for (final r in refusalReasons)
            ListTile(
              title: Text(r),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, r),
            ),
          ListTile(
            title: const Text('Sans motif'),
            onTap: () => Navigator.pop(context, ''),
          ),
        ],
      ),
    ),
  );
  if (reason == null || !context.mounted) return;
  final ok = await runAction(
    context,
    () => app.respond(b, accept: false, reason: reason),
  );
  if (ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Demande refusée. Le patient est prévenu.')),
    );
    if (Navigator.of(context).canPop()) Navigator.of(context).maybePop();
  }
}

/// Détail d'une demande : la carte, le dossier autorisé, les séances.
class RequestDetailScreen extends StatelessWidget {
  const RequestDetailScreen({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = booking;
    if (b.status != BookingStatus.pending) {
      return VisitScreen(booking: b);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Demande')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            RequestCard(booking: b, compact: false),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PatientChartScreen(booking: b),
                ),
              ),
              icon: const Icon(Icons.folder_shared_outlined),
              label: const Text('Voir l’essentiel du dossier'),
            ),
            const SizedBox(height: 6),
            const Text(
              'Avant d’accepter, vous voyez l’identité, les allergies et les '
              'traitements. Le reste du carnet s’ouvre après acceptation.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            if (b.contract case final c?) ...[
              const BlockTitle('Séances demandées'),
              for (final s in c.sessions)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text('${s.sessionIndex + 1}'),
                  title: Text(dateTimeLabel(s.scheduledAt)),
                  trailing: Text(fcfa(s.proEarnings)),
                ),
            ],
            if (app.conflictFor(b.pro, b.scheduledAt, b.endsAt, except: b)
                case final other?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: InfoBanner(
                  icon: Icons.event_busy,
                  warning: true,
                  text:
                      'Conflit : vous avez déjà ${other.service.name.toLowerCase()} '
                      'pour ${other.patientName} à ${timeLabel(other.scheduledAt)}.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
