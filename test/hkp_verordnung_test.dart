import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/hkp_verordnung_tab.dart';

/// Verordnung häuslicher Krankenpflege (Muster 12, § 37 SGB V).
///
/// ⚠️ Der Sinn dieser Datei ist NICHT, Zahlen zu prüfen, sondern zwei Dinge,
/// die sonst still versagen:
///
///  1. **Die Form der Serverantwort.** PHP kennt nur einen Array-Typ:
///     `['a'=>1]` wird zum Objekt, `[]` zur Liste. Ein `as Map` auf einer
///     Liste liefert nicht null, sondern wirft — genau daran hing der
///     Speedtest-Bildschirm am 05.08.2026 in der Produktion als graue Fläche.
///     Weder `flutter analyze` noch ein Widget-Test fasst die echte Antwort an.
///
///  2. **Die Kopplung der Schlüssel an den Server.** Das PHP liegt in keinem
///     Repo. Schickt der Client eine Versorgungsart, die
///     `hkp_verordnung_manage.php` nicht kennt, ersetzt der Server sie
///     stillschweigend durch den Vorgabewert — kein Fehler, kein Hinweis,
///     nur eine falsche Verordnung. Diese Liste ist die einzige Stelle, an
///     der so etwas überhaupt auffallen kann.

/// Echte Antwortform von `action: list` mit einer Verordnung.
const String _listeEine = r'''
{"success":true,"verordnungen":[{"id":7,"arzt_type":"gesundheit_hausarzt","verordnungsart":"erstverordnung","versorgungsart":"sicherungspflege","ausstellungsdatum":"2026-08-17","zeitraum_von":"2026-08-17","zeitraum_bis":"2026-08-30","unfall":false,"ser_bvg":false,"haeufigkeit_pflegefachkraft":true,"status":"eingereicht","eingereicht_am":"2026-08-18","genehmigt_am":"","genehmigt_bis":"","zuzahlung_betrag":10.0,"zuzahlung_befreit":false,"pflegedienst_id":1,"pflegedienst":{"id":1,"name":"Diakoniestation Ulm","strasse":"Musterweg 3","plz_ort":"89073 Ulm","telefon":"0731 12345","fax":"","email":"","website":"","notizen":""},"arzt_name":"Dr. Muster","diagnose_icd10":"I50.9","diagnose_text":"Herzinsuffizienz, nicht näher bezeichnet","leistungen":[{"bereich":"behandlungspflege","bezeichnung":"Medikamentengabe","ziffer":"26","haeufigkeit":"3x täglich","dauer_von":"2026-08-17","dauer_bis":"2026-08-30","durch_pflegefachkraft":false}],"ablehnung_grund":"","notizen":"","created_at":"2026-08-17 12:00:00","updated_at":"2026-08-17 12:00:00"}]}
''';

/// Kein einziger Datensatz. ⚠️ PHP macht daraus `[]`, nicht `{}` — und
/// `leistungen` ist beim leeren Feld ebenfalls Liste, nicht Objekt.
const String _listeLeer = r'''
{"success":true,"verordnungen":[]}
''';

/// Verordnung ohne zugeordneten Pflegedienst: `pflegedienst` ist dann `null`,
/// nicht ein leeres Objekt. Wer blind `as Map` schreibt, stürzt hier ab.
const String _ohnePflegedienst = r'''
{"success":true,"verordnungen":[{"id":8,"arzt_type":"gesundheit_hausarzt","verordnungsart":"folgeverordnung","versorgungsart":"krankenhausvermeidung","ausstellungsdatum":"2026-08-17","zeitraum_von":"2026-08-17","zeitraum_bis":"2026-09-14","unfall":false,"ser_bvg":false,"haeufigkeit_pflegefachkraft":false,"status":"offen","eingereicht_am":"","genehmigt_am":"","genehmigt_bis":"","zuzahlung_betrag":null,"zuzahlung_befreit":true,"pflegedienst_id":null,"pflegedienst":null,"arzt_name":"","diagnose_icd10":"","diagnose_text":"","leistungen":[],"ablehnung_grund":"","notizen":"","created_at":"2026-08-17 12:00:00","updated_at":"2026-08-17 12:00:00"}]}
''';

