import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Eine Benachrichtigung liegt auf dem Sperrbildschirm. Name und Wortlaut
/// einer Mitgliedsnachricht gehören dort nicht hin.
///
/// ⚠️ Geprüft wird der QUELLTEXT, nicht das Verhalten — wie bei
/// `kein_inhalt_im_protokoll_test.dart`. Der Weg dorthin führt über einen
/// echten ntfy-Strom und den Plattformkanal für Benachrichtigungen; beides
/// gibt es im Test nicht. Der Quelltext ist die Stelle, an der ein Rückbau
/// überhaupt auffallen kann.
void main() {
  test('showChatMessage nimmt Namen und Wortlaut gar nicht erst entgegen', () {
    final q = File('lib/services/notification_service.dart').readAsStringSync();
    final anfang = q.indexOf('Future<void> showChatMessage(');
    expect(anfang, greaterThan(-1), reason: 'showChatMessage nicht gefunden');
    final ende = q.indexOf('}', q.indexOf('{', anfang));
    final signatur = q.substring(anfang, ende);

    // Die Sperre ist, dass es die Parameter NICHT gibt: ein Aufrufer kann
    // dann nichts durchreichen, auch nicht aus Versehen.
    expect(signatur.contains('senderName'), isFalse,
        reason: 'showChatMessage darf keinen Absendernamen entgegennehmen');
    expect(signatur.contains('String message'), isFalse,
        reason: 'showChatMessage darf keinen Nachrichtentext entgegennehmen');
  });

  test('die gewöhnliche Chat-Benachrichtigung nennt weder Namen noch Text', () {
    final q = File('lib/services/notification_service.dart').readAsStringSync();
    final i = q.indexOf('Future<void> showChatMessage(');
    // bis zum Beginn der naechsten Methode
    final j = q.indexOf('Future<void>', i + 10);
    final rumpf = q.substring(i, j > i ? j : q.length);

    expect(rumpf.contains(r'$senderName'), isFalse);
    expect(rumpf.contains(r'$message'), isFalse);
    expect(rumpf.contains('bodyPreview'), isFalse,
        reason: 'Textvorschau gehört nicht in die Benachrichtigung');
    expect(rumpf.contains('chatBenachrichtigungTitel'), isTrue,
        reason: 'es soll weiterhin gemeldet werden, DASS etwas da ist');

    // ⚠️ Entscheidung des Users, 01.09.2026: NUR der Titel, kein Text.
    expect(RegExp(r"body:\s*''").hasMatch(rumpf), isTrue,
        reason: 'die Chat-Benachrichtigung trägt keinen Text');
  });

  test('es gibt genau EINEN Wortlaut, den sich beide Wege teilen', () {
    final n = File('lib/services/notification_service.dart').readAsStringSync();
    final t = File('lib/services/ntfy_service.dart').readAsStringSync();

    // ⚠️ Zwei getrennte Zeichenketten würden auseinanderlaufen, und dann
    // leckte wieder einer der beiden Wege. Der ntfy-Weg muss die Konstante
    // benutzen, nicht seinen eigenen Text.
    expect(
        n.contains(
            "static const String chatBenachrichtigungTitel = 'Neue Nachricht'"),
        isTrue);
    expect(t.contains('NotificationService.chatBenachrichtigungTitel'), isTrue,
        reason: 'ntfy muss denselben Wortlaut verwenden, nicht einen eigenen');
    expect(t.contains('Sie haben eine neue Nachricht'), isFalse,
        reason: 'kein zweiter, eigener Wortlaut im ntfy-Weg');
  });

  test('ntfy-Chatmeldungen werden an der Marke speech_balloon entschärft', () {
    final q = File('lib/services/ntfy_service.dart').readAsStringSync();

    expect(q.contains("tags.contains('speech_balloon')"), isTrue,
        reason: 'Chat-Meldungen müssen erkannt werden');

    // Titel und Text des Servers duerfen nicht mehr ungeprueft durchgereicht
    // werden. Genau diese Zeile stand hier vorher.
    expect(q.contains('NotificationService().show(title: title, body: body)'),
        isFalse,
        reason: 'Server-Titel/-Text gehen nicht mehr ungefiltert auf den Schirm');
  });

  test('der Blitz bleibt unangetastet — er zeigt die Nachricht mit Absicht', () {
    final q = File('lib/services/notification_service.dart').readAsStringSync();
    final i = q.indexOf('Future<void> showBlitzVollbild(');
    expect(i, greaterThan(-1));
    final j = q.indexOf('Future<void>', i + 10);
    final rumpf = q.substring(i, j > i ? j : q.length);

    // ⚠️ Diese Zusicherung ist bewusst UMGEKEHRT: sie schuetzt eine Funktion
    // davor, im Zuge einer Datenschutz-Aufraeumaktion versehentlich
    // mitentkernt zu werden. Der Blitz SOLL die Nachricht zeigen; die Karte
    // ist dafür eigens hergerichtet (Mitgliedsnummer statt Name, Text deckt
    // sich nach kurzem Lesen selbst zu). Entscheidung des Users, 01.09.2026.
    expect(rumpf.contains('senderName'), isTrue,
        reason: 'Der Blitz darf den Absender weiterhin zeigen');
    expect(rumpf.contains('title: senderName'), isTrue);
  });
}
