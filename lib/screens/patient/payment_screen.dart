import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';

/// Paiement Mobile Money. En production, l'agrégateur (CinetPay ou PayDunya)
/// envoie la demande sur le téléphone du patient et confirme au serveur.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.booking});

  final Booking booking;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  PaymentMethod _method = PaymentMethod.wave;
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

  Future<void> _pay() async {
    if (_phone.text.length != 10) {
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
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    app.pay(widget.booking, _method);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Paiement de ${fcfa(widget.booking.price)} reçu.'),
      ),
    );
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
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
              groupValue: _method,
              onChanged: (m) => setState(() => _method = m!),
              child: Column(
                children: [
                  for (final m in PaymentMethod.values)
                    RadioListTile<PaymentMethod>(
                      value: m,
                      title: Text(m.label),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: InputDecoration(
              labelText: 'Numéro ${_method.label}',
              prefixText: '+225  ',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'L’argent est conservé par MyNurse jusqu’à la fin du soin, puis '
            'reversé au soignant. En cas d’annulation, vous êtes remboursé.',
            style: TextStyle(color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 8),
          const Text(
            'Mode démo : aucun argent n’est débité.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _pay,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text('Payer ${fcfa(b.price)}'),
          ),
        ],
      ),
    );
  }
}
