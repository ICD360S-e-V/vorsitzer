import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/buergeramt_dokument.dart';

/// Die Meldebestätigung eines Bürgeramt-Vorfalls.
///
/// ⚠️ EIN TEIL LIEST DEN QUELLTEXT, UND DAS IST ABSICHT.
/// Die Zuordnung „welcher Vorfalltyp trägt eine Bestätigung" steht an drei
/// Stellen: in `kBuergeramtDokTitel`, in `_vorfallTypen` im Bildschirm (freier
/// Text, keine Aufzählung) und in `baDokArten()` auf dem Server — und das PHP
/// liegt in keinem Repo. Weicht eine Seite ab, **schlägt nichts fehl**: der
/// Reiter verschwindet still bzw. der Upload wird mit 400 abgewiesen, was für
/// den Nutzer wie ein Fehler der App aussieht. Dieser Test ist die einzige
/// Stelle im Baum, an der so ein Auseinanderlaufen überhaupt auffallen kann.
///
/// Derselbe Aufbau wie `sipgate_lebenszeichen_test.dart` und
/// `chat_reaktionen_test.dart`.
void main() {
  String quelle(String pfad) {
    final f = File(pfad);
    expect(f.existsSync(), isTrue, reason: 'Datei fehlt: $pfad');
    return f.readAsStringSync();
  }

  /// Quelltext OHNE Zeilenkommentare.
  ///
  /// ⚠️ Ohne das besteht jede dieser Prüfungen auch, wenn die Zeile
  /// auskommentiert ist — in der Gegenprobe blieb genau der Bearer-Test grün,
  /// nachdem `req.headers.addAll(kopf);` zu `// req.headers.addAll(kopf);`
  /// geworden war. Ein Test, der eine tote Zeile bestätigt, prüft nichts.
  String ohneKommentare(String q) => q
      .split('\n')
      .where((z) => !z.trimLeft().startsWith('//'))
      .join('\n');

  /// Was der Server in `BA_DOK_ERLAUBT` stehen hat. Von Hand nachgeführt —
  /// eine hier zusätzlich angebotene Endung gäbe ein 400.
  const serverEndungen = ['pdf', 'jpg', 'jpeg'];

  group('Zuordnung Vorfalltyp → Bestätigung', () {
    test('genau die drei Meldevorgänge tragen eine', () {
      expect(buergeramtDokTitel('Anmeldung (Wohnsitz)'), 'Meldebestätigung');
      expect(buergeramtDokTitel('Ummeldung (Wohnsitz)'), 'Ummeldebestätigung');
      expect(buergeramtDokTitel('Abmeldung (Wohnsitz)'), 'Abmeldebestätigung');
    });

    test('jeder andere Vorfalltyp bekommt keinen Reiter', () {
      for (final t in [
        'Personalausweis beantragen',
        'Reisepass beantragen',
        'Gewerbeanmeldung',
        'Tafelladen-Kundenkarte (LobbyCard)',
        '',
      ]) {
        expect(buergeramtDokTitel(t), isNull, reason: t);
      }
      expect(buergeramtDokTitel(null), isNull);
    });

    test('die Schlüssel stehen zeichengleich in _vorfallTypen', () {
      final src = ohneKommentare(quelle('lib/widgets/behorde_einwohnermeldeamt.dart'));
      final liste = RegExp(r'static const _vorfallTypen = \[(.*?)\];', dotAll: true)
          .firstMatch(src);
      expect(liste, isNotNull, reason: '_vorfallTypen nicht gefunden');
      final typen = RegExp(r"'([^']+)'")
          .allMatches(liste!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();
      for (final k in kBuergeramtDokTitel.keys) {
        expect(typen, contains(k),
            reason: 'Schlüssel „$k" kommt in _vorfallTypen nicht (mehr) vor — '
                'der Reiter würde still verschwinden');
      }
    });

    test('jede Art hat einen erklärenden Satz, die anderen keinen', () {
      for (final k in kBuergeramtDokTitel.keys) {
        expect(buergeramtDokHinweis(k), isNotEmpty, reason: k);
      }
      expect(buergeramtDokHinweis('Reisepass beantragen'), isEmpty);
    });

    test('der Ummeldungs-Hinweis nennt den amtlichen Namen', () {
      // Die Beschriftung „Ummeldebestätigung" ist unsere; amtlich heißt das
      // Papier auch dort „Meldebestätigung" (§ 24 Abs. 3 BMG). Wer die
      // Beschriftung ändert, darf den erklärenden Satz nicht mitnehmen.
      expect(buergeramtDokHinweis('Ummeldung (Wohnsitz)'), contains('§ 24 Abs. 3 BMG'));
    });
  });

  group('Was der Bildschirm abweist, bevor der Server es tut', () {
    test('erlaubt sind genau PDF, JPG und JPEG', () {
      expect(kBuergeramtDokEndungen, serverEndungen,
          reason: 'muss zu BA_DOK_ERLAUBT auf dem Server passen');
      for (final n in ['scan.pdf', 'Scan.PDF', 'foto.jpg', 'foto.JPEG']) {
        expect(buergeramtDokAblehnung(n, 1234), isNull, reason: n);
      }
    });

    test('PNG, TIFF und Namenlose werden abgewiesen', () {
      for (final n in ['bild.png', 'scan.tif', 'brief.docx', 'ohneendung']) {
        expect(buergeramtDokAblehnung(n, 1234), isNotNull, reason: n);
      }
    });

    test('leer und zu groß werden abgewiesen', () {
      expect(buergeramtDokAblehnung('scan.pdf', 0), isNotNull);
      expect(buergeramtDokAblehnung('scan.pdf', kBuergeramtDokMaxBytes + 1), isNotNull);
      expect(buergeramtDokAblehnung('scan.pdf', kBuergeramtDokMaxBytes), isNull);
    });

    test('der Grund ist Klartext, kein bool', () {
      // „Nichts passiert" nach dem Auswählen ist für den Nutzer nicht von
      // einem Fehler der App zu unterscheiden.
      expect(buergeramtDokAblehnung('bild.png', 10), contains('PDF'));
      expect(buergeramtDokAblehnung('scan.pdf', 0), contains('leer'));
    });
  });

  group('Kopplung an Bildschirm und Dienst', () {
    test('der Reiter hängt am Typ, nicht an einer festen Reiterzahl', () {
      final src = ohneKommentare(quelle('lib/widgets/behorde_einwohnermeldeamt.dart'));
      expect(src, contains('buergeramtDokTitel('),
          reason: 'der Bildschirm entscheidet sonst selbst, welcher Typ eine trägt');
      expect(src.contains('DefaultTabController(length: 4,'), isFalse,
          reason: 'feste 4 Reiter — der fünfte wäre nie erreichbar');
      expect(src, contains('dokTitel == null ? 4 : 5'));
    });

    test('das Dokument wird beim Neuladen auch wieder auf null gesetzt', () {
      // Sonst bliebe eine gerade gelöschte Bestätigung auf dem Schirm stehen —
      // derselbe Fehler wie beim Chat, wo Bekanntes nie aktualisiert wurde.
      final src = ohneKommentare(quelle('lib/widgets/behorde_einwohnermeldeamt.dart'));
      expect(src, contains("res['dokument']"));
      expect(src, contains('_dokument = dRes is Map ? Map<String, dynamic>.from(dRes) : null;'));
    });

    test('der Upload schickt den Bearer mit', () {
      // ⚠️ MultipartRequest setzt die Kopfzeilen selbst. Ohne `addAll` fehlt
      // der Bearer — genau der Fehler, der im August
      // platform/korrespondenz_create.php mit 401 lahmlegte.
      final src = ohneKommentare(quelle('lib/services/api_service.dart'));
      final i = src.indexOf('uploadBuergeramtDokument');
      expect(i, isNot(-1));
      final rumpf = src.substring(i, i + 1600);
      expect(rumpf, contains('req.headers.addAll(kopf)'));
      expect(rumpf, contains("Map<String, String>.from(_headers)"));
    });

    test('die Bestätigung wird nicht auf die Platte geschrieben', () {
      // Eine Meldebestätigung trägt Name und Anschrift. Auf dem Server liegt
      // sie verschlüsselt; sie hier entschlüsselt abzulegen gäbe das wieder
      // her — und ein fremder Betrachter behielte sie ohnehin.
      final src = ohneKommentare(quelle('lib/widgets/behorde_einwohnermeldeamt.dart'));
      final i = src.indexOf('Future<void> _dokAnsehen(');
      expect(i, isNot(-1));
      final rumpf = src.substring(i, src.indexOf('Future<void> _dokLoeschen('));
      expect(rumpf, contains('FileViewerDialog.showFromBytes'));
      for (final verboten in ['writeAsBytes', 'getTemporaryDirectory', 'OpenFile', 'Share']) {
        expect(rumpf.contains(verboten), isFalse, reason: '$verboten im Ansehen-Pfad');
      }
    });
  });
}
