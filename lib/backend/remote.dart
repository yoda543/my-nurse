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
}

/// Accès à la base Supabase. Les règles sont appliquées par le serveur ;
/// les erreurs remontent en [BusinessRuleError] avec son message.
class RemoteBackend {
  RemoteBackend(this.client);

  final SupabaseClient client;

  String? get userId => client.auth.currentUser?.id;
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
          .select(
            '*, pro_services(service_id, price), pro_documents(doc_type, storage_path)',
          ),
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
        status: _enum(
          VerificationStatus.values,
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
        p.documentPaths[_key(_docTypes, d['doc_type'] as String)] =
            d['storage_path'] as String;
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

    return RemoteSnapshot(
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
  }) => _call(() async {
    final row = await client
        .from('patients')
        .insert({
          'owner_id': userId,
          'full_name': name,
          'relation': relation,
          'allergies': allergies,
          'birth_date': ?(birthYear == null ? null : '$birthYear-01-01'),
        })
        .select('id')
        .single();
    return row['id'] as String;
  });

  Future<void> updatePatient(
    String id, {
    required String allergies,
    required String history,
    required String treatments,
  }) => _call(
    () => client
        .from('patients')
        .update({
          'allergies': allergies,
          'history': history,
          'treatments': treatments,
        })
        .eq('id', id),
  );

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

  Future<void> respond(String bookingId, bool accept) => _call(
    () => client.rpc(
      'respond_booking',
      params: {'p_booking': bookingId, 'p_accept': accept},
    ),
  );

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
  });

  /// Envoie les pièces dans le stockage privé, puis les enregistre.
  Future<void> uploadDocuments(Map<DocType, PickedFile> files) =>
      _call(() async {
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
}
