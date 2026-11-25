import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'booking_form.dart';

/// Icône d'un soin du catalogue.
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

/// Page publique d'un soignant : qui il est, ce qu'il propose, où, à quel
/// prix, ce qu'en disent les familles. On choisit le soin puis on réserve.
class ProProfileScreen extends StatefulWidget {
  const ProProfileScreen({
    super.key,
    required this.pro,
    this.service,
    this.patient,
  });

  final Pro pro;

  /// Proche pour qui on réserve.
  final Patient? patient;

  /// Soin cherché, présélectionné.
  final CareService? service;

  @override
  State<ProProfileScreen> createState() => _ProProfileScreenState();
}

class _ProProfileScreenState extends State<ProProfileScreen> {
  CareService? _service;

  @override
  void initState() {
    super.initState();
    _service = widget.service;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pro = widget.pro;
    final offered = app.servicesOf(pro);
    _service ??= offered.length == 1 ? offered.first : null;
    final wide = isWide(context);

    final header = Row(
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
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [const VerifiedBadge(), RatingLine(pro)],
              ),
            ],
          ),
        ),
      ],
    );

    final about = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pro.bio, style: const TextStyle(height: 1.4)),
            const Divider(height: 28),
            _info(
              Icons.place_outlined,
              'Se déplace à ${pro.communes.join(', ')}',
            ),
            _info(
              Icons.nightlight_outlined,
              pro.nightAvailable
                  ? 'Disponible la nuit (21 h – 6 h, majoration de 50 %)'
                  : 'Soins de jour uniquement',
            ),
            _info(
              Icons.fact_check_outlined,
              "Diplôme, autorisation d'exercer"
              '${pro.type.hasOrder ? ", inscription à l'Ordre" : ''} et pièce '
              "d'identité contrôlés par MyNurse",
            ),
            _info(
              Icons.history_rounded,
              '${pro.careCount} soins réalisés avec MyNurse',
            ),
          ],
        ),
      ),
    );

    final services = Card(
      child: RadioGroup<CareService>(
        groupValue: _service,
        onChanged: (v) => setState(() => _service = v),
        child: Column(
          children: [
            for (final s in offered)
              RadioListTile<CareService>(
                value: s,
                secondary: Icon(serviceIcon(s), color: brandGreen),
                title: Text(s.name),
                subtitle: Text(
                  [
                    fcfa(pro.prices[s.id]!),
                    '${s.durationMinutes} min environ',
                    if (s.needsPrescription) 'sur ordonnance',
                  ].join(' · '),
                ),
                controlAffinity: ListTileControlAffinity.trailing,
              ),
          ],
        ),
      ),
    );

    final reviews = _Reviews(pro: pro);

    final left = [header, const SizedBox(height: 20), about];
    final right = [
      const BlockTitle('Choisissez le soin'),
      services,
      const SizedBox(height: 4),
      const Text(
        'Prix fixé par le soignant dans la fourchette MyNurse. Vous payez '
        'seulement après sa confirmation.',
        style: TextStyle(color: Colors.black54, fontSize: 13),
      ),
      reviews,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Profil du soignant')),
      body: ContentWidth(
        maxWidth: wide ? 1100 : 720,
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 12, 24),
                      children: left,
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 24, 24),
                      children: right,
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [...left, ...right],
              ),
      ),
      bottomNavigationBar: SafeArea(
        child: ContentWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: FilledButton(
              onPressed: _service == null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BookingFormScreen(
                          pro: pro,
                          service: _service!,
                          patient: widget.patient,
                        ),
                      ),
                    ),
              child: Text(
                _service == null
                    ? 'Choisissez un soin ci-dessus'
                    : 'Réserver · ${fcfa(pro.prices[_service!.id]!)}',
              ),
            ),
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

class _Reviews extends StatefulWidget {
  const _Reviews({required this.pro});

  final Pro pro;

  @override
  State<_Reviews> createState() => _ReviewsState();
}

class _ReviewsState extends State<_Reviews> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final pro = widget.pro;
    final list = pro.reviews.where((r) => r.comment.isNotEmpty).toList();
    final shown = _all ? list : list.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BlockTitle(
          'Avis des familles',
          action: Text(
            '${pro.rating.toStringAsFixed(1).replaceAll('.', ',')}/5 · '
            '${pro.ratingCount} note${pro.ratingCount > 1 ? 's' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (list.isEmpty)
          const Text(
            'Pas encore d’avis écrit. Les notes viennent uniquement de '
            'patients qui ont eu un soin terminé.',
            style: TextStyle(color: Colors.black54),
          ),
        for (final r in shown) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 5; i++)
                        Icon(
                          i < r.rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 18,
                          color: const Color(0xFFE8A317),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          [
                            if (r.author.isNotEmpty) r.author,
                            if (r.serviceName.isNotEmpty) r.serviceName,
                          ].join(' · '),
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('« ${r.comment} »'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (list.length > 3 && !_all)
          TextButton(
            onPressed: () => setState(() => _all = true),
            child: Text('Voir les ${list.length} avis'),
          ),
      ],
    );
  }
}
