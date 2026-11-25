import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../backend/remote.dart' show PickedFile;
import '../../format.dart';
import '../../models.dart';
import '../../widgets.dart';

/// Inscription d'un professionnel : profil, soins et prix, pièces, charte.
/// Le compte n'est visible des patients qu'après vérification par MyNurse.
class ProOnboardingScreen extends StatefulWidget {
  const ProOnboardingScreen({super.key});

  @override
  State<ProOnboardingScreen> createState() => _ProOnboardingScreenState();
}

class _ProOnboardingScreenState extends State<ProOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _years = TextEditingController();
  final _order = TextEditingController();
  final _bio = TextEditingController();
  final _referral = TextEditingController();
  ProType _type = ProType.infirmier;
  final Set<String> _communes = {};
  final Map<String, TextEditingController> _prices = {};
  final Set<String> _selected = {};
  final Set<DocType> _docs = {};

  /// Fichiers choisis (base en ligne) : la pièce est envoyée à l'inscription.
  final Map<DocType, PickedFile> _files = {};
  bool _sending = false;

  static const _maxFileBytes = 5 * 1024 * 1024;

  Future<void> _toggleDoc(AppState app, DocType d) async {
    if (_docs.contains(d)) {
      setState(() {
        _docs.remove(d);
        _files.remove(d);
      });
      return;
    }
    if (!app.isRemote) {
      setState(() => _docs.add(d));
      return;
    }
    final picked = await FilePicker.pickFiles(
      dialogTitle: d.label,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (picked.isEmpty || !mounted) return;
    final file = picked.first;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > _maxFileBytes) {
      setState(
        () => _error = '${d.label} : fichier trop lourd (5 Mo maximum).',
      );
      return;
    }
    setState(() {
      _files[d] = (name: file.name, bytes: bytes);
      _docs.add(d);
      _error = null;
    });
  }

  bool _night = false;
  bool _charter = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _name,
      _years,
      _order,
      _bio,
      _referral,
      ..._prices.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _priceFor(CareService s) => _prices.putIfAbsent(
    s.id,
    () => TextEditingController(
      text: '${((s.minPrice + s.maxPrice) / 2 / 500).round() * 500}',
    ),
  );

  Future<void> _submit(AppState app) async {
    if (_sending) return;
    setState(() => _error = null);
    final formOk = _formKey.currentState!.validate();
    final services = app.services.where((s) => s.proType == _type);
    final chosen = services.where((s) => _selected.contains(s.id));
    final missing = requiredDocs(_type).where((d) => !_docs.contains(d));
    final problem = !formOk
        ? 'Corrigez les champs en rouge.'
        : _communes.isEmpty
        ? 'Choisissez au moins une commune.'
        : chosen.isEmpty
        ? 'Choisissez au moins un soin.'
        : missing.isNotEmpty
        ? 'Il manque : ${missing.map((d) => d.label).join(', ')}.'
        : !_charter
        ? 'Acceptez la charte MyNurse pour continuer.'
        : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (_referral.text.trim().isNotEmpty &&
        app.findReferrer(_referral.text) == null) {
      setState(
        () => _error =
            'Code de parrainage inconnu. Vérifiez-le ou laissez le champ vide.',
      );
      return;
    }
    setState(() => _sending = true);
    await runAction(
      context,
      () => app.registerPro(
        name: _name.text.trim(),
        phone: app.sessionPhone,
        type: _type,
        communes: communes.where(_communes.contains).toList(),
        prices: {for (final s in chosen) s.id: int.parse(_priceFor(s).text)},
        yearsExperience: int.parse(_years.text),
        bio: _bio.text.trim(),
        orderNumber: _order.text.trim(),
        nightAvailable: _night,
        documents: requiredDocs(_type).toSet(),
        referralCode: _referral.text,
        files: _files,
      ),
    );
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final services = app.services.where((s) => s.proType == _type).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Créer mon compte soignant'),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            onPressed: app.logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const InfoBanner(
                icon: Icons.verified_outlined,
                text:
                    'Votre profil sera visible des patients après contrôle '
                    "de vos pièces et un court entretien avec l'équipe MyNurse.",
              ),
              _heading('Votre profil'),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nom et prénom'),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Indiquez votre nom et votre prénom.'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ProType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Profession'),
                items: [
                  for (final t in ProType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (t) => setState(() {
                  _type = t!;
                  _selected.clear();
                  _docs.clear();
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _years,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: "Années d'expérience",
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return (n == null || n > 60) ? 'Indiquez un nombre.' : null;
                },
              ),
              if (_type.hasOrder) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _order,
                  decoration: const InputDecoration(
                    labelText: "Numéro d'inscription à l'Ordre",
                  ),
                  validator: (v) => (v == null || v.trim().length < 4)
                      ? "Indiquez votre numéro d'inscription."
                      : null,
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _bio,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Présentation (vue par les patients)',
                  hintText: 'Votre parcours, vos spécialités…',
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v == null || v.trim().length < 20)
                    ? 'Écrivez au moins une phrase (20 caractères).'
                    : null,
              ),
              _heading('Où intervenez-vous ?'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in communes)
                    FilterChip(
                      label: Text(c),
                      selected: _communes.contains(c),
                      onSelected: (on) => setState(
                        () => on ? _communes.add(c) : _communes.remove(c),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _night,
                onChanged: (v) => setState(() => _night = v),
                title: const Text('Disponible la nuit (21 h – 6 h)'),
                subtitle: const Text('Les soins de nuit sont majorés de 50 %.'),
              ),
              _heading('Vos soins et vos prix'),
              Text(
                'Fixez votre prix dans la fourchette recommandée par MyNurse. '
                'Une commission de ${(commissionRate * 100).round()} % est prélevée sur chaque soin.',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 8),
              for (final s in services)
                _ServicePriceTile(
                  service: s,
                  selected: _selected.contains(s.id),
                  controller: _priceFor(s),
                  onSelected: (on) => setState(
                    () => on ? _selected.add(s.id) : _selected.remove(s.id),
                  ),
                ),
              _heading('Vos pièces justificatives'),
              const Text(
                'Photo ou scan lisible de chaque document.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final d in requiredDocs(_type))
                      ListTile(
                        leading: Icon(
                          _docs.contains(d)
                              ? Icons.check_circle
                              : Icons.upload_file_outlined,
                          color: _docs.contains(d)
                              ? Theme.of(context).colorScheme.primary
                              : Colors.black54,
                        ),
                        title: Text(d.label),
                        subtitle: Text(
                          _files[d]?.name ??
                              (_docs.contains(d) ? 'Ajouté' : 'À ajouter'),
                        ),
                        trailing: TextButton(
                          onPressed: () => _toggleDoc(app, d),
                          child: Text(
                            _docs.contains(d) ? 'Retirer' : 'Ajouter',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                app.isRemote
                    ? 'Photo ou PDF, 5 Mo maximum. Seule l’équipe MyNurse les voit.'
                    : 'Mode démo : aucun fichier n’est envoyé.',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _referral,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Code de parrainage d’un collègue (facultatif)',
                  hintText: 'AYA-1',
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _charter,
                onChanged: (v) => setState(() => _charter = v!),
                title: const Text("J'accepte la charte MyNurse"),
                subtitle: const Text(
                  'Ponctualité, confidentialité des patients, paiement '
                  "uniquement via l'app, responsabilité civile pro à jour.",
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _sending ? null : () => _submit(app),
                child: const Text('Envoyer mon dossier'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
  );
}

class _ServicePriceTile extends StatelessWidget {
  const _ServicePriceTile({
    required this.service,
    required this.selected,
    required this.controller,
    required this.onSelected,
  });

  final CareService service;
  final bool selected;
  final TextEditingController controller;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final s = service;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                contentPadding: const EdgeInsets.only(left: 4),
                controlAffinity: ListTileControlAffinity.leading,
                value: selected,
                onChanged: (v) => onSelected(v!),
                title: Text(s.name),
                subtitle: Text(
                  'Fourchette : ${fcfa(s.minPrice)} – ${fcfa(s.maxPrice)}',
                ),
              ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: TextFormField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Votre prix',
                      suffixText: 'FCFA',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < s.minPrice || n > s.maxPrice) {
                        return 'Entre ${fcfa(s.minPrice)} et ${fcfa(s.maxPrice)}.';
                      }
                      return null;
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Écran affiché tant que le compte n'est pas vérifié.
