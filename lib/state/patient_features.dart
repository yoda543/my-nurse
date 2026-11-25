part of '../app_state.dart';

/// Parcours patient et famille : proches autorisés, carnet, documents,
/// accès des soignants, recherche, pharmacies, rappels, réclamations.
///
/// Même principe que le reste d'[AppState] : en démo tout se passe en
/// mémoire, en ligne chaque action passe par le serveur, qui applique les
/// mêmes règles (supabase/migrations/0009 à 0011).
extension PatientFeatures on AppState {
  // ================================================================ famille
  /// Personnes dont le compte s'occupe : les siennes, puis celles qu'un autre
  /// titulaire lui a confiées.
  List<Patient> get familyPatients => [...patients, ..._sharedPatients];

  List<Patient> get _sharedPatients {
    if (isRemote) return _remoteShared;
    final me = account?.id;
    if (me == null) return const [];
    return [
      for (final a in accounts)
        if (a != account)
          for (final p in a.patients)
            if (p.members.any((m) => m.accountId == me && m.activeAt(now))) p,
    ];
  }

  /// En ligne, avant l'installation des tables famille et carnet sur le
  /// serveur : on l'explique au lieu d'échouer.
  void _requireFamilyBackend() {
    if (isRemote && !familyBackendReady) {
      throw const BusinessRuleError(
        'Cette fonction arrive avec la prochaine mise à jour du serveur '
        'MyNurse. Vos soins et réservations fonctionnent normalement.',
      );
    }
  }

  /// Identifiant du compte connecté.
  String? get myAccountId => isRemote ? remote!.userId : account?.id;

  /// Accès du compte connecté au dossier d'un autre titulaire.
  FamilyMember? myMembership(Patient p) => p.members
      .where((m) => m.accountId == myAccountId && m.activeAt(now))
      .firstOrNull;

  /// Le compte connecté est-il titulaire de ce dossier ?
  bool isOwner(Patient p) => patients.contains(p);

  /// Droits du compte connecté sur ce patient (tous s'il est titulaire).
  Set<FamilyPermission> permissionsFor(Patient p) {
    if (isOwner(p)) return FamilyPermission.values.toSet();
    final me = isRemote ? remote!.userId : account?.id;
    final m = p.members
        .where((m) => m.accountId == me && m.activeAt(now))
        .firstOrNull;
    return m?.permissions ?? const {};
  }

  bool can(Patient p, FamilyPermission perm) =>
      permissionsFor(p).contains(perm);

  void _checkCanBook(Patient p) {
    if (!can(p, FamilyPermission.bookCare)) {
      throw BusinessRuleError(
        'Vous ne pouvez pas réserver pour ${p.name}. Demandez à '
        '${p.ownerName.isEmpty ? 'son titulaire' : p.ownerName} le droit '
        '« Réserver et payer des soins ».',
      );
    }
  }

  /// Compte titulaire d'un patient (démo).
  PatientAccount? _ownerAccountOf(Patient p) =>
      accounts.where((a) => a.patients.contains(p)).firstOrNull;

  /// Personnes pour qui le compte peut réserver.
  List<Patient> get bookablePatients =>
      familyPatients.where((p) => can(p, FamilyPermission.bookCare)).toList();

  /// Dernier lieu de soin connu pour ce patient (pour ne pas tout ressaisir).
  ({String commune, String address, GeoPoint? location})? lastPlaceFor(
    Patient p,
  ) {
    final past = bookings.where((b) => b.patient == p).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final b = past.firstOrNull;
    if (b == null) return null;
    return (commune: b.commune, address: b.address, location: b.location);
  }

  /// Commune proposée pour un soin de ce patient : la sienne, sinon la
  /// dernière utilisée, sinon celle détectée.
  String communeFor(Patient p) {
    if (communes.contains(p.commune)) return p.commune;
    return lastPlaceFor(p)?.commune ?? commune;
  }

