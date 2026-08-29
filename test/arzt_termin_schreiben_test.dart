import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/arzt_termin_schreiben.dart';

/// ⚠️ Wörtliche Kopie der Server-Whitelist aus
/// `api/helpers/arzt_termin_schreiben.php`.
///
/// Das PHP liegt in keinem Repo — dieser Test ist die einzige Stelle, an der
/// eine Abweichung überhaupt auffallen kann. Wer den Katalog auf dem Server
/// ändert, ändert ihn hier mit.
///
/// Warum auch die BESCHRIFTUNGEN und nicht nur die Schlüssel: den Brief setzt
/// der Server aus SEINER Tabelle. Driften die Texte auseinander, hakt man in
/// der App das eine an und verschickt das andere — und das fällt niemandem
/// auf, weil beide Seiten für sich stimmig aussehen. Dasselbe Verfahren wie
/// in `jc_termin_gruende_test.dart`.
const Map<String, String> _serverBestaetigen = {
  'begleitung': 'Eine Begleitperson des Vereins kommt mit',
  'dolmetscher': 'Sprachmittlung durch die Begleitperson',
  'unterlagen': 'Die angeforderten Unterlagen werden mitgebracht',
  'ueberweisung': 'Die Überweisung wird mitgebracht',
  'versichertenkarte': 'Die Versichertenkarte wird mitgebracht',
  'barrierefrei': 'Es wird ein barrierefreier Zugang benötigt',
  'rollstuhl': 'Die Vorstellung erfolgt im Rollstuhl',
  'nuechtern': 'Rückfrage: muss zu diesem Termin nüchtern erschienen werden?',
};

const Map<String, String> _serverVerschieben = {
  'behoerdentermin': 'Zeitgleicher Pflichttermin bei einer Behörde',
  'arbeitszeit': 'Der Termin liegt in der Arbeitszeit',
  'begleitung':
      'Begleitung und Sprachmittlung durch den Verein nur in einem anderen Zeitfenster möglich',
  'anderer_arzt': 'Zeitgleicher Termin bei einer anderen Praxis oder Klinik',
  'pflege': 'Betreuungs- oder Pflegezeit (Kind, Angehörige)',
  'gesundheit': 'Gesundheitliche Einschränkung zu dieser Tageszeit',
  'fahrt': 'Anfahrt mit dem ÖPNV zur genannten Uhrzeit nicht möglich',
  'ortsabwesenheit': 'Ortsabwesenheit an diesem Tag',
  'sonstiges': 'Sonstiger Grund',
};

const Map<String, String> _serverAbsagen = {
  'krankheit': 'Akute Erkrankung',
  'krankenhaus': 'Stationärer Krankenhausaufenthalt',
  'kind_krank':
      'Erkrankung des Kindes, Betreuung nicht anderweitig sicherzustellen',
  'pflege': 'Akute Pflege oder Betreuung einer oder eines Angehörigen',
  'behoerdentermin': 'Zeitgleicher Pflichttermin bei einer Behörde',
  'anderer_arzt': 'Die Behandlung wurde zwischenzeitlich anderweitig erbracht',
  'nicht_mehr_noetig':
      'Die Beschwerden bestehen nicht mehr, der Termin wird nicht mehr benötigt',
  'verkehr': 'Unvorhergesehener Ausfall öffentlicher Verkehrsmittel',
  'sonstiges': 'Sonstiger Grund',
};

/// ⚠️ Wörtliche Kopie der ENUM-Werte der Spalte `status` aus der Migration
/// vom 29.08.2026. Ein Wert, den die Spalte nicht kennt, wird vom Endpunkt
/// mit HTTP 400 abgewiesen — und der Reiter zeigte dann „bestätigt", während
/// in der Akte weiter „offen" steht.
const Set<String> _serverStatus = {
  'offen',
  'bestaetigt',
  'verschoben',
  'abgesagt'
};

void main() {
  group('Kataloge stimmen mit dem Server überein', () {
    test('Bestätigung', () {
      expect(kAtsZusaetzeBestaetigen, _serverBestaetigen);
    });
    test('Verlegung', () {
      expect(kAtsGruendeVerschieben, _serverVerschieben);
    });
    test('Absage', () {
      expect(kAtsGruendeAbsagen, _serverAbsagen);
    });

    test('atsKatalog trifft für jede Art den richtigen Katalog', () {
      expect(atsKatalog('bestaetigen'), _serverBestaetigen);
      expect(atsKatalog('verschieben'), _serverVerschieben);
      expect(atsKatalog('absagen'), _serverAbsagen);
      // Unbekannte Art → leer, nicht etwa der erstbeste Katalog.
      expect(atsKatalog('quatsch'), isEmpty);
    });
  });

  group('Status', () {
    test('jede Art setzt einen Status, den die Spalte kennt', () {
      for (final art in kAtsArten.keys) {
        expect(_serverStatus, contains(atsStatusFuer(art)),
            reason: 'Status für "$art" ist der Datenbank unbekannt');
      }
    });

    test('jeder Status hat eine Beschriftung', () {
      // Sonst stünde im Reiter der rohe Schlüssel — „bestaetigt" statt
      // „Bestätigt".
      for (final s in _serverStatus) {
        expect(kAtsStatusLabel.containsKey(s), isTrue, reason: 'ohne Text: $s');
      }
    });

    test('die drei Arten setzen drei VERSCHIEDENE Status', () {
      final gesetzt = kAtsArten.keys.map(atsStatusFuer).toSet();
      expect(gesetzt.length, kAtsArten.length);
      expect(gesetzt, isNot(contains('offen')));
    });
  });

  group('Prüfung', () {
    test('unbekannte Art wird abgewiesen', () {
      expect(
          atsSchreibenPruefen(art: 'quatsch', gruende: [], freitext: ''),
          isNotNull);
    });

    test('unbekannter Grund wird abgewiesen', () {
      expect(
          atsSchreibenPruefen(
              art: 'absagen', gruende: ['gibt_es_nicht'], freitext: ''),
          isNotNull);
    });

    test('Verlegung und Absage brauchen einen Grund', () {
      for (final art in ['verschieben', 'absagen']) {
        expect(atsSchreibenPruefen(art: art, gruende: [], freitext: ''),
            isNotNull,
            reason: '$art ohne Grund muss scheitern');
        // Freitext allein reicht — die Liste trifft nicht jeden Fall.
        expect(
            atsSchreibenPruefen(
                art: art, gruende: [], freitext: 'Kind ist krank'),
            isNull);
      }
    });

    test('eine Bestätigung braucht KEINEN Zusatz', () {
      // ⚠️ Der Kern der Sache: eine Bestätigung bestätigt bloß. Ein Zwang zum
      // Ankreuzen hätte dazu geführt, dass irgendein Zusatz gewählt wird, nur
      // damit der Knopf angeht — und dann steht im Brief an die Praxis eine
      // Zusage, die niemand geben wollte.
      expect(
          atsSchreibenPruefen(art: 'bestaetigen', gruende: [], freitext: ''),
          isNull);
    });

    test('gültige Kombination geht durch', () {
      expect(
          atsSchreibenPruefen(
              art: 'bestaetigen',
              gruende: ['begleitung', 'barrierefrei'],
              freitext: ''),
          isNull);
    });

    test('Leerzeichen zählen nicht als Freitext', () {
      expect(
          atsSchreibenPruefen(art: 'absagen', gruende: [], freitext: '   '),
          isNotNull);
    });
  });
}
