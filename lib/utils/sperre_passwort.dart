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
/// und zu Zetteln am Bildschirmrand. Länge ist das, was zählt — und SP
/// 800-63B-4 empfiehlt für einen EINZIGEN Faktor (das ist die App-Sperre)
/// 15 Zeichen. Bestehende kürzere Passwörter bleiben gültig; nur NEUE müssen
/// diese Länge erfüllen ([sperrePasswortPruefen] prüft die Länge nicht).
const int sperreMindestlaenge = 15;

/// Prüft ein NEU gewähltes Sperr-Passwort und gibt einen deutschen Grund
/// zurück, wenn es zu schwach ist — sonst `null`.
///
/// NIST SP 800-63B-4 verlangt (SHALL), neue Passwörter gegen eine Liste
/// häufiger/kompromittierter Werte zu prüfen. Ein vollständiges Leak-Korpus
/// lässt sich in einer Offline-App nicht mitliefern; diese Prüfung deckt das
/// Erwartbare ab: zu kurz, zu wenig Abwechslung, reine Zeichenfolge, oder ein
/// bekannt-schwaches Wort, das (fast) das ganze Passwort ausmacht. Bewusst
/// KEINE Zeichenklassen-Zwänge — die rät NIST ausdrücklich ab.
String? sperrePasswortProblem(String passwort) {
  if (passwort.length < sperreMindestlaenge) {
    return 'Mindestens $sperreMindestlaenge Zeichen.';
  }
  final klein = passwort.toLowerCase();
  if (klein.split('').toSet().length < 5) {
    return 'Zu wenig verschiedene Zeichen — bitte abwechslungsreicher.';
  }
  if (_istEinfacheFolge(klein)) {
    return 'Keine reine Zeichenfolge (wie 1234… oder abcd…).';
  }
  if (_istBekanntSchwach(klein)) {
    return 'Zu leicht zu erraten — bitte ein weniger gebräuchliches Passwort.';
  }
  return null;
}

/// Rein auf- oder absteigende Folge über die gesamte Länge (12345…, abcde…).
bool _istEinfacheFolge(String s) {
  if (s.length < 4) return false;
  var auf = true, ab = true;
  for (var i = 1; i < s.length; i++) {
    final d = s.codeUnitAt(i) - s.codeUnitAt(i - 1);
    if (d != 1) auf = false;
    if (d != -1) ab = false;
  }
  return auf || ab;
}

/// Kleine Liste gebräuchlicher Passwörter/Tastaturreihen (klein geschrieben).
/// Bewusst knapp: die Mindestlänge schließt die meisten schon aus; das hier
/// fängt das Wiederholen/Polstern eines schwachen Worts ab.
const List<String> _schwacheListe = [
  'passwort', 'password', 'kennwort', 'geheim', 'willkommen', 'welcome',
  'qwertz', 'qwerty', 'azerty', 'asdfgh', 'qwertzuiop', 'qwertyuiop',
  '123456', '1234567890', '000000', '111111', '12345678',
  'iloveyou', 'letmein', 'admin', 'master', 'sonnenschein', 'fussball',
  'monkey', 'dragon', 'passwort123', 'hallo123',
];

/// Entfernt auf-/absteigende Läufe ab Länge 4 (1234…, dcba…) — auch mittendrin,
/// nicht nur über das ganze Passwort (fängt „…12345…" und Wiederholungen).
String _ohneMonotoneLaeufe(String s) {
  final b = StringBuffer();
  var i = 0;
  while (i < s.length) {
    var j = i + 1;
    while (j < s.length && s.codeUnitAt(j) - s.codeUnitAt(j - 1) == 1) {
      j++;
    }
    if (j - i >= 4) {
      i = j;
      continue;
    }
    j = i + 1;
    while (j < s.length && s.codeUnitAt(j) - s.codeUnitAt(j - 1) == -1) {
      j++;
    }
    if (j - i >= 4) {
      i = j;
      continue;
    }
    b.writeCharCode(s.codeUnitAt(i));
    i++;
  }
  return b.toString();
}

/// Ist das Passwort im Kern nur Bekanntes/Triviales? Es wird schrittweise um
/// Wiederholungen, Zeichenfolgen und bekannte Wörter (längste zuerst) bereinigt;
/// bleibt danach kaum etwas übrig, taugt es nicht.
bool _istBekanntSchwach(String klein) {
  final sortiert = [..._schwacheListe]..sort((a, b) => b.length - a.length);
  var rest = klein;
  var geaendert = true;
  var runden = 0;
  while (geaendert && runden < 12) {
    runden++;
    final vorher = rest;
    // 3+ gleiche Zeichen (0000, aaaa) — NICHT die Doppelbuchstaben echter
    // Wörter (ss, tt), sonst wäre „passwort" nicht mehr erkennbar.
    rest = rest.replaceAll(RegExp(r'(.)\1{2,}'), '');
    rest = _ohneMonotoneLaeufe(rest); // 1234…, abcd…
    for (final s in sortiert) {
      if (s.length >= 3 && rest.contains(s)) rest = rest.replaceAll(s, '');
    }
    geaendert = rest != vorher;
  }
  return rest.length < 4;
}

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
