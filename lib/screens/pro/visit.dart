import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../patient/booking_detail.dart' show CareLogCard;
import 'care_log_form.dart';
import 'requests.dart';

/// Ouvre un soin : la demande s'il est en attente, la visite sinon.
void openBooking(BuildContext context, Booking b) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => b.status == BookingStatus.pending
        ? RequestDetailScreen(booking: b)
        : VisitScreen(booking: b),
  ),
);

/// Carte du prochain soin, avec le geste du moment en un seul bouton.
class NextVisitCard extends StatelessWidget {
  const NextVisitCard({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = booking;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openBooking(context, b),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${b.service.name.split(' (').first} · ${b.patientName}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _PayChip(booking: b),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${dateTimeLabel(b.scheduledAt)} · ${b.address}',
                style: const TextStyle(color: Colors.black54),
              ),
              if (b.patient.allergies.isNotEmpty && app.proCanSeeRecord(b)) ...[
                const SizedBox(height: 8),
                InfoBanner(
                  icon: Icons.warning_amber_rounded,
                  warning: true,
                  text: 'Allergies : ${b.patient.allergies}',
                ),
              ],
              const SizedBox(height: 12),
              VisitActions(booking: b),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayChip extends StatelessWidget {
  const _PayChip({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final paid = booking.paid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: paid ? const Color(0xFFE6EDFC) : const Color(0xFFFFF1D6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        booking.status == BookingStatus.done
            ? 'Terminé'
            : paid
            ? 'Payé'
            : 'Non payé',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: paid ? const Color(0xFF1E40AF) : const Color(0xFF8A5A00),
        ),
      ),
    );
  }
}

/// Le bon bouton selon l'étape : je pars → je suis arrivé → compte rendu.
class VisitActions extends StatelessWidget {
  const VisitActions({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = booking;
    if (b.status == BookingStatus.done) {
      return const Text('Soin terminé, compte rendu envoyé.');
    }
    if (!b.readyForCare) {
      return InfoBanner(
        icon: Icons.hourglass_top_rounded,
        warning: true,
        text:
            'Pas encore payé (limite ${timeLabel(b.paymentDeadline!)}). Ne vous '
            'déplacez pas avant la confirmation du paiement.',
      );
    }
    final departed = b.journal.any((j) => j.kind == JournalKind.onTheWay);
    final arrived = b.arrivedAt != null;
    final (label, icon, action) = !departed && !arrived
        ? ('Je pars', Icons.navigation_outlined, () => app.markOnTheWay(b))
        : !arrived
        ? (
            'Je suis arrivé(e)',
            Icons.where_to_vote_outlined,
            () => app.markArrived(b),
          )
        : (
            'Rédiger le compte rendu',
            Icons.edit_note,
            () async {
              if (!app.canLogCare(b)) {
                throw BusinessRuleError(
                  'Le compte rendu s’écrit à partir de '
                  '${timeLabel(b.careLogOpensAt)}.',
                );
              }
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CareLogFormScreen(booking: b),
                ),
              );
            },
          );
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ActionButton(
            label: label,
            icon: icon,
            onPressed: action,
            success: label == 'Je pars'
                ? 'La famille est prévenue que vous êtes en route.'
                : label.startsWith('Je suis')
                ? 'Arrivée notée. La famille est prévenue.'
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: 'Itinéraire',
            child: OutlinedButton(
              onPressed: () => launchUrl(
                b.location?.directionsUrl ??
                    Uri.https('www.google.com', '/maps/search/', {
                      'api': '1',
                      'query': '${b.address} ${b.commune} Abidjan',
                    }),
                mode: LaunchMode.externalApplication,
              ),
              child: const Icon(Icons.directions),
            ),
          ),
        ),
      ],
    );
  }
}

