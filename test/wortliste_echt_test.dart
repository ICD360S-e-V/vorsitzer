import 'dart:convert' show jsonDecode;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/diakritika.dart';
import 'package:icd360sev_vorsitzer/services/wortliste_service.dart';
import 'package:icd360sev_vorsitzer/utils/auto_korrektur.dart';
import 'package:icd360sev_vorsitzer/utils/tippfehler.dart';
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
    // ⚠️ Der Bindestrich ist erlaubt, aber nur INNEN: „mi-aș", „s-a",
    // „într-o" sind je EIN Wort. Am Rand wäre er ein Zerlesungsrest.
    final schlecht = woerter.where((w) => !RegExp(
            r'^[a-zA-ZăâîșțĂÂÎȘȚ]+(?:-[a-zA-ZăâîșțĂÂÎȘȚ]+)*$')
        .hasMatch(w) || w.length < 2);
    expect(schlecht, isEmpty, reason: 'gefunden: ${schlecht.take(5).toList()}');
  });

  group('Formen mit Bindestrich', () {
    // ⚠️ Sie fehlten ganz: die erste Fassung der Liste verwarf jedes Wort
    // mit Bindestrich. Im Rumänischen hängen dort aber die häufigsten
    // kurzen Wörter zusammen — „s-a" steht auf Platz 14 der ganzen Sprache.
    test('die häufigen stehen drin', () {
      for (final w in ['s-a', 'într-o', 'să-l', 'mi-a', 'nu-i', 'n-am',
                       'm-am', 'l-am', 'ne-am', 'te-am', 'dintr-un']) {
        expect(woerter, contains(w), reason: w);
      }
    });

    test('ohne Bindestrich getippt findet die richtige Form', () {
      // Beim schnellen Schreiben fällt der Strich weg. Gemeldet aus dem
      // Betrieb: 》mias《 sollte 》mi-aș《 werden.
      const faelle = {
        'mias': 'mi-aș',
        'nui': 'nu-i',
        'intro': 'într-o',
        'dintrun': 'dintr-un',
        'nam': 'n-am',
        'mam': 'm-am',
        'lam': 'l-am',
        'sasi': 'să-și',
      };
      faelle.forEach((getippt, erwartet) {
        expect(index.vorschlaege(getippt, hoechstens: 3), contains(erwartet),
            reason: getippt);
      });
    });

    test('der Bindestrich trennt kein Wort', () {
      // Sonst bliebe beim Tippen von „mi-aș" nur „aș" übrig.
      final w = AngefangenesWort.ausEingabe('vreau mi-aș', 11);
      expect(w?.text, 'mi-aș');
    });

    test('was für sich ein Wort ist, bleibt geschützt', () {
      // „neam", „team", „sai" sind echte rumänische Wörter — sie dürfen
      // nicht stillschweigend zu „ne-am", „te-am", „să-i" werden.
      for (final w in ['neam', 'team', 'sai', 'sal', 'sa']) {
        expect(index.kennt(w), isTrue, reason: w);
      }
    });
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
      // ⚠️ „Termin" und „Formular" standen hier einmal mit: seit [kennt]
      // auch klein nachschlägt, gelten sie als Wörter — 》termin《 und
      // 》formular《 sind rumänisch. Sie sind damit schon durch die ERSTE
      // Sicherung geschützt, nicht erst durch den großen Buchstaben. Dass
      // die deutschen Fachwörter dieses Vereins so oft rumänische Zwillinge
      // haben, war nicht geplant, hilft aber.
      const gefaehrlich = {
        'Radu': 'radule',
        'Padurean': 'pădurean',
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

  group('die AUSGELIEFERTEN Kontextregeln', () {
    late Diakritika d;
    setUpAll(() async {
      d = Diakritika.ausJson(jsonDecode(
          await rootBundle.loadString('assets/woerterbuch/ro_kontext.json'))
          as Map<String, dynamic>);
    });

    /// Ganzen Satz korrigieren, wie es das Schreibfeld Wort für Wort tut.
    String satz(String s) {
      final w = s.split(' ');
      final aus = List<String>.from(w);
      for (var i = 0; i < w.length; i++) {
        aus[i] = d.korrektur(w[i],
                links: i > 0 ? w[i - 1] : null,
                rechts: i + 1 < w.length ? w[i + 1] : null) ??
            w[i];
      }
      return aus.join(' ');
    }

    test('die Regeln sind da', () {
      expect(d.bereit, isTrue);
      expect(d.kontext.length, greaterThan(200));
      expect(d.kurz, containsPair('si', 'și'));
      expect(d.kurz, containsPair('in', 'în'));
    });

    // ⚠️ Genau die Sätze, wegen derer das hier gebaut wurde — an ihnen hat
    // der eigene Übersetzungsweg messbar danebengegriffen.
    test('repariert echte Sätze', () {
      expect(satz('va rog sa imi trimiteti hotararea'),
          startsWith('vă rog să'));
      expect(satz('am asteptat pana in luna mai'), contains('până în'));
      expect(satz('banuiesc ca nu a venit'), contains('că'));
      expect(satz('documentele pana maine'), contains('până'));
    });

    test('die häufigsten Wendungen sind abgedeckt', () {
      // ⚠️ Diese Zeile hielt einmal das Gegenteil fest — 》stiu ca《 blieb
      // stehen. Gemeldet aus dem Betrieb: 》sa《 und 》ca《 würden nicht
      // korrigiert. Ursache war der Korpusfilter: beide SIND rumänische
      // Wörter, ein Satz mit ihnen fiel also nicht auf und verdarb das
      // Verhältnis. Seit nur noch Sätze zählen, die selbst Häkchen tragen,
      // stieg die Trefferquote von 39,7 % auf 71,3 %.
      expect(satz('stiu ca nu a venit'), 'stiu că nu a venit');
      expect(satz('trebuie sa rezolv'), contains('să'));
      expect(satz('vrei sa ma vezi'), 'vrei să mă vezi');
    });

    test('was weiterhin NICHT abgedeckt ist, bleibt unangetastet', () {
      // Ein knappes Drittel bleibt stehen, und das ist gewollt: eine
      // geratene Korrektur wäre schlimmer als eine fehlende.
      expect(satz('o pana de curent'), 'o pana de curent');
    });

    test('lässt richtiges Futur in Ruhe', () {
      // „va" ist hier Hilfsverb, nicht Pronomen.
      expect(satz('el va mai veni'), 'el va mai veni');
      expect(satz('va place foarte mult'), 'va place foarte mult');
    });

    test('fasst Eigennamen nicht an', () {
      for (final n in ['Duinea', 'Padurean', 'Vollmacht', 'Landratsamt']) {
        expect(d.korrektur(n, links: 'la', rechts: 'rog'), isNull, reason: n);
      }
    });

    test('eine Korrektur kommt in unter einer Millisekunde', () {
      final uhr = Stopwatch()..start();
      for (var i = 0; i < 2000; i++) {
        d.korrektur('sa', links: 'ajunge', rechts: 'faca');
        d.korrektur('necunoscut', links: 'a', rechts: 'b');
      }
      uhr.stop();
      expect(uhr.elapsedMicroseconds / 4000, lessThan(1000));
    });
  });

  group('Vertipper gegen die AUSGELIEFERTE Liste', () {
    late Tippfehler t;
    late Diakritika regeln;
    setUpAll(() async {
      t = Tippfehler.aufbauen(woerter);
      regeln = Diakritika.ausJson(jsonDecode(
              await rootBundle.loadString('assets/woerterbuch/ro_kontext.json'))
          as Map<String, dynamic>);
    });

    test('repariert echte Vertipper', () {
      const faelle = {
        'dovumentul': 'documentul',   // falsche Taste
        'documnetul': 'documentul',   // vertauscht
        'multumesk': 'mulțumesc',     // daneben, dazu Häkchen
        'adeverinta': 'adeverința',
        'buletim': 'buletin',
        'membrii': null,              // ist selbst ein Wort
      };
      faelle.forEach((falsch, richtig) {
        expect(t.korrektur(falsch), richtig, reason: falsch);
      });
    });

    test('ein Gleichstand wird nur bei klarem Häufigkeitsabstand gelöst', () {
      // Zu „cerrere" liegen ZWEI Wörter einen Schritt entfernt: „cerere"
      // (ein Buchstabe zu viel) und „cernere" (ein Buchstabe daneben).
      // Früher blieb das stehen. Weil „cerere" um ein Vielfaches häufiger
      // ist, wird es jetzt aufgelöst — gemessen kostet das 0,08 Prozentpunkte
      // Genauigkeit und bringt zwei Prozentpunkte mehr Treffer.
      expect(t.korrektur('cerrere'), 'cerere');
      // Wo die Häufigkeiten dicht beieinander liegen, bleibt es beim
      // Nichtstun — und bei kurzen Wörtern immer.
      expect(t.korrektur('trimiter'), isNull);
      expect(t.korrektur('nare'), isNull);
    });

    test('was die Vervollständigung kann, macht sie — nicht der Vertipper', () {
      // ⚠️ „trimiteti" und „sedinta" liefern hier null, und das ist richtig:
      // sie sind Wortanfänge von „trimiteți" und „ședința" und werden von
      // [WortIndex] abgedeckt. Der Vertipper ist nur für das zuständig, was
      // Anfang von gar nichts ist.
      expect(t.korrektur('trimiteti'), isNull);
      expect(t.korrektur('sedinta'), isNull);
      expect(index.vorschlaege('trimiteti'), contains('trimiteți'));
      expect(index.vorschlaege('sedinta'), contains('ședința'));
    });

    test('fasst KEIN richtiges Wort an', () {
      // ⚠️ Die Gegenprobe, die zählt. Gemessen über die 4.000 häufigsten
      // Wörter: null Eingriffe.
      var angefasst = 0;
      for (final w in woerter.take(4000)) {
        if (t.korrektur(w) != null) angefasst++;
      }
      expect(angefasst, 0);
    });

    test('fasst Fremdwörter und Namen im Satz nicht an', () {
      // ⚠️ Für sich genommen greift der Vertipper bei „Bescheid" (》Deschid《
      // ist einen Schritt entfernt) und bei „Padurean" (》pădurean《 ist ein
      // rumänisches Wort). Was sie rettet, ist der große Anfangsbuchstabe
      // mitten im Satz — deshalb wird hier der ECHTE Weg geprüft und nicht
      // die Einzelteile.
      const fremd = ['Duinea', 'Padurean', 'Tanase', 'Menning', 'Anica',
        'Vollmacht', 'Landratsamt', 'Jobcenter', 'Krankenkasse',
        'Widerspruch', 'Pflegegrad', 'Bescheid', 'Termin', 'Antrag',
        'Rente', 'Formular', 'WhatsApp', 'ICD360S', 'Ulm', 'Bayern'];
      WortlisteService.setzenFuerTest(index, regeln, t);
      final getroffen = <String>[];
      for (final w in fremd) {
        final satz = 'am scris la $w';
        if (autoKorrigiert(satz) != satz) getroffen.add(w);
      }
      expect(getroffen, isEmpty, reason: 'getroffen: $getroffen');
    });

    test('eine Korrektur bleibt unter 15 Millisekunden', () {
      // Sie läuft einmal je Wortende, nicht je Tastendruck. Gemessen über
      // 4.000 Wörter: 2,97 ms im Schnitt; der teuerste Fall ist ein langes
      // Wort ohne jede Ähnlichkeit, weil dort nichts früh abbricht.
      final uhr = Stopwatch()..start();
      for (final w in ['dovument', 'cerrere', 'xyzabcdef', 'trimiter']) {
        t.korrektur(w);
      }
      uhr.stop();
      expect(uhr.elapsedMicroseconds / 4, lessThan(15000));
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
