import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../widgets.dart';
import 'booking_form.dart';

class ProsListScreen extends StatelessWidget {
  const ProsListScreen({super.key, required this.service});

  final CareService service;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pros = app.prosFor(service, app.commune);
    return Scaffold(
      appBar: AppBar(title: Text(service.name)),
      body: pros.isEmpty
          ? EmptyState(
              icon: Icons.person_search_outlined,
              text: 'Aucun soignant vérifié disponible à ${app.commune} '
                  'pour ce soin. Essayez une commune voisine.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              itemCount: pros.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Text(
                    '${pros.length} soignant${pros.length > 1 ? 's' : ''} '
                    'vérifié${pros.length > 1 ? 's' : ''} à ${app.commune}',
                    style: const TextStyle(color: Colors.black54),
                  );
                }
                final p = pros[i - 1];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ProDetailScreen(pro: p, service: service),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          ProAvatar(p),
                          const SizedBox(width: 14),
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
                                const SizedBox(height: 2),
                                RatingLine(p),
                                const SizedBox(height: 6),
                                const VerifiedBadge(),
                              ],
                            ),
                          ),
                          Text(
                            fcfa(p.prices[service.id]!),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class ProDetailScreen extends StatelessWidget {
  const ProDetailScreen({super.key, required this.pro, required this.service});

  final Pro pro;
  final CareService service;

  @override
  Widget build(BuildContext context) {
    final price = pro.prices[service.id]!;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              ProAvatar(pro, radius: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pro.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${pro.type.label} · ${pro.yearsExperience} ans '
                      "d'expérience",
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    const VerifiedBadge(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RatingLine(pro),
                  const SizedBox(height: 10),
                  Text(pro.bio, style: const TextStyle(height: 1.4)),
                  const Divider(height: 28),
                  _info(Icons.place_outlined, pro.communes.join(', ')),
                  _info(
                    Icons.nightlight_outlined,
                    pro.nightAvailable
                        ? 'Disponible la nuit (majoration de 50 %)'
                        : 'Soins de jour uniquement',
                  ),
                  _info(
                    Icons.fact_check_outlined,
                    "Diplôme, inscription à l'Ordre et pièce d'identité "
                    'contrôlés par MyNurse',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: Text(service.name),
              subtitle: service.needsPrescription
                  ? const Text('Sur ordonnance')
                  : null,
              trailing: Text(
                fcfa(price),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BookingFormScreen(pro: pro, service: service),
              ),
            ),
            child: const Text('Réserver ce soin'),
          ),
        ),
      ),
    );
  }

  Widget _info(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: Colors.black54),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
