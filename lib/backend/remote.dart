import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart' show BusinessRuleError;
import '../data/demo_data.dart' show demoServices;
import '../models.dart';

/// Correspondances entre les valeurs de l'app et celles de la base.
const _proTypes = {
  ProType.infirmier: 'infirmier',
  ProType.aideSoignant: 'aide_soignant',
  ProType.medecin: 'medecin',
  ProType.kine: 'kine',
  ProType.sageFemme: 'sage_femme',
};
const _docTypes = {
  DocType.diplome: 'diplome',
  DocType.autorisation: 'autorisation',
  DocType.ordre: 'ordre',
  DocType.cni: 'cni',
  DocType.rcPro: 'rc_pro',
};
const _frequencies = {
  Frequency.daily: 'daily',
  Frequency.everyOtherDay: 'every_other_day',
  Frequency.weekly: 'weekly',
};
const _txKinds = {
  'topup': WalletTxKind.topUp,
  'payment': WalletTxKind.payment,
  'refund': WalletTxKind.refund,
  'earning': WalletTxKind.earning,
  'withdrawal': WalletTxKind.withdrawal,
  'subscription': WalletTxKind.subscription,
};

K _key<K>(Map<K, String> m, String v) =>
    m.entries.firstWhere((e) => e.value == v).key;
T _enum<T extends Enum>(List<T> values, String v) =>
    values.firstWhere((e) => e.name == v);
DateTime _date(dynamic v) => DateTime.parse(v as String).toLocal();
DateTime? _dateOrNull(dynamic v) => v == null ? null : _date(v);
String _iso(DateTime d) => d.toUtc().toIso8601String();
int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

/// Un fichier choisi par l'utilisateur (pièce justificative).
typedef PickedFile = ({String name, Uint8List bytes});

/// Tout ce que l'utilisateur connecté a le droit de voir.
class RemoteSnapshot {
  RemoteSnapshot({
    required this.role,
    required this.fullName,
    required this.services,
    required this.pros,
    required this.myPatients,
    required this.bookings,
    required this.walletBalance,
    required this.walletHistory,
    required this.clientBalances,
    required this.proBalances,
    required this.premiumRevenue,
    required this.notifications,
    this.sharedPatients = const [],
    this.pharmacies = const [],
    this.complaints = const [],
    this.recordAccess = const {},
    this.hasFamilyTables = false,
    this.incidents = const [],
    this.adminPermissions = const {},
    this.adminPatientCount,
  });

  final UserRole role;
  final String fullName;
  final List<CareService> services;
  final List<Pro> pros;
  final List<Patient> myPatients;
  final List<Booking> bookings;
  final int walletBalance;
  final List<WalletTx> walletHistory;

  /// Totaux visibles par l'administration seulement.
  final int clientBalances;
  final int proBalances;
  final int premiumRevenue;
  final List<AppNotification> notifications;

  /// Famille et carnet (migrations 0009-0011) ; vides si absentes.
  final List<Patient> sharedPatients;
  final List<Pharmacy> pharmacies;
  final List<Complaint> complaints;
  final Map<String, List<RecordAccess>> recordAccess;
  final bool hasFamilyTables;

  /// Incidents signalés par le soignant connecté (0012).
  final List<Incident> incidents;

  /// Permissions du membre de l'équipe connecté, et nombre de patients
  /// (comptage serveur, sans données nominatives).
  final Set<AdminPermission> adminPermissions;
  final int? adminPatientCount;
}

/// Accès à la base Supabase. Les règles sont appliquées par le serveur ;
/// les erreurs remontent en [BusinessRuleError] avec son message.
class RemoteBackend {
  RemoteBackend(this.client);

  final SupabaseClient client;

  String? get userId => client.auth.currentUser?.id;

  /// Le serveur a-t-il les tables famille et carnet (migrations 0009-0011) ?
  /// Détecté au chargement ; sans elles, l'app garde le fonctionnement V1.
  bool hasFamilyTables = false;

  /// Le serveur a-t-il l'espace soignant (migration 0012) ?
  bool hasProTables = false;
  bool get signedIn => client.auth.currentSession != null;

