import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/logger_service.dart';

/// Der Protokollversand hielt sich selbst am Leben.
///
/// Hochladen → „Uploaded 2 logs to server" schreiben → diese Zeile landet in
/// der Warteschlange → beim nächsten Takt wird sie hochgeladen → „Uploaded 1
/// logs" → ohne Ende. Am Vormittag des 10.08.2026 standen im Serverprotokoll
/// 841 Übertragungen mit 2.665 Zeilen, davon 789 allein dieser Wortlaut.
///
/// Der Schaden war nicht die Datenmenge, sondern dass die Warteschlange NIE
/// leer wurde: `_uploadLogsToServer` kehrt bei leerer Warteschlange sofort
/// zurück, ohne Netzanfrage. Durch die Selbstprotokollierung kam es dazu nie —
/// in BEIDEN Isolaten, alle 30 Sekunden, rund um die Uhr.
void main() {
  group('Protokollversand', () {
    test('eine gewöhnliche Zeile wird zur Übertragung vorgemerkt', () {
      final log = LoggerService();
      final vorher = log.ausstehendeUebertragungen;

      log.info('Termin gespeichert', tag: 'TERMIN');

      expect(log.ausstehendeUebertragungen, vorher + 1);
    });

    test('der Versand protokolliert sich nicht selbst in die Warteschlange', () {
      final log = LoggerService();
      final vorher = log.ausstehendeUebertragungen;

      // Genau der Wortlaut, der die Schleife gedreht hat.
      log.debug('Uploaded 2 logs to server', tag: 'LOG');
      log.info('Log upload started for V27655 (every 30s)', tag: 'LOG');

      expect(log.ausstehendeUebertragungen, vorher,
          reason: 'Zeilen des Versands über den Versand dürfen die '
              'Warteschlange nicht füllen — sonst wird sie nie leer und der '
              'Takt funkt alle 30 Sekunden ins Leere.');
    });

    test('sie stehen aber weiterhin im Protokoll auf dem Gerät', () {
      final log = LoggerService();

      log.debug('Uploaded 7 logs to server', tag: 'LOG');

      expect(log.logs.last.message, contains('Uploaded 7 logs'),
          reason: 'Auf dem Gerät soll man den Versand weiterhin nachvollziehen '
              'können; nur verschickt wird er nicht.');
    });
  });
}
