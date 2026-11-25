part of '../app_state.dart';

/// Console d'administration : permissions par rôle, indicateurs par
/// période, listes filtrables, actions journalisées, exports, accès
/// d'urgence au dossier médical (motif obligatoire, durée limitée, patient
/// prévenu).
extension AdminFeatures on AppState {
  // ============================================================ permissions
  Set<AdminPermission> get adminPermissions => adminMe?.permissions ?? const {};

  bool hasAdminPerm(AdminPermission p) => adminPermissions.contains(p);

  void _requireAdmin(AdminPermission p) {
    if (role != UserRole.admin || !hasAdminPerm(p)) {
      throw BusinessRuleError(
        'Action réservée : permission « ${p.label} » nécessaire. Demandez-la '
        'à un responsable de l’équipe.',
      );
    }
  }

  /// Écrit une ligne dans le journal d'activité (démo ; en ligne, le
  /// serveur journalise lui-même chaque action).
  void _adminLog(
    String action,
    String target, {
    String details = '',
    String? patientId,
  }) {
    if (remote != null) return;
    adminLog.insert(
      0,
      AdminLogEntry(
        at: now,
        actor: adminMe?.name ?? 'Système',
        action: action,
        target: target,
        details: details,
        patientId: patientId,
      ),
    );
  }

  /// Le responsable attribue ou retire une permission. Personne ne s'attribue
  /// l'accès d'urgence au dossier médical.
  Future<void> setStaffPermission(
    StaffMember m,
    AdminPermission p,
    bool grant,
  ) async {
    _requireAdmin(AdminPermission.manageStaff);
    if (grant && p == AdminPermission.medicalBreakGlass && m == adminMe) {
      throw const BusinessRuleError(
        'Un autre responsable doit vous attribuer l’accès d’urgence.',
      );
    }
    if (remote != null) {
      return _online((r) => r.setStaffPermission(m.id, p, grant));
    }
    grant ? m.permissions.add(p) : m.permissions.remove(p);
    _adminLog(
      grant ? 'Permission attribuée' : 'Permission retirée',
      m.name,
      details: p.label,
    );
    _changed();
  }

  // ============================================================= indicateurs
  AdminMetrics adminMetrics(Period period) {
    final inPeriod = bookings.where((b) => period.contains(b.createdAt));
    final done = bookings.where(
      (b) => b.status == BookingStatus.done && period.contains(b.scheduledAt),
    );
    final answered = inPeriod.where((b) => b.acceptedAt != null);
    final rated = done.where((b) => b.rating != null);
    final allPatients = <Patient>{
      for (final a in accounts) ...a.patients,
      for (final b in bookings) b.patient,
    };
    return AdminMetrics(
      patients: isRemote && _remoteAdminCounts != null
          ? _remoteAdminCounts!.patients
          : allPatients.length,
      verifiedPros: pros.where((p) => p.activeAt(now)).length,
      pendingVerifications: verificationQueue.length,
      appointments: inPeriod.length,
      completed: done.length,
      cancelled: inPeriod
          .where(
            (b) =>
                b.status == BookingStatus.cancelled ||
                b.status == BookingStatus.refused,
          )
          .length,
      volume: done.fold(0, (s, b) => s + b.price),
      commissions: done.fold(0, (s, b) => s + b.commission),
      proEarnings: done.fold(0, (s, b) => s + b.proEarnings),
      responseMinutes: answered.isEmpty
          ? null
          : answered.fold<int>(
                  0,
                  (s, b) => s + b.acceptedAt!.difference(b.createdAt).inMinutes,
                ) ~/
                answered.length,
      satisfaction: rated.isEmpty
          ? null
          : rated.fold<int>(0, (s, b) => s + b.rating!) / rated.length,
      ratings: rated.length,
    );
  }

