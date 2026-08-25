import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/arzt_quelle.dart';

void main() {
  // Echte Zeile aus kliniken_datenbank (id 10 = Gastroenterologie BwKrhs Ulm).
  Map<String, dynamic> klinikZeile() => {
        'id': 10,
        'name': 'Klinik für Innere Medizin – Gastroenterologie und Endoskopie',
        'fachrichtung': 'Gastroenterologie',
        'krankenhaus': 'Bundeswehrkrankenhaus Ulm',
        'strasse': 'Oberer Eselsberg 40',
        'plz_ort': '89081 Ulm',
        'telefon': '0731 1710-1180',
        'fax': '0731 1710294-1188',
        'email': 'BwKrhsUlmInnereGastroenterologie@bundeswehr.org',
        'online_termin_url': null,
      };

  // Zeile aus einer Praxis-Tabelle — dieselbe id, alles andere anders.
  Map<String, dynamic> praxisZeile() => {
        'id': 10,
        'praxis_name': 'Gemeinschaftspraxis Musterstraße',
        'arzt_name': 'Dr. med. Erika Muster',
        'fachrichtung': 'Allgemeinmedizin',
        'strasse': 'Musterstraße 1',
        'plz_ort': '89073 Ulm',
        'telefon': '0731 111111',
      };

  group('klinikAlsArzt', () {
    test('bildet auf die Feldnamen der Arzt-Widgets ab', () {
      final a = klinikAlsArzt(klinikZeile());
      expect(a['arzt_name'], 'Klinik für Innere Medizin – Gastroenterologie und Endoskopie');
      expect(a['praxis_name'], 'Bundeswehrkrankenhaus Ulm');
      expect(a['online_termin_url'], '');
    });

    test('behält alle Ursprungsfelder — Fax und E-Mail dürfen nicht verloren gehen', () {
      final a = klinikAlsArzt(klinikZeile());
      expect(a['fax'], '0731 1710294-1188');
      expect(a['email'], 'BwKrhsUlmInnereGastroenterologie@bundeswehr.org');
      expect(a['plz_ort'], '89081 Ulm');
    });

    test('setzt die Herkunftsmarke', () {
      expect(klinikAlsArzt(klinikZeile())[kArztQuelleFeld], kArztQuelleKliniken);
    });

    test('fällt auf name zurück, wenn krankenhaus leer ist', () {
      final a = klinikAlsArzt({'id': 2, 'name': 'Universitätsklinikum Ulm'});
      expect(a['praxis_name'], 'Universitätsklinikum Ulm');
    });
  });

  group('istKlinikEintrag', () {
    test('erkennt einen frisch markierten Klinik-Eintrag', () {
      expect(istKlinikEintrag(klinikAlsArzt(klinikZeile())), isTrue);
    });

    test('erkennt einen Praxis-Eintrag', () {
      expect(istKlinikEintrag(praxisZeile()), isFalse);
    });

    test('Altbestand ohne Marke: krankenhaus-Feld entscheidet', () {
      final alt = klinikZeile()..remove(kArztQuelleFeld);
      expect(alt.containsKey(kArztQuelleFeld), isFalse);
      expect(istKlinikEintrag(alt), isTrue);
    });

    test('eine fremde Marke gilt nicht als Klinik', () {
      final fremd = klinikZeile()..[kArztQuelleFeld] = 'aerzte';
      expect(istKlinikEintrag(fremd), isFalse);
    });

    test('leere Marke fällt auf die Feld-Erkennung zurück', () {
      final leer = praxisZeile()..[kArztQuelleFeld] = '';
      expect(istKlinikEintrag(leer), isFalse);
    });
  });

  test('der eigentliche Fehlerfall: gleiche id, zwei Tabellen, zwei Herkünfte', () {
    // Genau diese Konstellation hat den gespeicherten Klinik-Eintrag beim
    // Auffrischen durch eine wildfremde Praxis ersetzt.
    final klinik = klinikAlsArzt(klinikZeile());
    final praxis = praxisZeile();
    expect(klinik['id'], praxis['id']);
    expect(istKlinikEintrag(klinik), isNot(istKlinikEintrag(praxis)));
  });
}