  /// Proches actifs d'un patient, du plus ancien au plus récent.
  List<FamilyMember> activeMembers(Patient p) =>
      p.members.where((m) => m.activeAt(now)).toList();

  /// Le titulaire autorise un proche (déjà inscrit sur MyNurse) à aider.
  Future<FamilyMember> addFamilyMember(
    Patient p, {
    required String name,
    required String contact,
    required String relation,
    required Set<FamilyPermission> permissions,
    DateTime? expiresAt,
  }) async {
    _requireFamilyBackend();
    if (!isOwner(p)) {
      throw const BusinessRuleError(
        'Seul le titulaire du dossier peut ajouter un proche.',
      );
    }
    final c = contact.trim().replaceAll(' ', '');
    if (name.trim().length < 2) {
      throw const BusinessRuleError('Indiquez le nom de ce proche.');
    }
    if (c.length < 8) {
      throw const BusinessRuleError(
        'Indiquez son numéro de téléphone ou son e-mail.',
      );
    }
    if (permissions.isEmpty) {
      throw const BusinessRuleError('Choisissez au moins un droit.');
    }
    if (expiresAt != null && !expiresAt.isAfter(now)) {
      throw const BusinessRuleError('La date de fin doit être à venir.');
    }
    if (remote != null) {
      late String id;
      await _online((r) async {
        id = await r.addFamilyMember(
          p.id,
          contact: c,
          name: name.trim(),
          relation: relation,
          permissions: permissions,
          expiresAt: expiresAt,
        );
      });
      return familyPatients
          .firstWhere((x) => x.id == p.id)
          .members
          .firstWhere((m) => m.id == id);
    }
    final target = accounts
        .where((a) => a.phone == c || a.phone == contact.trim())
        .firstOrNull;
    if (target == null || target == account) {
      throw const BusinessRuleError(
        'Invitation impossible : ce proche doit d’abord créer son compte '
        'MyNurse avec ce numéro, puis vous recommencez.',
      );
    }
    if (activeMembers(p).any((m) => m.accountId == target.id)) {
      throw const BusinessRuleError('Ce proche a déjà accès à ce dossier.');
    }
    final m = FamilyMember(
      id: 'M${_nextMember++}',
      name: name.trim(),
      contact: c,
      relation: relation,
      permissions: {...permissions},
      addedAt: now,
      accountId: target.id,
      expiresAt: expiresAt,
    );
    p.members.add(m);
    p.ownerName = p.ownerName.isEmpty ? patientName : p.ownerName;
    _notify(
      target.id,
      'Accès au dossier de ${p.name}',
      '$patientName vous a ajouté comme proche. Vous pouvez : '
          '${permissions.map((e) => e.label.toLowerCase()).join(', ')}.',
    );
    _changed();
    return m;
  }

  Future<void> updateFamilyMember(
    Patient p,
    FamilyMember m, {
    required Set<FamilyPermission> permissions,
    DateTime? expiresAt,
  }) async {
    if (!isOwner(p)) {
      throw const BusinessRuleError(
        'Seul le titulaire du dossier peut changer les droits.',
      );
    }
    if (permissions.isEmpty) {
      throw const BusinessRuleError(
        'Choisissez au moins un droit, ou retirez ce proche.',
      );
    }
    if (remote != null) {
      return _online((r) => r.updateFamilyMember(m.id, permissions, expiresAt));
    }
    m.permissions = {...permissions};
    m.expiresAt = expiresAt;
    _notify(
      m.accountId,
      'Vos droits ont changé',
      'Pour ${p.name} : '
          '${permissions.map((e) => e.label.toLowerCase()).join(', ')}.',
    );
    _changed();
  }

