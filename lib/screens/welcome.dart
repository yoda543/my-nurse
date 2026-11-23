import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void go(UserRole role) =>
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => LoginScreen(role: role)));
    return Scaffold(
      backgroundColor: brandGreen,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.health_and_safety,
                  color: brandGreen,
                  size: 38,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'MyNurse',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Des soignants vérifiés, des soins suivis, partout à Abidjan.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  height: 1.35,
                ),
              ),
              const Spacer(flex: 2),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: brandGreen,
                ),
                onPressed: () => go(UserRole.patient),
                child: const Text('Je cherche un soignant'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                ),
                onPressed: () => go(UserRole.pro),
                child: const Text('Je suis professionnel de santé'),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  onPressed: () => go(UserRole.admin),
                  child: const Text('Administration MyNurse'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Connexion par numéro de téléphone puis code SMS.
/// En démo, le code est toujours 123456.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.role});

  final UserRole role;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const demoCode = '123456';

  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _error = null);
    if (!_codeSent) {
      if (_phone.text.length != 10) {
        setState(() => _error = 'Entrez un numéro à 10 chiffres.');
        return;
      }
      setState(() => _codeSent = true);
      return;
    }
    if (_code.text != demoCode) {
      setState(() => _error = 'Code incorrect. Vérifiez le SMS reçu.');
      return;
    }
    final app = AppScope.of(context);
    if (widget.role == UserRole.pro) {
      app.loginPro(_phone.text);
    } else {
      app.login(widget.role, phone: _phone.text);
    }
    Navigator.of(context).popUntil((r) => r.isFirst);
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
              _codeSent ? 'Entrez le code reçu' : 'Votre numéro de téléphone',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _codeSent
                  ? 'Code envoyé par SMS au +225 ${_phone.text}.'
                  : switch (widget.role) {
                      UserRole.pro =>
                        'Connectez-vous ou créez votre compte soignant. '
                            'Démo : ${AppState.demoProPhone} ouvre un compte '
                            'déjà vérifié, tout autre numéro lance '
                            "l'inscription.",
                      UserRole.admin => 'Accès réservé à l’équipe MyNurse.',
                      UserRole.patient => 'Nous vous envoyons un code par SMS pour vous connecter.',
                    },
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            if (!_codeSent)
              TextField(
                key: const ValueKey('phone'),
                controller: _phone,
                autofocus: true,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(
                  labelText: 'Numéro de téléphone',
                  prefixText: '+225  ',
                  hintText: '07 00 00 00 00',
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
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: InputDecoration(
                  labelText: 'Code à 6 chiffres',
                  helperText: 'Mode démo : le code est $demoCode',
                  errorText: _error,
                ),
                onSubmitted: (_) => _submit(),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              child: Text(_codeSent ? 'Se connecter' : 'Recevoir le code'),
            ),
            if (_codeSent)
              TextButton(
                onPressed: () => setState(() {
                  _codeSent = false;
                  _code.clear();
                  _error = null;
                }),
                child: const Text('Modifier le numéro'),
              ),
          ],
        ),
      ),
    );
  }
}
