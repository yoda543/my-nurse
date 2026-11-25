part of '../app_state.dart';

/// Espace soignant : vérification, disponibilités, soins et tarifs,
/// journal de visite, constantes, accès autorisé au dossier, suivi des
/// patients, revenus, réputation, incidents.
///
/// Mêmes règles qu'au serveur (migrations 0010 à 0012) : l'app guide, le
/// serveur fait respecter.
extension ProFeatures on AppState {
  Pro get _me {
    final p = currentPro;
    if (p == null) {
      throw const BusinessRuleError('Compte soignant introuvable.');
    }
    return p;
  }

  /// En ligne, sans les tables de l'espace soignant sur le serveur : on
  /// l'explique au lieu d'échouer.
  void _requireServer({bool workspace = false}) {
    final r = remote;
    if (r == null) return;
    if (!r.hasFamilyTables || (workspace && !r.hasProTables)) {
      throw const BusinessRuleError(
        'Cette fonction arrive avec la prochaine mise à jour du serveur '
        'MyNurse. Vos demandes et vos soins fonctionnent normalement.',
      );
    }
  }

  void _requireActive() {
    if (!_me.activeAt(now)) {
      throw BusinessRuleError(
        'Action impossible : ${_me.statusAt(now).label.toLowerCase()}. '
        '${_me.statusAt(now).help}',
      );
    }
  }

  // =========================================================== vérification
  /// Le soignant dépose des pièces (manquantes, refusées ou expirées).
  /// Dossier complet : il repart en vérification.
  Future<void> submitProDocuments(
    Map<DocType, DateTime?> docs, {
    Map<DocType, PickedFile> files = const {},
  }) async {
    final p = _me;
    if (docs.isEmpty) {
      throw const BusinessRuleError('Ajoutez au moins une pièce.');
    }
    for (final e in docs.entries) {
      if (e.value != null && !e.value!.isAfter(now)) {
        throw BusinessRuleError(
          '${e.key.label} : cette pièce est déjà expirée.',
        );
      }
    }
    if (remote != null) {
      return _online((r) async {
        await r.uploadDocuments(files, expiry: docs);
        await r.submitProDossier();
      });
    }
    final before = p.statusAt(now);
    for (final e in docs.entries) {
      p.documents.add(e.key);
      if (e.value != null) {
        p.documentExpiry[e.key] = e.value!;
      } else {
        p.documentExpiry.remove(e.key);
      }
    }
    final complete = p.missingDocs.isEmpty;
    if (!complete) {
      p.status = VerificationStatus.incomplete;
    } else if (before == VerificationStatus.expired) {
      // Renouvellement : un vérificateur contrôle la nouvelle pièce.
      p.status = VerificationStatus.underReview;
    } else if (const [
      VerificationStatus.incomplete,
      VerificationStatus.rejected,
    ].contains(before)) {
      p.status = VerificationStatus.pending;
      p.rejectionReason = '';
    }
    if (complete && before != p.status) {
      _notify(
        'admin',
        before == VerificationStatus.expired
            ? 'Pièce renouvelée à contrôler'
            : 'Dossier complet à vérifier',
        '${p.name}, ${p.type.label}.',
      );
    }
    _changed();
  }

  /// Dossiers à traiter par les vérificateurs : nouveaux, en examen, et
  /// pièces renouvelées.
  List<Pro> get verificationQueue => pros
      .where(
        (p) =>
            p.status == VerificationStatus.pending ||
            p.status == VerificationStatus.underReview,
      )
      .toList();

  /// Administration : un vérificateur prend le dossier.
  Future<void> startReview(Pro p) async {
    if (p.status != VerificationStatus.pending) return;
    _checkAdmin(AdminPermission.verifyPros);
    if (remote != null) return _online((r) => r.startReview(p.id));
    _adminLog('Examen commencé', p.name);
    p.status = VerificationStatus.underReview;
    _notify(
      p.id,
      'Dossier en cours d’examen',
      'Un vérificateur MyNurse contrôle vos pièces. Il peut vous appeler.',
    );
    _changed();
  }

