import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Member document model
class MemberDokument {
  final int id;
  final int userId;
  final String dokumentName;
  final String originalFilename;
  final String storedFilename;
  final int filesize;
  final String mimeType;
  final String? beschreibung;
  final String kategorie; // 'vereindokumente' or 'behoerde'
  final String? dokumentTyp;
  final DateTime? ablaufDatum;
  final bool isEncrypted;
  final int? daysUntilExpiry;
  final int uploadedBy;
  final String uploadedByName;
  final DateTime createdAt;

  MemberDokument({
    required this.id,
    required this.userId,
    required this.dokumentName,
    required this.originalFilename,
    required this.storedFilename,
    required this.filesize,
    required this.mimeType,
    this.beschreibung,
    required this.kategorie,
    this.dokumentTyp,
    this.ablaufDatum,
    this.isEncrypted = false,
    this.daysUntilExpiry,
    required this.uploadedBy,
    required this.uploadedByName,
    required this.createdAt,
  });

  factory MemberDokument.fromJson(Map<String, dynamic> json) {
    return MemberDokument(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      userId: json['user_id'] is int ? json['user_id'] : int.parse(json['user_id'].toString()),
      dokumentName: json['dokument_name'] ?? '',
      originalFilename: json['original_filename'] ?? '',
      storedFilename: json['stored_filename'] ?? '',
      filesize: json['filesize'] is int ? json['filesize'] : int.parse(json['filesize'].toString()),
      mimeType: json['mime_type'] ?? '',
      beschreibung: json['beschreibung'],
      kategorie: json['kategorie'] ?? 'vereindokumente',
      dokumentTyp: json['dokument_typ'],
      ablaufDatum: json['ablauf_datum'] != null ? DateTime.tryParse(json['ablauf_datum']) : null,
      isEncrypted: json['is_encrypted'] == 1 || json['is_encrypted'] == true,
      daysUntilExpiry: json['days_until_expiry'] != null ? (json['days_until_expiry'] is int ? json['days_until_expiry'] : int.tryParse(json['days_until_expiry'].toString())) : null,
      uploadedBy: json['uploaded_by'] is int ? json['uploaded_by'] : int.parse(json['uploaded_by'].toString()),
      uploadedByName: json['uploaded_by_name'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  String get filesizeFormatted {
    if (filesize < 1024) return '$filesize B';
    if (filesize < 1024 * 1024) return '${(filesize / 1024).toStringAsFixed(1)} KB';
    return '${(filesize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get fileExtension {
    final parts = originalFilename.split('.');
    return parts.length > 1 ? parts.last.toUpperCase() : '';
  }

  bool get isExpired => ablaufDatum != null && ablaufDatum!.isBefore(DateTime.now());

  bool get isExpiringSoon => daysUntilExpiry != null && daysUntilExpiry! >= 0 && daysUntilExpiry! <= 30;
}

/// DokumenteService - handles member document API calls
class DokumenteService {
  static const String baseUrl = 'https://icd360sev.icd360s.de/api';
  // ✅ SECURITY FIX: Removed hardcoded API key (extractable via reverse engineering)
  // All requests now use dynamic Device Key only

  late http.Client _client;
  final DeviceKeyService _deviceKeyService = DeviceKeyService();
  String? _token;

  // Singleton
  static final DokumenteService _instance = DokumenteService._internal();
  factory DokumenteService() => _instance;
  DokumenteService._internal() {
    _client = IOClient(HttpClientFactory.createPinnedHttpClient());
  }

  void setToken(String? token) => _token = token;

  Map<String, String> get _headers {
    final deviceKey = _deviceKeyService.deviceKey;
    return {
      'Content-Type': 'application/json',
      'User-Agent': 'ICD360S-Vorsitzer/1.0',
      if (_token != null) 'Authorization': 'Bearer $_token',
      if (deviceKey != null) 'X-Device-Key': deviceKey,
    };
  }

  /// Upload a single document for a user
  Future<MemberDokument?> uploadDokument({
    required int userId,
    required String dokumentName,
    required File file,
    String? beschreibung,
    String kategorie = 'vereindokumente',
    String? dokumentTyp,
    String? ablaufDatum,
  }) async {
    try {
      final deviceKey = _deviceKeyService.deviceKey;
      final uri = Uri.parse('$baseUrl/admin/dokumente_upload.php');
      final request = http.MultipartRequest('POST', uri);

      request.headers['User-Agent'] = 'ICD360S-Vorsitzer/1.0';
      if (_token != null) {
        request.headers['Authorization'] = 'Bearer $_token';
      }
      if (deviceKey != null) {
        request.headers['X-Device-Key'] = deviceKey;
      }

      request.fields['user_id'] = userId.toString();
      request.fields['dokument_name'] = dokumentName;
      request.fields['kategorie'] = kategorie;
      if (beschreibung != null && beschreibung.isNotEmpty) {
        request.fields['beschreibung'] = beschreibung;
      }
      if (dokumentTyp != null && dokumentTyp.isNotEmpty) {
        request.fields['dokument_typ'] = dokumentTyp;
      }
      if (ablaufDatum != null && ablaufDatum.isNotEmpty) {
        request.fields['ablauf_datum'] = ablaufDatum;
      }

      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      _log.debug('Upload request to: ${uri.toString()}', tag: 'DOKUMENTE');
      _log.debug('Headers: ${request.headers}', tag: 'DOKUMENTE');
      _log.debug('Fields: ${request.fields}', tag: 'DOKUMENTE');
      _log.debug('Files count: ${request.files.length}', tag: 'DOKUMENTE');

      final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      _log.debug('Upload response status: ${response.statusCode}', tag: 'DOKUMENTE');
      _log.debug('Upload response body: ${response.body}', tag: 'DOKUMENTE');

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        return MemberDokument.fromJson(data['dokument']);
      }

      _log.error('Upload failed: status=${response.statusCode}, body=${response.body}', tag: 'DOKUMENTE');
      return null;
    } catch (e) {
      _log.error('Upload exception: $e', tag: 'DOKUMENTE');
      return null;
    }
  }

  /// Upload multiple documents for a user (batch upload, max 10)
  Future<List<MemberDokument>> uploadMultipleDokumente({
    required int userId,
    required List<File> files,
    String dokumentName = '',
    String? beschreibung,
    String kategorie = 'vereindokumente',
    String? dokumentTyp,
    String? ablaufDatum,
  }) async {
    try {
      final deviceKey = _deviceKeyService.deviceKey;
      final uri = Uri.parse('$baseUrl/admin/dokumente_upload.php');
      final request = http.MultipartRequest('POST', uri);

      request.headers['User-Agent'] = 'ICD360S-Vorsitzer/1.0';
      if (_token != null) {
        request.headers['Authorization'] = 'Bearer $_token';
      }
      if (deviceKey != null) {
        request.headers['X-Device-Key'] = deviceKey;
      }

      request.fields['user_id'] = userId.toString();
      request.fields['dokument_name'] = dokumentName;
      request.fields['kategorie'] = kategorie;
      if (beschreibung != null && beschreibung.isNotEmpty) {
        request.fields['beschreibung'] = beschreibung;
      }
      if (dokumentTyp != null && dokumentTyp.isNotEmpty) {
        request.fields['dokument_typ'] = dokumentTyp;
      }
      if (ablaufDatum != null && ablaufDatum.isNotEmpty) {
        request.fields['ablauf_datum'] = ablaufDatum;
      }

      for (final file in files) {
        request.files.add(await http.MultipartFile.fromPath('files[]', file.path));
      }

      _log.debug('Multi-upload request to: ${uri.toString()}', tag: 'DOKUMENTE');
      _log.debug('Files count: ${request.files.length}', tag: 'DOKUMENTE');

      final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      _log.debug('Multi-upload response status: ${response.statusCode}', tag: 'DOKUMENTE');
      _log.debug('Multi-upload response body: ${response.body}', tag: 'DOKUMENTE');

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        if (data['dokumente'] != null) {
          return (data['dokumente'] as List).map((d) => MemberDokument.fromJson(d)).toList();
        } else if (data['dokument'] != null) {
          return [MemberDokument.fromJson(data['dokument'])];
        }
      }

      _log.error('Multi-upload failed: status=${response.statusCode}, body=${response.body}', tag: 'DOKUMENTE');
      return [];
    } catch (e) {
      _log.error('Multi-upload exception: $e', tag: 'DOKUMENTE');
      return [];
    }
  }

  /// Get all documents for a user
  Future<List<MemberDokument>> getDokumente(int userId) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/admin/dokumente_list.php?user_id=$userId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final list = data['dokumente'] as List;
        return list.map((d) => MemberDokument.fromJson(d)).toList();
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  /// Delete a document
  Future<bool> deleteDokument(int id) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/admin/dokumente_delete.php'),
        headers: _headers,
        body: jsonEncode({'id': id}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Download a document (returns base64 data)
  Future<Map<String, dynamic>?> downloadDokument(int id) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/admin/dokumente_download.php'),
        headers: _headers,
        body: jsonEncode({'id': id}),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'filename': data['filename'],
          'mime_type': data['mime_type'],
          'filesize': data['filesize'],
          'data': data['data'], // base64
        };
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
