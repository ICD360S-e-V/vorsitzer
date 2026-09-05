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
    test('es wird keine antrag_id mitgeschickt', () {
      // ⚠️ Festlegung des Vorsitzenden vom 05.09.2026: die Vollmacht gilt der
      // ganzen Akte des Mitglieds bei diesem Amt. § 13 SGB X verlangt die
      // Bindung an ein Verfahren nicht — die stammt aus § 14 Abs. 1 Satz 2
      // VwVfG und gilt nur für das Landratsamt.
      expect(tab.contains('antrag_id'), isFalse);
      expect(tab.contains('vorfall_id'), isFalse);
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

  group('Widerruf', () {
    test('sagt, dass er erst mit Zugang bei der Behörde wirkt', () {
      // Sonst hält jemand die Vollmacht für erledigt, während das Amt sie
      // weiter für gültig hält.
      expect(tab.contains('§ 13 Abs. 1 Satz 4 SGB X'), isTrue);
      expect(tab.contains('zugeht'), isTrue);
    });
  });
}
