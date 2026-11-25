import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'admin_ops.dart';
import 'admin_widgets.dart';

String _kind(WalletTxKind k) => switch (k) {
  WalletTxKind.topUp => 'Recharge',
  WalletTxKind.payment => 'Paiement',
  WalletTxKind.refund => 'Remboursement',
  WalletTxKind.earning => 'Gain soignant',
  WalletTxKind.withdrawal => 'Retrait',
  WalletTxKind.subscription => 'Abonnement',
};

// ================================================================ finances
class FinanceModule extends StatefulWidget {
  const FinanceModule({super.key, required this.period});

  final Period period;

  @override
  State<FinanceModule> createState() => _FinanceModuleState();
}

class _FinanceModuleState extends State<FinanceModule> {
  WalletTxKind? _kind0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.adminMetrics(widget.period);
    final txs = app.adminTransactions(widget.period, kind: _kind0);
    int sum(WalletTxKind k) => app
        .adminTransactions(widget.period, kind: k)
        .fold(0, (s, e) => s + e.tx.amount.abs());
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ModuleHeader(
          title: 'Finances',
          subtitle: widget.period.label,
          actions: [
            ExportButton(
              title: 'Mouvements',
              csv: () => app.toCsv(
                ['Date', 'Compte', 'Type', 'Libellé', 'Montant'],
                [
                  for (final e in txs)
                    [
                      e.tx.at.toIso8601String().substring(0, 16),
                      e.owner,
                      _kind(e.tx.kind),
                      e.tx.label,
                      e.tx.amount,
                    ],
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: MetricGrid(
            children: [
              MetricCard(
                label: 'Volume des soins réalisés',
                value: fcfa(m.volume),
              ),
              MetricCard(label: 'Commissions', value: fcfa(m.commissions)),
              MetricCard(
                label: 'Gains des soignants',
                value: fcfa(m.proEarnings),
              ),
              MetricCard(
                label: 'Recharges',
                value: fcfa(sum(WalletTxKind.topUp)),
              ),
              MetricCard(
                label: 'Retraits des soignants',
                value: fcfa(sum(WalletTxKind.withdrawal)),
              ),
              MetricCard(
                label: 'Remboursements',
                value: fcfa(sum(WalletTxKind.refund)),
              ),
              MetricCard(
                label: 'Argent bloqué (soins payés à venir)',
                value: fcfa(app.escrowTotal),
                hint: 'à tout moment',
              ),
              MetricCard(
                label: 'Soldes des familles',
                value: fcfa(app.clientBalances),
                hint: 'à tout moment',
              ),
              MetricCard(
                label: 'Soldes des soignants',
                value: fcfa(app.proBalances),
                hint: 'à tout moment',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilterRow<WalletTxKind>(
          values: WalletTxKind.values,
          selected: _kind0,
          label: _kind,
          onSelected: (k) => setState(() => _kind0 = k),
        ),
        if (txs.isEmpty)
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            text: 'Aucun mouvement sur la période.',
          ),
        for (final e in txs.take(200))
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            dense: true,
            title: Text('${e.owner} · ${e.tx.label}'),
            subtitle: Text('${_kind(e.tx.kind)} · ${dateTimeLabel(e.tx.at)}'),
            trailing: Text(
              '${e.tx.amount > 0 ? '+' : '−'}${fcfa(e.tx.amount.abs())}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: e.tx.amount > 0 ? brandGreen : null,
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================= commissions
class CommissionsModule extends StatelessWidget {
  const CommissionsModule({super.key, required this.period});

  final Period period;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final done = app
        .adminBookings(period, status: BookingStatus.done)
        .where((b) => period.contains(b.scheduledAt))
        .toList();
    final total = done.fold<int>(0, (s, b) => s + b.commission);
    final fees = app.bookings.fold<int>(
      0,
      (s, b) => s + (b.cancellationFee * b.commissionRate).round(),
    );
    final rate = app.commissionOverride ?? commissionRate;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ModuleHeader(
          title: 'Commissions',
          subtitle: period.label,
          actions: [
            ExportButton(
              title: 'Commissions',
              csv: () => app.toCsv(
                [
                  'Date',
                  'Soin',
                  'Soignant',
                  'Prix',
                  'Taux',
                  'Commission',
                  'Net soignant',
                ],
                [
                  for (final b in done)
                    [
                      b.scheduledAt.toIso8601String().substring(0, 10),
                      b.service.name,
                      b.pro.name,
                      b.price,
                      '${(b.commissionRate * 100).round()} %',
                      b.commission,
                      b.proEarnings,
                    ],
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: MetricGrid(
            children: [
              MetricCard(
                label: 'Taux actuel (nouveaux soins)',
                value:
                    '${(rate * 100).toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')} %',
              ),
              MetricCard(
                label: 'Commissions sur la période',
                value: fcfa(total),
                hint: '${done.length} soins',
              ),
              MetricCard(
                label: 'Part des annulations tardives',
                value: fcfa(fees),
                hint: 'depuis le début',
              ),
            ],
          ),
        ),
        if (app.hasAdminPerm(AdminPermission.manageSettings))
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: OutlinedButton.icon(
              onPressed: () async {
                final r = await askReason(
                  context,
                  'Modifier le taux de commission',
                  label: 'Nouveau taux en % (ex. 10)',
                  help:
                      'S’applique aux nouveaux soins seulement. Les soins déjà '
                      'réservés gardent leur taux.',
                );
                final v = double.tryParse(
                  (r ?? '').replaceAll(',', '.').replaceAll('%', '').trim(),
                );
                if (r == null || !context.mounted) return;
                if (v == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Indiquez un nombre, par exemple 10.'),
                    ),
                  );
                  return;
                }
                await runAction(context, () => app.adminSetCommission(v / 100));
              },
              icon: const Icon(Icons.tune),
              label: const Text('Modifier le taux'),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: BlockTitle('Détail par soin'),
        ),
        for (final b in done)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            dense: true,
            title: Text('${b.service.name.split(' (').first} · ${b.pro.name}'),
            subtitle: Text(
              '${dateTimeLabel(b.scheduledAt)} · ${fcfa(b.price)} × ${(b.commissionRate * 100).round()} %',
            ),
            trailing: Text(
              fcfa(b.commission),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

// ========================================================== remboursements
class RefundsModule extends StatelessWidget {
  const RefundsModule({super.key, required this.period});

  final Period period;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final refunded = app.adminRefunds(period);
    final refundable = app
        .adminBookings(period)
        .where(
          (b) =>
              b.paid &&
              b.refundAmount < b.price &&
              b.status != BookingStatus.done,
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ModuleHeader(
          title: 'Remboursements',
          subtitle:
              '${refunded.length} remboursement(s) · ${fcfa(refunded.fold(0, (s, b) => s + b.refundAmount))}',
          actions: [
            ExportButton(
              title: 'Remboursements',
              csv: () => app.toCsv(
                [
                  'Date',
                  'Soin',
                  'Patient',
                  'Soignant',
                  'Payé',
                  'Remboursé',
                  'Motif',
                ],
                [
                  for (final b in refunded)
                    [
                      b.scheduledAt.toIso8601String().substring(0, 10),
                      b.service.name,
                      b.patientName,
                      b.pro.name,
                      b.price,
                      b.refundAmount,
                      b.cancelReason,
                    ],
                ],
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Remboursements automatiques (annulation, absence de réponse, '
            'soignant suspendu) et gestes de l’équipe. L’argent revient sur '
            'le solde MyNurse de la famille.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: BlockTitle('Effectués'),
        ),
        if (refunded.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Aucun remboursement sur la période.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        for (final b in refunded)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(
              '${b.service.name.split(' (').first} · ${b.patientName}',
            ),
            subtitle: Text(
              '${dateTimeLabel(b.scheduledAt)} · ${b.cancelReason}',
            ),
            trailing: Text(
              fcfa(b.refundAmount),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        if (refundable.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: BlockTitle('Soins payés remboursables'),
          ),
          for (final b in refundable)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(
                '${b.service.name.split(' (').first} · ${b.patientName}',
              ),
              subtitle: Text(
                '${dateTimeLabel(b.scheduledAt)} · payé ${fcfa(b.price)}',
              ),
              trailing: TextButton(
                onPressed: () => showRefundDialog(context, b),
                child: const Text('Rembourser'),
              ),
            ),
        ],
      ],
    );
  }
}

// ============================================================ abonnements
class SubscriptionsModule extends StatelessWidget {
  const SubscriptionsModule({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final active = app.pros.where((p) => p.isPremium(app.now)).toList();
    final ended = app.pros
        .where((p) => p.premiumUntil != null && !p.isPremium(app.now))
        .toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ModuleHeader(
          title: 'Abonnements Pro Premium',
          subtitle: '${fcfa(premiumPrice)} pour ${premiumPeriod.inDays} jours',
          actions: [
            ExportButton(
              title: 'Abonnements',
              csv: () => app.toCsv(
                ['Soignant', 'Profession', 'Fin de Premium', 'Actif'],
                [
                  for (final p in [...active, ...ended])
                    [
                      p.name,
                      p.type.label,
                      p.premiumUntil?.toIso8601String().substring(0, 10),
                      p.isPremium(app.now) ? 'oui' : 'non',
                    ],
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: MetricGrid(
            children: [
              MetricCard(label: 'Premium actifs', value: '${active.length}'),
              MetricCard(
                label: 'Revenus des abonnements',
                value: fcfa(app.premiumRevenue),
                hint: 'depuis le début',
              ),
              MetricCard(label: 'Expirés', value: '${ended.length}'),
            ],
          ),
        ),
        for (final p in [...active, ...ended])
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: ProAvatar(p, radius: 20),
            title: Text(p.name),
            subtitle: Text(
              p.isPremium(app.now)
                  ? 'Premium jusqu’au ${dateTimeLabel(p.premiumUntil!).split(' à ').first}'
                  : 'Terminé le ${dateTimeLabel(p.premiumUntil!).split(' à ').first}',
            ),
            trailing: app.hasAdminPerm(AdminPermission.finance)
                ? TextButton(
                    onPressed: () async {
                      final r = await askReason(
                        context,
                        'Offrir 30 jours à ${p.name}',
                        label: 'Motif (geste, parrainage manuel…)',
                        minLength: 3,
                      );
                      if (r != null && context.mounted) {
                        await runAction(
                          context,
                          () => app.adminExtendPremium(p, 30, r),
                        );
                      }
                    },
                    child: const Text('+30 jours'),
                  )
                : null,
          ),
        if (active.isEmpty && ended.isEmpty)
          const EmptyState(
            icon: Icons.workspace_premium_outlined,
            text: 'Aucun abonnement.',
          ),
      ],
    );
  }
}
