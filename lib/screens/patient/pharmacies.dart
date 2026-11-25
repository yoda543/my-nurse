import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// Onglet « Proximité » : pharmacies de la commune, celles de garde d'abord.
class PharmaciesTab extends StatefulWidget {
  const PharmaciesTab({super.key});

  @override
  State<PharmaciesTab> createState() => _PharmaciesTabState();
}

class _PharmaciesTabState extends State<PharmaciesTab> {
  bool _dutyOnly = true;
  String? _commune;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final commune = _commune ?? app.commune;
    final list = app.pharmaciesIn(commune, onDutyOnly: _dutyOnly);
    final all = app.pharmaciesIn(commune);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OfflineBanner(),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
          child: Text(
            'Pharmacies',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Pour une ordonnance à acheter avant le soin. Appelez avant de '
            'vous déplacer : la garde change chaque semaine.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(commune),
                  isExpanded: true,
                  initialValue: commune,
                  decoration: const InputDecoration(
                    labelText: 'Commune',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                  items: [
                    for (final c in communes)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (c) => setState(() => _commune = c),
                ),
              ),
            ],
          ),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          value: _dutyOnly,
          onChanged: (v) => setState(() => _dutyOnly = v),
          title: const Text('De garde maintenant'),
          subtitle: const Text(
            'Ouvertes la nuit, le dimanche et les jours fériés',
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.local_pharmacy_outlined,
                  text: all.isEmpty
                      ? 'Pas encore de pharmacie enregistrée à $commune. '
                            'L’équipe MyNurse complète la liste.'
                      : 'Aucune pharmacie de garde enregistrée à $commune en '
                            'ce moment. Désactivez le filtre pour voir les '
                            '${all.length} pharmacies de la commune.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => PharmacyCard(pharmacy: list[i]),
                ),
        ),
      ],
    );
  }
}

class PharmacyCard extends StatelessWidget {
  const PharmacyCard({super.key, required this.pharmacy});

  final Pharmacy pharmacy;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = pharmacy;
    final duty = p.onDutyAt(app.now);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_pharmacy, color: brandGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(p.address),
            const SizedBox(height: 4),
            Text(
              duty
                  ? 'De garde jusqu’au ${dateTimeLabel(p.onDutyUntil!)}'
                  : (p.hours.isEmpty ? 'Horaires non communiqués' : p.hours),
              style: TextStyle(
                color: duty ? brandGreen : Colors.black54,
                fontWeight: duty ? FontWeight.w700 : null,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (p.phone.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () => launchUrl(Uri.parse('tel:${p.phone}')),
                    icon: const Icon(Icons.call),
                    label: const Text('Appeler'),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: () => launchUrl(
                    p.location?.directionsUrl ??
                        Uri.https('www.google.com', '/maps/search/', {
                          'api': '1',
                          'query': '${p.name} ${p.address} ${p.commune}',
                        }),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.directions),
                  label: const Text('Itinéraire'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
