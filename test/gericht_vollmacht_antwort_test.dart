import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_gericht.dart';

/// Echte Antwort von `api/admin/vollmacht_data.php?behoerde=gericht` vom
/// 10.08.2026 — nur die personenbezogenen Werte des Mitglieds sind durch
/// Platzhalter ersetzt, die STRUKTUR ist unveraendert.
///
/// ⚠️ Der Test prueft nicht die Texte, sondern die Form. PHP kennt nur einen
/// Array-Typ: `umfang_organisation` kommt heute als JSON-Objekt, waere aber
/// eine Liste, sobald ein Gerichtstyp einmal keine Punkte hat; `grenzen`
/// kommt als Liste. Ein `as Map` auf einer Liste wirft, statt null zu
/// liefern — im Release-Build sieht man davon nur eine graue Flaeche.
const String _echteAntwort = r'''{"success": true, "user": {"id": 999, "vorname": "Maria", "nachname": "Musterfrau", "geburtsdatum": "1980-01-01", "geburtsort": "Musterstadt", "strasse": "Musterweg", "hausnummer": "1", "plz": "89073", "ort": "Ulm", "mitgliedernummer": "M00000"}, "user_behoerde": {"dienststelle": "", "kundennummer": "", "bg_nummer": ""}, "verfahren": {"id": 12, "gericht_typ": "insolvenzgericht", "titel": "Verbraucherinsolvenz (Privatinsolvenz)", "aktenzeichen": "3 IK 413/24", "datum": "2024-11-06", "status": "bewilligt", "sachbearbeiter": "Ri Muster", "klaeger": "Maria Musterfrau", "beklagter": "Beispiel GmbH", "klage_aktenzeichen": "", "klage_richter": "Ri Muster", "klage_status": "", "guetetermin_datum": "", "kammertermin_datum": ""}, "gericht": {"name": "Amtsgericht Ulm — Insolvenzabteilung", "adresse": "Olgastraße 109, 89073 Ulm", "telefon": "0731 / 189-2142, -2207, -2181"}, "recht": {"label": "Insolvenzgericht", "zweck": "Auskunft ueber den Stand des Verfahrens, Akteneinsicht und Erklaerungen in Raten- und Zahlungsangelegenheiten", "auskunft_stellen": "das Insolvenzgericht einschliesslich Rechtspflegerin oder Rechtspfleger und Geschaeftsstelle sowie die Insolvenzverwalterin oder der Insolvenzverwalter bzw. die Treuhaenderin oder der Treuhaender", "verfahrensordnung": "Insolvenzordnung (InsO) i.V.m. der Zivilprozessordnung (ZPO)", "vertretung_norm": "§ 305 Abs. 4 InsO bzw. § 4 InsO i.V.m. § 79 Abs. 2 ZPO", "vertretung_moeglich": "bedingt", "bedingung": "Eine Vertretung ist nur im Verbraucherinsolvenzverfahren und nur dann moeglich, wenn der Bevollmaechtigte eine geeignete Person oder ein Angehoeriger einer als geeignet anerkannten Stelle im Sinne des § 305 Abs. 1 Nr. 1 InsO ist (Anerkennung nach Landesrecht als Schuldnerberatungsstelle). Ausserhalb des Verbraucherinsolvenzverfahrens gilt ueber § 4 InsO der abschliessende Katalog des § 79 Abs. 2 ZPO, in dem ein Verein nicht enthalten ist.", "vertretung_text": "Fuer das Insolvenzverfahren gelten ueber § 4 InsO die Vorschriften der Zivilprozessordnung entsprechend; vertretungsbefugt sind daher grundsaetzlich nur die in § 79 Abs. 2 ZPO abschliessend genannten Personen. Im Verbraucherinsolvenzverfahren erweitert § 305 Abs. 4 InsO diesen Kreis: der Schuldner kann sich \"von einer geeigneten Person oder einem Angehoerigen einer als geeignet anerkannten Stelle im Sinne des Absatzes 1 Nr. 1 vertreten lassen\". Die Bescheinigung ueber den gescheiterten aussergerichtlichen Einigungsversuch nach § 305 Abs. 1 Nr. 1 InsO darf ebenfalls nur von einer solchen anerkannten Stelle ausgestellt werden.", "beistand_norm": "§ 90 ZPO i.V.m. § 4 InsO", "vollmacht_norm": "§ 80 ZPO i.V.m. § 4 InsO", "akte_norm": "§ 299 ZPO i.V.m. § 4 InsO", "kostenhilfe": "Stundung der Verfahrenskosten (§§ 4a ff. InsO)", "umfang_organisation": {"auskunft_muendlich": "Muendliche und fernmuendliche Auskunft (Telefon, persoenliche Vorsprache) ueber Stand und Fortgang der Sache", "auskunft_schriftlich": "Schriftliche und elektronische Auskunft sowie Sachstandsanfragen", "unterrichtung": "Unterrichtung des Vollmachtgebers ueber jede Auskunft, jedes Schriftstueck und jede laufende Frist, einschliesslich Erlaeuterung", "zustellung": "Empfangnahme von Zustellungen, Ladungen, Beschluessen, Verfuegungen und Urteilen des Gerichts an die unten genannte Postanschrift", "schriftverkehr": "Fuehrung des organisatorischen Schriftverkehrs mit dem Gericht (Sachstandsanfragen, Terminverlegungsgesuche aus organisatorischen Gruenden, Uebersendung von Unterlagen)", "fristen": "Ueberwachung und Einhaltung von Fristen und Terminen", "akteneinsicht": "Beantragung und Wahrnehmung der Akteneinsicht sowie Anfertigung von Abschriften", "termine": "Begleitung des Vollmachtgebers zu Gerichtsterminen (Antrag auf Zulassung als Beistand — siehe unten)", "uebersetzung": "Uebersetzungs- und Verstaendnishilfe (keine beglaubigte Uebersetzung)", "anwalt": "Beauftragung eines Rechtsanwalts im Namen und auf Rechnung des Vollmachtgebers sowie Uebermittlung der Unterlagen an diesen (rechtsgeschaeftliche Vollmacht, keine Rechtsdienstleistung)", "verwalter": "Korrespondenz mit der Insolvenzverwalterin oder dem Insolvenzverwalter bzw. der Treuhaenderin oder dem Treuhaender, einschliesslich Entgegennahme und Weiterleitung von Auskuenften", "raten": "Raten- und Zahlungsangelegenheiten: Auskunft ueber Hoehe, Faelligkeit und Verrechnung einholen, Zahlungstermine abstimmen und Raten- bzw. Zahlungsvereinbarungen im Namen des Vollmachtgebers erklaeren (§§ 164 ff. BGB, nach vorheriger Ruecksprache)", "glaeubiger": "Korrespondenz mit den Glaeubigern und Einholung von Auskuenften zum Stand angemeldeter Forderungen", "restschuld": "Begleitung der Wohlverhaltensphase bis zur Restschuldbefreiung (§§ 286 ff. InsO) — Fristenueberwachung und Erinnerung an die Obliegenheiten nach § 295 InsO"}, "umfang_vertretung": {"prozessvertretung": "Vertretung des Vollmachtgebers im gerichtlichen Verfahren (Prozess- bzw. Verfahrensvollmacht) einschliesslich der Abgabe von Verfahrenserklaerungen", "vergleich": "Abschluss eines Vergleichs, Verzicht auf den Streitgegenstand oder Anerkenntnis des gegnerischen Anspruchs (§ 83 Abs. 1 ZPO — nur wirksam, wenn ausdruecklich erteilt)", "rechtsmittel": "Einlegung und Ruecknahme von Rechtsmitteln"}, "grenzen": ["Rechtliche Pruefung des Einzelfalls, Rechtsberatung und Formulierung der rechtlichen Begruendung von Antraegen, Schriftsaetzen oder Rechtsmitteln (§ 2 Abs. 1 RDG). Hierfuer wird der Vollmachtgeber stets an einen Rechtsanwalt verwiesen.", "Entgegennahme von Geldbetraegen jeder Art. Zahlungen des Gerichts, der Staatskasse oder der Gegenseite erfolgen ausschliesslich auf ein Konto des Vollmachtgebers.", "Abgabe materiell-rechtlicher Erklaerungen (Verzicht, Anerkenntnis, Vergleich, Ruecknahme), soweit sie nicht oben ausdruecklich angekreuzt und rechtlich zulaessig sind.", "Stellung des Eroeffnungsantrags, des Antrags auf Restschuldbefreiung oder auf Stundung der Verfahrenskosten sowie die Durchfuehrung des aussergerichtlichen Einigungsversuchs. Der Verein stellt keine Antraege in diesem Verfahren.", "Ausstellung der Bescheinigung ueber den gescheiterten aussergerichtlichen Einigungsversuch nach § 305 Abs. 1 Nr. 1 InsO — diese darf nur eine als geeignet anerkannte Stelle oder ein Rechtsanwalt ausstellen.", "Die Auskunfts- und Mitwirkungspflicht des Schuldners nach § 97 InsO — er hat sich nach § 97 Abs. 3 InsO auf Anordnung des Gerichts jederzeit persoenlich zur Verfuegung zu stellen — sowie die Pflicht, eine wesentliche Aenderung der persoenlichen oder wirtschaftlichen Verhaeltnisse nach § 4b Abs. 2 InsO unverzueglich anzuzeigen. Beides bleibt beim Vollmachtgeber; der Bevollmaechtigte darf vorbereiten und uebermitteln, nicht aber an seiner Stelle erfuellen."]}, "vorsitzer": {"id": 2, "vorname": "Vorname", "nachname": "Vorsitzender"}, "verein": {"vereinsname": "ICD360S e.V.", "adresse": "c/o Vorstand\nMusterweg 1\n89231 Neu-Ulm", "registernummer": "VR 201335", "registergericht": "Amtsgericht Memmingen, Bayern", "email": "verein@icd360s.de", "zweck": ""}}''';

