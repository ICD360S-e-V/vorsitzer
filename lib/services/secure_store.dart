import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:dbus/dbus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_crypto_service.dart';
import 'logger_service.dart';

/// Cross-platform secure key/value store with a **Linux-only** encrypted-file
/// fallback for when the system keyring (gnome-keyring / KWallet via libsecret)
/// is unavailable or locked.
///
/// On Linux this is the common case, not an edge case: under auto-login,
/// headless / xrdp / minimal-desktop sessions, and inside some Flatpak
/// sandboxes the login keyring is never unlocked, so `flutter_secure_storage`
/// throws `libsecret_error: Failed to unlock the keyring`. Without a fallback
/// the device_key + JWT never persist and the user must re-activate the app on
/// every launch.
///
/// Behaviour by platform:
///  * Windows / macOS / iOS / Android → pure pass-through to
///    [FlutterSecureStorage]: identical calls, identical exceptions. Nothing
///    about those platforms changes (callers keep their own macOS `-34018`
///    handling, which still runs because we re-throw here).
///  * Linux → the keyring is still tried first and preferred, but every secret
///    is ALSO mirrored into an AES-256-GCM encrypted file in the app-support
///    dir. A value written while the keyring happened to be open therefore
///    still survives when the keyring is locked on the next launch (and vice
///    versa). Reads fall back to that file whenever the keyring throws or
///    returns null, and legacy plaintext values left in SharedPreferences by
///    older builds are transparently migrated in (and the plaintext copy
///    removed).
///
/// The file key is derived from the machine-id (+ a compile-time app secret),
/// so the ciphertext is NOT decryptable by copying the file to another machine.
/// This is deliberately weaker than a hardware-backed keyring — the key
/// material is re-derivable on the same box — but the Linux home dir is
/// normally encrypted at rest anyway, so it is an acceptable fallback and a
/// large improvement over the plaintext SharedPreferences copy it replaces.
/// The keyring is always preferred when it actually works.
class SecureStore {
  SecureStore({MacOsOptions? mOptions})
      : _storage = FlutterSecureStorage(
          mOptions: mOptions ??
              const MacOsOptions(usesDataProtectionKeychain: false),
        );

  final FlutterSecureStorage _storage;
  final LoggerService _log = LoggerService();

  // Compile-time secret mixed into the machine-id-derived key. Not a substitute
  // for a real keyring; it only ensures the fallback file is bound to *this*
  // app on *this* machine.
  static const String _appSecret =
      'ICD360S_Vorsitzer_LinuxKeyringFallback_v1';
  static const String _fallbackFileName = 'secure_fallback.enc';
  static const String _randomKeyFileName = 'secure_fallback.key';

  // Serialises every read-modify-write on the fallback file across ALL
  // SecureStore instances in the process (DeviceKeyService + ApiService each
  // own one), so two near-simultaneous writes during activation can't clobber
  // each other's keys.
  static Future<void> _ioGate = Future<void>.value();

  // Once the keyring fails (locked / no secrets service), stop calling it for
  // the rest of the process. A locked libsecret call blocks for the FULL ~25s
  // D-Bus timeout before throwing, so re-trying it on every secret read/write
  // adds minutes of startup hang (observed in the field). Process-wide so the
  // first failure in ANY SecureStore instance short-circuits the others, and a
  // per-call timeout caps even that first probe.
  static bool _linuxKeyringDown = false;
  static const Duration _keyringTimeout = Duration(seconds: 5);

  // ── Why the timeout above cannot save us, and what does ────────────────────
  //
  // `flutter_secure_storage_linux` calls libsecret SYNCHRONOUSLY
  // (`secret_service_get_sync`, `secret_password_lookupv_sync`) inside its
  // platform-channel handler. On the Flutter Linux embedder that handler runs
  // on the same thread that drives the Dart event loop, so the call freezes
  // timers, rendering and every `await` in the process — `.timeout()` included,
  // because the timer that would fire it needs exactly the blocked thread.
  //
  // Measured on an xrdp/XFCE session: 25.0 s per call, the D-Bus service
  // activation timeout, because `org.freedesktop.secrets` was only
  // *activatable* on that session bus and never actually started. Five secret
  // reads at startup (logger, tokens, device key/id, cloud DEK) therefore cost
  // ~115 s of frozen UI, and the window painted a stale, wrongly-sized frame
  // when it finally came back.
  //
  // The guard has to run BEFORE the plugin is entered, and must itself be
  // unable to block the platform thread — hence a pure-Dart D-Bus probe over
  // the package's own socket. One probe per process, shared by every caller,
  // so N concurrent readers can no longer queue N blocking calls behind each
  // other (that overlap is why `_linuxKeyringDown` alone never caught this).
  static const String _secretsService = 'org.freedesktop.secrets';
  static const Duration _probeTimeout = Duration(seconds: 3);
  static Future<bool>? _keyringProbe;

