import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';

/// Journal de soins : le compte rendu rempli par le soignant à chaque passage.
class CareLogFormScreen extends StatefulWidget {
  const CareLogFormScreen({super.key, required this.booking});

  final Booking booking;

  @override
  State<CareLogFormScreen> createState() => _CareLogFormScreenState();
}

class _CareLogFormScreenState extends State<CareLogFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bp = TextEditingController();
  final _temp = TextEditingController();
  final _pulse = TextEditingController();
  final _gly = TextEditingController();
  final _acts = TextEditingController();
  final _obs = TextEditingController();
  late TimeOfDay _arrival;
  late TimeOfDay _departure;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.booking.scheduledAt;
    _arrival = TimeOfDay.fromDateTime(s);
    _departure = TimeOfDay.fromDateTime(s.add(const Duration(minutes: 30)));
  }

  @override
  void dispose() {
    for (final c in [_bp, _temp, _pulse, _gly, _acts, _obs]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime _at(TimeOfDay t) {
    final d = widget.booking.scheduledAt;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _pick(bool arrival) async {
    final t = await showTimePicker(
      context: context,
      initialTime: arrival ? _arrival : _departure,
    );
    if (t != null) {
      setState(() => arrival ? _arrival = t : _departure = t);
    }
  }

  void _submit() {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    var left = _at(_departure);
    final arrived = _at(_arrival);
    // Un soin de nuit peut se terminer après minuit.
    if (left.isBefore(arrived)) left = left.add(const Duration(days: 1));
    if (left.difference(arrived).inHours >= 14) {
      setState(() => _error = "Vérifiez les heures d'arrivée et de départ.");
      return;
    }
    try {
      AppScope.of(context).submitCareLog(
        widget.booking,
        CareLog(
          arrivedAt: arrived,
          leftAt: left,
          acts: _acts.text.trim(),
          bloodPressure: _bp.text.trim(),
          temperature: _temp.text.trim(),
          pulse: _pulse.text.trim(),
          glycemia: _gly.text.trim(),
          observations: _obs.text.trim(),
        ),
      );
    } on BusinessRuleError catch (e) {
      setState(() => _error = e.message);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Compte rendu enregistré et envoyé au patient.'),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    return Scaffold(
      appBar: AppBar(title: const Text('Compte rendu du soin')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                b.service.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${b.patientName} · ${dateTimeLabel(b.scheduledAt)}',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(true),
                      child: Text('Arrivée ${timeLabel(_at(_arrival))}'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(false),
                      child: Text('Départ ${timeLabel(_at(_departure))}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Constantes (facultatif)',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _field(_bp, 'Tension', hint: '12/8')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(_temp, 'Température °C', hint: '37,0'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _field(_pulse, 'Pouls /min', hint: '72')),
                  const SizedBox(width: 12),
                  Expanded(child: _field(_gly, 'Glycémie g/L', hint: '1,10')),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _acts,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Actes réalisés',
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Décrivez les actes réalisés.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _obs,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Observations et suite à donner',
                  alignLabelWithHint: true,
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
                child: const Text('Terminer le soin'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {String? hint}) =>
      TextFormField(
        controller: c,
        keyboardType: TextInputType.text,
        decoration: InputDecoration(labelText: label, hintText: hint),
      );
}
