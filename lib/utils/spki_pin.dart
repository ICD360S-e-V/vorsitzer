/// Öffentlicher Schlüssel eines Zertifikats — der Wert, an den gepinnt wird.
///
/// Gepinnt wird der **SubjectPublicKeyInfo** (SPKI) des Serverzertifikats,
/// nicht das Zertifikat selbst und nicht die Wurzel-CA.
///
/// ⚠️ Bisher hingen wir an den Wurzeln von Let's Encrypt. OWASP nennt genau
/// das: *„Pinning the root CA is generally not recommended since it highly
/// increases the risk because it implies also trusting all its intermediate
/// CAs."* Praktisch hiess es: **jedes** Let's-Encrypt-Zertifikat für unseren
/// Namen wurde angenommen — und Let's Encrypt stellt jedem eines aus, der
/// Kontrolle über DNS oder Port 80 nachweist. Wer den Domainnamen übernimmt,
/// war damit durch.
///
/// Der SPKI überlebt jede Erneuerung, solange derselbe Schlüssel benutzt wird
/// (`reuse_key = True`, am 22.08.2026 gesetzt und mit `--dry-run` geprüft).
/// Das ist der Grund, warum an den Schlüssel gepinnt wird und nicht an das
/// Zertifikat: Let's Encrypt bietet inzwischen Laufzeiten von sechs Tagen an,
/// ein Zertifikatspin wäre binnen einer Woche tot.
library;

import 'dart:convert';
import 'dart:io';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart' as crypto;

/// Erlaubte Schlüssel, als base64 des SHA-256 über den SPKI.
///
/// ⚠️ **Zwei Einträge, und der zweite ist kein Schmuck.** Der erste ist der
/// Schlüssel im Einsatz, der zweite liegt unbenutzt auf dem Server
/// (`/root/pin-reserve.key`, 0600). Muss der erste je weichen — Verdacht auf
/// Kompromittierung, oder jemand lässt certbot ohne `reuse_key` laufen —, wird
/// das Zertifikat auf den Reserveschlüssel ausgestellt und die App läuft
/// weiter, **ohne neue Fassung**. Ohne diesen zweiten Eintrag wären in dem
/// Moment alle Geräte gleichzeitig draussen.
///
/// Dasselbe Verfahren wie bei den zwei TLSA-Einträgen des Mailservers.
///
/// ⚠️ Wird der Reserveschlüssel je aufgebraucht, muss VOR dem Wechsel eine
/// Fassung mit einem neuen dritten Pin draussen sein. Sonst sperrt man sich
/// beim übernächsten Mal selbst aus.
const List<String> spkiPins = [
  'T8X566x2pOmqv64JC8wSeChLtf1jPhEODcldlS9FxuU=', // im Einsatz
  'sEVg0LlpwQuX02gPw0kcavPEXGM0rWpVL+0pGzZHHrw=', // Reserve, unbenutzt
];

/// Der Rechnername, für den gepinnt wird.
///
/// ⚠️ Nur dieser. `turn.icd360s.de` und `mail.icd360s.de` liegen auf derselben
/// Maschine, tragen aber eigene Zertifikate mit eigenen Schlüsseln — würde der
/// Pin auch für sie gelten, brächen sie sofort.
const String spkiHost = 'icd360sev.icd360s.de';

/// Zieht den SPKI aus einem Zertifikat und gibt seinen Pin zurück.
///
/// `null`, wenn sich nichts Brauchbares finden lässt — der Aufrufer weist die
/// Verbindung dann ab. Lieber keine Verbindung als eine ungeprüfte.
String? spkiPinVon(X509Certificate? zertifikat) {
  if (zertifikat == null) return null;
  try {
    final spki = _spkiFinden(ASN1Parser(zertifikat.der).nextObject());
    if (spki == null) return null;
    return base64.encode(crypto.sha256.convert(spki.encodedBytes).bytes);
  } catch (_) {
    return null;
  }
}

/// Sucht den SubjectPublicKeyInfo **nach Gestalt**, nicht nach Position.
///
/// ⚠️ Nach Position wäre es Element 6 des TBSCertificate — aber nur, wenn das
/// optionale Versionsfeld dasteht, sonst 5. Solche Zählerei kippt beim ersten
/// Zertifikat, das anders aufgebaut ist.
///
/// Die Gestalt ist dagegen eindeutig: SubjectPublicKeyInfo ist die einzige
/// SEQUENCE mit genau zwei Kindern, deren zweites ein BIT STRING ist. Der
/// Signaturalgorithmus ist zwar auch eine SEQUENCE, hat aber eine OID und
/// Parameter; `issuer` und `subject` enthalten SETs, `validity` zwei Zeiten.
ASN1Object? _spkiFinden(ASN1Object knoten) {
  if (knoten is! ASN1Sequence) return null;
  final kinder = knoten.elements;
  if (kinder.length == 2 &&
      kinder[0] is ASN1Sequence &&
      kinder[1] is ASN1BitString) {
    return knoten;
  }
  for (final kind in kinder) {
    final treffer = _spkiFinden(kind);
    if (treffer != null) return treffer;
  }
  return null;
}

/// Passt das Zertifikat zu einem der erlaubten Schlüssel?
bool spkiPasst(X509Certificate? zertifikat, {List<String> pins = spkiPins}) {
  final pin = spkiPinVon(zertifikat);
  if (pin == null) return false;
  return pins.contains(pin);
}
