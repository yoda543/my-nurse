@Tags(['live'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mynurse/app_state.dart';
import 'package:mynurse/backend/remote.dart';
import 'package:mynurse/config.dart';
import 'package:mynurse/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Parcours complet contre la vraie base, avec des comptes d'essai créés
/// côté serveur : `flutter test test/live_supabase_test.dart --tags live
/// --run-skipped`.
const _password = 'Essai-MyNurse-2026';

Future<AppState> _open(String email) async {
  final client = SupabaseClient(
    supabaseUrl,
    supabaseKey,
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );
  await client.auth.signInWithPassword(email: email, password: _password);
  final app = AppState(remote: RemoteBackend(client));
  await app.restoreSession();
  return app;
}

void main() {
  test('inscription, validation, réservation, paiement, suivi, annulation', () async {
    final pro = await _open('test-pro@mynurse.test');
    final admin = await _open('test-admin@mynurse.test');
    final patient = await _open('test-patient@mynurse.test');
    expect(pro.role, UserRole.pro);
    expect(admin.role, UserRole.admin);
    expect(patient.role, UserRole.patient);
    expect(pro.services, hasLength(8));

    // 1. Le soignant s'inscrit avec ses pièces (petits fichiers d'essai).
    expect(pro.currentPro, isNull);
    final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0]);
    final me = await pro.registerPro(
      name: 'Soignant Essai',
      phone: '',
      type: ProType.infirmier,
      communes: ['Cocody'],
      prices: {'pansement': 8000},
      yearsExperience: 5,
      bio: 'Compte d’essai automatique.',
      orderNumber: 'ESSAI-1',
      nightAvailable: false,
      documents: requiredDocs(ProType.infirmier).toSet(),
      files: {
        for (final d in requiredDocs(ProType.infirmier))
          d: (name: '${d.name}.png', bytes: png),
      },
    );
    expect(me.status, VerificationStatus.pending);
    expect(me.documentPaths, hasLength(5));

    // 2. L'administration voit le dossier, ouvre une pièce et le valide.
    await admin.refresh();
    final dossier = admin.prosWithStatus(VerificationStatus.pending).single;
    expect(dossier.id, me.id);
    final url = await admin.remote!.documentUrl(
      dossier.documentPaths[DocType.cni]!,
    );
    expect(url.toString(), contains('token='));
    await admin.verifyPro(dossier);
    expect(
      admin.prosWithStatus(VerificationStatus.verified).map((p) => p.id),
      contains(me.id),
    );

    // 3. Le patient donne son nom, puis réserve avec sa position GPS.
    expect(patient.needsProfile, isTrue);
    await patient.completeProfile('Patient Essai');
    expect(patient.patients.single.relation, 'Moi');
    expect(patient.wallet.balance, 30000);
    final pansement = patient.services.firstWhere((s) => s.id == 'pansement');
    final soignant = patient.prosFor(pansement, 'Cocody').single;
    final now = DateTime.now();
    final booking = await patient.book(
      service: pansement,
      pro: soignant,
      commune: 'Cocody',
      address: 'Cité Sicogi 1001 logements, Angré, Cocody',
      scheduledAt: DateTime(now.year, now.month, now.day + 1, 10),
      hasPrescription: false,
      location: const GeoPoint(5.3967, -3.989),
    );
    expect(booking.price, 8000);
    expect(booking.status, BookingStatus.pending);
    expect(booking.location!.lat, closeTo(5.3967, 1e-6));

    // 4. Le soignant voit la demande avec le nom du patient et accepte.
    await pro.refresh();
    final request = pro.proRequests.single;
    expect(request.patientName, 'Patient Essai');
    await pro.respond(request, accept: true);
    expect(pro.proBookings(BookingStatus.accepted), hasLength(1));

    // 5. Le patient paie avec son solde ; Mobile Money n'est pas encore ouvert.
    await patient.refresh();
    final toPay = patient.patientBookings.first;
    expect(toPay.awaitingPayment, isTrue);
    expect(
      () => patient.pay(toPay, PaymentMethod.wave),
      throwsA(isA<BusinessRuleError>()),
    );
    expect(await patient.pay(toPay, PaymentMethod.wallet), isTrue);
    expect(patient.wallet.balance, 22000);
    expect(patient.patientBookings.first.readyForCare, isTrue);

    // 6. Compte rendu trop tôt : refusé.
    await pro.refresh();
    final ready = pro.proBookings(BookingStatus.accepted).single;
    expect(pro.canLogCare(ready), isFalse);

    // 7. Annulation par le patient plus de 2 h avant : remboursement complet.
    await patient.cancel(patient.patientBookings.first);
    expect(patient.wallet.balance, 30000);

    // 8. Suivi de 3 séances : accepté et payé en une fois, commission 10 %.
    final contract = await patient.bookContract(
      service: pansement,
      pro: soignant,
      commune: 'Cocody',
      address: 'Cité Sicogi 1001 logements, Angré, Cocody',
      firstAt: DateTime(now.year, now.month, now.day + 2, 15),
      frequency: Frequency.daily,
      sessions: 3,
      hasPrescription: false,
    );
    expect(contract.sessions, hasLength(3));
    expect(contract.sessions.first.commission, 800);
    await pro.refresh();
    expect(pro.proRequests.where((b) => b.contract != null), hasLength(1));
    await pro.respond(
      pro.proRequests.firstWhere((b) => b.contract != null),
      accept: true,
    );
    await patient.refresh();
    final session = patient.patientBookings.firstWhere(
      (b) => b.contract != null,
    );
    expect(patient.amountDue(session), 24000);
    expect(await patient.pay(session, PaymentMethod.wallet), isTrue);
    expect(patient.wallet.balance, 6000);

    // 9. Le soignant annule le suivi : remboursement complet, annulation comptée.
    await pro.refresh();
    final accepted = pro
        .proBookings(BookingStatus.accepted)
        .firstWhere((b) => b.contract != null);
    await pro.cancelByPro(accepted, 'Essai automatique');
    await patient.refresh();
    expect(patient.wallet.balance, 30000);

    // 10. Premium refusé sans solde ; l'administration voit les totaux.
    expect(
      () => pro.subscribePremium(pro.currentPro!),
      throwsA(isA<BusinessRuleError>()),
    );
    await admin.refresh();
    expect(admin.clientBalances, 30000);
    expect(
      admin.pros.firstWhere((p) => p.id == me.id).cancellations,
      hasLength(1),
    );

    // Nettoyage des fichiers d'essai (le reste est supprimé côté serveur).
    await pro.remote!.client.storage
        .from('pro-documents')
        .remove(me.documentPaths.values.toList());
  }, timeout: const Timeout(Duration(minutes: 2)));
}