/// La visite : gestes, journal horodaté, constantes, compte rendu, incident.
class VisitScreen extends StatelessWidget {
  const VisitScreen({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = booking;
    final canWrite = b.readyForCare && b.pro == app.currentPro;
    return Scaffold(
      appBar: AppBar(title: Text(b.patientName)),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            const OfflineBanner(),
            Text(
              b.service.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(
              [
                dateTimeLabel(b.scheduledAt),
                if (b.sessionLabel != null) b.sessionLabel!,
                '${fcfa(b.proEarnings)} pour vous',
              ].join(' · '),
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Text('${b.commune} · ${b.address}'),
            if (b.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '« ${b.note} »',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 12),
            VisitActions(booking: b),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PatientChartScreen(booking: b),
                ),
              ),
              icon: const Icon(Icons.folder_shared_outlined),
              label: const Text('Dossier du patient (accès autorisé)'),
            ),
            BlockTitle(
              'Constantes',
              action: canWrite
                  ? TextButton.icon(
                      onPressed: () => showVitalSheet(context, b),
                      icon: const Icon(Icons.add),
                      label: const Text('Mesure'),
                    )
                  : null,
            ),
            if (b.vitals.isEmpty)
              Text(
                canWrite
                    ? 'Notez les mesures au fur et à mesure : elles vont dans le '
                          'carnet du patient et dans votre compte rendu.'
                    : 'Aucune mesure.',
                style: const TextStyle(color: Colors.black54),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in b.vitals)
                  Chip(
                    avatar: v.alert
                        ? const Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: Color(0xFF9C2B12),
                          )
                        : null,
                    label: Text('${v.kind.label} ${v.display}'),
                    backgroundColor: v.alert ? const Color(0xFFFBE0DA) : null,
                  ),
              ],
            ),
            BlockTitle(
              'Journal de visite',
              action: canWrite
                  ? TextButton.icon(
                      onPressed: () => _addNote(context, b),
                      icon: const Icon(Icons.add_comment_outlined),
                      label: const Text('Note'),
                    )
                  : null,
            ),
            if (b.journal.isEmpty)
              const Text(
                'Chaque étape est horodatée automatiquement (départ, '
                'arrivée). Ajoutez une note si besoin.',
                style: TextStyle(color: Colors.black54),
              ),
            for (final j in b.journal)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(switch (j.kind) {
                  JournalKind.onTheWay => Icons.navigation_outlined,
                  JournalKind.arrived => Icons.where_to_vote_outlined,
                  JournalKind.note => Icons.notes,
                  JournalKind.left => Icons.logout,
                }, color: brandGreen),
                title: Text(j.label),
                trailing: Text(timeLabel(j.at)),
              ),
            if (b.careLog != null) ...[
              const BlockTitle('Compte rendu envoyé'),
              CareLogCard(log: b.careLog!),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => showIncidentSheet(context, booking: b),
              icon: const Icon(Icons.report_gmailerrorred_outlined),
              label: const Text('Signaler un incident'),
            ),
            if (b.status == BookingStatus.accepted) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => cancelByProDialog(context, b),
                child: Text(
                  b.contract == null ? 'Annuler ce soin' : 'Annuler le suivi',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addNote(BuildContext context, Booking b) async {
    final ctrl = TextEditingController();
    final app = AppScope.of(context);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Note de visite'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Ex. : plaie propre, patiente fatiguée',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (text != null && context.mounted) {
      await runAction(context, () => app.addJournalNote(b, text));
    }
  }
}

/// Saisie d'une constante : seules celles autorisées par la profession.
Future<void> showVitalSheet(BuildContext context, Booking b) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _VitalSheet(booking: b),
    );

class _VitalSheet extends StatefulWidget {
  const _VitalSheet({required this.booking});

  final Booking booking;

  @override
  State<_VitalSheet> createState() => _VitalSheetState();
}

class _VitalSheetState extends State<_VitalSheet> {
  VitalKind? _kind;
  final _v1 = TextEditingController();
  final _v2 = TextEditingController();

  @override
  void dispose() {
    _v1.dispose();
    _v2.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final app = AppScope.of(context);
    final navigator = Navigator.of(context);
    final v = _num(_v1);
    if (v == null) {
      throw const BusinessRuleError('Indiquez la valeur mesurée.');
    }
    final r = await app.recordVital(
      widget.booking,
      _kind!,
      v,
      value2: _kind == VitalKind.bloodPressure ? _num(_v2) : null,
    );
    navigator.pop();
    if (r.alert && mounted) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${r.kind.label} ${r.display} : valeur à surveiller. Signalez-la '
            'dans le compte rendu.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final allowed = app.currentPro!.scope.vitals;
    final k = _kind;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Nouvelle mesure',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in VitalKind.values)
                if (allowed.contains(v))
                  ChoiceChip(
                    label: Text(v.label),
                    selected: k == v,
                    onSelected: (_) => setState(() => _kind = v),
                  ),
            ],
          ),
          if (allowed.length < VitalKind.values.length) ...[
            const SizedBox(height: 6),
            const Text(
              'Seules les mesures de votre champ d’exercice sont proposées.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
          if (k != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _v1,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: k == VitalKind.bloodPressure
                          ? 'Systolique'
                          : k.label,
                      suffixText: k.unit,
                    ),
                  ),
                ),
                if (k == VitalKind.bloodPressure) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _v2,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Diastolique',
                        suffixText: 'mmHg',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 16),
          ActionButton(
            label: 'Enregistrer la mesure',
            onPressed: k == null ? null : _save,
          ),
        ],
      ),
    );
  }
}

/// Dossier du patient, tel que l'autorisation en cours et la profession le
/// permettent. En ligne, chaque ouverture est enregistrée.
class PatientChartScreen extends StatefulWidget {
  const PatientChartScreen({super.key, required this.booking});

  final Booking booking;

  @override
  State<PatientChartScreen> createState() => _PatientChartScreenState();
}

