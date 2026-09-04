import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die Listen des Reiters Sozialamt ▸ Antrag ▸ Dokumente stehen als private
/// `static const` in einer privaten State-Klasse — von aussen nicht
/// erreichbar. Geprüft wird deshalb der Quelltext.
///
/// 🔴 WARUM ÜBERHAUPT: der Schlüssel IST die Ablage. Er landet als `doc_typ`
/// in `sozialamt_antrag_docs` und in der Liste `checked_docs` in
/// `sozialamt_data`. Der Server prüft ihn nicht
/// (`$_POST['doc_typ'] ?? 'sonstiges'`), die Spalte ist varchar(50). Ein
/// umbenannter Schlüssel heisst also: Haken weg, hochgeladene Datei verwaist —
/// ohne Fehler, ohne Meldung, an keiner anderen Stelle bemerkbar.
void main() {
  late String quelle;

  List<String> keysAus(String block) =>
      RegExp(r"\('([a-z0-9_]+)',").allMatches(block).map((m) => m.group(1)!).toList();

  String block(String start, String ende) {
    final a = quelle.indexOf(start);
    expect(a, greaterThan(0), reason: 'Anker „$start" nicht gefunden — Test anpassen');
    final b = quelle.indexOf(ende, a);
    expect(b, greaterThan(a), reason: 'Ende „$ende" nicht gefunden — Test anpassen');
    return quelle.substring(a, b);
  }

  String leistungsListe(String name) =>
      block("    '$name': [", '\n    ],');

  setUpAll(() {
    quelle = File('lib/widgets/behorde_sozialamt.dart').readAsStringSync();
  });

  // Die vier Leistungen mit eigener Liste, plus die Rückfallliste.
  const mitEigenerListe = [
    'Grundsicherung im Alter',
    'Grundsicherung bei Erwerbsminderung',
    'Hilfe zur Pflege',
    'Eingliederungshilfe',
  ];

  List<String> alleListen() => [
        ...mitEigenerListe.map(leistungsListe),
        block('  static const _defaultDocs = [', '\n  ];'),
        block('  static const List<(String, String, IconData)> _amtsUnterlagen = [', '\n  ];'),
      ];

  group('Schlüssel', () {
    test('kein Schlüssel wird zu lang für doc_typ varchar(50)', () {
      for (final b in alleListen()) {
        for (final k in keysAus(b)) {
          expect(k.length, lessThanOrEqualTo(50), reason: 'Schlüssel „$k" ist zu lang');
        }
      }
    });

    test('keine Doppelung innerhalb einer Liste', () {
      for (final b in alleListen()) {
        final k = keysAus(b);
        expect(k.length, k.toSet().length, reason: 'Doppelter Schlüssel in: ${k.join(', ')}');
      }
    });

    test('die bereits vergebenen Schlüssel bleiben unangetastet', () {
      // ⚠️ Für diese gibt es Haken und Dateien im Bestand. Umbenennen heisst
      // Datenverlust ohne Fehlermeldung.
      const bestand = [
        'personalausweis', 'rentenbescheid', 'kontoauszuege', 'mietvertrag',
        'nebenkostenabrechnung', 'heizkostenabrechnung', 'krankenversicherung',
        'einkommensnachweis', 'vermoegensnachweis',
        'em_bescheid', 'schwerbehindertenausweis', 'pflegegrad_bescheid',
        'pflegekosten', 'aerztliches_gutachten', 'sonstiges',
      ];
      final alle = alleListen().expand(keysAus).toSet();
      for (final k in bestand) {
        expect(alle.contains(k), isTrue, reason: 'Schlüssel „$k" ist verschwunden');
      }
    });
  });

  group('Die vom Vorsitzenden verlangten Zeilen sind da', () {
    test('Anschreiben und Checkliste stehen in der Gruppe „vom Amt erhalten"', () {
      final amt = keysAus(block(
          '  static const List<(String, String, IconData)> _amtsUnterlagen = [', '\n  ];'));
      // ⚠️ GENAU diese zwei. Festlegung des Vorsitzenden vom 04.09.2026: alles
      // andere geht unterschrieben zurück und gehört damit in den Zähler.
      expect(amt, ['anschreiben_sozialamt', 'checkliste_sozialamt']);
    });

    test('die drei Merkblätter zählen mit, stehen also in JEDER Checkliste', () {
      const merkblaetter = ['sgb1_auszug', 'datenschutz_art13', 'hinweise_sozialhilfeantrag'];
      for (final name in mitEigenerListe) {
        final k = keysAus(leistungsListe(name));
        for (final m in merkblaetter) {
          expect(k.contains(m), isTrue, reason: '„$m" fehlt bei „$name"');
        }
      }
      final std = keysAus(block('  static const _defaultDocs = [', '\n  ];'));
      for (final m in merkblaetter) {
        expect(std.contains(m), isTrue, reason: '„$m" fehlt in der Rückfallliste');
      }
    });

    test('Vermögen, Grundbesitz und Auslandszeiten überall', () {
      for (final b in [
        ...mitEigenerListe.map(leistungsListe),
        block('  static const _defaultDocs = [', '\n  ];'),
      ]) {
        final k = keysAus(b);
        for (final n in ['erklaerung_vermoegen', 'erklaerung_grundbesitz', 'erklaerung_ausland']) {
          expect(k.contains(n), isTrue, reason: '„$n" fehlt in einer Liste');
        }
      }
    });

    test('Mietbescheinigung steht dort, wo auch die Miete steht', () {
      // Die Regel: eine neue Zeile kommt dorthin, wo ihr Geschwisterteil schon
      // steht. Eine Mietzeile in einer Liste ohne Miete ist ein Haken, den nie
      // jemand setzt — und der Balken erreicht die volle Zahl nie.
      for (final b in [
        ...mitEigenerListe.map(leistungsListe),
        block('  static const _defaultDocs = [', '\n  ];'),
      ]) {
        final k = keysAus(b);
        expect(k.contains('mietbescheinigung'), k.contains('mietvertrag'),
            reason: 'Mietbescheinigung und Mietvertrag laufen auseinander: ${k.join(', ')}');
      }
    });

    test('KV-Beiträge stehen dort, wo auch die Krankenversicherung steht', () {
      for (final b in [
        ...mitEigenerListe.map(leistungsListe),
        block('  static const _defaultDocs = [', '\n  ];'),
      ]) {
        final k = keysAus(b);
        expect(k.contains('antrag_kv_beitraege'), k.contains('krankenversicherung'),
            reason: 'KV-Beiträge und Krankenversicherung laufen auseinander: ${k.join(', ')}');
      }
    });

    test('das allgemeine Antragsformular steht NUR noch bei der Eingliederungshilfe', () {
      // ⚠️ Entscheidung des Vorsitzenden (04.09.2026): in den SGB-XII-Listen
      // heisst das Blatt „Antrag Leistungen nach dem SGB XII"; zwei Zeilen für
      // dasselbe Papier hätten den Zähler nie voll werden lassen. Bei der
      // Eingliederungshilfe bleibt das allgemeine Formular, weil dort kein
      // SGB-XII-Antrag stehen darf und die Liste sonst gar keine Antragszeile
      // mehr hätte.
      //
      // Beim Entfernen geprüft: `checked_docs` enthielt eine leere Liste und
      // `sozialamt_antrag_docs` null Zeilen — es ging kein Haken und keine
      // Datei verloren.
      for (final n in ['Grundsicherung im Alter', 'Grundsicherung bei Erwerbsminderung', 'Hilfe zur Pflege']) {
        expect(keysAus(leistungsListe(n)).contains('antrag_formular'), isFalse, reason: 'noch bei „$n"');
      }
      expect(keysAus(block('  static const _defaultDocs = [', '\n  ];')).contains('antrag_formular'), isFalse,
          reason: 'noch in der Rückfallliste');
      expect(keysAus(leistungsListe('Eingliederungshilfe')).contains('antrag_formular'), isTrue,
          reason: 'die Eingliederungshilfe hätte sonst gar keine Antragszeile');
    });

    test('jede Liste hat genau EINE Antragszeile', () {
      for (final b in [
        ...mitEigenerListe.map(leistungsListe),
        block('  static const _defaultDocs = [', '\n  ];'),
      ]) {
        final k = keysAus(b);
        final antraege = k.where((e) => e == 'antrag_sgb12' || e == 'antrag_formular').toList();
        expect(antraege.length, 1,
            reason: 'Antragszeilen: ${antraege.join(', ')} in ${k.join(', ')}');
      }
    });

    test('Antrag nach dem SGB XII überall AUSSER bei der Eingliederungshilfe', () {
      // ⚠️ Die Eingliederungshilfe steht seit dem BTHG (2020) im SGB IX
      // Teil 2, nicht mehr im SGB XII. Die Zeile dort wäre ein Haken, den
      // nie jemand setzen kann — und der Balken erreichte die volle Zahl nie.
      for (final n in ['Grundsicherung im Alter', 'Grundsicherung bei Erwerbsminderung', 'Hilfe zur Pflege']) {
        expect(keysAus(leistungsListe(n)).contains('antrag_sgb12'), isTrue, reason: 'fehlt bei „$n"');
      }
      expect(keysAus(block('  static const _defaultDocs = [', '\n  ];')).contains('antrag_sgb12'), isTrue,
          reason: 'fehlt in der Rückfallliste');
      expect(keysAus(leistungsListe('Eingliederungshilfe')).contains('antrag_sgb12'), isFalse,
          reason: 'Eingliederungshilfe ist SGB IX, nicht SGB XII');
    });

    test('Fragebogen zum Angehörigen bei Pflege und Eingliederungshilfe', () {
      expect(keysAus(leistungsListe('Hilfe zur Pflege')).contains('fragebogen_angehoerige'), isTrue);
      expect(keysAus(leistungsListe('Eingliederungshilfe')).contains('fragebogen_angehoerige'), isTrue);
    });
  });

  group('Keine Leistung fällt durch', () {
    test('jede Leistung des Antragsdialogs hat eine Liste — eigene oder Rückfall', () {
      // Der Dialog bietet neun Leistungen an, eigene Listen gibt es für vier.
      // Die übrigen fünf — darunter „Hilfe zum Lebensunterhalt", der
      // klassische Sozialhilfefall — landen in _defaultDocs. Deshalb muss
      // dort der Standardsatz vollständig stehen.
      final zeile = RegExp(r"final leistungen = \[(.*?)\];", dotAll: true).firstMatch(quelle);
      expect(zeile, isNotNull, reason: 'Leistungsliste des Dialogs nicht gefunden');
      final angeboten = RegExp(r"'([^']+)'")
          .allMatches(zeile!.group(1)!)
          .map((m) => m.group(1)!)
          .toList();
      expect(angeboten.length, 9);

      final ohneEigene = angeboten.where((l) => !mitEigenerListe.contains(l)).toList();
      expect(ohneEigene.contains('Hilfe zum Lebensunterhalt'), isTrue);

      final std = keysAus(block('  static const _defaultDocs = [', '\n  ];'));
      for (final n in [
        'mietbescheinigung', 'erklaerung_vermoegen', 'erklaerung_grundbesitz',
        'erklaerung_ausland', 'antrag_kv_beitraege', 'fragebogen_angehoerige',
        'sgb1_auszug', 'datenschutz_art13', 'hinweise_sozialhilfeantrag',
      ]) {
        expect(std.contains(n), isTrue,
            reason: '„$n" fehlt in der Rückfallliste — ${ohneEigene.length} Leistungen sähen sie nie');
      }
    });
  });

  group('Der Zähler misst nur, was beizubringen ist', () {
    test('doneCount läuft über die Checkliste, nicht über die Amtsblätter', () {
      final b = block('  Widget _buildDokumente(', '\n  }');
      // ⚠️ Nur die ZUWEISUNG, nicht der ganze Rumpf: über die Methode gemessen
      // stünde `_amtsUnterlagen` immer irgendwo hinter `doneCount`, und die
      // Prüfung wäre unwahr, ohne dass etwas kaputt wäre.
      final zuweisung = block('    final doneCount =', ';');
      expect(zuweisung.contains('checklist.where('), isTrue);
      // Wäre _amtsUnterlagen im Zähler, meldete der Schirm den Antrag als
      // unvollständig, weil ein Anschreiben nicht eingescannt ist.
      expect(zuweisung.contains('_amtsUnterlagen'), isFalse);
      expect(b.contains(r'$doneCount / ${checklist.length}'), isTrue);
    });

    test('beide Gruppen werden auch wirklich gezeichnet', () {
      final b = block('  Widget _buildDokumente(', '\n  }');
      expect(b.contains('...checklist.map((c) => _docZeile('), isTrue);
      expect(b.contains('..._amtsUnterlagen.map((c) => _docZeile('), isTrue);
    });
  });
}
