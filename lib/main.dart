import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'models.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/patient/patient_shell.dart';
import 'screens/pro/pro_shell.dart';
import 'screens/welcome.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  runApp(MyNurseApp(state: AppState()));
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
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    return switch (AppScope.of(context).role) {
      null => const WelcomeScreen(),
      UserRole.patient => const PatientShell(),
      UserRole.pro => const ProShell(),
      UserRole.admin => const AdminShell(),
    };
  }
}
