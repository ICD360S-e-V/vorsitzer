import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Records every step of main() to a plain-text log file from the very
/// first call, so a startup that never reaches runApp() is still
/// debuggable. The transcript is also POSTed to a central endpoint
/// (AES-256-GCM-encrypted) three seconds after runApp(), once the
/// first frame has rendered.
///
/// Wire format (POST body, application/json):
///   `{ "v": 1, "iv": "<base64 12B>", "data": "<base64 ct||tag>" }`
///
/// Server decrypts with openssl_decrypt(ct, "aes-256-gcm", $key,
/// OPENSSL_RAW_DATA, $iv, $tag) after substr(-16) split.
class StartupDiagnostics {
  StartupDiagnostics._();

  static final List<String> _entries = [];
  static File? _logFile;
  static bool _hadFailure = false;

  static bool get hadFailure => _hadFailure;
  static String get logPath => _logFile?.path ?? '';
  static String get transcript => _entries.join('\n');

  // App slug — matches the server endpoint family vorsitzer_<platform>.php
  // and the on-disk cache folder ~/.cache/vorsitzer/.
  static const _appSlug = 'vorsitzer';
  static const _reportBase = 'https://icd360sev.icd360s.de/api/logs';

  // The AES-256 key (64 hex chars) is supplied at build time via
  // --dart-define=STARTUP_DIAG_KEY=... from a GitHub Secret. Empty here
  // means the upload short-circuits — local-only mode (flutter run).
  // Never commit a default value.
  static const _diagKeyHex =
      String.fromEnvironment('STARTUP_DIAG_KEY', defaultValue: '');

  static String get _reportUrl {
    // Flatpak Linux gets its own bucket so we can correlate sandbox-specific
    // failures (missing libmpv, missing appindicator, XDG portal issues).
    // The naming "flatpack" is intentional — it matches the sibling
    // mitglieder_flatpack.php endpoint that's already deployed.
    if (Platform.environment['FLATPAK_ID'] != null) {
      return '$_reportBase/${_appSlug}_flatpack.php';
    }
    if (Platform.isWindows) return '$_reportBase/${_appSlug}_windows.php';
    if (Platform.isAndroid) return '$_reportBase/${_appSlug}_android.php';
    if (Platform.isMacOS)   return '$_reportBase/${_appSlug}_macos.php';
    if (Platform.isIOS)     return '$_reportBase/${_appSlug}_ios.php';
    // Linux without FLATPAK_ID — direct binary run, AppImage, etc.
    if (Platform.isLinux)   return '$_reportBase/${_appSlug}_linux.php';
    return '$_reportBase/${_appSlug}_startup.php';
  }

