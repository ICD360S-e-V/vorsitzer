import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

/// Die Antwort, die `jc_av_schweigepflicht_manage.php?action=katalog` am
/// 21.08.2026 wirklich geliefert hat — nicht gekürzt und nicht nachgebaut.
///
/// Der Themenkatalog lebt auf dem Server, damit App und PDF nie
/// auseinanderlaufen. Genau deshalb kann ihn kein Dart-Test aus dem Code
/// ableiten: er muss gegen das gehalten werden, was wirklich ankam.
const String kKatalogAntwort = r'''
{"success":true,"umfang":{"A. Vermittlung und Integration":{"mitwirkung":"Mitwirkung und Mitwirkungsobliegenheiten (§§ 60 ff. SGB I)","ziele":"Vorgesehene und vereinbarte (Zwischen-)Ziele","absprachen":"Absprachen und Vereinbarungen","beratung":"Inhalte der Beratungs- und Vermittlungsgespraeche","kooperationsplan":"Kooperationsplan bzw. Eingliederungsvereinbarung (§ 15 SGB II)","vorschlaege":"Vermittlungsvorschlaege und deren Ergebnis","eigenbemuehungen":"Eigenbemuehungen und deren Nachweis","stellenangebote":"Stellenangebote, Bewerbungen und Rueckmeldungen von Arbeitgebern","profiling":"Staerken- und Potenzialanalyse, Profiling"},"B. Massnahmen und Foerderung":{"massnahmen":"Zuweisung, Verlauf, Abbruch und Ergebnis von Massnahmen","traeger":"Austausch mit beauftragten Dritten und Massnahmetraegern (§ 16 SGB II i.V.m. §§ 45, 176 ff. SGB III)","bildungsgutschein":"Bildungsgutschein, Weiterbildung, Umschulung (§ 16 SGB II i.V.m. § 81 SGB III)","agh":"Arbeitsgelegenheiten (§ 16d SGB II)","eingliederung":"Eingliederungszuschuesse und Foerderleistungen an Arbeitgeber","coaching":"Ganzheitliche Betreuung und Coaching (§ 16k SGB II)","reha":"Teilhabe am Arbeitsleben, Reha-Verfahren, Umschulung aus gesundheitlichen Gruenden","vermittlungsbudget":"Vermittlungsbudget, Bewerbungs- und Fahrtkosten (§ 16 SGB II i.V.m. § 44 SGB III)"},"C. Leistung und Bescheide":{"bescheide":"Inhalte der Bescheide und des sonstigen Schriftverkehrs","sachstand":"Sachstand der Leistungsbearbeitung und erforderliche Unterlagen","berechnung":"Leistungsberechnung, Einkommens- und Vermoegensanrechnung","kdu":"Bedarfe fuer Unterkunft und Heizung (§ 22 SGB II)","mehrbedarf":"Mehrbedarfe und einmalige Bedarfe (§§ 21, 24 SGB II)","darlehen":"Darlehen, Aufrechnung, Rueckforderung und Erstattung","but":"Bildung und Teilhabe (§§ 28, 29 SGB II)","bg":"Zusammensetzung der Bedarfsgemeinschaft"},"D. Termine und Rechtsfolgen":{"termine":"Melde- und Beratungstermine, Einladungen und Terminverlegungen","meldeversaeumnis":"Meldeversaeumnisse und deren Begruendung","rechtsfolgen":"Rechtsfolgenbelehrungen","sanktionen":"Leistungsminderungen und Sanktionen (§ 31a SGB II) einschliesslich Anhoerungen","ordnungswidrig":"Ordnungswidrigkeiten- und Erstattungsverfahren"},"E. Rechtsbehelfe und Akten":{"widerspruch":"Sachstand von Widerspruchsverfahren","klage":"Sachstand von Klageverfahren vor dem Sozialgericht","akteneinsicht":"Akteneinsicht (§ 25 SGB X) und Erhalt von Abschriften","aktenvermerke":"Beratungsvermerke und Gespraechsnotizen zur Person"},"F. Form des Austauschs":{"auskunft_telefon":"Telefonische Auskunft","auskunft_schrift":"Schriftliche Auskunft, auch per E-Mail und Fax","kopien":"Uebersendung von Kopien der Bescheide und Schreiben","begleitung":"Teilnahme an Terminen als Begleitung (§ 13 Abs. 4 SGB X)"}},"gesundheit":{"aerztlicher_dienst":"Ergebnis der Begutachtung durch den Aerztlichen Dienst (nur Leistungsbild, keine Diagnosen)","psych_dienst":"Ergebnis der Begutachtung durch den Psychologischen Dienst","leistungsbild":"Festgestellte Einschraenkungen des Leistungsvermoegens und daraus folgende Vermittlungshemmnisse","arbeitsunfaehigkeit":"Zeiten der Arbeitsunfaehigkeit und deren Meldung","schwerbehinderung":"Grad der Behinderung, Merkzeichen und Gleichstellung (SGB IX)","reha_gesundheit":"Gesundheitsbezogene Angaben im Reha- und Teilhabeverfahren","diagnosen":"Diagnosen und aerztliche Befundberichte"}}
''';

