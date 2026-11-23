import 'package:material_ui/material_ui.dart';

import '../../app_state.dart';
import '../../format.dart';
import '../../models.dart';
import '../../widgets.dart';
import 'payment_screen.dart';

class BookingDetailScreen extends StatelessWidget {
  const BookingDetailScreen({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final b = booking;
    final log = b.careLog;
    final canCancel =
        b.status == BookingStatus.pending || b.status == BookingStatus.accepted;
    return Scaffold(
      appBar: AppBar(title: const Text('Détail du soin')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          BookingCard(booking: b, forPro: false),
          if (b.status == BookingStatus.pending) ...[
            const SizedBox(height: 16),
            InfoBanner(
              icon: Icons.hourglass_top_rounded,
              text:
                  '${b.pro.name} doit confirmer votre demande. Vous payerez '
                  'ensuite, avant le soin.',
            ),
          ],
          if (b.awaitingPayment) ...[
            const SizedBox(height: 16),
            InfoBanner(
              icon: Icons.check_circle_outline,
              text:
                  '${b.pro.name} a confirmé. Payez pour valider le '
                  'rendez-vous.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PaymentScreen(booking: b)),
              ),
              child: Text('Payer ${fcfa(b.price)}'),
            ),
          ],
          if (log != null) ...[
            const SizedBox(height: 20),
            const Text(
              'Compte rendu du soin',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            CareLogCard(log: log),
          ],
          if (b.status == BookingStatus.done) ...[
            const SizedBox(height: 20),
            if (b.rating == null)
              _RatingForm(booking: b)
            else
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFE8A317),
                  ),
                  title: Text('Votre note : ${b.rating}/5'),
                  subtitle: b.review.isEmpty ? null : Text(b.review),
                ),
              ),
          ],
          if (canCancel) ...[
            const SizedBox(height: 20),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Annuler ce soin ?'),
                    content: Text(
                      '${b.pro.name} sera prévenu(e).'
                      '${b.paid ? ' Vous serez remboursé de ${fcfa(b.price)} '
                                'sur votre compte ${b.paymentMethod!.label}.' : ''}',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Garder le soin'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Annuler le soin'),
                      ),
                    ],
                  ),
                );
                if (ok == true) app.cancel(b);
              },
              child: const Text('Annuler le soin'),
            ),
          ],
        ],
      ),
    );
  }
}

class CareLogCard extends StatelessWidget {
  const CareLogCard({super.key, required this.log});

  final CareLog log;

  @override
  Widget build(BuildContext context) {
    final vitals = [
      if (log.bloodPressure.isNotEmpty) 'Tension ${log.bloodPressure}',
      if (log.temperature.isNotEmpty) 'Température ${log.temperature} °C',
      if (log.pulse.isNotEmpty) 'Pouls ${log.pulse}/min',
      if (log.glycemia.isNotEmpty) 'Glycémie ${log.glycemia} g/L',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Arrivée ${timeLabel(log.arrivedAt)} · '
              'Départ ${timeLabel(log.leftAt)}',
              style: const TextStyle(color: Colors.black54),
            ),
            if (vitals.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final v in vitals) Chip(label: Text(v))],
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Actes réalisés',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(log.acts),
            if (log.observations.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Observations',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(log.observations),
            ],
          ],
        ),
      ),
    );
  }
}

class _RatingForm extends StatefulWidget {
  const _RatingForm({required this.booking});

  final Booking booking;

  @override
  State<_RatingForm> createState() => _RatingFormState();
}

class _RatingFormState extends State<_RatingForm> {
  int _stars = 0;
  final _review = TextEditingController();

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notez ${widget.booking.pro.name}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: '$i sur 5',
                    onPressed: () => setState(() => _stars = i),
                    icon: Icon(
                      i <= _stars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: const Color(0xFFE8A317),
                      size: 34,
                    ),
                  ),
              ],
            ),
            TextField(
              controller: _review,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Votre avis (facultatif)',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _stars == 0
                  ? null
                  : () =>
                        AppScope.of(context)
                            .rate(widget.booking, _stars, _review.text.trim()),
              child: const Text('Envoyer ma note'),
            ),
          ],
        ),
      ),
    );
  }
}
