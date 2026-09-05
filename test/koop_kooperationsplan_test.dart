import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/jobcenter_kooperationsplan_tab.dart';

/// Was hier festgehalten wird, kann sonst LAUTLOS auseinanderlaufen.
///
/// Das PHP des Servers liegt in keinem Repo. Diese Datei ist damit die einzige
/// Stelle im Baum, an der eine gebrochene Kopplung überhaupt auffallen kann —
/// dieselbe Rolle, die `chat_reaktionen_test.dart` für die Reaktions-Whitelist hat.
void main() {
  /// ⚠️ Zeilenkommentare weg, BEVOR im Quelltext gesucht wird. Sonst bestätigt
  /// ein Test eine auskommentierte Zeile — genau so blieb in der
  /// Bürgeramt-Gegenprobe eine abgeschaltete Bearer-Prüfung grün.
  String quelle(String pfad) {
    final ohneKommentar = File(pfad).readAsLinesSync().map((z) {
      final i = z.indexOf('//');
      return i < 0 ? z : z.substring(0, i);
    }).join('\n');
    /// ⚠️ Aneinandergrenzende Zeichenketten zusammenziehen. Dart fügt
    /// `'a ' 'b'` zu `'a b'` — im Quelltext stehen die Hälften aber auf zwei
    /// Zeilen, und eine Suche nach dem ganzen Satz findet nichts. Erst darüber
    /// gestolpert, als „KEIN Widerspruch" genau an der Umbruchstelle lag: der
    /// Text war da, der Test sagte nein. Ohne diesen Schritt zerbricht die
    /// Prüfung am nächsten `dart format`, nicht an einem echten Fehler.
    return ohneKommentar.replaceAll(RegExp(r"'\s*\n\s*'"), '');
  }

  final tab = quelle('lib/widgets/jobcenter_kooperationsplan_tab.dart');
  final api = quelle('lib/services/api_service.dart');

  group('Zugangswege', () {
    test('genau die drei ENUM-Werte des Servers', () {
      // ⚠️ Die Spalte `zugang_weg` ist ein ENUM. Ein vierter Schlüssel hier
      // ohne den passenden auf dem Server wird von MariaDB stillschweigend zu
      // '' gekürzt — der Zugangsweg wäre weg, ohne dass etwas fehlschlägt.
      expect(kKoopZugangswege.keys.toSet(), {'online', 'postalisch', 'persoenlich'});
    });

    test('jeder Weg hat ein Zeichen', () {
      for (final k in kKoopZugangswege.keys) {
        expect(kKoopZugangIcons.containsKey(k), isTrue, reason: 'Kein Icon für "$k"');
      }
    });

    test('jeder Status hat eine Beschriftung', () {
      expect(kKoopStatusLabel.keys.toSet(), {'offen', 'geprueft', 'beanstandet', 'erledigt'});
    });
  });

  group('Der Kriterienkatalog steht NICHT in Dart', () {
    test('keine eigene Kriterienliste im Reiter', () {
      // Der Server liefert `kriterien` und `gruppen` mit jeder Antwort. Eine
      // zweite Liste hier wäre eine zweite Wahrheit: der Server entscheidet,
      // welche Punkte für einen Plan und welche für einen Verwaltungsakt
      // gelten. Ein nur einseitig bekannter Schlüssel verschwände lautlos.
      for (final verboten in [
        'form_gemeinsam',
        'abgleich_zielberufe',
        'inhalt_eigenbem_konkret',
        'zumut_keine_behandlungspflicht',
      ]) {
        expect(tab.contains(verboten), isFalse,
            reason: 'Kriterien-Schlüssel "$verboten" darf nicht in Dart stehen — '
                'er kommt vom Server.');
      }
    });

    test('der Katalog wird aus der Antwort gelesen', () {
      expect(tab.contains("r['kriterien']"), isTrue);
      expect(tab.contains("r['gruppen']"), isTrue);
    });
  });

  group('Ein unsicherer Befund wird nie vorgehakt', () {
    test('unsicheres "nicht_erfuellt" landet auf offen', () {
      // ⚠️ Dieselbe Abwägung wie bei den Blutwerten: aus einem Bild gelesener
      // Text liefert plausible falsche Wörter. Ein vorgehakter Mangel wird zur
      // Beanstandung in einem Brief an eine Behörde, ohne dass ihn jemand
      // gelesen hat.
      expect(tab.contains("(unsicher && stand == 'nicht_erfuellt') ? 'unklar' : stand"), isTrue,
          reason: 'Die Regel "unsicher => offen" fehlt in _vorpruefen.');
    });

    test('der vermutete Mangel bleibt sichtbar', () {
      // Nicht vorhaken heisst nicht verschweigen — sonst geht der Hinweis
      // verloren und niemand sieht im Dokument nach.
      expect(tab.contains("'vermutet'"), isTrue);
      expect(tab.contains('Vermuteter Mangel'), isTrue);
    });

    test('Anfassen durch einen Menschen setzt die Quelle auf "hand"', () {
      expect(tab.contains("'quelle': 'hand'"), isTrue);
    });
  });

  group('Die Vollmacht wird auf den RICHTIGEN Punkt geprüft', () {
    test('der Reiter spricht von "Eingliederungsvereinbarung ändern"', () {
      // ⚠️ Nicht der Termin-Maßstab. Dieses Schreiben verlangt die ÄNDERUNG des
      // Plans; in der Vollmacht heisst der Punkt "Eingliederungsvereinbarung
      // abschließen / ändern / aufheben" (Schlüssel `egv`). Mit dem
      // Termin-Maßstab beriefe sich der Brief auf eine Vollmacht, die nur zum
      // Mitgehen ins Gespräch ermächtigt.
      expect(tab.contains('Eingliederungsvereinbarung ändern'), isTrue);
    });

    test('ohne Vollmacht behauptet der Text nichts über die Akte des Amtes', () {
      expect(tab.contains('behauptet deshalb nicht, sie liege dem Amt vor'), isTrue);
    });
  });

  group('Endpunkte und Zeitgrenzen', () {
    test('alle Aktionen gehen an denselben Endpunkt', () {
      expect(api.contains('admin/jobcenter_av_kooperationsplan.php'), isTrue);
      for (final a in ['list', 'kontext', 'save', 'delete', 'pruefen',
                       'pruefung_speichern', 'pruefung_lesen', 'beanstandungen']) {
        expect(api.contains("'action': '$a'"), isTrue, reason: 'Aktion "$a" fehlt');
      }
    });

    test('Prüfung und Upload bekommen viel Zeit', () {
      // ⚠️ Hinter beiden läuft bei einem Scan die Texterkennung: ein bis zwei
      // Sekunden je Seite. Mit den üblichen 15 Sekunden bräche der Aufruf ab,
      // und das sähe aus wie ein Fehlschlag, obwohl die Datei längst
      // verschlüsselt in der Datenbank liegt.
      expect(api.contains('sekunden: 300'), isTrue);
      expect(api.contains('Duration(seconds: 300)'), isTrue);
    });

    test('der Upload trägt den Bearer mit', () {
      // MultipartRequest setzt die Kopfzeilen selbst. Fehlt addAll(_headers),
      // geht nur der Geräteschlüssel hinaus und der Server antwortet 401 —
      // genau die Regression aus PR #508.
      expect(api.contains('request.headers.addAll(_headers)'), isTrue);
    });
  });

  group('Der Versand hat Bremsen', () {
    test('vor dem Fax wird gefragt', () {
      // ⚠️ Ein Fax an eine Behörde geht sofort hinaus und ist nicht
      // zurückholbar. Ohne Rückfrage wäre ein Fehlgriff endgültig.
      expect(tab.contains('Fax jetzt senden?'), isTrue);
      expect(tab.contains('nicht'), isTrue);
    });

    test('ohne tragende Vollmacht wird gewarnt', () {
      // Sonst faxt jemand einen Brief hinaus, der die Unterschrift des
      // Mitglieds bräuchte — und hält die Sache für erledigt.
      expect(tab.contains('braucht dessen Unterschrift'), isTrue);
    });

    test('beim Verwaltungsakt steht, dass keine Frist gewahrt wird', () {
      // ⚠️ Der gefährlichste Punkt der ganzen Funktion. Ein Änderungsschreiben
      // ist kein Widerspruch; wer sich darauf verlässt, verliert die Frist.
      // Der Satz muss ZWEIMAL dastehen: auf der Seite und in der Rückfrage.
      expect('KEIN Widerspruch'.allMatches(tab).length >= 2, isTrue,
          reason: 'Der Hinweis fehlt auf der Seite oder in der Rückfrage.');
      expect(tab.contains('wahrt keine Frist'), isTrue);
    });

    test('der Brief lässt sich vor dem Senden ansehen', () {
      expect(tab.contains('PDF ansehen'), isTrue);
      expect(tab.contains('Vor dem Senden ansehen'), isTrue);
    });

    test('Brief und Fax gehen an den Endpunkt', () {
      expect(api.contains("'action': 'brief_pdf'"), isTrue);
      expect(api.contains("'action': 'fax_senden'"), isTrue);
    });
  });

  group('Datumsanzeige', () {
    test('ISO wird deutsch', () {
      expect(koopDatumDe('2026-08-12'), '12.08.2026');
    });
    test('leer bleibt leer', () {
      expect(koopDatumDe(null), '');
      expect(koopDatumDe(''), '');
    });
    test('was kein Datum ist, bleibt stehen statt zu verschwinden', () {
      expect(koopDatumDe('unbekannt'), 'unbekannt');
    });
  });
}