/// Ein echter Eintrag aus `action=list`, entschlüsselt vom Server geliefert.
const String kListeAntwort = r'''
{"success":true,"eintraege":[{"id":1,"user_id":36,"user_av_id":4,
"av_name":"Muhrat","av_rolle":"pAp","av_telefon":"","av_email":"",
"jobcenter_name":"Jobcenter Neu-Ulm","jobcenter_anschrift":"89231 Neu-Ulm",
"kundennummer":"PROBE-123456","bg_nummer":"BG-PROBE",
"erteilt_am":"2026-08-21","gueltig_bis":null,
"umfang":{"richtung_jc_verein":true,"richtung_verein_jc":true,"mitwirkung":true},
"gesundheit":{"aerztlicher_dienst":true,"leistungsbild":true},
"status":"draft","revoked_at":null,"revoked_reason":"",
"pdf_filename":"jc_av_schweigepflicht_user36_20260821_082614.pdf.enc",
"pdf_sha256":"2f5661c26b5adbe119491d4af492be1dc784c73a6508eb911a3ac2c6150695a5",
"pdf_translation_filename":"jc_av_schweigepflicht_user36_20260821_082614_ro.pdf.enc",
"translation_language":"ro","signatur_id":null,"signatur_angefordert_at":null,
"submitted_at":null,"submitted_method":null,"submitted_reference":"",
"submitted_notes":"","notes":"Proba tehnica","created_at":"2026-08-21 08:26:14",
"versand":[
{"id":3,"methode":"fax","datum":"2026-08-21 11:30:12","fassung":"de","ziel":"","notiz":"",
 "signatur_id":null,"ergebnis":"fehler","fehler":"Gegenstelle besetzt"},
{"id":2,"methode":"signatur","datum":"2026-08-21 11:30:12","fassung":"de","ziel":"",
 "notiz":"Frist bis 04.09.2026","signatur_id":99,"ergebnis":"ok","fehler":""},
{"id":1,"methode":"chat","datum":"2026-08-21 11:30:11","fassung":"ro","ziel":"M10005",
 "notiz":"Zum Lesen","signatur_id":null,"ergebnis":"ok","fehler":""}]}]}
''';

/// Der Faxstand, wie ihn `action: list` am 21.08.2026 für die erste im
/// Betrieb gefaxte Erklärung geliefert hat.
const String kFaxAntwort = r"""
{"fax_id":14,"status":"in_zustellung","typ":"SENDING",
 "gesendet":"2026-08-21 18:22:54","seiten":3,"fehler":""}
""";

/// Ob der Fax-Knopf noch angeboten wird.
///
/// ⚠️ Nur nach einem gescheiterten Versuch. Ein Fax an eine Behörde ist nicht
/// zurückholbar; zweimal dieselbe Erklärung zu schicken sieht dort aus, als
/// hätten wir den Überblick verloren.
bool faxKnopfSichtbar(dynamic rohFax) {
  final fax = rohFax is Map ? Map<String, dynamic>.from(rohFax) : null;
  if (fax == null) return true;
  final st = (fax['status'] ?? '').toString();
  return st == 'fehlgeschlagen' || st == 'storniert';
}

/// Genau die Umwandlung, die die Historie beim Zeichnen macht.
List<Map<String, dynamic>> versandLesen(dynamic roh) => roh is List
    ? roh.map((x) => Map<String, dynamic>.from(x as Map)).toList()
    : <Map<String, dynamic>>[];

/// Genau die Umwandlung, die der Reiter beim Laden macht.
Map<String, Map<String, String>> katalogLesen(dynamic roh) {
  final out = <String, Map<String, String>>{};
  if (roh is Map) {
    roh.forEach((gruppe, items) {
      if (items is Map) out['$gruppe'] = items.map((k, v) => MapEntry('$k', '$v'));
    });
  }
  return out;
}

