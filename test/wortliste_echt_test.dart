import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/wort_vervollstaendigung.dart';

/// Prüft die AUSGELIEFERTE Wortliste, nicht eine erfundene.
///
/// ⚠️ Ohne diesen Test sagt alles andere nur, dass der Code mit Testdaten
/// funktioniert. Die Liste selbst ist erzeugt — aus einem Wörterbuch und
/// einer Häufigkeitsliste, die Cedille statt Komma-unten benutzt — und genau
/// dort steckt der Fehler, der sonst niemandem auffiele.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WortIndex index;
  late List<String> woerter;

  setUpAll(() async {
    final roh = await rootBundle.loadString('assets/woerterbuch/ro.txt');
    woerter = roh
        .split('\n')
        .map((z) => z.trim())
        .where((z) => z.isNotEmpty)
        .toList();
    index = WortIndex.aufbauen(woerter);
  });

  test('die Liste ist da und hat Umfang', () {
    expect(woerter.length, greaterThan(140000));
    expect(index.anzahl, woerter.length);
  });

  test('KEINE Cedille — sonst wanderte sie in Chat, NLLB und SMS', () {
    // Die Häufigkeitsliste aus den Untertiteln hatte 5.966 solcher Wörter,
    // darunter „şi" auf Platz 9.
    final ced = woerter.where((w) => RegExp(r'[şţŞŢ]').hasMatch(w));
    expect(ced, isEmpty, reason: 'gefunden: ${ced.take(5).toList()}');
  });

  test('nur rumänische Buchstaben, nichts Zerlesenes', () {
    final schlecht =
        woerter.where((w) => !RegExp(r'^[a-zA-ZăâîșțĂÂÎȘȚ]{2,}$').hasMatch(w));
    expect(schlecht, isEmpty, reason: 'gefunden: ${schlecht.take(5).toList()}');
  });

  test('nach Häufigkeit sortiert, nicht alphabetisch', () {
    // Wäre sie alphabetisch, stünde der brauchbarste Vorschlag nie oben.
    expect(woerter.take(12), containsAll(['de', 'nu', 'să', 'și', 'în']));
  });

  group('das Wort, das jemand wirklich schreibt', () {
    // Was in diesem Verein tatsächlich getippt wird — Ämter, Anträge, Arzt.
    const faelle = {
      'imputer': 'împuternicire',
      'contesta': 'contestație',
      'adeveri': 'adeverință',
      'dizabil': 'dizabilitate',
      'indemniz': 'indemnizație',
      'consimt': 'consimțământ',
      'hotarar': 'hotărâre',
      'sedint': 'ședință',
      'locuint': 'locuință',
      'multumesc': 'mulțumesc',
    };

    faelle.forEach((getippt, erwartet) {
      test('„$getippt" schlägt „$erwartet" vor', () {
        expect(index.vorschlaege(getippt, hoechstens: 8), contains(erwartet));
      });
    });
  });

  test('die häufige Form steht vor der seltenen', () {
    // „pentru" ist das mit Abstand häufigste Wort auf „pent".
    expect(index.vorschlaege('pent').first, 'pentru');
  });

  test('ein richtig geschriebenes Wort gilt als Wort', () {
    for (final w in ['bine', 'mulțumesc', 'ședință', 'și', 'împuternicire']) {
      expect(index.kennt(w), isTrue, reason: w);
    }
    // ...die Fassung ohne Häkchen dagegen nicht — darauf beruht die
    // Sicherung der Leertaste.
    for (final w in ['multumesc', 'sedinta', 'imputernicire']) {
      expect(index.kennt(w), isFalse, reason: w);
    }
  });

  group('was die Leertaste an ECHTEM Text täte', () {
    /// Bildet die Regel aus [WortVorschlaege] nach: ersetzt wird nur, wenn
    /// das Wort selbst keines ist UND es nicht großgeschrieben mitten im
    /// Satz steht.
    String? wuerdeErsetzen(String satz) {
      final wort = AngefangenesWort.ausEingabe(satz, satz.length);
      if (wort == null) return null;
      final v = index.vorschlaege(wort.text);
      if (v.isEmpty) return null;
      if (index.kennt(wort.text)) return null;
      if (AngefangenesWort.grossGeschrieben(wort.text) &&
          !AngefangenesWort.istSatzanfang(satz, wort.von)) {
        return null;
      }
      return WortIndex.schreibungUebernehmen(wort.text, v.first);
    }

    // ⚠️ Genau diese Wörter haben die Sicherung nötig gemacht: ohne sie
    // wurde aus „Termin" „terminat" und aus „Padurean" „pădurean".
    const eigennamen = [
      'Vollmacht', 'Landratsamt', 'Jobcenter', 'Krankenkasse', 'Termin',
      'Bescheid', 'Antrag', 'Widerspruch', 'Pflegegrad', 'Rente', 'Formular',
      'Duinea', 'Anica', 'Radu', 'Ionut', 'Padurean', 'Tanase', 'Menning',
    ];

    for (final name in eigennamen) {
      test('„$name" mitten im Satz bleibt unangetastet', () {
        expect(wuerdeErsetzen('Am scris la $name'), isNull);
      });
    }

    test('GEGENPROBE: ohne die Sicherung wären es echte Fehler', () {
      // ⚠️ Ohne diese Prüfung wäre der Test oben zahnlos: für „Vollmacht"
      // gibt es ohnehin keinen Vorschlag, der Test bestünde also auch dann,
      // wenn die Sicherung ganz fehlte. Diese Wörter HABEN einen Vorschlag —
      // gerettet werden sie allein durch den großen Buchstaben.
      const gefaehrlich = {
        'Termin': 'terminat',
        'Radu': 'radule',
        'Padurean': 'pădurean',
        'Formular': 'formularul',
      };
      gefaehrlich.forEach((wort, falsch) {
        expect(index.kennt(wort), isFalse, reason: wort);
        expect(index.vorschlaege(wort).first, falsch,
            reason: 'ohne Sicherung würde aus „$wort" „$falsch"');
      });
    });

    test('die fehlenden Häkchen werden trotzdem repariert', () {
      expect(wuerdeErsetzen('va rog multumesc'), 'mulțumesc');
      expect(wuerdeErsetzen('am trimis cererea la primarie'), 'primărie');
      expect(wuerdeErsetzen('Multumesc'), 'Mulțumesc');
    });

    test('ein richtig geschriebenes Wort wird nie ersetzt', () {
      for (final satz in [
        'va rog mulțumesc',
        'am fost bine',
        'la ședință',
        'cu împuternicire',
      ]) {
        expect(wuerdeErsetzen(satz), isNull, reason: satz);
      }
    });
  });

  test('ein Vorschlag kommt in unter zwei Millisekunden', () {
    // Er hängt an jedem Tastendruck. Wird das langsam, ruckelt das Schreiben.
    const proben = ['imputer', 'de', 'pent', 'con', 'multu', 'xyzab', 'ase'];
    final uhr = Stopwatch()..start();
    for (var i = 0; i < 300; i++) {
      for (final p in proben) {
        index.vorschlaege(p);
      }
    }
    uhr.stop();
    final proAbfrage = uhr.elapsedMicroseconds / (300 * proben.length);
    expect(proAbfrage, lessThan(2000), reason: '${proAbfrage.round()} µs');
  });
}