  // ======================================================== disponibilités
  void _checkAvailability(Pro pro, DateTime start, DateTime end) {
    for (final off in pro.daysOff) {
      if (overlaps(start, end, off.from, off.to)) {
        throw BusinessRuleError(
          '${pro.name} n’est pas disponible ce jour-là. Choisissez une autre '
          'date ou un autre soignant.',
        );
      }
    }
    if (pro.availability.isNotEmpty &&
        !pro.availability.any((r) => r.covers(start, end))) {
      throw BusinessRuleError(
        'Ce créneau est en dehors des disponibilités de ${pro.name} '
        '(${availabilitySummary(pro)}).',
      );
    }
  }

  /// Disponibilités en clair (« lun.–ven. 8 h – 18 h »).
  String availabilitySummary(Pro p) {
    if (p.availability.isEmpty) return 'tous les jours, à la demande';
    return [
      for (final r in p.availability)
        '${weekdayNames[r.weekday - 1].substring(0, 3).toLowerCase()}. ${r.label}',
    ].join(', ');
  }

  Future<void> setAvailability(List<AvailabilityRule> rules) async {
    _requireServer();
    final p = _me;
    for (final r in rules) {
      if (r.endMinute <= r.startMinute) {
        throw BusinessRuleError(
          '${weekdayNames[r.weekday - 1]} : l’heure de fin doit suivre '
          'l’heure de début.',
        );
      }
    }
    if (remote != null) return _online((r) => r.setAvailability(rules));
    p.availability
      ..clear()
      ..addAll(rules);
    _changed();
  }

  /// Disponible aujourd'hui ? (raccourci du tableau de bord).
  bool get availableToday {
    final p = currentPro;
    if (p == null) return false;
    final day = DateTime(now.year, now.month, now.day);
    return !p.daysOff.any(
      (o) => overlaps(day, day.add(const Duration(days: 1)), o.from, o.to),
    );
  }

  Future<void> setAvailableToday(bool available) async {
    _requireServer();
    final p = _me;
    final day = DateTime(now.year, now.month, now.day);
    final end = day.add(const Duration(days: 1));
    if (!available) {
      final busy = bookings.where(
        (b) =>
            b.pro == p &&
            b.status == BookingStatus.accepted &&
            overlaps(day, end, b.scheduledAt, b.endsAt),
      );
      if (busy.isNotEmpty) {
        throw BusinessRuleError(
          'Vous avez ${busy.length} soin${busy.length > 1 ? 's' : ''} '
          'confirmé${busy.length > 1 ? 's' : ''} aujourd’hui. Annulez-les '
          'd’abord si vous ne pouvez pas venir.',
        );
      }
    }
    if (remote != null) {
      return _online((r) => r.setDayOff(day, end, !available));
    }
    if (available) {
      p.daysOff.removeWhere((o) => overlaps(day, end, o.from, o.to));
    } else {
      p.daysOff.add((from: day, to: end, reason: 'Indisponible'));
    }
    _changed();
  }

  // ===================================================== soins et tarifs
  /// Soins que sa profession l'autorise à proposer.
  List<CareService> servicesAllowedFor(Pro p) =>
      services.where((s) => s.proType == p.type).toList();

  Future<void> updateProServices(Map<String, int> prices) async {
    final p = _me;
    if (prices.isEmpty) {
      throw const BusinessRuleError('Proposez au moins un soin.');
    }
    for (final e in prices.entries) {
      final s = services.where((x) => x.id == e.key).firstOrNull;
      if (s == null || s.proType != p.type) {
        throw BusinessRuleError(
          '${s?.name ?? e.key} ne fait pas partie des actes autorisés pour '
          '${p.type.label.toLowerCase()}.',
        );
      }
      if (e.value < s.minPrice || e.value > s.maxPrice) {
        throw BusinessRuleError(
          '${s.name} : prix entre ${AppState._money(s.minPrice)} et '
          '${AppState._money(s.maxPrice)}.',
        );
      }
    }
    if (remote != null) return _online((r) => r.updateServices(prices));
    p.prices = {...prices};
    _changed();
  }