class _PatientChartScreenState extends State<PatientChartScreen> {
  Future<PatientChart>? _chart;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chart ??= AppScope.of(context).patientChart(widget.booking);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = widget.booking;
    final history = app.proHistory(b.patient);
    return Scaffold(
      appBar: AppBar(title: const Text('Dossier du patient')),
      body: ContentWidth(
        child: FutureBuilder<PatientChart>(
          future: _chart,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              final e = snap.error;
              return EmptyState(
                icon: Icons.lock_outline,
                text: e is BusinessRuleError
                    ? e.message
                    : 'Dossier indisponible : vérifiez votre connexion.',
              );
            }
            final c = snap.data!;
            Widget field(String label, String value) => value.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                        Text(value, style: const TextStyle(fontSize: 16)),
                      ],
                    ),
                  );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Text(
                  c.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (c.age != null)
                  Text(
                    '${c.age} ans',
                    style: const TextStyle(color: Colors.black54),
                  ),
                const SizedBox(height: 10),
                InfoBanner(icon: Icons.lock_outline, text: c.scopeLabel),
                if (c.allergies.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  InfoBanner(
                    icon: Icons.warning_amber_rounded,
                    warning: true,
                    text: 'Allergies : ${c.allergies}',
                  ),
                ],
                const SizedBox(height: 14),
                field('Traitements en cours', c.treatments),
                field('Antécédents', c.history),
                field('Groupe sanguin', c.bloodGroup),
                field('Personne à prévenir sur place', c.emergencyContact),
                if (c.documents.isNotEmpty) ...[
                  const BlockTitle('Ordonnances et documents'),
                  for (final d in c.documents)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(d.title),
                      subtitle: Text(d.kind.label),
                    ),
                ],
                if (c.vitals.isNotEmpty) ...[
                  const BlockTitle('Dernières constantes'),
                  for (final v in c.vitals.take(8))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(v.kind.label),
                      subtitle: Text('${dateTimeLabel(v.at)} · ${v.by}'),
                      trailing: Text(
                        v.display,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: v.alert ? const Color(0xFF9C2B12) : null,
                        ),
                      ),
                    ),
                ],
                const BlockTitle('Mon suivi de ce patient'),
                if (history.where((h) => h.careLog != null).isEmpty)
                  const Text(
                    'Premier soin avec ce patient.',
                    style: TextStyle(color: Colors.black54),
                  ),
                for (final h in history.where((h) => h.careLog != null))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history),
                    title: Text(
                      '${h.service.name.split(' (').first} · ${dateTimeLabel(h.scheduledAt)}',
                    ),
                    subtitle: Text(h.careLog!.acts),
                  ),
                if (c.reports.isNotEmpty) ...[
                  const BlockTitle('Comptes rendus des soignants'),
                  for (final r in c.reports.take(5))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${r.pro} · ${dateTimeLabel(r.at)}'),
                      subtitle: Text(
                        [
                          r.acts,
                          if (r.observations.isNotEmpty) r.observations,
                        ].join('\n'),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Signalement d'un incident par le soignant.
Future<void> showIncidentSheet(BuildContext context, {Booking? booking}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _IncidentSheet(booking: booking),
    );

class _IncidentSheet extends StatefulWidget {
  const _IncidentSheet({this.booking});

  final Booking? booking;

  @override
  State<_IncidentSheet> createState() => _IncidentSheetState();
}

class _IncidentSheetState extends State<_IncidentSheet> {
  IncidentCategory? _category;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final navigator = Navigator.of(context);
    await AppScope.of(context).reportIncident(
      category: _category!,
      description: _text.text,
      booking: widget.booking,
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _category != null && _text.text.trim().length >= 10;
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
            const Text(
              'Signaler un incident',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if (widget.booking != null)
              Text(
                '${widget.booking!.service.name} · ${widget.booking!.patientName}',
                style: const TextStyle(color: Colors.black54),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in IncidentCategory.values)
                  ChoiceChip(
                    label: Text(c.label),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            if (_category?.urgent ?? false) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBE0DA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Danger immédiat ? Appelez d’abord le SAMU (185) ou la '
                        'police (170), puis signalez ici.',
                        style: TextStyle(color: Color(0xFF6B1D0C)),
                      ),
                    ),
                    TextButton(
                      onPressed: () => launchUrl(Uri.parse('tel:185')),
                      child: const Text('185'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Ce qui s’est passé',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            ActionButton(
              label: 'Envoyer à MyNurse',
              success: 'Incident envoyé. L’équipe MyNurse vous recontacte.',
              onPressed: ready ? _send : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Annulation d'un soin confirmé par le soignant (motif vu par le patient).
Future<void> cancelByProDialog(BuildContext context, Booking b) async {
  final ctrl = TextEditingController();
  final app = AppScope.of(context);
  final reason = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        b.contract == null ? 'Annuler ce soin ?' : 'Annuler tout le suivi ?',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${b.patientName} sera remboursé(e) en totalité. Au-delà de '
            '$proCancellationAlertCount annulations en '
            '${proCancellationAlertPeriod.inDays} jours, MyNurse revoit votre '
            'compte.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Motif (vu par le patient)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Garder le soin'),
        ),
        TextButton(
          onPressed: () {
            if (ctrl.text.trim().isNotEmpty) {
              Navigator.pop(context, ctrl.text.trim());
            }
          },
          child: const Text('Annuler le soin'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (reason != null && context.mounted) {
    await runAction(context, () => app.cancelByPro(b, reason));
  }
}
