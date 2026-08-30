import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icd360sev_vorsitzer/services/signatur_gateway_service.dart';

/// Die drei Stellen, an denen die Telefonie am 30.08.2026 still ausfallen
/// konnte — und die alle drei nichts gemeldet hätten.
///
/// ⚠️ ZWEI DAVON LESEN DEN QUELLTEXT, UND DAS IST ABSICHT.
/// Beide Fehler waren **leere Rümpfe**: eine Methode, die nichts tat, und eine,
/// der eine Zeile fehlte. So etwas lässt sich nicht aufbauen und beobachten —
/// `onNewReinvite` gehört zu einer privaten Klasse und braucht einen laufenden
/// SIP-Stack, `_klingelnBeenden` einen echten Klingelton. Ein Widget- oder
/// Einheitentest müsste den halben Stack nachbilden, um am Ende dieselbe
/// Eigenschaft zu prüfen, die im Quelltext direkt dasteht.
///
/// Derselbe Aufbau wie `rufnummern_waehlbar_test.dart` und die Notruf-Prüfung
/// in `sipgate_nummer_test.dart`.
void main() {
  String quelle(String pfad) {
    final f = File(pfad);
    expect(f.existsSync(), isTrue, reason: 'Datei fehlt: $pfad');
    return f.readAsStringSync();
  }

  /// Der Rumpf einer Methode ab ihrer Signatur.
  ///
  /// ⚠️ Zwei Fallen, in die die erste Fassung beide gelaufen ist:
  ///  * `cancelIncomingCall({int? conversationId})` trägt eine `{` in der
  ///    PARAMETERLISTE — „die erste Klammer nach der Signatur" liefert dann
  ///    die Parameter statt des Rumpfs.
  ///  * `nochGebraucht() => …` hat gar keinen Klammerrumpf.
  /// Beide Male schlug der Test fehl, obwohl der Code stimmte — und genau so
  /// entstehen Tests, die man am Ende entnervt lockert.
  String rumpf(String quelltext, String signatur) {
    final start = quelltext.indexOf(signatur);
    expect(start, isNot(-1), reason: 'nicht gefunden: $signatur');

    // Über die Parameterliste hinweg: von der ersten `(` bis zur passenden `)`.
    var i = quelltext.indexOf('(', start);
    var runde = 0;
    for (; i < quelltext.length; i++) {
      if (quelltext[i] == '(') runde++;
      if (quelltext[i] == ')') {
        runde--;
        if (runde == 0) break;
      }
    }
    i++;

    // `async` / `async*` / `sync*` dazwischen überspringen.
    final rest = quelltext.substring(i);
    final vorspann = RegExp(r'^\s*(async\*?|sync\*)?\s*').firstMatch(rest)!;
    i += vorspann.end;

    if (quelltext.startsWith('=>', i)) {
      final ende = quelltext.indexOf(';', i);
      expect(ende, isNot(-1), reason: 'Ausdrucksrumpf ohne `;`: $signatur');
      return quelltext.substring(i + 2, ende);
    }

    expect(quelltext[i], '{', reason: 'kein Rumpf gefunden: $signatur');
    var tiefe = 0;
    for (var k = i; k < quelltext.length; k++) {
      if (quelltext[k] == '{') tiefe++;
      if (quelltext[k] == '}') {
        tiefe--;
        if (tiefe == 0) return quelltext.substring(i + 1, k);
      }
    }
    fail('Rumpf von „$signatur" nicht abgeschlossen');
  }

  group('A1 — ein re-INVITE wird beantwortet', () {
    // `emit(EventReInvite(… callback: acceptReInvite …))` ist in
    // `sip_ua-1.1.0/lib/src/rtc_session.dart:2041` die LETZTE Anweisung von
    // `_receiveReinvite`; es gibt keinen Rückfall, anders als bei
    // `_receiveUpdate` dreissig Zeilen tiefer. Ein leerer Rumpf heisst hier
    // also nicht „ignorieren", sondern „eine SIP-Anfrage bleibt ohne
    // Endantwort".
    test('onNewReinvite ist nicht leer und ruft die Annahme', () {
      final r = rumpf(quelle('lib/services/sipgate_service.dart'),
          'void onNewReinvite(ReInvite event)');
      expect(r.trim(), isNotEmpty,
          reason: 'leerer Rumpf lässt den re-INVITE unbeantwortet');
      expect(r, contains('event.accept'),
          reason: 'ohne accept wird nichts beantwortet');
    });
  });

  group('A3 — die Anruf-Benachrichtigung wird zurückgenommen', () {
    // Vorher stoppte `_klingelnBeenden` nur den Ton. Die Nutzlast `call:null`
    // ist fest, also war auch die Kennung fest: jeder neue Anruf ersetzte nur
    // den Text, und es stand dauerhaft jemand in der Leiste, der angeblich
    // gerade anruft.
    test('_klingelnBeenden nimmt sie zurück, nicht nur den Ton', () {
      final r = rumpf(quelle('lib/services/sipgate_service.dart'),
          'void _klingelnBeenden()');
      expect(r, contains('cancelIncomingCall'));
    });

    test('das Gegenstück existiert und rechnet dieselbe Kennung', () {
      final q = quelle('lib/services/notification_service.dart');
      expect(q, contains('Future<void> cancelIncomingCall('));
      // Dieselbe Nutzlast wie in showIncomingCall — sonst wird eine andere
      // Benachrichtigung zurückgenommen als die, die steht.
      final r = rumpf(q, 'Future<void> cancelIncomingCall(');
      expect(r, contains("'call:\$conversationId'"));
      expect(quelle('lib/services/notification_service.dart'),
          contains("payload: 'call:\$conversationId'"));
    });
  });

  group('A2 — den Wachdienst braucht auch die sipgate-Anmeldung', () {
    // `sip_ua` lebt im Haupt-Isolat, und ein Haupt-Isolat ohne
    // Vordergrunddienst darf Android einfrieren. Bis zum 30.08.2026 startete
    // diesen Dienst niemand für die Telefonie — dass es lief, war Zufall:
    // dasselbe Tablet trägt auch das SMS-Gateway.
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      SignaturGatewayService.sipgateHaeltRegistrierung = false;
    });

    tearDown(() => SignaturGatewayService.sipgateHaeltRegistrierung = false);

    test('ohne jeden Grund wird er nicht gebraucht', () async {
      expect(await SignaturGatewayService.nochGebraucht(), isFalse);
    });

    test('die Anmeldung allein hält ihn am Leben', () async {
      // Genau die Lücke: beide Schalter aus, und trotzdem muss der Prozess
      // stehen bleiben — sonst klingelt es nicht mehr.
      SignaturGatewayService.sipgateHaeltRegistrierung = true;
      expect(await SignaturGatewayService.nochGebraucht(), isTrue);
    });

    test('das Feld wird gesetzt, nicht aus dem Schalter gelesen', () {
      // `autoAktiv()` steht auf Android voreingestellt AN — auch auf einem
      // Gerät ohne eigenes VoIP-Telefon. Würde hier der Schalter gelesen, zöge
      // der RDP-Kiosk eine Dauerbenachrichtigung hoch für eine Registrierung,
      // die er nie eingeht.
      final q = quelle('lib/services/signatur_gateway_service.dart');
      final r = rumpf(q, 'static Future<bool> nochGebraucht()');
      expect(r, contains('sipgateHaeltRegistrierung'));
      expect(r, isNot(contains('autoAktiv')));
    });

    test('beide Gateways fragen nicht mehr selbst, sondern an einer Stelle',
        () {
      // Vorher kannte jede Stelle nur die jeweils andere Hälfte. Mit einem
      // dritten Grund hätte jede von beiden den Dienst gestoppt, während ihn
      // der dritte noch braucht.
      for (final p in const [
        'lib/services/anruf_gateway_service.dart',
        'lib/services/termin_sms_gateway_service.dart',
      ]) {
        final q = quelle(p);
        expect(q, contains('SignaturGatewayService.stoppenWennUnnoetig()'),
            reason: '$p entscheidet noch selbst');
        expect(q, isNot(contains('SignaturGatewayService.stoppen()')),
            reason: '$p stoppt den Dienst noch bedingungslos');
      }
    });

    test('der Kiosk schaltet auch sipgate ab', () {
      // Sonst hätte der Kiosk einen fünften Grund für eine
      // Dauerbenachrichtigung — und ausgerechnet den einzigen, der sich selbst
      // wieder einschaltet: `starten()` plant nach jedem Fehlschlag den
      // nächsten Anlauf, also käme der Wachdienst nach der Stilllegung zurück.
      final q = quelle('lib/screens/rdp_only_screen.dart');
      expect(q, contains("stillegen('sipgate'"));
      // Vor dem Wachdienst, sonst stünde der Dienst danach wieder.
      expect(q.indexOf("stillegen('sipgate'"),
          lessThan(q.indexOf("stillegen('Wachdienst'")));
    });

    test('sipgate setzt das Feld in beide Richtungen', () {
      final q = quelle('lib/services/sipgate_service.dart');
      expect('sipgateHaeltRegistrierung = true'.allMatches(q).length, 1);
      // Zweimal zurück: beim Abschalten und wenn das Gerät gar kein eigenes
      // VoIP-Telefon hat.
      expect('sipgateHaeltRegistrierung = false'.allMatches(q).length, 2);
    });
  });
}
