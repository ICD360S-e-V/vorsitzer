import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die Kopplungen der Sozialamts-Vollmacht. Geprüft wird der Quelltext: das
/// Geprüfte zeigt sonst nur ein laufender Server mit angemeldetem Vorstand,
/// und das PHP liegt in keinem Repository.
void main() {
  late String tab;
  late String schirm;
  late String api;

  setUpAll(() {
    tab    = File('lib/widgets/sozialamt_vollmacht_tab.dart').readAsStringSync();
    schirm = File('lib/widgets/behorde_sozialamt.dart').readAsStringSync();
    api    = File('lib/services/api_service.dart').readAsStringSync();
  });

  group('Der Reiter hängt am richtigen Ort', () {
    test('sechs Reiter, Vollmacht neben Korrespondenz', () {
      expect(schirm.contains('DefaultTabController(length: 6'), isTrue);
      final korr = schirm.indexOf("text: 'Korrespondenz'");
      final voll = schirm.indexOf("text: 'Vollmacht'");
      expect(korr, greaterThan(0));
      expect(voll, greaterThan(korr), reason: 'Vollmacht muss NEBEN Korrespondenz stehen');
    });

    test('der Reiter wird auch gezeichnet', () {
      expect(schirm.contains('SozialamtVollmachtTab('), isTrue);
    });
  });

  group('Die ganze Akte, nicht der Antrag', () {
    test('das ERZEUGEN schickt keine antrag_id mit', () {
      // ⚠️ Festlegung des Vorsitzenden vom 05.09.2026: die Vollmacht gilt der
      // ganzen Akte des Mitglieds bei diesem Amt. § 13 SGB X verlangt die
      // Bindung an ein Verfahren nicht — die stammt aus § 14 Abs. 1 Satz 2
      // VwVfG und gilt nur für das Landratsamt.
      //
      // ⚠️ Zugeschnitten auf `_erzeugen()`, und der Zuschnitt hat einen Grund:
      // beim VERSAND wird sehr wohl eine antrag_id mitgegeben — dann trägt der
      // Betreff das Aktenzeichen jenes Antrags. Das bindet die Vollmacht
      // nicht, es adressiert den Brief. Über die ganze Datei gemessen wäre
      // diese Prüfung seit dem Versand-Zweig falsch rot.
      final a = tab.indexOf('Future<void> _erzeugen() async {');
      final b = tab.indexOf('Future<void> _zurUnterschrift(', a);
      expect(a, greaterThan(0), reason: '_erzeugen nicht gefunden — Test anpassen');
      expect(b, greaterThan(a));
      final erzeugen = tab.substring(a, b);
      expect(erzeugen.contains('antrag_id'), isFalse);
      expect(erzeugen.contains('vorfall_id'), isFalse);
      // Und die Zeile selbst trägt nach wie vor keine Antragsbindung.
      expect(tab.contains("'vorfall_id'"), isFalse);
    });

    test('der Reiter bekommt gar keine antragId', () {
      expect(RegExp(r'final\s+int\s+antragId').hasMatch(tab), isFalse);
    });

    test('und er sagt es auch auf dem Schirm', () {
      expect(tab.contains('gesamte Akte'), isTrue,
          reason: 'ohne den Satz liest man den Reiter als „Vollmacht für diesen Antrag"');
    });
  });

  group('Was an den Server geht', () {
    test("behoerde ist 'sozialamt'", () {
      expect(tab.contains("'behoerde': 'sozialamt'"), isTrue);
    });

    test('der Umfangskatalog kommt vom Server, nicht aus dem Client', () {
      // ⚠️ Der Bildschirm darf keine Option anbieten, die im PDF nicht steht —
      // sonst hätte jemand etwas bevollmächtigt, das er nie gelesen hat.
      expect(tab.contains("['umfang_katalog']"), isTrue);
      for (final k in ['bescheide', 'akteneinsicht', 'mehrbedarf', 'widerspruch']) {
        expect(tab.contains("'$k'"), isFalse,
            reason: 'Umfangspunkt „$k" steht fest im Client — er gehört auf den Server');
      }
    });

    test('der Signaturauftrag hängt an Tabelle und id, nie am Titel', () {
      // Der Titel ist bei jeder Vollmacht derselbe; über ihn verknüpft landet
      // der Stand auf der falschen Zeile.
      expect(tab.contains("quelleTabelle: 'member_vollmachten'"), isTrue);
      expect(tab.contains('quelleId: id'), isTrue);
    });

    test('das PDF geht aus dem Speicher in die Signatur, nicht über eine Datei', () {
      // Eine Zwischendatei schriebe den Klartext genau des Dokuments auf die
      // Platte, dessen Unversehrtheit gleich bezeugt wird.
      expect(tab.contains('anfordernAusBytes('), isTrue);
      expect(tab.contains('SignaturService().anfordern('), isFalse);
    });
  });

  group('Die beiden SMS-Links', () {
    test('der Reiter benutzt die gemeinsamen Knöpfe', () {
      expect(tab.contains('VollmachtLinkKnoepfe('), isTrue);
    });

    test('signieren erst, wenn die Unterschrift gestellt ist', () {
      // Der Signierlink FÜHRT zu einem offenen Vorgang, er legt keinen an.
      expect(tab.contains("signierbar: status == 'wartet_unterschriften'"), isTrue);
    });

    test('eigener Endpunkt — der Server prüft dort die Behörde', () {
      expect(api.contains('sozialamt_vollmacht_versand.php'), isTrue);
      expect(tab.contains('sozialamtVollmachtLinkSenden('), isTrue);
    });
  });

  group('Die Antwort wird unter dem richtigen Schlüssel gelesen', () {
    test("die Liste kommt aus 'vollmachten', nicht aus 'data'", () {
      // 🔴 Der Fehler, der es in den Betrieb geschafft hat: vollmacht_list.php
      // antwortet mit `['vollmachten' => …]`, die Antrags-Endpunkte desselben
      // Bildschirms mit `['data' => …]`. Mit dem falschen Schlüssel wurde die
      // Vollmacht jedes Mal erzeugt und erschien nie — kein Fehler, keine
      // Meldung, nur eine leere Liste.
      expect(tab.contains("l['vollmachten'] is List"), isTrue);
      expect(tab.contains("l['data']"), isFalse);
    });

    test('Katalog, Amt und Vorsitzender kommen aus der Wurzel der Antwort', () {
      // vollmacht_data.php legt sie direkt in die Wurzel — es gibt dort keine
      // `data`-Hülle (siehe jsonResponse).
      expect(tab.contains("d['recht']"), isTrue);
      expect(tab.contains("_daten['amt']"), isTrue);
      expect(tab.contains("_daten['vorsitzer']"), isTrue);
    });
  });

  group('Das Leseexemplar erreicht das Mitglied', () {
    test('per Chat, für Mitglieder MIT App', () {
      expect(tab.contains('_inDenChat('), isTrue);
      expect(tab.contains('uploadChatAttachments('), isTrue);
    });

    test('und zwar in SEINER Sprache, wenn es eine Übersetzung gibt', () {
      // ⚠️ Ohne den Typ `translation` ginge stillschweigend das deutsche Blatt
      // hinaus, während der Dialog eine Übersetzung angekündigt hat.
      expect(tab.contains("type: uebersetzt ? 'translation' : 'pdf'"), isTrue);
    });

    test('protokolliert wird ERST nach bestätigtem Empfang', () {
      // Eine Zeile, die eine Sendung behauptet, die nie ankam, ist genau die,
      // auf die sich später jemand verlässt.
      final i = tab.indexOf("final erfolg = res['success'] == true;");
      final j = tab.indexOf('sozialamtVollmachtVersandEintragen(');
      expect(i, greaterThan(0));
      expect(j, greaterThan(i), reason: 'Eintragen muss NACH der Erfolgsprüfung stehen');
      expect(tab.contains('if (erfolg) {'), isTrue);
    });

    test('die Zwischendatei wird wieder entfernt', () {
      expect(tab.contains('await temp.delete()'), isTrue);
    });

    test('das Versandprotokoll ist erreichbar', () {
      expect(tab.contains('sozialamtVollmachtVersandListe('), isTrue);
      expect(tab.contains('VollmachtLinkZeile(link: l)'), isTrue,
          reason: 'die Linkzeilen gehören abgesetzt neben die Sendungen');
    });

    test('der Weg steht ausgeschrieben da, nicht als Rohwert', () {
      expect(tab.contains('kVollmachtVersandWege['), isTrue);
    });
  });

  group('Versand an das Amt', () {
    test('nur die unterschriebene Fassung geht hinaus', () {
      // Der Server verweigert ohne Unterschriften; der Bildschirm sagt WARUM,
      // statt den Knopf nur grau zu zeigen.
      expect(tab.contains("z['bereit'] == true"), isTrue);
      expect(tab.contains('Erst unterschreiben lassen'), isTrue);
    });

    test('jeder Knopf nennt die Adresse, an die er schickt', () {
      // Ein Knopf „Per Fax" allein liesse offen, ob er in die Poststelle geht
      // oder zur Sachbearbeitung — und ein Fax an die falsche Stelle ist
      // schlimmer als keins.
      expect(tab.contains("'Poststelle: \$amtMail'"), isTrue);
      expect(tab.contains("'Fax: \$amtFax'"), isTrue);
    });

    test('Poststelle und Sachbearbeitung sind getrennte Knöpfe', () {
      expect(tab.contains("ziel: amtMail"), isTrue);
      expect(tab.contains("ziel: sbMail"), isTrue);
    });

    test('eine unbrauchbare Adresse wird genannt, nicht verschwiegen', () {
      // Wer nur einen fehlenden Knopf sieht, sucht den Fehler bei sich.
      expect(tab.contains("z['sb_email_gueltig'] != true"), isTrue);
      expect(tab.contains('keine gültige E-Mail'), isTrue);
    });

    test('die Adressen kommen vom Server, nicht aus dem Client', () {
      expect(tab.contains('sozialamtVollmachtVorlagen('), isTrue);
      // Keine fest getippte Behördenadresse im Bildschirm.
      expect(RegExp(r"'[a-z.]+@[a-z-]+\.[a-z]{2,}'").hasMatch(tab), isFalse);
    });

    test('der Grund eines Fehlschlags wird gezeigt', () {
      expect(tab.contains("r['message']"), isTrue);
    });
  });

  group('Die zuständige Person aus dem Antrag', () {
    test('wird als Empfänger angeboten', () {
      // 🔴 Sie steht im ANTRAG, nicht bei den Amtsdaten — und bei Mitgliedern,
      // deren Amt weder Mail noch Fax hat, ist sie der EINZIGE Sendeweg.
      expect(tab.contains("z['antrag_kontakte']"), isTrue);
      expect(tab.contains('Zuständige Person'), isTrue);
    });

    test('steht VOR der Poststelle', () {
      // Sie führt den Fall; die Poststelle verteilt ihn erst.
      final person = tab.indexOf("z['antrag_kontakte']");
      final post = tab.indexOf("z['amt_email_gueltig'] == true");
      expect(person, greaterThan(0));
      expect(post, greaterThan(person));
    });

    test('der Knopf trägt Leistung und Aktenzeichen', () {
      // Zwei Sachbearbeitungen desselben Mitglieds sähen sonst gleich aus.
      expect(tab.contains(r'$leistung'), isTrue);
      expect(tab.contains('Az. \$az'), isTrue);
    });

    test('die antrag_id geht mit — dafür trägt der Betreff das Aktenzeichen', () {
      expect(tab.contains("antragId: (k['antrag_id'] as num?)?.toInt() ?? 0"), isTrue);
      expect(api.contains("if (antragId > 0) 'antrag_id': antragId"), isTrue);
    });

    test('eine unbrauchbare Adresse wird auch hier genannt', () {
      expect(tab.contains('im Antrag berichtigen'), isTrue);
    });
  });

  group('Widerruf', () {
    test('sagt, dass er erst mit Zugang bei der Behörde wirkt', () {
      // Sonst hält jemand die Vollmacht für erledigt, während das Amt sie
      // weiter für gültig hält.
      expect(tab.contains('§ 13 Abs. 1 Satz 4 SGB X'), isTrue);
      expect(tab.contains('zugeht'), isTrue);
    });
  });
}
