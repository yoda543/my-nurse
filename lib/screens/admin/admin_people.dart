import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'admin_widgets.dart';

// =============================================================== utilisateurs
class UsersModule extends StatefulWidget {
  const UsersModule({super.key});

  @override
  State<UsersModule> createState() => _UsersModuleState();
}

class _UsersModuleState extends State<UsersModule> {
  String _q = '';
  String? _role;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app
        .adminUsers(_q)
        .where((u) => _role == null || u.role == _role)
        .toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ModuleHeader(
          title: 'Utilisateurs',
          subtitle: '${list.length} compte(s)',
          actions: [
            ExportButton(
              title: 'Utilisateurs',
              csv: () => app.toCsv(
                ['Nom', 'Rôle', 'Téléphone', 'Détail'],
                [
                  for (final u in list) [u.name, u.role, u.phone, u.detail],
                ],
              ),
            ),
          ],
        ),
        SearchBox(
          hint: 'Nom ou téléphone',
          onChanged: (v) => setState(() => _q = v),
        ),
        FilterRow<String>(
          values: const ['Patient', 'Soignant', 'Équipe MyNurse'],
          selected: _role,
          label: (r) => r,
          onSelected: (r) => setState(() => _role = r),
        ),
        for (final u in list)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: CircleAvatar(
              child: Icon(switch (u.role) {
                'Patient' => Icons.person_outline,
                'Soignant' => Icons.medical_services_outlined,
                _ => Icons.admin_panel_settings_outlined,
              }),
            ),
            title: Text(u.name),
            subtitle: Text(
              '${u.role}${u.phone.isEmpty ? '' : ' · +225 ${u.phone}'}\n${u.detail}',
            ),
            isThreeLine: true,
          ),
      ],
    );
  }
}

// =================================================================== patients
class PatientsModule extends StatefulWidget {
  const PatientsModule({super.key});

  @override
  State<PatientsModule> createState() => _PatientsModuleState();
}

class _PatientsModuleState extends State<PatientsModule> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.adminPatients(_q);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ModuleHeader(
          title: 'Patients',
          subtitle:
              '${list.length} personne(s) soignée(s) · sans données médicales',
          actions: [
            ExportButton(
              title: 'Patients',
              csv: () => app.toCsv(
                [
                  'Patient',
                  'Compte titulaire',
                  'Commune',
                  'Rendez-vous',
                  'Dernier soin',
                ],
                [
                  for (final e in list)
                    [
                      e.patient.name,
                      e.owner,
                      e.patient.commune,
                      e.bookings,
                      e.last?.toIso8601String().substring(0, 10) ?? '',
                    ],
                ],
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: InfoBanner(
            icon: Icons.lock_outline,
            text:
                'L’équipe voit l’identité et l’activité, jamais le dossier '
                'médical. En cas d’urgence, l’accès d’urgence (permission '
                'dédiée) ouvre le dossier 4 h, avec un motif enregistré et '
                'envoyé à la famille.',
          ),
        ),
        SearchBox(
          hint: 'Patient, titulaire ou commune',
          onChanged: (v) => setState(() => _q = v),
        ),
        for (final e in list)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(e.patient.name),
            subtitle: Text(
              [
                'Titulaire : ${e.owner}',
                if (e.patient.commune.isNotEmpty) e.patient.commune,
                '${e.bookings} rendez-vous',
                if (e.last != null)
                  'dernier ${dateTimeLabel(e.last!).split(' à ').first}',
              ].join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AdminPatientScreen(patient: e.patient),
              ),
            ),
          ),
      ],
    );
  }
}

