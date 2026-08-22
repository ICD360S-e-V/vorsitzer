import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/sicherer_dateiname.dart';
import 'package:path/path.dart' as p;

void main() {
  group('gepruefterDateiname — lehnt strukturelle Angriffe ab', () {
    void abgelehnt(Object? roh, String weil) {
      expect(() => gepruefterDateiname(roh), throwsA(isA<DateinameAbgelehnt>()),
          reason: weil);
    }

    test('Pfadtrenner in beiden Richtungen', () {
      // ⚠️ Auch der Schrägstrich muss fallen: Windows akzeptiert ihn ebenfalls
      // als Trenner, nicht nur den Backslash.
      abgelehnt('../../../.bashrc', 'klassische Traversierung');
      abgelehnt(r'..\..\.bashrc', 'Traversierung mit Backslash');
      abgelehnt('unter/ordner.pdf', 'Unterordner ist kein Dateiname');
      abgelehnt(r'unter\ordner.pdf', 'auch mit Backslash');
      abgelehnt('/etc/passwd', 'absoluter Pfad');
      abgelehnt(r'\windows\system32', 'wurzelrelativ');
    });

    test('Verzeichnisverweise', () {
      abgelehnt('..', 'das Elternverzeichnis');
      abgelehnt('.', 'das aktuelle Verzeichnis');
    });

    test('NUL-Byte', () {
      abgelehnt('harmlos.pdf\x00.exe', 'abgeschnittener Name');
    });

    test('Laufwerksangabe', () {
      // "C:datei.pdf" ist auf Windows relativ zum aktuellen Verzeichnis von C:.
      abgelehnt('C:datei.pdf', 'Laufwerk');
      abgelehnt(r'C:\Users\x\datei.pdf', 'Laufwerk mit Pfad');
    });

    test('die Ablehnung trägt den rohen Wert mit, aber nur für das Log', () {
      try {
        gepruefterDateiname('../../geheim');
        fail('hätte werfen müssen');
      } on DateinameAbgelehnt catch (e) {
        expect(e.roh, '../../geheim');
        expect(e.nachricht, isNot(contains('..')),
            reason: 'die Anzeige wiederholt den Angriffsstring nicht');
      }
    });
  });

  group('gepruefterDateiname — bereinigt Plattformeigenheiten still', () {
    test('lässt einen normalen Namen unangetastet', () {
      expect(gepruefterDateiname('Bescheid vom 12.03.2026.pdf'),
          'Bescheid vom 12.03.2026.pdf');
      expect(gepruefterDateiname('Anlage_2 (Kopie).pdf'),
          'Anlage_2 (Kopie).pdf');
    });

    test('deutsche Umlaute bleiben — das ist kein Angriff', () {
      expect(gepruefterDateiname('Übersicht Beiträge.pdf'),
          'Übersicht Beiträge.pdf');
    });

    test('ersetzt die auf Windows verbotenen Zeichen', () {
      expect(gepruefterDateiname('a<b>c:d"e|f?g*h.pdf'),
          'a_b_c_d_e_f_g_h.pdf');
    });

    test('entfernt Punkt und Leerzeichen am Ende', () {
      // Windows schneidet sie ohnehin still ab.
      expect(gepruefterDateiname('bericht.pdf.'), 'bericht.pdf');
      expect(gepruefterDateiname('bericht.pdf   '), 'bericht.pdf');
      expect(gepruefterDateiname('bericht.pdf . . '), 'bericht.pdf');
    });

    test('entschärft Windows-Gerätenamen — auch MIT Endung', () {
      // Der eigentliche Fallstrick: NUL.pdf ist laut Microsoft gleichbedeutend
      // mit NUL. Ohne diese Regel schriebe der Download ins Nichts und der
      // Betrachter zeigte eine leere Datei — das sähe nach einem kaputten
      // Programm aus, nicht nach einem seltsamen Namen.
      expect(gepruefterDateiname('NUL.pdf'), '_NUL.pdf');
      expect(gepruefterDateiname('nul'), '_nul');
      expect(gepruefterDateiname('CON.txt'), '_CON.txt');
      expect(gepruefterDateiname('COM1.pdf'), '_COM1.pdf');
      expect(gepruefterDateiname('LPT9.tar.gz'), '_LPT9.tar.gz');
      expect(gepruefterDateiname('aux.jpeg'), '_aux.jpeg');
    });

    test('auch die hochgestellten Gerätenamen', () {
      // Windows erkennt ¹ ² ³ als Ziffern in COM#/LPT#.
      expect(gepruefterDateiname('COM¹.pdf'), '_COM¹.pdf');
      expect(gepruefterDateiname('LPT³'), '_LPT³');
    });

    test('ein Name, der nur so ANFÄNGT, bleibt unangetastet', () {
      // `NULLWERTE.pdf` ist kein Gerät — nur `NUL` und `NUL.<endung>` sind es.
      expect(gepruefterDateiname('NULLWERTE.pdf'), 'NULLWERTE.pdf');
      expect(gepruefterDateiname('CONTRACT.pdf'), 'CONTRACT.pdf');
      expect(gepruefterDateiname('COM10.pdf'), 'COM10.pdf');
    });

    test('kürzt zu lange Namen und behält die Endung', () {
      final lang = '${'a' * 300}.pdf';
      final k = gepruefterDateiname(lang);
      expect(k.length, lessThanOrEqualTo(120));
      expect(k, endsWith('.pdf'),
          reason: 'die Endung entscheidet, womit geöffnet wird');
    });

    test('fällt auf den Ersatznamen zurück, wenn nichts übrig bleibt', () {
      expect(gepruefterDateiname(''), 'datei');
      expect(gepruefterDateiname(null), 'datei');
      expect(gepruefterDateiname('   '), 'datei');
      expect(gepruefterDateiname('...'), 'datei');
      expect(gepruefterDateiname(null, fallback: 'dokument.pdf'),
          'dokument.pdf');
    });

    test('ein führender Punkt darf bleiben', () {
      // Microsoft erlaubt ihn ausdrücklich, und `.gitignore` ist ein Name.
      expect(gepruefterDateiname('.htaccess'), '.htaccess');
    });
  });

  group('sichereDatei — die Zusicherung über das Ergebnis', () {
    late Directory basis;

    setUp(() => basis = Directory.systemTemp.createTempSync('sd_test'));
    tearDown(() => basis.deleteSync(recursive: true));

    test('legt die Datei unterhalb des Zielordners an', () {
      final f = sichereDatei(basis, 'bericht.pdf');
      expect(p.isWithin(p.canonicalize(basis.path), p.canonicalize(f.path)),
          isTrue);
      expect(p.basename(f.path), 'bericht.pdf');
    });

    test('eine Traversierung kommt gar nicht bis zur zweiten Schicht', () {
      expect(() => sichereDatei(basis, '../../../.bashrc'),
          throwsA(isA<DateinameAbgelehnt>()));
    });

    test('der Ersatzname landet ebenfalls im Ordner', () {
      final f = sichereDatei(basis, null, fallback: 'dokument.pdf');
      expect(p.isWithin(p.canonicalize(basis.path), p.canonicalize(f.path)),
          isTrue);
    });

    test('schreiben und wieder lesen geht wirklich', () {
      // Nicht nur Pfadarithmetik: der Name muss auch benutzbar sein.
      final f = sichereDatei(basis, 'Übersicht Beiträge (2026).pdf');
      f.writeAsBytesSync([1, 2, 3]);
      expect(f.readAsBytesSync(), [1, 2, 3]);
      expect(basis.listSync().length, 1);
    });

    test('nach einer Ablehnung entsteht keine Datei', () {
      expect(() => sichereDatei(basis, r'..\..\boese'),
          throwsA(isA<DateinameAbgelehnt>()));
      expect(basis.listSync(), isEmpty);
    });
  });

  group('Regression: was der Vorgänger durchgelassen hätte', () {
    // Die vier alten Fassungen im Baum waren alle verschieden und alle
    // lückenhaft. Diese Fälle halten fest, was jetzt anders ist.
    test('das alte allowlist-Muster ließ ".." stehen', () {
      // mail_screen: name.replaceAll(RegExp(r'[^A-Za-z0-9._\-]'), '_')
      final alt = '..'.replaceAll(RegExp(r'[^A-Za-z0-9._\-]'), '_');
      expect(alt, '..', reason: 'der Punkt stand auf der Erlaubnisliste');
      expect(() => gepruefterDateiname('..'),
          throwsA(isA<DateinameAbgelehnt>()));
    });

    test('keine der alten Fassungen kannte Windows-Gerätenamen', () {
      final alt = 'NUL.pdf'.replaceAll(RegExp(r'[^\w\.\- ]'), '_');
      expect(alt, 'NUL.pdf');
      expect(gepruefterDateiname('NUL.pdf'), '_NUL.pdf');
    });
  });
}
