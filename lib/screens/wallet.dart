import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Arrondit au multiple de 500 FCFA supérieur.
int roundUp500(int v) => ((v + 499) ~/ 500) * 500;

// ---------------------------------------------------------------- partagés

/// Choix du compte Mobile Money et du numéro.
class MobileMoneyPicker extends StatelessWidget {
  const MobileMoneyPicker({
    super.key,
    required this.method,
    required this.onChanged,
    required this.phone,
    this.error,
  });

  final PaymentMethod method;
  final ValueChanged<PaymentMethod> onChanged;
  final TextEditingController phone;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: RadioGroup<PaymentMethod>(
            groupValue: method,
            onChanged: (m) => onChanged(m!),
            child: Column(
              children: [
                for (final m in mobileMoneyMethods)
                  RadioListTile<PaymentMethod>(value: m, title: Text(m.label)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: InputDecoration(
            labelText: 'Numéro ${method.label}',
            prefixText: '+225  ',
            errorText: error,
          ),
        ),
      ],
    );
  }
}

/// Historique des mouvements d'un solde.
class WalletHistory extends StatelessWidget {
  const WalletHistory({super.key, required this.wallet});

  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    if (wallet.history.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          'Aucun mouvement pour le moment.',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }
    return Column(
      children: [
        for (final t in wallet.history)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: CircleAvatar(
              backgroundColor: t.amount > 0
                  ? const Color(0xFFD5EDE9)
                  : const Color(0xFFF1ECE2),
              child: Icon(
                switch (t.kind) {
                  WalletTxKind.topUp => Icons.add_card,
                  WalletTxKind.payment => Icons.medical_services_outlined,
                  WalletTxKind.refund => Icons.undo,
                  WalletTxKind.earning => Icons.healing_outlined,
                  WalletTxKind.withdrawal => Icons.call_made,
                  WalletTxKind.subscription => Icons.workspace_premium_outlined,
                },
                color: t.amount > 0 ? brandGreen : brandInk,
                size: 20,
              ),
            ),
            title: Text(t.label),
            subtitle: Text(dateTimeLabel(t.at)),
            trailing: Text(
              '${t.amount > 0 ? '+' : '−'} ${fcfa(t.amount.abs())}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.amount > 0 ? brandGreen : brandInk,
              ),
            ),
          ),
      ],
    );
  }
}

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({
    required this.label,
    required this.amount,
    required this.action,
    required this.onAction,
    this.footnote,
  });

  final String label;
  final int amount;
  final String action;
  final VoidCallback? onAction;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: brandGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            fcfa(amount),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 4),
            Text(footnote!, style: const TextStyle(color: Colors.white70)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: brandGreen,
            ),
            onPressed: onAction,
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ patient

/// Carte du solde affichée en haut de l'accueil patient.
class PatientWalletCard extends StatelessWidget {
  const PatientWalletCard({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PatientWalletScreen())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: brandGreen,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mon solde MyNurse',
                      style: TextStyle(color: Colors.black54),
                    ),
                    Text(
                      fcfa(app.wallet.balance),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const TopUpScreen())),
                icon: const Icon(Icons.add),
                label: const Text('Recharger'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PatientWalletScreen extends StatelessWidget {
  const PatientWalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mon solde')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: _BalanceHeader(
              label: 'Solde disponible',
              amount: app.wallet.balance,
              action: 'Recharger mon compte',
              onAction: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const TopUpScreen())),
              footnote:
                  'Payez vos soins en un geste. Les remboursements '
                  'arrivent ici tout de suite.',
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 4),
            child: Text(
              'Historique',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          WalletHistory(wallet: app.wallet),
        ],
      ),
    );
  }
}

class TopUpScreen extends StatefulWidget {
  const TopUpScreen({super.key, this.suggested});

  /// Montant proposé (par exemple ce qui manque pour payer un soin).
  final int? suggested;

  @override
  State<TopUpScreen> createState() => _TopUpScreenState();
}

class _TopUpScreenState extends State<TopUpScreen> {
  static const _quick = [5000, 10000, 25000, 50000];

  late final _amount = TextEditingController(
    text: '${widget.suggested ?? 10000}',
  );
  late final _phone = TextEditingController(
    text: AppScope.of(context).sessionPhone,
  );
  PaymentMethod _method = PaymentMethod.wave;
  bool _busy = false;
  String? _amountError;
  String? _phoneError;

  @override
  void dispose() {
    _amount.dispose();
    _phone.dispose();
    super.dispose();
  }

  int get _value => int.tryParse(_amount.text) ?? 0;

