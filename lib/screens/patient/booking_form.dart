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

  /// Position GPS du lieu du soin, quand l'adresse vient de la localisation.
  GeoPoint? _point;
  bool _locating = false;
  String? _locationNote;
  Frequency _frequency = Frequency.daily;
  int _sessions = 5;

  @override
  void initState() {
    super.initState();
    final t = DateTime.now().add(const Duration(days: 1));
    _when = DateTime(t.year, t.month, t.day, 9);
    // L'adresse sort directement si la position est déjà connue.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final place = AppScope.of(context).place;
      if (place != null && _address.text.isEmpty) _fill(place);
    });
  }

  void _fill(DetectedPlace place) {
    setState(() {
      _address.text = place.address;
      _point = place.point;
      _locationNote = place.simulated
          ? 'Position de démonstration : la vraie position est lue sur le '
                'téléphone.'
          : 'Position GPS partagée avec le soignant. Ajoutez un repère '
                '(étage, portail).';
    });
  }

  /// Remplit l'adresse à partir de la position du téléphone.
  Future<void> _locate() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _locationNote = null;
    });
    final app = AppScope.of(context);
    final place = await app.detectPlace();
    if (!mounted) return;
    setState(() => _locating = false);
    if (place != null) {
      _fill(place);
    } else {
      setState(() => _locationNote = app.locationError);
    }
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

  bool _sending = false;

  Future<void> _submit() async {
    if (_sending) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final app = AppScope.of(context);
    setState(() => _sending = true);
    try {
      if (_recurring) {
        await app.bookContract(
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
          location: _point,
        );
      } else {
        await app.book(
          service: widget.service,
          pro: widget.pro,
          commune: app.commune,
          address: _address.text.trim(),
          scheduledAt: _when,
          hasPrescription: _prescription,
          note: _note.text.trim(),
          patient: _patient ?? app.patients.first,
          location: _point,
        );
      }
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
                'avec ${widget.pro.name} · ${app.commune}'
                '${app.place?.commune == app.commune ? ' (votre position)' : ''}',
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
                onTap: () {
                  if (_address.text.isEmpty) _locate();
                },
                onChanged: (v) {
                  if (v.isEmpty) setState(() => _point = null);
                },
                decoration: InputDecoration(
                  labelText: 'Adresse et repères',
                  hintText: _locating
                      ? 'Localisation en cours…'
                      : 'Touchez pour utiliser votre position',
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.place_outlined),
                  suffixIcon: _locating
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Utiliser ma position',
                          onPressed: _locate,
                          icon: const Icon(Icons.my_location),
                        ),
                  helperText: _locationNote,
                  helperMaxLines: 3,
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
                  // Libellé court : la version longue était coupée à 360 px.
                  labelText: 'Précisions (facultatif)',
                  hintText: 'Ex. : code du portail, étage, chien…',
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
                onPressed: _sending ? null : _submit,
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
