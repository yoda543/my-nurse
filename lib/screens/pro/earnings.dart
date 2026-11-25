import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../wallet.dart' show WithdrawScreen;

/// Revenus : solde retirable, gains à venir, évolution, commissions et
/// retraits.
class ProEarningsTab extends StatelessWidget {
  const ProEarningsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.currentPro!;
    final done = app.proDone;
    final weeks = app.proWeeklyEarnings;
    final maxWeek = weeks.fold<int>(1, (m, w) => w.amount > m ? w.amount : m);
    final commission = done.fold<int>(0, (s, b) => s + b.commission);
    final withdrawals = app.proWithdrawals;
    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 20, 4, 12),
                child: Text(
                  'Revenus',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
              ),
              Card(
                color: brandInk,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Solde disponible',
                        style: TextStyle(color: Color(0xFFB9CDD0)),
                      ),
                      Text(
                        fcfa(p.wallet.balance),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: brandInk,
                        ),
                        onPressed: p.wallet.balance < minWithdrawal
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const WithdrawScreen(),
                                ),
                              ),
                        icon: const Icon(Icons.send_to_mobile_outlined),
                        label: Text(
                          p.wallet.balance < minWithdrawal
                              ? 'Retrait possible dès ${fcfa(minWithdrawal)}'
                              : 'Retirer vers Mobile Money',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat(label: 'Ce mois', value: fcfa(app.proMonthEarnings)),
                  const SizedBox(width: 8),
                  _Stat(
                    label: 'À venir (déjà payé)',
                    value: fcfa(app.upcomingEarnings(p)),
                  ),
                ],
              ),
              const BlockTitle('6 dernières semaines'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                  child: SizedBox(
                    height: 170,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final w in weeks)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  FittedBox(
                                    child: Text(
                                      w.amount == 0
                                          ? '–'
                                          : '${(w.amount / 1000).toStringAsFixed(w.amount < 10000 ? 1 : 0).replaceAll('.', ',')} k',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    height: 90 * w.amount / maxWeek + 2,
                                    decoration: BoxDecoration(
                                      color: w == weeks.last
                                          ? brandGreen
                                          : const Color(0xFF7FB8B1),
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(4),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${w.week.day}/${w.week.month}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              BlockTitle(
                'Commissions',
                action: Text(
                  '${fcfa(commission)} au total',
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
              Text(
                'MyNurse prélève ${(commissionRate * 100).round()} % sur chaque '
                'soin terminé. Le reste est versé sur votre solde à l’envoi du '
                'compte rendu.',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 8),
              if (done.isEmpty)
                const Text('Aucun soin terminé pour l’instant.'),
              if (done.isNotEmpty)
                Card(
                  child: Column(
                    children: [
                      for (final b in done.take(20))
                        ListTile(
                          dense: true,
                          title: Text(
                            '${b.service.name.split(' (').first} · ${b.patientName}',
                          ),
                          subtitle: Text(
                            '${dateTimeLabel(b.scheduledAt)}\n'
                            'Prix ${fcfa(b.price)} − commission ${fcfa(b.commission)} '
                            '(${(b.commissionRate * 100).round()} %)',
                          ),
                          isThreeLine: true,
                          trailing: Text(
                            fcfa(b.proEarnings),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                    ],
                  ),
                ),
              const BlockTitle('Retraits'),
              if (withdrawals.isEmpty)
                const Text(
                  'Aucun retrait. L’argent arrive en général en quelques '
                  'minutes sur votre compte Mobile Money.',
                  style: TextStyle(color: Colors.black54),
                ),
              for (final w in withdrawals)
                Card(
                  child: ListTile(
                    leading: Icon(
                      w.amount < 0 ? Icons.send_to_mobile_outlined : Icons.undo,
                      color: w.amount < 0
                          ? brandGreen
                          : const Color(0xFF8A5A00),
                    ),
                    title: Text(w.label),
                    subtitle: Text(
                      '${dateTimeLabel(w.at)} · '
                      '${w.amount < 0 ? 'envoyé' : 'non abouti, recrédité'}',
                    ),
                    trailing: Text(
                      fcfa(w.amount.abs()),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
