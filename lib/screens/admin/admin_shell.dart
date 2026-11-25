import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../widgets.dart';
import '../notifications.dart';
import 'admin_dashboard.dart';
import 'admin_money.dart';
import 'admin_ops.dart';
import 'admin_people.dart';
import 'admin_platform.dart';
import 'admin_widgets.dart';

/// Les modules de la console, avec la permission qui les ouvre (null :
/// toute l'équipe).
enum AdminModule {
  dashboard('Tableau de bord', Icons.dashboard_outlined, null),
  users(
    'Utilisateurs',
    Icons.manage_accounts_outlined,
    AdminPermission.support,
  ),
  patients('Patients', Icons.personal_injury_outlined, AdminPermission.support),
  pros(
    'Soignants',
    Icons.medical_services_outlined,
    AdminPermission.verifyPros,
  ),
  documents(
    'Vérifications',
    Icons.fact_check_outlined,
    AdminPermission.verifyPros,
  ),
  appointments(
    'Rendez-vous',
    Icons.event_note_outlined,
    AdminPermission.manageBookings,
  ),
  contracts('Suivis réguliers', Icons.repeat, AdminPermission.manageBookings),
  finance('Finances', Icons.account_balance_outlined, AdminPermission.finance),
  commissions('Commissions', Icons.percent, AdminPermission.finance),
  refunds('Remboursements', Icons.undo, AdminPermission.finance),
  subscriptions(
    'Abonnements',
    Icons.workspace_premium_outlined,
    AdminPermission.finance,
  ),
  complaints(
    'Réclamations',
    Icons.support_agent_outlined,
    AdminPermission.support,
  ),
  incidents(
    'Incidents',
    Icons.report_gmailerrorred_outlined,
    AdminPermission.support,
  ),
  pharmacies(
    'Pharmacies',
    Icons.local_pharmacy_outlined,
    AdminPermission.manageSettings,
  ),
  notifications(
    'Messages',
    Icons.campaign_outlined,
    AdminPermission.manageSettings,
  ),
  analytics('Statistiques', Icons.insights_outlined, null),
  logs('Journal d’activité', Icons.history, AdminPermission.auditRead),
  staff(
    'Équipe et droits',
    Icons.admin_panel_settings_outlined,
    AdminPermission.manageStaff,
  );

  const AdminModule(this.label, this.icon, this.permission);

  final String label;
  final IconData icon;
  final AdminPermission? permission;
}

