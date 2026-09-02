import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Prüfungen am QUELLTEXT, nicht am Verhalten.
///
/// ⚠️ Alle drei Fehler, die hier festgenagelt werden, sind STILL: sie werfen
/// nichts, sie loggen nichts, und die App sieht bedienbar aus. Genau deshalb
/// sind es Prüfungen — ein Widget-Test bräuchte einen laufenden Server, eine
/// angemeldete Sitzung und einen WebSocket, und würde die eigentliche Kopplung
/// trotzdem nicht sehen.
///
/// Dasselbe Vorgehen wie in `sipgate_lebenszeichen_test.dart`, und aus
/// demselben Grund.
void main() {
  String lies(String pfad) {
    final f = File(pfad);
    expect(f.existsSync(), isTrue, reason: '$pfad fehlt');
    return f.readAsStringSync();
  }

  group('StartWeiche schaltet auf die eingeschränkte Oberfläche', () {
    late String q;
    setUpAll(() => q = lies('lib/screens/start_weiche.dart'));

    test('fragt den Server und baut den Kompakt-Bildschirm', () {
      expect(q, contains('meinZugriff()'),
          reason: 'ohne die Abfrage weiss die Weiche nichts vom Flag');
      expect(q, contains('VorstandKompaktScreen('),
          reason: 'die Weiche muss den eingeschränkten Bildschirm auch bauen');
    });

    test('wartet auf den Bescheid, statt kurz das volle Dashboard zu zeigen', () {
      // Ohne `_eingeschraenkt == null` im Wartezweig blitzt beim Start für
      // einen Moment das vollständige Panel auf. Kein Datenleck -- der Server
      // weist ohnehin ab -- aber der Person wird gezeigt, was sie nicht hat.
      expect(q, contains('_eingeschraenkt == null'),
          reason: 'sonst flackert das volle Dashboard vor dem Bescheid');
    });

    test('fällt bei Netzfehler auf die VOLLE Oberfläche zurück', () {
      // Bewusst so. Der Server ist das Tor; ein eingeschränktes Konto bekommt
      // dort 403. Umgekehrt zu sperren hiesse: ein Netzaussetzer sperrt den
      // Vorsitzenden aus seiner eigenen App aus.
      expect(q, contains('_eingeschraenkt = false'),
          reason: 'der Rückfall muss "nicht eingeschränkt" sein');
    });

    test('merkt sich den letzten Bescheid', () {
      expect(q, contains('setBool('),
          reason: 'ohne gemerkten Wert zeigt ein Start ohne Netz das volle Panel');
    });
  });

  group('LiveChatDialog kann ein bestimmtes Gespräch öffnen', () {
    late String q;
    setUpAll(() => q = lies('lib/widgets/live_chat_dialog.dart'));

    test('nimmt eine vorgegebene Gesprächskennung entgegen', () {
      expect(q, contains('final int? conversationId'));
      expect(q, contains('final String? gegenueber'));
    });

    test('ruft bei vorgegebener Kennung NICHT startChat', () {
      // ⚠️ Der eigentliche Punkt. `startChat` liefert immer das EINE eigene
      // Support-Gespräch. Wer mit zwei Personen schreibt, käme an die zweite
      // nie heran -- und zwar ohne Fehlermeldung: die App zeigte einfach immer
      // dieselbe Unterhaltung.
      final anfang = q.indexOf('Future<void> _initChat()');
      expect(anfang, greaterThan(-1));
      final rumpf = q.substring(anfang, anfang + 1400);
      final abzweig = rumpf.indexOf('widget.conversationId != null');
      final startChat = rumpf.indexOf('startChat(');
      expect(abzweig, greaterThan(-1),
          reason: 'die Abzweigung für ein vorgegebenes Gespräch fehlt');
      expect(abzweig, lessThan(startChat),
          reason: 'die Abzweigung muss VOR dem startChat-Aufruf greifen');
      expect(rumpf.substring(abzweig, startChat), contains('return;'),
          reason: 'ohne return läuft startChat trotzdem und überschreibt die Kennung');
    });
  });

  group('Die Verwalter-Takte hängen am Dashboard, nicht am Programmstart', () {
    test('main.dart startet keinen von ihnen', () {
      // Läge auch nur einer in main.dart, liefe er für JEDES Konto — auch für
      // ein eingeschränktes, das den Kompakt-Bildschirm sieht und von den
      // Takten nichts ahnt.
      final m = lies('lib/main.dart');
      for (final dienst in [
        'FaxBadgeService',
        'MailBadgeService',
        'TicketNotificationService',
      ]) {
        expect(m, isNot(contains(dienst)),
            reason: '$dienst gehört an den Bildschirm, der ihn auch benutzt');
      }
    });
  });

  group('Der Kompakt-Bildschirm bleibt kompakt', () {
    late String q;
    setUpAll(() => q = lies('lib/screens/vorstand_kompakt_screen.dart'));

    test('führt nicht doch ins Dashboard', () {
      // ⚠️ Auf den KONSTRUKTOR und den Import prüfen, nicht auf das Wort: der
      // Kopfkommentar nennt [DashboardScreen] absichtlich, um zu erklären,
      // warum es diesen Bildschirm überhaupt gibt. Eine Prüfung, die daran
      // scheitert, wird beim nächsten Mal entnervt gelöscht -- und dann fängt
      // sie auch den echten Fall nicht mehr.
      expect(q, isNot(contains('DashboardScreen(')),
          reason: 'ein Weg zurück ins volle Panel hebt die Einschränkung auf');
      expect(q, isNot(contains("import 'dashboard_screen.dart'")),
          reason: 'der Kompakt-Bildschirm darf das Panel nicht einmal kennen');
    });

    test('filtert die Gesprächsliste NICHT im Client', () {
      // Die Auswahl trifft der Server (chat/conversations.php liefert einem
      // eingeschränkten Konto nur die eigenen Gespräche). Eine zweite
      // Filterung hier sähe aus wie der Schutz und wäre keiner.
      expect(q, isNot(contains('.where((g)')));
      expect(q, isNot(contains('admin_id ==')));
    });

    test('zeigt das GEGENÜBER, nicht das Mitglied des Gesprächs', () {
      // 🔴 Erst falsch gebaut: `member_*` wurde beim Direktchat mit der
      // Gegenseite überschrieben. In der Liste der Schatzmeisterin stand für
      // ihr Gespräch mit dem Vorsitz darum IHR EIGENER Name -- genau der Fall,
      // den die Spiegelung verhindern sollte, blieb offen. Der Server liefert
      // jetzt eigene `gegenueber_*`-Felder; wer hier wieder auf `member_name`
      // zurückfällt, holt den Fehler zurück.
      expect(q, contains("g['gegenueber_name']"),
          reason: 'sonst steht in der Liste der eigene Name');
      // Rückfall muss bleiben: ein älterer Server kennt das Feld nicht, und
      // eine Liste ohne Namen wäre schlimmer als eine mit dem falschen.
      expect(q, contains("?? g['member_name']"),
          reason: 'ohne Rückfall bleibt die Liste an einem alten Server leer');
    });

    test('startet keine Verwalter-Abfragen', () {
      // Die Abfragetakte des Dashboards (Fax, Mail, Ticket-Benachrichtigungen)
      // gehören einem Konto, das sie auch benutzen darf. Ein eingeschränktes
      // bekommt darauf 403 — und zwar alle fünf Minuten, rund um die Uhr:
      // Strom für nichts, und ein Log voller 403, in dem eine echte Warnung
      // nicht mehr auffällt.
      //
      // ⚠️ Heute stimmt das schon; diese Prüfung hält es fest. Wer später
      // einen Takt hier einbaut oder ihn nach main.dart verschiebt, bemerkt
      // nichts: es schlägt nichts fehl, der Server antwortet brav mit 403.
      for (final dienst in [
        'FaxBadgeService',
        'MailBadgeService',
        'TicketNotificationService',
        'listPendingMyVote',
        'getPendingApprovals',
      ]) {
        expect(q, isNot(contains(dienst)),
            reason: '$dienst gehört dem Dashboard, nicht diesem Bildschirm');
      }
    });

    test('zeigt keine internen Ticket-Notizen', () {
      expect(q, contains('!c.isInternal'),
          reason: 'interne Notizen sind Bemerkungen ÜBER den Vorgang, nicht an den Melder');
    });
  });
}