  /// Open the on-disk transcript and prime it with the environment dump.
  /// Safe to call from the very first line of main(); never throws.
  static void init() {
    if (_logFile == null) {
      try {
        final dir = _resolveDir();
        Directory(dir).createSync(recursive: true);
        _logFile = File('$dir/startup.log');
      } catch (_) {
        try {
          _logFile = File('/tmp/$_appSlug-startup.log');
        } catch (_) {}
      }
      // Truncate so yesterday's hang doesn't pollute today's transcript.
      try {
        _logFile?.writeAsStringSync('');
      } catch (_) {}
    }
    log('==================================================');
    log('startup @ ${DateTime.now().toIso8601String()}');
    log('OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    log('Dart: ${Platform.version.split(' ').first}');
    log('locale: ${Platform.localeName}');
    log('executable: ${Platform.resolvedExecutable}');
    log('inDebug: $kDebugMode  inProfile: $kProfileMode  inRelease: $kReleaseMode');
    log('-- environment hints --');
    for (final key in const [
      'XDG_SESSION_TYPE', 'XDG_CURRENT_DESKTOP',
      'WAYLAND_DISPLAY', 'DISPLAY', 'GDK_BACKEND', 'QT_QPA_PLATFORM',
      'LIBGL_ALWAYS_SOFTWARE', 'GALLIUM_DRIVER', 'MESA_LOADER_DRIVER_OVERRIDE',
      'FLATPAK_ID', 'container',
    ]) {
      log('  $key=${Platform.environment[key] ?? "<unset>"}');
    }
    log('-- end environment --');
  }

  /// Append one line to memory + disk. Errors are swallowed — diagnostics
  /// must never themselves crash the app.
  static void log(String msg) {
    final line = '[${DateTime.now().toIso8601String()}] $msg';
    _entries.add(line);
    debugPrint(line);
    try {
      _logFile?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// Run [body] with a wall-clock budget; record START / DONE / FAIL /
  /// TIMEOUT to the transcript. Never rethrows — returns null on any
  /// failure so the caller can keep going and `runApp()` still happens.
  static Future<T?> stepWithTimeout<T>(
    String name,
    Duration timeout,
    Future<T> Function() body,
  ) async {
    log('→ START $name (budget ${timeout.inSeconds}s)');
    final sw = Stopwatch()..start();
    try {
      final result = await body().timeout(timeout);
      log('  ← DONE  $name  (${sw.elapsedMilliseconds}ms)');
      return result;
    } on Object catch (e, st) {
      _hadFailure = true;
      final isTimeout = e.toString().contains('TimeoutException');
      log('  ✗ ${isTimeout ? "TIMEOUT" : "FAIL"}  $name  '
          '(${sw.elapsedMilliseconds}ms): $e');
      if (!isTimeout) {
        for (final s in st.toString().split('\n').take(8)) {
          if (s.isNotEmpty) log('     $s');
        }
      }
      return null;
    }
  }

  /// Encrypt and POST the transcript to the central endpoint. Fire-and-forget:
  /// must be invoked AFTER runApp() (typically Future.delayed(3s)) so the
  /// first frame has time to render. Silently no-ops if the key was not
  /// injected at build time (e.g. local `flutter run`).
  static Future<void> uploadToServer({
    String? appVersion,
    String? deviceId,
    String? mitgliedernummer,
  }) async {
    if (_entries.isEmpty) return;
    if (_diagKeyHex.isEmpty || _diagKeyHex.length != 64) {
      log('→ uploadToServer skipped (no STARTUP_DIAG_KEY at build time)');
      return;
    }
    log('→ uploadToServer ($_reportUrl)');
    try {
      final plaintext = utf8.encode(jsonEncode({
        'mitgliedernummer': mitgliedernummer ?? '',
        'device_id': deviceId ?? 'unknown',
        'platform': Platform.operatingSystem,
        'app_version': appVersion ?? 'unknown',
        'logs': [
          {
            'timestamp': DateTime.now().toIso8601String(),
            'message': _entries.join('\n'),
            'level': _hadFailure ? 'error' : 'info',
            'tag': 'STARTUP',
          }
        ],
      }));

      final aes = AesGcm.with256bits();
      final secretKey = SecretKey(_hexToBytes(_diagKeyHex));
      final nonce =
          List<int>.generate(12, (_) => Random.secure().nextInt(256));
      final box = await aes.encrypt(plaintext,
          secretKey: secretKey, nonce: nonce);

      // PHP expects ciphertext || tag concatenated; it splits with substr(-16).
      final packed = Uint8List(box.cipherText.length + box.mac.bytes.length)
        ..setRange(0, box.cipherText.length, box.cipherText)
        ..setRange(box.cipherText.length,
            box.cipherText.length + box.mac.bytes.length, box.mac.bytes);

      final envelope = jsonEncode({
        'v': 1,
        'iv': base64.encode(nonce),
        'data': base64.encode(packed),
      });

      final res = await http
          .post(
            Uri.parse(_reportUrl),
            headers: {'Content-Type': 'application/json'},
            body: envelope,
          )
          .timeout(const Duration(seconds: 10));
      log('  ← uploadToServer status=${res.statusCode}');
    } catch (e) {
      log('  ✗ uploadToServer failed: $e');
    }
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// XDG-cache aware log directory: $XDG_CACHE_HOME/vorsitzer/ on Linux,
  /// $HOME/.cache/vorsitzer/ as fallback, $TMPDIR or /tmp otherwise.
  static String _resolveDir() {
    final xdg = Platform.environment['XDG_CACHE_HOME'];
    if (xdg != null && xdg.isNotEmpty) return '$xdg/$_appSlug';
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) return '$home/.cache/$_appSlug';
    return Platform.environment['TMPDIR'] ?? '/tmp';
  }
}
