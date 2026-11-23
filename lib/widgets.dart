import 'package:material_ui/material_ui.dart';

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
          Text(
            'Vérifié MyNurse',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: brandGreen,
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
        Text(
          ' · ${pro.careCount} soins',
          style: const TextStyle(color: Colors.black54),
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
              if (forPro && b.patient.allergies.isNotEmpty)
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