void main() {
  final antwort = jsonDecode(_echteAntwort) as Map<String, dynamic>;
  final recht = vollmachtFeldAlsMap(antwort['recht']);

  group('vollmacht_data.php (Gericht) laesst sich vollstaendig lesen', () {
    test('die echte Antwort traegt alles, was der Tab braucht', () {
      expect(antwort['success'], isTrue);
      for (final k in ['user', 'vorsitzer', 'verein', 'verfahren', 'gericht', 'recht']) {
        expect(antwort.containsKey(k), isTrue, reason: 'Feld $k fehlt');
      }
      // Stufe-1-Felder — daraus wird der Vollmachtgeber gebaut.
      final user = vollmachtFeldAlsMap(antwort['user']);
      for (final k in ['vorname', 'nachname', 'geburtsdatum', 'geburtsort',
                       'strasse', 'hausnummer', 'plz', 'ort', 'mitgliedernummer']) {
        expect(user.containsKey(k), isTrue, reason: 'Stufe-1-Feld $k fehlt');
      }
      // Vorfall-Felder — daraus wird der Abschnitt "Verfahren" gebaut.
      final verfahren = vollmachtFeldAlsMap(antwort['verfahren']);
      for (final k in ['titel', 'aktenzeichen', 'klaeger', 'beklagter',
                       'klage_aktenzeichen', 'klage_richter',
                       'guetetermin_datum', 'kammertermin_datum']) {
        expect(verfahren.containsKey(k), isTrue, reason: 'Vorfall-Feld $k fehlt');
      }
    });

    test('umfang_organisation ist ein Objekt und wird als Map gelesen', () {
      final org = vollmachtFeldAlsMap(recht['umfang_organisation']);
      expect(org, isNotEmpty);
      expect(org.containsKey('zustellung'), isTrue);
      expect(org.containsKey('akteneinsicht'), isTrue);
    });

    test('der eigentliche Anlass steht in der Antwort: Auskunft', () {
      // Der Alltagsfall ist der Anruf bei Gericht oder Verwalter, bei dem nach
      // einer Vollmacht gefragt wird — nicht die Verhandlung.
      expect((recht['zweck'] ?? '').toString(), contains('Auskunft'));
      expect((recht['auskunft_stellen'] ?? '').toString(), isNotEmpty);
      final org = vollmachtFeldAlsMap(recht['umfang_organisation']);
      expect(org.containsKey('auskunft_muendlich'), isTrue);
      expect(org.containsKey('unterrichtung'), isTrue);
    });

    test('Insolvenz: Raten drin, Antragstellung raus', () {
      // Der Verein stellt keine Anträge — ein Kästchen dafür wäre eine
      // Einladung zu genau dem.
      final org = vollmachtFeldAlsMap(recht['umfang_organisation']);
      expect(org.containsKey('raten'), isTrue);
      expect(org.containsKey('verwalter'), isTrue);
      for (final weg in ['insolvenzantrag', 'einigungsversuch', 'formulare', 'kostenhilfe']) {
        expect(org.containsKey(weg), isFalse, reason: '\$weg gehört hier nicht hin');
      }
      // …und die Grenzen sagen es ausdrücklich.
      final g = vollmachtFeldAlsListe(recht['grenzen']).join(' ');
      expect(g, contains('keine Antraege'));
      expect(g, contains('97 InsO'));
      expect(g, contains('4b Abs. 2 InsO'));
    });


    test('eine LISTE an derselben Stelle wirft nicht', () {
      // Genau der Fall, der einen Bildschirm grau werden laesst: leeres
      // PHP-Array -> `[]` statt `{}`.
      expect(vollmachtFeldAlsMap(jsonDecode('[]')), isEmpty);
      expect(vollmachtFeldAlsMap(jsonDecode('["a","b"]')), {'0': 'a', '1': 'b'});
      expect(vollmachtFeldAlsMap(null), isEmpty);
    });

    test('grenzen ist eine Liste und wird auch als Objekt vertragen', () {
      expect(vollmachtFeldAlsListe(recht['grenzen']).length, greaterThan(2));
      expect(vollmachtFeldAlsListe(jsonDecode('{"a":"x","b":"y"}')), ['x', 'y']);
      expect(vollmachtFeldAlsListe(null), isEmpty);
    });
  });

  group('Rechtslage kommt vom Server, nicht aus dem Client', () {
    test('Insolvenzgericht ist "bedingt" und nennt die Bedingung', () {
      // § 4 InsO verweist auf § 79 Abs. 2 ZPO (Verein nicht enthalten);
      // § 305 Abs. 4 InsO oeffnet nur fuer anerkannte Stellen.
      expect(recht['vertretung_moeglich'], 'bedingt');
      expect((recht['bedingung'] as String).trim(), isNotEmpty);
      expect(recht['vertretung_norm'], contains('305 Abs. 4 InsO'));
    });

    test('jede Norm, die der Tab anzeigt, ist gefuellt', () {
      for (final k in ['label', 'verfahrensordnung', 'vertretung_norm',
                       'vertretung_text', 'beistand_norm', 'vollmacht_norm',
                       'akte_norm', 'kostenhilfe']) {
        expect((recht[k] ?? '').toString().trim(), isNotEmpty, reason: '$k ist leer');
      }
    });

    test('"bedingt" ohne Bedingung waere ein stiller Fehler', () {
      // Der Schalter "Vertretungsbefugnis geltend machen" erscheint nur, wenn
      // vertretung_moeglich != "nein". Kaeme dann keine Bedingung mit, stuende
      // im Bildschirm eine Moeglichkeit ohne nachlesbare Voraussetzung.
      if (recht['vertretung_moeglich'] != 'nein') {
        expect((recht['bedingung'] ?? '').toString().trim(), isNotEmpty);
      }
    });
  });
}
