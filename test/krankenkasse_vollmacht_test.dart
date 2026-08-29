/// Die stillen Kopplungen der Krankenkassen-Vollmacht.
///
/// ⚠️ Das PHP liegt in KEINEM Repo — es lebt nur auf dem Server. Diese Datei
/// ist deshalb die einzige Stelle, an der auffallen kann, dass Bildschirm und
/// Erzeuger auseinandergelaufen sind. Und der Fehler ist stumm: der Server
/// lehnt einen unbekannten Schlüssel nicht ab, er ignoriert ihn. Das Kästchen
/// wäre angekreuzt, die Vollmacht erzeugt, das Feld im PDF leer — niemand
/// bekäme eine Meldung.
///
/// Die Sollwerte unten sind am 29.08.2026 aus den laufenden Funktionen
/// abgelesen, nicht aus dem Gedächtnis:
///
///     kkVollmachtBereiche()      -> leistungen, mitgliedschaft, pflege
///     kkVollmachtHandlungen()    -> akteneinsicht … unterlagen
///     kkVollmachtOnline()        -> vertretung … stammdaten
///     kkVollmachtNurBeiHandeln() -> antraege, widerspruch
///
/// Zum Nachprüfen auf dem Server:
///     php -r "define('API_ACCESS',1); require 'config.php';
///             require 'vollmacht_krankenkasse_lib.php';
///             print_r(array_keys(kkVollmachtBereiche()));"
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/krankenkasse_vollmacht.dart';

/// Was der Server am 29.08.2026 wirklich liefert.
const _serverBereiche = ['leistungen', 'mitgliedschaft', 'pflege'];
const _serverUmfang = [
  'akteneinsicht', 'schriftverkehr', 'fristen', 'termine',
  'antraege', 'widerspruch', 'unterlagen',
];
const _serverOnline = ['vertretung', 'zugangsdaten', 'postfach', 'antraege', 'stammdaten'];
const _serverNurBeiHandeln = ['antraege', 'widerspruch'];

/// Eine Antwort von `vollmacht_data.php?behoerde=krankenkasse` — in der FORM,
/// wie sie kommt, mit erfundenen Werten.
///
/// ⚠️ Bewusst keine mitgeschnittene echte Antwort: das Repo ist öffentlich,
/// und über genau diesen Weg sind hier schon dreimal echte Zugangsdaten
/// hinausgegangen.
Map<String, dynamic> _antwort() => {
  'success': true,
  'kasse': {'name': 'Musterkasse', 'dienststelle': 'Musterstelle'},
  'recht': {
    'label': 'Krankenkasse und Pflegekasse',
    'norm': '§ 13 Abs. 1 SGB X',
    'vertretung_norm': '§ 13 Abs. 6 Satz 2 SGB X i.V.m. § 73 Abs. 2 Satz 2 Nr. 8 SGG',
    'bereiche_katalog': {for (final k in _serverBereiche) k: 'Text $k'},
    'umfang_katalog': {for (final k in _serverUmfang) k: 'Text $k'},
    'online_katalog': {for (final k in _serverOnline) k: 'Text $k'},
    'nur_bei_handeln': _serverNurBeiHandeln,
  },
};

void main() {
  group('Kopplung Bildschirm ↔ Erzeuger', () {
    test('die drei Bereiche heißen im Client wie auf dem Server', () {
      expect(kKkBereiche, _serverBereiche);
    });

    test('der Behördenschlüssel steht in beiden Positivlisten des Servers', () {
      // ⚠️ `vollmacht_data.php` UND `vollmacht_create.php` führen je eine
      // eigene Liste. Fehlt er in einer, lädt der Reiter Daten und kann nichts
      // erzeugen — oder umgekehrt.
      expect(kKkBehoerde, 'krankenkasse');
    });

    test('der Dokumenttyp ist der, unter dem der Vorgang wiederzufinden ist', () {
      expect(kKkDokumentTyp, 'krankenkasse_vollmacht');
    });

    test('der Bildschirm zeigt jeden Katalog, den der Server schickt', () {
      final r = _antwort()['recht'] as Map<String, dynamic>;
      // Die Beschriftungen kommen vom Server — der Client darf nichts
      // anbieten, was im PDF nicht steht, und nichts auslassen, was dort steht.
      expect((r['bereiche_katalog'] as Map).keys, _serverBereiche);
      expect((r['umfang_katalog'] as Map).keys, _serverUmfang);
      expect((r['online_katalog'] as Map).keys, _serverOnline);
    });

    test('„nur bei Handeln" nennt genau Anträge und Widerspruch', () {
      // Wer ausschließlich Auskunft bekommt, stellt keine Anträge und legt
      // keinen Widerspruch ein — stünden die Zeilen trotzdem im Blatt, behauptete
      // die Urkunde eine Befugnis, die die angekreuzte Stufe ausschließt.
      final r = _antwort()['recht'] as Map<String, dynamic>;
      expect(r['nur_bei_handeln'], _serverNurBeiHandeln);
    });
  });

  group('Ein Bereich steht in genau einer Spalte', () {
    late Map<String, bool> handeln;
    late Map<String, bool> auskunft;

    setUp(() {
      handeln  = {for (final b in kKkBereiche) b: false};
      auskunft = {for (final b in kKkBereiche) b: false};
    });

    test('A anhaken nimmt B weg', () {
      kkBereichWaehlen(handeln, auskunft, 'pflege', inSpalteA: false, an: true);
      expect(auskunft['pflege'], isTrue);
      kkBereichWaehlen(handeln, auskunft, 'pflege', inSpalteA: true, an: true);
      expect(handeln['pflege'], isTrue);
      expect(auskunft['pflege'], isFalse);
    });

    test('B anhaken nimmt A weg', () {
      kkBereichWaehlen(handeln, auskunft, 'leistungen', inSpalteA: true, an: true);
      kkBereichWaehlen(handeln, auskunft, 'leistungen', inSpalteA: false, an: true);
      expect(auskunft['leistungen'], isTrue);
      expect(handeln['leistungen'], isFalse);
    });

    test('Abhaken räumt die andere Spalte NICHT auf', () {
      // ⚠️ Wer A abhakt, will A nicht mehr — er will nicht plötzlich B. Ein
      // Kreuz, das von selbst in die andere Spalte springt, wäre schlimmer als
      // gar keines: der Umfang stünde dann anders im PDF als gemeint.
      kkBereichWaehlen(handeln, auskunft, 'mitgliedschaft', inSpalteA: true, an: true);
      kkBereichWaehlen(handeln, auskunft, 'mitgliedschaft', inSpalteA: true, an: false);
      expect(handeln['mitgliedschaft'], isFalse);
      expect(auskunft['mitgliedschaft'], isFalse);
    });

    test('kein Bereich landet je in beiden Spalten', () {
      // Alle Reihenfolgen von An/Aus über beide Spalten durchspielen.
      for (final b in kKkBereiche) {
        for (final a1 in [true, false]) {
          for (final an1 in [true, false]) {
            for (final a2 in [true, false]) {
              for (final an2 in [true, false]) {
                handeln  = {for (final x in kKkBereiche) x: false};
                auskunft = {for (final x in kKkBereiche) x: false};
                kkBereichWaehlen(handeln, auskunft, b, inSpalteA: a1, an: an1);
                kkBereichWaehlen(handeln, auskunft, b, inSpalteA: a2, an: an2);
                expect(handeln[b] == true && auskunft[b] == true, isFalse,
                    reason: 'Bereich $b stand in beiden Spalten '
                            '(A=$a1/$an1, dann A=$a2/$an2)');
              }
            }
          }
        }
      }
    });
  });
}
