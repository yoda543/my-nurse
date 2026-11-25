import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../backend/remote.dart' show PickedFile;
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// Vérification du soignant : où en est son dossier, chaque pièce et sa
/// validité, et ce qu'il doit faire. Sert d'écran d'accueil tant qu'il n'est
/// pas vérifié (il ne reçoit alors aucune demande), et de rubrique du profil
/// ensuite.
class VerificationScreen extends StatelessWidget {
  const VerificationScreen({super.key, this.gate = false, this.picker});

  /// true : écran bloquant (compte pas encore actif).
  final bool gate;

  /// Choix d'un fichier (remplaçable dans les tests).
  final Future<PickedFile?> Function()? picker;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.currentPro!;
    final status = p.statusAt(app.now);
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        if (gate)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Bonjour ${p.name.replaceFirst('Dr ', '').split(' ').first}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Se déconnecter',
                onPressed: app.logout,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
        const SizedBox(height: 8),
        _StatusCard(status: status, reason: p.rejectionReason),
        const SizedBox(height: 16),
        _Steps(status: status),
        const BlockTitle('Pièces du dossier'),
        Text(
          'Exigées pour ${p.type.label.toLowerCase()}. Indiquez la date de '
          'fin de validité quand il y en a une : MyNurse vous prévient 30 '
          'jours avant.',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 8),
        for (final d in requiredDocs(p.type))
          _DocTile(pro: p, doc: d, picker: picker),
        const BlockTitle('Ce que votre profession permet'),
        _ScopeCard(pro: p),
        if (!p.activeAt(app.now)) ...[
          const SizedBox(height: 16),
          const InfoBanner(
            icon: Icons.block,
            warning: true,
            text:
                'Tant que votre compte n’est pas vérifié, vous n’apparaissez '
                'pas dans les recherches et ne recevez aucune demande de soin.',
          ),
        ],
      ],
    );
    if (gate) {
      return Scaffold(
        body: SafeArea(child: ContentWidth(child: body)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Vérification')),
      body: ContentWidth(child: body),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.reason});

  final VerificationStatus status;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final (icon, bg, fg) = switch (status) {
      VerificationStatus.verified => (
        Icons.verified,
        const Color(0xFFD5EDE9),
        brandGreen,
      ),
      VerificationStatus.pending || VerificationStatus.underReview => (
        Icons.hourglass_top_rounded,
        const Color(0xFFE6EDFC),
        const Color(0xFF1E40AF),
      ),
      VerificationStatus.incomplete || VerificationStatus.expired => (
        Icons.upload_file,
        const Color(0xFFFFF1D6),
        const Color(0xFF6B4500),
      ),
      VerificationStatus.suspended || VerificationStatus.rejected => (
        Icons.report_outlined,
        const Color(0xFFFBE0DA),
        const Color(0xFF9C2B12),
      ),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 4),
                Text(status.help, style: TextStyle(color: fg, height: 1.35)),
                if (reason.isNotEmpty &&
                    (status == VerificationStatus.rejected ||
                        status == VerificationStatus.suspended)) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Motif : $reason',
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Les étapes du dossier, de l'inscription à la vérification.
class _Steps extends StatelessWidget {
  const _Steps({required this.status});

  final VerificationStatus status;

  @override
  Widget build(BuildContext context) {
    const labels = ['Pièces déposées', 'Dossier complet', 'Examen', 'Vérifié'];
    final reached = switch (status) {
      VerificationStatus.incomplete => 1,
      VerificationStatus.rejected => 1,
      VerificationStatus.pending => 2,
      VerificationStatus.underReview => 3,
      VerificationStatus.verified ||
      VerificationStatus.expired ||
      VerificationStatus.suspended => 4,
    };
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < labels.length - 1 ? 6 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: i < reached ? brandGreen : const Color(0xFFD9D3C5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 12,
                      color: i < reached ? brandInk : Colors.black45,
                      fontWeight: i == reached - 1 ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.pro, required this.doc, this.picker});

  final Pro pro;
  final DocType doc;
  final Future<PickedFile?> Function()? picker;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final has = pro.documents.contains(doc);
    final exp = pro.documentExpiry[doc];
    final expired = pro.expiredDocs(app.now).contains(doc);
    final soon = pro.expiringDocs(app.now).contains(doc);
    final (icon, color, state) = !has
        ? (Icons.radio_button_unchecked, Colors.black38, 'À fournir')
        : expired
        ? (Icons.error_outline, const Color(0xFF9C2B12), 'Expirée')
        : soon
        ? (Icons.schedule, const Color(0xFF8A5A00), 'Expire bientôt')
        : (Icons.check_circle, brandGreen, 'Fournie');
    final action = !has || expired || soon;
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(doc.label),
        subtitle: Text(
          [
            state,
            if (exp != null)
              'valable jusqu’au ${dateTimeLabel(exp).split(' à ').first}',
          ].join(' · '),
          style: TextStyle(color: color == Colors.black38 ? null : color),
        ),
        trailing: action
            ? TextButton(
                onPressed: () => _add(context),
                child: Text(has ? 'Renouveler' : 'Ajouter'),
              )
            : null,
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final app = AppScope.of(context);
    PickedFile? file;
    if (app.isRemote) {
      file =
          await (picker ??
              () async {
                final picked = await FilePicker.pickFiles(
                  dialogTitle: doc.label,
                  type: FileType.custom,
                  allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
                );
                if (picked.isEmpty) return null;
                return (
                  name: picked.first.name,
                  bytes: await picked.first.readAsBytes(),
                );
              })();
      if (file == null || !context.mounted) return;
    }
    final expiry = await showDatePicker(
      context: context,
      helpText: 'Fin de validité (Annuler : sans date de fin)',
      initialDate: app.now.add(const Duration(days: 365)),
      firstDate: app.now.add(const Duration(days: 1)),
      lastDate: app.now.add(const Duration(days: 3650)),
    );
    if (!context.mounted) return;
    final ok = await runAction(
      context,
      () => app.submitProDocuments({
        doc: expiry,
      }, files: file == null ? const {} : {doc: file}),
    );
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${doc.label} enregistrée.')));
    }
  }
}

class _ScopeCard extends StatelessWidget {
  const _ScopeCard({required this.pro});

  final Pro pro;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = pro.scope;
    Widget line(bool ok, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check : Icons.close,
            size: 18,
            color: ok ? brandGreen : Colors.black38,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actes : ${app.servicesAllowedFor(pro).map((x) => x.name.split(' (').first).join(', ')}.',
            ),
            const SizedBox(height: 8),
            line(
              true,
              'Constantes : ${s.vitals.map((v) => v.label.toLowerCase()).join(', ')}',
            ),
            line(
              s.fullRecord,
              s.fullRecord
                  ? 'Carnet complet du patient pendant un soin confirmé'
                  : 'Carnet limité à l’essentiel (allergies, traitements)',
            ),
            line(s.documents, 'Ordonnances et résultats du patient'),
          ],
        ),
      ),
    );
  }
}