  Future<bool> _keyringUsable() => _keyringProbe ??= _probeKeyring();

  Future<bool> _probeKeyring() async {
    if (!Platform.isLinux) return true;
    DBusClient? client;
    try {
      // Resolves DBUS_SESSION_BUS_ADDRESS exactly like GDBus does inside
      // libsecret, so we probe the bus the plugin would actually talk to — a
      // split session (systemd bus vs. the session's own dbus-launch bus) is
      // precisely the case this guard exists for.
      client = DBusClient.session();
      if (await client.nameHasOwner(_secretsService).timeout(_probeTimeout)) {
        return true;
      }
      // Nobody owns the name. It may still be activatable and start quickly on
      // a healthy desktop, so ask the bus to start it — but from Dart, where a
      // bus that never answers costs us `_probeTimeout` and not the UI.
      await client.startServiceByName(_secretsService).timeout(_probeTimeout);
      if (await client.nameHasOwner(_secretsService).timeout(_probeTimeout)) {
        return true;
      }
      _markKeyringDown('no owner for $_secretsService on the session bus');
      return false;
    } catch (e) {
      _markKeyringDown('secrets service unreachable: $e');
      return false;
    } finally {
      try {
        await client?.close();
      } catch (_) {}
    }
  }

  SecretKey? _cachedKey;
  bool _warnedFallbackOnce = false;
  bool _warnedFatalOnce = false;

  // ── Public API (mirrors FlutterSecureStorage) ──────────────────────────────

  Future<String?> read({required String key}) async {
    if (!Platform.isLinux) {
      // Untouched on every non-Linux platform — including the exceptions the
      // caller's own catch blocks rely on.
      return _storage.read(key: key);
    }

    // 1) Encrypted fallback file FIRST. On Linux this file is the source of
    //    truth — write() mirrors every secret into it — so whatever the keyring
    //    holds is here as well. Reading it first keeps the keyring, and its
    //    platform-thread-blocking sync calls, off the startup path completely.
    try {
      final map = await _synchronized(_readFileMap);
      final v = map[key];
      if (v != null) return v;
    } catch (e) {
      _log.warning('Encrypted fallback read failed for "$key": $e',
          tag: 'SECSTORE');
    }

    // 2) Legacy plaintext SharedPreferences left by older builds → migrate in.
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(key);
      if (legacy != null && legacy.isNotEmpty) {
        _log.info(
            'Migrating "$key" from legacy SharedPreferences → encrypted fallback',
            tag: 'SECSTORE');
        await write(key: key, value: legacy);
        await prefs.remove(key); // drop the plaintext copy
        return legacy;
      }
    } catch (_) {}

    // 3) Only now the keyring, and only if it is actually reachable: the value
    //    can still live there alone if a build older than this class wrote it.
    //    A hit is mirrored into the encrypted file so no later read needs the
    //    keyring again.
    if (!_linuxKeyringDown && await _keyringUsable()) {
      try {
        final viaKeyring =
            await _storage.read(key: key).timeout(_keyringTimeout);
        if (viaKeyring != null) {
          try {
            await write(key: key, value: viaKeyring);
          } catch (_) {}
          return viaKeyring;
        }
      } catch (e) {
        _markKeyringDown(e);
      }
    }

