import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Ticket Category model
class TicketCategory {
  final int id;
  final String name;
  final String description;
  final String color;
  final String icon;
  final int sortOrder;

  TicketCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    required this.icon,
    required this.sortOrder,
  });

  factory TicketCategory.fromJson(Map<String, dynamic> json) {
    return TicketCategory(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      color: json['color'] ?? '#4a90d9',
      icon: json['icon'] ?? 'category',
      sortOrder: json['sort_order'] ?? 0,
    );
  }
}

/// Ticket Comment model
class TicketComment {
  final int id;
  final int ticketId;
  final int userId;
  final String userName;
  final String userRole;
  final String userNummer;
  final String comment;
  final String? originalComment;
  final bool isTranslated;
  final bool isInternal;
  final DateTime createdAt;
  final DateTime? updatedAt;

  TicketComment({
    required this.id,
    required this.ticketId,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.userNummer,
    required this.comment,
    this.originalComment,
    this.isTranslated = false,
    required this.isInternal,
    required this.createdAt,
    this.updatedAt,
  });

  factory TicketComment.fromJson(Map<String, dynamic> json) {
    return TicketComment(
      id: json['id'],
      ticketId: json['ticket_id'],
      userId: json['user_id'],
      userName: json['user_name'],
      userRole: json['user_role'],
      userNummer: json['user_nummer'] ?? '',
      comment: json['comment'],
      originalComment: json['original_comment'],
      isTranslated: json['is_translated'] ?? false,
      isInternal: json['is_internal'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
    );
  }
}

/// Ticket Attachment model
class TicketAttachment {
  final int id;
  final int? commentId;
  final String filename;
  final String originalFilename;
  final int filesize;
  final String mimeType;
  final String uploadedByName;
  final DateTime createdAt;

  TicketAttachment({
    required this.id,
    this.commentId,
    required this.filename,
    required this.originalFilename,
    required this.filesize,
    required this.mimeType,
    required this.uploadedByName,
    required this.createdAt,
  });

