import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/terminanfrage_pdf.dart';
import 'package:icd360sev_vorsitzer/utils/terminanfrage_vorlagen.dart';

/// ⚠️ Die Seitenzahl kommt aus dem Dokument, NICHT aus den Bytes. Der erste
/// Anlauf suchte `/Type /Page` im Rohtext und zählte immer null, weil das
/// Paket die Objektströme komprimiert — ein Test, der stillschweigend null
/// zählt, hätte jede Zweiseitigkeit durchgewinkt.

/// Der längste Brief, den die Oberfläche überhaupt erzeugen kann: alle
/// Zusätze an, mehrere Gründe, Beleg mit Frist, Begleitung, voller
/// Angabenblock. Wenn DER auf ein Blatt passt, passt jeder.
const _laengster = TerminanfrageDaten(
  arztTyp: 'gesundheit_sanitaetshaus',
  vorname: 'Ilieș-Cristian',
  nachname: 'Düinea-Müller',
  geburtsdatum: '14.03.1985',
  strasse: 'Musterstraße 12',
  plz: '89073',
  ort: 'Ulm',
  krankenkasse: 'AOK Baden-Württemberg',
  versichertennummer: 'A123456789',
  praxisName: 'Sanitätshaus Beispiel GmbH',
  praxisStrasse: 'Bahnhofstraße 4',
  praxisPlzOrt: '89073 Ulm',
  anlaesse: [
    'Rezept einlösen',
    'Hausbesuch erforderlich',
    'Hilfsmittel drückt / passt nicht',
  ],
  ueberweisungLiegtVor: true,
  begleitung: true,
  erfassteTermine: 0,
  rueckantwortFax: '+49 731 80159737',
  rueckantwortTelefon: '0731 80159736',
  vereinsname: 'ICD360S e.V.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('das Ergebnis ist ein PDF — sonst lehnt sipgate es ab', () async {
    // `api/sipgate/sipgate_fax.php` prüft die %PDF-Kennung VOR dem Hochladen.
    final b = await terminanfragePdf(
        vorlage: TerminanfrageVorlage.erstvorstellung,
        daten: _laengster,
        datum: '20.08.2026');
    expect(String.fromCharCodes(b.take(5)), '%PDF-');
  });

  test('auch der längste Brief passt auf ein Blatt', () async {
    // 🔴 Vorher landete bei genau diesem Brief die Grußformel auf Seite 1 und
    // der NAME allein auf Seite 2 — `MultiPage` darf eine `Column` zwischen
    // ihren Kindern trennen. Ein Fax, dessen zweite Seite aus einem Wort
    // besteht, kostet eine Seite Übertragung und sieht nach Fehler aus.
    for (final v in TerminanfrageVorlage.values) {
      var seiten = 0;
      await terminanfragePdf(
          vorlage: v,
          daten: _laengster,
          datum: '20.08.2026',
          empfaengerFax: '+49 731 1234567',
          seitenzahl: (n) => seiten = n);
      expect(seiten, 1, reason: 'Vorlage ${v.titel} braucht zwei Seiten');
    }
  });

  group('Dateiname', () {
    test('rumänische Diakritika werden umgeschrieben, nicht verschluckt', () {
      // ⚠️ Der Name geht als `filename` an sipgate und steht später im
      // Sendebericht. `Ionuț` wurde vorher zu `Ionu_`.
      expect(terminanfrageDateiname(_laengster, '20.08.2026'),
          'Terminanfrage_Dueinea-Mueller_Ilies-Cristian_20-08-2026.pdf');
    });

    test('der Name bleibt reines ASCII', () {
      const kyrillisch = TerminanfrageDaten(
          arztTyp: 'gesundheit_hausarzt',
          vorname: 'Олена',
          nachname: 'Шевченко');
      final n = terminanfrageDateiname(kyrillisch, '01.01.2026');
      expect(n.codeUnits.every((c) => c < 128), isTrue, reason: n);
      expect(n.endsWith('.pdf'), isTrue);
    });
  });
}
