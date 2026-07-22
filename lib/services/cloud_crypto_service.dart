import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

// ─── Admin Secure Cloud — client-side zero-knowledge crypto ─────────────────
//
// The server NEVER sees plaintext files nor the data key. It stores only opaque
// ciphertext blobs plus a wrapped (encrypted) copy of the data key.
//
// Key hierarchy (envelope / DEK–KEK):
//   DEK  256-bit random Data Encryption Key. Encrypts every file
//        (per-file subkey via HKDF, chunked AES-256-GCM with counter nonces).
//   KEK  derived from the user's recovery passphrase via PBKDF2-HMAC-SHA256.
//   wrapped_DEK = AES-256-GCM(DEK) under KEK. Stored on the server. Useless
//        without the passphrase → the server remains zero-knowledge.
//
// The DEK lives ONLY in RAM while the cloud is unlocked. It is never persisted
// on the device and never leaves the device in plaintext. The passphrase is
// requested on every open (see CloudPassphrasePolicy for the strength gate).
//
// The wrapped-DEK envelope is self-describing (records its own KDF + iteration
// count), so the KDF can be upgraded later (e.g. to Argon2id) without breaking
// existing wraps.

class CloudCryptoException implements Exception {
  final String message;
  CloudCryptoException(this.message);
  @override
  String toString() => 'CloudCryptoException: $message';
}

/// Self-describing wrapped Data-Encryption-Key, stored on the server as JSON.
/// Contains no secret usable without the passphrase.
class CloudKeyEnvelope {
  static const int currentVersion = 1;

  final int version;
  final String kdf; // e.g. 'pbkdf2-hmac-sha256'
  final int iterations; // KDF work factor (stored so it can be tuned/upgraded)
  final Uint8List salt; // KDF salt
  final Uint8List nonce; // GCM nonce used to wrap the DEK
  final Uint8List wrappedDek; // ciphertext(32) || tag(16)

  CloudKeyEnvelope({
    required this.version,
    required this.kdf,
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.wrappedDek,
  });

  Map<String, dynamic> toJson() => {
        'v': version,
        'kdf': kdf,
        'iterations': iterations,
        'salt': base64.encode(salt),
        'nonce': base64.encode(nonce),
        'wrapped_dek': base64.encode(wrappedDek),
      };

  String toJsonString() => jsonEncode(toJson());

  factory CloudKeyEnvelope.fromJson(Map<String, dynamic> j) {
    try {
      return CloudKeyEnvelope(
        version: (j['v'] as num).toInt(),
        kdf: j['kdf'] as String,
        iterations: (j['iterations'] as num).toInt(),
        salt: base64.decode(j['salt'] as String),
        nonce: base64.decode(j['nonce'] as String),
        wrappedDek: base64.decode(j['wrapped_dek'] as String),
      );
    } catch (e) {
      throw CloudCryptoException('Invalid key envelope: $e');
    }
  }

  factory CloudKeyEnvelope.fromJsonString(String s) =>
      CloudKeyEnvelope.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// Stateless crypto primitives for the secure cloud. The unlocked [SecretKey]
/// (the DEK) is held by the caller (in memory only) and passed to the file
/// encrypt/decrypt calls.
class CloudCrypto {
  // KDF — PBKDF2-HMAC-SHA256. Iteration count is stored in the envelope so it
  // can be raised over time (or the whole KDF swapped for Argon2id) without a
  // breaking migration. 310k is a defensible default pending on-device tuning.
  static const String kdfId = 'pbkdf2-hmac-sha256';
  static const int kdfDefaultIterations = 310000;

  // File container: magic(6) | version(1) | fileSalt(16) | noncePrefix(8) |
  // chunkSize(4, big-endian) = 35-byte header, then per-chunk records of
  // ciphertext||tag(16). Plaintext is split into fixed chunkSize blocks; the
  // final block may be shorter. Each chunk uses a 12-byte nonce = noncePrefix
  // || counter(4, big-endian). The per-file HKDF subkey guarantees a fresh key
  // per file, so counter nonces never repeat under the same key.
  static const List<int> _magic = [0x49, 0x43, 0x44, 0x43, 0x4C, 0x44]; // ICDCLD
  static const int _fileFormatVersion = 1;
  static const int _headerLen = 35;
  static const int _tagLen = 16;
  static const int _nonceLen = 12;
  static const int _chunkSize = 4 * 1024 * 1024; // 4 MiB

  static final AesGcm _gcm = AesGcm.with256bits();

  static final Random _rng = Random.secure();

  static Uint8List _randomBytes(int n) {
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = _rng.nextInt(256);
    }
    return b;
  }

