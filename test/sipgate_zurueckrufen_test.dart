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
  });
}
