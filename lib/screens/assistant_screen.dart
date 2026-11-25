import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../intelligence/assistant/assistant.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Ouvre l'assistant. Renvoie l'action choisie (aller vers un écran), que
/// l'écran appelant traite.
Future<AssistantAction?> openAssistant(
  BuildContext context,
  AssistantRole role,
) => Navigator.of(context).push<AssistantAction>(
  MaterialPageRoute(builder: (_) => AssistantScreen(role: role)),
);

/// Contexte donné à l'assistant : jamais le dossier médical.
AssistantContext assistantContextFor(AppState app, AssistantRole role) =>
    AssistantContext(
      role: role,
      services: app.services,
      commune: role == AssistantRole.pro
          ? (app.currentPro?.communes.firstOrNull ?? app.commune)
          : app.commune,
      now: app.now,
      userName: role == AssistantRole.pro
          ? (app.currentPro?.name ?? '')
          : app.patientName,
      findPros: (s, c) => app.searchPros(
        SearchFilters(commune: c, serviceId: s.id),
        patient: app.patients.firstOrNull,
      ),
      proDay: app.currentPro == null ? null : app.proDay,
      showUnreviewedArticles: !app.isRemote,
    );

class _Message {
  const _Message(this.fromUser, this.text, [this.reply]);

  final bool fromUser;
  final String text;
  final AssistantReply? reply;
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, required this.role, this.assistant});

  final AssistantRole role;
  final MyNurseAssistant? assistant;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  late final MyNurseAssistant _assistant =
      widget.assistant ?? MyNurseAssistant();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Message> _messages = [];
  bool _thinking = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final q = text.trim();
    if (q.isEmpty || _thinking) return;
    final app = AppScope.of(context);
    _input.clear();
    setState(() {
      _messages.add(_Message(true, q));
      _thinking = true;
    });
    final reply = await _assistant.ask(
      q,
      assistantContextFor(app, widget.role),
    );
    if (!mounted) return;
    setState(() {
      _messages.add(_Message(false, reply.text, reply));
      _thinking = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final starters = MyNurseAssistant.starters(widget.role);
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant MyNurse')),
      body: ContentWidth(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFE6EDFC),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: const Text(
                'Je vous aide à utiliser MyNurse. Je ne pose pas de diagnostic '
                'et ne conseille aucun médicament. Mes réponses sont calculées '
                'sur votre téléphone : vos données de santé ne sont pas '
                'envoyées à un service d’IA.',
                style: TextStyle(fontSize: 13, color: Color(0xFF1E3A8A)),
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  if (_messages.isEmpty) ...[
                    const Text(
                      'Que puis-je faire pour vous ?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in starters)
                          ActionChip(label: Text(s), onPressed: () => _send(s)),
                      ],
                    ),
                  ],
                  for (final m in _messages) _Bubble(message: m, onAsk: _send),
                  if (_thinking)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _send,
                        minLines: 1,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Votre question',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Envoyer',
                      onPressed: () => _send(_input.text),
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onAsk});

  final _Message message;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final r = m.reply;
    if (m.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 48),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: brandGreen,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(m.text, style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    final (bg, fg) = switch (r?.kind) {
      ReplyKind.emergency => (const Color(0xFFFBE0DA), const Color(0xFF6B1D0C)),
      ReplyKind.refusal => (const Color(0xFFFFF1D6), const Color(0xFF6B4500)),
      _ => (Colors.white, brandInk),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 32),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E0D5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.text, style: TextStyle(color: fg, height: 1.35)),
            if (r?.source != null) ...[
              const SizedBox(height: 6),
              Text(
                'Source : ${r!.source}',
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (r?.kind == ReplyKind.emergency) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9C2B12),
                  minimumSize: const Size(0, 44),
                ),
                onPressed: () => launchUrl(Uri.parse('tel:185')),
                icon: const Icon(Icons.call),
                label: const Text('Appeler le SAMU (185)'),
              ),
            ],
            if (r != null && r.actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in r.actions)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      onPressed: () => Navigator.of(context).pop(a),
                      child: Text(a.label),
                    ),
                ],
              ),
            ],
            if (r != null && r.suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in r.suggestions.take(4))
                    ActionChip(label: Text(s), onPressed: () => onAsk(s)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
