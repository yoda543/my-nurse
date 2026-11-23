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
                  '${b.pro.name} a jusqu’à ${dateTimeLabel(b.responseDeadline)} '
                  'pour confirmer. Sans réponse, la demande est annulée et vous '
                  'pouvez choisir un autre soignant.',
            ),
          ],
          if (b.awaitingPayment) ...[
            const SizedBox(height: 16),
            InfoBanner(
              icon: Icons.check_circle_outline,
              text:
                  '${b.pro.name} a confirmé. Payez avant '
                  '${dateTimeLabel(b.paymentDeadline!)}, sinon le rendez-vous '
                  'est annulé.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PaymentScreen(booking: b)),
              ),
              child: Text(
                b.contract == null
                    ? 'Payer ${fcfa(app.amountDue(b))}'
                    : 'Payer le suivi : ${fcfa(app.amountDue(b))}',
              ),
            ),
          ],
          if (b.contract != null) ...[
            const SizedBox(height: 16),
            _ContractSummary(contract: b.contract!),
          ],
          if (b.receiptNumber != null) ...[
            const SizedBox(height: 20),
            _Receipt(booking: b),
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
                final q = app.cancellationQuote(b);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(
                      q.sessions > 1
                          ? 'Annuler les ${q.sessions} séances restantes ?'
                          : 'Annuler ce soin ?',
                    ),
                    content: Text(
                      [
                        '${b.pro.name} sera prévenu(e).',
                        if (q.refund > 0)
                          '${fcfa(q.refund)} reviennent tout de suite sur '
                              'votre solde MyNurse.',
                        if (q.fee > 0)
                          'Annulation à moins de '
                              '${freeCancellationWindow.inHours} h du soin : '
                              '${fcfa(q.fee)} sont versés au soignant, qui '
                              's’était libéré pour vous.',
                        if (q.fee == 0 && q.refund > 0)
                          'Annulation gratuite : plus de '
                              '${freeCancellationWindow.inHours} h avant le '
                              'soin.',
                      ].join(' '),
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
                if (ok == true && context.mounted) {
                  await runAction(context, () => app.cancel(b));
                }
              },
              child: Text(
                b.contract == null ? 'Annuler le soin' : 'Annuler le suivi',
              ),
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
                  : () => runAction(
                      context,
                      () => AppScope.of(context)
                          .rate(widget.booking, _stars, _review.text.trim()),
                    ),
              child: const Text('Envoyer ma note'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContractSummary extends StatelessWidget {
  const _ContractSummary({required this.contract});

  final Contract contract;

  @override
  Widget build(BuildContext context) {
    final c = contract;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Suivi régulier',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${c.sessions.length} séances, ${c.frequency.label.toLowerCase()}, '
              'du ${dateTimeLabel(c.start)} au ${dateTimeLabel(c.end)}.',
            ),
            const SizedBox(height: 4),
            Text(
              '${c.doneCount} séance${c.doneCount > 1 ? 's' : ''} réalisée'
              '${c.doneCount > 1 ? 's' : ''} · total ${fcfa(c.total)}',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reçu du soin, pour le patient et sa comptabilité.
class _Receipt extends StatelessWidget {
  const _Receipt({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    Widget row(String l, String v, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(l)),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null)),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined),
                const SizedBox(width: 8),
                Text(
                  'Reçu ${b.receiptNumber}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('${b.service.name} · ${b.pro.name} (${b.pro.type.label})'),
            Text('Pour ${b.patientName} · ${dateTimeLabel(b.scheduledAt)}'),
            const Divider(height: 20),
            row('Prix du soin', fcfa(b.basePrice)),
            if (b.night) row('Majoration de nuit', fcfa(b.price - b.basePrice)),
            row('Total payé', fcfa(b.price), bold: true),
            if (b.paymentMethod != null)
              row('Moyen de paiement', b.paymentMethod!.label),
          ],
        ),
      ),
    );
  }
}
