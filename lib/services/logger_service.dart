import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'api_service.dart';
import 'http_client_factory.dart';
import 'update_service.dart';

/// Logger Service - captures app logs for debugging
class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal() {
    _httpClient = IOClient(HttpClientFactory.createPinnedHttpClient());
  }

  final List<LogEntry> _logs = [];
  final _controller = StreamController<List<LogEntry>>.broadcast();
  final _secureStorage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  late final http.Client _httpClient;

  String? _deviceId;
  String? _machineName;

  // Log upload system
  final List<LogEntry> _uploadQueue = [];
  Timer? _uploadTimer;
  String? _mitgliedernummer;

  static const String _uploadUrl = 'https://icd360sev.icd360s.de/api/logs/vorsitzer_logs.php';
  static const Duration _uploadInterval = Duration(seconds: 30);

  Stream<List<LogEntry>> get logStream => _controller.stream;
  List<LogEntry> get logs => List.unmodifiable(_logs);
  String get deviceId => _deviceId ?? 'unknown';
  String get machineName => _machineName ?? 'unknown';

  /// Initialize device ID (call once at app startup)
  Future<void> init() async {
    // Get machine name
    try {
      _machineName = Platform.localHostname;
    } catch (e) {
      _machineName = 'unknown';
    }

    // Get or generate persistent device ID
    try {
      _deviceId = await _secureStorage.read(key: 'device_id');
      if (_deviceId == null) {
        _deviceId = _generateDeviceId();
        await _secureStorage.write(key: 'device_id', value: _deviceId);
      }
    } catch (e) {
      _deviceId = _generateDeviceId();
    }

    info('Logger initialized: deviceId=$_deviceId, machine=$_machineName', tag: 'SYS');
  }

  String _generateDeviceId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void log(String message, {LogLevel level = LogLevel.info, String? tag}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      message: message,
      level: level,
      tag: tag,
    );
    _logs.add(entry);
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    _controller.add(_logs);

    // Add to upload queue
    _uploadQueue.add(entry);
    if (_uploadQueue.length > 500) {
      _uploadQueue.removeAt(0);
    }

    // Upload immediately for errors
    if (level == LogLevel.error && _mitgliedernummer != null) {
      _uploadLogsToServer();
    }
  }

  void info(String message, {String? tag}) => log(message, level: LogLevel.info, tag: tag);
  void warning(String message, {String? tag}) => log(message, level: LogLevel.warning, tag: tag);
  void error(String message, {String? tag}) => log(message, level: LogLevel.error, tag: tag);
  void debug(String message, {String? tag}) => log(message, level: LogLevel.debug, tag: tag);

  void clear() {
    _logs.clear();
    _controller.add(_logs);
  }

  String exportLogs() {
    final buffer = StringBuffer();
    buffer.writeln('=== ICD360S e.V Log Export ===');
    buffer.writeln('Exported: ${DateTime.now()}');
    buffer.writeln('Device ID: $_deviceId');
    buffer.writeln('Machine: $_machineName');
    buffer.writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buffer.writeln('Total entries: ${_logs.length}');
    buffer.writeln('');

    for (final entry in _logs) {
      buffer.writeln(entry.toString());
    }
    return buffer.toString();
  }

  /// Push logs to server after user login
  Future<bool> pushToServer(String mitgliedernummer) async {
    if (_logs.isEmpty) return true;

    try {
      final logsJson = _logs.map((e) => {
        'timestamp': e.timestamp.toIso8601String(),
        'level': e.level.name,
        'tag': e.tag,
        'message': e.message,
      }).toList();

      final result = await ApiService().pushLogs(
        mitgliedernummer: mitgliedernummer,
        deviceId: deviceId,
        machineName: machineName,
        platform: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        logs: logsJson,
      );

      if (result['success'] == true) {
        info('Logs pushed to server (${_logs.length} entries)', tag: 'SYS');
        return true;
      } else {
        warning('Failed to push logs: ${result['message']}', tag: 'SYS');
        return false;
      }
    } catch (e) {
      error('Push logs error: $e', tag: 'SYS');
      return false;
    }
  }

  /// Start periodic log upload to server (every 30s)
  void startUpload(String mitgliedernummer) {
    _mitgliedernummer = mitgliedernummer;
    _uploadTimer?.cancel();
    _uploadTimer = Timer.periodic(_uploadInterval, (_) => _uploadLogsToServer());
    info('Log upload started for $mitgliedernummer (every ${_uploadInterval.inSeconds}s)', tag: 'LOG');
  }

  /// Stop log upload
  void stopUpload() {
    _uploadTimer?.cancel();
    _uploadTimer = null;
    info('Log upload stopped', tag: 'LOG');
  }

  /// Upload logs to server
  Future<void> _uploadLogsToServer() async {
    if (_uploadQueue.isEmpty || _mitgliedernummer == null) return;

    try {
      final logsToUpload = List<LogEntry>.from(_uploadQueue);
      _uploadQueue.clear();

      final logsJson = logsToUpload.map((log) => {
        'timestamp': log.timestamp.toIso8601String(),
        'message': log.message,
        'level': log.level.toString().split('.').last,
        'tag': log.tag,
      }).toList();

      final response = await _httpClient.post(
        Uri.parse(_uploadUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'mitgliedernummer': _mitgliedernummer,
          'device_id': _deviceId,
          'machine_name': _machineName,
          'platform': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          'app_version': UpdateService.currentVersion, // CRITICAL: Track app version!
          'build_number': UpdateService.currentBuildNumber,
          'logs': logsJson,
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        debug('Uploaded ${logsToUpload.length} logs to server', tag: 'LOG');
      } else {
        warning('Upload failed: ${response.statusCode}', tag: 'LOG');
        _uploadQueue.addAll(logsToUpload); // Re-queue on failure
      }
    } catch (e) {
      warning('Upload error: $e', tag: 'LOG');
      // Don't re-add to queue to avoid infinite growth on network errors
    }
  }
}

enum LogLevel { debug, info, warning, error }

class LogEntry {
  final DateTime timestamp;
  final String message;
  final LogLevel level;
  final String? tag;

  LogEntry({
    required this.timestamp,
    required this.message,
    required this.level,
    this.tag,
  });

  String get levelIcon {
    switch (level) {
      case LogLevel.debug:
        return '[D]';
      case LogLevel.info:
        return '[I]';
      case LogLevel.warning:
        return '[W]';
      case LogLevel.error:
        return '[E]';
    }
  }

  @override
  String toString() {
    final time = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    final tagStr = tag != null ? '[$tag] ' : '';
    return '$time $levelIcon $tagStr$message';
  }
}
