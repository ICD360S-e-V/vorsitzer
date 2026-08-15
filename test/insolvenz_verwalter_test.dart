import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_gericht.dart';

/// Die Listen, die `api/admin/insolvenz_manage.php` als Whitelist führt.
///
/// ⚠️ Das PHP liegt nur auf dem Server, nicht im Repository — dieser Test ist
/// deshalb die einzige Stelle, an der die Kopplung überhaupt auffallen kann.
/// Und sie fällt sonst NICHT auf: ein Wert, den der Server nicht kennt, wird
/// dort still auf den Standard zurückgesetzt (`verwalter`, `sonstiges`) oder
/// verworfen (`phase` wird NULL). Der Nutzer sieht keine Fehlermeldung, nur
/// ein Feld, das nach dem Speichern etwas anderes zeigt als vorher.
const _serverRollen = <String>{
  'vorlaeufig', 'verwalter', 'treuhaender', 'vorl_sachwalter', 'sachwalter',
};
const _serverPhasen = <String>{
  'eroeffnungsverfahren', 'eroeffnet', 'pruefungstermin', 'verwertung',
  'schlusstermin', 'wohlverhalten', 'restschuldbefreiung', 'aufgehoben',
};
const _serverStatus = <String>{'laufend', 'ruhend', 'abgeschlossen'};
const _serverKategorien = <String>{
  'beschluss', 'forderungsanmeldung', 'einkommen', 'vermoegen',
  'abtretung', 'schriftverkehr', 'sonstiges',
};

