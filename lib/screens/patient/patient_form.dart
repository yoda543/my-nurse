import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../widgets.dart';

const _relations = ['Mère', 'Père', 'Conjoint(e)', 'Enfant', 'Autre proche'];

/// Ouvre le formulaire d'ajout d'un proche. Renvoie le proche créé, ou null.
Future<Patient?> showPatientForm(BuildContext context) {
  return showModalBottomSheet<Patient>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => const _PatientForm(),
  );
}

class _PatientForm extends StatefulWidget {
  const _PatientForm();

  @override
  State<_PatientForm> createState() => _PatientFormState();
}

class _PatientFormState extends State<_PatientForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _allergies = TextEditingController();
  final _birthYear = TextEditingController();
  String _relation = _relations.first;
  String? _commune;

  @override
  void dispose() {
    _name.dispose();
    _allergies.dispose();
    _birthYear.dispose();
    super.dispose();
  }

  Future<void> _submitAsync() async {
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final p = await AppScope.of(context).addPatient(
      name: _name.text.trim(),
      relation: _relation,
      allergies: _allergies.text.trim(),
      birthYear: int.tryParse(_birthYear.text.trim()),
      commune: _commune ?? '',
    );
    navigator.pop(p);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ajouter un proche',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nom et prénom'),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Indiquez le nom et le prénom.'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _relation,
              decoration: const InputDecoration(labelText: 'Lien avec vous'),
              items: [
                for (final r in _relations)
                  DropdownMenuItem(value: r, child: Text(r)),
              ],
              onChanged: (r) => setState(() => _relation = r!),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _commune,
                    decoration: const InputDecoration(
                      labelText: 'Commune où il vit',
                    ),
                    items: [
                      for (final c in communes)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (c) => setState(() => _commune = c),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 130,
                  child: TextFormField(
                    controller: _birthYear,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Né(e) en',
                      hintText: '1956',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final y = int.tryParse(v.trim());
                      return y == null || y < 1900 || y > DateTime.now().year
                          ? 'Année ?'
                          : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'La commune sert à proposer les soignants qui se déplacent '
              'chez lui, même si vous réservez depuis l’étranger.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _allergies,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Allergies connues (facultatif)',
                hintText: 'Pénicilline, latex…',
              ),
            ),
            const SizedBox(height: 20),
            ActionButton(label: 'Enregistrer', onPressed: _submitAsync),
          ],
        ),
      ),
    );
  }
}
