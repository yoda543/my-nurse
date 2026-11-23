import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../widgets.dart';
import 'booking_detail.dart';

/// Carnet de santé d'une personne : informations médicales et comptes rendus.
class HealthRecordScreen extends StatefulWidget {
  const HealthRecordScreen({super.key, required this.patient});

  final Patient patient;

  @override
  State<HealthRecordScreen> createState() => _HealthRecordScreenState();
}

class _HealthRecordScreenState extends State<HealthRecordScreen> {
  late final _allergies = TextEditingController(text: widget.patient.allergies);
  late final _history = TextEditingController(text: widget.patient.history);
  late final _treatments = TextEditingController(
    text: widget.patient.treatments,
  );
  bool _dirty = false;

  @override
  void dispose() {
    _allergies.dispose();
    _history.dispose();
    _treatments.dispose();
    super.dispose();
  }

  void _save() {
    AppScope.of(context).updateHealthRecord(
      widget.patient,
      allergies: _allergies.text.trim(),
      history: _history.text.trim(),
      treatments: _treatments.text.trim(),
    );
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Carnet enregistré.')));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.patient;
    final history = AppScope.of(context).careHistory(p);
    final age = p.birthYear == null ? null : DateTime.now().year - p.birthYear!;
    return Scaffold(
      appBar: AppBar(title: Text('Carnet de ${p.name.split(' ').first}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text(
            p.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          Text(
            [p.relation, if (age != null) '$age ans'].join(' · '),
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          _field(_allergies, 'Allergies', 'Pénicilline, latex…'),
          const SizedBox(height: 12),
          _field(_history, 'Antécédents', 'Diabète, hypertension, opérations…'),
          const SizedBox(height: 12),
          _field(
            _treatments,
            'Traitements en cours',
            'Médicament, dose, horaire',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _dirty ? _save : null,
            child: const Text('Enregistrer'),
          ),
          const SizedBox(height: 12),
          const InfoBanner(
            icon: Icons.lock_outline,
            text:
                'Seul le soignant d’un soin confirmé voit ces informations, '
                'et seulement le temps du suivi.',
          ),
          const SizedBox(height: 24),
          const Text(
            'Comptes rendus de soins',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (history.isEmpty)
            const Text(
              'Les comptes rendus des soignants apparaîtront ici après '
              'chaque soin.',
              style: TextStyle(color: Colors.black54),
            ),
          for (final b in history) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text(
                '${b.service.name} · ${b.pro.name}\n'
                '${dateTimeLabel(b.scheduledAt)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            CareLogCard(log: b.careLog!),
          ],
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint) =>
      TextField(
        controller: c,
        minLines: 1,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) {
          if (!_dirty) setState(() => _dirty = true);
        },
        decoration: InputDecoration(labelText: label, hintText: hint),
      );
}

/// Onglet « Carnet » : une entrée par personne soignée.
class HealthRecordsTab extends StatelessWidget {
  const HealthRecordsTab({super.key, required this.onAddPatient});

  final VoidCallback onAddPatient;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionTitle('Carnet de santé'),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            'Antécédents, traitements et comptes rendus de chaque soin, pour '
            'vous et vos proches.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Column(
              children: [
                for (final p in app.patients)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(p.name),
                    subtitle: Text(
                      '${p.relation} · ${app.careHistory(p).length} compte'
                      '${app.careHistory(p).length > 1 ? 's' : ''} rendu'
                      '${app.careHistory(p).length > 1 ? 's' : ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HealthRecordScreen(patient: p),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: OutlinedButton.icon(
            onPressed: onAddPatient,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un proche'),
          ),
        ),
      ],
    );
  }
}