  // ── Key envelope: create / unlock / re-wrap ───────────────────────────────

  static Future<SecretKey> _deriveKek(
      String passphrase, Uint8List salt, int iterations) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  static Future<CloudKeyEnvelope> _wrap(
      Uint8List dekBytes, String passphrase) async {
    final salt = _randomBytes(16);
    final kek = await _deriveKek(passphrase, salt, kdfDefaultIterations);
    final nonce = _randomBytes(_nonceLen);
    final box = await _gcm.encrypt(dekBytes, secretKey: kek, nonce: nonce);
    final wrapped = Uint8List(box.cipherText.length + box.mac.bytes.length)
      ..setRange(0, box.cipherText.length, box.cipherText)
      ..setAll(box.cipherText.length, box.mac.bytes);
    return CloudKeyEnvelope(
      version: CloudKeyEnvelope.currentVersion,
      kdf: kdfId,
      iterations: kdfDefaultIterations,
      salt: salt,
      nonce: nonce,
      wrappedDek: wrapped,
    );
  }

  /// First-time setup: generate a fresh random DEK and wrap it under
  /// [passphrase]. Returns the server-storable envelope plus the unlocked DEK
  /// so the session starts already unlocked.
  static Future<({CloudKeyEnvelope envelope, SecretKey dek})> createEnvelope(
      String passphrase) async {
    final dekBytes = _randomBytes(32);
    final env = await _wrap(dekBytes, passphrase);
    return (envelope: env, dek: SecretKey(dekBytes));
  }

  /// Unlock an existing cloud: derive the KEK from [passphrase] and unwrap the
  /// DEK. Throws [CloudCryptoException] on a wrong passphrase (GCM tag fails).
  static Future<SecretKey> unlock(
      CloudKeyEnvelope env, String passphrase) async {
    if (env.wrappedDek.length <= _tagLen) {
      throw CloudCryptoException('Corrupt key envelope');
    }
    final kek = await _deriveKek(passphrase, env.salt, env.iterations);
    final ctLen = env.wrappedDek.length - _tagLen;
    final ct = env.wrappedDek.sublist(0, ctLen);
    final tag = env.wrappedDek.sublist(ctLen);
    try {
      final dekBytes = await _gcm.decrypt(
        SecretBox(ct, nonce: env.nonce, mac: Mac(tag)),
        secretKey: kek,
      );
      return SecretKey(dekBytes);
    } catch (_) {
      // GCM authentication failed → wrong passphrase (or tampered envelope).
      throw CloudCryptoException('Falsche Passphrase');
    }
  }

  /// Change the recovery passphrase: re-wrap the SAME DEK under a new
  /// passphrase. Files are untouched (only the small envelope changes).
  static Future<CloudKeyEnvelope> rewrap(
      SecretKey dek, String newPassphrase) async {
    final dekBytes = Uint8List.fromList(await dek.extractBytes());
    return _wrap(dekBytes, newPassphrase);
  }

  // ── File encryption (chunked, streamed to/from disk) ──────────────────────

