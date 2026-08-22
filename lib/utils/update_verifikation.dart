/// Prüft, dass ein Update wirklich von uns stammt — bevor es installiert wird.
///
/// Bisher gab es dazu nichts: `update_service.dart` lud den in
/// `version_vorsitzer.json` genannten URL herunter und führte das Ergebnis aus
/// (Windows: PowerShell über dem Anwendungsverzeichnis, Linux: `chmod +x` und
/// starten, macOS: DMG nach /Applications). Weder Prüfsumme noch Signatur.
///
/// **Warum eine Signatur und nicht nur eine Prüfsumme.** Manifest und Artefakt
/// liegen in derselben GitHub-Release. Wer das eine austauschen kann, tauscht
/// das andere gleich mit — die Prüfsumme passte dann perfekt zur gefälschten
/// Datei. Eine Prüfsumme beantwortet „ist die Datei heil angekommen", eine
/// Signatur beantwortet „stammt sie von uns". Nur die zweite Frage schützt
/// gegen ein durchgesickertes Token mit Schreibrecht auf die Release.
///
/// Der private Schlüssel liegt als Repo-Secret und wird nur im Release-Lauf
/// benutzt; der öffentliche steht unten im Klartext — er ist öffentlich, und
/// im Quelltext ist er nachlesbar und mitversioniert.
///
/// ⚠️ **Grenze, ausdrücklich:** wer den CI-Lauf vollständig übernimmt, kommt
/// auch an das Secret und kann gültig signieren. Dagegen hülfe nur ein
/// Schlüssel außerhalb von GitHub, der jede Veröffentlichung von Hand
/// unterschreibt — bei Auto-Bump auf jedem Push nach `main` (Stand: Build 1704)
/// wäre das ein manueller Schritt pro Release. Bewusst nicht gewählt.
///
/// Dasselbe Verfahren benutzen Sparkle (macOS) und der Tauri-Updater: Ed25519,
/// öffentlicher Schlüssel in der Anwendung, privater außerhalb der Auslieferung.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// Öffentlicher Ed25519-Schlüssel (32 Byte, base64) für Update-Manifeste.
///
/// Gegenstück zum Repo-Secret `UPDATE_SIGNING_KEY`. Wird der Schlüssel je
/// gewechselt, muss ERST eine Fassung mit dem neuen öffentlichen Schlüssel
/// draußen sein, bevor damit signiert wird — sonst lehnt jede installierte
/// Fassung das nächste Update ab und niemand bekommt die Reparatur.
const String updatePublicKeyBase64 = 'DyaYyF38Dr/Fh7nJ7fxDAdtPsdj8z3tIX1cjvsiYNBw=';

/// Warum ein Update abgelehnt wurde.
enum UpdateAblehnung {
  /// Das Manifest trug keine Signatur (Feld/Asset fehlt).
  signaturFehlt,

  /// Die Signatur passt nicht zum Manifest.
  signaturFalsch,

  /// Das Manifest nennt für diese Plattform keine Prüfsumme.
  pruefsummeFehlt,

  /// Die heruntergeladene Datei hat eine andere Prüfsumme als angekündigt.
  pruefsummeFalsch,
}

extension UpdateAblehnungText on UpdateAblehnung {
  /// Für die Anzeige. Nennt den Grund, statt das Update wortlos ausfallen zu
  /// lassen — ein ausbleibendes Update sieht sonst aus wie „es gibt keins".
  String get text => switch (this) {
        UpdateAblehnung.signaturFehlt =>
          'Update abgelehnt: Es trägt keine Signatur.',
        UpdateAblehnung.signaturFalsch =>
          'Update abgelehnt: Die Signatur stimmt nicht. '
              'Die Datei stammt nicht von uns.',
        UpdateAblehnung.pruefsummeFehlt =>
          'Update abgelehnt: Für diese Plattform ist keine Prüfsumme angegeben.',
        UpdateAblehnung.pruefsummeFalsch =>
          'Update abgelehnt: Die heruntergeladene Datei weicht von der '
              'angekündigten ab.',
      };
}

/// Prüft die Ed25519-Signatur über die **rohen Bytes** des Manifests.
///
/// ⚠️ [manifestBytes] muss byteweise das sein, was vom Netz kam — nicht ein
/// neu serialisiertes JSON. Signiert wurde die Datei, nicht ihr Inhalt: schon
/// eine andere Einrückung oder Schlüsselreihenfolge macht die Signatur ungültig,
/// und ein `jsonDecode`/`jsonEncode` dazwischen ändert beides gern.
Future<bool> manifestSignaturGueltig(
  List<int> manifestBytes,
  String? signaturBase64, {
  String publicKeyBase64 = updatePublicKeyBase64,
}) async {
  if (signaturBase64 == null || signaturBase64.trim().isEmpty) return false;

  Uint8List sig;
  Uint8List pub;
  try {
    sig = base64.decode(signaturBase64.trim());
    pub = base64.decode(publicKeyBase64.trim());
  } on FormatException {
    return false;
  }
  // Ed25519: Signatur 64 Byte, öffentlicher Schlüssel 32 Byte. Früh und
  // ausdrücklich geprüft, damit eine verstümmelte Eingabe nicht erst tief in
  // der Bibliothek auffällt.
  if (sig.length != 64 || pub.length != 32) return false;

  try {
    return await Ed25519().verify(
      manifestBytes,
      signature: Signature(
        sig,
        publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519),
      ),
    );
  } catch (_) {
    return false;
  }
}

/// SHA-256 einer Datei als Kleinbuchstaben-Hex.
String sha256Hex(List<int> bytes) =>
    crypto.sha256.convert(bytes).toString();

/// Vergleicht zwei Prüfsummen unabhängig von Schreibweise und `sha256:`-Präfix.
///
/// Die GitHub-API liefert `sha256:027825bb…`, von Hand geschriebene Manifeste
/// oft nur den nackten Hex-Wert. Beide sollen passen.
///
/// ⚠️ Der Vergleich läuft in **konstanter Zeit**. Hier ginge auch `==`, weil
/// beide Seiten öffentlich sind — aber diese Funktion ist genau die, die
/// später jemand für einen echten Geheimnisvergleich wiederverwendet.
bool pruefsummeStimmt(String? erwartet, String tatsaechlich) {
  if (erwartet == null) return false;
  final a = erwartet.trim().toLowerCase().replaceFirst('sha256:', '');
  final b = tatsaechlich.trim().toLowerCase().replaceFirst('sha256:', '');
  if (a.isEmpty || a.length != b.length) return false;
  var unterschied = 0;
  for (var i = 0; i < a.length; i++) {
    unterschied |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return unterschied == 0;
}

/// Schlüssel der Prüfsumme im Manifest, je Plattform.
String pruefsummenSchluessel(String plattform) => switch (plattform) {
      'android' => 'sha256_android',
      'macos' => 'sha256_macos',
      'windows' => 'sha256_windows',
      _ => 'sha256',
    };
