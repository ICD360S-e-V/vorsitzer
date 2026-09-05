import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';

/// Die Rufnummer auf der schwebenden Gesprächskarte.
///
/// 🔴 WOZU. Die Karte schwebt über allem, was gerade auf dem Schirm ist, und
/// sie ist von einem Meter Abstand zu lesen. Wer im Wartezimmer, im Amt oder
/// im Bus daneben steht, hatte bisher die vollständige Rufnummer des Anrufers
/// — eines Mitglieds, eines Arztes, einer Behörde. Im Vollbild steht sie
/// weiterhin ganz da: dorthin geht man absichtlich.
void main() {
  group('anruferVerdeckt', () {
    test('lässt die ersten zwei und die letzten drei Ziffern stehen', () {
      expect(SipgateService.anruferVerdeckt('0731 80159736'), '07·······736');
      expect(SipgateService.anruferVerdeckt('016087654321'), '01·······321');
    });

    test('das Pluszeichen bleibt, und die Ziffern werden richtig gezählt', () {
      // ⚠️ Gezählt werden ZIFFERN, nicht Zeichen — sonst verbrauchte ein
      // „+49 " die sichtbaren Stellen und man sähe von der Nummer nichts.
      expect(SipgateService.anruferVerdeckt('+4915112345678'), '+49········678');
      expect(SipgateService.anruferVerdeckt('+40755532286'), '+40······286');
    });

    test('ein Punkt je verdeckter Ziffer — die Länge bleibt sichtbar', () {
      // Sonst sähen zwei ganz verschiedene Anrufer gleich aus.
      final kurz = SipgateService.anruferVerdeckt('0731801597');
      final lang = SipgateService.anruferVerdeckt('073180159736');
      expect(kurz.length, lessThan(lang.length));
    });

    test('🔴 KURZE NUMMERN BLEIBEN GANZ STEHEN', () {
      // 110, 112, 116117: verdeckt ergäben sie Unsinn, sie sind niemandes
      // Privatsache — und ausgerechnet dort muss man sofort sehen, worum es
      // geht.
      for (final n in ['110', '112', '116117', '115', '0731161']) {
        expect(SipgateService.anruferVerdeckt(n), contains(n.substring(0, 3)),
            reason: '$n wurde verdeckt');
        expect(SipgateService.anruferVerdeckt(n), isNot(contains('·')),
            reason: '$n wurde verdeckt');
      }
    });

    test('eine unterdrückte Nummer bleibt „Unbekannter Anrufer"', () {
      expect(SipgateService.anruferVerdeckt('anonymous'), 'Unbekannter Anrufer');
      expect(SipgateService.anruferVerdeckt(null), isNot(contains('·')));
    });

    test('die Nummer lässt sich daraus NICHT rekonstruieren', () {
      // Das ist der ganze Zweck: wiedererkennen ja, anrufen nein.
      const voll = '073180159736';
      final v = SipgateService.anruferVerdeckt(voll);
      final sichtbar = v.replaceAll('·', '');
      expect(sichtbar.length, 5, reason: 'zu viel sichtbar: $v');
      expect(v, isNot(contains('80159')));
    });
  });

  group('das Overlay benutzt durchgehend die verdeckte Form', () {
    late String quelle;
    setUpAll(() {
      quelle = File('lib/widgets/sipgate_anruf_overlay.dart').readAsStringSync();
    });

    test('keine unverdeckte Anzeige mehr in der Karte', () {
      // ⚠️ Auf das WORT geprüft, mit Grenze: `anzeigeVerdeckt` enthält
      // `anzeige` als Teilzeichenkette, ein naives contains fände immer etwas.
      final offen = RegExp(r'\.anzeige\b(?!Verdeckt)').allMatches(quelle);
      expect(offen, isEmpty,
          reason: 'unverdeckte Stelle: '
              '${offen.map((m) => quelle.substring(m.start - 30, m.end + 10))}');
      expect(quelle, isNot(contains('SipgateService.anruferAnzeige(')));
    });

    test('auch die Konferenz und das gehaltene zweite Gespräch', () {
      expect(quelle, contains('b.anzeigeVerdeckt'));
      expect(quelle, contains('z.zweites!.anzeigeVerdeckt'));
    });
  });

  test('im Vollbild bleibt die Nummer ganz', () {
    // ⚠️ Die Trennung ist der Punkt: die Karte drängt sich auf, der Bildschirm
    // wird aufgesucht. Verdeckte man beides, könnte man nicht mehr zurückrufen.
    final schirm = File('lib/screens/sipgate_screen.dart').readAsStringSync();
    expect(schirm, contains('SipgateService.anruferAnzeige('));
    expect(schirm, isNot(contains('anruferVerdeckt')));
  });
}
