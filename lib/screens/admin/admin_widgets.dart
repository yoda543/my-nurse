import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// Couleurs de la console (bleu d'action, encre de la barre latérale).
const adminBlue = Color(0xFF1D4ED8);
const adminInk = Color(0xFF0F2A2E);

/// En-tête d'un module : titre, sous-titre, actions (export…).
class ModuleHeader extends StatelessWidget {
  const ModuleHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 8,
      spacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            if (subtitle != null)
              Text(subtitle!, style: const TextStyle(color: Colors.black54)),
          ],
        ),
        if (actions.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    ),
  );
}

/// Carte d'indicateur du tableau de bord.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.icon,
    this.alert = false,
    this.onTap,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData? icon;
  final bool alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 18,
                    color: alert ? const Color(0xFF9C2B12) : brandGreen,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: alert ? const Color(0xFF9C2B12) : brandInk,
                ),
              ),
            ),
            if (hint != null)
              Text(
                hint!,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    ),
  );
}

/// Grille responsive : 2 colonnes sur téléphone, 3 ou 4 au-delà.
class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 640 ? 3 : 2);
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final ch in children) SizedBox(width: w, height: 124, child: ch),
        ],
      );
    },
  );
}

/// Champ de recherche d'un module.
class SearchBox extends StatelessWidget {
  const SearchBox({super.key, required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
    child: TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        isDense: true,
      ),
    ),
  );
}

/// Rangée de filtres (puces), défilante sur téléphone.
class FilterRow<T> extends StatelessWidget {
  const FilterRow({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.allLabel = 'Tous',
  });

  final List<T> values;
  final T? selected;
  final String Function(T) label;
  final ValueChanged<T?> onSelected;
  final String allLabel;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        ChoiceChip(
          label: Text(allLabel),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final v in values) ...[
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(label(v)),
            selected: selected == v,
            onSelected: (_) => onSelected(v),
          ),
        ],
      ],
    ),
  );
}

/// Bouton d'export : produit un CSV (séparateur « ; », pour Excel) et
/// propose de le copier. L'export est inscrit au journal d'activité.
class ExportButton extends StatelessWidget {
  const ExportButton({super.key, required this.title, required this.csv});

  final String title;

  /// Produit le contenu CSV au moment de l'export.
  final String Function() csv;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
    onPressed: () => showExport(context, title, csv()),
    icon: const Icon(Icons.download_outlined, size: 18),
    label: const Text('Exporter'),
  );
}

Future<void> showExport(
  BuildContext context,
  String title,
  String csv,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('Export : $title'),
    content: SizedBox(
      width: 640,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${csv.split('\n').length - 1} ligne(s) · format CSV '
            '(séparateur « ; »), à coller dans Excel ou Google Sheets.',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F6F7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                csv,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fermer'),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: csv));
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Rapport copié.')));
          }
        },
        icon: const Icon(Icons.copy),
        label: const Text('Copier'),
      ),
    ],
  ),
);

/// Demande un motif (obligatoire) avant une action sensible.
Future<String?> askReason(
  BuildContext context,
  String title, {
  String label = 'Motif',
  String? help,
  int minLength = 1,
  String confirm = 'Confirmer',
}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (help != null) ...[
              Text(help, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: label),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Retour'),
          ),
          TextButton(
            onPressed: ctrl.text.trim().length >= minLength
                ? () => Navigator.pop(context, ctrl.text.trim())
                : null,
            child: Text(confirm),
          ),
        ],
      ),
    ),
  ).whenComplete(ctrl.dispose);
}

/// Message d'accès refusé faute de permission (module visible en lecture).
class NoPermission extends StatelessWidget {
  const NoPermission({super.key, required this.permission});

  final AdminPermission permission;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.lock_outline,
    text:
        'Module réservé : permission « ${permission.label} ». Demandez-la à '
        'un responsable de l’équipe.',
  );
}

/// Pastille de statut générique.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = adminBlue});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
    ),
  );
}

/// Barres horizontales simples (répartitions).
class BarList extends StatelessWidget {
  const BarList({super.key, required this.data, this.suffix = ''});

  final Map<String, int> data;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final max = data.values.fold<int>(1, (m, v) => v > m ? v : m);
    if (data.isEmpty) {
      return const Text(
        'Aucune donnée sur la période.',
        style: TextStyle(color: Colors.black54),
      );
    }
    return Column(
      children: [
        for (final e in data.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 130,
                  child: Text(e.key, overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  child: LinearProgressIndicator(
                    value: e.value / max,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                    backgroundColor: const Color(0xFFE4E8EA),
                    color: brandGreen,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text('${e.value}$suffix', textAlign: TextAlign.end),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Histogramme vertical par jour.
class DailyBars extends StatelessWidget {
  const DailyBars({super.key, required this.values, required this.labels});

  final List<int> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final max = values.fold<int>(1, (m, v) => v > m ? v : m);
    final step = (values.length / 10).ceil().clamp(1, 100);
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Tooltip(
                      message: '${labels[i]} : ${values[i]}',
                      child: Container(
                        height: 110 * values[i] / max + 2,
                        decoration: BoxDecoration(
                          color: i == values.length - 1
                              ? brandGreen
                              : const Color(0xFF7FB8B1),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 14,
                      child: i % step == 0
                          ? FittedBox(
                              child: Text(
                                labels[i],
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Raccourci : vérifie une permission pour afficher une action.
bool allowed(BuildContext context, AdminPermission p) =>
    AppScope.of(context).hasAdminPerm(p);
