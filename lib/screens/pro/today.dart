import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../notifications.dart';
import 'visit.dart';

/// « Aujourd'hui » : disponibilité, chiffres du jour, soin en cours ou
/// suivant avec ses gestes, demandes à traiter, rappels.
class ProTodayTab extends StatelessWidget {
  const ProTodayTab({
    super.key,
    required this.onOpenRequests,
    required this.onOpenAgenda,
    required this.onOpenEarnings,
  });

  final VoidCallback onOpenRequests;
  final VoidCallback onOpenAgenda;
  final VoidCallback onOpenEarnings;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.currentPro!;
    final today = app.proDay(app.now);
    final next = app.proNextVisit;
    final requests = app.proRequests;
    final reminders = app.proReminders;
    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await app.retrySync();
            },
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _Header(
                  pro: p,
                  todayCount: today.length,
                  requests: requests.length,
                  month: app.proMonthEarnings,
                  onOpenRequests: onOpenRequests,
                  onOpenEarnings: onOpenEarnings,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (reminders.isNotEmpty) ...[
                        const BlockTitle('À faire'),
                        for (final r in reminders.take(3))
                          Card(
                            color: r.urgent ? const Color(0xFFFFF7E6) : null,
                            child: ListTile(
                              leading: Icon(
                                r.urgent
                                    ? Icons.priority_high_rounded
                                    : Icons.notifications_none,
                                color: r.urgent
                                    ? const Color(0xFF8A5A00)
                                    : brandGreen,
                              ),
                              title: Text(
                                r.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(r.body),
                              onTap: r.booking == null
                                  ? null
                                  : () => openBooking(context, r.booking!),
                            ),
                          ),
                      ],
                      BlockTitle(
                        next != null &&
                                !next.scheduledAt.isAfter(
                                  app.now.add(const Duration(minutes: 30)),
                                )
                            ? 'Soin en cours'
                            : 'Prochain soin',
                        action: TextButton(
                          onPressed: onOpenAgenda,
                          child: const Text('Agenda'),
                        ),
                      ),
                      if (next == null)
                        const Card(
                          child: ListTile(
                            leading: Icon(Icons.event_available_outlined),
                            title: Text('Aucun soin confirmé'),
                            subtitle: Text(
                              'Les demandes acceptées et payées apparaissent ici.',
                            ),
                          ),
                        )
                      else
                        NextVisitCard(booking: next),
                      BlockTitle(
                        requests.isEmpty
                            ? 'Aucune demande en attente'
                            : 'Demandes en attente',
                        action: requests.isEmpty
                            ? null
                            : TextButton(
                                onPressed: onOpenRequests,
                                child: Text('Tout voir (${requests.length})'),
                              ),
                      ),
                      for (final b in requests.take(2))
                        Card(
                          child: ListTile(
                            title: Text(
                              b.contract == null
                                  ? b.service.name.split(' (').first
                                  : 'Suivi · ${b.contract!.sessions.length} séances',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${b.patientName} · ${b.commune} · '
                              '${dateTimeLabel(b.scheduledAt)}\n'
                              'Répondre avant ${timeLabel(b.responseDeadline)}',
                            ),
                            isThreeLine: true,
                            trailing: Text(
                              fcfa(
                                b.contract?.sessions.fold<int>(
                                      0,
                                      (s, x) => s + x.proEarnings,
                                    ) ??
                                    b.proEarnings,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onTap: onOpenRequests,
                          ),
                        ),
                      if (today.isNotEmpty) ...[
                        const BlockTitle('Aujourd’hui'),
                        Card(
                          child: Column(
                            children: [
                              for (final b in today)
                                ListTile(
                                  dense: true,
                                  leading: Text(
                                    timeLabel(b.scheduledAt),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  title: Text(
                                    '${b.service.name.split(' (').first} · ${b.patientName}',
                                  ),
                                  trailing: StatusChip(b.status),
                                  onTap: () => openBooking(context, b),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.pro,
    required this.todayCount,
    required this.requests,
    required this.month,
    required this.onOpenRequests,
    required this.onOpenEarnings,
  });

  final Pro pro;
  final int todayCount;
  final int requests;
  final int month;
  final VoidCallback onOpenRequests;
  final VoidCallback onOpenEarnings;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    const muted = Color(0xFFB9CDD0);
    Widget stat(String value, String label, VoidCallback? onTap) => Expanded(
      child: Material(
        color: const Color(0xFF17383D),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(label, style: const TextStyle(color: muted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
    final available = app.availableToday;
    return Container(
      color: brandInk,
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateTimeLabel(app.now).split(' à ').first,
                      style: const TextStyle(color: muted),
                    ),
                    Text(
                      'Bonjour ${pro.name.replaceFirst('Dr ', '').split(' ').first}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const IconTheme(
                data: IconThemeData(color: Colors.white),
                child: NotificationBell(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: const Color(0xFF17383D),
              borderRadius: BorderRadius.circular(14),
              child: SwitchListTile(
                value: available,
                onChanged: (v) =>
                    runAction(context, () => app.setAvailableToday(v)),
                title: Text(
                  available
                      ? 'Disponible aujourd’hui'
                      : 'Indisponible aujourd’hui',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  available
                      ? '${pro.communes.join(', ')} · ${app.availabilitySummary(pro)}'
                      : 'Aucune nouvelle demande pour aujourd’hui',
                  style: const TextStyle(color: muted),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  stat('$todayCount', 'soins aujourd’hui', null),
                  const SizedBox(width: 8),
                  stat('$requests', 'demandes', onOpenRequests),
                  const SizedBox(width: 8),
                  stat(fcfa(month), 'gagnés ce mois', onOpenEarnings),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