/// Fiche patient côté équipe : identité et activité. Le dossier médical
/// n'apparaît qu'après un accès d'urgence motivé.
class AdminPatientScreen extends StatelessWidget {
  const AdminPatientScreen({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = patient;
    final list = app.bookings.where((b) => b.patient == p).toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    final chart = app.adminChart(p);
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(
              [
                if (p.ageAt(app.now) != null) '${p.ageAt(app.now)} ans',
                if (p.commune.isNotEmpty) p.commune,
                if (p.ownerName.isNotEmpty) 'titulaire : ${p.ownerName}',
              ].join(' · '),
              style: const TextStyle(color: Colors.black54),
            ),
            const BlockTitle('Rendez-vous'),
            if (list.isEmpty) const Text('Aucun rendez-vous.'),
            for (final b in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${b.service.name} · ${b.pro.name}'),
                subtitle: Text(dateTimeLabel(b.scheduledAt)),
                trailing: StatusChip(b.status),
              ),
            const BlockTitle('Dossier médical'),
            if (chart == null) ...[
              const Text(
                'Non accessible à l’équipe. Seul l’accès d’urgence permet de '
                'l’ouvrir, pour un motif légitime (danger pour le patient, '
                'demande d’une autorité de santé…).',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              if (app.hasAdminPerm(AdminPermission.medicalBreakGlass))
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () async {
                    final reason = await askReason(
                      context,
                      'Accès d’urgence au dossier',
                      label: 'Motif détaillé (envoyé à la famille)',
                      help:
                          'L’accès dure 4 h. Il est inscrit au journal '
                          'd’activité et la famille reçoit le motif.',
                      minLength: 10,
                      confirm: 'Ouvrir le dossier',
                    );
                    if (reason == null || !context.mounted) return;
                    await runAction(
                      context,
                      () => app.adminBreakGlass(p, reason),
                    );
                  },
                  icon: const Icon(Icons.emergency_outlined),
                  label: const Text('Accès d’urgence'),
                )
              else
                const InfoBanner(
                  icon: Icons.lock_outline,
                  text:
                      'Vous n’avez pas la permission d’accès d’urgence. Elle est '
                      'attribuée par un responsable, jamais à soi-même.',
                ),
            ] else ...[
              InfoBanner(
                icon: Icons.emergency_outlined,
                warning: true,
                text: chart.scopeLabel,
              ),
              const SizedBox(height: 10),
              if (chart.allergies.isNotEmpty)
                Text('Allergies : ${chart.allergies}'),
              if (chart.treatments.isNotEmpty)
                Text('Traitements : ${chart.treatments}'),
              if (chart.history.isNotEmpty)
                Text('Antécédents : ${chart.history}'),
              if (chart.emergencyContact.isNotEmpty)
                Text('À prévenir : ${chart.emergencyContact}'),
              for (final v in chart.vitals.take(5))
                Text('${v.kind.label} : ${v.display} (${dateTimeLabel(v.at)})'),
            ],
          ],
        ),
      ),
    );
  }
}

// ================================================================= soignants
class ProsModule extends StatefulWidget {
  const ProsModule({super.key});

  @override
  State<ProsModule> createState() => _ProsModuleState();
}

class _ProsModuleState extends State<ProsModule> {
  String _q = '';
  VerificationStatus? _status;

  bool _alert(Pro p, AppState app) =>
      p.ratingAlert || p.reliabilityAlert(app.now);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.adminPros(_q, status: _status)
      ..sort((a, b) => (_alert(b, app) ? 1 : 0) - (_alert(a, app) ? 1 : 0));
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ModuleHeader(
          title: 'Soignants',
          subtitle:
              '${app.pros.where((p) => p.activeAt(app.now)).length} actifs · '
              '${app.pros.where((p) => p.status == VerificationStatus.suspended).length} suspendus',
          actions: [
            ExportButton(
              title: 'Soignants',
              csv: () => app.toCsv(
                [
                  'Nom',
                  'Profession',
                  'Statut',
                  'Communes',
                  'Note',
                  'Soins',
                  'Annulations 30 j',
                ],
                [
                  for (final p in list)
                    [
                      p.name,
                      p.type.label,
                      p.statusAt(app.now).label,
                      p.communes.join(', '),
                      p.rating.toStringAsFixed(1),
                      p.careCount,
                      p.recentCancellations(app.now),
                    ],
                ],
              ),
            ),
          ],
        ),
        SearchBox(
          hint: 'Nom, profession ou commune',
          onChanged: (v) => setState(() => _q = v),
        ),
        FilterRow<VerificationStatus>(
          values: VerificationStatus.values,
          selected: _status,
          label: (s) => s.label,
          onSelected: (s) => setState(() => _status = s),
        ),
        for (final p in list)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: ProAvatar(p, radius: 22),
            title: Text(p.name),
            subtitle: Text(
              '${p.type.label} · ${p.statusAt(app.now).label}'
              '${p.ratingCount > 0 ? ' · ${p.rating.toStringAsFixed(1).replaceAll('.', ',')}/5' : ''}'
              '${p.ratingAlert ? ' · note sous 4/5, à revoir' : ''}'
              '${p.reliabilityAlert(app.now) ? ' · ${p.recentCancellations(app.now)} annulations en 30 jours' : ''}'
              '${p.isPremium(app.now) ? ' · Premium' : ''}',
              style: TextStyle(
                color: _alert(p, app)
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
            trailing: switch (p.status) {
              VerificationStatus.verified => TextButton(
                onPressed: () async {
                  final r = await askReason(
                    context,
                    'Suspendre ${p.name}',
                    label: 'Motif (vu par le soignant)',
                  );
                  if (r != null && context.mounted) {
                    await runAction(context, () => app.suspendPro(p, r));
                  }
                },
                child: const Text('Suspendre'),
              ),
              VerificationStatus.suspended => TextButton(
                onPressed: () => runAction(context, () => app.verifyPro(p)),
                child: const Text('Réactiver'),
              ),
              _ => null,
            },
          ),
      ],
    );
  }
}

