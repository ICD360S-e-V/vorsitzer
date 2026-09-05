import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/kuendigung_schreiben.dart';

KuendigungsDaten _d({
  String nummer = '11 O144 1465 1269',
  String label = 'Versicherungsscheinnummer',
  KuendigungsArt art = KuendigungsArt.naechstmoeglich,
  String zumDatum = '',
  String grund = '',
  KuendigungsUnterzeichner wer = KuendigungsUnterzeichner.mitglied,
  bool sepa = true,
  String kunde = '',
  String ruf = '',
  String zusatz = '',
}) =>
    KuendigungsDaten(
      empfaengerName: 'Generali Deutschland Versicherung AG',
      empfaengerStrasse: 'Adenauerring 7',
      empfaengerPlzOrt: '81737 München',
      absenderName: 'Olena Musterenko',
      absenderStrasse: 'Schönfeldstr. 6',
      absenderPlzOrt: '89155 Erbach',
      vertragsBezeichnung: 'Unfallversicherung',
      vertragsNummer: nummer,
      nummerLabel: label,
      kundenNummer: kunde,
      rufNummer: ruf,
      art: art,
      zumDatum: zumDatum,
      grund: grund,
      unterzeichner: wer,
      vereinName: 'ICD360S e.V.',
      bestaetigungAn: 'icd@icd360s.de',
      sepaWiderrufen: sepa,
      zusatz: zusatz,
      datum: '29.08.2026',
    );

