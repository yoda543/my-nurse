import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../widgets.dart';

/// Disponibilités : jours travaillés et horaires. Sans aucune plage, le
/// soignant reste réservable à toute heure (comme avant).
class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  /// Par jour (1-7) : plage ou null (jour non travaillé).
  final Map<int, (int, int)?> _days = {};
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    final p = AppScope.of(context).currentPro!;
    for (var d = 1; d <= 7; d++) {
      final r = p.availability.where((r) => r.weekday == d).firstOrNull;
      _days[d] = r == null ? null : (r.startMinute, r.endMinute);
    }
    if (p.availability.isEmpty) {
      // Proposition de départ : du lundi au samedi, 8 h – 18 h.
      for (var d = 1; d <= 6; d++) {
        _days[d] = (8 * 60, 18 * 60);
      }
    }
  }

  Future<void> _pick(int day, bool start) async {
    final (s, e) = _days[day]!;
    final m = start ? s : e;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (t == null) return;
    final v = t.hour * 60 + t.minute;
    setState(() => _days[day] = start ? (v, e) : (s, v));
  }

  String _t(int m) =>
      '${m ~/ 60} h${m % 60 == 0 ? '' : (m % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes disponibilités')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            const Text(
              'Les patients ne peuvent réserver que sur ces plages. Les soins '
              'déjà confirmés ne changent pas.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            for (var d = 1; d <= 7; d++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Switch(
                        value: _days[d] != null,
                        onChanged: (on) => setState(
                          () => _days[d] = on ? (8 * 60, 18 * 60) : null,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          weekdayNames[d - 1],
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_days[d] case (final s, final e)) ...[
                        TextButton(
                          onPressed: () => _pick(d, true),
                          child: Text(_t(s)),
                        ),
                        const Text('–'),
                        TextButton(
                          onPressed: () => _pick(d, false),
                          child: Text(_t(e)),
                        ),
                      ] else
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Text(
                            'Repos',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            ActionButton(
              label: 'Enregistrer mes disponibilités',
              success: 'Disponibilités enregistrées.',
              onPressed: () => app.setAvailability([
                for (final e in _days.entries)
                  if (e.value case (final s, final end))
                    AvailabilityRule(e.key, s, end),
              ]),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                final ok = await runAction(
                  context,
                  () => app.setAvailability([]),
                );
                if (ok && context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Être réservable à toute heure'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soins et tarifs : uniquement les actes de sa profession, prix dans la
/// fourchette MyNurse.
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final Map<String, TextEditingController> _prices = {};
  final Set<String> _on = {};
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    final app = AppScope.of(context);
    final p = app.currentPro!;
    for (final s in app.servicesAllowedFor(p)) {
      final price = p.prices[s.id];
      if (price != null) _on.add(s.id);
      _prices[s.id] = TextEditingController(
        text: '${price ?? ((s.minPrice + s.maxPrice) / 2 / 500).round() * 500}',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.currentPro!;
    final allowed = app.servicesAllowedFor(p);
    return Scaffold(
      appBar: AppBar(title: const Text('Soins et tarifs')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(
              'Actes autorisés pour ${p.type.label.toLowerCase()}. Vous touchez '
              'le prix moins ${(commissionRate * 100).round()} % de commission.',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            for (final s in allowed)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Switch(
                            value: _on.contains(s.id),
                            onChanged: (v) => setState(
                              () => v ? _on.add(s.id) : _on.remove(s.id),
                            ),
                          ),
                        ],
                      ),
                      if (_on.contains(s.id)) ...[
                        TextField(
                          controller: _prices[s.id],
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Votre prix',
                            suffixText: 'FCFA',
                            helperText:
                                'Entre ${fcfa(s.minPrice)} et ${fcfa(s.maxPrice)} · '
                                'vous touchez ${fcfa(((int.tryParse(_prices[s.id]!.text) ?? 0) * (1 - commissionRate)).round())}',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            ActionButton(
              label: 'Enregistrer mes soins',
              success: 'Soins et tarifs mis à jour.',
              onPressed: () => app.updateProServices({
                for (final id in _on) id: int.tryParse(_prices[id]!.text) ?? 0,
              }),
            ),
          ],
        ),
      ),
    );
  }
}
