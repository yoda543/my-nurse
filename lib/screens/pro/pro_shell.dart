import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../widgets.dart';
import 'agenda.dart';
import 'earnings.dart';
import 'pro_onboarding.dart';
import 'profile.dart';
import 'requests.dart';
import 'today.dart';
import 'verification.dart';

/// Espace soignant, pensé pour le téléphone : 5 onglets, l'essentiel en un
/// geste. Tant que le compte n'est pas vérifié (ou qu'une pièce a expiré),
/// seul l'écran de vérification s'affiche : aucune demande n'arrive.
class ProShell extends StatefulWidget {
  const ProShell({super.key});

  @override
  State<ProShell> createState() => _ProShellState();
}

class _ProShellState extends State<ProShell> {
  int _tab = 0;

  void _go(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pro = app.currentPro;
    if (pro == null) return const ProOnboardingScreen();
    if (!pro.activeAt(app.now)) return const VerificationScreen(gate: true);
    final pending = app.proRequests.length;
    final body = switch (_tab) {
      0 => ProTodayTab(
        onOpenRequests: () => _go(1),
        onOpenAgenda: () => _go(2),
        onOpenEarnings: () => _go(3),
      ),
      1 => const ProRequestsTab(),
      2 => const ProAgendaTab(),
      3 => const ProEarningsTab(),
      _ => const ProProfileTab(),
    };
    final destinations = [
      (Icons.today_outlined, Icons.today, 'Accueil', 0),
      (Icons.inbox_outlined, Icons.inbox, 'Demandes', pending),
      (Icons.calendar_month_outlined, Icons.calendar_month, 'Agenda', 0),
      (
        Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet,
        'Revenus',
        0,
      ),
      (Icons.person_outline, Icons.person, 'Profil', 0),
    ];
    Widget badge(IconData icon, int n) =>
        Badge(isLabelVisible: n > 0, label: Text('$n'), child: Icon(icon));
    if (isWide(context)) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _tab,
                onDestinationSelected: _go,
                labelType: NavigationRailLabelType.all,
                backgroundColor: Colors.white,
                destinations: [
                  for (final d in destinations)
                    NavigationRailDestination(
                      icon: badge(d.$1, d.$4),
                      selectedIcon: badge(d.$2, d.$4),
                      label: Text(d.$3),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: ContentWidth(maxWidth: 900, child: body)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: badge(d.$1, d.$4),
              selectedIcon: badge(d.$2, d.$4),
              label: d.$3,
            ),
        ],
      ),
    );
  }
}
