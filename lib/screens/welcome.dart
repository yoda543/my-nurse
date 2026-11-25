import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'email_login.dart';

/// Ouvre l'écran de connexion adapté au mode de l'app.
/// [role] null : connexion à un compte existant ; sinon création d'un compte.
void openLogin(BuildContext context, UserRole? role) {
  final remote = AppScope.of(context).isRemote;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          remote ? EmailLoginScreen(role: role) : LoginScreen(role: role),
    ),
  );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                onPressed: () => openLogin(context, null),
                child: const Text('Se connecter'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountTypeScreen()),
                ),
                child: const Text('Créer un compte'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Création de compte : patient (ou proche) ou professionnel de santé.
class AccountTypeScreen extends StatelessWidget {
  const AccountTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget choice(IconData icon, String title, String text, UserRole role) =>
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openLogin(context, role),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFFD5EDE9),
                    child: Icon(icon, color: brandGreen, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          text,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Créer un compte',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choisissez le type de compte.',
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 24),
          choice(
            Icons.family_restroom,
            'Je cherche un soignant',
            'Pour moi ou pour un proche, même depuis l’étranger.',
            UserRole.patient,
          ),
          const SizedBox(height: 12),
          choice(
            Icons.medical_services_outlined,
            'Je suis professionnel de santé',
            'Infirmier, aide-soignant, médecin, kiné ou sage-femme.',
            UserRole.pro,
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: () => openLogin(context, null),
              child: const Text('J’ai déjà un compte : me connecter'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Démo : numéro de téléphone puis code SMS (toujours 123456).
/// [role] null : connexion à un compte existant ; sinon création.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.role});

  final UserRole? role;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const demoCode = '123456';

  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  String? _error;

  bool get _creating => widget.role != null;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final app = AppScope.of(context);
    setState(() => _error = null);
    if (!_codeSent) {
      if (_phone.text.length != 10) {
        setState(() => _error = 'Entrez un numéro à 10 chiffres.');
        return;
      }
      final exists = app.demoAccountExists(_phone.text);
      if (!_creating && !exists) {
        setState(
          () => _error =
              'Aucun compte avec ce numéro. Vérifiez-le ou créez un compte.',
        );
        return;
      }
      if (_creating && exists) {
        setState(() => _error = 'Ce numéro a déjà un compte. Connectez-vous.');
        return;
      }
      setState(() => _codeSent = true);
      return;
    }
    if (_code.text != demoCode) {
      setState(() => _error = 'Code incorrect. Vérifiez le SMS reçu.');
      return;
    }
    try {
      if (_creating) {
        app.signUpDemo(_phone.text, widget.role!);
      } else {
        app.loginDemo(_phone.text);
      }
    } on BusinessRuleError catch (e) {
      setState(() => _error = e.message);
      return;
    }
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final title = _codeSent
        ? 'Entrez le code reçu'
        : _creating
        ? 'Votre numéro de téléphone'
        : 'Connexion';
    final subtitle = _codeSent
        ? 'Code envoyé par SMS au +225 ${_phone.text}.'
        : switch (widget.role) {
            null => 'Entrez le numéro de votre compte MyNurse.',
            UserRole.pro =>
              'Votre numéro servira à vous connecter à votre espace soignant.',
            _ => 'Votre numéro servira à vous connecter. Pas de mot de passe.',
          };
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
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
            if (!_creating && !_codeSent) ...[
              const SizedBox(height: 24),
              const _DemoAccounts(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Démo : rappel des comptes prêts à l'emploi.
class _DemoAccounts extends StatelessWidget {
  const _DemoAccounts();

  @override
  Widget build(BuildContext context) {
    Widget line(String who, String phone) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text(who)),
          SelectableText(
            phone,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFD5EDE9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Comptes de démonstration',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          line('Patiente (Awa Bamba)', '07 00 00 00 00'),
          line('Infirmière (Aya Kouamé)', '05 00 00 00 00'),
          line('Infirmière en attente', '01 01 01 01 01'),
          line('Administration (tous droits)', '01 00 00 00 00'),
          line('Agent support', '01 00 00 00 02'),
          line('Médecin coordinateur', '01 00 00 00 03'),
          const SizedBox(height: 8),
          const Text(
            'Les comptes créés pendant la visite restent disponibles jusqu’au '
            'rechargement de la page.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
