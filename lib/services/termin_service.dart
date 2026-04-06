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
  final String status; // scheduled, completed, cancelled
  final DateTime createdAt;
  final DateTime? updatedAt;

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
    );
  }

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
