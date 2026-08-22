import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/update_verifikation.dart';

/// Manifest und Signatur stammen aus einem echten Lauf von
/// `openssl pkeyutl -sign -rawin` mit demselben Schlüssel, dessen öffentliche
/// Hälfte in `update_verifikation.dart` steht — also genau der Werkzeugkette,
/// die der Release-Lauf benutzt.
///
/// ⚠️ Das ist der eigentliche Zweck dieser Datei. Ein Test, der in Dart
/// signiert und in Dart prüft, bestätigt nur sich selbst; er würde grün
/// bleiben, während openssl und `package:cryptography` sich uneins sind — und
/// das fiele erst beim Ausliefern auf, wenn kein Gerät mehr ein Update annimmt.
const _manifestB64 =
    'ewogICJzdWNjZXNzIjogdHJ1ZSwKICAidmVyc2lvbiI6ICI2LjEzMy4xIiwKICAiYnVpbGRfbn'
    'VtYmVyIjogMTcwNCwKICAiZG93bmxvYWRfdXJsX2FuZHJvaWQiOiAiaHR0cHM6Ly9naXRodWIu'
    'Y29tL0lDRDM2MFMtZS1WL3ZvcnNpdHplci9yZWxlYXNlcy9kb3dubG9hZC92Ni4xMzMuMS92b3'
    'JzaXR6ZXIuYXBrIiwKICAic2hhMjU2X2FuZHJvaWQiOiAic2hhMjU2OmNjZDdiYzQ2MWE2ZDUx'
    'ZGQ5ZTc4Y2NmNGM1OGZmNDRmMGM1ZmQ4OTQ1ZGU3ZTNlZmFjYjI0NzMzMWU2MDQ5NTQiCn0K';

const _signaturB64 =
    'mBPh6wyRwa/zqqTHsfS9hqHdNapUhIa/OzQr2ErZhows6KXxZfojKFKlt15SB7pqicwIzOj0'
    '3e95lBGIYGm2AA==';

void main() {
  final manifest = base64.decode(_manifestB64);

  group('Signatur — gegen eine echte openssl-Signatur', () {
    test('nimmt die Signatur an, die der Release-Lauf erzeugen wird', () async {
      expect(await manifestSignaturGueltig(manifest, _signaturB64), isTrue);
    });

    test('ein einziges geändertes Byte im Manifest reicht zur Ablehnung',
        () async {
      final verbogen = List<int>.from(manifest);
      verbogen[10] = verbogen[10] ^ 0x01;
      expect(await manifestSignaturGueltig(verbogen, _signaturB64), isFalse);
    });

    test('die eigentliche Angriffsprobe: getauschte Download-Adresse', () async {
      // Genau der Fall, um den es geht — jemand mit Schreibrecht auf die
      // Release biegt den URL auf sein eigenes Artefakt um.
      final boese = utf8.encode(utf8
          .decode(manifest)
          .replaceAll('github.com/ICD360S-e-V', 'github.com/boesewicht'));
      expect(await manifestSignaturGueltig(boese, _signaturB64), isFalse);
    });

    test('eine fremde Signatur wird abgelehnt', () async {
      final fremd = base64.encode(List<int>.filled(64, 7));
      expect(await manifestSignaturGueltig(manifest, fremd), isFalse);
    });

    test('fehlende, leere und unsinnige Signatur', () async {
      expect(await manifestSignaturGueltig(manifest, null), isFalse);
      expect(await manifestSignaturGueltig(manifest, ''), isFalse);
      expect(await manifestSignaturGueltig(manifest, '   '), isFalse);
      expect(await manifestSignaturGueltig(manifest, 'kein base64!!'), isFalse);
    });

    test('falsche Längen fallen früh durch', () async {
      expect(
          await manifestSignaturGueltig(
              manifest, base64.encode(List<int>.filled(63, 1))),
          isFalse);
      expect(
          await manifestSignaturGueltig(manifest, _signaturB64,
              publicKeyBase64: base64.encode(List<int>.filled(31, 1))),
          isFalse);
    });

    test('ein anderer öffentlicher Schlüssel nimmt die Signatur nicht an',
        () async {
      // Ed25519-Schlüssel sind 32 zufällige Byte; irgendeiner davon darf
      // unsere Signatur nicht bestätigen.
      final anderer = base64.encode(List<int>.generate(32, (i) => (i * 7) % 256));
      expect(
          await manifestSignaturGueltig(manifest, _signaturB64,
              publicKeyBase64: anderer),
          isFalse);
    });

    test('der eingebaute öffentliche Schlüssel hat die richtige Länge', () {
      expect(base64.decode(updatePublicKeyBase64).length, 32);
    });
  });

  group('Prüfsumme', () {
    test('rechnet SHA-256 als Kleinbuchstaben-Hex', () {
      // Bekannter Wert: SHA-256 der leeren Eingabe.
      expect(sha256Hex(const []),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('versteht beide Schreibweisen der GitHub-API', () {
      const roh = 'ccd7bc461a6d51dd9e78ccf4c58ff44f0c5fd8945de7e3efacb247331e604954';
      expect(pruefsummeStimmt('sha256:$roh', roh), isTrue);
      expect(pruefsummeStimmt(roh, roh), isTrue);
      expect(pruefsummeStimmt(roh.toUpperCase(), roh), isTrue);
      expect(pruefsummeStimmt('  sha256:$roh  ', roh), isTrue);
    });

    test('lehnt Abweichung, Fehlen und Leere ab', () {
      const roh = 'ccd7bc461a6d51dd9e78ccf4c58ff44f0c5fd8945de7e3efacb247331e604954';
      expect(pruefsummeStimmt(null, roh), isFalse);
      expect(pruefsummeStimmt('', roh), isFalse);
      expect(pruefsummeStimmt('sha256:', roh), isFalse);
      expect(pruefsummeStimmt(roh.replaceFirst('c', 'd'), roh), isFalse);
      expect(pruefsummeStimmt(roh.substring(0, 60), roh), isFalse);
    });
  });

  group('Plattformschlüssel', () {
    test('jede Plattform hat ihren eigenen', () {
      expect(pruefsummenSchluessel('android'), 'sha256_android');
      expect(pruefsummenSchluessel('macos'), 'sha256_macos');
      expect(pruefsummenSchluessel('windows'), 'sha256_windows');
      expect(pruefsummenSchluessel('irgendwas'), 'sha256');
    });
  });

  group('Ablehnungsgründe', () {
    test('jeder Grund sagt etwas Brauchbares', () {
      for (final g in UpdateAblehnung.values) {
        expect(g.text, isNotEmpty);
        expect(g.text, contains('Update abgelehnt'),
            reason: 'der Benutzer muss erfahren, DASS abgelehnt wurde');
      }
    });
  });
}
