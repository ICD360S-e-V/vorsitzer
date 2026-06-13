import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';

/// Termin Model
class Termin {
  final int id;
  final String title;
  final String category; // vorstandssitzung, mitgliederversammlung, schulung, sonstiges
  final String description;
  final DateTime terminDate;
  final int durationMinutes;
  final String location;
  final int createdBy;
  final String? createdByName;
  final int? ticketId;
  final String? ticketSubject;
  final bool brauchtMich;
  final String status; // scheduled, completed, cancelled
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Termin-Nachbearbeitung (manuelles Tracking nach dem Termin)
  final String feedbackStatus; // offen, wahrgenommen, nicht_wahrgenommen
  final bool feedbackErhalten;
  final String? nichtWahrgenommenGrund; // key aus 10er-Liste
  final String? nichtWahrgenommenGrundText;
  final String? feedbackText;
  final DateTime? feedbackEingegangenAm;
  final int? markiertVonUserId;
  final DateTime? markiertAm;

  // Participant stats (când vine din admin list)
  final int? totalParticipants;
  final int? confirmedCount;
  final int? declinedCount;
  final int? pendingCount;
  final int? reschedulingCount;

  // My response (când vine din member list)
  final String? myResponse;
  final String? myReschedulingReason;
  final DateTime? myRespondedAt;

  // Participant identity (când server-ul agregă termine + ale copiilor)
  // Dacă participantUserId != self.id, termin-ul aparține unui copil al
  // user-ului curent — badge se afișează în calendar.
  final int? participantUserId;
  final String? participantVorname;
  final String? participantNachname;
  final String? participantMitgliedernummer;
  final String? participantRole;

  Termin({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.terminDate,
    required this.durationMinutes,
    required this.location,
    required this.createdBy,
    this.createdByName,
    this.ticketId,
    this.ticketSubject,
    this.brauchtMich = false,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.totalParticipants,
    this.confirmedCount,
    this.declinedCount,
    this.pendingCount,
    this.reschedulingCount,
    this.myResponse,
    this.myReschedulingReason,
    this.myRespondedAt,
    this.participantUserId,
    this.participantVorname,
    this.participantNachname,
    this.participantMitgliedernummer,
    this.participantRole,
    this.feedbackStatus = 'offen',
    this.feedbackErhalten = false,
    this.nichtWahrgenommenGrund,
    this.nichtWahrgenommenGrundText,
    this.feedbackText,
    this.feedbackEingegangenAm,
    this.markiertVonUserId,
    this.markiertAm,
  });

  factory Termin.fromJson(Map<String, dynamic> json) {
    return Termin(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      title: json['title'] ?? '',
      category: json['category'] ?? 'sonstiges',
      description: json['description'] ?? '',
      terminDate: DateTime.parse(json['termin_date']),
      durationMinutes: json['duration_minutes'] is int
          ? json['duration_minutes']
          : int.parse(json['duration_minutes']?.toString() ?? '60'),
      location: json['location'] ?? '',
      createdBy: json['created_by'] is int
          ? json['created_by']
          : int.parse(json['created_by'].toString()),
      createdByName: json['created_by_name'],
      ticketId: json['ticket_id'] != null
          ? (json['ticket_id'] is int ? json['ticket_id'] : int.parse(json['ticket_id'].toString()))
          : null,
      ticketSubject: json['ticket_subject'],
      brauchtMich: json['braucht_mich'] == 1 || json['braucht_mich'] == '1' || json['braucht_mich'] == true,
      status: json['status'] ?? 'scheduled',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      totalParticipants: json['total_participants'] != null
          ? (json['total_participants'] is int
              ? json['total_participants']
              : int.parse(json['total_participants'].toString()))
          : null,
      confirmedCount: json['confirmed_count'] != null
          ? (json['confirmed_count'] is int
              ? json['confirmed_count']
              : int.parse(json['confirmed_count'].toString()))
          : null,
      declinedCount: json['declined_count'] != null
          ? (json['declined_count'] is int
              ? json['declined_count']
              : int.parse(json['declined_count'].toString()))
          : null,
      pendingCount: json['pending_count'] != null
          ? (json['pending_count'] is int
              ? json['pending_count']
              : int.parse(json['pending_count'].toString()))
          : null,
      reschedulingCount: json['rescheduling_count'] != null
          ? (json['rescheduling_count'] is int
              ? json['rescheduling_count']
              : int.parse(json['rescheduling_count'].toString()))
          : null,
      myResponse: json['response'],
      myReschedulingReason: json['rescheduling_reason'],
      myRespondedAt:
          json['responded_at'] != null ? DateTime.parse(json['responded_at']) : null,
      participantUserId: json['participant_user_id'] == null
          ? null
          : (json['participant_user_id'] is int
              ? json['participant_user_id'] as int
              : int.tryParse(json['participant_user_id'].toString())),
      participantVorname: json['participant_vorname'],
      participantNachname: json['participant_nachname'],
      participantMitgliedernummer: json['participant_mitgliedernummer'],
      participantRole: json['participant_role'],
      feedbackStatus: (json['feedback_status'] ?? 'offen').toString(),
      feedbackErhalten: json['feedback_erhalten'] == 1 || json['feedback_erhalten'] == '1' || json['feedback_erhalten'] == true,
      nichtWahrgenommenGrund: json['nicht_wahrgenommen_grund']?.toString(),
      nichtWahrgenommenGrundText: json['nicht_wahrgenommen_grund_text']?.toString(),
      feedbackText: json['feedback_text']?.toString(),
      feedbackEingegangenAm: (json['feedback_eingegangen_am'] != null && json['feedback_eingegangen_am'].toString().isNotEmpty)
          ? DateTime.tryParse(json['feedback_eingegangen_am'].toString())
          : null,
      markiertVonUserId: json['markiert_von_user_id'] is int
          ? json['markiert_von_user_id']
          : int.tryParse(json['markiert_von_user_id']?.toString() ?? ''),
      markiertAm: (json['markiert_am'] != null && json['markiert_am'].toString().isNotEmpty)
          ? DateTime.tryParse(json['markiert_am'].toString())
          : null,
    );
  }