  static Future<SecretKey> _deriveFileKey(
      SecretKey dek, Uint8List fileSalt) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: dek,
      nonce: fileSalt,
      info: utf8.encode('icd360s-cloud-file-v1'),
    );
  }

  static Uint8List _nonceFor(Uint8List prefix8, int counter) {
    final n = Uint8List(_nonceLen);
    n.setRange(0, 8, prefix8);
    ByteData.sublistView(n).setUint32(8, counter, Endian.big);
    return n;
  }

  static Uint8List _buildHeader(Uint8List fileSalt, Uint8List noncePrefix) {
    final h = BytesBuilder();
    h.add(_magic);
    h.addByte(_fileFormatVersion);
    h.add(fileSalt);
    h.add(noncePrefix);
    final cs = ByteData(4)..setUint32(0, _chunkSize, Endian.big);
    h.add(cs.buffer.asUint8List());
    return h.toBytes();
  }

  /// Read exactly [count] bytes, or fewer only at EOF. Shields the chunking
  /// logic from RandomAccessFile.read's "up to count" semantics.
  static Future<Uint8List> _readExactly(RandomAccessFile raf, int count) async {
    final buf = Uint8List(count);
    var got = 0;
    while (got < count) {
      final part = await raf.read(count - got);
      if (part.isEmpty) break; // EOF
      buf.setRange(got, got + part.length, part);
      got += part.length;
    }
    return got == count ? buf : Uint8List.sublistView(buf, 0, got);
  }

  /// Encrypt [plain] into [out] using the unlocked [dek]. Streams in 4 MiB
  /// chunks, so arbitrarily large files use bounded memory.
  static Future<void> encryptFile(File plain, File out, SecretKey dek) async {
    final fileSalt = _randomBytes(16);
    final noncePrefix = _randomBytes(8);
    final fileKey = await _deriveFileKey(dek, fileSalt);
    final rin = await plain.open();
    final rout = await out.open(mode: FileMode.write);
    try {
      await rout.writeFrom(_buildHeader(fileSalt, noncePrefix));
      var counter = 0;
      while (true) {
        final chunk = await _readExactly(rin, _chunkSize);
        if (chunk.isEmpty) break;
        final box = await _gcm.encrypt(chunk,
            secretKey: fileKey, nonce: _nonceFor(noncePrefix, counter));
        await rout.writeFrom(box.cipherText);
        await rout.writeFrom(box.mac.bytes);
        counter++;
        if (chunk.length < _chunkSize) break; // final (short) chunk
      }
    } finally {
      await rin.close();
      await rout.close();
    }
  }

  /// Decrypt [enc] (produced by [encryptFile]/[encryptBytes]) into [out] using
  /// [dek]. Throws [CloudCryptoException] on a wrong key or tampered data.
  static Future<void> decryptFile(File enc, File out, SecretKey dek) async {
    final rin = await enc.open();
    final rout = await out.open(mode: FileMode.write);
    try {
      final head = await _readExactly(rin, _headerLen);
      final parsed = _parseHeader(head);
      final fileKey = await _deriveFileKey(dek, parsed.fileSalt);
      final recordLen = parsed.chunkSize + _tagLen;
      var counter = 0;
      while (true) {
        final rec = await _readExactly(rin, recordLen);
        if (rec.isEmpty) break;
        if (rec.length < _tagLen) {
          throw CloudCryptoException('Corrupt file (truncated record)');
        }
        final plain = await _decryptRecord(rec, fileKey, parsed.noncePrefix, counter);
        await rout.writeFrom(plain);
        counter++;
        if (rec.length < recordLen) break; // final (short) chunk
      }
    } finally {
      await rin.close();
      await rout.close();
    }
  }

  // ── In-memory variants (for small blobs, e.g. scanned photos) ──────────────

  /// Encrypt [plain] bytes into a self-contained container (same format as
  /// [encryptFile]). Suitable for small/medium blobs held in memory.
  static Future<Uint8List> encryptBytes(Uint8List plain, SecretKey dek) async {
    final fileSalt = _randomBytes(16);
    final noncePrefix = _randomBytes(8);
    final fileKey = await _deriveFileKey(dek, fileSalt);
    final out = BytesBuilder();
    out.add(_buildHeader(fileSalt, noncePrefix));
    var counter = 0;
    var offset = 0;
    if (plain.isEmpty) {
      // Encrypt a single empty chunk so the container round-trips to empty.
      final box = await _gcm.encrypt(const <int>[],
          secretKey: fileKey, nonce: _nonceFor(noncePrefix, 0));
      out.add(box.cipherText);
      out.add(box.mac.bytes);
      return out.toBytes();
    }
    while (offset < plain.length) {
      final end = (offset + _chunkSize < plain.length)
          ? offset + _chunkSize
          : plain.length;
      final chunk = plain.sublist(offset, end);
      final box = await _gcm.encrypt(chunk,
          secretKey: fileKey, nonce: _nonceFor(noncePrefix, counter));
      out.add(box.cipherText);
      out.add(box.mac.bytes);
      counter++;
      offset = end;
    }
    return out.toBytes();
  }

  /// Decrypt a container produced by [encryptBytes]/[encryptFile].
  static Future<Uint8List> decryptBytes(
      Uint8List container, SecretKey dek) async {
    if (container.length < _headerLen) {
      throw CloudCryptoException('Corrupt file (header)');
    }
    final parsed = _parseHeader(container.sublist(0, _headerLen));
    final fileKey = await _deriveFileKey(dek, parsed.fileSalt);
    final recordLen = parsed.chunkSize + _tagLen;
    final out = BytesBuilder();
    var counter = 0;
    var offset = _headerLen;
    while (offset < container.length) {
      final end = (offset + recordLen < container.length)
          ? offset + recordLen
          : container.length;
      final rec = container.sublist(offset, end);
      if (rec.length < _tagLen) {
        throw CloudCryptoException('Corrupt file (truncated record)');
      }
      final plain = await _decryptRecord(rec, fileKey, parsed.noncePrefix, counter);
      out.add(plain);
      counter++;
      offset = end;
    }
    return out.toBytes();
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  static ({Uint8List fileSalt, Uint8List noncePrefix, int chunkSize})
      _parseHeader(Uint8List head) {
    if (head.length < _headerLen) {
      throw CloudCryptoException('Corrupt file (header too short)');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (head[i] != _magic[i]) {
        throw CloudCryptoException('Not a cloud container (bad magic)');
      }
    }
    final ver = head[6];
    if (ver != _fileFormatVersion) {
      throw CloudCryptoException('Unsupported container version $ver');
    }
    final fileSalt = Uint8List.fromList(head.sublist(7, 23));
    final noncePrefix = Uint8List.fromList(head.sublist(23, 31));
    final chunkSize =
        ByteData.sublistView(head, 31, 35).getUint32(0, Endian.big);
    if (chunkSize <= 0 || chunkSize > 64 * 1024 * 1024) {
      throw CloudCryptoException('Corrupt file (bad chunk size)');
    }
    return (fileSalt: fileSalt, noncePrefix: noncePrefix, chunkSize: chunkSize);
  }

  static Future<Uint8List> _decryptRecord(
      Uint8List rec, SecretKey fileKey, Uint8List noncePrefix, int counter) async {
    final ctLen = rec.length - _tagLen;
    final ct = rec.sublist(0, ctLen);
    final tag = rec.sublist(ctLen);
    try {
      final plain = await _gcm.decrypt(
        SecretBox(ct, nonce: _nonceFor(noncePrefix, counter), mac: Mac(tag)),
        secretKey: fileKey,
      );
      return Uint8List.fromList(plain);
    } catch (_) {
      throw CloudCryptoException(
          'Decryption failed (wrong key or file was tampered with)');
    }
  }
}