  Future<void> _submit() async {
    final v = _value;
    setState(() {
      _amountError = (v < minTopUp || v > maxTopUp)
          ? 'Entre ${fcfa(minTopUp)} et ${fcfa(maxTopUp)}.'
          : null;
      _phoneError = _phone.text.length != 10
          ? 'Entrez le numéro Mobile Money à 10 chiffres.'
          : null;
    });
    if (_amountError != null || _phoneError != null) return;
    setState(() => _busy = true);
    final app = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (!app.isRemote) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    if (!mounted) return;
    final ok = await runAction(context, () => app.topUp(v, _method));
    if (!ok) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Compte rechargé de ${fcfa(v)}. Nouveau solde : '
          '${fcfa(app.wallet.balance)}.',
        ),
      ),
    );
    nav.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Recharger mon compte')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text(
            'Solde actuel : ${fcfa(app.wallet.balance)}',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in _quick)
                ChoiceChip(
                  label: Text(fcfa(q)),
                  selected: _value == q,
                  onSelected: (_) => setState(() => _amount.text = '$q'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Montant',
              suffixText: 'FCFA',
              errorText: _amountError,
            ),
          ),
          const SizedBox(height: 16),
          MobileMoneyPicker(
            method: _method,
            onChanged: (m) => setState(() => _method = m),
            phone: _phone,
            error: _phoneError,
          ),
          const SizedBox(height: 12),
          const Text(
            'Vous validez la recharge sur votre téléphone. Mode démo : aucun '
            'argent n’est débité.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text('Recharger ${fcfa(_value)}'),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- soignant

/// Onglet « Solde » du soignant.
class ProWalletTab extends StatelessWidget {
  const ProWalletTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.currentPro!;
    final upcoming = app.upcomingEarnings(p);
    final done = app.proBookings(BookingStatus.done);
    final commission = done.fold<int>(0, (s, b) => s + b.commission);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionTitle('Mon solde'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _BalanceHeader(
            label: 'Solde disponible',
            amount: p.wallet.balance,
            action: 'Retirer vers Mobile Money',
            onAction: p.wallet.balance < minWithdrawal
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WithdrawScreen()),
                  ),
            footnote:
                'Crédité dès que vous terminez un soin, commission '
                'déduite.',
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.hourglass_top_rounded),
                  title: const Text('À venir'),
                  subtitle: const Text(
                    'Déjà payé par vos patients, versé à '
                    'la fin des soins',
                  ),
                  trailing: Text(
                    fcfa(upcoming),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.percent),
                  title: const Text('Commission MyNurse'),
                  subtitle: Text(
                    '$commissionPercent % sur ${done.length} soin${done.length > 1 ? 's' : ''} '
                    'terminé${done.length > 1 ? 's' : ''}',
                  ),
                  trailing: Text(fcfa(commission)),
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 4),
          child: Text(
            'Historique',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        WalletHistory(wallet: p.wallet),
      ],
    );
  }
}

class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  late final _amount = TextEditingController(
    text: '${AppScope.of(context).currentPro!.wallet.balance}',
  );
  late final _phone = TextEditingController(
    text: AppScope.of(context).sessionPhone,
  );
  PaymentMethod _method = PaymentMethod.wave;
  bool _busy = false;
  String? _amountError;
  String? _phoneError;

  @override
  void dispose() {
    _amount.dispose();
    _phone.dispose();
    super.dispose();
  }

  int get _value => int.tryParse(_amount.text) ?? 0;

  Future<void> _submit() async {
    final app = AppScope.of(context);
    final balance = app.currentPro!.wallet.balance;
    final v = _value;
    setState(() {
      _amountError = v < minWithdrawal
          ? 'Minimum ${fcfa(minWithdrawal)}.'
          : v > balance
          ? 'Votre solde est de ${fcfa(balance)}.'
          : null;
      _phoneError = _phone.text.length != 10
          ? 'Entrez le numéro Mobile Money à 10 chiffres.'
          : null;
    });
    if (_amountError != null || _phoneError != null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (!app.isRemote) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    if (!mounted) return;
    final ok = await runAction(
      context,
      () => app.withdraw(app.currentPro!, v, _method, phone: _phone.text),
    );
    if (!ok) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          app.isRemote
              ? 'Retrait de ${fcfa(v)} demandé vers votre compte ${_method.label}.'
              : '${fcfa(v)} envoyés sur votre compte ${_method.label}.',
        ),
      ),
    );
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final balance = AppScope.of(context).currentPro!.wallet.balance;
    return Scaffold(
      appBar: AppBar(title: const Text('Retirer mes gains')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text(
            'Solde disponible : ${fcfa(balance)}',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Montant à retirer',
              suffixText: 'FCFA',
              errorText: _amountError,
            ),
          ),
          const SizedBox(height: 16),
          MobileMoneyPicker(
            method: _method,
            onChanged: (m) => setState(() => _method = m),
            phone: _phone,
            error: _phoneError,
          ),
          const SizedBox(height: 12),
          const Text(
            'L’argent arrive en général en quelques minutes. Mode démo : '
            'aucun virement n’est fait.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text('Retirer ${fcfa(_value)}'),
          ),
        ],
      ),
    );
  }
}
