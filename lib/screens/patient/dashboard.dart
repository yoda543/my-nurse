import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../notifications.dart';
import '../wallet.dart';
import '../../intelligence/assistant/assistant.dart';
import '../assistant_screen.dart';
import 'booking_detail.dart';
import 'complaints.dart';
import 'search.dart';

/// Accueil du patient : ce qui l'attend, le prochain soin de chaque proche,
/// et les gestes les plus courants. Tout se lit sans connexion (données
/// gardées en mémoire).
class PatientDashboard extends StatefulWidget {
  const PatientDashboard({
    super.key,
    required this.onOpenBookings,
    required this.onOpenFamily,
    required this.onOpenRecord,
    required this.onOpenPharmacies,
  });

  final VoidCallback onOpenBookings;
  final VoidCallback onOpenFamily;
  final ValueChanged<Patient> onOpenRecord;
  final VoidCallback onOpenPharmacies;

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  /// Personne mise en avant (null : toute la famille).
  Patient? _focus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = AppScope.of(context);
      if (app.place == null && !app.locating) app.detectPlace();
    });
  }

  /// Assistant : il peut renvoyer vers un écran de l'app.
  Future<void> _assistant() async {
    final a = await openAssistant(context, AssistantRole.patient);
    if (a == null || !mounted) return;
    switch (a.destination) {
      case AssistantDestination.search:
        _search(service: a.service);
      case AssistantDestination.bookings:
        widget.onOpenBookings();
      case AssistantDestination.family || AssistantDestination.records:
        widget.onOpenFamily();
      case AssistantDestination.pharmacies:
        widget.onOpenPharmacies();
      case AssistantDestination.complaints:
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ComplaintsScreen()));
      default:
        break;
    }
  }

  void _search({CareService? service, bool focus = false}) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SearchScreen(service: service, autofocus: focus),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final family = app.familyPatients;
    if (_focus != null && !family.contains(_focus)) _focus = null;
    bool concerns(Booking b) => _focus == null || b.patient == _focus;
    final reminders = app.reminders
        .where((r) => r.booking == null || concerns(r.booking!))
        .toList();
    final upcoming = app.patientBookings
        .where(
          (b) =>
              concerns(b) &&
              (b.status == BookingStatus.pending ||
                  b.status == BookingStatus.accepted) &&
              b.endsAt.isAfter(app.now),
        )
        .toList();
    final wide = isWide(context);

    final hello = Row(
      children: [
        Expanded(
          child: Text(
            'Bonjour ${app.patientName.split(' ').first},',
            style: const TextStyle(fontSize: 16, color: Colors.black54),
          ),
        ),
        const NotificationBell(),
      ],
    );

    final searchBox = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'De quel soin avez-vous besoin ?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: brandInk,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFD9D3C5)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _search(focus: true),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.search, color: Colors.black54),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Infirmier, pansement, kiné…',
                      style: TextStyle(color: Colors.black54, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    final whoFor = family.length < 2
        ? const SizedBox.shrink()
        : SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ChoiceChip(
                  label: const Text('Toute la famille'),
                  selected: _focus == null,
                  onSelected: (_) => setState(() => _focus = null),
                ),
                for (final p in family) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(
                      p == app.patients.firstOrNull
                          ? 'Moi'
                          : '${p.name.split(' ').first} (${p.relation})',
                    ),
                    selected: _focus == p,
                    onSelected: (_) => setState(() => _focus = p),
                  ),
                ],
              ],
            ),
          );

    final todo = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlockTitle(
          reminders.isEmpty ? 'Rien à faire pour l’instant' : 'À faire',
        ),
        if (reminders.isEmpty)
          const Text(
            'Vos rappels (paiement, soin du lendemain, note à donner) '
            'apparaîtront ici.',
            style: TextStyle(color: Colors.black54),
          ),
        for (final r in reminders.take(3)) ...[
          _ReminderTile(reminder: r),
          const SizedBox(height: 8),
        ],
      ],
    );

    final next = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlockTitle(
          upcoming.length > 1 ? 'Prochains soins' : 'Prochain soin',
          action: upcoming.isEmpty
              ? null
              : TextButton(
                  onPressed: widget.onOpenBookings,
                  child: const Text('Tout voir'),
                ),
        ),
        if (upcoming.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('Aucun soin prévu'),
              subtitle: Text(
                _focus == null
                    ? 'Réservez un soignant vérifié en quelques minutes.'
                    : 'Réservez un soin pour ${_focus!.name.split(' ').first}.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _search(),
            ),
          ),
        for (final b in upcoming.take(2)) ...[
          _NextCareCard(booking: b),
          const SizedBox(height: 8),
        ],
      ],
    );

    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BlockTitle('Raccourcis'),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 96,
          ),
          children: [
            _Shortcut(
              icon: Icons.home_work_outlined,
              label: 'Soin à domicile',
              filled: true,
              onTap: () => _search(),
            ),
            _Shortcut(
              icon: Icons.menu_book_outlined,
              label: _focus == null
                  ? 'Carnet de santé'
                  : 'Carnet de ${_focus!.name.split(' ').first}',
              onTap: () => _focus == null
                  ? widget.onOpenFamily()
                  : widget.onOpenRecord(_focus!),
            ),
            _Shortcut(
              icon: Icons.family_restroom,
              label: 'Ma famille',
              onTap: widget.onOpenFamily,
            ),
            _Shortcut(
              icon: Icons.local_pharmacy_outlined,
              label: 'Pharmacies de garde',
              onTap: widget.onOpenPharmacies,
            ),
            _Shortcut(
              icon: Icons.assistant_outlined,
              label: 'Assistant MyNurse',
              onTap: _assistant,
            ),
          ],
        ),
      ],
    );

    final emergency = Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFBE0DA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.emergency_outlined, color: Color(0xFF9C2B12)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Urgence vitale ? MyNurse n'est pas un service d'urgence.",
              style: TextStyle(color: Color(0xFF6B1D0C)),
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF9C2B12),
            ),
            onPressed: () => launchUrl(Uri.parse('tel:185')),
            icon: const Icon(Icons.call),
            label: const Text('SAMU 185'),
          ),
        ],
      ),
    );

    final mainColumn = [hello, const SizedBox(height: 4), searchBox];
    final side = [whoFor, todo, next];
    final bottom = [
      actions,
      const SizedBox(height: 16),
      const PatientWalletCard(),
      const SizedBox(height: 16),
      emergency,
    ];

    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await app.retrySync();
            },
            child: wide
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                    children: [
                      ...mainColumn,
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Column(children: side)),
                          const SizedBox(width: 24),
                          Expanded(child: Column(children: bottom)),
                        ],
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    children: [
                      ...mainColumn,
                      const SizedBox(height: 12),
                      ...side,
                      ...bottom,
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder});

  final CareReminder reminder;

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final bg = r.urgent ? const Color(0xFFFFF1D6) : Colors.white;
    final fg = r.urgent ? const Color(0xFF6B4500) : brandInk;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: r.urgent ? const Color(0xFFF1D9A6) : const Color(0xFFE5E0D5),
        ),
      ),
      child: ListTile(
        leading: Icon(
          r.urgent ? Icons.priority_high_rounded : Icons.notifications_none,
          color: fg,
        ),
        title: Text(
          r.title,
          style: TextStyle(fontWeight: FontWeight.w700, color: fg),
        ),
        subtitle: Text(r.body, style: TextStyle(color: fg)),
        trailing: r.booking == null ? null : const Icon(Icons.chevron_right),
        onTap: r.booking == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BookingDetailScreen(booking: r.booking!),
                ),
              ),
      ),
    );
  }
}

class _NextCareCard extends StatelessWidget {
  const _NextCareCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = booking;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BookingDetailScreen(booking: b)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProAvatar(b.pro, radius: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${b.service.name.split(' (').first} · '
                          '${b.patient == app.patients.firstOrNull ? 'pour vous' : 'pour ${b.patientName}'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${dateTimeLabel(b.scheduledAt)} · ${b.pro.name}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CareSteps(booking: b),
              const SizedBox(height: 8),
              Text(
                nextStepText(b, app.now),
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : brandInk;
    return Material(
      color: filled ? brandGreen : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: filled
            ? BorderSide.none
            : const BorderSide(color: Color(0xFFE5E0D5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: filled ? Colors.white : brandGreen),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