/// Result of a passphrase strength check.
class PassphraseCheck {
  final bool ok;
  final double entropyBits;
  final List<String> issues; // human-readable, empty when ok

  PassphraseCheck({
    required this.ok,
    required this.entropyBits,
    required this.issues,
  });

  /// 0..1 for a strength meter (0 = unusable, 1 = very strong ≥ 100 bits).
  double get meter => (entropyBits / 100.0).clamp(0.0, 1.0);
}

/// Recovery-passphrase policy. The user chooses their own passphrase (so they
/// remember it), but it must clear a strength floor because the wrapped DEK on
/// the server is offline-attackable if the server is ever breached.
class CloudPassphrasePolicy {
  static const int minLength = 20;
  static const double minEntropyBits = 60;

  static PassphraseCheck check(String p) {
    final issues = <String>[];

    if (p.length < minLength) {
      issues.add('Mindestens $minLength Zeichen (aktuell ${p.length})');
    }
    if (p.trim().isEmpty) {
      issues.add('Darf nicht nur aus Leerzeichen bestehen');
    }
    if (RegExp(r'^(.)\1+$').hasMatch(p)) {
      issues.add('Nicht nur ein wiederholtes Zeichen');
    }
    if (RegExp(r'^\d+$').hasMatch(p)) {
      issues.add('Nicht nur Ziffern verwenden');
    }
    if (_isSequential(p)) {
      issues.add('Keine reine Zeichenfolge (z. B. 12345…/abcde…)');
    }

    final entropy = _estimateEntropyBits(p);
    if (entropy < minEntropyBits) {
      issues.add('Zu schwach – mehr Wörter oder Zeichen verwenden');
    }

    return PassphraseCheck(
      ok: issues.isEmpty,
      entropyBits: entropy,
      issues: issues,
    );
  }

  static bool _isSequential(String p) {
    if (p.length < 4) return false;
    var asc = true, desc = true;
    for (var i = 1; i < p.length; i++) {
      final d = p.codeUnitAt(i) - p.codeUnitAt(i - 1);
      if (d != 1) asc = false;
      if (d != -1) desc = false;
    }
    return asc || desc;
  }

  // Conservative Shannon-style floor: pool size from the character classes
  // present, times length. Rewards length (passphrases), which is exactly what
  // we want. Not a substitute for zxcvbn, but a solid reject gate.
  static double _estimateEntropyBits(String p) {
    if (p.isEmpty) return 0;
    var pool = 0;
    if (RegExp(r'[a-z]').hasMatch(p)) pool += 26;
    if (RegExp(r'[A-Z]').hasMatch(p)) pool += 26;
    if (RegExp(r'[0-9]').hasMatch(p)) pool += 10;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(p)) pool += 32;
    if (pool == 0) pool = 1;
    // Penalise low character variety (e.g. many repeats) by capping effective
    // length at 2× the number of distinct characters.
    final distinct = p.split('').toSet().length;
    final effectiveLen = min(p.length, distinct * 2);
    return effectiveLen * (log(pool) / log(2));
  }
}
