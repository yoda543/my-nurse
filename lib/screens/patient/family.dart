import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'health_record.dart';
import 'patient_form.dart';
import 'search.dart';

/// Onglet « Famille » : chaque personne dont le compte s'occupe, ce qu'on
/// peut faire pour elle, et qui d'autre aide.
class FamilyTab extends StatelessWidget {
  const FamilyTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final family = app.familyPatients;
    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              const Text(
                'Ma famille',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Organisez les soins de vos proches en Côte d’Ivoire, même '
                'depuis l’étranger. Invitez un parent sur place à suivre les '
                'soins avec vous.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              for (final p in family) ...[
                FamilyMemberCard(patient: p),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: () => showPatientForm(context),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Ajouter un proche à soigner'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Vous en devenez le titulaire : vous gérez son carnet et '
                'choisissez qui d’autre y a accès.',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Une personne de la famille, avec les gestes permis au compte connecté.
class FamilyMemberCard extends StatelessWidget {
  const FamilyMemberCard({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = patient;
    final me = p == app.patients.firstOrNull;
    final owner = app.isOwner(p);
    final age = p.ageAt(app.now);
    final next = app.patientBookings
        .where(
          (b) =>
              b.patient == p &&
              (b.status == BookingStatus.pending ||
                  b.status == BookingStatus.accepted) &&
              b.endsAt.isAfter(app.now),
        )
        .firstOrNull;
    final helpers = app.activeMembers(p).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: owner ? brandGreen : const Color(0xFF1D4ED8),
                  child: Text(
                    p.name.isEmpty ? '?' : p.name[0],
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        me ? '${p.name} (moi)' : p.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        [
                          if (!me) p.relation,
                          if (age != null) '$age ans',
                          if (p.commune.isNotEmpty) p.commune,
                        ].join(' · '),
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!owner)
              InfoBanner(
                icon: Icons.handshake_outlined,
                text:
                    'Dossier de ${p.ownerName}. Vous pouvez : '
                    '${app.permissionsFor(p).map((e) => e.label.toLowerCase()).join(', ')}.',
              )
            else if (!me || helpers > 0)
              Text(
                helpers == 0
                    ? 'Personne d’autre n’aide pour ce dossier.'
                    : '$helpers proche${helpers > 1 ? 's' : ''} autorisé'
                          '${helpers > 1 ? 's' : ''} à aider.',
                style: const TextStyle(color: Colors.black54),
              ),
            if (next != null) ...[
              const SizedBox(height: 10),
              Text(
                'Prochain soin : ${next.service.name.split(' (').first}, '
                '${dateTimeLabel(next.scheduledAt)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              CareSteps(booking: next),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (app.can(p, FamilyPermission.bookCare))
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SearchScreen(patient: p),
                      ),
                    ),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Réserver un soin'),
                  ),
                if (app.can(p, FamilyPermission.viewRecords))
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HealthRecordScreen(patient: p),
                      ),
                    ),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Carnet'),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FamilyAccessScreen(patient: p),
                    ),
                  ),
                  icon: const Icon(Icons.lock_person_outlined),
                  label: Text(owner ? 'Qui a accès' : 'Mes droits'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Qui a accès au dossier : proches autorisés et soignants en cours de soin.
/// Le titulaire ajoute, modifie et retire ; un proche voit ses droits et peut
/// se retirer.
class FamilyAccessScreen extends StatelessWidget {
  const FamilyAccessScreen({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = patient;
    final owner = app.isOwner(p);
    return Scaffold(
      appBar: AppBar(
        title: Text('Accès au dossier de ${p.name.split(' ').first}'),
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: owner
              ? _ownerView(context, app)
              : _memberView(context, app),
        ),
      ),
    );
  }

  List<Widget> _memberView(BuildContext context, AppState app) {
    final p = patient;
    final perms = app.permissionsFor(p);
    final me = app.myMembership(p);
    return [
      InfoBanner(
        icon: Icons.handshake_outlined,
        text:
            '${p.ownerName} est titulaire de ce dossier et a choisi ce que '
            'vous pouvez faire. Pour un droit de plus, demandez-le-lui.',
      ),
      const BlockTitle('Vos droits'),
      for (final perm in FamilyPermission.values)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            perms.contains(perm)
                ? Icons.check_circle
                : Icons.remove_circle_outline,
            color: perms.contains(perm) ? brandGreen : Colors.black38,
          ),
          title: Text(perm.label),
          subtitle: Text(perm.help),
        ),
      if (me?.expiresAt != null)
        Text(
          'Accès jusqu’au ${dateTimeLabel(me!.expiresAt!)}.',
          style: const TextStyle(color: Colors.black54),
        ),
      const SizedBox(height: 20),
      if (me != null)
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () async {
            final ok = await _confirm(
              context,
              'Vous retirer du dossier de ${p.name} ?',
              'Vous ne verrez plus ses soins ni son carnet. ${p.ownerName} '
                  'pourra vous réinviter.',
              'Me retirer',
            );
            if (!ok || !context.mounted) return;
            final done = await runAction(
              context,
              () => app.revokeFamilyMember(p, me),
            );
            if (done && context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Me retirer de ce dossier'),
        ),
    ];
  }

  List<Widget> _ownerView(BuildContext context, AppState app) {
    final p = patient;
    final members = app.activeMembers(p);
    final pros = app.recordAccessFor(p);
    return [
      const Text(
        'Vous êtes titulaire : vous décidez qui voit et fait quoi. Chaque '
        'changement est immédiat et la personne est prévenue.',
        style: TextStyle(color: Colors.black54),
      ),
      BlockTitle(
        'Proches autorisés',
        action: TextButton.icon(
          onPressed: () => showMemberSheet(context, p),
          icon: const Icon(Icons.add),
          label: const Text('Autoriser'),
        ),
      ),
      if (members.isEmpty)
        const Text(
          'Personne pour l’instant. Exemple : un frère sur place qui suit '
          'les soins pendant que vous êtes à l’étranger.',
          style: TextStyle(color: Colors.black54),
        ),
      for (final m in members)
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text('${m.name} · ${m.relation}'),
            subtitle: Text(
              [
                m.permissions.map((e) => e.label).join(', '),
                if (m.expiresAt != null)
                  'jusqu’au ${dateTimeLabel(m.expiresAt!)}',
              ].join('\n'),
            ),
            isThreeLine: m.expiresAt != null,
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => showMemberSheet(context, p, member: m),
          ),
        ),
      const BlockTitle('Soignants qui voient le carnet'),
      Text(
        pros.isEmpty
            ? 'Aucun en ce moment. Un soignant voit le carnet seulement à '
                  'partir d’une demande de soin, et jusqu’à 24 h après le soin.'
            : 'Accès ouvert par une demande de soin. Il se ferme tout seul '
                  '24 h après le soin ; vous pouvez le fermer avant.',
        style: const TextStyle(color: Colors.black54),
      ),
      const SizedBox(height: 8),
      for (final a in pros)
        Card(
          child: ListTile(
            leading: const Icon(Icons.medical_services_outlined),
            title: Text(a.who),
            subtitle: Text('${a.scope}\nJusqu’au ${dateTimeLabel(a.until)}'),
            isThreeLine: true,
            trailing: TextButton(
              onPressed: () async {
                final ok = await _confirm(
                  context,
                  'Retirer l’accès de ${a.who.split(' · ').first} ?',
                  'Le soignant ne verra plus le carnet. Le rendez-vous, lui, '
                      'n’est pas annulé : sans les allergies et traitements, '
                      'le soin peut être moins sûr.',
                  'Retirer',
                );
                if (ok && context.mounted) {
                  final done = await runAction(
                    context,
                    () => app.revokeRecordAccess(p, a),
                  );
                  if (done && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Accès retiré.')),
                    );
                  }
                }
              },
              child: const Text('Retirer'),
            ),
          ),
        ),
    ];
  }
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String body,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Garder'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Ajout ou modification d'un proche autorisé.
Future<void> showMemberSheet(
  BuildContext context,
  Patient patient, {
  FamilyMember? member,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  builder: (_) => _MemberSheet(patient: patient, member: member),
);

class _MemberSheet extends StatefulWidget {
  const _MemberSheet({required this.patient, this.member});

  final Patient patient;
  final FamilyMember? member;

  @override
  State<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends State<_MemberSheet> {
  static const _relations = [
    'Fils',
    'Fille',
    'Frère',
    'Sœur',
    'Conjoint(e)',
    'Neveu / nièce',
    'Aide à domicile',
    'Autre proche',
  ];

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  String _relation = _relations.first;
  late Set<FamilyPermission> _perms;

  /// Durée de l'accès en jours (null : sans limite).
  int? _days;

  bool get _editing => widget.member != null;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    _perms = m == null ? {FamilyPermission.viewReports} : {...m.permissions};
    if (m != null) {
      _name.text = m.name;
      _contact.text = m.contact;
      _relation = _relations.contains(m.relation) ? m.relation : 'Autre proche';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final app = AppScope.of(context);
    final navigator = Navigator.of(context);
    final until = _days == null ? null : app.now.add(Duration(days: _days!));
    if (_editing) {
      await app.updateFamilyMember(
        widget.patient,
        widget.member!,
        permissions: _perms,
        expiresAt: until ?? widget.member!.expiresAt,
      );
    } else {
      await app.addFamilyMember(
        widget.patient,
        name: _name.text,
        contact: _contact.text,
        relation: _relation,
        permissions: _perms,
        expiresAt: until,
      );
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _editing
                    ? 'Droits de ${widget.member!.name}'
                    : 'Autoriser un proche pour ${widget.patient.name.split(' ').first}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _editing
                    ? 'Le changement est immédiat ; ce proche est prévenu.'
                    : 'Ce proche doit avoir un compte MyNurse. Il est prévenu '
                          'et voit le dossier dans son onglet Famille.',
                style: const TextStyle(color: Colors.black54),
              ),
              if (!_editing) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Son nom'),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Indiquez son nom.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contact,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone ou e-mail de son compte',
                  ),
                  validator: (v) => (v == null || v.trim().length < 8)
                      ? 'Indiquez son téléphone ou son e-mail.'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _relation,
                  decoration: InputDecoration(
                    labelText:
                        'Lien avec ${widget.patient.name.split(' ').first}',
                  ),
                  items: [
                    for (final r in _relations)
                      DropdownMenuItem(value: r, child: Text(r)),
                  ],
                  onChanged: (r) => setState(() => _relation = r!),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Ce qu’il peut faire',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final perm in FamilyPermission.values)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _perms.contains(perm),
                  onChanged: (on) => setState(
                    () => on! ? _perms.add(perm) : _perms.remove(perm),
                  ),
                  title: Text(perm.label),
                  subtitle: Text(perm.help),
                ),
              const SizedBox(height: 8),
              const Text(
                'Pendant combien de temps ?',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final (label, days) in [
                    (_editing ? 'Inchangé' : 'Sans limite', null),
                    ('1 mois', 30),
                    ('3 mois', 90),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: _days == days,
                      onSelected: (_) => setState(() => _days = days),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              ActionButton(
                label: _editing
                    ? 'Enregistrer les droits'
                    : 'Autoriser ce proche',
                success: _editing
                    ? 'Droits mis à jour.'
                    : 'Proche autorisé et prévenu.',
                onPressed: _perms.isEmpty ? null : _save,
              ),
              if (_perms.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Cochez au moins un droit.',
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_editing) ...[
                const SizedBox(height: 10),
                ActionButton(
                  label: 'Retirer ce proche',
                  outlined: true,
                  danger: true,
                  success: 'Accès retiré.',
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await app.revokeFamilyMember(
                      widget.patient,
                      widget.member!,
                    );
                    navigator.pop();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