  /// Rendez-vous créés par jour sur la période (pour le graphique).
  List<({DateTime day, int count, int volume})> adminDaily(Period p) {
    final days = p.to.difference(p.from).inDays.clamp(1, 120);
    return [
      for (var i = 0; i < days; i++)
        () {
          final d0 = DateTime(p.from.year, p.from.month, p.from.day + i);
          final d1 = DateTime(d0.year, d0.month, d0.day + 1);
          final day = bookings.where(
            (b) => !b.createdAt.isBefore(d0) && b.createdAt.isBefore(d1),
          );
          return (
            day: d0,
            count: day.length,
            volume: day
                .where((b) => b.status == BookingStatus.done)
                .fold(0, (s, b) => s + b.price),
          );
        }(),
    ];
  }

  /// Répartition des rendez-vous de la période (par soin, par commune).
  Map<String, int> adminBreakdown(Period p, {required bool byCommune}) {
    final out = <String, int>{};
    for (final b in bookings.where((b) => p.contains(b.createdAt))) {
      final k = byCommune ? b.commune : b.service.name.split(' (').first;
      out[k] = (out[k] ?? 0) + 1;
    }
    final sorted = out.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in sorted) e.key: e.value};
  }

  // ================================================================ listes
  static bool _match(String query, List<String> fields) {
    final q = PatientFeatures._fold(query.trim());
    if (q.isEmpty) return true;
    final hay = PatientFeatures._fold(fields.join(' '));
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  /// Comptes : patients (titulaires), soignants, équipe.
  List<({String id, String name, String role, String phone, String detail})>
  adminUsers(String query) => [
    for (final a in accounts)
      if (_match(query, [a.name, a.phone]))
        (
          id: a.id,
          name: a.name.isEmpty ? '(sans nom)' : a.name,
          role: 'Patient',
          phone: a.phone,
          detail:
              '${a.patients.length} personne${a.patients.length > 1 ? 's' : ''} · solde ${AppState._money(a.wallet.balance)}',
        ),
    for (final p in pros)
      if (_match(query, [p.name, p.phone, p.type.label]))
        (
          id: p.id,
          name: p.name,
          role: 'Soignant',
          phone: p.phone,
          detail: '${p.type.label} · ${p.statusAt(now).label}',
        ),
    for (final m in staff)
      if (_match(query, [m.name, m.phone]))
        (
          id: m.id,
          name: m.name,
          role: 'Équipe MyNurse',
          phone: m.phone,
          detail: '${m.permissions.length} permission(s)',
        ),
  ];

  /// Patients, sans aucune donnée médicale (identité, compte, activité).
  List<({Patient patient, String owner, int bookings, DateTime? last})>
  adminPatients(String query) {
    final out =
        <({Patient patient, String owner, int bookings, DateTime? last})>[];
    final seen = <Patient>{};
    void add(Patient p, String owner) {
      if (!seen.add(p) || !_match(query, [p.name, owner, p.commune])) return;
      final list = bookings.where((b) => b.patient == p).toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
      out.add((
        patient: p,
        owner: owner,
        bookings: list.length,
        last: list.firstOrNull?.scheduledAt,
      ));
    }

    for (final a in accounts) {
      for (final p in a.patients) {
        add(p, a.name);
      }
    }
    for (final b in bookings) {
      add(b.patient, '—');
    }
    return out;
  }

  List<Pro> adminPros(String query, {VerificationStatus? status}) =>
      pros
          .where((p) => status == null || p.statusAt(now) == status)
          .where((p) => _match(query, [p.name, p.type.label, ...p.communes]))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  List<Booking> adminBookings(
    Period period, {
    String query = '',
    BookingStatus? status,
    bool contractsOnly = false,
  }) =>
      bookings
          .where(
            (b) =>
                period.contains(b.createdAt) || period.contains(b.scheduledAt),
          )
          .where((b) => status == null || b.status == status)
          .where((b) => !contractsOnly || b.contract != null)
          .where(
            (b) => _match(query, [
              b.patientName,
              b.pro.name,
              b.service.name,
              b.commune,
              b.id,
            ]),
          )
          .toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  /// Suivis réguliers (une entrée par suivi).
  List<Contract> adminContracts(String query) {
    final seen = <Contract>{};
    for (final b in bookings) {
      if (b.contract != null &&
          _match(query, [b.patientName, b.pro.name, b.service.name])) {
        seen.add(b.contract!);
      }
    }
    return seen.toList()..sort((a, b) => b.start.compareTo(a.start));
  }

  /// Mouvements d'argent de tous les comptes sur la période.
  List<({WalletTx tx, String owner})> adminTransactions(
    Period period, {
    WalletTxKind? kind,
  }) {
    final out = <({WalletTx tx, String owner})>[
      for (final a in accounts)
        for (final t in a.wallet.history) (tx: t, owner: a.name),
      for (final p in pros)
        for (final t in p.wallet.history) (tx: t, owner: p.name),
    ];
    return out
        .where((e) => period.contains(e.tx.at))
        .where((e) => kind == null || e.tx.kind == kind)
        .toList()
      ..sort((a, b) => b.tx.at.compareTo(a.tx.at));
  }

  /// Soins remboursés (en tout ou partie) sur la période.
  List<Booking> adminRefunds(Period p) => bookings
      .where(
        (b) =>
            b.refundAmount > 0 &&
            (p.contains(b.createdAt) || p.contains(b.scheduledAt)),
      )
      .toList();

  /// Vérifie la permission quand un membre de l'équipe est connecté (les
  /// tests et la démo appellent aussi ces actions sans session admin).
  void _checkAdmin(AdminPermission p) {
    if (role == UserRole.admin) _requireAdmin(p);
  }

  // ======================================================= actions : soins
  /// Annulation d'un rendez-vous par l'équipe : remboursement intégral,
  /// soignant et famille prévenus.
  Future<void> adminCancelBooking(Booking b, String reason) async {
    _requireAdmin(AdminPermission.manageBookings);
    if (reason.trim().length < 5) {
      throw const BusinessRuleError('Indiquez le motif (vu par la famille).');
    }
    if (b.status != BookingStatus.pending &&
        b.status != BookingStatus.accepted) {
      throw const BusinessRuleError('Ce rendez-vous n’est plus en cours.');
    }
    if (remote != null) {
      return _online((r) => r.adminCancelBooking(b.id, reason.trim()));
    }
    for (final s in _cancellable(b)) {
      _cancel(s, 'Annulé par MyNurse : ${reason.trim()}');
    }
    _notifyFamily(
      b,
      'Soin annulé par MyNurse',
      '${reason.trim()}. ${b.paid ? 'Vous êtes remboursé sur votre solde. ' : ''}',
    );
    _notify(
      b.pro.id,
      'Soin annulé par MyNurse',
      '${b.service.name} · ${b.patientName} : ${reason.trim()}.',
    );
    _adminLog(
      'Rendez-vous annulé',
      '${b.service.name} · ${b.patientName}',
      details: reason.trim(),
    );
    _changed();
  }

  /// Remboursement (geste commercial ou litige) sur le solde de la famille.
  Future<void> adminRefund(Booking b, int amount, String reason) async {
    _requireAdmin(AdminPermission.finance);
    if (!b.paid) {
      throw const BusinessRuleError('Ce soin n’a pas été payé.');
    }
    final max = b.price - b.refundAmount;
    if (amount <= 0 || amount > max) {
      throw BusinessRuleError('Montant entre 1 et ${AppState._money(max)}.');
    }
    if (reason.trim().length < 5) {
      throw const BusinessRuleError('Indiquez le motif du remboursement.');
    }
    if (remote != null) {
      return _online((r) => r.adminRefund(b.id, amount, reason.trim()));
    }
    final owner = _ownerOf(b);
    owner?.wallet.move(
      WalletTxKind.refund,
      amount,
      'Remboursement MyNurse · ${b.service.name}',
      at: now,
    );
    b.adminRefunded += amount;
    _notify(
      b.ownerId,
      'Remboursement',
      '${AppState._money(amount)} crédités sur votre solde : ${reason.trim()}.',
      booking: b,
    );
    _adminLog(
      'Remboursement',
      '${b.service.name} · ${b.patientName}',
      details: '${AppState._money(amount)} · ${reason.trim()}',
    );
    _changed();
  }

  // ================================================= actions : soignants
  Future<void> adminExtendPremium(Pro p, int days, String reason) async {
    _requireAdmin(AdminPermission.finance);
    if (days < 1 || days > 365) {
      throw const BusinessRuleError('Entre 1 et 365 jours.');
    }
    if (remote != null) {
      return _online((r) => r.adminExtendPremium(p.id, days, reason));
    }
    p.premiumUntil = extendPremium(p.premiumUntil, now, Duration(days: days));
    _notify(p.id, 'Pro Premium offert', '$days jours offerts par MyNurse.');
    _adminLog('Premium offert', p.name, details: '$days jours · $reason');
    _changed();
  }

  /// Taux de commission appliqué aux nouveaux soins (les soins déjà créés
  /// gardent le leur).
  Future<void> adminSetCommission(double rate) async {
    _requireAdmin(AdminPermission.manageSettings);
    if (rate < 0 || rate > 0.30) {
      throw const BusinessRuleError('Commission entre 0 et 30 %.');
    }
    if (remote != null) {
      return _online((r) => r.adminUpdateSetting('commission_rate', rate));
    }
    commissionOverride = rate;
    _adminLog(
      'Commission modifiée',
      'Plateforme',
      details:
          '${(rate * 100).toStringAsFixed(1).replaceAll('.0', '')} % pour les nouveaux soins',
    );
    _changed();
  }

  // =================================================== réclamations
  Future<void> adminUpdateComplaint(
    Complaint c,
    ComplaintStatus status, {
    String resolution = '',
    int refund = 0,
  }) async {
    _requireAdmin(AdminPermission.support);
    if (refund > 0) _requireAdmin(AdminPermission.finance);
    if ((status == ComplaintStatus.resolved ||
            status == ComplaintStatus.rejected) &&
        resolution.trim().isEmpty) {
      throw const BusinessRuleError('Indiquez la réponse apportée.');
    }
    if (remote != null) {
      return _online(
        (r) => r.adminUpdateComplaint(c.id, status, resolution.trim(), refund),
      );
    }
    c.status = status;
    if (resolution.trim().isNotEmpty) c.resolution = resolution.trim();
    if (refund > 0) {
      final owner = c.booking == null ? account : _ownerOf(c.booking!);
      owner?.wallet.move(
        WalletTxKind.refund,
        refund,
        'Geste commercial MyNurse',
        at: now,
      );
    }
    if (status == ComplaintStatus.resolved ||
        status == ComplaintStatus.rejected) {
      _notify(
        c.booking?.ownerId ?? account?.id,
        'Réclamation traitée',
        c.resolution,
      );
    }
    _adminLog(
      'Réclamation : ${status.label.toLowerCase()}',
      c.category.label,
      details: [
        if (resolution.trim().isNotEmpty) resolution.trim(),
        if (refund > 0) 'remboursé ${AppState._money(refund)}',
      ].join(' · '),
    );
    _changed();
  }

  // ======================================================= incidents
  Future<void> adminUpdateIncident(
    Incident i,
    String status,
    String note,
  ) async {
    _requireAdmin(AdminPermission.support);
    if (remote != null) {
      return _online((r) => r.adminUpdateIncident(i.id, status, note));
    }
    i.status = status;
    _notify(
      i.booking?.pro.id ?? currentPro?.id,
      'Incident : $status',
      note.isEmpty ? i.category.label : note,
    );
    _adminLog('Incident : $status', i.category.label, details: note);
    _changed();
  }

  // ======================================================= pharmacies
  Future<void> adminSavePharmacy(Pharmacy p, {Pharmacy? replacing}) async {
    _requireAdmin(AdminPermission.manageSettings);
    if (p.name.trim().length < 3 || p.address.trim().isEmpty) {
      throw const BusinessRuleError('Nom et adresse obligatoires.');
    }
    if (remote != null) return _online((r) => r.adminSavePharmacy(p));
    if (replacing != null) pharmacies.remove(replacing);
    pharmacies.add(p);
    _adminLog(
      replacing == null ? 'Pharmacie ajoutée' : 'Pharmacie modifiée',
      p.name,
      details: p.onDutyUntil == null
          ? ''
          : 'de garde jusqu’au ${AppState._shortDate(p.onDutyUntil!)}',
    );
    _changed();
  }

  Future<void> adminRemovePharmacy(Pharmacy p) async {
    _requireAdmin(AdminPermission.manageSettings);
    if (remote != null) return _online((r) => r.adminHidePharmacy(p.id));
    pharmacies.remove(p);
    _adminLog('Pharmacie retirée', p.name);
    _changed();
  }

  // ====================================================== messages
  Future<int> adminBroadcast(
    BroadcastAudience audience,
    String title,
    String body,
  ) async {
    _requireAdmin(AdminPermission.manageSettings);
    if (title.trim().length < 3 || body.trim().length < 5) {
      throw const BusinessRuleError('Titre et message obligatoires.');
    }
    late int n;
    if (remote != null) {
      await _online((r) async {
        n = await r.adminBroadcast(audience, title.trim(), body.trim());
      });
    } else {
      final ids = <String>[
        if (audience != BroadcastAudience.pros) ...accounts.map((a) => a.id),
        if (audience != BroadcastAudience.patients)
          ...pros.where((p) => p.activeAt(now)).map((p) => p.id),
      ];
      for (final id in ids) {
        _notify(id, title.trim(), body.trim());
      }
      n = ids.length;
      _adminLog(
        'Message envoyé',
        audience.label,
        details: '${title.trim()} ($n destinataires)',
      );
    }
    broadcasts.insert(
      0,
      Broadcast(
        at: now,
        audience: audience,
        title: title.trim(),
        body: body.trim(),
        recipients: n,
        by: adminMe?.name ?? '',
      ),
    );
    _changed();
    return n;
  }

  // ================================= accès d'urgence au dossier médical
  /// L'équipe n'a pas accès aux dossiers médicaux. Exception : l'accès
  /// d'urgence, réservé à la permission dédiée, avec un motif détaillé,
  /// limité à 4 h, journalisé et notifié au titulaire.
  Future<PatientChart> adminBreakGlass(Patient p, String reason) async {
    _requireAdmin(AdminPermission.medicalBreakGlass);
    if (reason.trim().length < 10) {
      throw const BusinessRuleError(
        'Motif détaillé obligatoire (10 caractères minimum) : il est '
        'communiqué à la famille.',
      );
    }
    if (remote != null) {
      try {
        await remote!.adminBreakGlass(p.id, reason.trim());
        return await remote!.patientChart(
          p.id,
          ScopeOfPractice.of(ProType.medecin),
        );
      } on BusinessRuleError {
        rethrow;
      } catch (_) {
        noteNetworkFailure();
        rethrow;
      }
    }
    _breakGlass[p.id] = now.add(const Duration(hours: 4));
    final owner = _ownerAccountOf(p);
    _notify(
      owner?.id,
      'Accès d’urgence à un dossier',
      'L’équipe MyNurse a consulté le dossier de ${p.name}. Motif : ${reason.trim()}',
    );
    _adminLog(
      'Accès d’urgence au dossier',
      p.name,
      details: reason.trim(),
      patientId: p.id,
    );
    _changed();
    return adminChart(p)!;
  }

  /// Dossier visible par l'équipe : seulement pendant un accès d'urgence.
  PatientChart? adminChart(Patient p) {
    final until = _breakGlass[p.id];
    if (until == null || !now.isBefore(until)) return null;
    return PatientChart(
      name: p.name,
      age: p.ageAt(now),
      scopeLabel:
          'Accès d’urgence jusqu’à ${AppState._time(until)}. Chaque lecture '
          'est enregistrée et la famille est prévenue.',
      allergies: p.allergies,
      treatments: p.treatments,
      history: p.history,
      bloodGroup: p.bloodGroup,
      emergencyContact: p.emergencyContact,
      documents: p.documents,
      vitals: patientVitals(p),
    );
  }

  // ========================================================= exports
  /// Rapport CSV (séparateur « ; », lisible par Excel en français).
  String toCsv(List<String> header, List<List<Object?>> rows) {
    String cell(Object? v) {
      final t = (v ?? '').toString();
      return t.contains(RegExp(r'[;"\n]')) ? '"${t.replaceAll('"', '""')}"' : t;
    }

    return [
      header.map(cell).join(';'),
      for (final r in rows) r.map(cell).join(';'),
    ].join('\n');
  }

  String adminReportCsv(Period p) {
    final m = adminMetrics(p);
    final rows = <List<Object?>>[
      ['Période', p.label],
      ['Patients inscrits', m.patients],
      ['Soignants vérifiés', m.verifiedPros],
      ['Vérifications en attente', m.pendingVerifications],
      ['Rendez-vous', m.appointments],
      ['Soins réalisés', m.completed],
      ['Annulés ou refusés', m.cancelled],
      ['Volume des transactions (FCFA)', m.volume],
      ['Commissions MyNurse (FCFA)', m.commissions],
      ['Gains des soignants (FCFA)', m.proEarnings],
      ['Délai moyen de réponse (min)', m.responseMinutes ?? ''],
      ['Satisfaction (sur 5)', m.satisfaction?.toStringAsFixed(2) ?? ''],
    ];
    _adminLog('Export', 'Rapport d’activité', details: p.label);
    return toCsv(['Indicateur', 'Valeur'], rows);
  }

  String adminBookingsCsv(List<Booking> list) {
    _adminLog('Export', 'Rendez-vous', details: '${list.length} lignes');
    return toCsv(
      [
        'Référence',
        'Date',
        'Soin',
        'Soignant',
        'Patient',
        'Commune',
        'Statut',
        'Prix',
        'Commission',
        'Net soignant',
      ],
      [
        for (final b in list)
          [
            b.id,
            b.scheduledAt.toIso8601String().substring(0, 16),
            b.service.name,
            b.pro.name,
            b.patientName,
            b.commune,
            b.status.label,
            b.price,
            b.commission,
            b.proEarnings,
          ],
      ],
    );
  }

  // ========================================================= intelligence
  /// Signaux, pics, doublons, retours et rapport de la période. Le moteur ne
  /// reçoit qu'une projection sans aucun champ médical.
  InsightsReport adminInsights(Period period) {
    CancelledBy? by(Booking b) {
      if (b.status != BookingStatus.cancelled) return null;
      if (b.cancelReason.startsWith('Annulé par le patient')) {
        return CancelledBy.patient;
      }
      if (b.cancelReason.startsWith('Annulé par le soignant')) {
        return CancelledBy.pro;
      }
      return CancelledBy.platform;
    }

    final facts = [
      for (final b in bookings)
        BookingFact(
          id: b.id,
          ownerId: b.ownerId,
          proId: b.pro.id,
          proName: b.pro.name,
          commune: b.commune,
          serviceName: b.service.name.split(' (').first,
          createdAt: b.createdAt,
          scheduledAt: b.scheduledAt,
          status: b.status.name,
          cancelledBy: by(b),
          price: b.price,
          paid: b.paid,
          refundAmount: b.refundAmount,
          rating: b.rating,
          night: b.night,
        ),
    ];
    final people = [
      for (final a in accounts)
        if (a.id.isNotEmpty)
          AccountFact(
            id: a.id,
            kind: AccountKind.patient,
            name: a.name,
            phone: a.phone,
          ),
      for (final p in pros)
        AccountFact(
          id: p.id,
          kind: AccountKind.pro,
          name: p.name,
          phone: p.phone,
        ),
      for (final m in staff)
        AccountFact(
          id: m.id,
          kind: AccountKind.staff,
          name: m.name,
          phone: m.phone,
        ),
    ];
    final complaintFacts = [
      for (final c in complaints)
        ComplaintFact(
          category: c.category.label,
          text: c.description,
          createdAt: c.createdAt,
          proId: c.booking?.pro.id,
          open:
              c.status == ComplaintStatus.open ||
              c.status == ComplaintStatus.inReview,
        ),
    ];
    final reviewFacts = [
      for (final p in pros)
        for (final r in p.reviews)
          ReviewFact(
            proId: p.id,
            proName: p.name,
            rating: r.rating,
            text: r.comment,
            at: r.at,
          ),
    ];
    return const AdminInsightsEngine().analyze(
      from: period.from,
      to: period.to,
      now: now,
      bookings: facts,
      accounts: people,
      complaints: complaintFacts,
      reviews: reviewFacts,
      proCancellations: {
        for (final p in pros)
          if (p.cancellations.isNotEmpty) p.id: p.cancellations,
      },
    );
  }
}
