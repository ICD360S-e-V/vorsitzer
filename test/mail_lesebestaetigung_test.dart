import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Warum es diese Prüfung gibt.
///
/// Bis zum 31.08.2026 merkte sich einzig das Widget, dass eine Lesebestätigung
/// draußen war (`bool _receiptSent = false;`). Nach jedem Neuladen stand die
/// Bitte wieder da, und jedes Antippen schickte dem Absender eine weitere
/// Bestätigung. Im Maillog steht der Preis: die HNO-Praxis Ulm hat am
/// 17.08.2026 um 13:01:38 und 13:01:43 **zwei** bekommen.
///
/// ⚠️ DIESE PRÜFUNG LIEST DEN QUELLTEXT, UND DAS IST ABSICHT.
/// Der Fehler war ein Feld mit dem falschen Ursprung. Um ihn aufzubauen und zu
/// beobachten, bräuchte es `MailMessageView` mit einem echten Server dahinter —
/// am Ende geprüft würde dieselbe Eigenschaft, die hier direkt dasteht.
/// Gleicher Aufbau wie `sipgate_lebenszeichen_test.dart`.
///
/// ⚠️ Die Gegenseite dieser Kopplung liegt in `/opt/mailapi/app.py` und damit
/// in keinem Repo: dort setzt `/v1/mdn` nach erfolgreichem Versand das
/// IMAP-Keyword `$MDNSent` (RFC 3503) und `/v1/message` meldet es als
/// `mdn_sent`. Wer den Feldnamen dort ändert, muss ihn hier ändern — sonst
/// fragt die Mail wieder jedes Mal.
void main() {
  // ⚠️ `expect` gehört in einen Test, nicht in einen Gruppenrumpf: dort wirft
  // es `OutsideTestException`, und die Datei lädt gar nicht erst.
  String quelle(String pfad) {
    final f = File(pfad);
    if (!f.existsSync()) throw StateError('Datei fehlt: $pfad');
    return f.readAsStringSync();
  }

  group('Lesebestätigung wird nur einmal erbeten', () {
    late final String screen = quelle('lib/screens/mail_screen.dart');

    test('der Stand kommt vom Server, nicht allein aus dem Widget', () {
      expect(
        screen.contains("_msg['mdn_sent'] == true"),
        isTrue,
        reason: 'Ohne mdn_sent aus der Mailbox ist die Antwort nach jedem '
            'Neuladen wieder „nein" — genau der alte Fehler.',
      );
      expect(
        RegExp(r'bool\s+get\s+_receiptSent').hasMatch(screen),
        isTrue,
        reason: '_receiptSent muss der abgeleitete Wert sein. Ein einfaches '
            'Feld kann den Serverstand nicht kennen.',
      );
    });

    test('das Sitzungs-Merkfeld überschreibt den Serverstand nicht', () {
      // ⚠️ Ein `bool _receiptSent = false;` DARF es nicht mehr geben: es würde
      // den Getter verdecken und den Fehler lautlos zurückbringen.
      expect(
        RegExp(r'bool\s+_receiptSent\s*=').hasMatch(screen),
        isFalse,
        reason: 'Das Feld ist durch den Getter ersetzt worden.',
      );
      expect(screen.contains('_receiptLokal = true'), isTrue,
          reason: 'Die eigene Bestätigung muss sofort greifen, ohne Neuladen.');
    });

    test('„war schon gesendet" wird nicht als frischer Versand gemeldet', () {
      // Der Server sendet in dem Fall NICHT noch einmal. Es als „gesendet" zu
      // melden verschweigt, dass der Knopf nichts getan hat.
      expect(screen.contains("res['already'] == true"), isTrue);
      expect(screen.contains('Lesebestätigung war schon gesendet'), isTrue);
    });

    test('der Stand überlebt den Zwischenspeicher', () {
      // Die Ablage ist eine Positivliste — ein nicht genanntes Feld fällt weg,
      // und offline stünde die Bitte wieder da.
      expect(
        quelle('lib/services/mail_cache_service.dart').contains("'mdn_sent'"),
        isTrue,
      );
    });
  });
}
