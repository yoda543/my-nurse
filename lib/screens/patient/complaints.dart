import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../widgets.dart';

/// Signaler un problème au support MyNurse, depuis un soin ou en général.
Future<void> showComplaintSheet(BuildContext context, {Booking? booking}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _ComplaintSheet(booking: booking),
    );

class _ComplaintSheet extends StatefulWidget {
  const _ComplaintSheet({this.booking});

  final Booking? booking;

  @override
  State<_ComplaintSheet> createState() => _ComplaintSheetState();
}

class _ComplaintSheetState extends State<_ComplaintSheet> {
  ComplaintCategory? _category;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final navigator = Navigator.of(context);
    await AppScope.of(context).openComplaint(
      category: _category!,
      description: _text.text,
      booking: widget.booking,
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Signaler un problème',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if (b != null)
              Text(
                '${b.service.name} · ${b.pro.name} · ${dateTimeLabel(b.scheduledAt)}',
                style: const TextStyle(color: Colors.black54),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in ComplaintCategory.values)
                  ChoiceChip(
                    label: Text(c.label),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            if (_category == ComplaintCategory.safety) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBE0DA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Danger immédiat pour le patient ? Appelez d’abord le '
                        'SAMU. Votre signalement est traité en priorité.',
                        style: TextStyle(color: Color(0xFF6B1D0C)),
                      ),
                    ),
                    TextButton(
                      onPressed: () => launchUrl(Uri.parse('tel:185')),
                      child: const Text('185'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Que s’est-il passé ?',
                hintText: 'En une ou deux phrases',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Le support répond sous 24 h. Si un remboursement est justifié, '
              'il arrive sur votre solde MyNurse.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ActionButton(
              label: 'Envoyer au support',
              success:
                  'Réclamation envoyée. Suivez-la dans « Mes réclamations ».',
              onPressed: _category == null || _text.text.trim().length < 10
                  ? null
                  : _send,
            ),
            if (_category == null || _text.text.trim().length < 10)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Choisissez le type de problème et décrivez-le (10 caractères '
                  'au moins).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Réclamations envoyées et leur avancement.
class ComplaintsScreen extends StatelessWidget {
  const ComplaintsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.complaints;
    return Scaffold(
      appBar: AppBar(title: const Text('Mes réclamations')),
      body: ContentWidth(
        child: list.isEmpty
            ? const EmptyState(
                icon: Icons.support_agent_outlined,
                text:
                    'Aucune réclamation. En cas de souci avec un soin, ouvrez '
                    'le soin puis « Signaler un problème ».',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final c = list[i];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        c.status == ComplaintStatus.resolved
                            ? Icons.check_circle_outline
                            : Icons.support_agent_outlined,
                      ),
                      title: Text(c.category.label),
                      subtitle: Text(
                        [
                          '${c.status.label} · ${dateTimeLabel(c.createdAt)}',
                          if (c.booking != null)
                            '${c.booking!.service.name} · ${c.booking!.pro.name}',
                          c.description,
                          if (c.resolution.isNotEmpty)
                            'Réponse : ${c.resolution}',
                        ].join('\n'),
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
