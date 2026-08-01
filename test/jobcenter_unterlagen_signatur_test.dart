// Wann der Reiter „Unterlagen" ein Dokument (erneut) zur Unterschrift stellen
// darf, und ob ein Vorgang seiner Datei zugeordnet wird.
//
// Beides ist reine Regel, deshalb ohne Widget-Aufbau prüfbar — und
// prüfenswert, weil ein Fehler hier entweder das Mitglied mit doppelten
// Anforderungen behelligt oder den Status an der falschen Zeile anzeigt.
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/signatur_service.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_jobcenter.dart';

Signaturvorgang _vorgang({
  required String status,
  DateTime? fristBis,
  DateTime? signedAtUtc,
  String? quelleTabelle,
  int? quelleId,
}) =>
    Signaturvorgang(
      id: 1,
      dokumentTyp: kJcSignaturTypWba,
      dokumentTitel: 'WBA_Antrag_55_18.pdf',
      status: status,
      fristBis: fristBis,
      signedAtUtc: signedAtUtc,
      quelleTabelle: quelleTabelle,
      quelleId: quelleId,
    );

void main() {
  group('jcErneutAnfordernMoeglich', () {
    final morgen = DateTime.now().toUtc().add(const Duration(days: 7));
    final gestern = DateTime.now().toUtc().subtract(const Duration(days: 1));

    test('offen und in der Frist blockiert eine zweite Anforderung', () {
      // Sonst lägen beim Mitglied zwei gleiche Blätter und es müsste raten.
      expect(
        jcErneutAnfordernMoeglich(_vorgang(status: 'offen', fristBis: morgen)),
        isFalse,
      );
    });

    test('unterschrieben blockiert dauerhaft', () {
      expect(
        jcErneutAnfordernMoeglich(
            _vorgang(status: 'signiert', signedAtUtc: gestern)),
        isFalse,
      );
    });

    test('offen mit abgelaufener Frist lässt einen neuen Anlauf zu', () {
      // Der Server stellt den Status erst beim nächsten Zugriff auf
      // „abgelaufen" — bis dahin wäre der Knopf sonst gesperrt, ohne dass
      // irgendjemand etwas dagegen tun könnte.
      expect(
        jcErneutAnfordernMoeglich(_vorgang(status: 'offen', fristBis: gestern)),
        isTrue,
      );
    });

    test('abgelehnt, widerrufen und abgelaufen lassen einen neuen Anlauf zu', () {
      for (final status in ['abgelehnt', 'widerrufen', 'abgelaufen']) {
        expect(
          jcErneutAnfordernMoeglich(_vorgang(status: status)),
          isTrue,
          reason: 'Status $status ist beendet, ein neuer Anlauf muss gehen',
        );
      }
    });

    test('offen ohne Frist bleibt gesperrt', () {
      // Ohne Frist ist nichts abgelaufen — der Vorgang läuft noch.
      expect(
        jcErneutAnfordernMoeglich(_vorgang(status: 'offen')),
        isFalse,
      );
    });
  });

  group('Zuordnung zur abgelegten Datei', () {
    test('stammtAus trifft nur bei Tabelle UND ID', () {
      final v = _vorgang(
        status: 'offen',
        quelleTabelle: kJcSignaturQuelle,
        quelleId: 42,
      );
      expect(v.stammtAus(kJcSignaturQuelle, 42), isTrue);
      expect(v.stammtAus(kJcSignaturQuelle, 43), isFalse);
      expect(v.stammtAus('finanzen_kontoauszug', 42), isFalse);
    });

    test('ein Vorgang ohne Herkunft gehört zu keiner Datei', () {
      // Über den Dateinamen zu raten wäre der Fehler: er ist je Antrag
      // konstant, jede Neuerzeugung trüge denselben.
      final v = _vorgang(status: 'offen');
      expect(v.stammtAus(kJcSignaturQuelle, 42), isFalse);
    });

    test('fromJson liest die Herkunft, auch als Text', () {
      final v = Signaturvorgang.fromJson({
        'id': 7,
        'dokument_typ': kJcSignaturTypVm,
        'dokument_titel': 'AnlageVM_55_18.pdf',
        'status': 'offen',
        'quelle_tabelle': kJcSignaturQuelle,
        'quelle_id': '42', // MySQL liefert je nach Treiber Text
      });
      expect(v.quelleTabelle, kJcSignaturQuelle);
      expect(v.quelleId, 42);
      expect(v.stammtAus(kJcSignaturQuelle, 42), isTrue);
    });

    test('fehlende Herkunft kommt als null an, nicht als "null"', () {
      final v = Signaturvorgang.fromJson({
        'id': 8,
        'dokument_typ': 'sonstiges',
        'dokument_titel': 'x.pdf',
        'status': 'offen',
        'quelle_tabelle': null,
        'quelle_id': null,
      });
      expect(v.quelleTabelle, isNull);
      expect(v.quelleId, isNull);
    });
  });
}
