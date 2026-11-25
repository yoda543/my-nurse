import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'pro_profile.dart';

/// Recherche d'un soignant : un champ libre (nom, soin, spécialité), le soin
/// en un geste, la commune détectée, et des filtres repliés pour ne pas
/// encombrer l'écran.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.service,
    this.autofocus = false,
    this.patient,
  });

  final CareService? service;
  final bool autofocus;

  /// Proche pour qui on cherche (sa commune est proposée d'office).
  final Patient? patient;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  late SearchFilters _f;
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    final app = AppScope.of(context);
    final forRelative =
        widget.patient != null && widget.patient != app.patients.firstOrNull;
    _f = SearchFilters(
      commune: forRelative ? app.communeFor(widget.patient!) : app.commune,
      serviceId: widget.service?.id,
    );
    if (!forRelative && app.place == null && !app.locating) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await app.detectPlace();
        if (mounted) setState(() => _f = _f.copyWith(commune: app.commune));
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _set(SearchFilters f) => setState(() => _f = f);

  Future<void> _openFilters() async {
    final f = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => FiltersSheet(initial: _f),
    );
    if (f != null) _set(f);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final results = app.searchPros(
      _f,
      patient: widget.patient ?? app.patients.firstOrNull,
    );
    final service = _f.serviceId == null
        ? null
        : app.services.firstWhere((s) => s.id == _f.serviceId);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.patient == null || widget.patient == app.patients.firstOrNull
              ? 'Trouver un soignant'
              : 'Soignant pour ${widget.patient!.name.split(' ').first}',
        ),
      ),
      body: ContentWidth(
        child: Column(
          children: [
            const OfflineBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: TextField(
                controller: _query,
                autofocus: widget.autofocus,
                textInputAction: TextInputAction.search,
                onChanged: (v) => _set(_f.copyWith(query: v)),
                decoration: InputDecoration(
                  hintText: 'Nom, soin ou spécialité (ex. pansement)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer',
                          onPressed: () {
                            _query.clear();
                            _set(_f.copyWith(query: ''));
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                children: [
                  _CommuneChip(
                    commune: _f.commune,
                    onChanged: (c) {
                      app.setCommune(c);
                      _set(_f.copyWith(commune: c));
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    avatar: const Icon(Icons.tune, size: 18),
                    label: Text(
                      _f.activeCount == 0
                          ? 'Filtres'
                          : 'Filtres (${_f.activeCount})',
                    ),
                    selected: _f.activeCount > 0,
                    onSelected: (_) => _openFilters(),
                  ),
                  const SizedBox(width: 8),
                  for (final s in app.services) ...[
                    ChoiceChip(
                      label: Text(s.name.split(' (').first),
                      selected: _f.serviceId == s.id,
                      onSelected: (on) =>
                          _set(_f.copyWith(serviceId: () => on ? s.id : null)),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: LocationStatus(
                onRetry: () async {
                  await app.detectPlace();
                  if (mounted) _set(_f.copyWith(commune: app.commune));
                },
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? _NoResult(
                      filters: _f,
                      onClear: () {
                        _query.clear();
                        _set(SearchFilters(commune: _f.commune));
                      },
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: results.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          final n = results.length;
                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '$n soignant${n > 1 ? 's' : ''} '
                                  'vérifié${n > 1 ? 's' : ''} à ${_f.commune}'
                                  '${service == null ? '' : ' pour ${service.name.split(' (').first.toLowerCase()}'}',
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ),
                              Text(
                                _f.sort.label,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          );
                        }
                        return ProResultCard(
                          match: results[i - 1],
                          patient: widget.patient,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommuneChip extends StatelessWidget {
  const _CommuneChip({required this.commune, required this.onChanged});

  final String commune;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Changer de commune',
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final c in communes) PopupMenuItem(value: c, child: Text(c)),
      ],
      child: Chip(
        avatar: const Icon(Icons.place_outlined, size: 18, color: brandGreen),
        label: Text(commune),
      ),
    );
  }
}

/// Un soignant dans les résultats.
class ProResultCard extends StatelessWidget {
  const ProResultCard({super.key, required this.match, this.patient});

  final ProMatch match;
  final Patient? patient;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = match.pro;
    final services = app.servicesOf(p);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProProfileScreen(
              pro: p,
              service: match.service,
              patient: patient,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    Text(
                      '${p.type.label} · ${p.yearsExperience} ans',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 4),
                    RatingLine(p),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        const VerifiedBadge(),
                        if (p.nightAvailable) const _Tag('Nuit'),
                      ],
                    ),
                    if (match.reasons.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      for (final r in match.reasons)
                        Row(
                          children: [
                            const Icon(
                              Icons.check,
                              size: 14,
                              color: brandGreen,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                r,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: brandGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                    if (match.service == null) ...[
                      const SizedBox(height: 6),
                      Text(
                        services
                            .map((s) => s.name.split(' (').first)
                            .join(' · '),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (match.service == null)
                    const Text(
                      'dès',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  Text(
                    fcfa(match.price),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFE4E8EA),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

class _NoResult extends StatelessWidget {
  const _NoResult({required this.filters, required this.onClear});

  final SearchFilters filters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final narrowed =
        filters.activeCount > 0 ||
        filters.query.isNotEmpty ||
        filters.serviceId != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_search_outlined,
              size: 48,
              color: Colors.black26,
            ),
            const SizedBox(height: 12),
            Text(
              narrowed
                  ? 'Aucun soignant ne correspond à ces critères à '
                        '${filters.commune}.'
                  : 'Aucun soignant vérifié à ${filters.commune} pour le '
                        'moment. Essayez une commune voisine.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 15),
            ),
            if (narrowed) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onClear,
                child: const Text('Effacer les critères'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Filtres avancés, dans une feuille qu'on applique en une fois.
class FiltersSheet extends StatefulWidget {
  const FiltersSheet({super.key, required this.initial});

  final SearchFilters initial;

  @override
  State<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<FiltersSheet> {
  late SearchFilters _f = widget.initial;

  static const _budgets = [7000, 10000, 15000, 20000];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final count = app.searchPros(_f).length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filtres',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _f = _f.cleared()),
                    child: const Text('Tout effacer'),
                  ),
                ],
              ),
              _label('Profession'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in ProType.values)
                    ChoiceChip(
                      label: Text(t.label),
                      selected: _f.proType == t,
                      onSelected: (on) => setState(
                        () => _f = _f.copyWith(proType: () => on ? t : null),
                      ),
                    ),
                ],
              ),
              _label('Prix maximum'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final b in _budgets)
                    ChoiceChip(
                      label: Text(fcfa(b)),
                      selected: _f.maxPrice == b,
                      onSelected: (on) => setState(
                        () => _f = _f.copyWith(maxPrice: () => on ? b : null),
                      ),
                    ),
                ],
              ),
              _label('Note minimale'),
              Wrap(
                spacing: 8,
                children: [
                  for (final r in [4.0, 4.5, 4.8])
                    ChoiceChip(
                      avatar: const Icon(
                        Icons.star_rounded,
                        size: 18,
                        color: Color(0xFFE8A317),
                      ),
                      label: Text(
                        '${r.toStringAsFixed(1).replaceAll('.', ',')} et +',
                      ),
                      selected: _f.minRating == r,
                      onSelected: (on) => setState(
                        () => _f = _f.copyWith(minRating: on ? r : 0),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _f.nightOnly,
                onChanged: (v) =>
                    setState(() => _f = _f.copyWith(nightOnly: v)),
                title: const Text('Disponible la nuit'),
                subtitle: const Text('21 h – 6 h, majoration de 50 %'),
              ),
              _label('Trier par'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in SearchSort.values)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: _f.sort == s,
                      onSelected: (_) =>
                          setState(() => _f = _f.copyWith(sort: s)),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_f),
                child: Text(
                  count == 0
                      ? 'Aucun résultat avec ces filtres'
                      : 'Voir $count soignant${count > 1 ? 's' : ''}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}
