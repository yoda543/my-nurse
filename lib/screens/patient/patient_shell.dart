import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'booking_detail.dart';
import 'patient_form.dart';
import 'pros_list.dart';

class PatientShell extends StatefulWidget {
  const PatientShell({super.key});

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (_tab) {
          0 => const _HomeTab(),
          1 => const _BookingsTab(),
          _ => const _ProfileTab(),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Trouver',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Mes soins',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

IconData serviceIcon(CareService s) => switch (s.id) {
      'injection' => Icons.vaccines_outlined,
      'perfusion' => Icons.water_drop_outlined,
      'pansement' => Icons.healing_outlined,
      'sonde' => Icons.medical_services_outlined,
      'toilette' => Icons.bathtub_outlined,
      'consultation' => Icons.medical_information_outlined,
      'kine' => Icons.accessibility_new,
      _ => Icons.pregnant_woman,
    };

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Text(
          'Bonjour ${app.patientName.split(' ').first},',
          style: const TextStyle(fontSize: 16, color: Colors.black54),
        ),
        const SizedBox(height: 2),
        const Text(
          'De quel soin avez-vous besoin ?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: brandInk,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: app.commune,
          decoration: const InputDecoration(
            labelText: 'Commune du soin',
            prefixIcon: Icon(Icons.place_outlined),
          ),
          items: [
            for (final c in communes) DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (c) => app.setCommune(c!),
        ),
        const SizedBox(height: 20),
        for (final s in app.services) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFD5EDE9),
                child: Icon(serviceIcon(s), color: brandGreen),
              ),
              title: Text(
                s.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(s.proType.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ProsListScreen(service: s)),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFBE0DA),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            children: [
              Icon(Icons.emergency_outlined, color: Color(0xFF9C2B12)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Urgence vitale ? MyNurse n'est pas un service d'urgence. "
                  'Appelez le SAMU au 185.',
                  style: TextStyle(color: Color(0xFF6B1D0C)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BookingsTab extends StatelessWidget {
  const _BookingsTab();

  @override
  Widget build(BuildContext context) {
    final list = AppScope.of(context).patientBookings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text(
            'Mes soins',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(
                  icon: Icons.event_note_outlined,
                  text: 'Vous n’avez pas encore réservé de soin.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => BookingCard(
                    booking: list[i],
                    forPro: false,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BookingDetailScreen(booking: list[i]),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Profil',
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
            subtitle: Text('Compte patient · ${app.commune}'),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Personnes soignées',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Réservez pour vous ou pour un proche, même à distance.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (final p in app.patients)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(p.name),
                  subtitle: Text(
                    p.allergies.isEmpty
                        ? p.relation
                        : '${p.relation} · Allergies : ${p.allergies}',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => showPatientForm(context),
          icon: const Icon(Icons.add),
          label: const Text('Ajouter un proche'),
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