const String _korrLeer = r'''
{"success":true,"korrespondenz":[]}
''';

const String _korrEine = r'''
{"success":true,"korrespondenz":[{"id":3,"verordnung_id":7,"richtung":"ausgang","kontaktart":"post","datum":"18.08.2026","betreff":"Verordnung eingereicht","inhalt":"Ausfertigung 12a per Post an die Kasse."}]}
''';

/// Genau das, was der Client beim Speichern einer fremden id bekommt.
const String _nichtGefunden = r'''
{"success":false,"message":"Verordnung not found"}
''';

List<Map<String, dynamic>> _verordnungen(String roh) {
  final j = jsonDecode(roh) as Map<String, dynamic>;
  return (j['verordnungen'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
}

void main() {
  group('Antwortform von hkp_verordnung_manage.php', () {
    test('Liste mit einer Verordnung wird vollständig gelesen', () {
      final v = _verordnungen(_listeEine).single;
      expect(v['id'], 7);
      expect(v['verordnungsart'], 'erstverordnung');
      expect(v['versorgungsart'], 'sicherungspflege');
      expect(v['diagnose_icd10'], 'I50.9');
      // Umlaute überleben den Weg durch GCM und JSON.
      expect(v['diagnose_text'], contains('näher'));
      expect(v['haeufigkeit_pflegefachkraft'], isTrue);
      final l = (v['leistungen'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      expect(l, hasLength(1));
      expect(l.single['ziffer'], '26');
      expect(l.single['durch_pflegefachkraft'], isFalse);
    });

    test('leere Liste ist [] und wirft nicht', () {
      expect(_verordnungen(_listeLeer), isEmpty);
    });

    test('ohne Pflegedienst ist das Feld null, nicht ein leeres Objekt', () {
      final v = _verordnungen(_ohnePflegedienst).single;
      expect(v['pflegedienst'], isNull);
      expect(v['pflegedienst_id'], isNull);
      // Der Zugriff, den der Tab macht, darf hier nicht werfen.
      final pd = v['pflegedienst'] is Map ? Map<String, dynamic>.from(v['pflegedienst'] as Map) : null;
      expect(pd, isNull);
      expect((v['leistungen'] as List), isEmpty);
      expect(v['zuzahlung_betrag'], isNull);
    });

    test('Pflegedienst-Objekt trägt die Felder der Detailansicht', () {
      final pd = Map<String, dynamic>.from(_verordnungen(_listeEine).single['pflegedienst'] as Map);
      for (final k in ['id', 'name', 'strasse', 'plz_ort', 'telefon', 'fax', 'email', 'website', 'notizen']) {
        expect(pd.containsKey(k), isTrue, reason: 'Feld $k fehlt in der Pflegedienst-Antwort');
      }
    });

    test('Korrespondenz: leer ist [], ein Eintrag wird gelesen', () {
      expect((jsonDecode(_korrLeer) as Map)['korrespondenz'], isEmpty);
      final k = Map<String, dynamic>.from(
          ((jsonDecode(_korrEine) as Map)['korrespondenz'] as List).single as Map);
      expect(k['richtung'], 'ausgang');
      expect(k['kontaktart'], 'post');
      expect(k['betreff'], 'Verordnung eingereicht');
    });

    test('Fehlerantwort trägt eine lesbare Begründung', () {
      final j = jsonDecode(_nichtGefunden) as Map<String, dynamic>;
      expect(j['success'], isFalse);
      // Ohne message stünde im Dialog „unbekannter Fehler" — der Server
      // liefert einen Grund, und der Client zeigt ihn.
      expect(j['message'], isNotEmpty);
    });
  });

  group('Schlüssel sind an den Server gekoppelt', () {
    // ⚠️ Spiegel der Whitelists in hkp_verordnung_manage.php
    // (VERORDNUNGSARTEN, VERSORGUNGSARTEN, STATI). Das PHP liegt in keinem
    // Repo — wird dort etwas geändert, muss es HIER mitgeändert werden,
    // sonst ersetzt der Server den Wert stumm durch den Vorgabewert.
    const serverVerordnungsarten = {'erstverordnung', 'folgeverordnung'};
    const serverVersorgungsarten = {
      'krankenhausvermeidung',
      'krankenhausverkuerzung',
      'sicherungspflege',
      'unterstuetzungspflege',
    };
    const serverStati = {'offen', 'eingereicht', 'genehmigt', 'teilgenehmigt', 'abgelehnt', 'abgelaufen'};

    test('Verordnungsarten stimmen mit der Server-Whitelist überein', () {
      expect(kHkpVerordnungsarten.map((e) => e.$1).toSet(), serverVerordnungsarten);
    });

    test('Versorgungsarten stimmen mit der Server-Whitelist überein', () {
      expect(kHkpVersorgungsarten.map((e) => e.$1).toSet(), serverVersorgungsarten);
    });

    test('Status-Werte stimmen mit der Server-Whitelist überein', () {
      expect(kHkpStatus.map((e) => e.$1).toSet(), serverStati);
    });

    test('jeder Leistungsbereich hat einen Katalog', () {
      for (final b in kHkpLeistungsbereiche) {
        expect(kHkpLeistungskatalog[b.$1], isNotNull, reason: 'Bereich ${b.$1} ohne Katalog');
        expect(kHkpLeistungskatalog[b.$1], isNotEmpty);
      }
      // Und umgekehrt: kein Katalog ohne Bereich, sonst wäre er unerreichbar.
      final bereiche = kHkpLeistungsbereiche.map((e) => e.$1).toSet();
      expect(kHkpLeistungskatalog.keys.toSet(), bereiche);
    });
  });

  group('Datumsdarstellung', () {
    test('ISO wird deutsch dargestellt', () {
      expect(hkpDatumLesbar('2026-08-17'), '17.08.2026');
      expect(hkpDatumLesbar('2026-08-17 12:00:00'), '17.08.2026');
      expect(hkpDatumLesbar('2026-01-05'), '05.01.2026');
    });

    test('leeres Datum bleibt leer und wird nicht zu 01.01.1970', () {
      expect(hkpDatumLesbar(''), '');
      expect(hkpDatumLesbar('   '), '');
      // Unlesbares kommt unverändert zurück, statt eine Zahl zu erfinden.
      expect(hkpDatumLesbar('unklar'), 'unklar');
    });
  });

  group('Betragsdarstellung', () {
    test('JSON-Zahl wird deutsch mit zwei Nachkommastellen dargestellt', () {
      // ⚠️ Der Server liefert 10.5, das Eingabefeld ist ein deutsches.
      // Unverändert stünde dort „10.5", obwohl „10,50" getippt wurde.
      expect(hkpBetragLesbar(10.5), '10,50');
      expect(hkpBetragLesbar(10), '10,00');
      expect(hkpBetragLesbar(0), '0,00');
      expect(hkpBetragLesbar('7,25'), '7,25');
    });

    test('kein Betrag bleibt leer und wird nicht zu 0,00', () {
      // 0,00 hieße „nichts zu zahlen" — nicht dasselbe wie „noch nicht erfasst".
      expect(hkpBetragLesbar(null), '');
    });

    test('Unlesbares kommt unverändert zurück statt als erfundene Zahl', () {
      expect(hkpBetragLesbar('keine Angabe'), 'keine Angabe');
    });
  });

  group('Restlaufzeit', () {
    String iso(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    test('heute sind 0 Tage — nicht null und nicht 1', () {
      expect(hkpTageBis(iso(DateTime.now())), 0);
    });

    test('Zukunft ist positiv, Vergangenheit negativ', () {
      expect(hkpTageBis(iso(DateTime.now().add(const Duration(days: 5)))), 5);
      expect(hkpTageBis(iso(DateTime.now().subtract(const Duration(days: 3)))), -3);
    });

    test('kein Datum ergibt null, nicht 0', () {
      // 0 hieße „läuft heute ab" — das wäre eine Falschmeldung.
      expect(hkpTageBis(''), isNull);
      expect(hkpTageBis('kein Datum'), isNull);
    });

    test('Uhrzeit im Wert stört die Tagesrechnung nicht', () {
      final morgen = DateTime.now().add(const Duration(days: 1));
      expect(hkpTageBis('${iso(morgen)} 23:59:59'), 1);
    });
  });
}
