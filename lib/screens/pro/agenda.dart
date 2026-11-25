import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'settings.dart';
import 'visit.dart';

/// Agenda : les 14 prochains jours, les soins du jour choisi, les suivis
/// réguliers et les disponibilités.
class ProAgendaTab extends StatefulWidget {
  const ProAgendaTab({super.key});

  @override
  State<ProAgendaTab> createState() => _ProAgendaTabState();
}

class _ProAgendaTabState extends State<ProAgendaTab> {
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.currentPro!;
    final today = DateTime(app.now.year, app.now.month, app.now.day);
    final day = today.add(Duration(days: _offset));
    final list = app.proDay(day);
    final off = p.daysOff.any(
      (o) => overlaps(day, day.add(const Duration(days: 1)), o.from, o.to),
    );
    final contracts = app.proContracts;
    const short = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OfflineBanner(),
        Row(
          children: [
            const Expanded(child: SectionTitle('Agenda')),
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 8),
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AvailabilityScreen()),
                ),
                icon: const Icon(Icons.schedule),
                label: const Text('Disponibilités'),
              ),
            ),
          ],
        ),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 14,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final d = today.add(Duration(days: i));
              final n = app.proDay(d).length;
              final selected = i == _offset;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _offset = i),
                child: Container(
                  width: 60,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: selected ? brandGreen : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? brandGreen : const Color(0xFFE5E0D5),
                    ),
                  ),
                  child: FittedBox(
                    // Reste lisible avec les grandes tailles de texte.
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          i == 0 ? 'auj.' : short[d.weekday - 1],
                          style: TextStyle(
                            fontSize: 12,
                            color: selected ? Colors.white : Colors.black54,
                          ),
                        ),
                        Text(
                          '${d.day}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: selected ? Colors.white : brandInk,
                          ),
                        ),
                        Text(
                          n == 0 ? ' ' : '$n soin${n > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: selected ? Colors.white : brandGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                dateTimeLabel(day).split(' à ').first,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              if (off)
                const InfoBanner(
                  icon: Icons.event_busy,
                  warning: true,
                  text: 'Vous êtes indisponible ce jour : aucune demande.',
                ),
              if (list.isEmpty && !off)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Aucun soin prévu ce jour.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              for (final b in list)
                Card(
                  child: ListTile(
                    leading: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          timeLabel(b.scheduledAt),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${b.service.durationMinutes} min',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    title: Text(
                      '${b.service.name.split(' (').first} · ${b.patientName}',
                    ),
                    subtitle: Text(
                      [
                        b.commune,
                        if (b.sessionLabel != null) b.sessionLabel!,
                        if (!b.paid && b.status == BookingStatus.accepted)
                          'non payé',
                      ].join(' · '),
                    ),
                    trailing: StatusChip(b.status),
                    onTap: () => openBooking(context, b),
                  ),
                ),
              if (contracts.isNotEmpty) ...[
                const BlockTitle('Suivis réguliers'),
                for (final c in contracts) _ContractTile(contract: c),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ContractTile extends StatelessWidget {
  const _ContractTile({required this.contract});

  final Contract contract;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = contract;
    final first = c.sessions.first;
    final next = c.sessions
        .where(
          (s) =>
              s.status == BookingStatus.accepted && s.endsAt.isAfter(app.now),
        )
        .firstOrNull;
    final total = c.sessions.length;
    return Card(
      child: InkWell(
        onTap: () => openBooking(context, next ?? first),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${first.patientName} · ${first.service.name.split(' (').first}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                c.frequency.label,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: c.doneCount / total,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: const Color(0xFFE4E8EA),
                color: brandGreen,
              ),
              const SizedBox(height: 6),
              Text(
                'Séance ${c.doneCount}/$total'
                '${next == null ? '' : ' · prochaine ${dateTimeLabel(next.scheduledAt)}'}',
              ),
              Text(
                '${fcfa(c.sessions.fold(0, (s, x) => s + x.proEarnings))} pour vous au total',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