  factory TicketAttachment.fromJson(Map<String, dynamic> json) {
    return TicketAttachment(
      id: json['id'],
      commentId: json['comment_id'],
      filename: json['filename'],
      originalFilename: json['original_filename'],
      filesize: json['filesize'],
      mimeType: json['mime_type'],
      uploadedByName: json['uploaded_by_name'] ?? 'Unknown',
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  String get filesizeDisplay {
    if (filesize < 1024) return '$filesize B';
    if (filesize < 1024 * 1024) return '${(filesize / 1024).toStringAsFixed(1)} KB';
    return '${(filesize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool get isImage {
    return mimeType.startsWith('image/');
  }
}

/// Time entry category
enum TimeCategory {
  fahrzeit,
  arbeitszeit,
  wartezeit;

  String get display {
    switch (this) {
      case TimeCategory.fahrzeit:
        return 'Fahrzeit';
      case TimeCategory.arbeitszeit:
        return 'Arbeitszeit';
      case TimeCategory.wartezeit:
        return 'Wartezeit';
    }
  }

  static TimeCategory fromString(String value) {
    switch (value) {
      case 'fahrzeit':
        return TimeCategory.fahrzeit;
      case 'arbeitszeit':
        return TimeCategory.arbeitszeit;
      case 'wartezeit':
        return TimeCategory.wartezeit;
      default:
        return TimeCategory.arbeitszeit;
    }
  }
}

/// Ticket Time Entry model
class TimeEntry {
  final int id;
  final int ticketId;
  final int userId;
  final String? userName;
  final TimeCategory category;
  final DateTime? startedAt;
  final DateTime? stoppedAt;
  final int durationSeconds;
  final String? note;
  final bool isRunning;
  final bool isManual;
  final DateTime createdAt;

  TimeEntry({
    required this.id,
    required this.ticketId,
    required this.userId,
    this.userName,
    required this.category,
    this.startedAt,
    this.stoppedAt,
    required this.durationSeconds,
    this.note,
    required this.isRunning,
    required this.isManual,
    required this.createdAt,
  });

  factory TimeEntry.fromJson(Map<String, dynamic> json) {
    return TimeEntry(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      ticketId: json['ticket_id'] is int ? json['ticket_id'] : int.parse(json['ticket_id'].toString()),
      userId: json['user_id'] is int ? json['user_id'] : int.parse(json['user_id'].toString()),
      userName: json['user_name'],
      category: TimeCategory.fromString(json['category'] ?? 'arbeitszeit'),
      startedAt: json['started_at'] != null ? DateTime.parse(json['started_at']) : null,
      stoppedAt: json['stopped_at'] != null ? DateTime.parse(json['stopped_at']) : null,
      durationSeconds: json['duration_seconds'] is int ? json['duration_seconds'] : int.parse(json['duration_seconds']?.toString() ?? '0'),
      note: json['note'],
      isRunning: json['is_running'] == 1 || json['is_running'] == true,
      isManual: json['is_manual'] == 1 || json['is_manual'] == true,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  int get effectiveDurationSeconds {
    if (isRunning && startedAt != null) {
      return DateTime.now().difference(startedAt!).inSeconds;
    }
    return durationSeconds;
  }

  String get durationDisplay {
    final seconds = effectiveDurationSeconds;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m';
    }
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}

/// Time tracking summary
class TimeSummary {
  final int fahrzeitSeconds;
  final int arbeitszeitSeconds;
  final int wartezeitSeconds;
  final int gesamtSeconds;

  TimeSummary({
    required this.fahrzeitSeconds,
    required this.arbeitszeitSeconds,
    required this.wartezeitSeconds,
    required this.gesamtSeconds,
  });

  factory TimeSummary.fromJson(Map<String, dynamic> json) {
    return TimeSummary(
      fahrzeitSeconds: json['fahrzeit_seconds'] is int ? json['fahrzeit_seconds'] : int.parse(json['fahrzeit_seconds']?.toString() ?? '0'),
      arbeitszeitSeconds: json['arbeitszeit_seconds'] is int ? json['arbeitszeit_seconds'] : int.parse(json['arbeitszeit_seconds']?.toString() ?? '0'),
      wartezeitSeconds: json['wartezeit_seconds'] is int ? json['wartezeit_seconds'] : int.parse(json['wartezeit_seconds']?.toString() ?? '0'),
      gesamtSeconds: json['gesamt_seconds'] is int ? json['gesamt_seconds'] : int.parse(json['gesamt_seconds']?.toString() ?? '0'),
    );
  }

  String _format(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  String get fahrzeitDisplay => _format(fahrzeitSeconds);
  String get arbeitszeitDisplay => _format(arbeitszeitSeconds);
  String get wartezeitDisplay => _format(wartezeitSeconds);
  String get gesamtDisplay => _format(gesamtSeconds);
}

/// Result container for time entries
class TimeEntriesResult {
  final List<TimeEntry> entries;
  final TimeSummary summary;
  final TimeEntry? runningEntry;

  TimeEntriesResult({required this.entries, required this.summary, this.runningEntry});
}

/// Weekly time summary
class WeeklyTimeSummary {
  final int kw;
  final String weekStart;
  final String weekEnd;
  final TimeSummary summary;
  final List<DailyTime> daily;
  final int runningSeconds;
  final int maxWeeklySeconds;

  WeeklyTimeSummary({
    required this.kw,
    required this.weekStart,
    required this.weekEnd,
    required this.summary,
    required this.daily,
    required this.runningSeconds,
    required this.maxWeeklySeconds,
  });

  int get totalWithRunning => summary.gesamtSeconds + runningSeconds;

  String get totalDisplay {
    final s = totalWithRunning;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  String get maxDisplay {
    final h = maxWeeklySeconds ~/ 3600;
    return '${h}h';
  }

  double get progressPercent {
    if (maxWeeklySeconds <= 0) return 0;
    return (totalWithRunning / maxWeeklySeconds).clamp(0.0, 1.5);
  }

  bool get isOverLimit => totalWithRunning > maxWeeklySeconds;
}

/// Daily time entry for weekly breakdown
class DailyTime {
  final String date;
  final int totalSeconds;

  DailyTime({required this.date, required this.totalSeconds});

  String get display {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m';
  }
}

/// Per-ticket time breakdown
class TicketTimeBreakdown {
  final int ticketId;
  final String subject;
  final int fahrzeitSeconds;
  final int arbeitszeitSeconds;
  final int wartezeitSeconds;
  final int gesamtSeconds;

  TicketTimeBreakdown({
    required this.ticketId,
    required this.subject,
    required this.fahrzeitSeconds,
    required this.arbeitszeitSeconds,
    required this.wartezeitSeconds,
    required this.gesamtSeconds,
  });

  String get gesamtDisplay {
    final h = gesamtSeconds ~/ 3600;
    final m = (gesamtSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m';
  }
}

/// User time summary (time spent on a member's tickets)
class UserTimeSummary {
  final TimeSummary summary;
  final List<TicketTimeBreakdown> perTicket;
  final int runningSeconds;
  final int ticketCount;

  UserTimeSummary({
    required this.summary,
    required this.perTicket,
    required this.runningSeconds,
    required this.ticketCount,
  });

  int get totalWithRunning => summary.gesamtSeconds + runningSeconds;

  String get totalDisplay {
    final s = totalWithRunning;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }
}

/// Ticket model
class Ticket {
  final int id;
  final String subject;
  final String? originalSubject;
  final bool subjectIsTranslated;
  final String message;
  final String status;
  final String priority;
  final int? categoryId;
  final String? categoryName;
  final String? adminName;
  final String? memberName;      // For admin view
  final String? memberNummer;    // For admin view
  final String? memberVorname;
  final String? memberNachname;
  final String? memberGeburtsdatum;
  final String? memberStrasse;
  final String? memberHausnummer;
  final String? memberPlz;
  final String? memberOrt;
  final String? memberTelefon;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? closedAt;
  final DateTime? lastReplyAt;
  final DateTime? scheduledDate;
  final bool isUnread;
  final int totalTimeSeconds;

  Ticket({
    required this.id,
    required this.subject,
    this.originalSubject,
    this.subjectIsTranslated = false,
    required this.message,
    required this.status,
    required this.priority,
    this.categoryId,
    this.categoryName,
    this.adminName,
    this.memberName,
    this.memberNummer,
    this.memberVorname,
    this.memberNachname,
    this.memberGeburtsdatum,
    this.memberStrasse,
    this.memberHausnummer,
    this.memberPlz,
    this.memberOrt,
    this.memberTelefon,
    required this.createdAt,
    this.updatedAt,
    this.closedAt,
    this.lastReplyAt,
    this.scheduledDate,
    this.isUnread = false,
    this.totalTimeSeconds = 0,
  });

  factory Ticket.fromJson(Map<String, dynamic> json) {
    return Ticket(
      id: json['id'],
      subject: json['subject'],
      originalSubject: json['original_subject'],
      subjectIsTranslated: json['subject_is_translated'] ?? false,
      message: json['message'],
      status: json['status'],
      priority: json['priority'],
      categoryId: json['category_id'],
      categoryName: json['category_name'],
      adminName: json['admin_name'],
      memberName: json['member_name'],
      memberNummer: json['member_nummer'],
      memberVorname: json['member_vorname'],
      memberNachname: json['member_nachname'],
      memberGeburtsdatum: json['member_geburtsdatum'],
      memberStrasse: json['member_strasse'],
      memberHausnummer: json['member_hausnummer'],
      memberPlz: json['member_plz'],
      memberOrt: json['member_ort'],
      memberTelefon: json['member_telefon'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      closedAt: json['closed_at'] != null ? DateTime.parse(json['closed_at']) : null,
      lastReplyAt: json['last_reply_at'] != null ? DateTime.parse(json['last_reply_at']) : null,
      scheduledDate: json['scheduled_date'] != null ? DateTime.parse(json['scheduled_date']) : null,
      isUnread: json['is_unread'] ?? false,
      totalTimeSeconds: json['total_time_seconds'] is int ? json['total_time_seconds'] : int.tryParse(json['total_time_seconds']?.toString() ?? '0') ?? 0,
    );
  }

  String get statusDisplay {
    switch (status) {
      case 'open':
        return 'Offen';
      case 'in_progress':
        return 'In Bearbeitung';
      case 'waiting_member':
        return 'Warten auf Benutzer';
      case 'waiting_staff':
        return 'Warten auf Mitarbeiter';
      case 'waiting_authority':
        return 'Warten auf Behörde';
      case 'waiting_documents':
        return 'Warten auf Unterlagen';
      case 'done':
        return 'Erledigt';
      default:
        return status;
    }
  }

  String get priorityDisplay {
    switch (priority) {
      case 'low':
        return 'Niedrig';
      case 'medium':
        return 'Mittel';
      case 'high':
        return 'Hoch';
      default:
        return priority;
    }
  }

  /// Formatted time display for scheduled date, e.g. "09:30"
  String get scheduledTimeDisplay {
    if (scheduledDate == null) return '';
    return '${scheduledDate!.hour.toString().padLeft(2, '0')}:${scheduledDate!.minute.toString().padLeft(2, '0')}';
  }

  /// Formatted total time display, e.g. "2h 30m"
  String get totalTimeDisplay {
    if (totalTimeSeconds <= 0) return '';
    final h = totalTimeSeconds ~/ 3600;
    final m = (totalTimeSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m';
  }
}

/// Translation data for ticket subject/message
class TicketTranslation {
  final String subject;
  final String? originalSubject;
  final bool subjectIsTranslated;
  final String message;
  final String? originalMessage;
  final bool messageIsTranslated;

  TicketTranslation({
    required this.subject,
    this.originalSubject,
    this.subjectIsTranslated = false,
    required this.message,
    this.originalMessage,
    this.messageIsTranslated = false,
  });

  factory TicketTranslation.fromJson(Map<String, dynamic> json) {
    return TicketTranslation(
      subject: json['subject'] ?? '',
      originalSubject: json['original_subject'],
      subjectIsTranslated: json['subject_is_translated'] ?? false,
      message: json['message'] ?? '',
      originalMessage: json['original_message'],
      messageIsTranslated: json['message_is_translated'] ?? false,
    );
  }
}

/// Result container for ticket comments and attachments
class CommentsResult {
  final List<TicketComment> comments;
  final List<TicketAttachment> attachments;
  final TicketTranslation? ticketTranslation;

  CommentsResult({required this.comments, required this.attachments, this.ticketTranslation});
}

/// Ticket Service - handles ticket API calls
class TicketService {
  static const String baseUrl = 'https://icd360sev.icd360s.de/api';

  // ✅ SECURITY FIX: Removed hardcoded API key (extractable via reverse engineering)
  // All requests now use dynamic Device Key only

  late http.Client _client;
  final DeviceKeyService _deviceKeyService = DeviceKeyService();

  // Singleton pattern
  static final TicketService _instance = TicketService._internal();
  factory TicketService() => _instance;
  TicketService._internal() {
    _client = IOClient(HttpClientFactory.createPinnedHttpClient());
  }

  Map<String, String> get _headers {
    final deviceKey = _deviceKeyService.deviceKey;
    return {
      'Content-Type': 'application/json',
      'User-Agent': 'ICD360S-Vorsitzer/1.0',
      if (deviceKey != null) 'X-Device-Key': deviceKey,
    };
  }

  /// Get all tickets for a user
  Future<List<Ticket>> getTickets(String mitgliedernummer) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/list.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': mitgliedernummer,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final ticketsList = data['tickets'] as List;
        return ticketsList.map((t) => Ticket.fromJson(t)).toList();
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  /// Create a new ticket
  /// Returns {'ticket': Ticket} on success, {'error': String} on failure
  Future<Map<String, dynamic>> createTicket({
    required String mitgliedernummer,
    required String subject,
    required String message,
    String priority = 'medium',
    int? categoryId,
    bool systemTicket = false,
    String? scheduledDate,
  }) async {
    try {
      final body = <String, dynamic>{
        'mitgliedernummer': mitgliedernummer,
        'subject': subject,
        'message': message,
        'priority': priority,
        if (systemTicket) 'system_ticket': true,
        if (scheduledDate != null) 'scheduled_date': scheduledDate,
      };

      if (categoryId != null) {
        body['category_id'] = categoryId.toString();
      }

      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/create.php'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        return {'ticket': Ticket.fromJson(data['ticket'])};
      }

      // Weekly limit or other error
      final msg = data['message'] ?? 'Fehler beim Erstellen des Tickets';
      return {'error': msg};
    } catch (e) {
      return {'error': 'Fehler beim Erstellen des Tickets'};
    }
  }

  /// Create a ticket on behalf of a member (admin only)
  /// Returns {'ticket': Ticket} on success, {'error': String} on failure
  Future<Map<String, dynamic>> createTicketForMember({
    required String adminMitgliedernummer,
    required String memberMitgliedernummer,
    required String subject,
    required String message,
    String priority = 'medium',
    required String scheduledDate,
    bool systemAuto = false,
  }) async {
    try {
      final body = <String, dynamic>{
        'admin_mitgliedernummer': adminMitgliedernummer,
        'member_mitgliedernummer': memberMitgliedernummer,
        'subject': subject,
        'message': message,
        'priority': priority,
        'scheduled_date': scheduledDate,
        if (systemAuto) 'system_auto': true,
      };

      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/admin_create.php'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        return {'ticket': Ticket.fromJson(data['ticket'])};
      }

      // Weekly limit or other error
      final msg = data['message'] ?? 'Fehler beim Erstellen des Tickets';
      return {'error': msg};
    } catch (e) {
      return {'error': 'Fehler beim Erstellen des Tickets'};
    }
  }

  // ==================== ADMIN METHODS ====================

  /// Get all tickets (admin only), optionally filtered by member
  Future<AdminTicketsResult?> getAdminTickets(String mitgliedernummer, {String? statusFilter, String? memberMitgliedernummer}) async {
    try {
      final body = <String, dynamic>{
        'mitgliedernummer': mitgliedernummer,
      };
      if (statusFilter != null) {
        body['status'] = statusFilter;
      }
      if (memberMitgliedernummer != null) {
        body['member_mitgliedernummer'] = memberMitgliedernummer;
      }

      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/admin_list.php'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final ticketsList = data['tickets'] as List;
        final tickets = ticketsList.map((t) => Ticket.fromJson(t)).toList();
        final stats = TicketStats.fromJson(data['stats']);
        return AdminTicketsResult(tickets: tickets, stats: stats);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Update ticket (admin actions: assign, close, reopen, set_in_progress, set_scheduled_date)
  Future<Ticket?> updateTicket({
    required String mitgliedernummer,
    required int ticketId,
    required String action,
    String? scheduledDate,
  }) async {
    try {
      final body = <String, dynamic>{
        'mitgliedernummer': mitgliedernummer,
        'ticket_id': ticketId,
        'action': action,
      };
      if (scheduledDate != null) {
        body['scheduled_date'] = scheduledDate;
      }

      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/update.php'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return Ticket.fromJson(data['ticket']);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // ==================== CATEGORIES ====================

  /// Get all ticket categories
  Future<List<TicketCategory>> getCategories() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/tickets/categories/list.php'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final categoriesList = data['categories'] as List;
        return categoriesList.map((c) => TicketCategory.fromJson(c)).toList();
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  // ==================== COMMENTS ====================

  /// Add comment to a ticket
  Future<TicketComment?> addComment({
    required String mitgliedernummer,
    required int ticketId,
    required String comment,
    bool isInternal = false,
  }) async {
    try {
      _log.info('API: Adding comment to ticket $ticketId (internal=$isInternal, comment_length=${comment.length})', tag: 'TICKET_API');

      final requestBody = {
        'mitgliedernummer': mitgliedernummer,
        'ticket_id': ticketId,
        'comment': comment,
        'is_internal': isInternal,
      };

      _log.debug('API: Request body: ${jsonEncode(requestBody)}', tag: 'TICKET_API');

      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/comments/add.php'),
        headers: _headers,
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      _log.info('API: Response status=${response.statusCode}, body=${response.body}', tag: 'TICKET_API');

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        _log.info('API: Comment added successfully (id=${data['comment']['id']})', tag: 'TICKET_API');
        return TicketComment.fromJson(data['comment']);
      }

      _log.warning('API: Comment add failed - statusCode=${response.statusCode}, success=${data['success']}, message=${data['message']}', tag: 'TICKET_API');
      return null;
    } catch (e) {
      _log.error('API: Exception adding comment: $e', tag: 'TICKET_API');
      return null;
    }
  }

  /// Get all comments for a ticket
  Future<CommentsResult?> getComments({
    required String mitgliedernummer,
    required int ticketId,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/comments/list.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': mitgliedernummer,
          'ticket_id': ticketId,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final commentsList = data['comments'] as List;
        final attachmentsList = data['attachments'] as List;

        final comments = commentsList.map((c) => TicketComment.fromJson(c)).toList();
        final attachments = attachmentsList.map((a) => TicketAttachment.fromJson(a)).toList();

        TicketTranslation? ticketTranslation;
        if (data['ticket_translation'] != null) {
          ticketTranslation = TicketTranslation.fromJson(data['ticket_translation']);
        }

        return CommentsResult(comments: comments, attachments: attachments, ticketTranslation: ticketTranslation);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // ==================== ATTACHMENTS ====================

  /// Upload attachment to a ticket
  Future<TicketAttachment?> uploadAttachment({
    required String mitgliedernummer,
    required int ticketId,
    required String filePath,
    int? commentId,
  }) async {
    try {
      final deviceKey = _deviceKeyService.deviceKey;

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/tickets/attachments/upload.php'),
      );

      // Add headers
      if (deviceKey != null) {
        request.headers['X-Device-Key'] = deviceKey;
      }
      request.headers['User-Agent'] = 'ICD360S-Vorsitzer/1.0';

      // Add fields
      request.fields['mitgliedernummer'] = mitgliedernummer;
      request.fields['ticket_id'] = ticketId.toString();
      if (commentId != null) {
        request.fields['comment_id'] = commentId.toString();
      }

      // Add file
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        return TicketAttachment.fromJson(data['attachment']);
      }

      _log.error('Upload failed: status=${response.statusCode}, body=${response.body}', tag: 'TICKET_UPLOAD');
      return null;
    } catch (e) {
      _log.error('Upload exception: $e', tag: 'TICKET_UPLOAD');
      return null;
    }
  }

  /// Delete attachment
  Future<bool> deleteAttachment({
    required String mitgliedernummer,
    required int attachmentId,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/attachments/delete.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': mitgliedernummer,
          'attachment_id': attachmentId,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Download attachment to temp directory and return local file path
  Future<String?> downloadAttachment({
    required String mitgliedernummer,
    required int attachmentId,
    required String originalFilename,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/tickets/attachments/download.php?mitgliedernummer=$mitgliedernummer&attachment_id=$attachmentId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final tempDir = await Directory.systemTemp.createTemp('ticket_attachment_');
        final filePath = '${tempDir.path}/$originalFilename';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      }

      _log.error('Download failed: status=${response.statusCode}', tag: 'TICKET_DOWNLOAD');
      return null;
    } catch (e) {
      _log.error('Download exception: $e', tag: 'TICKET_DOWNLOAD');
      return null;
    }
  }

  /// Mark ticket as viewed (updates admin_last_viewed_at)
  Future<bool> markTicketAsViewed(int ticketId) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/mark_viewed.php'),
        headers: _headers,
        body: jsonEncode({'ticket_id': ticketId}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  // ==================== TIME TRACKING ====================

  /// Start timer for a ticket
  Future<TimeEntry?> startTimer({
    required String mitgliedernummer,
    required int ticketId,
    required String category,
    String? note,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/time/start.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': mitgliedernummer,
          'ticket_id': ticketId,
          'category': category,
          if (note != null) 'note': note,
        }),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['time_entry'] != null) {
        return TimeEntry.fromJson(data['time_entry']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Stop running timer for a ticket
  Future<TimeEntry?> stopTimer({required String mitgliedernummer, required int ticketId, String? note}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/time/stop.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': mitgliedernummer,
          'ticket_id': ticketId,
          if (note != null) 'note': note,
        }),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['time_entry'] != null) {
        return TimeEntry.fromJson(data['time_entry']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get all time entries for a ticket
  Future<TimeEntriesResult?> getTimeEntries({required String mitgliedernummer, required int ticketId}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/time/list.php'),
        headers: _headers,
        body: jsonEncode({'mitgliedernummer': mitgliedernummer, 'ticket_id': ticketId}),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final entriesList = data['time_entries'] as List? ?? [];
        final entries = entriesList.map((e) => TimeEntry.fromJson(e)).toList();
        final summary = TimeSummary.fromJson(data['summary'] ?? {});
        TimeEntry? running;
        if (data['running_entry'] != null) {
          running = TimeEntry.fromJson(data['running_entry']);
        }
        return TimeEntriesResult(entries: entries, summary: summary, runningEntry: running);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Add manual time entry
  Future<TimeEntry?> addManualTime({
    required String mitgliedernummer,
    required int ticketId,
    required String category,
    required int durationMinutes,
    String? note,
    String? date,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/time/add.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': mitgliedernummer,
          'ticket_id': ticketId,
          'category': category,
          'duration_minutes': durationMinutes,
          if (note != null) 'note': note,
          if (date != null) 'date': date,
        }),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['time_entry'] != null) {
        return TimeEntry.fromJson(data['time_entry']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Delete a time entry
  Future<bool> deleteTimeEntry({required String mitgliedernummer, required int timeEntryId}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/time/delete.php'),
        headers: _headers,
        body: jsonEncode({'mitgliedernummer': mitgliedernummer, 'time_entry_id': timeEntryId}),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Check if user has any running timer
  Future<TimeEntry?> getRunningTimer({required String mitgliedernummer}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/time/running.php'),
        headers: _headers,
        body: jsonEncode({'mitgliedernummer': mitgliedernummer}),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['has_running'] == true && data['running_entry'] != null) {
        return TimeEntry.fromJson(data['running_entry']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Sync running timer duration to database (periodic save)
  Future<bool> syncTimer({required String mitgliedernummer}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/time/sync.php'),
        headers: _headers,
        body: jsonEncode({'mitgliedernummer': mitgliedernummer}),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      return data['success'] == true && data['synced'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Get weekly time summary for dashboard
  Future<WeeklyTimeSummary?> getWeeklyTimeSummary({required String mitgliedernummer, String? weekStart}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/time/weekly.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': mitgliedernummer,
          if (weekStart != null) 'week_start': weekStart,
        }),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final summaryJson = data['summary'] ?? {};
        final dailyList = (data['daily'] as List? ?? []).map((d) => DailyTime(
          date: d['date'],
          totalSeconds: d['total_seconds'] is int ? d['total_seconds'] : int.parse(d['total_seconds'].toString()),
        )).toList();
        return WeeklyTimeSummary(
          kw: data['kw'] is int ? data['kw'] : int.parse(data['kw'].toString()),
          weekStart: data['week_start'],
          weekEnd: data['week_end'],
          summary: TimeSummary.fromJson(summaryJson),
          daily: dailyList,
          runningSeconds: data['running_seconds'] is int ? data['running_seconds'] : int.parse(data['running_seconds'].toString()),
          maxWeeklySeconds: data['max_weekly_seconds'] is int ? data['max_weekly_seconds'] : int.parse(data['max_weekly_seconds'].toString()),
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get time summary for a specific member's tickets
  Future<UserTimeSummary?> getUserTimeSummary({required String mitgliedernummer, required String memberMitgliedernummer}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/time/user_summary.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': mitgliedernummer,
          'member_mitgliedernummer': memberMitgliedernummer,
        }),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final summaryJson = data['summary'] ?? {};
        final perTicketList = (data['per_ticket'] as List? ?? []).map((t) => TicketTimeBreakdown(
          ticketId: t['ticket_id'] is int ? t['ticket_id'] : int.parse(t['ticket_id'].toString()),
          subject: t['subject'] ?? '',
          fahrzeitSeconds: t['fahrzeit_seconds'] is int ? t['fahrzeit_seconds'] : int.parse(t['fahrzeit_seconds']?.toString() ?? '0'),
          arbeitszeitSeconds: t['arbeitszeit_seconds'] is int ? t['arbeitszeit_seconds'] : int.parse(t['arbeitszeit_seconds']?.toString() ?? '0'),
          wartezeitSeconds: t['wartezeit_seconds'] is int ? t['wartezeit_seconds'] : int.parse(t['wartezeit_seconds']?.toString() ?? '0'),
          gesamtSeconds: t['gesamt_seconds'] is int ? t['gesamt_seconds'] : int.parse(t['gesamt_seconds']?.toString() ?? '0'),
        )).toList();
        return UserTimeSummary(
          summary: TimeSummary.fromJson(summaryJson),
          perTicket: perTicketList,
          runningSeconds: data['running_seconds'] is int ? data['running_seconds'] : int.parse(data['running_seconds']?.toString() ?? '0'),
          ticketCount: data['ticket_count'] is int ? data['ticket_count'] : int.parse(data['ticket_count']?.toString() ?? '0'),
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // Aufgaben (Tasks) per Ticket
  // ============================================================

  /// Get all aufgaben for a ticket
  Future<AufgabenResult?> getAufgaben({required String mitgliedernummer, required int ticketId}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/aufgaben/list.php'),
        headers: _headers,
        body: jsonEncode({'mitgliedernummer': mitgliedernummer, 'ticket_id': ticketId}),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final list = (data['aufgaben'] as List? ?? []).map((e) => TicketAufgabe.fromJson(e)).toList();
        final stats = data['stats'] as Map<String, dynamic>? ?? {};
        return AufgabenResult(
          aufgaben: list,
          total: stats['total'] ?? 0,
          offen: stats['offen'] ?? 0,
          erledigt: stats['erledigt'] ?? 0,
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Create a new aufgabe for a ticket
  Future<TicketAufgabe?> createAufgabe({
    required String mitgliedernummer,
    required int ticketId,
    required String title,
    String? description,
    String priority = 'mittel',
    String? assignedTo,
    String? dueDate,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/aufgaben/create.php'),
        headers: _headers,
        body: jsonEncode({
          'mitgliedernummer': mitgliedernummer,
          'ticket_id': ticketId,
          'title': title,
          if (description != null) 'description': description,
          'priority': priority,
          if (assignedTo != null) 'assigned_to': assignedTo,
          if (dueDate != null) 'due_date': dueDate,
        }),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['aufgabe'] != null) {
        return TicketAufgabe.fromJson(data['aufgabe']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Update an aufgabe
  Future<TicketAufgabe?> updateAufgabe({
    required String mitgliedernummer,
    required int aufgabeId,
    String? title,
    String? description,
    String? status,
    String? priority,
    String? assignedTo,
    String? dueDate,
  }) async {
    try {
      final body = <String, dynamic>{
        'mitgliedernummer': mitgliedernummer,
        'aufgabe_id': aufgabeId,
      };
      if (title != null) body['title'] = title;
      if (description != null) body['description'] = description;
      if (status != null) body['status'] = status;
      if (priority != null) body['priority'] = priority;
      if (assignedTo != null) body['assigned_to'] = assignedTo;
      if (dueDate != null) body['due_date'] = dueDate;

      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/aufgaben/update.php'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['aufgabe'] != null) {
        return TicketAufgabe.fromJson(data['aufgabe']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Toggle aufgabe status (offen <-> erledigt)
  Future<TicketAufgabe?> toggleAufgabe({required String mitgliedernummer, required int aufgabeId}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/aufgaben/toggle.php'),
        headers: _headers,
        body: jsonEncode({'mitgliedernummer': mitgliedernummer, 'aufgabe_id': aufgabeId}),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['aufgabe'] != null) {
        return TicketAufgabe.fromJson(data['aufgabe']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Delete an aufgabe
  Future<bool> deleteAufgabe({required String mitgliedernummer, required int aufgabeId}) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/tickets/aufgaben/delete.php'),
        headers: _headers,
        body: jsonEncode({'mitgliedernummer': mitgliedernummer, 'aufgabe_id': aufgabeId}),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      return false;
    }
  }
}

/// Ticket Aufgabe (Task) model
class TicketAufgabe {
  final int id;
  final int ticketId;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final String? assignedTo;
  final String? assignedName;
  final String? dueDate;
  final String createdBy;
  final String? createdByName;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  TicketAufgabe({
    required this.id,
    required this.ticketId,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    this.assignedTo,
    this.assignedName,
    this.dueDate,
    required this.createdBy,
    this.createdByName,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  bool get isErledigt => status == 'erledigt';

  factory TicketAufgabe.fromJson(Map<String, dynamic> json) {
    return TicketAufgabe(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      ticketId: json['ticket_id'] is int ? json['ticket_id'] : int.parse(json['ticket_id'].toString()),
      title: json['title'] ?? '',
      description: json['description'],
      status: json['status'] ?? 'offen',
      priority: json['priority'] ?? 'mittel',
      assignedTo: json['assigned_to'],
      assignedName: json['assigned_name'],
      dueDate: json['due_date'],
      createdBy: json['created_by'] ?? '',
      createdByName: json['created_by_name'],
      sortOrder: json['sort_order'] is int ? json['sort_order'] : int.parse(json['sort_order']?.toString() ?? '0'),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
    );
  }
}

/// Result container for aufgaben list
class AufgabenResult {
  final List<TicketAufgabe> aufgaben;
  final int total;
  final int offen;
  final int erledigt;

  AufgabenResult({required this.aufgaben, required this.total, required this.offen, required this.erledigt});
}

/// Ticket statistics for admin dashboard
class TicketStats {
  final int total;
  final int open;
  final int inProgress;
  final int waitingMember;
  final int waitingStaff;
  final int waitingAuthority;
  final int done;

  TicketStats({
    required this.total,
    required this.open,
    required this.inProgress,
    required this.waitingMember,
    required this.waitingStaff,
    required this.waitingAuthority,
    required this.done,
  });

  factory TicketStats.fromJson(Map<String, dynamic> json) {
    return TicketStats(
      total: json['total'] ?? 0,
      open: json['open'] ?? 0,
      inProgress: json['in_progress'] ?? 0,
      waitingMember: json['waiting_member'] ?? 0,
      waitingStaff: json['waiting_staff'] ?? 0,
      waitingAuthority: json['waiting_authority'] ?? 0,
      done: json['done'] ?? 0,
    );
  }
}

/// Result container for admin ticket list
class AdminTicketsResult {
  final List<Ticket> tickets;
  final TicketStats stats;

  AdminTicketsResult({required this.tickets, required this.stats});
}
