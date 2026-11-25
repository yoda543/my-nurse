import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../backend/remote.dart' show PickedFile;
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// Choisit un fichier sur l'appareil (remplaçable dans les tests).
typedef FilePickerFn = Future<PickedFile?> Function();

Future<PickedFile?> pickMedicalFile() async {
  final picked = await FilePicker.pickFiles(
    dialogTitle: 'Ordonnance, résultat ou compte rendu',
    type: FileType.custom,
    allowedExtensions: PatientFeatures.docExtensions,
  );
  if (picked.isEmpty) return null;
  final f = picked.first;
  return (name: f.name, bytes: await f.readAsBytes());
}

/// Documents du carnet : liste, ajout, consultation.
class DocumentsSection extends StatelessWidget {
  const DocumentsSection({super.key, required this.patient, this.picker});

  final Patient patient;
  final FilePickerFn? picker;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = patient;
    final canAdd = app.can(p, FamilyPermission.manageRecords);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlockTitle(
          'Ordonnances et documents',
          action: canAdd
              ? TextButton.icon(
                  onPressed: () => showAddDocumentSheet(
                    context,
                    p,
                    picker: picker ?? pickMedicalFile,
                  ),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Ajouter'),
                )
              : null,
        ),
        if (p.documents.isEmpty)
          Text(
            canAdd
                ? 'Photographiez une ordonnance ou un résultat : le soignant '
                      'la verra au moment du soin.'
                : 'Aucun document.',
            style: const TextStyle(color: Colors.black54),
          ),
        for (final d in p.documents)
          Card(
            child: ListTile(
              leading: Icon(
                d.kind == MedicalDocKind.prescription
                    ? Icons.receipt_long_outlined
                    : d.isImage
                    ? Icons.image_outlined
                    : Icons.picture_as_pdf_outlined,
                color: brandGreen,
              ),
              title: Text(d.title),
              subtitle: Text(
                '${d.kind.label} · ajouté par ${d.addedBy} le '
                '${dateTimeLabel(d.addedAt)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DocumentScreen(patient: p, document: d),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        const Text(
          'Stockés dans un espace privé. Seuls vous, les proches autorisés et '
          'le soignant d’un soin en cours peuvent les ouvrir.',
          style: TextStyle(color: Colors.black54, fontSize: 13),
        ),
      ],
    );
  }
}

Future<void> showAddDocumentSheet(
  BuildContext context,
  Patient patient, {
  required FilePickerFn picker,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  builder: (_) => _AddDocumentSheet(patient: patient, picker: picker),
);

class _AddDocumentSheet extends StatefulWidget {
  const _AddDocumentSheet({required this.patient, required this.picker});

  final Patient patient;
  final FilePickerFn picker;

  @override
  State<_AddDocumentSheet> createState() => _AddDocumentSheetState();
}

class _AddDocumentSheetState extends State<_AddDocumentSheet> {
  MedicalDocKind _kind = MedicalDocKind.prescription;
  final _title = TextEditingController();
  PickedFile? _file;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final f = await widget.picker();
    if (!mounted || f == null) return;
    setState(() {
      _file = f;
      _error = null;
    });
  }

  Future<void> _send() async {
    final app = AppScope.of(context);
    final navigator = Navigator.of(context);
    await app.addDocument(
      widget.patient,
      kind: _kind,
      title: _title.text,
      file: _file!,
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ajouter au carnet de ${widget.patient.name.split(' ').first}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in MedicalDocKind.values)
                  ChoiceChip(
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Titre (facultatif)',
                hintText: '${_kind.label} du Dr …',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pick,
              icon: Icon(f == null ? Icons.attach_file : Icons.check_circle),
              label: Text(
                f == null
                    ? 'Choisir une photo ou un PDF'
                    : '${f.name} (${(f.bytes.length / 1024).ceil()} Ko)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Photo (JPG, PNG) ou PDF, 10 Mo maximum. Sur une connexion '
              'lente, l’envoi peut prendre une minute : gardez l’écran ouvert.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            ActionButton(
              label: 'Envoyer dans le carnet',
              success: 'Document ajouté au carnet.',
              onPressed: f == null ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// Un document : aperçu (photo), informations, retrait.
class DocumentScreen extends StatefulWidget {
  const DocumentScreen({
    super.key,
    required this.patient,
    required this.document,
  });

  final Patient patient;
  final MedicalDocument document;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  late Future<dynamic> _bytes;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _bytes = AppScope.of(context).documentBytes(widget.document);
  }

  void _retry() => setState(
    () => _bytes = AppScope.of(context).documentBytes(widget.document),
  );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final d = widget.document;
    return Scaffold(
      appBar: AppBar(title: Text(d.kind.label)),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(
              d.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(
              'Ajouté par ${d.addedBy} le ${dateTimeLabel(d.addedAt)}'
              '${d.documentDate == null ? '' : ' · daté du ${dateTimeLabel(d.documentDate!).split(' à ').first}'}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            FutureBuilder(
              future: _bytes,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return Column(
                    children: [
                      const InfoBanner(
                        icon: Icons.wifi_off_rounded,
                        warning: true,
                        text:
                            'Document impossible à télécharger pour le moment. '
                            'Vérifiez votre connexion.',
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _retry,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  );
                }
                final bytes = snap.data;
                if (bytes != null && d.isImage) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  );
                }
                return InfoBanner(
                  icon: Icons.picture_as_pdf_outlined,
                  text:
                      '${d.fileName} est enregistré dans le carnet. Montrez-le '
                      'au soignant depuis cet écran.',
                );
              },
            ),
            const SizedBox(height: 24),
            if (app.can(widget.patient, FamilyPermission.manageRecords))
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Retirer ce document du carnet ?'),
                      content: const Text(
                        'Il n’apparaîtra plus dans le carnet. Une copie reste '
                        'conservée par MyNurse pour la traçabilité des soins.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Garder'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Retirer'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true || !context.mounted) return;
                  final done = await runAction(
                    context,
                    () => app.removeDocument(widget.patient, d),
                  );
                  if (done && context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Retirer du carnet'),
              ),
          ],
        ),
      ),
    );
  }
}
