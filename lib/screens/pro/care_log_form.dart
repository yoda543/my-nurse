import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../intelligence/assistant/pro_tools.dart';
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
    final b = widget.booking;
    final s = b.arrivedAt ?? b.scheduledAt;
    _arrival = TimeOfDay.fromDateTime(s);
    _departure = TimeOfDay.fromDateTime(s.add(const Duration(minutes: 30)));
    // Reprend les mesures et notes déjà saisies pendant la visite.
    String last(VitalKind k) {
      final v = b.vitals.where((v) => v.kind == k).lastOrNull;
      if (v == null) return '';
      return k == VitalKind.bloodPressure
          ? '${v.value.round()}/${(v.value2 ?? 0).round()}'
          : v.display.split(' ').first;
    }

    _bp.text = last(VitalKind.bloodPressure);
    _temp.text = last(VitalKind.temperature);
    _pulse.text = last(VitalKind.heartRate);
    _gly.text = last(VitalKind.glycemia);
    _obs.text = [
      for (final j in b.journal)
        if (j.kind == JournalKind.note) j.text,
    ].join('\n');
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

  bool _sending = false;
  List<String> _review = const [];

  /// Range les notes libres dans les rubriques. Rien n'est inventé ni
  /// envoyé hors du téléphone ; le soignant relit et corrige.
  Future<void> _structure() async {
    final ctrl = TextEditingController(
      text: [
        _acts.text,
        _obs.text,
      ].where((t) => t.trim().isNotEmpty).join('\n'),
    );
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vos notes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Écrivez comme vous parlez : actes, ce que vous avez observé, la '
              'suite. Ex. « TA 13/8. Pansement refait. Plaie propre. Revoir dans '
              '2 jours. » Le texte reste sur votre téléphone.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Mettre en forme'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (notes == null || !mounted) return;
    final d = structureCareNotes(notes, vitals: widget.booking.vitals);
    setState(() {
      if (d.bloodPressure.isNotEmpty) _bp.text = d.bloodPressure;
      if (d.temperature.isNotEmpty) _temp.text = d.temperature;
      if (d.pulse.isNotEmpty) _pulse.text = d.pulse;
      if (d.glycemia.isNotEmpty) _gly.text = d.glycemia;
      _acts.text = d.acts;
      _obs.text = [
        d.observations,
        if (d.followUp.isNotEmpty) 'Suite à donner :\n${d.followUp}',
      ].where((t) => t.isNotEmpty).join('\n');
      _review = d.toReview;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Brouillon prêt : relisez et corrigez avant d’envoyer.'),
      ),
    );
  }

  Future<void> _submit() async {
    if (_sending) return;
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
    setState(() => _sending = true);
    try {
      await AppScope.of(context).submitCareLog(
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
    } catch (_) {
      setState(
        () => _error =
            'Connexion impossible. Vérifiez votre réseau et réessayez.',
      );
      return;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) return;
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
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _structure,
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: const Text('Mettre en forme mes notes'),
              ),
              if (_review.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1D6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'À relire : ces phrases ressemblent à un diagnostic ou à '
                    'une prescription. Vérifiez qu’elles relèvent de votre '
                    'rôle.\n• ${_review.join('\n• ')}',
                    style: const TextStyle(color: Color(0xFF6B4500)),
                  ),
                ),
              ],
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
