import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../widgets.dart';
import 'care_log_form.dart';
import 'pro_onboarding.dart';

class ProShell extends StatefulWidget {
  const ProShell({super.key});

  @override
  State<ProShell> createState() => _ProShellState();
}

class _ProShellState extends State<ProShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pro = app.currentPro;
    if (pro == null) return const ProOnboardingScreen();
    if (!pro.verified) return ProStatusScreen(pro: pro);
    final pending = app.proBookings(BookingStatus.pending).length;
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

class _RequestsTab extends StatelessWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.proBookings(BookingStatus.pending);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Nouvelles demandes'),
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
                          if (b.service.needsPrescription)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Text(
                                'Sur ordonnance : vérifiez-la avant le soin.',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
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
        const SectionTitle('Soins à réaliser'),
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
                      footer: b.readyForCare
                          ? FilledButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CareLogFormScreen(booking: b),
                                ),
                              ),
                              icon: const Icon(Icons.edit_note),
                              label: const Text('Rédiger le compte rendu'),
                            )
                          : const InfoBanner(
                              icon: Icons.hourglass_top_rounded,
                              warning: true,
                              text:
                                  'Le patient n’a pas encore payé. Ne vous '
                                  'déplacez pas avant la confirmation du '
                                  'paiement.',
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
    final app = AppScope.of(context);
    final done = app.proBookings(BookingStatus.done);
    final total = done.fold<int>(0, (s, b) => s + b.proEarnings);
    final commission = done.fold<int>(0, (s, b) => s + b.commission);
    final blocked = app
        .proBookings(BookingStatus.accepted)
        .where((b) => b.readyForCare)
        .fold<int>(0, (s, b) => s + b.proEarnings);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionTitle('Revenus'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gains versés',
                    style: TextStyle(color: Colors.black54),
                  ),
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
                  if (blocked > 0) ...[
                    const Divider(height: 24),
                    Text(
                      '${fcfa(blocked)} déjà payés par vos patients, versés '
                      'dès que vous terminez les soins.',
                    ),
                  ],
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
            subtitle: Text(
              '${b.patientName} · ${dateTimeLabel(b.scheduledAt)}',
            ),
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
    final p = app.currentPro!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionTitle('Profil'),
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
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Zones couvertes',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in communes)
                            FilterChip(
                              label: Text(c),
                              selected: p.communes.contains(c),
                              onSelected: (on) {
                                final next = communes
                                    .where(
                                      (x) =>
                                          x == c ? on : p.communes.contains(x),
                                    )
                                    .toList();
                                if (next.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Gardez au moins une commune.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                app.updateProAvailability(
                                  p,
                                  communes: next,
                                  nightAvailable: p.nightAvailable,
                                );
                              },
                            ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: p.nightAvailable,
                        onChanged: (v) => app.updateProAvailability(
                          p,
                          communes: p.communes,
                          nightAvailable: v,
                        ),
                        title: const Text('Disponible la nuit'),
                        subtitle: const Text('21 h – 6 h, majoration de 50 %'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
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