    return null;
  }

  Future<void> write({required String key, required String value}) async {
    if (!Platform.isLinux) {
      return _storage.write(key: key, value: value);
    }

    // The encrypted file is the source of truth on Linux, so it is written
    // FIRST: read() consults it first, and a process that dies between the two
    // writes must not leave the file behind the keyring.
    await _synchronized(() async {
      final map = await _readFileMap();
      map[key] = value;
      await _writeFileMap(map);
    });

    // Best-effort keyring mirror, kept in sync for the day it works again —
    // and skipped entirely while no secret service answers, because that call
    // blocks the platform thread for its full D-Bus timeout.
    if (!_linuxKeyringDown && await _keyringUsable()) {
      try {
        await _storage.write(key: key, value: value).timeout(_keyringTimeout);
      } catch (e) {
        _markKeyringDown(e);
      }
    }
  }

  Future<void> delete({required String key}) async {
    if (!Platform.isLinux) {
      return _storage.delete(key: key);
    }
    if (!_linuxKeyringDown && await _keyringUsable()) {
      try {
        await _storage.delete(key: key).timeout(_keyringTimeout);
      } catch (e) {
        _markKeyringDown(e);
      }
    }
    await _synchronized(() async {
      final map = await _readFileMap();
      if (map.remove(key) != null) {
        await _writeFileMap(map);
      }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  // ── Linux encrypted-file fallback internals ────────────────────────────────

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final prev = _ioGate;
    _ioGate = completer.future.then((_) {}, onError: (_) {});
    prev.whenComplete(() async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<File> _fallbackFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fallbackFileName');
  }

  Future<Map<String, String>> _readFileMap() async {
    final file = await _fallbackFile();
    if (!await file.exists()) return <String, String>{};
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return <String, String>{};
      final key = await _deriveKey();
      final plain = await CloudCrypto.decryptBytes(
          Uint8List.fromList(bytes), key);
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (e) {
      // Corrupt / wrong key (e.g. machine-id changed) → treat as empty so the
      // caller falls through to re-activation rather than crashing.
      _log.warning('Encrypted fallback unreadable, ignoring: $e',
          tag: 'SECSTORE');
    }
    return <String, String>{};
  }

  Future<void> _writeFileMap(Map<String, String> map) async {
    try {
      final file = await _fallbackFile();
      final key = await _deriveKey();
      final container = await CloudCrypto.encryptBytes(
          Uint8List.fromList(utf8.encode(jsonEncode(map))), key);
      // Write + rename for a torn-write-safe replace.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(container, flush: true);
      await tmp.rename(file.path);
      // Best-effort tighten permissions (owner-only). Home is usually already
      // encrypted; this is defence in depth.
      try {
        await Process.run('chmod', ['600', file.path]);
      } catch (_) {}
    } catch (e) {
      // Even the fallback failed (app dir not writable, machine-id + key file
      // both unavailable). Surface it ONCE — no loop, no silent loss — the
      // value stays in memory for this session only.
      if (!_warnedFatalOnce) {
        _warnedFatalOnce = true;
        _log.error(
            'Secure storage unavailable (keyring locked AND encrypted fallback '
            'failed): $e — activation may be requested again next launch',
            tag: 'SECSTORE');
      }
      rethrow;
    }
  }

  /// AES-256 key material bound to this machine. Preferred source is the
  /// machine-id (stable, not stored next to the ciphertext); if that is somehow
  /// unavailable we fall back to a per-install random key file (weakest tier,
  /// documented as such).
  Future<SecretKey> _deriveKey() async {
    if (_cachedKey != null) return _cachedKey!;
    final machineId = await _machineId();
    if (machineId != null && machineId.isNotEmpty) {
      final material = utf8.encode('$_appSecret|$machineId');
      final digest = crypto.sha256.convert(material).bytes; // 32 bytes
      _cachedKey = SecretKey(digest);
      return _cachedKey!;
    }
    // Fallback tier: persisted random key (no machine binding). Reduced
    // security, but still bound to a file only this app can read.
    _cachedKey = SecretKey(await _loadOrCreateRandomKey());
    return _cachedKey!;
  }

  Future<String?> _machineId() async {
    for (final path in const ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
      try {
        final f = File(path);
        if (await f.exists()) {
          final v = (await f.readAsString()).trim();
          if (v.isNotEmpty) return v;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<List<int>> _loadOrCreateRandomKey() async {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/$_randomKeyFileName');
    try {
      if (await f.exists()) {
        final b = await f.readAsBytes();
        if (b.length == 32) return b;
      }
    } catch (_) {}
    final rng = Random.secure();
    final key = Uint8List.fromList(
        List<int>.generate(32, (_) => rng.nextInt(256)));
    try {
      await f.writeAsBytes(key, flush: true);
      try {
        await Process.run('chmod', ['600', f.path]);
      } catch (_) {}
    } catch (_) {}
    return key;
  }

  void _markKeyringDown(Object e) {
    _linuxKeyringDown = true;
    if (_warnedFallbackOnce) return;
    _warnedFallbackOnce = true;
    _log.warning(
        'System keyring unavailable on Linux ($e) — using encrypted-file '
        'fallback for secrets (keyring skipped for the rest of this session)',
        tag: 'SECSTORE');
  }
}
