import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';
import 'cloud_crypto_service.dart';

// ─── Admin Secure Cloud — session orchestration ─────────────────────────────
//
// Holds the unlocked DEK in memory ONLY (never persisted). Every file is
// encrypted before it leaves the device and decrypted only after download; the
// server sees opaque ciphertext and an unreadable wrapped-key envelope. File
// names / mime / original size are themselves encrypted (meta_enc).

/// One decrypted cloud entry for the UI.
class CloudFile {
  final int id;
  final String name; // decrypted display name
  final String? mime; // decrypted
  final int plainSize; // decrypted original size (bytes)
  final int blobSize; // ciphertext size on disk (quota unit)
  final String source; // 'device' | 'scan'
  final DateTime createdAt;
  final bool readable; // false when meta_enc could not be decrypted

  CloudFile({
    required this.id,
    required this.name,
    required this.mime,
    required this.plainSize,
    required this.blobSize,
    required this.source,
    required this.createdAt,
    this.readable = true,
  });
}

class CloudListing {
  final List<CloudFile> files;
  final int quotaUsed;
  final int quotaTotal;
  CloudListing({required this.files, required this.quotaUsed, required this.quotaTotal});
}

class SecureCloudService {
  final ApiService _api;
  final String mitgliedernummer;
  SecretKey? _dek; // in-memory only; null when locked

  SecureCloudService(this._api, this.mitgliedernummer);

  bool get isUnlocked => _dek != null;

  /// Wipe the in-memory key. Call when leaving the screen / on inactivity.
  void lock() => _dek = null;

  /// true = cloud exists (unlock), false = not set up (setup), null = network error.
  Future<bool?> hasCloud() async {
    final r = await _api.getCloudKeyEnvelope(mitgliedernummer);
    if (r['success'] != true) return null;
    return r['has_key'] == true;
  }

  /// First-time setup: generate a DEK, wrap under [passphrase], store the
  /// envelope. On success the session is unlocked. Returns null on success,
  /// otherwise a human-readable error.
  Future<String?> setup(String passphrase) async {
    final check = CloudPassphrasePolicy.check(passphrase);
    if (!check.ok) return check.issues.join('\n');
    try {
      final created = await CloudCrypto.createEnvelope(passphrase);
      final r = await _api.setCloudKeyEnvelope(
          mitgliedernummer, created.envelope.toJsonString());
      if (r['success'] != true) {
        return r['message']?.toString() ?? 'Einrichtung fehlgeschlagen';
      }
      _dek = created.dek;
      return null;
    } catch (e) {
      return 'Einrichtung fehlgeschlagen: $e';
    }
  }

  /// Unlock an existing cloud. Returns null on success, else an error.
  Future<String?> unlock(String passphrase) async {
    final r = await _api.getCloudKeyEnvelope(mitgliedernummer);
    if (r['success'] != true) return r['message']?.toString() ?? 'Netzwerkfehler';
    if (r['has_key'] != true) return 'Cloud noch nicht eingerichtet';
    try {
      final env = CloudKeyEnvelope.fromJsonString(r['envelope'] as String);
      _dek = await CloudCrypto.unlock(env, passphrase);
      return null;
    } on CloudCryptoException catch (e) {
      return e.message; // 'Falsche Passphrase'
    } catch (e) {
      return 'Entsperren fehlgeschlagen';
    }
  }

  /// Change the passphrase (re-wrap the SAME DEK). Requires an unlocked session.
  Future<String?> changePassphrase(String newPassphrase) async {
    final dek = _dek;
    if (dek == null) return 'Zuerst entsperren';
    final check = CloudPassphrasePolicy.check(newPassphrase);
    if (!check.ok) return check.issues.join('\n');
    try {
      final env = await CloudCrypto.rewrap(dek, newPassphrase);
      final r = await _api.rewrapCloudKeyEnvelope(
          mitgliedernummer, env.toJsonString());
      if (r['success'] != true) {
        return r['message']?.toString() ?? 'Änderung fehlgeschlagen';
      }
      return null;
    } catch (e) {
      return 'Änderung fehlgeschlagen: $e';
    }
  }