  /// Retire un proche (le titulaire), ou se retire soi-même (le proche).
  Future<void> revokeFamilyMember(Patient p, FamilyMember m) async {
    final me = isRemote ? remote!.userId : account?.id;
    if (!isOwner(p) && m.accountId != me) {
      throw const BusinessRuleError('Action réservée au titulaire du dossier.');
    }
    if (remote != null) return _online((r) => r.revokeFamilyMember(m.id));
    m.revokedAt = now;
    if (isOwner(p)) {
      _notify(
        m.accountId,
        'Accès retiré',
        'Vous n’avez plus accès au dossier de ${p.name}.',
      );
    }
    _changed();
  }

  /// Notification d'un événement de soin : celui qui a réservé, le titulaire
  /// du dossier et les proches qui suivent les soins de ce patient.
  void _notifyFamily(
    Booking about,
    String title,
    String body, {
    Booking? booking,
  }) {
    final recipients = <String?>{
      about.ownerId,
      _ownerAccountOf(about.patient)?.id,
      for (final m in about.patient.members)
        if (m.activeAt(now) &&
            (m.permissions.contains(FamilyPermission.viewReports) ||
                m.permissions.contains(FamilyPermission.bookCare)))
          m.accountId,
    };
    for (final r in recipients) {
      _notify(r, title, body, booking: booking ?? about);
    }
  }

  // ======================================================= carnet et documents
  /// Formats acceptés pour un document médical.
  static const docExtensions = ['pdf', 'jpg', 'jpeg', 'png'];
  static const maxDocBytes = 10 * 1024 * 1024;

  Future<MedicalDocument> addDocument(
    Patient p, {
    required MedicalDocKind kind,
    required String title,
    required PickedFile file,
    DateTime? documentDate,
  }) async {
    _requireFamilyBackend();
    if (!can(p, FamilyPermission.manageRecords)) {
      throw const BusinessRuleError(
        'Vous ne pouvez pas ajouter de document à ce carnet.',
      );
    }
    final ext = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    if (!docExtensions.contains(ext)) {
      throw const BusinessRuleError(
        'Format non accepté : envoyez une photo (JPG, PNG) ou un PDF.',
      );
    }
    if (file.bytes.length > maxDocBytes) {
      throw const BusinessRuleError(
        'Fichier trop lourd (10 Mo maximum). Reprenez la photo en plus '
        'petit.',
      );
    }
    final t = title.trim().isEmpty ? kind.label : title.trim();
    if (remote != null) {
      late String id;
      await _online((r) async {
        id = await r.addDocument(p.id, kind, t, file, documentDate);
      });
      return familyPatients
          .firstWhere((x) => x.id == p.id)
          .documents
          .firstWhere((d) => d.id == id);
    }
    final d = MedicalDocument(
      id: 'D${_nextDoc++}',
      kind: kind,
      title: t,
      addedAt: now,
      addedBy: patientName,
      fileName: file.name,
      bytes: file.bytes,
      documentDate: documentDate,
    );
    p.documents.insert(0, d);
    final owner = _ownerAccountOf(p);
    if (owner != null && owner != account) {
      _notify(
        owner.id,
        'Nouveau document dans le carnet',
        '$patientName a ajouté « $t » au carnet de ${p.name}.',
      );
    }
    _changed();
    return d;
  }

  /// Masque un document (il reste conservé côté serveur pour la traçabilité).
  Future<void> removeDocument(Patient p, MedicalDocument d) async {
    if (!can(p, FamilyPermission.manageRecords)) {
      throw const BusinessRuleError('Vous ne pouvez pas retirer ce document.');
    }
    if (remote != null) return _online((r) => r.hideDocument(d.id));
    p.documents.remove(d);
    _changed();
  }

  /// Contenu d'un document à afficher.
  Future<Uint8List?> documentBytes(MedicalDocument d) async {
    if (d.bytes != null) return d.bytes;
    if (remote == null || d.storagePath == null) return null;
    try {
      return await remote!.downloadMedicalFile(d.storagePath!);
    } on BusinessRuleError {
      rethrow;
    } catch (_) {
      noteNetworkFailure();
      rethrow;
    }
  }

