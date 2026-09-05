import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Prüft die Kopplungen des Reiters „Maßnahme (Träger)" am Quelltext.
///
/// ⚠️ Am Quelltext, weil die betroffenen Stellen nur mit laufendem Server,
/// echtem Bearer und einem Dateiwähler zu erreichen wären — dieselbe
/// Vorgehensweise wie sipgate_lebenszeichen_test.dart. Jede Zusicherung ist
/// durch Rückbau gegengeprüft.
void main() {
  late String modal;
  late String api;
  late String tab;

  setUpAll(() {
    modal = File('lib/widgets/massnahme_detail_modal.dart').readAsStringSync();
    api = File('lib/services/api_service.dart').readAsStringSync();
    tab = File('lib/widgets/jobcenter_massnahme_tab.dart').readAsStringSync();
  });

  /// Zeilenkommentare weg, bevor gesucht wird. Sonst bestätigt der Test eine
  /// auskommentierte, also tote Zeile — genau das ist bei der Bürgeramt-Probe
  /// in der Gegenprobe passiert.
  String ohneKommentare(String s) => s
      .split('\n')
      .where((z) => !z.trimLeft().startsWith('//'))
      .join('\n');

  group('Upload', () {
    // ⚠️ Ein MultipartRequest setzt die Kopfzeilen NICHT von selbst. Genau
    // daran ist im August platform/korrespondenz_create.php gescheitert: 401,
    // und auf dem Schirm sieht das aus wie ein Fehler der App.
    test('Multipart-Upload schickt den Bearer über addAll(_headers)', () {
      final block = api.substring(api.indexOf('massnahmeDokUpload'));
      final ende = block.indexOf('massnahmeDokDownload');
      expect(ohneKommentare(block.substring(0, ende)).contains('addAll(_headers)'), isTrue,
          reason: 'ohne addAll(_headers) kommt kein Bearer mit — HTTP 401');
    });

    test('erlaubt sind genau PDF, JPEG und PNG', () {
      expect(ohneKommentare(modal).contains("['pdf', 'jpg', 'jpeg', 'png']"), isTrue);
    });

    // ⚠️ CloudPickerHelper legt die Datei ENTSCHLÜSSELT im temporären
    // Verzeichnis ab. Sie muss weg, ob der Upload klappt oder nicht — ein
    // Fehlschlag ist kein Grund, Klartext liegen zu lassen.
    test('die entschlüsselte Cloud-Zwischendatei wird im finally gelöscht', () {
      final i = modal.indexOf('Future<void> _hochladen');
      final j = modal.indexOf('Future<void> _ansehen');
      final rumpf = ohneKommentare(modal.substring(i, j));
      expect(rumpf.contains('} finally {'), isTrue);
      final fin = rumpf.indexOf('} finally {');
      expect(rumpf.substring(fin).contains('deleteSync()'), isTrue,
          reason: 'das Löschen muss im finally stehen, nicht im Erfolgszweig');
    });
  });

  group('Ansehen', () {
    // Der Bescheid berührt die Platte des Geräts nie.
    test('wird aus dem Arbeitsspeicher gezeigt, nicht von der Platte', () {
      final i = modal.indexOf('Future<void> _ansehen');
      final j = modal.indexOf('Future<void> _loeschen');
      final rumpf = ohneKommentare(modal.substring(i, j));
      expect(rumpf.contains('showFromBytes'), isTrue);
      for (final verboten in ['writeAsBytes', 'getTemporaryDirectory', 'OpenFilex', 'Share']) {
        expect(rumpf.contains(verboten), isFalse,
            reason: '$verboten würde den Bescheid auf die Platte schreiben');
      }
    });

    // ⚠️ 410 heißt: die Prüfsumme passt nicht mehr. Das darf nicht als
    // gewöhnlicher Fehler durchgehen und schon gar nicht angezeigt werden.
    test('eine veränderte Datei (410) wird benannt, nicht angezeigt', () {
      final i = modal.indexOf('Future<void> _ansehen');
      final j = modal.indexOf('Future<void> _loeschen');
      final rumpf = ohneKommentare(modal.substring(i, j));
      expect(rumpf.contains('410'), isTrue);
      expect(rumpf.indexOf('410') < rumpf.indexOf('showFromBytes'), isTrue,
          reason: 'die Prüfung muss VOR dem Anzeigen stehen');
    });
  });

  group('Zugehörigkeit', () {
    // ⚠️ Eine hochgezählte id darf keine fremden Bescheide liefern. Genau
    // diese Lücke steckte im August in tickets/attachments und
    // platform/korrespondenz_download.
    test('jeder Dateiaufruf trägt die user_id mit', () {
      for (final m in ['massnahmeDokListe', 'massnahmeDokDownload', 'massnahmeDokLoeschen']) {
        final i = api.indexOf(m);
        expect(i, greaterThan(0), reason: '$m fehlt');
        expect(api.substring(i, i + 700).contains('user_id'), isTrue,
            reason: '$m ohne user_id — fremde Dokumente wären lesbar');
      }
    });
  });

  group('Verdrahtung', () {
    test('die Karte öffnet die Detailansicht', () {
      final o = ohneKommentare(tab);
      expect(o.contains('onTap: () => _detailOeffnen(z)'), isTrue);
      expect(o.contains('MassnahmeDetailModal('), isTrue);
    });

    test('das Modal hat genau die drei Reiter', () {
      expect(RegExp(r'TabController\(length:\s*3').hasMatch(modal), isTrue);
      for (final t in ['Details', 'Bewilligung', 'Korrespondenz']) {
        expect(modal.contains("text: '$t'"), isTrue, reason: 'Reiter fehlt: $t');
      }
    });

    // ⚠️ Zeichengleich mit den ENUM-Spalten und mit $MN_RICHTUNG /
    // $MN_KONTAKTART in massnahme_manage.php. Das PHP liegt in keinem Repo;
    // weicht die Liste ab, weist der Server ab und es sieht wie ein
    // App-Fehler aus.
    test('Richtung und Kontaktart stimmen mit dem Server überein', () {
      expect(modal.contains("const _kRichtung = ['eingang', 'ausgang'];"), isTrue);
      for (final k in ['post', 'email', 'fax', 'telefon', 'persoenlich', 'online']) {
        expect(modal.contains("'$k'"), isTrue, reason: 'Kontaktart fehlt: $k');
      }
    });
  });
}