  /// Returns the display name for the family member this termin belongs to,
  /// when [selfMitgliedernummer] is the logged-in user. Returns null if this
  /// termin is the user's own (no badge needed).
  String? forKindBadge(String selfMitgliedernummer) {
    if (participantMitgliedernummer == null) return null;
    if (participantMitgliedernummer == selfMitgliedernummer) return null;
    final composed = [participantVorname ?? '', participantNachname ?? '']
        .where((p) => p.isNotEmpty).join(' ').trim();
    if (composed.isNotEmpty) return composed;
    return participantMitgliedernummer!;
  }

  /// Whether this termin belongs to a managed child (jugendmitglied role).
  bool get isKindTermin => participantRole == 'jugendmitglied';

  String get categoryDisplay {
    switch (category) {
      case 'vorstandssitzung':
        return 'Vorstandssitzung';
      case 'mitgliederversammlung':
        return 'Mitgliederversammlung';
      case 'schulung':
        return 'Schulung';
      case 'sonstiges':
        return 'Sonstiges';
      default:
        return category;
    }
  }

  Color get categoryColor {
    switch (category) {
      case 'vorstandssitzung':
        return Colors.purple;
      case 'mitgliederversammlung':
        return Colors.blue;
      case 'schulung':
        return Colors.green;
      case 'sonstiges':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  DateTime get terminEndTime {
    return terminDate.add(Duration(minutes: durationMinutes));
  }

  bool get isUpcoming => terminDate.isAfter(DateTime.now());
  bool get isPast => terminDate.isBefore(DateTime.now());
}

/// Termin Participant Model
class TerminParticipant {
  final int id;
  final int userId;
  final String userName;
  final String mitgliedernummer;
  final String response; // pending, confirmed, declined, rescheduling
  final String? reschedulingReason;
  final DateTime? respondedAt;

  TerminParticipant({
    required this.id,
    required this.userId,
    required this.userName,
    required this.mitgliedernummer,
    required this.response,
    this.reschedulingReason,
    this.respondedAt,
  });

  factory TerminParticipant.fromJson(Map<String, dynamic> json) {
    return TerminParticipant(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      userId: json['user_id'] is int ? json['user_id'] : int.parse(json['user_id'].toString()),
      userName: json['user_name'] ?? '',
      mitgliedernummer: json['mitgliedernummer'] ?? '',
      response: json['response'] ?? 'pending',
      reschedulingReason: json['rescheduling_reason'],
      respondedAt:
          json['responded_at'] != null ? DateTime.parse(json['responded_at']) : null,
    );
  }

  String get responseDisplay {
    switch (response) {
      case 'confirmed':
        return 'Bestätigt';
      case 'declined':
        return 'Abgelehnt';
      case 'pending':
        return 'Ausstehend';
      case 'rescheduling':
        return 'Verschiebung';
      default:
        return response;
    }
  }

  Color get responseColor {
    switch (response) {
      case 'confirmed':
        return Colors.green;
      case 'declined':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'rescheduling':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }
}

/// Termin Service - handles termine API calls
class TerminService {
  static const String baseUrl = 'https://icd360sev.icd360s.de/api';
  // ✅ SECURITY FIX: Removed hardcoded API key (extractable via reverse engineering)
  // All requests now use dynamic Device Key only

  late http.Client _client;
  final DeviceKeyService _deviceKeyService = DeviceKeyService();

  String? _token;

  // Singleton
  static final TerminService _instance = TerminService._internal();
  factory TerminService() => _instance;

  TerminService._internal() {
    _client = IOClient(HttpClientFactory.createPinnedHttpClient());
  }

  void setToken(String? token) {
    _token = token;
  }

  Map<String, String> get _headers {
    final deviceKey = _deviceKeyService.deviceKey;
    return {
      'Content-Type': 'application/json',
      'User-Agent': 'ICD360S-Vorsitzer/1.0',
      if (_token != null) 'Authorization': 'Bearer $_token',
      if (deviceKey != null) 'X-Device-Key': deviceKey,
    };
  }

  // ========== NACHBEARBEITUNG (manuelles Status-Tracking) ==========

  /// Setzt den Feedback-Status (offen / wahrgenommen / nicht_wahrgenommen).
  /// Bei nicht_wahrgenommen ist [grund] aus der 10er-Liste Pflicht.
  Future<Map<String, dynamic>> setTerminStatus({
    required int terminId,
    required String feedbackStatus,
    String? grund,
    String? grundText,
  }) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/admin/termine_nachbearbeitung.php'),
      headers: _headers,
      body: jsonEncode({
        'action': 'set_status',
        'termin_id': terminId,
        'feedback_status': feedbackStatus,
        if (grund != null) 'grund': grund,
        if (grundText != null) 'grund_text': grundText,
      }),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  /// Speichert Feedback-Text und markiert "feedback erhalten".
  Future<Map<String, dynamic>> setTerminFeedback({
    required int terminId,
    required String feedbackText,
    String? eingegangenAm,
  }) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/admin/termine_nachbearbeitung.php'),
      headers: _headers,
      body: jsonEncode({
        'action': 'set_feedback',
        'termin_id': terminId,
        'feedback_text': feedbackText,
        if (eingegangenAm != null) 'eingegangen_am': eingegangenAm,
      }),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  /// Reset auf "offen" und löscht Gründe / Feedback.
  Future<Map<String, dynamic>> clearTerminNachbearbeitung(int terminId) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/admin/termine_nachbearbeitung.php'),
      headers: _headers,
      body: jsonEncode({'action': 'clear', 'termin_id': terminId}),
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  /// Wochen-Statistik aller Termine im Zeitraum.
  Future<Map<String, dynamic>> getTerminStats({required DateTime from, required DateTime to}) async {
    String fmt(DateTime d) => '${d.year.toString().padLeft(4, "0")}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
    final r = await _client.get(
      Uri.parse('$baseUrl/admin/termine_nachbearbeitung.php?action=stats&from=${fmt(from)}&to=${fmt(to)}'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    try { return jsonDecode(r.body); } on FormatException { return {'success': false}; }
  }

  /// Erlaubte Gründe für "nicht wahrgenommen" — synchron mit Server-Allowlist.
  static const Map<String, String> nichtWahrgenommenGruende = {
    'vergessen': 'Vergessen',
    'krankheit': 'Akute Krankheit / Verschlechterung',
    'transport': 'Transportprobleme (Bahn, Auto, Ticket)',
    'familiennotfall': 'Familiennotfall (Kind krank, Pflegefall)',
    'arbeit_kollision': 'Arbeitseinsatz / Schichtkollision',
    'sprachbarriere': 'Sprachbarriere / Verständnis',
    'angst': 'Angst / psychische Belastung',
    'umgebucht': 'Vom Anbieter umgebucht — nicht rechtzeitig informiert',
    'falsche_zeit': 'Falsche Uhrzeit notiert',
    'sonstiges': 'Sonstiges (Freitext erforderlich)',
  };

  // ========== ADMIN METHODS ==========

  /// Create termin (admin only)
  Future<Map<String, dynamic>> createTermin({
    required String title,
    required String category,
    required String description,
    required DateTime terminDate,
    required int durationMinutes,
    required String location,
    required List<int> participantIds,
    int? ticketId,
    bool brauchtMich = false,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/termine_create.php'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'category': category,
        'description': description,
        'termin_date': terminDate.toIso8601String().substring(0, 19).replaceAll('T', ' '),
        'duration_minutes': durationMinutes,
        'location': location,
        'participant_ids': participantIds,
        if (ticketId != null) 'ticket_id': ticketId,
        'braucht_mich': brauchtMich ? 1 : 0,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Get all termine (admin only) with optional date range for weekly calendar
  /// If [participantId] is set, only returns termine where that user is a participant
  Future<Map<String, dynamic>> getAllTermine({DateTime? from, DateTime? to, int? participantId}) async {
    String url = '$baseUrl/admin/termine_list.php';
    final params = <String>[];

    if (from != null && to != null) {
      final fromStr = from.toIso8601String().substring(0, 10);
      final toStr = to.toIso8601String().substring(0, 10);
      params.add('from=$fromStr');
      params.add('to=$toStr');
    }

    if (participantId != null) {
      params.add('participant_id=$participantId');
    }

    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }

    final response = await _client.get(
      Uri.parse(url),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Get termin details with participants (admin only)
  Future<Map<String, dynamic>> getTerminDetails(int terminId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/termine_details.php'),
      headers: _headers,
      body: jsonEncode({'termin_id': terminId}),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Update termin (admin only)
  Future<Map<String, dynamic>> updateTermin({
    required int terminId,
    String? title,
    String? category,
    String? description,
    DateTime? terminDate,
    int? durationMinutes,
    String? location,
    List<int>? participantIds,
    int? ticketId,
    bool? brauchtMich,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/termine_update.php'),
      headers: _headers,
      body: jsonEncode({
        'termin_id': terminId,
        if (title != null) 'title': title,
        if (category != null) 'category': category,
        if (description != null) 'description': description,
        if (terminDate != null)
          'termin_date': terminDate.toIso8601String().substring(0, 19).replaceAll('T', ' '),
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
        if (location != null) 'location': location,
        if (participantIds != null) 'participant_ids': participantIds,
        if (ticketId != null) 'ticket_id': ticketId,
        if (brauchtMich != null) 'braucht_mich': brauchtMich ? 1 : 0,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Delete termin (admin only)
  Future<Map<String, dynamic>> deleteTermin(int terminId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/termine_delete.php'),
      headers: _headers,
      body: jsonEncode({'termin_id': terminId}),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== URLAUB METHODS (Admin) ==========

  /// Create urlaub period (admin only)
  Future<Map<String, dynamic>> createUrlaub({
    required DateTime startDate,
    required DateTime endDate,
    String beschreibung = 'Urlaub',
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/urlaub_create.php'),
      headers: _headers,
      body: jsonEncode({
        'start_date': startDate.toIso8601String().substring(0, 10),
        'end_date': endDate.toIso8601String().substring(0, 10),
        'beschreibung': beschreibung,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Get urlaub periods (admin only)
  Future<Map<String, dynamic>> getUrlaub({DateTime? from, DateTime? to}) async {
    String url = '$baseUrl/admin/urlaub_list.php';

    if (from != null && to != null) {
      final fromStr = from.toIso8601String().substring(0, 10);
      final toStr = to.toIso8601String().substring(0, 10);
      url += '?from=$fromStr&to=$toStr';
    }

    final response = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Get German public holidays (Feiertage)
  Future<Map<String, dynamic>> getFeiertage({DateTime? from, DateTime? to, String? bundesland}) async {
    String url = '$baseUrl/admin/feiertage_list.php';

    if (from != null && to != null) {
      final fromStr = from.toIso8601String().substring(0, 10);
      final toStr = to.toIso8601String().substring(0, 10);
      url += '?from=$fromStr&to=$toStr';
      if (bundesland != null && bundesland.isNotEmpty) {
        url += '&bundesland=$bundesland';
      }
    }

    final response = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Update urlaub period (admin only)
  Future<Map<String, dynamic>> updateUrlaub({
    required int urlaubId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/urlaub_update.php'),
      headers: _headers,
      body: jsonEncode({
        'urlaub_id': urlaubId,
        'start_date': startDate.toIso8601String().substring(0, 10),
        'end_date': endDate.toIso8601String().substring(0, 10),
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Delete urlaub period (admin only)
  Future<Map<String, dynamic>> deleteUrlaub(int urlaubId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/urlaub_delete.php'),
      headers: _headers,
      body: jsonEncode({'urlaub_id': urlaubId}),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ========== MEMBER METHODS ==========

  /// Get my termine (member)
  Future<Map<String, dynamic>> getMyTermine({String filter = 'upcoming'}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/termine/my_termine.php?filter=$filter'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(response.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  /// Respond to termin (member)
  Future<Map<String, dynamic>> respondToTermin({
    required int terminId,
    required String response, // confirmed, declined, rescheduling
    String? reason,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/termine/respond.php'),
      headers: _headers,
      body: jsonEncode({
        'termin_id': terminId,
        'response': response,
        if (reason != null) 'reason': reason,
      }),
    ).timeout(const Duration(seconds: 15));

    try {
      return jsonDecode(res.body);
    } on FormatException {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }
}