// ====================================================== vérification des pièces
class VerificationModule extends StatelessWidget {
  const VerificationModule({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.verificationQueue;
    final expiring = [
      for (final p in app.pros)
        if (p.activeAt(app.now) && p.expiringDocs(app.now).isNotEmpty) p,
    ];
    final incomplete = app.pros
        .where((p) => p.status == VerificationStatus.incomplete)
        .toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const ModuleHeader(
          title: 'Dossiers à vérifier',
          subtitle:
              'Nouveaux dossiers, dossiers en examen et pièces renouvelées',
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: InfoBanner(
            icon: Icons.checklist,
            text:
                'Avant de valider : comparer chaque pièce à l’original, '
                'vérifier le numéro sur la liste de l’Ordre, puis faire '
                'l’entretien vidéo.',
          ),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const EmptyState(
            icon: Icons.fact_check_outlined,
            text: 'Aucun dossier en attente.',
          ),
        for (final p in list)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: PendingProCard(pro: p),
          ),
        if (expiring.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: BlockTitle('Pièces qui expirent dans les 30 jours'),
          ),
          for (final p in expiring)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.schedule, color: Color(0xFF8A5A00)),
              title: Text(p.name),
              subtitle: Text(
                p
                    .expiringDocs(app.now)
                    .map(
                      (d) =>
                          '${d.label} (${dateTimeLabel(p.documentExpiry[d]!).split(' à ').first})',
                    )
                    .join(', '),
              ),
            ),
        ],
        if (incomplete.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: BlockTitle('Dossiers incomplets (en attente du soignant)'),
          ),
          for (final p in incomplete)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(p.name),
              subtitle: Text(
                'Manque : ${p.missingDocs.map((d) => d.label).join(', ')}',
              ),
            ),
        ],
      ],
    );
  }
}

/// Carte d'un dossier à vérifier (pièces, examen, validation, refus).
class PendingProCard extends StatelessWidget {
  const PendingProCard({super.key, required this.pro});

  final Pro pro;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = pro;
    final missing = p.missingDocs;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProAvatar(p),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${p.type.label} · ${p.yearsExperience} ans · +225 ${p.phone}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                Pill(p.status.label),
              ],
            ),
            const SizedBox(height: 12),
            if (p.orderNumber.isNotEmpty) Text('Ordre : ${p.orderNumber}'),
            Text('Communes : ${p.communes.join(', ')}'),
            Text(
              'Soins : ${p.prices.entries.map((e) => '${app.services.firstWhere((s) => s.id == e.key).name} (${fcfa(e.value)})').join(' ; ')}',
            ),
            const SizedBox(height: 10),
            for (final d in requiredDocs(p.type))
              Row(
                children: [
                  Icon(
                    p.documents.contains(d) ? Icons.check_circle : Icons.cancel,
                    size: 18,
                    color: p.documents.contains(d)
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${d.label}${p.documentExpiry[d] == null ? '' : ' · jusqu’au ${dateTimeLabel(p.documentExpiry[d]!).split(' à ').first}'}',
                    ),
                  ),
                  if (app.isRemote && p.documentPaths[d] != null)
                    TextButton(
                      onPressed: () => runAction(context, () async {
                        final url = await app.remote!.documentUrl(
                          p.documentPaths[d]!,
                        );
                        await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
                      }),
                      child: const Text('Voir'),
                    ),
                ],
              ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Dossier incomplet : impossible de valider.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final r = await askReason(
                        context,
                        'Refuser le dossier',
                        label: 'Motif (vu par le soignant)',
                      );
                      if (r != null && context.mounted) {
                        await runAction(context, () => app.rejectPro(p, r));
                      }
                    },
                    child: const Text('Refuser'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: p.status == VerificationStatus.pending
                      ? FilledButton(
                          onPressed: () =>
                              runAction(context, () => app.startReview(p)),
                          child: const Text('Examiner'),
                        )
                      : FilledButton(
                          onPressed: missing.isEmpty
                              ? () => runAction(context, () => app.verifyPro(p))
                              : null,
                          child: const Text('Valider'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================= équipe et droits
class StaffModule extends StatelessWidget {
  const StaffModule({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const ModuleHeader(
          title: 'Équipe et droits',
          subtitle: 'Chaque membre ne voit que les modules de ses permissions',
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: InfoBanner(
            icon: Icons.shield_outlined,
            text:
                'Moindre privilège : donnez seulement ce qui est utile au '
                'travail de la personne. L’accès d’urgence au dossier médical '
                'est attribué par un autre responsable, jamais à soi-même.',
          ),
        ),
        for (final m in app.staff)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Card(
              child: ExpansionTile(
                leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
                title: Text('${m.name}${m == app.adminMe ? ' (vous)' : ''}'),
                subtitle: Text('${m.permissions.length} permission(s)'),
                children: [
                  for (final p in AdminPermission.values)
                    SwitchListTile(
                      dense: true,
                      value: m.permissions.contains(p),
                      onChanged: (v) => runAction(
                        context,
                        () => app.setStaffPermission(m, p, v),
                      ),
                      title: Text(p.label),
                      secondary: p == AdminPermission.medicalBreakGlass
                          ? const Icon(
                              Icons.emergency_outlined,
                              color: Color(0xFF9C2B12),
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ),
        if (app.isRemote)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              'Nouveau membre : il crée son compte, puis un responsable '
              'l’active avec bootstrap_staff depuis la console Supabase.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
      ],
    );
  }
}

/// Couleur de la marque (réexport pour les autres modules).
const adminGreen = brandGreen;
