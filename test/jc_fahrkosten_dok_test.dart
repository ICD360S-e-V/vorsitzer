import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/jc_fahrkosten_dok.dart';

/// Jobcenter ▸ Termin ▸ Fahrkosten.
///
/// ⚠️ Ein Teil dieser Prüfungen liest QUELLTEXT. Das ist hier kein Notbehelf:
/// die Gegenstelle ist `api/admin/jobcenter_av_termin_fahrkosten.php`, und das
/// PHP liegt in KEINEM Repo. Läuft eine der beiden Seiten weg, weist der
/// Server mit HTTP 400 ab — und das sieht auf dem Schirm wie ein Fehler der
/// App aus. Dieser Test ist die einzige Stelle im Baum, an der das auffallen
/// kann.
void main() {
  // Beim Ausführen aus dem Paketwurzelverzeichnis.
  //
  // 🔴 OHNE KOMMENTARE. In der Gegenprobe blieb die Bearer-Prüfung grün,
  // nachdem `request.headers.addAll(_headers);` zu `// request.headers…`
  // geworden war — ein Test, der eine tote Zeile bestätigt, prüft nichts.
  final widget = _ohneKommentare(File('lib/widgets/behorde_jobcenter.dart').readAsStringSync());
  final api = _ohneKommentare(File('lib/services/api_service.dart').readAsStringSync());

  group('Katalog', () {
    test('die drei Arten sind zeichengleich mit JCFK_TYPEN auf dem Server', () {
      expect(kJcFahrkostenDokTypen.keys.toList(), ['antrag', 'beleg', 'anlage']);
      // Jede Art braucht auch eine Kurzform — sonst steht in der Liste der
      // rohe Schlüssel.
      for (final k in kJcFahrkostenDokTypen.keys) {
        expect(kJcFahrkostenDokKurz.containsKey(k), isTrue, reason: 'Kurzform fehlt: $k');
      }
      expect(kJcFahrkostenDokKurz.keys.toSet(), kJcFahrkostenDokTypen.keys.toSet());
    });

    test('Endungen und Höchstzahl decken sich mit dem Server', () {
      // jcfkTypBestimmen() erkennt genau PDF, JPEG und PNG an den ersten Bytes.
      expect(kJcFahrkostenEndungen, ['pdf', 'jpg', 'jpeg', 'png']);
      expect(kJcFahrkostenMaxDokumente, 20); // JCFK_MAX_DOCS
    });

    test('nicht mit dem Gründe-Katalog des Schreibens verwechselt', () {
      // kJcFahrtkosten (jc_termin_gruende.dart) trägt oepnv/pkw/begleitung/… —
      // das sind Gründe eines Briefes, keine Dateiarten. Ein gemeinsamer
      // Schlüssel wäre der erste Schritt zum Verwechseln.
      expect(kJcFahrkostenDokTypen.keys, isNot(contains('oepnv')));
      expect(kJcFahrkostenDokTypen.keys, isNot(contains('vorschuss')));
    });
  });

  group('Versandzustand — drei, nicht zwei', () {
    test('ohne alles: weder gesendet noch fehlgeschlagen', () {
      const d = <String, dynamic>{};
      expect(jcFahrkostenVersandt(d), isFalse);
      expect(jcFahrkostenFehler(d), isFalse);
    });

    test('übergeben: Datum gesetzt, kein Fehler', () {
      final d = {'versand_datum': '2026-09-05 10:12:00',
                 'versand_status': 'an sipgate uebergeben'};
      expect(jcFahrkostenVersandt(d), isTrue);
      expect(jcFahrkostenFehler(d), isFalse);
    });

    // 🔴 Der Fall, an dem die erste Fassung der Karte scheiterte.
    test('Fehlversuch hat KEIN Datum — der Fehler darf trotzdem sichtbar sein', () {
      // Genau das schreibt der Server im Fehlerzweig: nur versand_status.
      final d = {'versand_status': 'Fehler: Keine Faxnummer'};
      expect(jcFahrkostenVersandt(d), isFalse,
          reason: 'ohne Datum ist nichts herausgegangen');
      expect(jcFahrkostenFehler(d), isTrue,
          reason: 'der Versuch muss unabhängig vom Datum erkennbar bleiben');
    });

    test('leere Zeichenketten zählen nicht als Datum', () {
      expect(jcFahrkostenVersandt({'versand_datum': ''}), isFalse);
      expect(jcFahrkostenFehler({'versand_status': ''}), isFalse);
    });
  });

  group('Verdrahtung im Termin-Fenster', () {
    test('der Reiter hat vier Seiten, nicht mehr drei', () {
      // ⚠️ Im RICHTIGEN State nachsehen. `TabController(length: 4)` steht auch
      // in _AvVorschlagDetailModal — in der Gegenprobe blieb die Prüfung
      // deshalb grün, obwohl der Termin wieder auf drei Reiter zurückgebaut
      // war. Eine Zeichenkette über die ganze Datei zu suchen heisst, die
      // erstbeste gleichnamige Stelle zu prüfen.
      final rumpf = _funktionsrumpf(widget,
          '_tab = TabController(length: 4, vsync: this);\n    _t = Map<String, dynamic>.from');
      expect(rumpf, isNotEmpty,
          reason: '_TerminDetailModalState hat keine vier Reiter mehr');
      expect(widget.contains("text: 'Fahrkosten"), isTrue);
      expect(widget.contains('_TerminFahrkostenTab('), isTrue);
    });

    test('der Fehlschlag wird VOR dem Datum geprüft', () {
      // Sonst verschwindet ein gescheiterter Versuch hinter „noch nicht
      // gesendet" — er trägt kein versand_datum.
      final rumpf = _funktionsrumpf(widget, 'Widget _karte(Map<String, dynamic> d) {');
      final iFehler = rumpf.indexOf('child: fehler');
      final iVersandt = rumpf.indexOf(': versandt');
      expect(iFehler, greaterThan(-1), reason: 'die Fehlerprüfung fehlt ganz');
      expect(iVersandt, greaterThan(iFehler),
          reason: 'versandt darf erst NACH fehler geprüft werden');
    });

    test('beide Knöpfe laufen durch denselben Hochladeweg', () {
      final rumpf = _funktionsrumpf(widget, 'Widget build(BuildContext context) {\n    final frei =');
      // Gerät und Cloud rufen beide _hochladen — zwei getrennte Wege bekämen
      // mit der Zeit zwei Prüfungen und zwei Fehlermeldungen.
      expect(rumpf.contains('onPicked: (r) => _hochladen(ausCloud: r)'), isTrue);
      expect(rumpf.contains('onPressed: (_busy || frei <= 0) ? null : () => _hochladen()'), isTrue);
      // …und mit derselben Liste erlaubter Endungen.
      expect('allowedExtensions: kJcFahrkostenEndungen'.allMatches(rumpf).length, 1);
      expect(rumpf.contains('CloudPickButton('), isTrue);
    });

    test('die Zwischendatei aus dem Cloud wird immer gelöscht', () {
      // ⚠️ Sie liegt ENTSCHLÜSSELT im temporären Verzeichnis. Das Löschen
      // gehört in finally, nicht in den Erfolgszweig — ein Fehlschlag ist kein
      // Grund, den Klartext liegen zu lassen.
      final rumpf = _funktionsrumpf(widget, 'Future<void> _hochladen({FilePickerResult? ausCloud}) async {');
      final iFinally = rumpf.indexOf('} finally {');
      final iDelete = rumpf.indexOf('d.deleteSync()');
      expect(iFinally, greaterThan(-1));
      expect(iDelete, greaterThan(iFinally),
          reason: 'deleteSync muss im finally-Zweig stehen');
      // Auch der Abbruch im Art-und-Datum-Dialog räumt auf.
      expect(rumpf.contains('if (ausCloud != null) _tempAufraeumen(ergebnis);'), isTrue);
    });

    test('der Querverweis auf das Schreiben steht da', () {
      // Der Vordruck allein trägt die Vollmacht nicht — das muss auf dem
      // Schirm stehen, nicht nur in einem Kommentar.
      expect(widget.contains('Reisekosten beantragen'), isTrue);
      expect(widget.contains('§ 13 Abs. 1 SGB X'), isTrue);
      expect(widget.contains('§ 37 Abs. 2 Satz 1 SGB II'), isTrue);
      expect(widget.contains('§ 59 SGB II i. V. m. § 309 Abs. 4 SGB III'), isTrue);
    });

    test('die Datei wird aus dem Arbeitsspeicher gezeigt, nicht von der Platte', () {
      final rumpf = _funktionsrumpf(widget, 'Future<void> _ansehen(Map<String, dynamic> d) async {');
      expect(rumpf.contains('FileViewerDialog.showFromBytes'), isTrue);
      for (final verboten in ['writeAsBytes', 'getTemporaryDirectory', 'OpenFilex', 'Share']) {
        expect(rumpf.contains(verboten), isFalse, reason: '$verboten im Ansehen-Pfad');
      }
    });
  });

  group('Zugang zum Endpunkt', () {
    test('der Upload trägt den Bearer', () {
      // ⚠️ Ein MultipartRequest mit von Hand gesetzten Kopfzeilen bekommt 401 —
      // daran ist im August platform/korrespondenz_create.php gescheitert.
      final rumpf = _funktionsrumpf(api, 'Future<Map<String, dynamic>> jcFahrkostenUpload({');
      expect(rumpf.contains('request.headers.addAll(_headers)'), isTrue);
    });

    test('jede Anfrage nennt die user_id', () {
      // Sie steht auf dem Server in der WHERE-Klausel — ohne sie liest eine
      // hochgezählte id fremde Unterlagen.
      for (final f in ['jcFahrkostenListe', 'jcFahrkostenUpload', 'jcFahrkostenDownload',
                       'jcFahrkostenUpdate', 'jcFahrkostenLoeschen', 'jcFahrkostenFax']) {
        final rumpf = _funktionsrumpf(api, f);
        expect(rumpf.contains('user_id'), isTrue, reason: '$f schickt keine user_id');
      }
    });
  });
}