  // =========================================================== agenda
  /// Soins confirmés ou réalisés du soignant ce jour-là, par heure.
  List<Booking> proDay(DateTime day) {
    final p = currentPro;
    final d0 = DateTime(day.year, day.month, day.day);
    final d1 = d0.add(const Duration(days: 1));
    return bookings
        .where(
          (b) =>
              b.pro == p &&
              (b.status == BookingStatus.accepted ||
                  b.status == BookingStatus.done) &&
              !b.scheduledAt.isBefore(d0) &&
              b.scheduledAt.isBefore(d1),
        )
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  /// Prochain soin à réaliser (ou en cours).
  Booking? get proNextVisit => bookings
      .where(
        (b) =>
            b.pro == currentPro &&
            b.status == BookingStatus.accepted &&
            b.endsAt.add(const Duration(hours: 2)).isAfter(now),
      )
      .fold<Booking?>(
        null,
        (best, b) =>
            best == null || b.scheduledAt.isBefore(best.scheduledAt) ? b : best,
      );

  /// Suivis réguliers acceptés, une entrée par suivi.
  List<Contract> get proContracts {
    final seen = <Contract>{};
    for (final b in bookings) {
      if (b.pro == currentPro &&
          b.contract != null &&
          b.contract!.sessions.any(
            (s) =>
                s.status == BookingStatus.accepted ||
                s.status == BookingStatus.done,
          )) {
        seen.add(b.contract!);
      }
    }
    return seen.toList()..sort((a, b) => a.start.compareTo(b.start));
  }

  // ===================================================== journal de visite
  Future<void> _journal(Booking b, JournalKind kind, [String text = '']) async {
    _requireServer(workspace: true);
    _requireActive();
    if (b.pro != currentPro || !b.readyForCare) {
      throw const BusinessRuleError(
        'Ce soin n’est pas confirmé et payé, ou ne vous est pas attribué.',
      );
    }
    if (remote != null) {
      return _online((r) => r.addJournal(b.id, kind, text));
    }
    b.journal.add(JournalEntry(kind, now, text));
    switch (kind) {
      case JournalKind.onTheWay:
        _notifyFamily(
          b,
          '${b.pro.name} est en route',
          '${b.service.name} pour ${b.patientName}. Prévenez la personne sur '
              'place.',
        );
      case JournalKind.arrived:
        _notifyFamily(
          b,
          '${b.pro.name} est arrivé(e)',
          'Le soin de ${b.patientName} commence.',
        );
      case JournalKind.note || JournalKind.left:
        break;
    }
    _changed();
  }

  Future<void> markOnTheWay(Booking b) async {
    if (b.journal.any((j) => j.kind == JournalKind.onTheWay)) return;
    if (b.scheduledAt.difference(now) > const Duration(hours: 3)) {
      throw const BusinessRuleError(
        'Trop tôt : indiquez « Je pars » au plus 3 h avant le soin.',
      );
    }
    return _journal(b, JournalKind.onTheWay);
  }

  Future<void> markArrived(Booking b) async {
    if (b.arrivedAt != null) return;
    if (now.isBefore(b.careLogOpensAt)) {
      throw BusinessRuleError(
        'Le soin est prévu à ${AppState._time(b.scheduledAt)} : l’arrivée '
        'se note à partir de ${AppState._time(b.careLogOpensAt)}.',
      );
    }
    return _journal(b, JournalKind.arrived);
  }

  Future<void> addJournalNote(Booking b, String text) {
    if (text.trim().length < 3) {
      throw const BusinessRuleError('Écrivez la note.');
    }
    return _journal(b, JournalKind.note, text.trim());
  }

  // ============================================================ constantes
  Future<VitalSign> recordVital(
    Booking b,
    VitalKind kind,
    double value, {
    double? value2,
  }) async {
    _requireActive();
    _requireServer();
    final p = _me;
    if (b.pro != p || !b.readyForCare) {
      throw const BusinessRuleError('Ce soin ne vous est pas attribué.');
    }
    if (!p.scope.vitals.contains(kind)) {
      throw BusinessRuleError(
        '${kind.label} : hors du champ d’exercice '
        '${p.type == ProType.aideSoignant ? 'd’un(e) aide-soignant(e)' : 'de votre profession'}.',
      );
    }
    final (lo, hi) = kind.range;
    if (value < lo || value > hi) {
      throw BusinessRuleError(
        '${kind.label} : valeur improbable. Vérifiez la mesure.',
      );
    }
    if (kind == VitalKind.bloodPressure &&
        (value2 == null || value2 < 20 || value2 >= value)) {
      throw const BusinessRuleError(
        'Tension : indiquez la systolique puis la diastolique (ex. 130 / 80).',
      );
    }
    final v = VitalSign(
      kind: kind,
      value: value,
      value2: value2,
      at: now,
      by: p.name,
      booking: b,
    );
    if (remote != null) {
      await _online(
        (r) => r.recordVital(b.patient.id, b.id, kind, value, value2),
      );
      b.vitals.add(v); // le serveur renvoie la mesure au prochain chargement
      return v;
    }
    b.vitals.add(v);
    _changed();
    return v;
  }

  // ======================================= dossier du patient (autorisé)
  /// Ce que le soignant voit du dossier pour ce soin : selon l'accès en cours
  /// (ouvert par la demande, révocable par le titulaire) et sa profession.
  /// En ligne, chaque lecture est journalisée côté serveur.
  Future<PatientChart> patientChart(Booking b) async {
    final p = _me;
    if (b.pro != p) {
      throw const BusinessRuleError(
        'Ce patient ne fait pas partie de vos soins.',
      );
    }
    if (remote != null) {
      try {
        return await remote!.patientChart(b.patient.id, p.scope);
      } on BusinessRuleError {
        rethrow;
      } catch (_) {
        noteNetworkFailure();
        rethrow;
      }
    }
    final until = b.endsAt.add(const Duration(hours: 24));
    final open =
        proCanSeeRecord(b) &&
        (b.status == BookingStatus.pending ||
            b.status == BookingStatus.accepted ||
            (b.status == BookingStatus.done && now.isBefore(until)));
    if (!open) {
      throw const BusinessRuleError(
        'Accès fermé : il s’ouvre avec une demande de soin et se ferme 24 h '
        'après le soin, ou plus tôt si la famille le retire.',
      );
    }
    final pt = b.patient;
    final full = b.status != BookingStatus.pending && p.scope.fullRecord;
    final docs = b.status != BookingStatus.pending && p.scope.documents;
    return PatientChart(
      name: pt.name,
      age: pt.ageAt(now),
      scopeLabel: b.status == BookingStatus.pending
          ? 'Demande en attente : identité, allergies et traitements seulement.'
          : full
          ? 'Soin confirmé : carnet complet jusqu’au ${AppState._shortDate(until)}.'
          : 'Votre profession donne accès à l’essentiel (allergies, '
                'traitements), pas aux documents médicaux.',
      allergies: pt.allergies,
      treatments: pt.treatments,
      history: full ? pt.history : '',
      bloodGroup: full ? pt.bloodGroup : '',
      emergencyContact: b.status == BookingStatus.pending
          ? ''
          : pt.emergencyContact,
      documents: docs ? pt.documents : const [],
      vitals: full ? patientVitals(pt) : const [],
      reports: full
          ? [
              for (final x in careHistory(pt))
                (
                  at: x.careLog!.arrivedAt,
                  pro: x.pro.name,
                  acts: x.careLog!.acts,
                  observations: x.careLog!.observations,
                ),
            ]
          : const [],
    );
  }

  /// Constantes structurées d'un patient, de la plus récente à la plus
  /// ancienne.
  List<VitalSign> patientVitals(Patient pt) =>
      [for (final b in bookings.where((b) => b.patient == pt)) ...b.vitals]
        ..sort((a, b) => b.at.compareTo(a.at));

  // ================================================ patients suivis
  /// Patients que le soignant a déjà soignés ou va soigner.
  List<Patient> get proPatients {
    final out = <Patient>[];
    for (final b in bookings) {
      if (b.pro == currentPro &&
          (b.status == BookingStatus.accepted ||
              b.status == BookingStatus.done) &&
          !out.contains(b.patient)) {
        out.add(b.patient);
      }
    }
    return out;
  }

  /// Soins du soignant pour ce patient, du plus récent au plus ancien.
  List<Booking> proHistory(Patient pt) =>
      bookings
          .where(
            (b) =>
                b.pro == currentPro &&
                b.patient == pt &&
                (b.status == BookingStatus.accepted ||
                    b.status == BookingStatus.done),
          )
          .toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  // ================================================================ revenus
  /// Soins terminés du soignant, du plus récent au plus ancien.
  List<Booking> get proDone =>
      bookings
          .where((b) => b.pro == currentPro && b.status == BookingStatus.done)
          .toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  /// Gains nets du mois en cours.
  int get proMonthEarnings => proDone
      .where(
        (b) =>
            b.scheduledAt.year == now.year && b.scheduledAt.month == now.month,
      )
      .fold(0, (s, b) => s + b.proEarnings);

  /// Gains nets des 6 dernières semaines (de la plus ancienne à la plus
  /// récente), pour le graphique.
  List<({DateTime week, int amount})> get proWeeklyEarnings {
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    return [
      for (var i = 5; i >= 0; i--)
        (
          week: monday.subtract(Duration(days: 7 * i)),
          amount: proDone
              .where(
                (b) =>
                    !b.scheduledAt.isBefore(
                      monday.subtract(Duration(days: 7 * i)),
                    ) &&
                    b.scheduledAt.isBefore(
                      monday.subtract(Duration(days: 7 * (i - 1))),
                    ),
              )
              .fold(0, (s, b) => s + b.proEarnings),
        ),
    ];
  }

  /// Retraits demandés (historique du solde).
  List<WalletTx> get proWithdrawals =>
      (currentPro?.wallet.history ?? const <WalletTx>[])
          .where((t) => t.kind == WalletTxKind.withdrawal)
          .toList();

  // ============================================================ réputation
  /// Répartition des notes (index 0 = 1 étoile).
  List<int> ratingDistribution(Pro p) {
    final d = List<int>.filled(5, 0);
    for (final r in p.reviews) {
      if (r.rating >= 1 && r.rating <= 5) d[r.rating - 1]++;
    }
    return d;
  }

  /// Délai moyen de réponse aux demandes (30 derniers jours).
  Duration? proResponseTime(Pro p) {
    final answered = bookings.where(
      (b) =>
          b.pro == p &&
          b.acceptedAt != null &&
          now.difference(b.createdAt) <= const Duration(days: 30),
    );
    if (answered.isEmpty) return null;
    final total = answered.fold<int>(
      0,
      (s, b) => s + b.acceptedAt!.difference(b.createdAt).inMinutes,
    );
    return Duration(minutes: total ~/ answered.length);
  }

  // ===================================================== rappels soignant
  List<CareReminder> get proReminders {
    final p = currentPro;
    if (p == null) return const [];
    final out = <CareReminder>[];
    for (final d in p.expiringDocs(now)) {
      out.add(
        CareReminder(
          title:
              '${d.label} expire le ${AppState._shortDate(p.documentExpiry[d]!).split(' à ').first}',
          body:
              'Déposez la nouvelle version pour continuer à recevoir des '
              'demandes.',
          urgent: true,
        ),
      );
    }
    for (final b in proRequests) {
      if (b.responseDeadline.difference(now) <= const Duration(minutes: 30)) {
        out.add(
          CareReminder(
            title:
                'Demande à traiter avant ${AppState._time(b.responseDeadline)}',
            body: '${b.service.name} pour ${b.patientName}.',
            booking: b,
            urgent: true,
          ),
        );
      }
    }
    for (final b in bookings.where(
      (b) => b.pro == p && b.readyForCare && canLogCare(b),
    )) {
      out.add(
        CareReminder(
          title: 'Compte rendu à rédiger',
          body:
              '${b.service.name} · ${b.patientName}. Votre paiement est '
              'versé dès l’envoi.',
          booking: b,
        ),
      );
    }
    return out;
  }

  // ============================================================= incidents
  Future<Incident> reportIncident({
    required IncidentCategory category,
    required String description,
    Booking? booking,
  }) async {
    final text = description.trim();
    if (text.length < 10) {
      throw const BusinessRuleError(
        'Décrivez ce qui s’est passé en une ou deux phrases.',
      );
    }
    if (booking != null && booking.pro != currentPro) {
      throw const BusinessRuleError('Ce soin ne vous est pas attribué.');
    }
    _requireServer(workspace: true);
    if (remote != null) {
      late String id;
      await _online((r) async {
        id = await r.reportIncident(booking?.id, category, text);
      });
      return incidents.firstWhere(
        (i) => i.id == id,
        orElse: () => Incident(
          id: id,
          category: category,
          description: text,
          at: now,
          booking: booking,
        ),
      );
    }
    final i = Incident(
      id: 'I${incidents.length + 1}',
      category: category,
      description: text,
      at: now,
      booking: booking,
    );
    incidents.insert(0, i);
    _notify(
      'admin',
      category.urgent ? 'Urgent : incident signalé' : 'Incident signalé',
      '${category.label} · ${_me.name}'
          '${booking == null ? '' : ' · ${booking.patientName}'}.',
    );
    _notify(
      _me.id,
      'Incident reçu',
      category.urgent
          ? 'L’équipe MyNurse vous rappelle rapidement.'
          : 'L’équipe MyNurse vous répond sous 24 h.',
    );
    _changed();
    return i;
  }
}