  /// Exécute un appel et traduit les erreurs du serveur.
  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      throw BusinessRuleError(_clean(e.message));
    } on AuthException catch (e) {
      throw BusinessRuleError(_authMessage(e));
    } on StorageException catch (e) {
      throw BusinessRuleError('Envoi du fichier impossible : ${e.message}');
    }
  }

  static String _clean(String m) {
    if (m.contains('bookings_no_overlap')) {
      return 'Ce soignant a déjà un soin à cette heure.';
    }
    if (m.contains('row-level security') || m.contains('permission denied')) {
      return 'Action non autorisée pour ce compte.';
    }
    return m;
  }

  static String _authMessage(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('expired') || m.contains('invalid')) {
      return 'Code incorrect ou expiré. Demandez un nouveau code.';
    }
    if (m.contains('rate') || m.contains('security purposes')) {
      return 'Trop de demandes de code. Patientez une minute.';
    }
    return e.message;
  }

  // -------------------------------------------------------------- connexion
  /// Envoie le code. [role] null : connexion à un compte existant seulement.
  Future<void> sendCode(String email, {UserRole? role}) async {
    try {
      await _call(
        () => client.auth.signInWithOtp(
          email: email,
          shouldCreateUser: role != null,
          data: role == null
              ? null
              : {'role': role == UserRole.pro ? 'pro' : 'patient'},
        ),
      );
    } on BusinessRuleError catch (e) {
      final m = e.message.toLowerCase();
      if (role == null && (m.contains('signup') || m.contains('not found'))) {
        throw const BusinessRuleError(
          'Aucun compte avec cette adresse. Vérifiez-la ou créez un compte.',
        );
      }
      rethrow;
    }
  }

  Future<void> markRead(List<String> ids) => _call(
    () => client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .inFilter('id', ids),
  );

  Future<void> verifyCode(String email, String code) => _call(
    () => client.auth.verifyOTP(email: email, token: code, type: OtpType.email),
  );

  Future<void> signOut() => client.auth.signOut();

  // -------------------------------------------------------------- lecture
  Future<RemoteSnapshot> load() => _call(() async {
    final uid = userId!;
    final profile = await client
        .from('profiles')
        .select('role, full_name')
        .eq('id', uid)
        .single();
    final role = _enum(UserRole.values, profile['role'] as String);

    final results = await Future.wait([
      client.from('services').select().eq('active', true),
      client
          .from('pros')
          .select('*, pro_services(service_id, price), pro_documents(*)'),
      client.from('pro_cancellations').select('pro_id, created_at'),
      client.from('patients').select(),
      client.from('contracts').select('id, frequency'),
      client
          .from('bookings')
          .select('*, care_logs(*), reviews(rating, comment)')
          .order('scheduled_at')
          .limit(2000),
      client
          .from('wallet_transactions')
          .select('kind, amount, label, created_at, owner_id')
          .order('created_at', ascending: false)
          .limit(500),
      client.from('wallets').select('owner_id, balance, profiles(role)'),
      client
          .from('notifications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(100),
    ]);

    // Catalogue, dans l'ordre de l'app.
    final order = demoServices.map((s) => s.id).toList();
    final services = [
      for (final r in results[0])
        CareService(
          id: r['id'] as String,
          name: r['name'] as String,
          proType: _key(_proTypes, r['pro_type'] as String),
          minPrice: _int(r['min_price']),
          maxPrice: _int(r['max_price']),
          needsPrescription: r['needs_prescription'] as bool,
          durationMinutes: _int(r['duration_minutes']),
        ),
    ]..sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));

    // Soignants.
    final pros = <String, Pro>{};
    final referrers = <String, String>{};
    for (final r in results[1]) {
      final type = _key(_proTypes, r['pro_type'] as String);
      final docs = (r['pro_documents'] as List).cast<Map<String, dynamic>>();
      final p = Pro(
        id: r['id'] as String,
        name: r['display_name'] as String,
        type: type,
        communes: (r['communes'] as List).cast<String>(),
        prices: {
          for (final ps in (r['pro_services'] as List))
            ps['service_id'] as String: _int(ps['price']),
        },
        yearsExperience: _int(r['years_experience']),
        bio: r['bio'] as String,
        orderNumber: (r['order_number'] as String?) ?? '',
        rating: (r['rating_avg'] as num).toDouble(),
        ratingCount: _int(r['rating_count']),
        careCount: _int(r['care_count']),
        status: VerificationStatusLabel.fromDb(
          r['verification_status'] as String,
        ),
        nightAvailable: r['night_available'] as bool,
        documents: {
          for (final d in docs) _key(_docTypes, d['doc_type'] as String),
        },
        rejectionReason: r['rejection_reason'] as String,
        premiumUntil: _dateOrNull(r['premium_until']),
      )..referralRewarded = r['referral_rewarded'] as bool;
      for (final d in docs) {
        final type = _key(_docTypes, d['doc_type'] as String);
        p.documentPaths[type] = d['storage_path'] as String;
        // Date de validité (0012) : on garde la plus lointaine par pièce.
        if (d['expires_on'] case final String e) {
          final date = DateTime.parse(e);
          final known = p.documentExpiry[type];
          if (known == null || date.isAfter(known)) {
            p.documentExpiry[type] = date;
          }
        }
      }
      if (r['referred_by'] != null) {
        referrers[p.id] = r['referred_by'] as String;
      }
      pros[p.id] = p;
    }
    referrers.forEach((id, by) => pros[id]!.referredBy = pros[by]);
    for (final c in results[2]) {
      pros[c['pro_id']]?.cancellations.add(_date(c['created_at']));
    }
    // Soignant connecté : son propre wallet.
    final me = pros[uid];

    // Patients visibles.
    final patients = <String, Patient>{};
    final mine = <Patient>[];
    for (final r in results[3]) {
      final birth = r['birth_date'] as String?;
      final p = Patient(
        id: r['id'] as String,
        name: r['full_name'] as String,
        relation: _relationLabel(r['relation'] as String),
        birthYear: birth == null ? null : int.parse(birth.substring(0, 4)),
        allergies: r['allergies'] as String,
        history: r['history'] as String,
        treatments: r['treatments'] as String,
        commune: (r['commune'] as String?) ?? '',
      );
      patients[p.id] = p;
      if (r['owner_id'] == uid) mine.add(p);
    }
    // Le titulaire en premier, puis ses proches.
    mine.sort(
      (a, b) =>
          (a.relation == 'Moi' ? 0 : 1).compareTo(b.relation == 'Moi' ? 0 : 1),
    );

    // Suivis.
    final contracts = {
      for (final r in results[4])
        r['id'] as String: Contract(
          id: r['id'] as String,
          frequency: _key(_frequencies, r['frequency'] as String),
        ),
    };

    final servicesById = {for (final s in services) s.id: s};
    final bookings = <Booking>[];
    final sessions = <String, List<Booking>>{};
    for (final r in results[5]) {
      final pro = pros[r['pro_id']];
      final service = servicesById[r['service_id']];
      if (pro == null || service == null) continue;
      final contract = contracts[r['contract_id']];
      final lat = r['location_lat'] as num?;
      final lng = r['location_lng'] as num?;
      final b =
          Booking(
              id: r['id'] as String,
              patient:
                  patients[r['patient_id']] ??
                  Patient(id: r['patient_id'] as String, name: 'Patient'),
              ownerId: r['booked_by'] as String,
              service: service,
              pro: pro,
              commune: r['commune'] as String,
              address: r['address'] as String,
              scheduledAt: _date(r['scheduled_at']),
              basePrice: _int(r['base_price']),
              hasPrescription: r['has_prescription'] as bool,
              note: r['note'] as String,
              status: _enum(BookingStatus.values, r['status'] as String),
              createdAt: _date(r['created_at']),
              contract: contract,
              sessionIndex: _int(r['session_index']),
              commissionRate: (r['commission_rate'] as num).toDouble(),
              location: lat == null || lng == null
                  ? null
                  : GeoPoint(lat.toDouble(), lng.toDouble()),
            )
            ..acceptedAt = _dateOrNull(r['accepted_at'])
            ..paidAt = _dateOrNull(r['paid_at'])
            ..paymentMethod = r['payment_method'] == null
                ? null
                : _enum(PaymentMethod.values, r['payment_method'] as String)
            ..refunded = r['refunded'] as bool
            ..cancelReason = r['cancel_reason'] as String
            ..cancellationFee = _int(r['cancellation_fee'])
            ..receiptNumber = r['receipt_number'] as String?;
      final log = _one(r['care_logs']);
      if (log != null) {
        b.careLog = CareLog(
          arrivedAt: _date(log['arrived_at']),
          leftAt: _date(log['left_at']),
          acts: log['acts'] as String,
          bloodPressure: log['blood_pressure'] as String,
          temperature: log['temperature'] as String,
          pulse: log['pulse'] as String,
          glycemia: log['glycemia'] as String,
          observations: log['observations'] as String,
        );
      }
      final review = _one(r['reviews']);
      if (review != null) {
        b.rating = _int(review['rating']);
        b.review = review['comment'] as String;
      }
      bookings.add(b);
      if (contract != null) sessions.putIfAbsent(contract.id, () => []).add(b);
    }
    sessions.forEach((id, list) {
      list.sort((a, b) => a.sessionIndex.compareTo(b.sessionIndex));
      contracts[id]!.sessions.addAll(list);
    });

    // Soldes.
    List<WalletTx> txsOf(String owner) => [
      for (final t in results[6])
        if (t['owner_id'] == owner)
          WalletTx(
            at: _date(t['created_at']),
            kind: _txKinds[t['kind']]!,
            amount: _int(t['amount']),
            label: t['label'] as String,
          ),
    ];
    var myBalance = 0, clients = 0, prosTotal = 0;
    for (final w in results[7]) {
      final balance = _int(w['balance']);
      if (w['owner_id'] == uid) myBalance = balance;
      final ownerRole = (w['profiles'] as Map?)?['role'];
      if (ownerRole == 'pro') {
        prosTotal += balance;
      } else {
        clients += balance;
      }
      final p = pros[w['owner_id']];
      if (p != null) {
        p.wallet.replaceWith(balance, txsOf(p.id));
      }
    }
    final premium = results[6]
        .where((t) => t['kind'] == 'subscription')
        .fold<int>(0, (s, t) => s - _int(t['amount']));

    final bookingsById = {for (final b in bookings) b.id: b};
    final notifications = [
      for (final n in results[8])
        AppNotification(
          id: n['id'] as String,
          recipient: switch (role) {
            UserRole.admin => 'admin',
            _ => uid,
          },
          at: _date(n['created_at']),
          title: n['title'] as String,
          body: n['body'] as String,
          booking: bookingsById[n['booking_id']],
          read: n['read_at'] != null,
        ),
    ];

    final family = await _loadFamily(
      uid: uid,
      patients: patients,
      mine: mine,
      pros: pros,
      bookingsById: bookingsById,
    );
    hasFamilyTables = family != null;
    final incidents = await _loadPro(
      uid: uid,
      me: pros[uid],
      bookingsById: bookingsById,
    );
    for (final r in results[5]) {
      if (r['refusal_reason'] case final String reason when reason.isNotEmpty) {
        bookingsById[r['id']]?.refusalReason = reason;
      }
      // Remboursements accordés par l'équipe (0013).
      if (r['admin_refunded'] case final num v when v > 0) {
        bookingsById[r['id']]?.adminRefunded = v.toInt();
      }
    }

    // Administration : permissions et comptages (0013). Sans la fonction
    // sur le serveur, l'ancien fonctionnement (admin = tous les droits, sauf
    // l'accès d'urgence au dossier) est conservé.
    ({int patients, Set<AdminPermission> perms})? admin;
    if (role == UserRole.admin) {
      try {
        admin = await adminContext();
      } on BusinessRuleError catch (e) {
        if (!e.message.contains('Could not find')) rethrow;
      }
    }

    return RemoteSnapshot(
      adminPermissions:
          admin?.perms ??
          (role == UserRole.admin
              ? {
                  for (final p in AdminPermission.values)
                    if (p != AdminPermission.medicalBreakGlass) p,
                }
              : const {}),
      adminPatientCount: admin?.patients,
      incidents: incidents,
      sharedPatients: family?.shared ?? const [],
      pharmacies: family?.pharmacies ?? const [],
      complaints: family?.complaints ?? const [],
      recordAccess: family?.access ?? const {},
      hasFamilyTables: family != null,
      role: role,
      fullName: profile['full_name'] as String,
      services: services,
      pros: pros.values.toList(),
      myPatients: mine,
      bookings: bookings.reversed.toList(),
      walletBalance: me?.wallet.balance ?? myBalance,
      walletHistory: me != null ? me.wallet.history.toList() : txsOf(uid),
      clientBalances: clients,
      proBalances: prosTotal,
      premiumRevenue: premium,
      notifications: notifications,
    );
  });

  /// Proches, carnet, documents, accès, pharmacies, réclamations, avis.
  /// Renvoie null si le serveur n'a pas encore ces tables : l'app garde
  /// alors le fonctionnement V1 sans erreur.
  Future<
    ({
      List<Patient> shared,
      List<Pharmacy> pharmacies,
      List<Complaint> complaints,
      Map<String, List<RecordAccess>> access,
    })?
  >
  _loadFamily({
    required String uid,
    required Map<String, Patient> patients,
    required List<Patient> mine,
    required Map<String, Pro> pros,
    required Map<String, Booking> bookingsById,
  }) async {
    final List<List<dynamic>> r;
    try {
      r = await Future.wait<List<dynamic>>([
        client.from('patient_members').select().isFilter('revoked_at', null),
        client.rpc('my_shared_patients').then((v) => v as List<dynamic>),
        client.from('medical_records').select(),
        client
            .from('medical_documents')
            .select()
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false),
        client
            .from('record_access_grants')
            .select(
              'id, patient_id, grantee_id, scopes, expires_at, booking_id',
            )
            .isFilter('revoked_at', null)
            .gt('expires_at', DateTime.now().toUtc().toIso8601String()),
        client.from('pharmacies').select().eq('active', true),
        client
            .from('complaints')
            .select()
            .order('created_at', ascending: false),
        client
            .from('reviews')
            .select('pro_id, rating, comment, created_at')
            .order('created_at', ascending: false)
            .limit(500),
      ]);
    } on PostgrestException catch (e) {
      // Table ou fonction absente : migrations pas encore appliquées.
      if (const ['42P01', '42883', 'PGRST202', 'PGRST205'].contains(e.code)) {
        return null;
      }
      rethrow;
    }
    Set<FamilyPermission> perms(dynamic v) => {
      for (final x in (v as List).cast<String>())
        FamilyPermission.values.firstWhere((p) => p.dbName == x),
    };

    // Proches autorisés sur mes dossiers.
    final mineIds = {for (final p in mine) p.id};
    for (final m in r[0]) {
      final p = patients[m['patient_id']];
      if (p == null || !mineIds.contains(p.id)) continue;
      p.members.add(
        FamilyMember(
          id: m['id'] as String,
          name: (m['display_name'] as String?)?.isNotEmpty == true
              ? m['display_name'] as String
              : 'Proche',
          contact: (m['contact_hint'] as String?) ?? '',
          relation: (m['relation_label'] as String?) ?? '',
          permissions: perms(m['permissions']),
          addedAt: _date(m['created_at']),
          accountId: m['member_id'] as String,
          expiresAt: _dateOrNull(m['expires_at']),
        ),
      );
    }
    // Dossiers qu'on m'a confiés.
    final shared = <Patient>[];
    for (final row in r[1]) {
      final p = patients[row['patient_id']];
      if (p == null) continue;
      p.ownerName = row['owner_name'] as String;
      p.members.add(
        FamilyMember(
          id: row['member_id'] as String,
          name: 'Vous',
          contact: '',
          relation: '',
          permissions: perms(row['permissions']),
          addedAt: DateTime.now(),
          accountId: uid,
          expiresAt: _dateOrNull(row['expires_at']),
        ),
      );
      shared.add(p);
    }
    // Carnet : le dossier fait foi quand il existe.
    for (final m in r[2]) {
      final p = patients[m['patient_id']];
      if (p == null) continue;
      p
        ..allergies = m['allergies'] as String
        ..treatments = m['current_treatments'] as String
        ..history = m['history'] as String
        ..bloodGroup = (m['blood_group'] as String?) ?? ''
        ..emergencyContact = (m['emergency_contact_name'] as String?) ?? '';
    }
    for (final d in r[3]) {
      final p = patients[d['patient_id']];
      if (p == null) continue;
      final path = d['storage_path'] as String;
      p.documents.add(
        MedicalDocument(
          id: d['id'] as String,
          kind: MedicalDocKind.values.firstWhere(
            (k) => k.dbName == d['kind'],
            orElse: () => MedicalDocKind.other,
          ),
          title: d['title'] as String,
          addedAt: _date(d['created_at']),
          addedBy: d['uploaded_by'] == uid
              ? 'vous'
              : pros.containsKey(d['uploaded_by'])
              ? pros[d['uploaded_by']]!.name
              : 'un proche',
          fileName: path.split('/').last,
          storagePath: path,
          documentDate: d['document_date'] == null
              ? null
              : DateTime.parse(d['document_date'] as String),
        ),
      );
    }
    // Accès des soignants à mes dossiers.
    final access = <String, List<RecordAccess>>{};
    for (final g in r[4]) {
      if (!mineIds.contains(g['patient_id']) || g['grantee_id'] == uid) {
        continue;
      }
      final scopes = (g['scopes'] as List).cast<String>();
      final pro = pros[g['grantee_id']];
      access
          .putIfAbsent(g['patient_id'] as String, () => [])
          .add(
            RecordAccess(
              id: g['id'] as String,
              who: pro == null
                  ? 'Équipe MyNurse (accès d’urgence)'
                  : '${pro.name} · ${pro.type.label}',
              scope: scopes.length == 1 && scopes.first == 'summary'
                  ? 'Identité, allergies et traitements, pour décider'
                  : 'Carnet complet, le temps du soin',
              until: _date(g['expires_at']),
              booking: bookingsById[g['booking_id']],
            ),
          );
    }
    final pharmacies = [
      for (final ph in r[5])
        Pharmacy(
          id: ph['id'] as String,
          name: ph['name'] as String,
          commune: ph['commune'] as String,
          address: ph['address'] as String,
          phone: (ph['phone'] as String?) ?? '',
          location: ph['location_lat'] == null || ph['location_lng'] == null
              ? null
              : GeoPoint(
                  (ph['location_lat'] as num).toDouble(),
                  (ph['location_lng'] as num).toDouble(),
                ),
          onDutyFrom: _dateOrNull(ph['on_duty_from']),
          onDutyUntil: _dateOrNull(ph['on_duty_until']),
        ),
    ];
    const statuses = {
      'open': ComplaintStatus.open,
      'in_review': ComplaintStatus.inReview,
      'resolved': ComplaintStatus.resolved,
      'rejected': ComplaintStatus.rejected,
    };
    final complaints = [
      for (final c in r[6])
        Complaint(
          id: c['id'] as String,
          category: ComplaintCategory.values.firstWhere(
            (k) => k.dbName == c['category'],
            orElse: () => ComplaintCategory.other,
          ),
          description: c['description'] as String,
          createdAt: _date(c['created_at']),
          booking: bookingsById[c['booking_id']],
          status: statuses[c['status']] ?? ComplaintStatus.open,
          resolution: (c['resolution'] as String?) ?? '',
        ),
    ];
    for (final rv in r[7]) {
      pros[rv['pro_id']]?.reviews.add(
        ProReview(
          rating: _int(rv['rating']),
          comment: (rv['comment'] as String?) ?? '',
          at: _date(rv['created_at']),
        ),
      );
    }
    return (
      shared: shared,
      pharmacies: pharmacies,
      complaints: complaints,
      access: access,
    );
  }

  /// Espace soignant : disponibilités, mesures (0010-0011), journal de
  /// visite et incidents (0012). Chaque bloc est facultatif : sans les
  /// tables sur le serveur, l'app garde le fonctionnement précédent.
  Future<List<Incident>> _loadPro({
    required String uid,
    required Pro? me,
    required Map<String, Booking> bookingsById,
  }) async {
    bool missing(PostgrestException e) =>
        const ['42P01', '42883', 'PGRST202', 'PGRST205'].contains(e.code);
    if (hasFamilyTables) {
      try {
        final r = await Future.wait<List<dynamic>>([
          client.from('vital_signs').select().eq('entered_in_error', false),
          if (me != null)
            client.from('availability_rules').select().eq('pro_id', uid),
          if (me != null)
            client
                .from('availability_exceptions')
                .select()
                .eq('pro_id', uid)
                .eq('kind', 'off'),
        ]);
        for (final v in r[0]) {
          final b = bookingsById[v['booking_id']];
          if (b == null) continue;
          b.vitals.add(
            VitalSign(
              kind: VitalKind.values.firstWhere(
                (k) => k.dbName == v['kind'],
                orElse: () => VitalKind.temperature,
              ),
              value: (v['value'] as num).toDouble(),
              value2: (v['value2'] as num?)?.toDouble(),
              at: _date(v['measured_at']),
              by: v['recorded_by'] == b.pro.id ? b.pro.name : 'un proche',
              booking: b,
            ),
          );
        }
        if (me != null) {
          int minutes(String t) =>
              int.parse(t.substring(0, 2)) * 60 + int.parse(t.substring(3, 5));
          me.availability.addAll([
            for (final a in r[1])
              AvailabilityRule(
                _int(a['weekday']),
                minutes(a['start_time'] as String),
                minutes(a['end_time'] as String),
              ),
          ]);
          for (final e in r[2]) {
            // Intervalle PostgreSQL : ["début","fin")
            final parts = (e['period'] as String)
                .replaceAll(RegExp(r'[\[\]()"]'), '')
                .split(',');
            if (parts.length == 2) {
              me.daysOff.add((
                from: DateTime.parse(parts[0].trim()).toLocal(),
                to: DateTime.parse(parts[1].trim()).toLocal(),
                reason: (e['reason'] as String?) ?? '',
              ));
            }
          }
        }
      } on PostgrestException catch (e) {
        if (!missing(e)) rethrow;
      }
    }
    try {
      final r = await Future.wait<List<dynamic>>([
        client.from('care_journal_entries').select().order('created_at'),
        client
            .from('incident_reports')
            .select()
            .order('created_at', ascending: false),
      ]);
      hasProTables = true;
      for (final j in r[0]) {
        bookingsById[j['booking_id']]?.journal.add(
          JournalEntry(
            switch (j['kind']) {
              'on_the_way' => JournalKind.onTheWay,
              'arrived' => JournalKind.arrived,
              'left' => JournalKind.left,
              _ => JournalKind.note,
            },
            _date(j['created_at']),
            (j['text'] as String?) ?? '',
          ),
        );
      }
      return [
        for (final i in r[1])
          Incident(
            id: i['id'] as String,
            category: IncidentCategory.values.firstWhere(
              (c) => c.dbName == i['category'],
              orElse: () => IncidentCategory.other,
            ),
            description: i['description'] as String,
            at: _date(i['created_at']),
            booking: bookingsById[i['booking_id']],
            status: switch (i['status']) {
              'in_review' => 'En cours',
              'closed' => 'Traité',
              _ => 'Envoyé',
            },
          ),
      ];
    } on PostgrestException catch (e) {
      if (!missing(e)) rethrow;
      hasProTables = false;
      return const [];
    }
  }

  static Map<String, dynamic>? _one(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is List && v.isNotEmpty) return v.first as Map<String, dynamic>;
    return null;
  }

  static String _relationLabel(String r) => r == 'moi' ? 'Moi' : r;

  // ------------------------------------------------------------- patients
  Future<void> completeProfile(String fullName) => _call(() async {
    await client
        .from('profiles')
        .update({'full_name': fullName})
        .eq('id', userId!);
    final existing = await client
        .from('patients')
        .select('id')
        .eq('owner_id', userId!)
        .eq('relation', 'moi');
    if ((existing as List).isEmpty) {
      await client.from('patients').insert({
        'owner_id': userId,
        'full_name': fullName,
        'relation': 'moi',
      });
    }
  });

  Future<String> addPatient({
    required String name,
    required String relation,
    required String allergies,
    int? birthYear,
    String commune = '',
  }) => _call(() async {
    final row = await client
        .from('patients')
        .insert({
          'owner_id': userId,
          'full_name': name,
          'relation': relation,
          'allergies': allergies,
          'birth_date': ?(birthYear == null ? null : '$birthYear-01-01'),
          // Colonne ajoutée par la migration 0010 (envoyée seulement si
          // elle existe sur le serveur).
          if (hasFamilyTables && commune.isNotEmpty) 'commune': commune,
        })
        .select('id')
        .single();
    return row['id'] as String;
  });

  /// Met à jour le carnet. Avec les migrations 0010+, le dossier médical
  /// fait foi (un proche autorisé peut le modifier) ; le titulaire met aussi
  /// à jour l'ancienne fiche, encore lue par les versions précédentes.
  Future<void> updatePatient(
    String id, {
    required String allergies,
    required String history,
    required String treatments,
    String? bloodGroup,
    String? emergencyContact,
    bool owner = true,
  }) => _call(() async {
    if (owner) {
      await client
          .from('patients')
          .update({
            'allergies': allergies,
            'history': history,
            'treatments': treatments,
          })
          .eq('id', id);
    }
    if (!hasFamilyTables) return;
    await client.from('medical_records').upsert({
      'patient_id': id,
      'allergies': allergies,
      'history': history,
      'current_treatments': treatments,
      'blood_group': ?(bloodGroup == null || bloodGroup.isEmpty
          ? null
          : bloodGroup),
      'emergency_contact_name': ?emergencyContact,
    });
  });

  // ------------------------------------------------------------ réservations
  Map<String, dynamic> _bookingRow({
    required String patientId,
    required String proId,
    required String serviceId,
    required String commune,
    required String address,
    required DateTime at,
    required bool hasPrescription,
    required String note,
    GeoPoint? location,
  }) => {
    'booked_by': userId,
    'patient_id': patientId,
    'pro_id': proId,
    'service_id': serviceId,
    'commune': commune,
    'address': address,
    'scheduled_at': _iso(at),
    'has_prescription': hasPrescription,
    'note': note,
    'location_lat': ?location?.lat,
    'location_lng': ?location?.lng,
  };

  Future<String> book({
    required String patientId,
    required String proId,
    required String serviceId,
    required String commune,
    required String address,
    required DateTime at,
    required bool hasPrescription,
    required String note,
    GeoPoint? location,
  }) => _call(() async {
    final row = await client
        .from('bookings')
        .insert(
          _bookingRow(
            patientId: patientId,
            proId: proId,
            serviceId: serviceId,
            commune: commune,
            address: address,
            at: at,
            hasPrescription: hasPrescription,
            note: note,
            location: location,
          ),
        )
        .select('id')
        .single();
    return row['id'] as String;
  });

  Future<String> bookContract({
    required String patientId,
    required String proId,
    required String serviceId,
    required String commune,
    required String address,
    required List<DateTime> dates,
    required Frequency frequency,
    required bool hasPrescription,
    required String note,
    GeoPoint? location,
  }) => _call(() async {
    final contract = await client
        .from('contracts')
        .insert({'booked_by': userId, 'frequency': _frequencies[frequency]})
        .select('id')
        .single();
    final id = contract['id'] as String;
    await client.from('bookings').insert([
      for (var i = 0; i < dates.length; i++)
        {
          ..._bookingRow(
            patientId: patientId,
            proId: proId,
            serviceId: serviceId,
            commune: commune,
            address: address,
            at: dates[i],
            hasPrescription: hasPrescription,
            note: note,
            location: location,
          ),
          'contract_id': id,
          'session_index': i,
        },
    ]);
    return id;
  });

  /// Réponse du soignant. Un refus motivé passe par refuse_booking (0012) ;
  /// sans cette fonction sur le serveur, on refuse sans motif.
  Future<void> respond(String bookingId, bool accept, {String reason = ''}) =>
      _call(() async {
        if (!accept && reason.trim().isNotEmpty) {
          try {
            await client.rpc(
              'refuse_booking',
              params: {'p_booking': bookingId, 'p_reason': reason.trim()},
            );
            return;
          } on PostgrestException catch (e) {
            if (e.code != 'PGRST202') rethrow;
          }
        }
        await client.rpc(
          'respond_booking',
          params: {'p_booking': bookingId, 'p_accept': accept},
        );
      });

  Future<void> payWithWallet(String bookingId) => _call(
    () =>
        client.rpc('pay_booking_with_wallet', params: {'p_booking': bookingId}),
  );

  Future<void> cancel(String bookingId) => _call(
    () => client.rpc('cancel_booking', params: {'p_booking': bookingId}),
  );

  Future<void> cancelByPro(String bookingId, String reason) => _call(
    () => client.rpc(
      'pro_cancel_booking',
      params: {'p_booking': bookingId, 'p_reason': reason},
    ),
  );

  Future<void> submitCareLog(String bookingId, CareLog log) => _call(
    () => client.from('care_logs').insert({
      'booking_id': bookingId,
      'pro_id': userId,
      'arrived_at': _iso(log.arrivedAt),
      'left_at': _iso(log.leftAt),
      'acts': log.acts,
      'blood_pressure': log.bloodPressure,
      'temperature': log.temperature,
      'pulse': log.pulse,
      'glycemia': log.glycemia,
      'observations': log.observations,
    }),
  );

  Future<void> rate(
    String bookingId,
    String proId,
    int stars,
    String comment,
  ) => _call(
    () => client.from('reviews').insert({
      'booking_id': bookingId,
      'pro_id': proId,
      'rating': stars,
      'comment': comment,
    }),
  );

  // -------------------------------------------------------------- soignants
  Future<void> registerPro({
    required String name,
    required ProType type,
    required List<String> communes,
    required Map<String, int> prices,
    required int yearsExperience,
    required String bio,
    required String orderNumber,
    required bool nightAvailable,
    required Map<DocType, PickedFile> files,
    String? referredBy,
  }) => _call(() async {
    final uid = userId!;
    await client.from('pros').insert({
      'id': uid,
      'display_name': name,
      'pro_type': _proTypes[type],
      'bio': bio,
      'years_experience': yearsExperience,
      'communes': communes,
      'night_available': nightAvailable,
      'order_number': orderNumber,
      'referred_by': ?referredBy,
    });
    await client.from('pro_services').insert([
      for (final e in prices.entries)
        {'pro_id': uid, 'service_id': e.key, 'price': e.value},
    ]);
    await uploadDocuments(files);
    // Statut selon les pièces : incomplet ou en attente (0012).
    if (hasProTables) await client.rpc('submit_pro_dossier');
  });

  /// Envoie les pièces dans le stockage privé, puis les enregistre.
  Future<void> uploadDocuments(
    Map<DocType, PickedFile> files, {
    Map<DocType, DateTime?> expiry = const {},
  }) => _call(() async {
    final uid = userId!;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (final e in files.entries) {
      final ext = e.value.name.contains('.')
          ? e.value.name.split('.').last.toLowerCase()
          : 'jpg';
      final path = '$uid/${_docTypes[e.key]}_$stamp.$ext';
      await client.storage
          .from('pro-documents')
          .uploadBinary(
            path,
            e.value.bytes,
            fileOptions: FileOptions(
              contentType: ext == 'pdf'
                  ? 'application/pdf'
                  : (ext == 'png' ? 'image/png' : 'image/jpeg'),
            ),
          );
      await client.from('pro_documents').insert({
        'pro_id': uid,
        'doc_type': _docTypes[e.key],
        'storage_path': path,
        // Colonne ajoutée par 0012.
        if (hasProTables && expiry[e.key] != null)
          'expires_on': expiry[e.key]!.toIso8601String().substring(0, 10),
      });
    }
  });

  Future<Uri> documentUrl(String path) => _call(() async {
    final url = await client.storage
        .from('pro-documents')
        .createSignedUrl(path, 600);
    return Uri.parse(url);
  });

  Future<void> resubmitPro() => _call(() => client.rpc('resubmit_pro'));

  Future<void> updateAvailability(List<String> communes, bool night) => _call(
    () => client
        .from('pros')
        .update({'communes': communes, 'night_available': night})
        .eq('id', userId!),
  );

  Future<void> subscribePremium() =>
      _call(() => client.rpc('subscribe_premium'));

  Future<void> withdraw(int amount, PaymentMethod method, String phone) =>
      _call(
        () => client.rpc(
          'request_withdrawal',
          params: {
            'p_amount': amount,
            'p_method': method.name,
            'p_phone': phone,
          },
        ),
      );

  // --------------------------------------------------------- administration
  Future<void> verifyPro(String id) =>
      _call(() => client.rpc('admin_verify_pro', params: {'p_pro': id}));

  Future<void> rejectPro(String id, String reason) => _call(
    () => client.rpc(
      'admin_reject_pro',
      params: {'p_pro': id, 'p_reason': reason},
    ),
  );

  Future<void> suspendPro(String id, String reason) => _call(
    () => client.rpc(
      'admin_suspend_pro',
      params: {'p_pro': id, 'p_reason': reason},
    ),
  );

  // ------------------------------------------------ famille et carnet (0009+)
  Future<String> addFamilyMember(
    String patientId, {
    required String contact,
    required String name,
    required String relation,
    required Set<FamilyPermission> permissions,
    DateTime? expiresAt,
  }) => _call(() async {
    final id = await client.rpc(
      'add_patient_member',
      params: {
        'p_patient': patientId,
        'p_contact': contact,
        'p_relation': relation == 'Aide à domicile' ? 'caregiver' : 'family',
        'p_permissions': [for (final p in permissions) p.dbName],
        'p_expires_at': expiresAt == null ? null : _iso(expiresAt),
        'p_display_name': name,
        'p_relation_label': relation,
      },
    );
    return id as String;
  });

  Future<void> updateFamilyMember(
    String memberId,
    Set<FamilyPermission> permissions,
    DateTime? expiresAt,
  ) => _call(
    () => client.rpc(
      'update_patient_member',
      params: {
        'p_member': memberId,
        'p_permissions': [for (final p in permissions) p.dbName],
        'p_expires_at': expiresAt == null ? null : _iso(expiresAt),
      },
    ),
  );

  Future<void> revokeFamilyMember(String memberId) => _call(
    () => client.rpc('revoke_patient_member', params: {'p_member': memberId}),
  );

  Future<void> revokeRecordAccess(String grantId) => _call(
    () => client.rpc(
      'revoke_record_access',
      params: {'p_grant': grantId, 'p_reason': 'Retiré par le patient'},
    ),
  );

  /// Dépose le fichier dans le dossier du patient puis l'enregistre.
  Future<String> addDocument(
    String patientId,
    MedicalDocKind kind,
    String title,
    PickedFile file,
    DateTime? documentDate,
  ) => _call(() async {
    final ext = file.name.split('.').last.toLowerCase();
    final mime = ext == 'pdf'
        ? 'application/pdf'
        : ext == 'png'
        ? 'image/png'
        : 'image/jpeg';
    final path =
        '$patientId/${DateTime.now().millisecondsSinceEpoch}-${kind.dbName}.$ext';
    await client.storage
        .from('medical-documents')
        .uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(contentType: mime),
        );
    final row = await client
        .from('medical_documents')
        .insert({
          'patient_id': patientId,
          'kind': kind.dbName,
          'title': title,
          'storage_path': path,
          'mime_type': mime,
          'size_bytes': file.bytes.length,
          'document_date': documentDate?.toIso8601String().substring(0, 10),
          'uploaded_by': userId,
        })
        .select('id')
        .single();
    return row['id'] as String;
  });

  Future<void> hideDocument(String id) => _call(
    () => client
        .from('medical_documents')
        .update({
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          'deleted_by': userId,
        })
        .eq('id', id),
  );

  Future<Uint8List> downloadMedicalFile(String path) =>
      _call(() => client.storage.from('medical-documents').download(path));

  Future<String> openComplaint(
    String? bookingId,
    ComplaintCategory category,
    String description,
  ) => _call(() async {
    final id = await client.rpc(
      'open_complaint',
      params: {
        'p_booking': bookingId,
        'p_category': category.dbName,
        'p_description': description,
      },
    );
    return id as String;
  });

  // ------------------------------------------------- espace soignant (0012)
  Future<void> submitProDossier() =>
      _call(() => client.rpc('submit_pro_dossier'));

  Future<void> startReview(String proId) =>
      _call(() => client.rpc('admin_start_review', params: {'p_pro': proId}));

  /// Remplace les plages hebdomadaires (table availability_rules, 0011).
  Future<void> setAvailability(List<AvailabilityRule> rules) => _call(() async {
    final uid = userId!;
    await client.from('availability_rules').delete().eq('pro_id', uid);
    if (rules.isEmpty) return;
    String t(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    await client.from('availability_rules').insert([
      for (final r in rules)
        {
          'pro_id': uid,
          'weekday': r.weekday,
          'start_time': t(r.startMinute),
          'end_time': t(r.endMinute),
        },
    ]);
  });

  Future<void> setDayOff(DateTime from, DateTime to, bool off) =>
      _call(() async {
        final uid = userId!;
        final range = '[${_iso(from)},${_iso(to)})';
        if (off) {
          await client.from('availability_exceptions').insert({
            'pro_id': uid,
            'period': range,
            'kind': 'off',
            'reason': 'Indisponible',
          });
        } else {
          await client
              .from('availability_exceptions')
              .delete()
              .eq('pro_id', uid)
              .eq('kind', 'off')
              .filter('period', 'ov', range);
        }
      });

  /// Soins et tarifs : ajoute, modifie, retire (la base contrôle la
  /// profession et la fourchette de prix).
  Future<void> updateServices(Map<String, int> prices) => _call(() async {
    final uid = userId!;
    final current = await client
        .from('pro_services')
        .select('service_id')
        .eq('pro_id', uid);
    final removed = [
      for (final r in current)
        if (!prices.containsKey(r['service_id'])) r['service_id'] as String,
    ];
    if (removed.isNotEmpty) {
      await client
          .from('pro_services')
          .delete()
          .eq('pro_id', uid)
          .inFilter('service_id', removed);
    }
    await client.from('pro_services').upsert([
      for (final e in prices.entries)
        {'pro_id': uid, 'service_id': e.key, 'price': e.value},
    ]);
  });

  Future<void> addJournal(String bookingId, JournalKind kind, String text) =>
      _call(
        () => client.rpc(
          'add_care_journal',
          params: {
            'p_booking': bookingId,
            'p_kind': switch (kind) {
              JournalKind.onTheWay => 'on_the_way',
              JournalKind.arrived => 'arrived',
              JournalKind.note => 'note',
              JournalKind.left => 'left',
            },
            'p_text': text,
          },
        ),
      );

  Future<void> recordVital(
    String patientId,
    String bookingId,
    VitalKind kind,
    double value,
    double? value2,
  ) => _call(
    () => client.from('vital_signs').insert({
      'patient_id': patientId,
      'booking_id': bookingId,
      'kind': kind.dbName,
      'value': value,
      'value2': ?value2,
      'unit': kind.unit,
      'recorded_by': userId,
    }),
  );

  /// Lecture tracée du dossier (get_patient_chart, 0010) : le serveur ne
  /// renvoie que le périmètre autorisé et journalise chaque lecture.
  Future<PatientChart> patientChart(String patientId, ScopeOfPractice scope) =>
      _call(() async {
        final j = Map<String, dynamic>.from(
          await client.rpc(
            'get_patient_chart',
            params: {'p_patient': patientId},
          ) as Map,
        );
        final p = _one(j['patient']) ?? const {};
        final r = _one(j['record']) ?? const {};
        final birth = p['birth_date'] as String?;
        final full = j['vitals'] != null && scope.fullRecord;
        return PatientChart(
          name: (p['full_name'] as String?) ?? 'Patient',
          age: birth == null
              ? null
              : DateTime.now().year - int.parse(birth.substring(0, 4)),
          scopeLabel: full
              ? 'Soin confirmé : carnet complet le temps du soin. Chaque '
                    'consultation est enregistrée.'
              : 'Accès limité à l’essentiel (allergies, traitements). Chaque '
                    'consultation est enregistrée.',
          allergies: (r['allergies'] as String?) ?? '',
          treatments: (r['current_treatments'] as String?) ?? '',
          history: full ? (r['history'] as String?) ?? '' : '',
          bloodGroup: full ? (r['blood_group'] as String?) ?? '' : '',
          emergencyContact: (r['emergency_contact_name'] as String?) ?? '',
          documents: !scope.documents
              ? const []
              : [
                  for (final d in (j['documents'] as List? ?? const []))
                    MedicalDocument(
                      id: d['id'] as String,
                      kind: MedicalDocKind.values.firstWhere(
                        (k) => k.dbName == d['kind'],
                        orElse: () => MedicalDocKind.other,
                      ),
                      title: d['title'] as String,
                      addedAt: _date(d['created_at']),
                      addedBy: 'famille',
                      fileName: (d['storage_path'] as String).split('/').last,
                      storagePath: d['storage_path'] as String,
                    ),
                ],
          vitals: !full
              ? const []
              : [
                  for (final v in (j['vitals'] as List? ?? const []))
                    VitalSign(
                      kind: VitalKind.values.firstWhere(
                        (k) => k.dbName == v['kind'],
                        orElse: () => VitalKind.temperature,
                      ),
                      value: (v['value'] as num).toDouble(),
                      value2: (v['value2'] as num?)?.toDouble(),
                      at: _date(v['measured_at']),
                      by: 'soignant',
                    ),
                ],
          reports: !full
              ? const []
              : [
                  for (final c in (j['reports'] as List? ?? const []))
                    (
                      at: _date(c['arrived_at']),
                      pro: (c['pro_name'] as String?) ?? '',
                      acts: c['acts'] as String,
                      observations: (c['observations'] as String?) ?? '',
                    ),
                ],
        );
      });

  Future<String> reportIncident(
    String? bookingId,
    IncidentCategory category,
    String description,
  ) => _call(() async {
    final id = await client.rpc(
      'report_incident',
      params: {
        'p_booking': bookingId,
        'p_category': category.dbName,
        'p_description': description,
      },
    );
    return id as String;
  });

  // ------------------------------------------------------ administration
  Future<void> setStaffPermission(
    String profileId,
    AdminPermission p,
    bool grant,
  ) => _call(
    () => client.rpc(
      'admin_set_staff_permission',
      params: {'p_profile': profileId, 'p_perm': p.dbName, 'p_grant': grant},
    ),
  );

  Future<void> adminCancelBooking(String bookingId, String reason) => _call(
    () => client.rpc(
      'admin_cancel_booking',
      params: {'p_booking': bookingId, 'p_reason': reason},
    ),
  );

  Future<void> adminRefund(String bookingId, int amount, String reason) =>
      _call(
        () => client.rpc(
          'admin_refund_booking',
          params: {
            'p_booking': bookingId,
            'p_amount': amount,
            'p_reason': reason,
          },
        ),
      );

  Future<void> adminExtendPremium(String proId, int days, String reason) =>
      _call(
        () => client.rpc(
          'admin_extend_premium',
          params: {'p_pro': proId, 'p_days': days, 'p_reason': reason},
        ),
      );

  Future<void> adminUpdateSetting(String key, Object value) => _call(
    () => client.rpc(
      'admin_update_setting',
      params: {'p_key': key, 'p_value': value},
    ),
  );

  Future<void> adminUpdateComplaint(
    String id,
    ComplaintStatus status,
    String resolution,
    int refund,
  ) => _call(
    () => client.rpc(
      'admin_update_complaint',
      params: {
        'p_id': id,
        'p_status': switch (status) {
          ComplaintStatus.open => 'open',
          ComplaintStatus.inReview => 'in_review',
          ComplaintStatus.resolved => 'resolved',
          ComplaintStatus.rejected => 'rejected',
        },
        'p_resolution': resolution.isEmpty ? null : resolution,
        'p_refund': refund,
      },
    ),
  );

  Future<void> adminUpdateIncident(String id, String status, String note) =>
      _call(
        () => client.rpc(
          'admin_update_incident',
          params: {
            'p_id': id,
            'p_status': switch (status) {
              'En cours' => 'in_review',
              'Traité' => 'closed',
              _ => 'open',
            },
            'p_note': note,
          },
        ),
      );

  Future<void> adminSavePharmacy(Pharmacy p) => _call(
    () => client.from('pharmacies').upsert({
      if (!p.id.startsWith('new')) 'id': p.id,
      'name': p.name,
      'commune': p.commune,
      'address': p.address,
      'phone': p.phone.isEmpty ? null : p.phone,
      'location_lat': p.location?.lat,
      'location_lng': p.location?.lng,
      'on_duty_from': p.onDutyFrom == null ? null : _iso(p.onDutyFrom!),
      'on_duty_until': p.onDutyUntil == null ? null : _iso(p.onDutyUntil!),
      'active': true,
    }),
  );

  Future<void> adminHidePharmacy(String id) => _call(
    () => client.from('pharmacies').update({'active': false}).eq('id', id),
  );

  Future<int> adminBroadcast(
    BroadcastAudience audience,
    String title,
    String body,
  ) => _call(() async {
    final n = await client.rpc(
      'admin_broadcast',
      params: {'p_audience': audience.name, 'p_title': title, 'p_body': body},
    );
    return (n as num).toInt();
  });

  Future<void> adminBreakGlass(String patientId, String reason) => _call(
    () => client.rpc(
      'admin_break_glass',
      params: {'p_patient': patientId, 'p_reason': reason},
    ),
  );

  /// Journal d'activité (audit.events), lecture tracée côté serveur.
  Future<List<AdminLogEntry>> adminAuditEvents(DateTime since) =>
      _call(() async {
        final rows = await client.rpc(
          'admin_audit_events',
          params: {'p_since': _iso(since), 'p_limit': 500},
        );
        return [
          for (final e in rows as List)
            AdminLogEntry(
              at: _date(e['occurred_at']),
              actor: (e['actor_role'] as String?) ?? 'serveur',
              action: '${e['action']}',
              target: '${e['entity']}',
              details:
                  (e['reason'] as String?) ??
                  ((e['changed_fields'] as List?)?.join(', ') ?? ''),
              patientId: e['patient_id'] as String?,
            ),
        ];
      });

  /// Indicateurs agrégés et permissions du membre connecté (0013).
  Future<({int patients, Set<AdminPermission> perms})> adminContext() =>
      _call(() async {
        final j = Map<String, dynamic>.from(
          await client.rpc('admin_dashboard_context') as Map,
        );
        return (
          patients: _int(j['patients']),
          perms: {
            for (final x in (j['permissions'] as List? ?? const []))
              AdminPermission.values.firstWhere(
                (p) => p.dbName == x,
                orElse: () => AdminPermission.support,
              ),
          },
        );
      });
}
