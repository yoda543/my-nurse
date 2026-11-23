import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../models.dart';

/// Connexion à la base en ligne : adresse e-mail, puis code à 6 chiffres
/// reçu par e-mail. Le compte est créé à la première connexion.
class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key, required this.role});

  final UserRole role;

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final app = AppScope.of(context);
    final email = _email.text.trim().toLowerCase();
    setState(() => _error = null);
    if (!_codeSent && !_emailPattern.hasMatch(email)) {
      setState(() => _error = 'Entrez une adresse e-mail valide.');
      return;
    }
    if (_codeSent && _code.text.length != 6) {
      setState(() => _error = 'Le code compte 6 chiffres.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (!_codeSent) {
        await app.sendCode(email, widget.role);
        if (mounted) setState(() => _codeSent = true);
      } else {
        await app.verifyCode(email, _code.text, widget.role);
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } on BusinessRuleError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Connexion impossible. Vérifiez votre réseau et réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _codeSent ? 'Entrez le code reçu' : 'Votre adresse e-mail',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _codeSent
                  ? 'Code envoyé à ${_email.text.trim()}. Pensez à regarder '
                        'dans les courriers indésirables.'
                  : switch (widget.role) {
                      UserRole.pro =>
                        'Connectez-vous ou créez votre compte soignant. '
                            'Nous vous envoyons un code par e-mail.',
                      UserRole.admin => 'Accès réservé à l’équipe MyNurse.',
                      UserRole.patient =>
                        'Nous vous envoyons un code par e-mail pour vous '
                            'connecter. Pas de mot de passe à retenir.',
                    },
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            if (!_codeSent)
              TextField(
                key: const ValueKey('email'),
                controller: _email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: 'Adresse e-mail',
                  hintText: 'nom@exemple.com',
                  errorText: _error,
                ),
                onSubmitted: (_) => _submit(),
              )
            else
              TextField(
                key: const ValueKey('code'),
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: InputDecoration(
                  labelText: 'Code à 6 chiffres',
                  errorText: _error,
                ),
                onSubmitted: (_) => _submit(),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(_codeSent ? 'Se connecter' : 'Recevoir le code'),
            ),
            if (_codeSent)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _codeSent = false;
                        _code.clear();
                        _error = null;
                      }),
                child: const Text('Modifier l’adresse ou renvoyer un code'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Premier passage d'un patient : son nom, pour les soignants et les reçus.
class ProfileNameScreen extends StatefulWidget {
  const ProfileNameScreen({super.key});

  @override
  State<ProfileNameScreen> createState() => _ProfileNameScreenState();
}

class _ProfileNameScreenState extends State<ProfileNameScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.length < 3 || !name.contains(' ')) {
      setState(() => _error = 'Indiquez votre prénom et votre nom.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).completeProfile(name);
    } on BusinessRuleError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Connexion impossible. Vérifiez votre réseau et réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            onPressed: AppScope.of(context).logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Bienvenue sur MyNurse',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Votre nom figure sur vos demandes de soin et vos reçus. Vous '
              'pourrez ajouter vos proches ensuite.',
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: InputDecoration(
                labelText: 'Prénom et nom',
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Text('Continuer'),
            ),
          ],
        ),
      ),
    );
  }
}
