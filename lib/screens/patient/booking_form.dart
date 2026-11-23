import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import 'patient_form.dart';

class BookingFormScreen extends StatefulWidget {
  const BookingFormScreen({
    super.key,
    required this.pro,
    required this.service,
  });

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
  Patient? _patient;
  String? _error;
  bool _recurring = false;
  Frequency _frequency = Frequency.daily;
  int _sessions = 5;

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
      lastDate: now.add(maxAdvance),
    );
    if (d != null) {
      setState(
        () =>
            _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute),
      );
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (t != null) {
      setState(
        () => _when = DateTime(
          _when.year,
          _when.month,
          _when.day,
          t.hour,
          t.minute,
        ),
      );
    }
  }

  void _submit() {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final app = AppScope.of(context);
    try {
      if (_recurring) {
        app.bookContract(
          service: widget.service,
          pro: widget.pro,
          commune: app.commune,
          address: _address.text.trim(),
          firstAt: _when,
          frequency: _frequency,
          sessions: _sessions,
          hasPrescription: _prescription,
          note: _note.text.trim(),
          patient: _patient ?? app.patients.first,
        );
      } else {
        app.book(
          service: widget.service,
          pro: widget.pro,
          commune: app.commune,
          address: _address.text.trim(),
          scheduledAt: _when,
          hasPrescription: _prescription,
          note: _note.text.trim(),
          patient: _patient ?? app.patients.first,
        );
      }
    } on BusinessRuleError catch (e) {
      setState(() => _error = e.message);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => _ConfirmationScreen(
          pro: widget.pro,
          sessions: _recurring ? _sessions : 1,
        ),
      ),
      (r) => r.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final base = widget.pro.prices[widget.service.id]!;
    final dates = _recurring
        ? sessionDates(_when, _frequency, _sessions)
        : [_when];
    final total = dates.fold(0, (s, d) => s + careFee(base, d));
    final nightCount = dates.where(isNight).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Réserver')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.service.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'avec ${widget.pro.name} · ${app.commune}',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Soin ponctuel'),
                    icon: Icon(Icons.event_outlined),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Suivi régulier'),
                    icon: Icon(Icons.repeat),
                  ),
                ],
                selected: {_recurring},
                onSelectionChanged: (v) => setState(() {
                  _recurring = v.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Patient>(
                key: ValueKey(app.patients.length),
                initialValue: _patient ?? app.patients.first,
                decoration: const InputDecoration(
                  labelText: 'Pour qui est le soin ?',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                items: [
                  for (final p in app.patients)
                    DropdownMenuItem(
                      value: p,
                      child: Text('${p.name} (${p.relation})'),
                    ),
                ],
                onChanged: (p) => setState(() => _patient = p),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final p = await showPatientForm(context);
                    if (p != null) setState(() => _patient = p);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter un proche'),
                ),
              ),
              const SizedBox(height: 4),
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
              if (_recurring) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<Frequency>(
                  initialValue: _frequency,
                  decoration: const InputDecoration(labelText: 'Fréquence'),
                  items: [
                    for (final f in Frequency.values)
                      DropdownMenuItem(value: f, child: Text(f.label)),
                  ],
                  onChanged: (f) => setState(() => _frequency = f!),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Nombre de séances',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: 'Une séance de moins',
                      onPressed: _sessions > contractMinSessions
                          ? () => setState(() => _sessions--)
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '$_sessions',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: 'Une séance de plus',
                      onPressed: _sessions < contractMaxSessions
                          ? () => setState(() => _sessions++)
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Du ${dateTimeLabel(dates.first)} au '
                  '${dateTimeLabel(dates.last)}. Le même soignant pour toutes '
                  'les séances.',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
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
                      _row(
                        _recurring
                            ? '${dates.length} séances × ${fcfa(base)}'
                            : 'Prix du soin',
                        fcfa(base * dates.length),
                      ),
                      if (nightCount > 0)
                        _row(
                          'Majoration de nuit (50 %)',
                          fcfa(total - base * dates.length),
                        ),
                      const Divider(height: 20),
                      _row('Total', fcfa(total), bold: true),
                      const SizedBox(height: 8),
                      Text(
                        'Paiement après confirmation du soignant, dans les '
                        '${paymentWindow.inHours} h, avec votre solde MyNurse '
                        'ou en Mobile Money. Annulation gratuite jusqu’à '
                        '${freeCancellationWindow.inHours} h avant '
                        '${_recurring ? 'chaque séance' : 'le soin'}.',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
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
                child: Text(
                  _recurring
                      ? 'Demander le suivi (${dates.length} séances)'
                      : 'Envoyer la demande',
                ),
              ),
            ],
          ),
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
  const _ConfirmationScreen({required this.pro, required this.sessions});

  final Pro pro;
  final int sessions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const Icon(
                Icons.check_circle,
                size: 72,
                color: Color(0xFF0B7A6E),
              ),
              const SizedBox(height: 20),
              const Text(
                'Demande envoyée',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '${pro.name} a ${responseWindow.inHours} h pour confirmer '
                '${sessions > 1 ? 'votre suivi de $sessions séances' : 'votre demande'}. '
                'Vous la retrouvez dans « Mes soins ».',
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
