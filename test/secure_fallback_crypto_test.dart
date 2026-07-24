import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/cloud_crypto_service.dart';

// Validates the container format used by the Linux keyring fallback in
// SecureStore: a JSON map of secrets encrypted under a machine-id-derived key
// via CloudCrypto.encryptBytes / decryptBytes.
void main() {
  SecretKey keyFrom(String machineId) {
    const appSecret = 'ICD360S_Vorsitzer_LinuxKeyringFallback_v1';
    final digest = crypto.sha256.convert(utf8.encode('$appSecret|$machineId')).bytes;
    return SecretKey(digest);
  }

  Future<Uint8List> enc(Map<String, String> m, SecretKey k) =>
      CloudCrypto.encryptBytes(Uint8List.fromList(utf8.encode(jsonEncode(m))), k);

  Future<Map<String, String>> dec(Uint8List c, SecretKey k) async {
    final plain = await CloudCrypto.decryptBytes(c, k);
    final decoded = jsonDecode(utf8.decode(plain)) as Map;
    return decoded.map((a, b) => MapEntry(a.toString(), b.toString()));
  }

  test('secrets round-trip through the encrypted fallback container', () async {
    final key = keyFrom('abc123machineid');
    final secrets = {
      'device_key': 'DK_9f8e7d6c5b4a3210',
      'device_id': 'LNX_deadbeefcafebabe',
      'access_token': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.sig',
      'refresh_token': 'r3fr3sh-t0k3n-value',
    };

    final container = await enc(secrets, key);
    final restored = await dec(container, key);

    expect(restored, equals(secrets));
  });

  test('a different machine-id cannot decrypt the container', () async {
    final container = await enc({'device_key': 'DK_secret'}, keyFrom('machine-A'));

    // Wrong machine → GCM auth tag fails → decrypt throws (data stays private).
    await expectLater(
      dec(container, keyFrom('machine-B')),
      throwsA(isA<CloudCryptoException>()),
    );
  });

  test('ciphertext is randomised per write (fresh nonce/salt)', () async {
    final key = keyFrom('same-machine');
    final a = await enc({'device_key': 'DK_x'}, key);
    final b = await enc({'device_key': 'DK_x'}, key);

    // Same plaintext + same key must NOT yield identical bytes.
    expect(a, isNot(equals(b)));
    // ...yet both decrypt back to the same value.
    expect(await dec(a, key), equals(await dec(b, key)));
  });
}
