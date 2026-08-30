import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/wortliste_service.dart';
import 'package:icd360sev_vorsitzer/utils/diakritika.dart';
import 'package:icd360sev_vorsitzer/utils/tippfehler.dart';
import 'package:icd360sev_vorsitzer/utils/wort_vervollstaendigung.dart';
import 'package:icd360sev_vorsitzer/widgets/eingabe_tasten.dart';
import 'package:icd360sev_vorsitzer/widgets/wort_vorschlaege.dart';

void main() {
  late TextEditingController c;
  late int gesendet;

  setUp(() {
    WortlisteService.setzenFuerTest(WortIndex.aufbauen(
      [
        'mulțumesc', 'mulțumiri', 'bine', 'binevoitor', 'trimiteți', 'dacă',
        // Genau die Wörter, an denen der echte Test gescheitert ist.
        'terminat', 'radule', 'pădurean', 'formularul',
      ],
    ), Diakritika.ausJson(const {
      'kurz': {'si': 'și', 'in': 'în'},
      'kontext': {
        'sa': {'să': {'r': ['trimit', 'faca'], 'l': ['ajunge']}},
        'va': {'vă': {'r': ['rog', 'trimit'], 'l': []}},
        'pana': {'până': {'r': ['in'], 'l': []}},
      },
    }), Tippfehler.aufbauen(
      ['document', 'trimiteți', 'mulțumesc', 'bine', 'care', 'mare'],
    ));
    c = TextEditingController();
    gesendet = 0;
  });

  tearDown(() => c.dispose());

  Future<void> aufbauen(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WortVorschlaege(
          controller: c,
          bauen: (vorDemSenden) => EingabeTasten(
            onSend: () {
              vorDemSenden();
              gesendet++;
            },
            bauen: (senden) => TextField(
              controller: c,
              autofocus: true,
              onSubmitted: (_) => senden(),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
  }

  /// Schreiben wie ein Mensch: Text UND Cursor. Ohne Cursor am Wortende gäbe
  /// es nach der Regel gar kein angefangenes Wort.
  void tippen(String text) {
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Ein einzelnes Zeichen anhängen — so, wie es eine Tastatur täte.
  void anhaengen(String zeichen) => tippen(c.text + zeichen);

  group('Vorschlagsleiste', () {
    testWidgets('nach drei Buchstaben steht der Vorschlag da', (t) async {
      await aufbauen(t);
      tippen('mulțu');
      await t.pump();
      expect(find.text('mulțumesc'), findsOneWidget);
    });

    testWidgets('ohne Häkchen getippt wird die richtige Schreibung angeboten',
        (t) async {
      await aufbauen(t);
      tippen('multu');
      await t.pump();
      expect(find.text('mulțumesc'), findsOneWidget);
    });

    testWidgets('mitten im Wort kommt kein Vorschlag', (t) async {
      await aufbauen(t);
      c.value = const TextEditingValue(
        text: 'multumesc frumos',
        selection: TextSelection.collapsed(offset: 4),
      );
      await t.pump();
      expect(find.text('mulțumesc'), findsNothing);
    });
  });

  group('Leertaste', () {
    testWidgets('übernimmt den obersten Vorschlag', (t) async {
      await aufbauen(t);
      tippen('multu');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'mulțumesc ');
      expect(c.selection.baseOffset, 10);
    });

    testWidgets('repariert die fehlenden Häkchen eines ganzen Wortes',
        (t) async {
      await aufbauen(t);
      tippen('Va rog multumesc');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'Va rog mulțumesc ');
    });

    testWidgets('lässt ein richtiges Wort in Ruhe', (t) async {
      // Die Sicherung gegen den bekanntesten Vorwurf: „bine" ist ein Wort und
      // darf nicht zu „binevoitor" werden, bloß weil das danebensteht.
      await aufbauen(t);
      tippen('bine');
      await t.pump();
      expect(find.text('binevoitor'), findsOneWidget);
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'bine ');
    });

    testWidgets('lässt ein unbekanntes Wort ohne Vorschlag in Ruhe',
        (t) async {
      await aufbauen(t);
      tippen('Duinea');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'Duinea ');
    });

    testWidgets('überträgt die Schreibung', (t) async {
      await aufbauen(t);
      tippen('Multu');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'Mulțumesc ');
    });

    testWidgets('das zweite Leerzeichen ersetzt nichts mehr', (t) async {
      await aufbauen(t);
      tippen('multu');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'mulțumesc  ');
    });
  });

  group('Häkchen aus dem Kontext', () {
    testWidgets('das eben getippte Wort, aus dem linken Nachbarn', (t) async {
      await aufbauen(t);
      tippen('ajunge sa');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'ajunge să ');
    });

    testWidgets('das Wort DAVOR, sobald der rechte Nachbar dasteht',
        (t) async {
      // ⚠️ Der wichtigste Fall: „va rog". Die Regel kann erst greifen, wenn
      // „rog" getippt ist — also beim Leerzeichen NACH „rog", nicht davor.
      await aufbauen(t);
      tippen('va rog');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'vă rog ');
    });

    testWidgets('kurze Nicht-Wörter brauchen keinen Nachbarn', (t) async {
      await aufbauen(t);
      tippen('si');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'și ');
    });

    testWidgets('„va mai" ist Futur und bleibt', (t) async {
      await aufbauen(t);
      tippen('va mai');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'va mai ');
    });

    testWidgets('die Eingabetaste sendet — und räumt vorher auf', (t) async {
      // Sie vervollständigt weiterhin NICHTS (das ist Sache der Leertaste),
      // aber sie lässt das letzte Wort nicht mehr ungeprüft rausgehen.
      await aufbauen(t);
      tippen('va rog');
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(gesendet, 1);
      expect(c.text, 'vă rog');
    });

    testWidgets('Rücktaste nimmt auch die Häkchen zurück', (t) async {
      await aufbauen(t);
      tippen('va rog');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'vă rog ');

      final i = c.selection.baseOffset;
      c.value = TextEditingValue(
        text: c.text.substring(0, i - 1) + c.text.substring(i),
        selection: TextSelection.collapsed(offset: i - 1),
      );
      await t.pump();
      expect(c.text, 'va rog ', reason: 'wieder genau das Getippte');
    });
  });

  group('Vertippt', () {
    testWidgets('ein Anschlag daneben wird repariert', (t) async {
      // „dovument" ist der Anfang von gar nichts — die Vorschlagsliste
      // kennt dazu nichts, der Abstand zum gemeinten Wort schon.
      await aufbauen(t);
      tippen('dovument');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'document ');
    });

    testWidgets('auch vor dem Senden', (t) async {
      await aufbauen(t);
      tippen('va trimit dovument');
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(c.text, 'va trimit document');
      expect(gesendet, 1);
    });

    testWidgets('bei Gleichstand bleibt es stehen', (t) async {
      // „nare" ist von „mare" und „care" gleich weit entfernt.
      await aufbauen(t);
      tippen('nare');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'nare ');
    });

    testWidgets('ein Eigenname mitten im Satz bleibt', (t) async {
      await aufbauen(t);
      tippen('scris la Documint');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'scris la Documint ');
    });

    testWidgets('die Rücktaste nimmt auch das zurück', (t) async {
      await aufbauen(t);
      tippen('dovument');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'document ');
      final i = c.selection.baseOffset;
      c.value = TextEditingValue(
        text: c.text.substring(0, i - 1) + c.text.substring(i),
        selection: TextSelection.collapsed(offset: i - 1),
      );
      await t.pump();
      expect(c.text, 'dovument ');
    });
  });

  group('Wann korrigiert wird', () {
    testWidgets('auch ein Punkt schließt das Wort ab', (t) async {
      // ⚠️ Anfangs löste nur das Leerzeichen aus — „va rog." blieb stehen,
      // und Satzenden sind gerade die Stellen, an denen viel steht.
      await aufbauen(t);
      tippen('va rog');
      await t.pump();
      anhaengen('.');
      await t.pump();
      expect(c.text, 'vă rog.');
    });

    testWidgets('ein Fragezeichen ebenso', (t) async {
      await aufbauen(t);
      tippen('ajunge sa');
      await t.pump();
      anhaengen('?');
      await t.pump();
      expect(c.text, 'ajunge să?');
    });

    testWidgets('vor dem Senden wird das LETZTE Wort noch geprüft',
        (t) async {
      // ⚠️ Der wichtigste Fall: dem letzten Wort folgt kein Leerzeichen
      // mehr. Ohne diesen Weg ginge es in JEDER Nachricht ungeprüft raus.
      await aufbauen(t);
      tippen('va rog');
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(c.text, 'vă rog', reason: 'korrigiert, bevor es rausgeht');
      expect(gesendet, 1);
    });

    testWidgets('der Sendeknopf geht denselben Weg', (t) async {
      await aufbauen(t);
      tippen('si');
      await t.pump();
      // In der App hängt der Knopf an derselben Funktion; hier steht sie
      // über die Eingabetaste zur Verfügung.
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(c.text, 'și');
      expect(gesendet, 1);
    });

    testWidgets('vor dem Senden bleibt ein Eigenname unangetastet',
        (t) async {
      await aufbauen(t);
      tippen('am vorbit cu Radu');
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(c.text, 'am vorbit cu Radu');
      expect(gesendet, 1);
    });

    testWidgets('ein richtiges Wort wird auch beim Senden nicht angefasst',
        (t) async {
      await aufbauen(t);
      tippen('totul este bine');
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(c.text, 'totul este bine');
    });
  });

  group('Eigennamen mitten im Satz', () {
    // Gemessen an echtem Text: ohne diese Sicherung würde aus „Termin"
    // „terminat", aus „Radu" „radule", aus „Padurean" „pădurean".
    const namen = {
      'Am trimis la Termin': 'Am trimis la Termin ',
      'Vorbit cu Radu': 'Vorbit cu Radu ',
      'membrul Padurean': 'membrul Padurean ',
      'am completat Formular': 'am completat Formular ',
    };

    namen.forEach((getippt, erwartet) {
      testWidgets('„$getippt" bleibt unangetastet', (t) async {
        await aufbauen(t);
        tippen(getippt);
        await t.pump();
        anhaengen(' ');
        await t.pump();
        expect(c.text, erwartet);
      });
    });

    testWidgets('am Satzanfang wird trotzdem vervollständigt', (t) async {
      // Dort ist der große Buchstabe nur Rechtschreibung.
      await aufbauen(t);
      tippen('Multu');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'Mulțumesc ');
    });

    testWidgets('auch nach einem Punkt gilt Satzanfang', (t) async {
      await aufbauen(t);
      tippen('Am scris. Multu');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'Am scris. Mulțumesc ');
    });

    testWidgets('klein geschrieben bleibt es eine Vervollständigung',
        (t) async {
      await aufbauen(t);
      tippen('Vorbit cu multu');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'Vorbit cu mulțumesc ');
    });

    testWidgets('antippen geht auch beim Eigennamen', (t) async {
      // Die Sicherung gilt nur für die Leertaste — wer antippt, will es.
      await aufbauen(t);
      tippen('Vorbit cu Radu');
      await t.pump();
      await t.tap(find.text('Radule'));
      await t.pump();
      expect(c.text, 'Vorbit cu Radule ');
    });
  });

  group('Rücktaste nimmt zurück', () {
    /// Rücktaste = ein Zeichen weniger am Cursor.
    void ruecktaste() {
      final t = c.text;
      final i = c.selection.baseOffset;
      c.value = TextEditingValue(
        text: t.substring(0, i - 1) + t.substring(i),
        selection: TextSelection.collapsed(offset: i - 1),
      );
    }

    testWidgets('holt das zurück, was wirklich getippt wurde', (t) async {
      await aufbauen(t);
      tippen('multu');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      expect(c.text, 'mulțumesc ');

      ruecktaste();
      await t.pump();
      expect(c.text, 'multu', reason: 'wieder das Getippte, ohne Leerzeichen');
      expect(c.selection.baseOffset, 5);
    });

    testWidgets('und danach wird dasselbe Wort in Ruhe gelassen', (t) async {
      // Ohne das setzte die nächste Leertaste sofort wieder dasselbe ein.
      await aufbauen(t);
      tippen('multu');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      ruecktaste();
      await t.pump();

      anhaengen(' ');
      await t.pump();
      expect(c.text, 'multu ');
    });

    testWidgets('greift nur unmittelbar danach', (t) async {
      await aufbauen(t);
      tippen('multu');
      await t.pump();
      anhaengen(' ');
      await t.pump();
      // Erst weiterschreiben, dann löschen — das ist eine ganz normale
      // Rücktaste und darf nichts wiederherstellen.
      anhaengen('f');
      await t.pump();
      ruecktaste();
      await t.pump();
      expect(c.text, 'mulțumesc ');
    });
  });

  group('Eingabetaste', () {
    testWidgets('sendet, auch wenn ein Vorschlag dasteht', (t) async {
      await aufbauen(t);
      tippen('multu');
      await t.pump();
      expect(find.text('mulțumesc'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(gesendet, 1);
      expect(c.text, 'multu', reason: 'die Taste vervollständigt nichts');
    });
  });

  group('Antippen', () {
    testWidgets('übernimmt auch dort, wo die Leertaste in Ruhe ließe',
        (t) async {
      await aufbauen(t);
      tippen('bine');
      await t.pump();
      await t.tap(find.text('binevoitor'));
      await t.pump();
      expect(c.text, 'binevoitor ');
      expect(gesendet, 0);
    });

    testWidgets('nimmt den angetippten, nicht den ersten Vorschlag',
        (t) async {
      await aufbauen(t);
      tippen('mulțum');
      await t.pump();
      await t.tap(find.text('mulțumiri'));
      await t.pump();
      expect(c.text, 'mulțumiri ');
    });
  });
}
