import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/mail_adressbuch.dart';

void main() {
  group('Antwort lesen', () {
    test('liest die flache Antwort des Servers', () {
      final a = mailKontakteAusAntwort({
        'success': true,
        'gesamt': 2,
        'kategorien': {'arzt': 1, 'behoerde': 1},
        'kontakte': [
          {
            'name': 'Praxis Dr. Meier, Ulm',
            'email': 'praxis@meier.de',
            'kategorie': 'arzt',
            'quelle': 'aerzte_datenbank',
            'eigen': false,
          },
          {
            'name': 'Jobcenter Ulm',
            'email': 'info@jobcenter-ulm.de',
            'kategorie': 'behoerde',
            'eigen': false,
          },
        ],
      });
      expect(a.gesamt, 2);
      expect(a.kontakte.length, 2);
      expect(a.kontakte.first.name, 'Praxis Dr. Meier, Ulm');
      expect(a.kontakte.first.quelle, 'aerzte_datenbank');
      expect(a.kategorien['arzt'], 1);
    });

    // ⚠️ Der Fall, der den Speedtest-Bildschirm am 05.08.2026 in Produktion
    // grau gemacht hat: PHP kennt nur einen Array-Typ, ein leeres `kategorien`
    // wird deshalb zu `[]` — also zu einer JSON-Liste, nicht zu einem Objekt.
    // Eine Suche ohne Treffer ist genau dieser Zustand, und sie ist normal.
    test('leere kategorien kommen als Liste und werfen nicht', () {
      final a = mailKontakteAusAntwort({
        'success': true,
        'gesamt': 0,
        'kategorien': <dynamic>[],
        'kontakte': <dynamic>[],
      });
      expect(a.gesamt, 0);
      expect(a.kategorien, isEmpty);
      expect(a.kontakte, isEmpty);
    });

    test('fehlende Felder ergeben eine leere Liste, keine Ausnahme', () {
      final a = mailKontakteAusAntwort({'success': true});
      expect(a.kontakte, isEmpty);
      expect(a.kategorien, isEmpty);
      expect(a.gesamt, 0);
    });

    test('Zeilen ohne Adresse oder ohne Namen fallen weg', () {
      final a = mailKontakteAusAntwort({
        'kontakte': [
          {'name': 'Ohne Adresse', 'email': ''},
          {'name': '', 'email': 'ohne@name.de'},
          {'name': 'Gut', 'email': 'gut@example.de'},
        ],
      });
      expect(a.kontakte.length, 1);
      expect(a.kontakte.single.email, 'gut@example.de');
    });

    test('gesamt fällt auf die Anzahl zurück, wenn der Server keins schickt', () {
      final a = mailKontakteAusAntwort({
        'kontakte': [
          {'name': 'A', 'email': 'a@b.de'},
        ],
      });
      expect(a.gesamt, 1);
    });
  });

  group('Kategoriename', () {
    test('kennt die üblichen Kennungen', () {
      expect(mailKategorieName('arzt'), 'Ärzte');
      expect(mailKategorieName('eigen'), 'Eigene Kontakte');
      expect(mailKategorieName(''), 'Sonstige');
      expect(mailKategorieName(null), 'Sonstige');
    });

    // Eine neue Tabelle auf dem Server soll sichtbar sein, auch wenn niemand
    // daran gedacht hat, sie hier einzutragen.
    test('reicht Unbekanntes durch, statt es zu verschlucken', () {
      expect(mailKategorieName('notariat'), 'notariat');
    });
  });

  group('Adressen aufteilen', () {
    test('trennt am Komma und wirft Leeres weg', () {
      expect(mailAdressenAufteilen('a@b.de, c@d.de'), ['a@b.de', 'c@d.de']);
      expect(mailAdressenAufteilen('a@b.de,'), ['a@b.de']);
      expect(mailAdressenAufteilen('  '), isEmpty);
      expect(mailAdressenAufteilen(''), isEmpty);
    });
  });

  group('Adressen anhängen', () {
    test('hängt an ein leeres Feld an', () {
      expect(mailAdressenAnhaengen('', ['a@b.de']), 'a@b.de');
    });

    // ⚠️ Der Kern der Sache: wer die erste Adresse schon getippt hat, darf sie
    // mit einem Griff ins Adressbuch nicht verlieren.
    test('ersetzt nichts, was schon im Feld steht', () {
      expect(
        mailAdressenAnhaengen('erste@x.de', ['zweite@y.de', 'dritte@z.de']),
        'erste@x.de, zweite@y.de, dritte@z.de',
      );
    });

    test('nimmt dieselbe Adresse kein zweites Mal auf', () {
      expect(mailAdressenAnhaengen('a@b.de', ['a@b.de']), 'a@b.de');
    });

    test('erkennt Doppelte unabhängig von Groß- und Kleinschreibung', () {
      // Die Schreibweise, die schon im Feld steht, bleibt stehen.
      expect(mailAdressenAnhaengen('Info@Amt.de', ['info@amt.de']), 'Info@Amt.de');
    });

    test('nimmt dieselbe Adresse auch innerhalb einer Auswahl nur einmal', () {
      expect(mailAdressenAnhaengen('', ['a@b.de', 'A@B.de']), 'a@b.de');
    });

    test('räumt Leerraum und leere Einträge weg', () {
      expect(
        mailAdressenAnhaengen('  a@b.de ,, ', ['  c@d.de  ', '', '   ']),
        'a@b.de, c@d.de',
      );
    });

    test('lässt das Feld unverändert, wenn nichts gewählt wurde', () {
      expect(mailAdressenAnhaengen('a@b.de, c@d.de', const []), 'a@b.de, c@d.de');
    });

    // Das Trennzeichen muss zu dem passen, was der Hinweis unter dem Feld sagt
    // und was `_firstInvalid` vor dem Senden prüft — sonst ist die eingesetzte
    // Adresse für die Prüfung eine einzige, kaputte.
    test('trennt mit Komma und Leerzeichen, wie das Feld es erwartet', () {
      final feld = mailAdressenAnhaengen('', ['a@b.de', 'c@d.de']);
      expect(feld, 'a@b.de, c@d.de');
      final regel = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
      for (final teil in feld.split(',')) {
        expect(regel.hasMatch(teil.trim()), isTrue, reason: teil);
      }
    });
  });
}
