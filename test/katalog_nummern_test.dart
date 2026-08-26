import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 🔴 LANR UND BSNR MÜSSEN IN DEN EIGENEN KATALOG.
///
/// Alle sechs Arzt-Reiter riefen dafür `manageArzt` auf, also
/// `aerzte_manage.php`. In fünf davon stammt die id aber aus einem ANDEREN
/// Katalog, und die id-Folgen sind je Tabelle eigenständig (siehe
/// `lib/utils/arzt_quelle.dart`): die Nummern landeten auf einer wildfremden
/// Praxis, im eigenen Reiter erschienen sie nie. Beides ohne Fehlermeldung —
/// und beide Nummern stehen auf der Überweisung.
///
/// ⚠️ Dieser Test liest den QUELLTEXT, nicht das Verhalten. `ApiService` ist
/// ein Singleton ohne einspeisbaren HTTP-Client, ein Netz-Test wäre also nur
/// mit Umbau zu haben. Geprüft wird deshalb genau die Kopplung, die hier schon
/// einmal gerissen ist: welcher Endpunkt in welcher Datei steht. In diesem
/// Projekt sind von einem Arzt-Reiter sechs Kopien entstanden — eine siebte
/// mit falschem Endpunkt fiele sonst wieder niemandem auf.
void main() {
  const erwartet = <String, String>{
    'mitgliederverwaltung_arzten_augenarzt': 'augenarzt_datenbank_manage.php',
    'mitgliederverwaltung_arzten_hno': 'hno_datenbank_manage.php',
    'mitgliederverwaltung_arzten_rheumatologie': 'rheumatologie_datenbank_manage.php',
    'mitgliederverwaltung_arzten_md': 'md_datenbank_manage.php',
    // Der Krankenhaus-Reiter liest aus `kliniken_datenbank`; die Tabelle führt
    // LANR und BSNR seit dem 26.08.2026 selbst.
    'mitgliederverwaltung_arzten_krankenhaus': 'kliniken_manage.php',
  };

  String quelle(String name) => File('lib/widgets/$name.dart').readAsStringSync();

  erwartet.forEach((datei, endpunkt) {
    test('$datei schreibt die Nummern nach $endpunkt', () {
      final s = quelle(datei);
      final treffer = RegExp(r"updateKatalogNummern\(\s*\n?\s*endpunkt: '([^']+)'")
          .allMatches(s)
          .map((m) => m.group(1))
          .toList();
      expect(treffer, [endpunkt],
          reason: 'genau ein Aufruf, und er muss auf den eigenen Katalog zeigen');
    });

    test('$datei ruft für die Nummern NICHT manageArzt auf', () {
      // `manageArzt` ist `aerzte_manage.php` — ein anderer Katalog mit einer
      // eigenen id-Folge.
      final s = quelle(datei);
      expect(s.contains("'action': 'update_nummern'"), isFalse,
          reason: 'der alte Aufruf über manageArzt ist zurückgekehrt');
    });
  });

  test('gesundheit_tab_content bleibt bei aerzte_datenbank — dort stimmt es', () {
    // Die sechzehn Reiter dieses Widgets wählen wirklich aus
    // `aerzte_datenbank`; hier wäre ein Wechsel der Fehler.
    final s = quelle('gesundheit_tab_content');
    expect(s.contains("'action': 'update_nummern'"), isTrue);
    expect(s.contains('updateKatalogNummern'), isFalse);
  });

  test('der Klinik-Katalog ist schreibbar geworden', () {
    // `kliniken_manage.php` kannte bis zum 26.08.2026 nur `search`; die
    // Schreibhälfte lag auf einer Tabelle mit 0 Zeilen, die niemand las.
    final api = File('lib/services/api_service.dart').readAsStringSync();
    expect(api.contains('manageKlinik'), isTrue);
    expect(api.contains('kliniken_manage.php'), isTrue);
    // Die geräumte Tabelle hat keinen Aufrufer mehr.
    expect(api.contains('krankenhaus_datenbank_manage.php'), isFalse);
    expect(api.contains('KrankenhausDatenbank'), isFalse);
  });
}
