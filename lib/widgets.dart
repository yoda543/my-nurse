import 'package:material_ui/material_ui.dart';

import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'format.dart';
import 'models.dart';
import 'theme.dart';

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFD5EDE9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, size: 14, color: brandGreen),
          SizedBox(width: 4),
          Flexible(
            child: Text(
              'Vérifié MyNurse',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: brandGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProAvatar extends StatelessWidget {
  const ProAvatar(this.pro, {super.key, this.radius = 26});

  final Pro pro;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final parts = pro.name
        .replaceFirst('Dr ', '')
        .split(' ')
        .where((e) => e.isNotEmpty);
    final initials = parts.take(2).map((e) => e[0]).join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: brandGreen,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}

class RatingLine extends StatelessWidget {
  const RatingLine(this.pro, {super.key});

  final Pro pro;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 18, color: Color(0xFFE8A317)),
        const SizedBox(width: 2),
        Text(
          pro.rating.toStringAsFixed(1).replaceAll('.', ','),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Flexible(
          child: Text(
            ' · ${pro.careCount} soins',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      ],
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      BookingStatus.pending => (
        const Color(0xFFFFF1D6),
        const Color(0xFF8A5A00),
      ),
      BookingStatus.accepted => (const Color(0xFFD5EDE9), brandGreen),
      BookingStatus.done => (const Color(0xFFE4E8EA), brandInk),
      BookingStatus.refused || BookingStatus.cancelled => (
        const Color(0xFFFBE0DA),
        const Color(0xFF9C2B12),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Carte résumant une réservation (côté patient ou soignant).
class BookingCard extends StatelessWidget {
  const BookingCard({
    super.key,
    required this.booking,
    required this.forPro,
    this.onTap,
    this.footer,
  });

  final Booking booking;
  final bool forPro;
  final VoidCallback? onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      b.service.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(b.status),
                ],
              ),
              const SizedBox(height: 8),
              if (forPro)
                _line(Icons.person_outline, b.patientName)
              else ...[
                _line(Icons.person_outline, 'Pour ${b.patientName}'),
                _line(
                  Icons.medical_services_outlined,
                  '${b.pro.name} · ${b.pro.type.label}',
                ),
              ],
              if (forPro && b.location != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.my_location,
                        size: 18,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Position GPS partagée')),
                      TextButton.icon(
                        onPressed: () => launchUrl(
                          b.location!.directionsUrl,
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.directions, size: 18),
                        label: const Text('Itinéraire'),
                      ),
                    ],
                  ),
                ),
              if (forPro &&
                  b.patient.allergies.isNotEmpty &&
                  AppScope.of(context).proCanSeeRecord(b))
                _line(
                  Icons.warning_amber_rounded,
                  'Allergies : ${b.patient.allergies}',
                ),
              _line(Icons.event_outlined, dateTimeLabel(b.scheduledAt)),
              if (b.sessionLabel case final label?) _line(Icons.repeat, label),
              _line(Icons.place_outlined, '${b.commune} · ${b.address}'),
              _line(
                Icons.payments_outlined,
                forPro
                    ? '${fcfa(b.proEarnings)} pour vous'
                    : '${fcfa(b.price)}${b.night ? ' (majoration de nuit)' : ''}',
              ),
              if (paymentLabel(b) case final label?)
                _line(Icons.account_balance_wallet_outlined, label),
              if (footer != null) ...[const SizedBox(height: 12), footer!],
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

/// Où en est l'argent du soin, en une ligne.
String? paymentLabel(Booking b) {
  if (b.refunded) return 'Remboursé sur le solde MyNurse';
  if (b.status == BookingStatus.cancelled && b.cancelReason.isNotEmpty) {
    return b.cancelReason;
  }
  if (b.awaitingPayment) return 'En attente du paiement';
  if (b.readyForCare) {
    return 'Payé (${b.paymentMethod!.label}), bloqué jusqu’à la fin du soin';
  }
  if (b.status == BookingStatus.done && b.paid) {
    return 'Payé (${b.paymentMethod!.label}), reversé au soignant';
  }
  return null;
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
    ),
  );
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.icon,
    required this.text,
    this.warning = false,
  });

  final IconData icon;
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final bg = warning ? const Color(0xFFFFF1D6) : const Color(0xFFD5EDE9);
    final fg = warning ? const Color(0xFF6B4500) : brandInk;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: fg, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

