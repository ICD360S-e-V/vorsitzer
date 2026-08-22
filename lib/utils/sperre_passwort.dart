/// Passwortablage für die App-Sperre — die reine Rechnerei, ohne Speicher und
/// ohne Oberfläche.
///
/// Getrennt vom Dienst, damit sie prüfbar ist: `SecureStore` braucht
/// Plattformkanäle und läuft in einem gewöhnlichen Test gar nicht erst an. Was
/// hier steht, entscheidet aber darüber, ob ein falsches Passwort abgewiesen
/// wird — das will man belegen können, nicht annehmen.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// PBKDF2-Runden.
///
/// ⚠️ Nicht die 310 000 aus `CloudCrypto`, und das ist Absicht. Gemessen auf
/// dem Entwicklungsrechner: 310 000 → 1329 ms, 120 000 → 503 ms, 60 000 →
/// 245 ms. Auf einem Tablet ist das drei- bis fünfmal so lang; bei 310 000
/// wartete man nach jeder Leerlaufsperre vier bis sechs Sekunden, und das
/// mehrmals täglich.
///
/// Die Abwägung sieht hier anders aus als bei der Cloud-Passphrase: dieser
/// Hash liegt im Schlüsselbund des Geräts. Wer ihn hat, hat das Gerät — dann
/// ist die Sperre ohnehin überwunden. Der Fall, gegen den sie schützt, ist das
/// unbeaufsichtigt liegengelassene, entsperrte Gerät, und dagegen hilft jede
/// Rundenzahl gleich gut.
///
/// Gegen das Durchprobieren steht die Wartestaffel im Dienst — die wirkt an
/// dieser Stelle mehr als eine höhere Rundenzahl.
const int sperreRunden = 120000;

/// Kürzestes zulässiges Passwort.
///
/// Kein Zwang zu Sonderzeichen: der [NIST-Leitfaden SP 800-63B] rät
/// ausdrücklich von Zusammensetzungsregeln ab, weil sie zu `Passwort1!` führen
/// und zu Zetteln am Bildschirmrand. Länge ist das, was zählt.
const int sperreMindestlaenge = 8;

/// Abgelegter Prüfwert eines Passworts.
class SperrePasswort {
  const SperrePasswort({
    required this.salz,
    required this.hash,
    required this.runden,
  });

  final Uint8List salz;
  final Uint8List hash;
  final int runden;

  String alsJson() => jsonEncode({
        'v': 1,
        'salz': base64.encode(salz),
        'hash': base64.encode(hash),
        'runden': runden,
      });

  /// `null`, wenn der Datensatz unbrauchbar ist — dann gilt „kein Passwort
  /// gesetzt", nicht „jedes Passwort passt".
  static SperrePasswort? ausJson(String? roh) {
    if (roh == null || roh.trim().isEmpty) return null;
    try {
      final j = jsonDecode(roh) as Map<String, dynamic>;
      final salz = base64.decode(j['salz'] as String);
      final hash = base64.decode(j['hash'] as String);
      final runden = (j['runden'] as num?)?.toInt() ?? sperreRunden;
      if (salz.isEmpty || hash.isEmpty || runden < 1000) return null;
      return SperrePasswort(
        salz: Uint8List.fromList(salz),
        hash: Uint8List.fromList(hash),
        runden: runden,
      );
    } catch (_) {
      return null;
    }
  }
}

final Random _zufall = Random.secure();

Future<Uint8List> _ableiten(String passwort, Uint8List salz, int runden) async {
  final s = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: runden,
    bits: 256,
  ).deriveKey(
    secretKey: SecretKey(utf8.encode(passwort)),
    nonce: salz,
  );
  return Uint8List.fromList(await s.extractBytes());
}

/// Erzeugt den Prüfwert zu einem neuen Passwort.
Future<SperrePasswort> sperrePasswortErzeugen(String passwort) async {
  final salz =
      Uint8List.fromList(List<int>.generate(16, (_) => _zufall.nextInt(256)));
  return SperrePasswort(
    salz: salz,
    hash: await _ableiten(passwort, salz, sperreRunden),
    runden: sperreRunden,
  );
}

/// Prüft ein eingegebenes Passwort gegen den abgelegten Wert.
///
/// Die Rundenzahl kommt aus dem Datensatz, nicht aus der Konstanten — sonst
/// würden beim nächsten Anheben alle bestehenden Passwörter ungültig, und
/// niemand käme mehr hinein.
Future<bool> sperrePasswortPruefen(
    SperrePasswort? abgelegt, String eingabe) async {
  if (abgelegt == null) return false;
  final hash = await _ableiten(eingabe, abgelegt.salz, abgelegt.runden);
  return _gleichInKonstanterZeit(hash, abgelegt.hash);
}

/// ⚠️ Kein `==` auf Listen: das bricht beim ersten abweichenden Byte ab und
/// verrät über die Laufzeit, wie weit ein Rateversuch gekommen ist.
bool _gleichInKonstanterZeit(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var unterschied = 0;
  for (var i = 0; i < a.length; i++) {
    unterschied |= a[i] ^ b[i];
  }
  return unterschied == 0;
}

/// Wie lange nach [fehlversuche] Fehlversuchen gewartet werden muss.
///
/// Verdopplung ab dem fünften Versuch, gedeckelt bei fünf Minuten. Das ist der
/// eigentliche Schutz gegen Durchprobieren — wirksamer als eine höhere
/// Rundenzahl, und es kostet den rechtmäßigen Benutzer nichts, weil er beim
/// ersten oder zweiten Versuch hineinkommt.
Duration sperreWartezeit(int fehlversuche) {
  if (fehlversuche < 5) return Duration.zero;
  final stufe = fehlversuche - 4;              // 1, 2, 3, …
  final sekunden = min(300, 5 * (1 << (stufe - 1).clamp(0, 6)));
  return Duration(seconds: sekunden);
}