  /// List files + decrypt their metadata. Requires unlocked. null on error.
  Future<CloudListing?> list() async {
    final dek = _dek;
    if (dek == null) return null;
    final r = await _api.listAdminCloud(mitgliedernummer);
    if (r['success'] != true) return null;

    final raw = (r['files'] as List?) ?? const [];
    final files = <CloudFile>[];
    for (final entry in raw) {
      final m = (entry as Map).cast<String, dynamic>();
      final blobSize = (m['size'] as num?)?.toInt() ?? 0;
      String name = 'Datei';
      String? mime;
      int plainSize = blobSize;
      bool readable = true;
      try {
        final metaBytes =
            await CloudCrypto.decryptBytes(base64.decode(m['meta_enc'] as String), dek);
        final meta = (jsonDecode(utf8.decode(metaBytes)) as Map).cast<String, dynamic>();
        name = (meta['name'] ?? 'Datei').toString();
        mime = meta['mime']?.toString();
        plainSize = (meta['plain_size'] as num?)?.toInt() ?? blobSize;
      } catch (_) {
        name = '⚠︎ Nicht lesbar';
        readable = false;
      }
      files.add(CloudFile(
        id: (m['id'] as num).toInt(),
        name: name,
        mime: mime,
        plainSize: plainSize,
        blobSize: blobSize,
        source: (m['source'] ?? 'device').toString(),
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
        readable: readable,
      ));
    }
    return CloudListing(
      files: files,
      quotaUsed: (r['quota_used'] as num?)?.toInt() ?? 0,
      quotaTotal: (r['quota_total'] as num?)?.toInt() ?? 0,
    );
  }

  /// Encrypt [plain] and upload it. Returns null on success, else an error.
  Future<String?> uploadFile({
    required File plain,
    required String displayName,
    String? mime,
    String source = 'device',
  }) async {
    final dek = _dek;
    if (dek == null) return 'Zuerst entsperren';
    final plainSize = await plain.length();
    final tmpDir = await getTemporaryDirectory();
    final encFile = File(
        '${tmpDir.path}/cloud_up_${DateTime.now().microsecondsSinceEpoch}.enc');
    try {
      await CloudCrypto.encryptFile(plain, encFile, dek);
      final metaJson = jsonEncode({
        'name': displayName,
        'mime': mime,
        'plain_size': plainSize,
      });
      final metaEnc = base64.encode(
          await CloudCrypto.encryptBytes(Uint8List.fromList(utf8.encode(metaJson)), dek));
      final r = await _api.uploadAdminCloudFile(
        mitgliedernummer: mitgliedernummer,
        encryptedFile: encFile,
        metaEnc: metaEnc,
        source: source,
      );
      if (r['success'] != true) {
        return r['message']?.toString() ?? 'Upload fehlgeschlagen';
      }
      return null;
    } catch (e) {
      return 'Upload fehlgeschlagen: $e';
    } finally {
      if (await encFile.exists()) {
        try {
          await encFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Download [file] and decrypt it entirely IN MEMORY (RAM) — the plaintext is
  /// NEVER written to disk. Use this for in-app preview so decrypted content
  /// stays off persistent storage (zero-knowledge). Returns bytes or null.
  Future<Uint8List?> downloadToMemory(CloudFile file) async {
    final dek = _dek;
    if (dek == null) return null;
    final blob = await _api.downloadAdminCloudBlob(
        mitgliedernummer: mitgliedernummer, cloudFileId: file.id);
    if (blob == null) return null;
    try {
      return await CloudCrypto.decryptBytes(blob, dek);
    } catch (_) {
      return null;
    }
  }

  /// Download [file], decrypt, and write the plaintext to a temp file the caller
  /// can open/share/export. Writes plaintext to disk — use only for explicit
  /// "save/export"; prefer [downloadToMemory] for viewing.
  Future<File?> downloadToTemp(CloudFile file) async {
    final dek = _dek;
    if (dek == null) return null;
    final blob = await _api.downloadAdminCloudBlob(
        mitgliedernummer: mitgliedernummer, cloudFileId: file.id);
    if (blob == null) return null;
    final tmpDir = await getTemporaryDirectory();
    final encFile = File('${tmpDir.path}/cloud_dl_${file.id}.enc');
    final outFile = File('${tmpDir.path}/${_safeName(file.name)}');
    try {
      await encFile.writeAsBytes(blob);
      await CloudCrypto.decryptFile(encFile, outFile, dek);
      return outFile;
    } catch (_) {
      return null;
    } finally {
      if (await encFile.exists()) {
        try {
          await encFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Delete a file. Returns null on success, else an error.
  Future<String?> delete(int cloudFileId) async {
    final r = await _api.deleteAdminCloudFile(
        mitgliedernummer: mitgliedernummer, cloudFileId: cloudFileId);
    if (r['success'] != true) {
      return r['message']?.toString() ?? 'Löschen fehlgeschlagen';
    }
    return null;
  }

  String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^\w\.\- ]'), '_').trim();
    return cleaned.isEmpty ? 'datei' : cleaned;
  }
}