void main() {
  group('Themenkatalog vom Server', () {
    late Map<String, dynamic> antwort;
    setUp(() => antwort = jsonDecode(kKatalogAntwort) as Map<String, dynamic>);

    test('liefert Gruppen mit Punkten', () {
      final kat = katalogLesen(antwort['umfang']);
      expect(kat, isNotEmpty);
      // Sechs Gruppen A–F; wird eine hinzugefügt, ist das eine bewusste
      // Änderung und der Test soll sie melden.
      expect(kat.length, 6);
      for (final g in kat.entries) {
        expect(g.value, isNotEmpty, reason: 'Gruppe "${g.key}" ist leer');
      }
    });

    test('jeder Punkt hat eine nicht-leere Beschriftung', () {
      final kat = katalogLesen(antwort['umfang']);
      for (final g in kat.entries) {
        g.value.forEach((k, v) {
          expect(v.trim(), isNotEmpty, reason: 'Punkt "$k" ohne Beschriftung');
        });
      }
    });

    test('Schlüssel sind über alle Gruppen hinweg eindeutig', () {
      // Zwei Gruppen mit demselben Schlüssel hiessen: ein Haken setzt zwei
      // Zeilen im PDF, oder eine bleibt stumm leer.
      final kat = katalogLesen(antwort['umfang']);
      final gesehen = <String>{};
      for (final g in kat.values) {
        for (final k in g.keys) {
          expect(gesehen.contains(k), isFalse, reason: 'Schlüssel "$k" kommt doppelt vor');
          gesehen.add(k);
        }
      }
      // 9 + 8 + 8 + 5 + 4 + 4 — die Gesundheitspunkte zählen hier nicht mit,
      // die stehen in einer eigenen Liste.
      expect(gesehen.length, 38);
    });

    test('Gesundheitspunkte überschneiden sich NICHT mit dem Umfang', () {
      // Ein Schlüssel in beiden Listen wäre nicht bloss doppelt: der
      // Gesundheitsblock ist die gesonderte Einwilligung nach
      // Art. 9 Abs. 2 lit. a DSGVO. Fiele ein Punkt auch in den allgemeinen
      // Umfang, wäre er über den dortigen Haken miterteilt — also genau die
      // stillschweigende Einwilligung, die der eigene Block verhindern soll.
      final umfangKeys = <String>{
        for (final g in katalogLesen(antwort['umfang']).values) ...g.keys,
      };
      final ges = (antwort['gesundheit'] as Map).keys.map((e) => '$e').toSet();
      expect(ges, isNotEmpty);
      expect(umfangKeys.intersection(ges), isEmpty);
    });

    test('die drei Richtungs-Schlüssel stehen NICHT im Katalog', () {
      // Sie werden in der App gesondert angezeigt. Kämen sie zusätzlich aus
      // dem Katalog, erschienen sie zweimal im Formular.
      final umfangKeys = <String>{
        for (final g in katalogLesen(antwort['umfang']).values) ...g.keys,
      };
      for (final r in ['richtung_jc_verein', 'richtung_verein_jc', 'richtung_direkt']) {
        expect(umfangKeys.contains(r), isFalse, reason: '"$r" doppelt');
      }
    });

    test('ein leerer Katalog wirft nicht', () {
      // ⚠️ PHP kennt nur einen Array-Typ: eine leere Liste wird zu `[]`,
      // nicht zu `{}`. Ein `as Map` darauf wirft — in einem Release-Build
      // ist das eine graue Fläche ohne jede Meldung.
      expect(katalogLesen(jsonDecode('[]')), isEmpty);
      expect(katalogLesen(null), isEmpty);
      expect(katalogLesen(jsonDecode('{"A":[]}')), isEmpty);
    });
  });

  group('Liste der Erklärungen', () {
    late Map<String, dynamic> eintrag;
    setUp(() {
      final a = jsonDecode(kListeAntwort) as Map<String, dynamic>;
      eintrag = Map<String, dynamic>.from((a['eintraege'] as List).first as Map);
    });

    test('umfang und gesundheit kommen als Objekt, nicht als Liste', () {
      expect(eintrag['umfang'], isA<Map>());
      expect(eintrag['gesundheit'], isA<Map>());
    });

    test('verschlüsselte Felder kommen entschlüsselt an', () {
      expect(eintrag['av_name'], 'Muhrat');
      expect(eintrag['jobcenter_name'], 'Jobcenter Neu-Ulm');
      expect(eintrag['kundennummer'], 'PROBE-123456');
    });

    test('eine frische Erklärung ist Entwurf und ohne Unterschrift', () {
      expect(eintrag['status'], 'draft');
      expect(eintrag['signatur_id'], isNull);
    });

    test('die Übersetzung wird nur gemeldet, wenn es eine Datei gibt', () {
      final lang = (eintrag['translation_language'] ?? '').toString();
      final datei = (eintrag['pdf_translation_filename'] ?? '').toString();
      expect(lang.isNotEmpty && datei.isNotEmpty, isTrue);
    });
  });

  group('Faxstand', () {
    test('ein laufendes Fax verbirgt den Knopf', () {
      expect(faxKnopfSichtbar(jsonDecode(kFaxAntwort)), isFalse);
    });

    test('ein zugestelltes Fax verbirgt den Knopf', () {
      final f = jsonDecode(kFaxAntwort) as Map<String, dynamic>;
      f['status'] = 'zugestellt';
      expect(faxKnopfSichtbar(f), isFalse);
    });

    test('nach einem Fehlschlag darf erneut gefaxt werden', () {
      final f = jsonDecode(kFaxAntwort) as Map<String, dynamic>;
      for (final st in ['fehlgeschlagen', 'storniert']) {
        f['status'] = st;
        expect(faxKnopfSichtbar(f), isTrue, reason: st);
      }
    });

    test('ohne Fax steht der Knopf da', () {
      expect(faxKnopfSichtbar(null), isTrue);
      // ⚠️ Eine ältere Serverfassung liefert den Schlüssel gar nicht, und
      // PHP macht aus einer leeren Struktur `[]`, nicht `{}`. Beides heißt
      // „noch nicht gefaxt" — und darf kein `as Map` zerbrechen.
      expect(faxKnopfSichtbar(jsonDecode('[]')), isTrue);
    });

    test('der Stand trägt Zeitpunkt und Seitenzahl', () {
      final f = jsonDecode(kFaxAntwort) as Map<String, dynamic>;
      expect(f['gesendet'], isNotEmpty);
      expect(f['seiten'], 3);
      expect(f['fax_id'], 14);
    });
  });

  group('Versandprotokoll', () {
    late Map<String, dynamic> eintrag;
    setUp(() {
      final a = jsonDecode(kListeAntwort) as Map<String, dynamic>;
      eintrag = Map<String, dynamic>.from((a['eintraege'] as List).first as Map);
    });

    test('kommt mit der Liste mit, nicht über einen zweiten Aufruf', () {
      expect(eintrag.containsKey('versand'), isTrue);
      expect(versandLesen(eintrag['versand']), hasLength(3));
    });

    test('neueste Zeile zuerst', () {
      final ids = versandLesen(eintrag['versand']).map((v) => v['id'] as int).toList();
      expect(ids, [3, 2, 1]);
    });

    test('verschlüsselte Felder kommen entschlüsselt an', () {
      final v = versandLesen(eintrag['versand']);
      final chat = v.firstWhere((x) => x['methode'] == 'chat');
      expect(chat['ziel'], 'M10005');
      final fax = v.firstWhere((x) => x['methode'] == 'fax');
      expect(fax['fehler'], 'Gegenstelle besetzt');
    });

    test('ein Fehlversuch steht drin und ist als solcher erkennbar', () {
      // Nur Erfolge zu protokollieren versteckt genau die Lücke, in der
      // jemand glaubte, das Papier sei unterwegs.
      final v = versandLesen(eintrag['versand']);
      final misslungen = v.where((x) => x['ergebnis'] == 'fehler').toList();
      expect(misslungen, hasLength(1));
      expect((misslungen.first['fehler'] as String), isNotEmpty);
    });

    test('Chat trägt die Übersetzung, die Unterschrift immer Deutsch', () {
      // ⚠️ Der Kern der Trennung: gelesen wird in der eigenen Sprache,
      // unterschrieben wird die deutsche Fassung. Andersherum beglaubigte
      // ein Siegel das falsche Dokument.
      final v = versandLesen(eintrag['versand']);
      expect(v.firstWhere((x) => x['methode'] == 'chat')['fassung'], 'ro');
      expect(v.firstWhere((x) => x['methode'] == 'signatur')['fassung'], 'de');
    });

    test('die Unterschrift hält den Rückweg zum Beweisbündel fest', () {
      final sig = versandLesen(eintrag['versand']).firstWhere((x) => x['methode'] == 'signatur');
      expect(sig['signatur_id'], 99);
    });

    test('fehlendes oder leeres Protokoll wirft nicht', () {
      // ⚠️ PHP macht aus einer leeren Liste `[]`, nicht `{}` — und eine
      // ältere Serverfassung liefert den Schlüssel gar nicht. Beides heißt
      // „noch nicht verschickt", nicht „Fehler".
      expect(versandLesen(jsonDecode('[]')), isEmpty);
      expect(versandLesen(null), isEmpty);
      expect(versandLesen(jsonDecode('{}')), isEmpty);
    });
  });
}