/// Console d'administration : un tableau de bord et un module par métier,
/// chacun ouvert selon les permissions du membre connecté. Navigation
/// latérale sur grand écran, menu sur téléphone.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  AdminModule _module = AdminModule.dashboard;
  Period? _period;

  Period _currentPeriod(AppState app) =>
      _period ?? Period.lastDays(app.now, 30);

  void _open(AdminModule m) => setState(() => _module = m);

  Future<void> _pickPeriod(AppState app) async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in [
              Period.lastDays(app.now, 7),
              Period.lastDays(app.now, 30),
              Period.lastDays(app.now, 90),
              Period.thisMonth(app.now),
            ])
              ListTile(
                title: Text(p.label),
                onTap: () => Navigator.pop(context, p),
              ),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Dates précises…'),
              onTap: () => Navigator.pop(context, 'custom'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice is Period) {
      setState(() => _period = choice);
      return;
    }
    final r = await showDateRangePicker(
      context: context,
      firstDate: app.now.subtract(const Duration(days: 730)),
      lastDate: app.now.add(const Duration(days: 60)),
      initialDateRange: DateTimeRange(
        start: _currentPeriod(app).from,
        end: _currentPeriod(app).to.subtract(const Duration(days: 1)),
      ),
    );
    if (r != null && mounted) {
      setState(
        () => _period = Period(
          r.start,
          DateTime(r.end.year, r.end.month, r.end.day + 1),
          'Du ${r.start.day}/${r.start.month} au ${r.end.day}/${r.end.month}/${r.end.year}',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final period = _currentPeriod(app);
    final visible = [
      for (final m in AdminModule.values)
        if (m.permission == null || app.hasAdminPerm(m.permission!)) m,
    ];
    if (!visible.contains(_module)) _module = AdminModule.dashboard;
    final body = switch (_module) {
      AdminModule.dashboard => AdminDashboard(period: period, onOpen: _open),
      AdminModule.users => const UsersModule(),
      AdminModule.patients => const PatientsModule(),
      AdminModule.pros => const ProsModule(),
      AdminModule.documents => const VerificationModule(),
      AdminModule.appointments => AppointmentsModule(period: period),
      AdminModule.contracts => const ContractsModule(),
      AdminModule.finance => FinanceModule(period: period),
      AdminModule.commissions => CommissionsModule(period: period),
      AdminModule.refunds => RefundsModule(period: period),
      AdminModule.subscriptions => const SubscriptionsModule(),
      AdminModule.complaints => const ComplaintsModule(),
      AdminModule.incidents => const IncidentsModule(),
      AdminModule.pharmacies => const PharmaciesModule(),
      AdminModule.notifications => const BroadcastModule(),
      AdminModule.analytics => AnalyticsModule(period: period),
      AdminModule.logs => LogsModule(period: period),
      AdminModule.staff => const StaffModule(),
    };
    int badge(AdminModule m) => switch (m) {
      AdminModule.documents => app.verificationQueue.length,
      AdminModule.complaints =>
        app.complaints.where((c) => c.status == ComplaintStatus.open).length,
      AdminModule.incidents =>
        app.incidents.where((i) => i.status == 'Envoyé').length,
      _ => 0,
    };
    final periodButton = ActionChip(
      avatar: const Icon(Icons.date_range, size: 18),
      label: Text(period.label),
      tooltip: 'Changer la période',
      onPressed: () => _pickPeriod(app),
    );
    final showPeriod = const {
      AdminModule.dashboard,
      AdminModule.appointments,
      AdminModule.finance,
      AdminModule.commissions,
      AdminModule.refunds,
      AdminModule.analytics,
      AdminModule.logs,
    }.contains(_module);
    final wide = isWide(context);
    final actions = [
      if (showPeriod && wide)
        Padding(padding: const EdgeInsets.only(right: 4), child: periodButton),
      const NotificationBell(),
      IconButton(
        tooltip: 'Se déconnecter',
        onPressed: app.logout,
        icon: const Icon(Icons.logout),
      ),
    ];
    // Téléphone : la période passe sous le titre.
    final periodBar = showPeriod && !wide
        ? PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: periodButton,
              ),
            ),
          )
        : null;
    final menu = ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            'MyNurse Admin',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            app.adminMe?.name ?? 'Équipe MyNurse',
            style: const TextStyle(color: Color(0xFFB9CDD0)),
          ),
        ),
        for (final m in visible)
          ListTile(
            dense: true,
            selected: m == _module,
            selectedTileColor: const Color(0xFF17383D),
            textColor: const Color(0xFFD6E2E4),
            iconColor: const Color(0xFFD6E2E4),
            selectedColor: Colors.white,
            leading: Icon(m.icon),
            title: Text(m.label),
            trailing: badge(m) > 0 ? Badge(label: Text('${badge(m)}')) : null,
            onTap: () {
              _open(m);
              if (!isWide(context)) Navigator.of(context).maybePop();
            },
          ),
      ],
    );
    final content = Column(
      children: [
        const OfflineBanner(),
        Expanded(child: body),
      ],
    );
    if (isWide(context)) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 248,
              child: Material(
                color: adminInk,
                child: SafeArea(child: menu),
              ),
            ),
            Expanded(
              child: Scaffold(
                appBar: AppBar(title: Text(_module.label), actions: actions),
                body: content,
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_module.label),
        actions: actions,
        bottom: periodBar,
      ),
      drawer: Drawer(
        backgroundColor: adminInk,
        child: SafeArea(child: menu),
      ),
      body: content,
    );
  }
}
