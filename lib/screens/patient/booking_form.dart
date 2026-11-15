import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';

class BookingFormScreen extends StatefulWidget {
  const BookingFormScreen({super.key, required this.pro, required this.service});

  final Pro pro;
  final CareService service;

  @override
  State<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends State<BookingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _note = TextEditingController();
  late DateTime _when;
  bool _prescription = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = DateTime.now().add(const Duration(days: 1));
    _when = DateTime(t.year, t.month, t.day, 9);
  }

  @override
  void dispose() {
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (d != null) {
      setState(() =>
          _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (t != null) {
      setState(() => _when =
          DateTime(_when.year, _when.month, _when.day, t.hour, t.minute));
    }
  }

  void _submit() {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_when.isBefore(DateTime.now())) {
      setState(() => _error = 'Choisissez une date et une heure à venir.');
      return;
    }
    if (isNight(_when) && !widget.pro.nightAvailable) {
      setState(() => _error =
          '${widget.pro.name} ne fait pas de soins de nuit (21 h – 6 h). '
          'Choisissez une autre heure ou un autre soignant.');
      return;
    }
    if (widget.service.needsPrescription && !_prescription) {
      setState(() => _error = 'Ce soin se fait uniquement sur ordonnance.');
      return;
    }
    final app = AppScope.of(context);
    app.book(
      service: widget.service,
      pro: widget.pro,
      commune: app.commune,
      address: _address.text.trim(),
      scheduledAt: _when,
      hasPrescription: _prescription,
      note: _note.text.trim(),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => _ConfirmationScreen(pro: widget.pro)),
      (r) => r.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final base = widget.pro.prices[widget.service.id]!;
    final night = isNight(_when);
    final total = night ? (base * (1 + nightSurchargeRate)).round() : base;
    return Scaffold(
      appBar: AppBar(title: const Text('Réserver')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(
              widget.service.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              'avec ${widget.pro.name} · ${app.commune}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      '${_when.day.toString().padLeft(2, '0')}/'
                      '${_when.month.toString().padLeft(2, '0')}/${_when.year}',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(timeLabel(_when)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _address,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Adresse et repères',
                hintText: 'Quartier, résidence, repère connu…',
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().length < 8)
                  ? "Indiquez l'adresse avec un repère."
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Précisions pour le soignant (facultatif)',
                alignLabelWithHint: true,
              ),
            ),
            if (widget.service.needsPrescription) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _prescription,
                onChanged: (v) => setState(() => _prescription = v!),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text("J'ai une ordonnance pour ce soin"),
                subtitle: const Text('Le soignant la vérifiera sur place.'),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _row('Prix du soin', fcfa(base)),
                    if (night)
                      _row('Majoration de nuit (50 %)', fcfa(total - base)),
                    const Divider(height: 20),
                    _row('Total', fcfa(total), bold: true),
                    const SizedBox(height: 8),
                    const Text(
                      'Paiement Mobile Money après confirmation du soignant.',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submit,
              child: const Text('Envoyer la demande'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontSize: bold ? 17 : 15,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _ConfirmationScreen extends StatelessWidget {
  const _ConfirmationScreen({required this.pro});

  final Pro pro;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const Icon(Icons.check_circle, size: 72, color: Color(0xFF0B7A6E)),
              const SizedBox(height: 20),
              const Text(
                'Demande envoyée',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '${pro.name} va confirmer votre demande. Vous la retrouvez '
                'dans « Mes soins ».',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Retour à l'accueil"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
