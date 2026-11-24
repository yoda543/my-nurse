import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'patient/booking_detail.dart';

/// Cloche avec le nombre de notifications non lues.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = AppScope.of(context).unreadCount;
    return IconButton(
      tooltip: unread == 0
          ? 'Notifications'
          : '$unread notification${unread > 1 ? 's' : ''} non lue${unread > 1 ? 's' : ''}',
      onPressed: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: const Icon(Icons.notifications_outlined, size: 28),
      ),
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.myNotifications;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (app.unreadCount > 0)
            TextButton(
              onPressed: () => runAction(context, app.markAllRead),
              child: const Text('Tout marquer comme lu'),
            ),
        ],
      ),
      body: list.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_none,
              text:
                  'Aucune notification pour le moment. Vous serez prévenu à '
                  'chaque étape de vos soins.',
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _NotificationTile(n: list[i]),
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n});

  final AppNotification n;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = n.booking;
    final opensBooking =
        app.role == UserRole.patient &&
        b != null &&
        b.ownerId == app.account?.id;
    return Material(
      color: n.read ? Colors.transparent : const Color(0xFFE8F4F2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: n.read
              ? const Color(0xFFF1ECE2)
              : const Color(0xFFD5EDE9),
          child: Icon(_icon(n.title), color: brandGreen, size: 20),
        ),
        title: Text(
          n.title,
          style: TextStyle(
            fontWeight: n.read ? FontWeight.w500 : FontWeight.w800,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('${n.body}\n${dateTimeLabel(n.at)}'),
        ),
        isThreeLine: true,
        trailing: n.read
            ? (opensBooking ? const Icon(Icons.chevron_right) : null)
            : const Icon(Icons.circle, size: 10, color: brandGreen),
        onTap: () {
          app.markRead(n);
          if (opensBooking) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BookingDetailScreen(booking: b),
              ),
            );
          }
        },
      ),
    );
  }

  static IconData _icon(String title) {
    final t = title.toLowerCase();
    if (t.contains('paiement') ||
        t.contains('recharge') ||
        t.contains('retrait')) {
      return Icons.payments_outlined;
    }
    if (t.contains('annul') ||
        t.contains('expir') ||
        t.contains('sans réponse')) {
      return Icons.event_busy_outlined;
    }
    if (t.contains('compte rendu')) return Icons.description_outlined;
    if (t.contains('note')) return Icons.star_outline_rounded;
    if (t.contains('dossier') ||
        t.contains('vérifié') ||
        t.contains('suspendu')) {
      return Icons.verified_outlined;
    }
    if (t.contains('premium') || t.contains('parrainage')) {
      return Icons.workspace_premium_outlined;
    }
    if (t.contains('alerte')) return Icons.warning_amber_rounded;
    if (t.contains('confirmé')) return Icons.check_circle_outline;
    return Icons.notifications_outlined;
  }
}
