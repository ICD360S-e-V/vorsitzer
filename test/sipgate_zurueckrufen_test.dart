import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';

/// Der Knopf „Zurückrufen" im Verlauf füllte bis zum 25.08.2026 nur das
/// Eingabefeld — man musste danach unter der Tastatur ein zweites Mal auf
/// „Anrufen" drücken. Auf dem Rechner tat er sogar gar nichts: dort wird der
/// Verlauf angezeigt, das Wählfeld aber nicht.
///
/// Und er hakte den verpassten Anruf als erledigt ab, OHNE dass jemand
/// angerufen hatte. Wer danach nicht auch noch „Anrufen" drückte, hatte den
/// Anruf aus dem Abzeichen genommen und nie zurückgerufen — genau das, was das
/// Abzeichen verhindern soll.
///
/// Diese Regel entscheidet beides: ob die Zeile hervorgehoben wird und ob das
/// Zurückrufen abhakt. Sie steht deshalb an einer Stelle statt an zweien.
void main() {
  Map<String, dynamic> zeile({
    String richtung = 'ein',
    String status = 'verpasst',
    Object? gesehen = false,
  }) =>
      {'richtung': richtung, 'status': status, 'gesehen': gesehen};

  group('was offen ist', () {
    test('ein verpasster eingehender Anruf', () {
      expect(sipgateVerpasstOffen(zeile()), isTrue);
    });

    test('auch einer, der auf klingelt stehen blieb', () {
      // Drei Zeilen stehen dauerhaft darauf, weil die App mitten im Läuten
      // abgeräumt wurde. Die sind so gut verpasst wie ein `verpasst`.
      expect(sipgateVerpasstOffen(zeile(status: 'klingelt')), isTrue);
    });
  });

  group('was nicht offen ist', () {
    test('ein abgehakter', () {
      expect(sipgateVerpasstOffen(zeile(gesehen: true)), isFalse);
    });

    test('ein abgelehnter — wegdrücken ist eine Entscheidung', () {
      expect(sipgateVerpasstOffen(zeile(status: 'abgelehnt')), isFalse);
    });

    test('ein beendeter', () {
      expect(sipgateVerpasstOffen(zeile(status: 'beendet')), isFalse);
    });

    test('ein ausgehender — auch wenn er verpasst heisst', () {
      // Ausgehend „verpasst" bedeutet: der andere ist nicht rangegangen. Das
      // gehört nicht in ein Abzeichen, das an Rückrufe erinnert.
      expect(sipgateVerpasstOffen(zeile(richtung: 'aus')), isFalse);
      expect(
        sipgateVerpasstOffen(zeile(richtung: 'aus', status: 'klingelt')),
        isFalse,
      );
    });
  });

  group('Randfälle aus echten Antworten', () {
    test('fehlendes `gesehen` heisst offen, nicht abgehakt', () {
      // Eine ältere Serverantwort ohne das Feld darf den Anruf nicht
      // stillschweigend als erledigt zählen.
      expect(sipgateVerpasstOffen({'richtung': 'ein', 'status': 'verpasst'}),
          isTrue);
    });

    test('`gesehen: null` ebenso', () {
      expect(sipgateVerpasstOffen(zeile(gesehen: null)), isTrue);
    });

    test('eine leere Zeile bringt nichts zum Leuchten', () {
      expect(sipgateVerpasstOffen(const <String, dynamic>{}), isFalse);
    });

    test('ein unbekannter Status zählt nicht mit', () {
      expect(sipgateVerpasstOffen(zeile(status: 'irgendwas')), isFalse);
    });

    test('`unklar` zählt nicht mit', () {
      // Der Server vergibt es, wenn eine Zeile zwölf Stunden lang unfertig
      // liegenblieb. Ein eingehender Anruf, der nur geläutet hat, wird dabei
      // zu `verpasst` — was hier als `unklar` ankommt, war schon verbunden
      // oder ging hinaus. Kein Rückruf offen.
      expect(sipgateVerpasstOffen(zeile(status: 'unklar')), isFalse);
    });
  });

  /// ⚠️ Dieselbe Frage beantwortet `sipgateVerpasstZaehlen()` in SQL, und dort
  /// gilt zusätzlich eine Altersgrenze: `klingelt` zählt erst nach fünf
  /// Minuten. Hier stand sie nicht — für eine Zeile, die GERADE klingelt, gaben
  /// die beiden also verschiedene Antworten.
  ///
  /// Nachrechnen kann der Client sie auch nicht: `begonnen_am` schreibt MySQL
  /// (Europe/Berlin), PHP steht auf UTC — gemessen am 30.08.2026 zwei Stunden
  /// Abstand. Deshalb liefert der Server das Ergebnis je Zeile mit, und es hat
  /// Vorrang.
  group('der Server hat das letzte Wort', () {
    test('`verpasst_offen: true` gewinnt gegen die lokale Regel', () {
      // Lokal wäre das ein klares Nein — ausgehend und abgehakt.
      final z = zeile(richtung: 'aus', status: 'beendet', gesehen: true);
      expect(sipgateVerpasstOffen(z), isFalse);
      z['verpasst_offen'] = true;
      expect(sipgateVerpasstOffen(z), isTrue);
    });

    test('`verpasst_offen: false` gewinnt ebenso', () {
      // Genau der Fall, um den es geht: ein Anruf, der in dieser Sekunde
      // läutet. Lokal „offen", der Server sagt nein — und der Server hat die
      // Uhr, mit der die Fünf-Minuten-Grenze überhaupt zu rechnen ist.
      final z = zeile(status: 'klingelt');
      expect(sipgateVerpasstOffen(z), isTrue);
      z['verpasst_offen'] = false;
      expect(sipgateVerpasstOffen(z), isFalse);
    });

    test('auch als Zahl, nicht nur als bool', () {
      // Der Wert kommt aus einem SQL-Ausdruck; ob PHP daraus `true` oder `1`
      // macht, hängt daran, wie er entstanden ist. Ein `as bool` hätte hier
      // erst beim Benutzer geworfen.
      expect(sipgateVerpasstOffen(zeile()..['verpasst_offen'] = 0), isFalse);
      expect(
        sipgateVerpasstOffen(zeile(status: 'beendet')..['verpasst_offen'] = 1),
        isTrue,
      );
    });

    test('eine ältere Serverfassung ohne das Feld fällt auf die alte Regel', () {
      // Ohne Rückfall bliebe der Verlauf dort ganz ohne Hervorhebung — und das
      // Abhaken hinge an einem Feld, das gar nicht ankommt.
      expect(sipgateVerpasstOffen(zeile()), isTrue);
      expect(sipgateVerpasstOffen(zeile()..['verpasst_offen'] = null), isTrue);
    });
  });
}
