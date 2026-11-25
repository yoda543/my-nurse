import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'booking_detail.dart';

/// Onglet « Mes soins » : tous les soins de la famille, par personne, avec
/// leur avancement ; les suivis réguliers en tête.
class BookingsTab extends StatefulWidget {
  const BookingsTab({super.key});

  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab> {
  Patient? _who;
  bool _past = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final family = app.familyPatients;
    if (_who != null && !family.contains(_who)) _who = null;
    bool open(Booking b) =>
        b.status == BookingStatus.pending || b.status == BookingStatus.accepted;
    final all = app.patientBookings
        .where((b) => _who == null || b.patient == _who)
        .toList();
    // Un suivi n'apparaît qu'une fois dans la liste : sa prochaine séance.
    final seen = <Contract>{};
    final list = [
      for (final b in all)
        if (open(b) != _past &&
            (b.contract == null || _past || seen.add(b.contract!)))
          b,
    ];
    final contracts = app.activeContracts
        .where((c) => _who == null || c.sessions.first.patient == _who)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OfflineBanner(),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text(
            'Mes soins',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
        ),
        if (family.length > 1)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                ChoiceChip(
                  label: const Text('Tout le monde'),
                  selected: _who == null,
                  onSelected: (_) => setState(() => _who = null),
                ),
                for (final p in family) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(
                      p == app.patients.firstOrNull
                          ? 'Moi'
                          : p.name.split(' ').first,
                    ),
                    selected: _who == p,
                    onSelected: (_) => setState(() => _who = p),
                  ),
                ],
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('En cours et à venir')),
              ButtonSegment(value: true, label: Text('Historique')),
            ],
            selected: {_past},
            onSelectionChanged: (v) => setState(() => _past = v.first),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await app.retrySync();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                if (!_past)
                  for (final c in contracts) ...[
                    ContractProgressCard(contract: c),
                    const SizedBox(height: 12),
                  ],
                if (list.isEmpty && (contracts.isEmpty || _past))
                  EmptyState(
                    icon: Icons.event_note_outlined,
                    text: _past
                        ? 'Les soins terminés ou annulés apparaîtront ici.'
                        : 'Aucun soin en cours. Réservez depuis l’accueil.',
                  ),
                for (final b in list)
                  if (b.contract == null || _past) ...[
                    _TrackedCard(booking: b),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackedCard extends StatelessWidget {
  const _TrackedCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = booking;
    return BookingCard(
      booking: b,
      forPro: false,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BookingDetailScreen(booking: b)),
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CareSteps(booking: b),
          const SizedBox(height: 6),
          Text(
            nextStepText(b, app.now),
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          if (!app.bookedByMe(b))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Réservé par ${app.bookerName(b)}',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

/// Avancement d'un suivi régulier : séances faites, prochaine séance.
class ContractProgressCard extends StatelessWidget {
  const ContractProgressCard({super.key, required this.contract});

  final Contract contract;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = contract;
    final first = c.sessions.first;
    final total = c.sessions.length;
    final done = c.doneCount;
    final next = c.sessions
        .where(
          (s) =>
              (s.status == BookingStatus.accepted ||
                  s.status == BookingStatus.pending) &&
              s.endsAt.isAfter(app.now),
        )
        .firstOrNull;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BookingDetailScreen(booking: next ?? first),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.repeat, color: brandGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Suivi ${first.service.name.split(' (').first.toLowerCase()} · '
                      '${first.patientName}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  StatusChip(
                    first.status == BookingStatus.pending
                        ? BookingStatus.pending
                        : BookingStatus.accepted,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${first.pro.name} · ${c.frequency.label.toLowerCase()}',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: '$done séances sur $total réalisées',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : done / total,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE4E8EA),
                    color: brandGreen,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text('Séance $done/$total réalisée${done > 1 ? 's' : ''}'),
              if (next != null)
                Text(
                  'Prochaine séance : ${dateTimeLabel(next.scheduledAt)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              if (first.awaitingPayment && app.bookedByMe(first))
                Text(
                  'À payer : ${fcfa(c.amountDue)} avant '
                  '${timeLabel(first.paymentDeadline!)}',
                  style: const TextStyle(color: Color(0xFF8A5A00)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chronologie détaillée d'un soin, avec qui est prévenu.
class CareTimeline extends StatelessWidget {
  const CareTimeline({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = booking;
    final events = <(String, DateTime?, bool)>[
      ('Demande envoyée par ${app.bookerName(b)}', b.createdAt, true),
      (
        b.status == BookingStatus.refused
            ? 'Refusé par ${b.pro.name}'
            : 'Confirmé par ${b.pro.name}',
        b.acceptedAt,
        b.acceptedAt != null || b.status == BookingStatus.refused,
      ),
      (
        'Payé${b.paymentMethod == null ? '' : ' (${b.paymentMethod!.label})'}',
        b.paidAt,
        b.paid,
      ),
      for (final j in b.journal)
        if (j.kind != JournalKind.note)
          (
            j.kind == JournalKind.onTheWay
                ? '${b.pro.name} en route'
                : j.kind == JournalKind.arrived
                ? '${b.pro.name} arrivé(e)'
                : 'Départ du soignant',
            j.at,
            true,
          ),
      if (b.arrivedAt == null)
        ('Soignant attendu', b.scheduledAt, b.status == BookingStatus.done),
      (
        'Soin réalisé, compte rendu envoyé',
        b.careLog?.leftAt,
        b.careLog != null,
      ),
      if (b.status == BookingStatus.cancelled)
        (
          'Annulé${b.cancelReason.isEmpty ? '' : ' : ${b.cancelReason}'}',
          null,
          true,
        ),
    ];
    final watchers = <String>{
      if (!app.bookedByMe(b)) app.bookerName(b),
      if (!app.isOwner(b.patient) && b.patient.ownerName.isNotEmpty)
        b.patient.ownerName,
      for (final m in app.activeMembers(b.patient))
        if (m.permissions.contains(FamilyPermission.viewReports) ||
            m.permissions.contains(FamilyPermission.bookCare))
          m.name,
    }..remove(app.patientName);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Suivi du soin',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            CareSteps(booking: b),
            const SizedBox(height: 12),
            for (final (label, at, reached) in events)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      reached
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: reached ? brandGreen : Colors.black26,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: reached ? brandInk : Colors.black54,
                        ),
                      ),
                    ),
                    if (at != null)
                      Text(
                        dateTimeLabel(at),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                  ],
                ),
              ),
            const Divider(height: 20),
            Text(
              watchers.isEmpty
                  ? 'Vous êtes prévenu à chaque étape.'
                  : 'Prévenus à chaque étape : vous, ${watchers.join(', ')}.',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
