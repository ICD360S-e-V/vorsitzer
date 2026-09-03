import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Was nach dem Auflegen einer Konferenz passieren muss.
///
/// 🔴 ZWEI FEHLER AUS DEM ECHTEN BETRIEB, beide mit derselben Wurzel: seit der
/// zweite Teilnehmer über die Telefonanlage dazukommt (`*3<nr>#`), hängt unser
/// Softphone an genau EINEM SIP-Dialog. Für den zweiten gibt es keinen `Call`
/// — und damit auch nie ein Ereignis, das ihn beendet oder abräumt.
///
///   1. „Das Gespräch schliesst sich nicht bei allen." Unser BYE beendet nur
///      unser Bein; die anderen beiden können verbunden bleiben.
///   2. „Beim nächsten Anruf sieht es aus, als riefe ich zwei Nummern an."
///      Der Eintrag des zweiten Teilnehmers blieb für immer im Zustand stehen.
///
/// Geprüft wird der Quelltext: beide Zweige brauchen einen laufenden SIP-Stack
/// und zwei abgehobene Gegenstellen.
void main() {
  final dienst = File('lib/services/sipgate_service.dart').readAsStringSync();

  String rumpf(String beginn, String ende) {
    final i = dienst.indexOf(beginn);
    if (i < 0) throw StateError('Anker „$beginn" nicht gefunden');
    final j = dienst.indexOf(ende, i + beginn.length);
    if (j <= i) throw StateError('Ende „$ende" nicht gefunden');
    return dienst.substring(i, j);
  }

  group('auflegen beendet die Konferenz für alle', () {
    final r = rumpf('void auflegen({bool? zweites})',
        'Future<void> _restAuflegen(');

    test('die Nummern werden VOR dem Auflegen abgelesen', () {
      // ⚠️ Die Reihenfolge ist die Zusicherung: gleich nach `hangup()` räumt
      // das ENDED-Ereignis den Zustand ab. Wer die Nummern danach liest,
      // bekommt eine leere Liste — und der Server legt dann gar nichts auf,
      // ohne dass irgendwo etwas fehlschlägt.
      final vorher = r.indexOf('final betroffen = <String>[');
      final hangup = r.indexOf('ruf?.hangup();');
      expect(vorher, isNot(-1));
      expect(hangup, isNot(-1));
      expect(vorher, lessThan(hangup));
    });

    test('nachgefasst wird nur, wenn es mehr als ein Bein gab', () {
      expect(r, contains('if (mehrAlsEins && betroffen.isNotEmpty)'));
    });

    test('und mit den Nummern, nicht pauschal', () {
      expect(r, contains('_restAuflegen(betroffen)'));
    });
  });

  group('das Nachfassen selbst', () {
    final r = rumpf('Future<void> _restAuflegen(', '  /// Das Bein, das gerade');

    test('wartet kurz, bevor es fragt', () {
      // ⚠️ Unser BYE ist gerade erst hinaus; die Anlage braucht einen Moment,
      // bis `/calls` den neuen Stand zeigt. Ohne die Pause sieht man das
      // eigene, schon beendete Bein und legt es ein zweites Mal auf.
      expect(r, contains('await Future<void>.delayed'));
    });

    test('schickt die Nummern mit', () {
      expect(r, contains("'action': 'alle_auflegen', 'nummern': nummern"));
    });

    test('ein Fehlschlag stört das Auflegen nicht', () {
      // Unser eigenes Bein ist da schon weg; eine Meldung über den Bildschirm
      // hülfe niemandem mehr.
      expect(r, contains('catch (e)'));
      expect(r.contains('meldung:'), isFalse);
    });
  });

  group('kein Bein überlebt ohne SIP-Dialog', () {
    final r = rumpf('EIN BEIN OHNE SIP-DIALOG KANN NICHT WEITERLAUFEN',
        '// Bleibt genau ein Bein übrig');

    test('geräumt wird, sobald KEIN Call mehr da ist', () {
      // ⚠️ Und nicht „wenn die Konferenz an war": auch ein abgebrochener
      // Versuch, bei dem nie zusammengeschaltet wurde, hinterlässt den Geist.
      expect(r, contains('if (_rufA == null && _rufB == null)'));
      expect(r.contains('zustand.value.konferenz)'), isTrue,
          reason: 'Das Konferenz-Kennzeichen wird nicht zurückgesetzt');
    });

    test('beide Seiten werden abgeräumt, nicht nur die gemeldete', () {
      expect(r, contains("for (final s in const ['A', 'B'])"));
      expect(r, contains('_setzeBein(s, null)'));
    });

    test('und der Verlauf bekommt für beide eine Endzeile', () {
      // Sonst bliebe die Zeile des zweiten Teilnehmers für immer „gestartet" —
      // und der tägliche Wächter zählte sie als offenes Gespräch.
      expect(r, contains('_anrufProtokoll('));
      expect(r, contains("status: 'beendet'"));
    });
  });
}