  /// Constantes relevées lors des soins, de la plus récente à la plus
  /// ancienne.
  List<({DateTime at, String label, String value})> vitalsFor(Patient p) {
    final out = <({DateTime at, String label, String value})>[];
    for (final b in careHistory(p)) {
      if (b.vitals.isNotEmpty) {
        // Mesures structurées saisies par le soignant.
        for (final v in b.vitals) {
          out.add((at: v.at, label: v.kind.label, value: v.display));
        }
        continue;
      }
      final l = b.careLog!;
      void add(String label, String v) {
        if (v.trim().isNotEmpty) {
          out.add((at: l.arrivedAt, label: label, value: v.trim()));
        }
      }

      final t = l.temperature.trim();
      add('Tension', l.bloodPressure);
      add('Température', t.isEmpty || t.contains('°') ? t : '$t °C');
      add('Pouls', l.pulse);
      add('Glycémie', l.glycemia);
    }
    return out;
  }

  // ================================================== accès des soignants
  /// Soignants qui voient en ce moment le carnet de ce patient.
  List<RecordAccess> recordAccessFor(Patient p) {
    if (isRemote) return _remoteAccess[p.id] ?? const [];
    final out = <RecordAccess>[];
    for (final b in bookings.where((b) => b.patient == p)) {
      if (_revokedAccess.contains(b.id)) continue;
      final until = b.endsAt.add(const Duration(hours: 24));
      final open =
          b.status == BookingStatus.pending ||
          b.status == BookingStatus.accepted ||
          (b.status == BookingStatus.done && now.isBefore(until));
      if (!open) continue;
      if (b.contract != null &&
          out.any((a) => a.booking?.contract == b.contract)) {
        continue;
      }
      out.add(
        RecordAccess(
          id: b.id,
          who: '${b.pro.name} · ${b.pro.type.label}',
          scope: b.status == BookingStatus.pending
              ? 'Identité, allergies et traitements, pour décider'
              : 'Carnet complet, le temps du soin',
          until: b.contract?.end.add(const Duration(hours: 24)) ?? until,
          booking: b,
        ),
      );
    }
    return out;
  }

  /// Le soignant de ce soin voit-il encore le carnet du patient ?
  bool proCanSeeRecord(Booking b) {
    if (isRemote) return true; // le serveur ne renvoie que ce qui est permis
    return !_revokedAccess.contains(b.id);
  }

  Future<void> revokeRecordAccess(Patient p, RecordAccess a) async {
    _requireFamilyBackend();
    if (!isOwner(p)) {
      throw const BusinessRuleError(
        'Seul le titulaire du dossier peut retirer un accès.',
      );
    }
    if (remote != null) return _online((r) => r.revokeRecordAccess(a.id));
    final group =
        a.booking?.contract?.sessions ?? [if (a.booking != null) a.booking!];
    for (final b in group) {
      _revokedAccess.add(b.id);
    }
    _notify(
      a.booking?.pro.id,
      'Accès au carnet retiré',
      '${p.name} a retiré votre accès à son carnet de santé.',
    );
    _changed();
  }

