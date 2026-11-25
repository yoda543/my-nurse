import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../widgets.dart';
import '../notifications.dart';
import '../wallet.dart';
import 'dashboard.dart';
import 'complaints.dart';
import 'family.dart';
import 'pharmacies.dart';
import 'tracking.dart';
import 'health_record.dart';

class PatientShell extends StatefulWidget {
  const PatientShell({super.key});

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  int _tab = 0;

  static const _destinations = [
    (Icons.home_outlined, Icons.home, 'Accueil'),
    (Icons.event_note_outlined, Icons.event_note, 'Mes soins'),
    (Icons.family_restroom_outlined, Icons.family_restroom, 'Famille'),
    (Icons.local_pharmacy_outlined, Icons.local_pharmacy, 'Proximité'),
    (Icons.person_outline, Icons.person, 'Compte'),
  ];

  void _go(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final body = switch (_tab) {
      0 => PatientDashboard(
        onOpenBookings: () => _go(1),
        onOpenFamily: () => _go(2),
        onOpenRecord: (p) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => HealthRecordScreen(patient: p)),
        ),
        onOpenPharmacies: () => _go(3),
      ),
      1 => const BookingsTab(),
      2 => const FamilyTab(),
      3 => const PharmaciesTab(),
      _ => const _ProfileTab(),
    };
    if (isWide(context)) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _tab,
                onDestinationSelected: _go,
                labelType: NavigationRailLabelType.all,
                backgroundColor: Colors.white,
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(
                      icon: Icon(d.$1),
                      selectedIcon: Icon(d.$2),
                      label: Text(d.$3),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: ContentWidth(maxWidth: 1100, child: body)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.$1),
              selectedIcon: Icon(d.$2),
              label: d.$3,
            ),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    void open(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Compte',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(
              app.patientName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${app.familyPatients.length} personne'
              '${app.familyPatients.length > 1 ? 's' : ''} suivie'
              '${app.familyPatients.length > 1 ? 's' : ''}',
            ),
          ),
        ),
        const SizedBox(height: 12),
        const PatientWalletCard(),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notifications et rappels'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(const NotificationsScreen()),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.support_agent_outlined),
                title: const Text('Mes réclamations'),
                subtitle: app.complaints.isEmpty
                    ? null
                    : Text(
                        '${app.complaints.length} envoyée'
                        '${app.complaints.length > 1 ? 's' : ''}',
                      ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(const ComplaintsScreen()),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.report_outlined),
                title: const Text('Signaler un problème'),
                subtitle: const Text('Paiement, compte, autre'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showComplaintSheet(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: app.logout,
          icon: const Icon(Icons.logout),
          label: const Text('Se déconnecter'),
        ),
      ],
    );
  }
}