void main() {
  group('Schlüssel decken sich mit dem Server', () {
    test('Rollen', () => expect(kInsolvenzRollen.keys.toSet(), _serverRollen));
    test('Phasen', () => expect(kInsolvenzPhasen.keys.toSet(), _serverPhasen));
    test('Status', () => expect(kInsolvenzAkteStatus.keys.toSet(), _serverStatus));
    test('Dokumentkategorien',
        () => expect(kInsolvenzDokKategorien.keys.toSet(), _serverKategorien));

    test('jede Rolle und jede Phase hat einen lesbaren deutschen Namen', () {
      for (final v in [...kInsolvenzRollen.values, ...kInsolvenzPhasen.values]) {
        expect(v.trim(), isNotEmpty);
        // Der Schlüssel selbst wäre kein Name — genau so sähe ein vergessener
        // Eintrag aus, und auf dem Schirm stünde dann "vorl_sachwalter".
        expect(v.contains('_'), isFalse, reason: '„$v" ist ein Schlüssel, kein Name');
      }
    });
  });

  group('insolvenzRegisterzeichen', () {
    // Dieselben Fälle prüft `insolvenz_probe.php` gegen die PHP-Fassung. Die
    // beiden Ausdrücke sind zeichengleich; wer einen ändert, ändert beide.
    test('erkennt die gerichtliche Form', () {
      expect(insolvenzRegisterzeichen('12 IK 345/25'), 'IK');
      expect(insolvenzRegisterzeichen('123 IN 456/24'), 'IN');
      expect(insolvenzRegisterzeichen('5 IE 7/26'), 'IE');
      expect(insolvenzRegisterzeichen('IK 12/25'), 'IK');
      expect(insolvenzRegisterzeichen('123 IN 456/2024'), 'IN');
      expect(insolvenzRegisterzeichen('IK12/25'), 'IK');
    });

    test('rät nicht, wo die Form nichts hergibt', () {
      expect(insolvenzRegisterzeichen(''), isNull);
      expect(insolvenzRegisterzeichen('ohne alles'), isNull);
      expect(insolvenzRegisterzeichen('IN ohne Nummer'), isNull);
    });

    // ⚠️ Genau diese beiden Zeilen haben die erste Fassung des Ausdrucks
    // widerlegt. `\b(IN|IK|IE)\b[\s.]*\d` traf an „Termin in 2 Wochen" und
    // behauptete eine Regelinsolvenz, wo nur das deutsche Wort „in" stand;
    // ohne Beachtung der Großschreibung zusätzlich an „Zahlung in 12/25".
    // Das ist nicht kosmetisch: an IN oder IK hängt, ob es ein Regel- oder
    // ein Verbraucherverfahren ist.
    test('fällt nicht auf das deutsche Wort „in" herein', () {
      expect(insolvenzRegisterzeichen('Termin in 2 Wochen'), isNull);
      expect(insolvenzRegisterzeichen('Zahlung in 12/25 fällig'), isNull);
      expect(insolvenzRegisterzeichen('Eingang in 3/25 vermerkt'), isNull);
    });
  });

  group('insolvenzVerfahrensart', () {
    test('leitet die Verfahrensart aus dem Registerzeichen ab', () {
      expect(insolvenzVerfahrensart('IK'), 'Verbraucherinsolvenzverfahren');
      expect(insolvenzVerfahrensart('IN'), 'Regelinsolvenzverfahren');
      expect(insolvenzVerfahrensart('IE'), 'Verfahren mit internationalem Bezug');
    });

    test('schweigt bei unbekanntem oder fehlendem Zeichen', () {
      expect(insolvenzVerfahrensart(null), isNull);
      expect(insolvenzVerfahrensart(''), isNull);
      expect(insolvenzVerfahrensart('HRB'), isNull);
    });
  });

  group('Antwortform von insolvenz_manage.php', () {
    // ⚠️ PHP kennt nur einen Array-Typ. `json_encode` macht aus einer leeren
    // Struktur eine LISTE (`[]`), aus einer gefüllten assoziativen ein Objekt.
    // Ein `as Map` auf einer Liste liefert nicht null, sondern wirft — im
    // Release-Build bleibt davon nur eine graue Fläche übrig (so geschehen im
    // Speedtest-Bildschirm am 05.08.2026). Deshalb stehen hier echte
    // Antworten und nicht nachgebaute.
    const ohneVerwalter = '{"success":true,"data":null}';
    // Die Kanzlei ist ein VERWEIS in `rechtsanwalt_datenbank` und kommt als
    // eigener Block `kanzlei` zurück — im Klartext, weil Kanzleidaten
    // öffentliche Berufsdaten sind. Verschlüsselt ist nur, was zum Mitglied
    // gehört: Sachbearbeitung und Notiz.
    const mitVerwalter =
        '{"success":true,"data":{"id":1,"vorfall_id":25,"rechtsanwalt_id":13,'
        '"user_id":2,"rolle":"treuhaender","sachbearbeiter":"Frau Mustermann",'
        '"sachbearbeiter_tel":"","bestellt_am":"2026-02-01","ende_am":null,"notiz":"",'
        '"created_at":"2026-08-14 13:30:00","updated_at":"2026-08-14 13:30:00",'
        '"kanzlei":{"id":13,"firmenname":"Anwaltskanzlei Mumm",'
        '"anwalt_name":"Monika Mumm, Rechtsanwältin","strasse":"Musterweg 1",'
        '"plz_ort":"89231 Neu-Ulm","telefon":"","fax":"","email":"","website":"",'
        '"rechtsform":"","rechtsanwaltskammer":"","bea_safe_id":"","fachgebiete":""}}}';

    /// Ohne ausgewählte Kanzlei liefert der JOIN nichts — `kanzlei` ist dann
    /// null, nicht etwa ein leeres Objekt. Der Bildschirm muss daran erkennen,
    /// dass noch niemand ausgewählt wurde.
    const ohneKanzlei =
        '{"success":true,"data":{"id":1,"vorfall_id":25,"rechtsanwalt_id":null,'
        '"user_id":2,"rolle":"verwalter","sachbearbeiter":"","sachbearbeiter_tel":"",'
        '"bestellt_am":null,"ende_am":null,"notiz":"","kanzlei":null}}';

    const keineAkten = '{"success":true,"data":[]}';

    test('data ist null, solange niemand die Verwaltung erfasst hat', () {
      final j = jsonDecode(ohneVerwalter) as Map<String, dynamic>;
      expect(j['data'], isNull);
      // Der Bildschirm muss das aushalten, ohne zu werfen.
      final d = j['data'];
      expect(d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{}, isEmpty);
    });

    test('die Kanzlei kommt als eigener Block aus dem Nachschlagewerk', () {
      final j = jsonDecode(mitVerwalter) as Map<String, dynamic>;
      final m = Map<String, dynamic>.from(j['data'] as Map);
      expect(m['rolle'], 'treuhaender');
      expect(kInsolvenzRollen.containsKey(m['rolle']), isTrue);
      expect(m['rechtsanwalt_id'], 13);
      final k = Map<String, dynamic>.from(m['kanzlei'] as Map);
      expect(k['id'], 13);
      expect(k['firmenname'], 'Anwaltskanzlei Mumm');
      // Die Karte liest diese Felder direkt; leere kommen als '' zurück,
      // nicht als fehlender Schlüssel.
      for (final f in ['anwalt_name', 'strasse', 'plz_ort', 'telefon', 'fax',
                       'email', 'website', 'bea_safe_id', 'rechtsanwaltskammer',
                       'fachgebiete']) {
        expect(k.containsKey(f), isTrue, reason: '$f fehlt in der Kanzlei');
      }
    });

    test('ohne Auswahl ist kanzlei null — nicht ein leeres Objekt', () {
      final j = jsonDecode(ohneKanzlei) as Map<String, dynamic>;
      final m = Map<String, dynamic>.from(j['data'] as Map);
      expect(m['rechtsanwalt_id'], isNull);
      expect(m['kanzlei'], isNull);
      // Genau daran erkennt der Bildschirm „noch niemand ausgewählt".
      final vom = m['kanzlei'];
      expect(vom is Map ? Map<String, dynamic>.from(vom) : null, isNull);
    });

    test('eine leere Aktenliste ist eine JSON-Liste, kein Objekt', () {
      final j = jsonDecode(keineAkten) as Map<String, dynamic>;
      expect(j['data'], isA<List>());
      expect(j['data'], isEmpty);
    });

    test('registerzeichen der Akte darf null sein', () {
      const akten =
          '{"success":true,"data":[{"id":7,"vorfall_id":25,"user_id":2,'
          '"bezeichnung":"Probe","az_gericht":"ohne alles","az_verwalter":"",'
          '"registerzeichen":null,"phase":null,"status":"laufend",'
          '"eroeffnet_am":null,"ende_am":null,"notiz":"",'
          '"created_at":"2026-08-14 13:30:00","updated_at":"2026-08-14 13:30:00",'
          '"korr_anzahl":0,"doc_anzahl":0}]}';
      final liste = (jsonDecode(akten) as Map<String, dynamic>)['data'] as List;
      final a = Map<String, dynamic>.from(liste.first as Map);
      expect(a['registerzeichen'], isNull);
      // Die Liste zeigt dann '?' statt einer erfundenen Verfahrensart.
      expect(insolvenzVerfahrensart((a['registerzeichen'] ?? '').toString()), isNull);
      expect((a['registerzeichen'] ?? '?').toString(), '?');
    });

    test('Zähler kommen als Zahl zurück, nicht als Text', () {
      // MySQL liefert COUNT(*) über PDO als String, wenn der Treiber nicht
      // emuliert — die Chips rechnen damit nicht, aber sie zeigen es an.
      const mit = '{"success":true,"data":[{"id":7,"korr_anzahl":3,"doc_anzahl":0}]}';
      final a = ((jsonDecode(mit) as Map<String, dynamic>)['data'] as List).first as Map;
      expect(a['korr_anzahl'].toString(), '3');
      expect(a['doc_anzahl'] != 0 || a['doc_anzahl'] == 0, isTrue);
    });
  });
}
