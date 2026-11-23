import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../widgets.dart';
import '../wallet.dart';
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
    final pending = app.proRequests.length;
    return Scaffold(
      body: SafeArea(
        child: switch (_tab) {
          0 => _RequestsTab(onOpenWallet: () => setState(() => _tab = 2)),
          1 => const _PlanningTab(),
          2 => const ProWalletTab(),
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
            label: 'Solde',
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
  const _RequestsTab({required this.onOpenWallet});

  final VoidCallback onOpenWallet;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.proRequests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: SectionTitle('Demandes')),
            Padding(
              padding: const EdgeInsets.only(right: 20, top: 8),
              child: ActionChip(
                avatar: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 18,
                ),
                label: Text(fcfa(app.currentPro!.wallet.balance)),
                tooltip: 'Mon solde',
                onPressed: onOpenWallet,
              ),
            ),
          ],
        ),
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
                          if (b.contract case final c?)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: InfoBanner(
                                icon: Icons.repeat,
                                text:
                                    'Suivi de ${c.sessions.length} séances, '
                                    '${c.frequency.label.toLowerCase()}, du '
                                    '${dateTimeLabel(c.start)} au '
                                    '${dateTimeLabel(c.end)}. Commission réduite '
                                    'à ${(contractCommissionRate * 100).round()} % : '
                                    '${fcfa(c.sessions.fold(0, (s, x) => s + x.proEarnings))} '
                                    'pour vous au total.',
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Répondez avant ${dateTimeLabel(b.responseDeadline)}.',
                              style: const TextStyle(color: Colors.black54),
                            ),
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
                                      _respond(context, b, accept: false),
                                  child: const Text('Refuser'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () =>
                                      _respond(context, b, accept: true),
                                  child: Text(
                                    b.contract == null
                                        ? 'Accepter'
                                        : 'Accepter le suivi',
                                  ),
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
    final app = AppScope.of(context);
    final list = app.proBookings(BookingStatus.accepted)
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
                      footer: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!b.readyForCare)
                            InfoBanner(
                              icon: Icons.hourglass_top_rounded,
                              warning: true,
                              text:
                                  'Le patient n’a pas encore payé (limite : '
                                  '${dateTimeLabel(b.paymentDeadline!)}). Ne '
                                  'vous déplacez pas avant la confirmation du '
                                  'paiement.',
                            )
                          else
                            FilledButton.icon(
                              onPressed: app.canLogCare(b)
                                  ? () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            CareLogFormScreen(booking: b),
                                      ),
                                    )
                                  : null,
                              icon: const Icon(Icons.edit_note),
                              label: Text(
                                app.canLogCare(b)
                                    ? 'Rédiger le compte rendu'
                                    : 'Compte rendu à partir de '
                                          '${dateTimeLabel(b.careLogOpensAt)}',
                              ),
                            ),
                          const SizedBox(height: 4),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .error,
                            ),
                            onPressed: () => _cancelByPro(context, b),
                            child: Text(
                              b.contract == null
                                  ? 'Annuler ce soin'
                                  : 'Annuler le suivi',
                            ),
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
                                runAction(
                                  context,
                                  () => app.updateProAvailability(
                                    p,
                                    communes: next,
                                    nightAvailable: p.nightAvailable,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: p.nightAvailable,
                        onChanged: (v) => runAction(
                          context,
                          () => app.updateProAvailability(
                            p,
                            communes: p.communes,
                            nightAvailable: v,
                          ),
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
              const SizedBox(height: 12),
              _PremiumCard(pro: p),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.group_add_outlined),
                  title: Text('Mon code de parrainage : ${p.referralCode}'),
                  subtitle: Text(
                    'Donnez-le à un collègue soignant : ${referralBonus.inDays} '
                    'jours de Premium offerts dès que son compte est vérifié.',
                  ),
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

Future<void> _respond(
  BuildContext context,
  Booking b, {
  required bool accept,
}) => runAction(context, () => AppScope.of(context).respond(b, accept: accept));

Future<void> _cancelByPro(BuildContext context, Booking b) async {
  final ctrl = TextEditingController();
  final app = AppScope.of(context);
  final reason = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        b.contract == null ? 'Annuler ce soin ?' : 'Annuler tout le suivi ?',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${b.patientName} sera remboursé(e) en totalité. Au-delà de '
            '$proCancellationAlertCount annulations en '
            '${proCancellationAlertPeriod.inDays} jours, MyNurse revoit votre '
            'compte.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Motif (vu par le patient)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Garder le soin'),
        ),
        TextButton(
          onPressed: () {
            if (ctrl.text.trim().isNotEmpty) {
              Navigator.pop(context, ctrl.text.trim());
            }
          },
          child: const Text('Annuler le soin'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (reason != null && context.mounted) {
    await runAction(context, () => app.cancelByPro(b, reason));
  }
}

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.pro});

  final Pro pro;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final active = pro.isPremium(app.now);
    final stats = app.proStats(pro);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.workspace_premium_outlined,
                  color: Color(0xFFB8860B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active
                        ? 'Pro Premium jusqu’au ${dateTimeLabel(pro.premiumUntil!)}'
                        : 'Pro Premium',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Vous apparaissez en tête des résultats dans vos communes, et vous '
              'suivez vos chiffres. ${fcfa(premiumPrice)} pour '
              '${premiumPeriod.inDays} jours, payés avec votre solde.',
              style: const TextStyle(color: Colors.black54),
            ),
            if (active) ...[
              const Divider(height: 24),
              const Text(
                'Vos 30 derniers jours',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '${stats.cares} soin${stats.cares > 1 ? 's' : ''} terminé${stats.cares > 1 ? 's' : ''} · ${fcfa(stats.earnings)} gagnés',
              ),
              Text('Taux d’acceptation : ${stats.acceptance} %'),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await runAction(
                  context,
                  () => app.subscribePremium(pro),
                );
                if (ok) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Pro Premium activé jusqu’au ${dateTimeLabel(pro.premiumUntil!)}.',
                      ),
                    ),
                  );
                }
              },
              child: Text(
                active
                    ? 'Prolonger de ${premiumPeriod.inDays} jours (${fcfa(premiumPrice)})'
                    : 'Passer Premium (${fcfa(premiumPrice)})',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