void main() {
  group('Betreff', () {
    test('trägt Bezeichnung und Nummer', () {
      expect(kuendigungBetreff(_d()),
          'Kündigung · Unfallversicherung · Versicherungsscheinnummer: 11 O144 1465 1269');
    });

    // ⚠️ Ohne Nummer darf die Zeile nicht mit einem leeren „: " enden — das
    // sieht nach abgeschnittenem Text aus und lädt die Poststelle ein, das
    // Schreiben liegen zu lassen.
    test('ohne Nummer bleibt der Betreff sauber', () {
      final b = kuendigungBetreff(_d(nummer: ''));
      expect(b, 'Kündigung · Unfallversicherung');
      expect(b.endsWith(':'), isFalse);
    });
  });

  group('Brieftext', () {
    test('nennt die Nummer auch im Fliesstext', () {
      // Der Betreff kann beim Weiterleiten wegfallen; der Vertrag muss am
      // Text erkennbar bleiben.
      expect(kuendigungBrieftext(_d()), contains('11 O144 1465 1269'));
    });

    test('enthält immer die Hilfskündigung', () {
      for (final a in KuendigungsArt.values) {
        final t = kuendigungBrieftext(_d(art: a, grund: 'Beitragserhöhung'));
        expect(t, contains('hilfsweise zum nächstzulässigen Termin'),
            reason: 'fehlt bei $a');
      }
    });

    test('widerspricht der stillschweigenden Verlängerung', () {
      expect(kuendigungBrieftext(_d()),
          contains('stillschweigenden Verlängerung'));
    });

    test('zum Datum übernimmt das Datum', () {
      expect(
          kuendigungBrieftext(
              _d(art: KuendigungsArt.zumDatum, zumDatum: '17.06.2027')),
          contains('zum 17.06.2027'));
    });

    test('ISO-Datum wird deutsch geschrieben', () {
      expect(
          kuendigungBrieftext(
              _d(art: KuendigungsArt.zumDatum, zumDatum: '2027-06-17')),
          contains('zum 17.06.2027'));
    });

    // ⚠️ Ein leeres Datum darf NICHT zu „zum ." werden. Dann stünde eine
    // Kündigung ohne Termin im Schreiben, und der Empfänger dürfte sich den
    // Termin aussuchen.
    test('zum Datum ohne Datum fällt auf nächstmöglich zurück', () {
      final t = kuendigungBrieftext(_d(art: KuendigungsArt.zumDatum));
      expect(t, contains('zum nächstmöglichen Zeitpunkt'));
      expect(t, isNot(contains('zum .')));
    });

    test('außerordentlich nennt den Grund', () {
      final t = kuendigungBrieftext(_d(
          art: KuendigungsArt.ausserordentlich, grund: 'Beitragserhöhung'));
      expect(t, contains('außerordentlich'));
      expect(t, contains('Grund: Beitragserhöhung.'));
    });

    test('SEPA-Widerruf ist abschaltbar', () {
      expect(kuendigungBrieftext(_d()), contains('SEPA-Lastschriftmandat'));
      expect(kuendigungBrieftext(_d(sepa: false)),
          isNot(contains('SEPA-Lastschriftmandat')));
    });

    test('Kunden- und Rufnummer kommen mit, wenn vorhanden', () {
      final t = kuendigungBrieftext(_d(kunde: 'K-4711', ruf: '0731 123456'));
      expect(t, contains('Kundennummer K-4711'));
      expect(t, contains('Rufnummer 0731 123456'));
    });

    test('leere Zusatzfelder erzeugen keine leeren Klammern', () {
      expect(kuendigungBrieftext(_d(nummer: '', kunde: '', ruf: '')),
          isNot(contains('()')));
    });

    // ⚠️ Der Vollmachtssatz gehört NUR in die Vereinsfassung. Steht er unter
    // einer Kündigung, die das Mitglied selbst unterschreibt, behauptet das
    // Schreiben eine Stellvertretung, die es gar nicht gibt — und lädt den
    // Empfänger zur Zurückweisung nach § 174 BGB geradezu ein.
    test('Vollmachtssatz nur, wenn der Verein unterschreibt', () {
      expect(kuendigungBrieftext(_d()), isNot(contains('Vollmacht')));
      final v =
          kuendigungBrieftext(_d(wer: KuendigungsUnterzeichner.verein));
      expect(v, contains('Vollmacht'));
      expect(v, contains('ICD360S e.V.'));
      expect(v, contains('i. V. für Olena Musterenko'));
    });

    test('Mitgliedsfassung unterschreibt mit dem Namen des Inhabers', () {
      final t = kuendigungBrieftext(_d());
      expect(t.trimRight().endsWith('Olena Musterenko'), isTrue);
      expect(t, isNot(contains('i. V.')));
    });

    test('Zusatzsätze landen vor der Grußformel', () {
      final t = kuendigungBrieftext(_d(zusatz: 'Bitte um Aktenzeichen.'));
      expect(t.indexOf('Bitte um Aktenzeichen.'),
          lessThan(t.indexOf('Mit freundlichen Grüßen')));
    });
  });

  group('Pflichtangaben', () {
    test('vollständige Daten melden nichts', () {
      expect(kuendigungFehlendeAngaben(_d()), isEmpty);
    });

    test('ohne Nummer wird die Nummer mit ihrem Label gemeldet', () {
      expect(kuendigungFehlendeAngaben(_d(nummer: '')),
          contains('Versicherungsscheinnummer'));
      expect(
          kuendigungFehlendeAngaben(
              _d(nummer: '', label: 'Vertragsnummer')),
          contains('Vertragsnummer'));
    });

    test('außerordentlich ohne Grund wird gemeldet', () {
      expect(
          kuendigungFehlendeAngaben(_d(art: KuendigungsArt.ausserordentlich)),
          contains('Grund der außerordentlichen Kündigung'));
    });
  });

  group('Beschriftung der Nummer', () {
    test('Versicherung heißt Versicherungsscheinnummer', () {
      expect(kuendigungNummerLabel('versicherung'), 'Versicherungsscheinnummer');
    });
    test('alles andere heißt Vertragsnummer', () {
      for (final k in ['handy', 'multimedia', 'strom', '']) {
        expect(kuendigungNummerLabel(k), 'Vertragsnummer');
      }
    });
  });

  group('Datumsumwandlung', () {
    test('ISO wird deutsch', () {
      expect(kuendigungDatumDeutsch('2027-06-17'), '17.06.2027');
    });
    test('deutsches Datum bleibt unangetastet', () {
      expect(kuendigungDatumDeutsch('17.06.2027'), '17.06.2027');
    });
    test('Unsinn bleibt Unsinn statt zu werfen', () {
      expect(kuendigungDatumDeutsch('bald'), 'bald');
      expect(kuendigungDatumDeutsch(''), '');
    });
  });

  // ⚠️ Der Text landet als PDF im Fax, und dort steht ihm nur Helvetica zur
  // Verfügung — die kann ausschliesslich WinAnsi (CP1252). Ein Zeichen
  // ausserhalb davon wird zu einem leeren Kästchen, und zwar erst auf dem
  // gedruckten Blatt beim Empfänger: `flutter analyze` sieht nichts, die
  // Vorschau am Bildschirm sieht richtig aus. Derselbe Fehler ist im
  // Blutwerte-Bericht schon einmal passiert (Pfeile ↑↓ als Kästchen).
  group('faxtauglich', () {
    // ⚠️ NUR Latin-1, nicht CP1252. Der Unterschied ist gemessen, nicht
    // angenommen: ein Probe-PDF mit allen 27 Zeichen des Blocks
    // 0x80–0x9F ergab 27 schwarze Kästchen — €, „, ", …, –, —, ™ und der
    // Rest. Die erste Fassung dieses Tests erlaubte den Block und liess
    // damit genau den Gedankenstrich durch, der im Betreff dann als
    // Kästchen stand. Wer hier etwas hinzufügt, rendert es vorher.
    bool latin1(int c) =>
        (c >= 0x20 && c <= 0x7E) || c == 0x0A || (c >= 0xA0 && c <= 0xFF);

    test('Betreff und Brieftext bleiben in Latin-1', () {
      for (final art in KuendigungsArt.values) {
        for (final wer in KuendigungsUnterzeichner.values) {
          final d = _d(
              art: art,
              wer: wer,
              grund: 'Beitragserhöhung',
              zumDatum: '17.06.2027',
              kunde: 'K-4711',
              ruf: '0731 123456');
          final text = '${kuendigungBetreff(d)}\n${kuendigungBrieftext(d)}';
          final schlecht = text.runes
              .where((r) => !latin1(r))
              .map((r) => '${String.fromCharCode(r)} (U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')})')
              .toSet();
          expect(schlecht, isEmpty,
              reason: 'nicht druckbar bei $art/$wer: $schlecht');
        }
      }
    });
  });
}
