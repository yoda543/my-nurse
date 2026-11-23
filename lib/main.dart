import 'dart:async';

import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'backend/remote.dart';
import 'config.dart';
import 'models.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/email_login.dart';
import 'screens/patient/patient_shell.dart';
import 'screens/pro/pro_shell.dart';
import 'screens/welcome.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  RemoteBackend? remote;
  if (!demoMode) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
    remote = RemoteBackend(Supabase.instance.client);
  }
  final state = AppState(remote: remote);
  if (remote != null) {
    try {
      await state.restoreSession();
    } catch (_) {
      // Pas de réseau ou session expirée : l'accueil s'affiche.
    }
    // Les délais sont vérifiés par le serveur ; l'app se met à jour.
    Timer.periodic(const Duration(seconds: 30), (_) {
      state.refresh().catchError((_) {});
    });
  } else {
    // Démo : délais de réponse et de paiement vérifiés chaque minute.
    Timer.periodic(const Duration(minutes: 1), (_) => state.expireStale());
  }
  runApp(MyNurseApp(state: state));
}

class MyNurseApp extends StatelessWidget {
  const MyNurseApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'MyNurse',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // Sur un grand écran (démo web sur PC, tablette), l'app garde une
        // largeur de téléphone, centrée : lignes lisibles, boutons à portée.
        builder: (context, child) => ColoredBox(
          color: brandSand,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxAppWidth),
              child: child,
            ),
          ),
        ),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.needsProfile) return const ProfileNameScreen();
    return switch (app.role) {
      null => const WelcomeScreen(),
      UserRole.patient => const PatientShell(),
      UserRole.pro => const ProShell(),
      UserRole.admin => const AdminShell(),
    };
  }
}