/// État de la détection de position, sous le choix de la commune.
class LocationStatus extends StatelessWidget {
  const LocationStatus({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final place = app.place;
    final (IconData icon, String text) = app.locating
        ? (Icons.my_location, 'Localisation en cours…')
        : app.locationError != null
        ? (Icons.location_off_outlined, app.locationError!)
        : place != null
        ? (
            Icons.my_location,
            place.simulated
                ? 'Position de démonstration : ${place.address}'
                : 'Vous êtes à ${place.address}',
          )
        : (Icons.location_searching, 'Position non détectée');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: brandGreen),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
        if (!app.locating && (app.locationError != null || place == null))
          InkWell(
            onTap: onRetry,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Réessayer',
                style: TextStyle(
                  color: brandGreen,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Lance une action et affiche la raison d'un éventuel refus.
/// Renvoie true si l'action a réussi.
Future<bool> runAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  void show(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));
  try {
    await action();
    return true;
  } on BusinessRuleError catch (e) {
    show(e.message);
  } on ArgumentError catch (e) {
    show('${e.message}');
  } on StateError catch (e) {
    show(e.message);
  } catch (_) {
    show('Connexion impossible. Vérifiez votre réseau et réessayez.');
  }
  return false;
}

/// Limite la largeur du contenu sur tablette et ordinateur, centré.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    // Prend la hauteur de son contenu (sinon, en barre du bas, il couvrirait
    // tout l'écran).
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Écran large (tablette, ordinateur) : navigation latérale, deux colonnes.
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 840;

/// Bandeau affiché quand le serveur ne répond pas : les données gardées en
/// mémoire restent visibles, et on peut réessayer.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _trying = false;

  Future<void> _retry() async {
    setState(() => _trying = true);
    final app = AppScope.of(context);
    final ok = await app.retrySync();
    if (!mounted) return;
    setState(() => _trying = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Connexion rétablie, données à jour.' : 'Toujours pas de connexion. Nouvel essai automatique dans 30 s.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.offline) return const SizedBox.shrink();
    final since = app.lastSync == null
        ? ''
        : ' Données du ${dateTimeLabel(app.lastSync!)}.';
    return Material(
      color: const Color(0xFFFFF1D6),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.wifi_off_rounded, color: Color(0xFF6B4500)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Connexion instable.$since Vos actions seront possibles '
                  'dès le retour du réseau.',
                  style: const TextStyle(color: Color(0xFF6B4500)),
                ),
              ),
              _trying
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      onPressed: _retry,
                      child: const Text('Réessayer'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bouton d'action : se désactive et montre un indicateur pendant l'envoi
/// (pas de double envoi sur un réseau lent), affiche la raison d'un refus,
/// et un message de réussite s'il y en a un.
class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.success,
    this.icon,
    this.outlined = false,
    this.danger = false,
    this.onDone,
  });

  final String label;

  /// null : bouton désactivé.
  final Future<void> Function()? onPressed;
  final String? success;
  final IconData? icon;
  final bool outlined;
  final bool danger;
  final VoidCallback? onDone;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await runAction(context, widget.onPressed!);
    if (mounted) setState(() => _busy = false);
    if (!ok) return;
    if (widget.success != null) {
      messenger.showSnackBar(SnackBar(content: Text(widget.success!)));
    }
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed == null || _busy ? null : _run;
    final child = _busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(widget.label, textAlign: TextAlign.center)),
            ],
          );
    final danger = widget.danger ? Theme.of(context).colorScheme.error : null;
    return widget.outlined
        ? OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: danger),
            onPressed: onPressed,
            child: child,
          )
        : FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: onPressed,
            child: child,
          );
  }
}

/// Titre de section dans une page (plus petit que [SectionTitle]).
class BlockTitle extends StatelessWidget {
  const BlockTitle(this.text, {super.key, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        ?action,
      ],
    ),
  );
}

/// Avancement d'un soin en 4 étapes : demandé, confirmé, payé, réalisé.
class CareSteps extends StatelessWidget {
  const CareSteps({super.key, required this.booking});

  final Booking booking;

  static const labels = ['Demandé', 'Confirmé', 'Payé', 'Réalisé'];

  /// Nombre d'étapes franchies (0 à 4), ou -1 si le soin est arrêté.
  static int reached(Booking b) => switch (b.status) {
    BookingStatus.refused || BookingStatus.cancelled => -1,
    BookingStatus.pending => 1,
    BookingStatus.accepted => b.paid ? 3 : 2,
    BookingStatus.done => 4,
  };

  @override
  Widget build(BuildContext context) {
    final n = reached(booking);
    if (n == -1) {
      return Row(
        children: [
          const Icon(Icons.cancel_outlined, color: Color(0xFF9C2B12), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${booking.status.label}${booking.cancelReason.isEmpty ? '' : ' · ${booking.cancelReason}'}',
              style: const TextStyle(color: Color(0xFF9C2B12)),
            ),
          ),
        ],
      );
    }
    return Semantics(
      label: 'Avancement : ${labels[n - 1].toLowerCase()}',
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < labels.length - 1 ? 6 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: i < n ? brandGreen : const Color(0xFFD9D3C5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: i == n - 1 ? FontWeight.w700 : null,
                        color: i < n ? brandInk : Colors.black45,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ce qu'il se passe ensuite pour ce soin, en une phrase.
String nextStepText(Booking b, DateTime now) => switch (b.status) {
  BookingStatus.pending =>
    '${b.pro.name} doit répondre avant ${timeLabel(b.responseDeadline)}.',
  BookingStatus.accepted when b.onTheWay => '${b.pro.name} est en route.',
  BookingStatus.accepted when b.arrivedAt != null =>
    '${b.pro.name} est arrivé(e) à ${timeLabel(b.arrivedAt!)}. Soin en cours.',
  BookingStatus.accepted when !b.paid =>
    'Confirmé. À payer avant ${timeLabel(b.paymentDeadline!)}.',
  BookingStatus.accepted when now.isBefore(b.scheduledAt) =>
    'Payé. ${b.pro.name} viendra le ${dateTimeLabel(b.scheduledAt)}.',
  BookingStatus.accepted => 'Soin en cours. Le compte rendu arrive à la fin.',
  BookingStatus.done => 'Soin réalisé. Le compte rendu est disponible.',
  BookingStatus.refused => 'Le soignant n’était pas disponible.',
  BookingStatus.cancelled => 'Soin annulé.',
};
