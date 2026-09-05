import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/auslaenderbehoerde_dokumente.dart';
import 'package:icd360sev_vorsitzer/utils/auslaenderbehoerde_vorfaelle.dart';

/// ⚠️ Wörtliche Kopie von `abDokPlaetze()` aus
/// `api/helpers/auslaenderbehoerde_dok_lib.php`.
///
/// Das PHP liegt in keinem Repo — dies ist die EINZIGE Stelle im Baum, an der
/// eine Abweichung überhaupt auffallen kann. Weicht ein Name ab, verschwindet
/// der Reiter still bzw. der Upload wird mit 400 abgelehnt, und auf dem Schirm
/// sieht beides aus wie ein Fehler der App. Wer die Serverliste ändert, ändert
/// diese hier mit.
const _serverPlaetze = <String, List<String>>{
  'Aufenthaltserlaubnis beantragen (Erstantrag)': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Aufenthaltserlaubnis verlängern': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Aufenthaltserlaubnis zum Zweck der Ausbildung oder des Studiums': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Aufenthaltserlaubnis für eine Beschäftigung beantragen': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Aufenthaltserlaubnis zur Ausübung einer selbständigen Tätigkeit': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Aufenthaltserlaubnis zum Zweck der Forschung': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Blaue Karte EU beantragen': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Chancenkarte beantragen': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Niederlassungserlaubnis beantragen': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Erlaubnis zum Daueraufenthalt-EU beantragen': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Aufenthaltskarte oder Daueraufenthaltsbescheinigung (Freizügigkeit)': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Familiennachzug zu Ausländern — Aufenthaltserlaubnis beantragen': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Familiennachzug zu Deutschen — Aufenthaltserlaubnis beantragen': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Nachzug weiterer Familienangehöriger': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Aufenthaltstitel für ein minderjähriges Kind erteilen oder verlängern': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Aufenthaltstitel bei Asylantrag beantragen': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Elektronischen Aufenthaltstitel (eAT) beantragen': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'eAT bei neuem oder geändertem Nationalpass bestellen (Passübertrag)': ['titel', 'titel_rueckseite', 'zusatzblatt'],
  'Aufenthaltserlaubnis nach § 24 AufenthG (vorübergehender Schutz)': ['titel', 'titel_rueckseite', 'zusatzblatt', 'fortgeltungsnachweis'],
  'Aufenthaltsgestattung verlängern': ['titel'],
  'Duldung — Erteilung oder Verlängerung': ['titel'],
  'Ausbildungsduldung': ['titel'],
  'Beschäftigungsduldung': ['titel'],
  'Fiktionsbescheinigung': ['titel'],
  'Reiseausweis für Ausländer beantragen': ['titel'],
  'Reiseausweis für Flüchtlinge oder für Staatenlose beantragen': ['titel'],
  'Notreiseausweis für Ausländer': ['titel'],
  'Verpflichtungserklärung abgeben': ['titel'],
  'Integrationskurs — Verpflichtung oder Berechtigungsschein': ['titel'],
};

