import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../widgets.dart';
import 'care_log_form.dart';

class ProShell extends StatefulWidget {
  const ProShell({super.key});

  @override
  State<ProShell> createState() => _ProShellState();
}

class _ProShellState extends State<ProShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pending =
        AppScope.of(context).proBookings(BookingStatus.pending).length;
    return Scaffold(
      body: SafeArea(
        child: switch (_tab) {
          0 => const _RequestsTab(),
          1 => const _PlanningTab(),
          2 => const _EarningsTab(),
          _ => const _ProProfileTab(),
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
              child: const Icon(Icons.inbox_outlined),
            ),
            label: 'Demandes',
          ),
          const NavigationDestination(
            icon: Icon(Icons.event_available_outlined),
            label: 'Planning',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Revenus',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

class _TabTitle extends StatelessWidget {
  const _TabTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Text(
          text,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
      );
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.proBookings(BookingStatus.pending);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TabTitle('Nouvelles demandes'),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(
                  icon: Icons.inbox_outlined,
                  text: 'Aucune demande en attente.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final b = list[i];
                    return BookingCard(
                      booking: b,
                      forPro: true,
                      footer: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (b.note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text('« ${b.note} »'),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      app.respond(b, accept: false),
                                  child: const Text('Refuser'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => app.respond(b, accept: true),
                                  child: const Text('Accepter'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PlanningTab extends StatelessWidget {
  const _PlanningTab();

  @override
  Widget build(BuildContext context) {
    final list = AppScope.of(context).proBookings(BookingStatus.accepted)
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TabTitle('Soins à réaliser'),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(
                  icon: Icons.event_available_outlined,
                  text: 'Aucun soin confirmé pour le moment.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final b = list[i];
                    return BookingCard(
                      booking: b,
                      forPro: true,
                      footer: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CareLogFormScreen(booking: b),
                          ),
                        ),
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Rédiger le compte rendu'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EarningsTab extends StatelessWidget {
  const _EarningsTab();

  @override
  Widget build(BuildContext context) {
    final done = AppScope.of(context).proBookings(BookingStatus.done);
    final total = done.fold<int>(0, (s, b) => s + b.proEarnings);
    final commission = done.fold<int>(0, (s, b) => s + b.commission);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const _TabTitle('Revenus'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Gains nets',
                      style: TextStyle(color: Colors.black54)),
                  Text(
                    fcfa(total),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${done.length} soin${done.length > 1 ? 's' : ''} '
                    'terminé${done.length > 1 ? 's' : ''} · commission '
                    'MyNurse ${fcfa(commission)}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final b in done)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(b.service.name),
            subtitle: Text('${b.patientName} · ${dateTimeLabel(b.scheduledAt)}'),
            trailing: Text(
              '+ ${fcfa(b.proEarnings)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

class _ProProfileTab extends StatelessWidget {
  const _ProProfileTab();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.currentPro;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const _TabTitle('Profil'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
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
                            Text(p.type.label),
                            const SizedBox(height: 6),
                            const VerifiedBadge(),
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
                      leading: const Icon(Icons.place_outlined),
                      title: const Text('Zones couvertes'),
                      subtitle: Text(p.communes.join(', ')),
                    ),
                    ListTile(
                      leading: const Icon(Icons.nightlight_outlined),
                      title: const Text('Soins de nuit'),
                      subtitle: Text(p.nightAvailable ? 'Oui' : 'Non'),
                    ),
                    for (final s in app.services)
                      if (p.prices.containsKey(s.id))
                        ListTile(
                          leading: const Icon(Icons.sell_outlined),
                          title: Text(s.name),
                          trailing: Text(fcfa(p.prices[s.id]!)),
                        ),
                  ],
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
