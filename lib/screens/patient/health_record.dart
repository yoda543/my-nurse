import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../widgets.dart';
import 'booking_detail.dart';
import 'documents.dart';

/// Carnet de santé d'une personne : l'essentiel pour un soignant (allergies,
/// traitements, antécédents), constantes, documents, comptes rendus.
/// Modifiable par le titulaire et les proches qui en ont le droit ; en
/// lecture seule sinon.
class HealthRecordScreen extends StatefulWidget {
  const HealthRecordScreen({super.key, required this.patient, this.picker});

  final Patient patient;

  /// Choix de fichier (remplaçable dans les tests).
  final FilePickerFn? picker;

  @override
  State<HealthRecordScreen> createState() => _HealthRecordScreenState();
}

class _HealthRecordScreenState extends State<HealthRecordScreen> {
  late final _allergies = TextEditingController(text: widget.patient.allergies);
  late final _history = TextEditingController(text: widget.patient.history);
  late final _treatments = TextEditingController(
    text: widget.patient.treatments,
  );
  late final _emergency = TextEditingController(
    text: widget.patient.emergencyContact,
  );
  late String _blood = widget.patient.bloodGroup;
  bool _dirty = false;

  static const _groups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  void dispose() {
    _allergies.dispose();
    _history.dispose();
    _treatments.dispose();
    _emergency.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await AppScope.of(context).updateHealthRecord(
      widget.patient,
      allergies: _allergies.text.trim(),
      history: _history.text.trim(),
      treatments: _treatments.text.trim(),
      bloodGroup: _blood,
      emergencyContact: _emergency.text.trim(),
    );
    if (mounted) setState(() => _dirty = false);
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = widget.patient;
    if (!app.can(p, FamilyPermission.viewRecords)) {
      return Scaffold(
        appBar: AppBar(title: Text('Carnet de ${p.name.split(' ').first}')),
        body: EmptyState(
          icon: Icons.lock_outline,
          text:
              'Vous n’avez pas accès à ce carnet. Demandez à '
              '${p.ownerName.isEmpty ? 'son titulaire' : p.ownerName} le droit '
              '« Lire le carnet de santé ».',
        ),
      );
    }
    final edit = app.can(p, FamilyPermission.manageRecords);
    final history = app.careHistory(p);
    final vitals = app.vitalsFor(p);
    final age = p.ageAt(app.now);
    return Scaffold(
      appBar: AppBar(title: Text('Carnet de ${p.name.split(' ').first}')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            const OfflineBanner(),
            Text(
              p.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            Text(
              [
                p.relation,
                if (age != null) '$age ans',
                if (p.bloodGroup.isNotEmpty) 'groupe ${p.bloodGroup}',
              ].join(' · '),
              style: const TextStyle(color: Colors.black54),
            ),
            if (p.allergies.isNotEmpty) ...[
              const SizedBox(height: 12),
              InfoBanner(
                icon: Icons.warning_amber_rounded,
                warning: true,
                text: 'Allergies : ${p.allergies}',
              ),
            ],
            if (!edit) ...[
              const SizedBox(height: 12),
              InfoBanner(
                icon: Icons.visibility_outlined,
                text:
                    'Lecture seule : ${p.ownerName.isEmpty ? 'le titulaire' : p.ownerName} '
                    'tient ce carnet à jour.',
              ),
            ],
            const BlockTitle('L’essentiel pour le soignant'),
            _field(_allergies, 'Allergies', 'Pénicilline, latex…', edit),
            const SizedBox(height: 12),
            _field(
              _treatments,
              'Traitements en cours',
              'Médicament, dose, horaire',
              edit,
            ),
            const SizedBox(height: 12),
            _field(
              _history,
              'Antécédents',
              'Diabète, hypertension, opérations…',
              edit,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _blood.isEmpty ? null : _blood,
                    decoration: const InputDecoration(labelText: 'Groupe'),
                    items: [
                      for (final g in _groups)
                        DropdownMenuItem(value: g, child: Text(g)),
                    ],
                    onChanged: edit
                        ? (g) {
                            _blood = g ?? '';
                            _changed();
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    _emergency,
                    'Personne à prévenir sur place',
                    'Nom et téléphone',
                    edit,
                  ),
                ),
              ],
            ),
            if (edit) ...[
              const SizedBox(height: 12),
              ActionButton(
                label: _dirty ? 'Enregistrer le carnet' : 'Carnet à jour',
                success: 'Carnet enregistré.',
                onPressed: _dirty ? _save : null,
              ),
            ],
            const SizedBox(height: 12),
            const InfoBanner(
              icon: Icons.lock_outline,
              text:
                  'Un soignant voit ces informations seulement à partir d’une '
                  'demande de soin, et jusqu’à 24 h après le soin.',
            ),
            const BlockTitle('Constantes relevées'),
            if (vitals.isEmpty)
              const Text(
                'Les constantes notées par les soignants (tension, '
                'température…) apparaîtront ici.',
                style: TextStyle(color: Colors.black54),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final v in vitals.take(8))
                      ListTile(
                        dense: true,
                        title: Text(v.label),
                        subtitle: Text(dateTimeLabel(v.at)),
                        trailing: Text(
                          v.value,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            DocumentsSection(patient: p, picker: widget.picker),
            const BlockTitle('Comptes rendus de soins'),
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
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    String hint,
    bool edit,
  ) => TextField(
    controller: c,
    readOnly: !edit,
    minLines: 1,
    maxLines: 3,
    textCapitalization: TextCapitalization.sentences,
    onChanged: (_) => _changed(),
    decoration: InputDecoration(labelText: label, hintText: edit ? hint : null),
  );
}