  // =============================================================== recherche
  static String _fold(String s) {
    const from = 'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ’\'';
    const to = 'aaaeeeeiioouuucAAAEEEEIIOOUUUC  ';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      b.write(i == -1 ? ch : to[i]);
    }
    return b.toString().toLowerCase();
  }

  /// Soignants vérifiés de la commune qui correspondent aux critères.
  List<ProMatch> searchPros(SearchFilters f) {
    final service = f.serviceId == null
        ? null
        : services.where((s) => s.id == f.serviceId).firstOrNull;
    final words = _fold(f.query)
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toList();
    final out = <ProMatch>[];
    for (final p in pros) {
      if (!p.activeAt(now) || !p.communes.contains(f.commune)) continue;
      if (service != null && !p.prices.containsKey(service.id)) continue;
      if (f.proType != null && p.type != f.proType) continue;
      if (f.nightOnly && !p.nightAvailable) continue;
      if (p.rating < f.minRating) continue;
      final price = service != null ? p.prices[service.id]! : p.fromPrice;
      if (f.maxPrice != null && price > f.maxPrice!) continue;
      if (words.isNotEmpty) {
        final hay = _fold(
          [
            p.name,
            p.type.label,
            p.bio,
            for (final id in p.prices.keys)
              services.where((s) => s.id == id).firstOrNull?.name ?? '',
          ].join(' '),
        );
        if (!words.every(hay.contains)) continue;
      }
      out.add(ProMatch(p, price, service: service));
    }
    int byPremium(ProMatch a, ProMatch b) =>
        (b.pro.isPremium(now) ? 1 : 0) - (a.pro.isPremium(now) ? 1 : 0);
    out.sort((a, b) {
      switch (f.sort) {
        case SearchSort.recommended:
          final c = byPremium(a, b);
          return c != 0 ? c : b.pro.rating.compareTo(a.pro.rating);
        case SearchSort.priceAsc:
          return a.price.compareTo(b.price);
        case SearchSort.ratingDesc:
          return b.pro.rating.compareTo(a.pro.rating);
        case SearchSort.experienceDesc:
          return b.pro.yearsExperience.compareTo(a.pro.yearsExperience);
      }
    });
    return out;
  }

  /// Soins proposés par un soignant, dans l'ordre du catalogue.
  List<CareService> servicesOf(Pro p) =>
      services.where((s) => p.prices.containsKey(s.id)).toList();

  // ============================================================== pharmacies
  /// Pharmacies d'une commune : celles de garde en premier.
  List<Pharmacy> pharmaciesIn(String commune, {bool onDutyOnly = false}) {
    final list = pharmacies
        .where((p) => p.commune == commune)
        .where((p) => !onDutyOnly || p.onDutyAt(now))
        .toList();
    list.sort((a, b) {
      final d = (b.onDutyAt(now) ? 1 : 0) - (a.onDutyAt(now) ? 1 : 0);
      return d != 0 ? d : a.name.compareTo(b.name);
    });
    return list;
  }

  // ================================================================= rappels
  /// Ce qui demande une action ou arrive bientôt, le plus urgent d'abord.
  List<CareReminder> get reminders {
    final out = <CareReminder>[];
    final seenContracts = <Contract>{};
    for (final b in patientBookings) {
      if (b.contract != null) {
        if (seenContracts.contains(b.contract)) continue;
      }
      final who = b.patient == patients.firstOrNull ? 'vous' : b.patientName;
      if (b.awaitingPayment && _isMine(b)) {
        if (b.contract != null) seenContracts.add(b.contract!);
        out.add(
          CareReminder(
            title:
                'Paiement à faire avant ${AppState._time(b.paymentDeadline!)}',
            body:
                '${b.pro.name} a confirmé ${b.service.name} pour $who. Sans '
                'paiement, le rendez-vous est annulé.',
            booking: b,
            urgent: true,
          ),
        );
      } else if (b.readyForCare &&
          b.scheduledAt.isAfter(now) &&
          b.scheduledAt.isBefore(DateTime(now.year, now.month, now.day + 2))) {
        // Aujourd'hui ou demain : on prévient la veille.
        out.add(
          CareReminder(
            title:
                '${_dayWord(b.scheduledAt)} à ${AppState._time(b.scheduledAt)} : ${b.service.name}',
            body:
                '${b.pro.name} vient pour $who. '
                '${b.hasPrescription ? 'Préparez l’ordonnance. ' : ''}'
                'Prévenez la personne sur place.',
            booking: b,
          ),
        );
      } else if (b.status == BookingStatus.pending &&
          (b.contract == null || seenContracts.add(b.contract!))) {
        out.add(
          CareReminder(
            title: 'En attente de ${b.pro.name}',
            body:
                'Réponse au plus tard à ${AppState._time(b.responseDeadline)}. '
                'Vous serez prévenu dès sa réponse.',
            booking: b,
          ),
        );
      } else if (b.status == BookingStatus.done &&
          b.rating == null &&
          _isMine(b) &&
          now.difference(b.scheduledAt) <= const Duration(days: 14)) {
        out.add(
          CareReminder(
            title: 'Notez le soin de ${b.pro.name}',
            body: 'Votre avis aide les autres familles à choisir.',
            booking: b,
          ),
        );
      }
    }
    // Urgent d'abord, puis ce qui arrive bientôt, puis ce qui attend une
    // réponse, enfin les notes à donner (tri stable).
    int rank(CareReminder r) {
      if (r.urgent) return 0;
      final b = r.booking;
      if (b == null) return 4;
      if (b.readyForCare) return 1;
      if (b.status == BookingStatus.pending) return 2;
      return 3;
    }

    final indexed = [for (var i = 0; i < out.length; i++) (i, out[i])];
    indexed.sort((a, b) {
      final c = rank(a.$2).compareTo(rank(b.$2));
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  String _dayWord(DateTime d) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    return switch (day.difference(today).inDays) {
      0 => 'Aujourd’hui',
      1 => 'Demain',
      _ => 'Le ${AppState._two(d.day)}/${AppState._two(d.month)}',
    };
  }

  /// Qui a réservé ce soin, vu par le compte connecté.
  String bookerName(Booking b) {
    if (_isMine(b)) return 'vous';
    final a = accounts.where((a) => a.id == b.ownerId).firstOrNull;
    return a?.name.isNotEmpty == true ? a!.name : 'un proche';
  }

  /// Suivis réguliers en cours que le compte voit (une entrée par suivi).
  List<Contract> get activeContracts {
    final seen = <Contract>{};
    for (final b in patientBookings) {
      final c = b.contract;
      if (c != null &&
          c.sessions.any(
            (s) =>
                s.status == BookingStatus.pending ||
                s.status == BookingStatus.accepted,
          )) {
        seen.add(c);
      }
    }
    return seen.toList();
  }

  /// Prochain soin à venir parmi ceux que le compte suit.
  Booking? get nextBooking => patientBookings
      .where(
        (b) =>
            (b.status == BookingStatus.accepted ||
                b.status == BookingStatus.pending) &&
            b.endsAt.isAfter(now),
      )
      .firstOrNull;

  // ============================================================ réclamations
  Future<Complaint> openComplaint({
    required ComplaintCategory category,
    required String description,
    Booking? booking,
  }) async {
    _requireFamilyBackend();
    final text = description.trim();
    if (text.length < 10) {
      throw const BusinessRuleError(
        'Décrivez ce qui s’est passé en une ou deux phrases.',
      );
    }
    if (booking != null && !_visibleToPatientSide(booking)) {
      throw const BusinessRuleError('Rendez-vous introuvable.');
    }
    if (remote != null) {
      late String id;
      await _online((r) async {
        id = await r.openComplaint(booking?.id, category, text);
      });
      return complaints.firstWhere((c) => c.id == id);
    }
    final c = Complaint(
      id: 'RC${_nextComplaint++}',
      category: category,
      description: text,
      createdAt: now,
      booking: booking,
    );
    complaints.insert(0, c);
    _notify(
      'admin',
      category == ComplaintCategory.safety
          ? 'Urgent : signalement de sécurité'
          : 'Nouvelle réclamation',
      '${category.label}${booking == null ? '' : ' · ${booking.service.name} avec ${booking.pro.name}'}.',
    );
    _notify(
      account?.id,
      'Réclamation reçue',
      'Le support MyNurse vous répond sous 24 h. Vous suivez son avancement '
          'dans « Mes réclamations ».',
    );
    _changed();
    return c;
  }
}

/// Prénom et initiale du nom (« Awa B. ») pour un avis public.
String _shortName(String full) {
  final parts = full.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return 'Patient';
  return parts.length == 1 ? parts.first : '${parts.first} ${parts[1][0]}.';
}