void main() {
  group('Kopplung an den Server', () {
    test('Client und Server ordnen dieselben Plätze zu', () {
      for (final e in _serverPlaetze.entries) {
        expect(abDokArtenFuerTyp(e.key), e.value,
            reason: 'Client und Server sind sich bei „${e.key}" uneinig');
      }
    });

    test('der Client vergibt keine Plätze, die der Server nicht kennt', () {
      for (final t in kAbVorfallTypen) {
        final arten = abDokArtenFuerTyp(t.name);
        if (arten.isEmpty) continue;
        expect(_serverPlaetze.containsKey(t.name), isTrue,
            reason: '„${t.name}" hat im Client einen Reiter, der Server lehnt '
                'den Upload aber mit 400 ab — das sieht wie ein App-Fehler aus');
      }
    });

    test('jeder Servereintrag ist ein echter Vorfalltyp', () {
      // Ein Tippfehler in der Serverliste träfe einen Typ, den es nicht gibt:
      // der Reiter erschiene dann NIE, ohne dass etwas fehlschlägt.
      for (final name in _serverPlaetze.keys) {
        expect(abTypFinden(name), isNotNull,
            reason: '„$name" steht in der Serverliste, aber in keinem Katalog');
      }
    });
  });

  group('Zuordnung', () {
    test('die Rückseite ist ein eigener Platz', () {
      // 🔴 Das Feld „Anmerkungen" mit der Erwerbstätigkeit steht HINTEN. Ein
      // Scan nur der Vorderseite lässt genau die Auskunft weg, wegen der man
      // das Papier überhaupt aufhebt.
      expect(abDokArtenFuerTyp('Aufenthaltserlaubnis verlängern'),
          contains(kAbDokRueckseite));
      expect(abDokZweckFuerArt(kAbDokRueckseite), contains('Anmerkungen'));
      expect(abDokZweckFuerArt(kAbDokRueckseite), contains('Erwerbstätigkeit'));
    });

    test('das Zusatzblatt nennt den Zweck und den Aufdruck, nicht nur die Farbe', () {
      // ⚠️ Die Aufenthaltsgestattung ist EBENFALLS eine grüne Klappkarte. Wer
      // nur „das grüne Blatt" sagt, bekommt von Asylsuchenden das falsche
      // Dokument — und amtlich festgelegt ist die Farbe nirgends.
      final z = abDokZweckFuerArt(kAbDokZusatzblatt);
      expect(z, contains('Nebenbestimmungen'));
      expect(z, contains('siehe Zusatzblatt'));
      expect(abDokTitelFuerArt(kAbDokZusatzblatt, null), 'Zusatzblatt zum Aufenthaltstitel',
          reason: 'der Name steht vorn, die Farbe darf nur ein Zusatz sein');
    });

    test('§ 24 hat zusätzlich den Fortgeltungsnachweis', () {
      // Weil keine neue Karte ausgestellt wird, sieht die alte für jeden
      // Arbeitgeber abgelaufen aus.
      expect(abDokArtenFuerTyp(kUkraineTyp), contains(kAbDokFortgeltung));
      expect(abDokArtenFuerTyp('Aufenthaltserlaubnis verlängern'),
          isNot(contains(kAbDokFortgeltung)),
          reason: 'nur bei § 24 gibt es diese Bescheinigung');
    });

    test('optional ist, was es nicht in jedem Fall gibt', () {
      // Das Zusatzblatt gibt es nur, WENN Nebenbestimmungen vergeben sind.
      // Ein leerer Platz ist dort kein fehlendes Dokument.
      expect(abDokOptional(kAbDokZusatzblatt), isTrue);
      expect(abDokOptional(kAbDokFortgeltung), isTrue);
      expect(abDokOptional(kAbDokTitel), isFalse);
      expect(abDokOptional(kAbDokRueckseite), isFalse);
    });

    test('nur die Karte hat ein Zusatzblatt', () {
      // Das Zusatzblatt gehört zur eAT-Karte. Zu einer Duldung, einer
      // Verpflichtungserklärung oder einem Berechtigungsschein gibt es keines.
      expect(abDokArtenFuerTyp('Aufenthaltserlaubnis verlängern'),
          contains(kAbDokZusatzblatt));
      for (final ohne in [
        'Fiktionsbescheinigung',
        'Duldung — Erteilung oder Verlängerung',
        'Verpflichtungserklärung abgeben',
        'Notreiseausweis für Ausländer',
      ]) {
        expect(abDokArtenFuerTyp(ohne), [kAbDokTitel],
            reason: 'zu „$ohne" gehört weder Rückseite noch Zusatzblatt');
      }
    });

    test('Vorgänge ohne eigenes Papier haben gar keinen Reiter', () {
      for (final ohne in [
        'Rückkehrberatung',
        'Beschleunigtes Fachkräfteverfahren',
        kAbSonstigesTyp,
      ]) {
        expect(abDokArtenFuerTyp(ohne), isEmpty);
        expect(abHatDokumente(ohne), isFalse);
      }
    });

    test('unbekannter Typ bekommt keinen Reiter statt eines leeren', () {
      expect(abDokArtenFuerTyp('gibt es nicht'), isEmpty);
      expect(abDokArtenFuerTyp(null), isEmpty);
      expect(abDokArtenFuerTyp(''), isEmpty);
    });

    test('§ 24 hat alle vier Plätze', () {
      // Karte, Rückseite und Zusatzblatt wie sonst — die Fortgeltung ändert
      // nur, dass das aufgedruckte Datum nichts mehr besagt, und fügt den
      // Nachweis hinzu.
      expect(abDokArtenFuerTyp(kUkraineTyp),
          [kAbDokTitel, kAbDokRueckseite, kAbDokZusatzblatt, kAbDokFortgeltung]);
    });
  });

  group('Dateiprüfung', () {
    test('PNG ist erlaubt', () {
      // Anders als beim Bürgeramt — Entscheidung des Users, weil die Papiere
      // meist abfotografiert werden.
      expect(kAbDokEndungen, contains('png'));
      expect(abDokAblehnung('titel.png', 1000), isNull);
    });

    test('PDF, JPG und JPEG ebenso', () {
      for (final n in ['a.pdf', 'a.jpg', 'a.JPEG', 'A.Pdf']) {
        expect(abDokAblehnung(n, 1000), isNull, reason: n);
      }
    });

    test('alles andere wird abgelehnt', () {
      for (final n in ['a.gif', 'a.exe', 'a.tiff', 'a.pdf.exe', 'ohnepunkt']) {
        expect(abDokAblehnung(n, 1000), isNotNull, reason: n);
      }
    });

    test('leer und zu groß werden abgelehnt', () {
      expect(abDokAblehnung('a.pdf', 0), isNotNull);
      expect(abDokAblehnung('a.pdf', kAbDokMaxBytes + 1), isNotNull);
      expect(abDokAblehnung('a.pdf', kAbDokMaxBytes), isNull);
    });

    test('die Grenze deckt sich mit dem Server', () {
      expect(kAbDokMaxBytes, 20 * 1024 * 1024);
    });
  });

  group('Kopplung an den Bildschirm', () {
    String quelle(String pfad) => File(pfad)
        .readAsLinesSync()
        .where((z) => !z.trimLeft().startsWith('//'))
        .join('\n');

    test('der Upload schickt die Art mit', () {
      // Ohne `art` antwortet der Server mit 400 — und zwar bei JEDEM Upload.
      final s = quelle('lib/services/api_service.dart');
      final i = s.indexOf('uploadAuslaenderbehoerdeDokument');
      expect(i, greaterThan(-1));
      final block = s.substring(i, i + 1600);
      expect(block, contains("req.fields['art'] = art;"));
      expect(block, contains('req.headers.addAll(kopf);'),
          reason: 'ohne addAll fehlt der Bearer — dann 401 bei jedem Upload');
    });

    test('das Papier wird aus dem Arbeitsspeicher gezeigt, nie von der Platte', () {
      // Ein Aufenthaltstitel trägt Name, Geburtsdatum, Lichtbild und Status.
      final s = quelle('lib/widgets/behorde_auslaenderbehoerde.dart');
      final i = s.indexOf('Future<void> _dokAnsehen');
      expect(i, greaterThan(-1));
      final block = s.substring(i, s.indexOf('Future<void> _dokLoeschen', i));
      expect(block, contains('showFromBytes'));
      for (final verboten in [
        'writeAsBytes',
        'getTemporaryDirectory',
        'OpenFile',
        'Share',
      ]) {
        expect(block.contains(verboten), isFalse,
            reason: '„$verboten" legt den Ausweis auf der Platte ab');
      }
    });

    test('ein laufender Upload sperrt nur den eigenen Knopf', () {
      // Mit einem bloßen bool sperrte der Titel-Upload auch das Zusatzblatt.
      final s = quelle('lib/widgets/behorde_auslaenderbehoerde.dart');
      expect(s, contains('String? _laedt;'));
      expect(s, contains('final laeuft = _laedt == art;'));
    });

    test('der Reiter fehlt, wo es kein Papier gibt', () {
      final s = quelle('lib/widgets/behorde_auslaenderbehoerde.dart');
      expect(s, contains('abDokArtenFuerTyp('));
      expect(s, contains('length: arten.isEmpty ? 4 : 5'));
    });

    test('es gibt einen zweiten Weg: aus dem Cloud', () {
      final s = quelle('lib/widgets/behorde_auslaenderbehoerde.dart');
      expect(s, contains('CloudPickerHelper.pickFiles('));
      // ⚠️ maxFiles: 1 — je Platz nimmt der Server genau eine Datei. Ohne die
      // Grenze dürfte man drei wählen, von denen zwei stillschweigend fallen.
      expect(s, contains('maxFiles: 1'));
      // ⚠️ Derselbe Filter wie beim Geräte-Weg. Die Cloud-Dialoge kennen keine
      // Typfilter; ohne ihn wiese erst der Server ab.
      final i = s.indexOf('Future<void> _dokAusCloud');
      expect(i, greaterThan(-1));
      final block = s.substring(i, s.indexOf('Future<void> _dokUebernehmen', i));
      expect(block, contains('allowedExtensions: kAbDokEndungen'));
    });

    test('welcher Speicher sich öffnet, entscheidet der Helfer', () {
      // ⚠️ Ein hier durchgereichtes Kennzeichen wäre die Stelle, an der später
      // der falsche — und damit leere — Speicher aufgeht. Der Helfer nimmt nur
      // die memberId und wählt selbst.
      final s = quelle('lib/widgets/behorde_auslaenderbehoerde.dart');
      final i = s.indexOf('Future<void> _dokAusCloud');
      final block = s.substring(i, s.indexOf('Future<void> _dokUebernehmen', i));
      expect(block, contains('memberId: widget.userId'));
      // Die Beschriftung nennt den Speicher, damit klar ist, wessen Cloud.
      expect(s, contains('CloudPickerHelper.istVerschluesselt(widget.userId)'));
      expect(s, contains('Aus Cloud des Mitglieds'));
      expect(s, contains('Aus eigenem Cloud'));
    });

    test('beide Wege laufen durch dieselbe Prüfung', () {
      // Zwei getrennte Upload-Zweige wichen über kurz oder lang ab — einer
      // hätte die Größengrenze, der andere nicht.
      final s = quelle('lib/widgets/behorde_auslaenderbehoerde.dart');
      expect(s, contains('_dokUebernehmen(art, titel,'));
      expect('_dokUebernehmen('.allMatches(s).length, greaterThanOrEqualTo(3),
          reason: 'Gerät und Cloud müssen beide dorthin führen');
      // Die Prüfung steht genau einmal.
      expect('abDokAblehnung('.allMatches(s).length, 1);
    });

    test('das Hochladedatum steht an jedem Dokument', () {
      // Ohne Datum ließe sich nicht sagen, ob das hinterlegte Zusatzblatt noch
      // den heutigen Stand zeigt — es wird auch OHNE neue Karte neu ausgestellt.
      final s = quelle('lib/widgets/behorde_auslaenderbehoerde.dart');
      expect(s, contains('_hochgeladenAm('));
      expect(s, contains("d['created_at']"));
    });
  });
}