/// Der Rumpf einer Funktion ab [start] bis zur passenden schließenden Klammer.
///
/// ⚠️ Zeichenpositionen über die GANZE Datei zu vergleichen misst den Text,
/// nicht den Ablauf: verschiebt sich etwas in eine andere Methode, meldet der
/// Test eine Regression, die es nicht gibt. Deshalb wird zugeschnitten.
///
/// ⚠️ Die geschweifte Klammer der BENANNTEN PARAMETER zählt nicht mit. Die
/// erste Fassung nahm sie für den Rumpfanfang und gab bei jeder Funktion mit
/// `({…})` nur die Signatur zurück — drei Prüfungen waren dadurch grün
/// beziehungsweise rot, ohne je den Rumpf gesehen zu haben. Deshalb beginnt
/// der Rumpf an der ersten Klammer, die AUSSERHALB der Parameterliste steht.
String _funktionsrumpf(String quelle, String start) {
  final i = quelle.indexOf(start);
  if (i < 0) return '';
  var klammern = 0; // runde Klammern der Signatur
  var tiefe = 0;
  var gesehen = false;
  for (var j = i; j < quelle.length; j++) {
    final c = quelle[j];
    if (c == '(') { klammern++; continue; }
    if (c == ')') { klammern--; continue; }
    if (klammern > 0 && !gesehen) continue;
    if (c == '{') { tiefe++; gesehen = true; }
    else if (c == '}') {
      tiefe--;
      if (gesehen && tiefe == 0) return quelle.substring(i, j + 1);
    }
  }
  return quelle.substring(i);
}

/// Zeilenkommentare weg — ein auskommentierter Aufruf ist kein Aufruf.
///
/// ⚠️ Nur `//` bis Zeilenende. Zeichenketten mit `//` darin (etwa eine URL)
/// gibt es in den geprüften Rümpfen nicht; ein voller Dart-Parser wäre für
/// diese Frage die falsche Größe.
String _ohneKommentare(String quelle) => quelle
    .split('\n')
    .map((z) {
      final i = z.indexOf('//');
      return i < 0 ? z : z.substring(0, i);
    })
    .join('\n');
