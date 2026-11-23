import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../widgets.dart';
import '../wallet.dart';

/// Paiement d'un soin : avec le solde MyNurse ou directement en Mobile Money.
/// En production, un paiement Mobile Money est confirmé au serveur par
/// l'agrégateur (CinetPay ou PayDunya), jamais par l'app.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.booking});

  final Booking booking;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  PaymentMethod? _choice;
  late final _phone = TextEditingController(
    text: AppScope.of(context).sessionPhone,
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pay(PaymentMethod method) async {
    if (method != PaymentMethod.wallet && _phone.text.length != 10) {
      setState(() => _error = 'Entrez le numéro Mobile Money à 10 chiffres.');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final app = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (method != PaymentMethod.wallet) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    if (!app.pay(widget.booking, method)) {
      setState(() {
        _busy = false;
        _error = 'Solde insuffisant. Rechargez votre compte.';
      });
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Paiement de ${fcfa(widget.booking.price)} reçu'
          '${method == PaymentMethod.wallet ? '. Solde restant : ${fcfa(app.wallet.balance)}' : ''}.',
        ),
      ),
    );
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = widget.booking;
    final balance = app.wallet.balance;
    final enough = balance >= b.price;
    final method =
        _choice ?? (enough ? PaymentMethod.wallet : PaymentMethod.wave);
    final missing = b.price - balance;
    return Scaffold(
      appBar: AppBar(title: const Text('Paiement')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text(
            fcfa(b.price),
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
          ),
          Text(
            '${b.service.name} · ${b.pro.name}\n${dateTimeLabel(b.scheduledAt)}',
            style: const TextStyle(color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 20),
          Card(
            child: RadioGroup<PaymentMethod>(
              groupValue: method == PaymentMethod.wallet
                  ? PaymentMethod.wallet
                  : PaymentMethod.wave,
              onChanged: (m) => setState(() {
                _choice = m;
                _error = null;
              }),
              child: Column(
                children: [
                  RadioListTile<PaymentMethod>(
                    value: PaymentMethod.wallet,
                    title: const Text('Mon solde MyNurse'),
                    subtitle: Text('Disponible : ${fcfa(balance)}'),
                  ),
                  const RadioListTile<PaymentMethod>(
                    value: PaymentMethod.wave,
                    title: Text('Mobile Money'),
                    subtitle: Text('Orange Money, MTN MoMo, Moov Money, Wave'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (method == PaymentMethod.wallet && !enough) ...[
            InfoBanner(
              icon: Icons.account_balance_wallet_outlined,
              warning: true,
              text:
                  'Il vous manque ${fcfa(missing)}. Rechargez votre compte '
                  'ou payez directement en Mobile Money.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TopUpScreen(suggested: roundUp500(missing)),
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text('Recharger ${fcfa(roundUp500(missing))}'),
            ),
          ],
          if (method != PaymentMethod.wallet)
            MobileMoneyPicker(
              method: method,
              onChanged: (m) => setState(() => _choice = m),
              phone: _phone,
              error: _error,
            ),
          if (method == PaymentMethod.wallet && _error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'L’argent est conservé par MyNurse jusqu’à la fin du soin, puis '
            'reversé au soignant. En cas d’annulation, il revient sur votre '
            'solde MyNurse.',
            style: TextStyle(color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 8),
          const Text(
            'Mode démo : aucun argent n’est débité.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy || (method == PaymentMethod.wallet && !enough)
                ? null
                : () => _pay(method),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text(
                    method == PaymentMethod.wallet
                        ? 'Payer ${fcfa(b.price)} avec mon solde'
                        : 'Payer ${fcfa(b.price)}',
                  ),
          ),
        ],
      ),
    );
  }
}
