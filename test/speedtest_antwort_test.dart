import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/speedtest_screen.dart';

/// Echte Serverantwort vom 05.08.2026, unveraendert uebernommen.
///
/// ⚠️ Der Sinn dieses Tests ist NICHT, die Zahlen zu pruefen, sondern die
/// FORM. PHP kennt nur einen Array-Typ: eine Struktur mit lueckenlosen
/// Zahlenschluesseln kodiert `json_encode` als Liste, dieselbe Struktur mit
/// einer Luecke als Objekt, und eine leere als Liste. Ein `as Map?` auf einer
/// Liste liefert nicht null, sondern wirft — genau daran blieb der
/// Speedtest-Bildschirm am 05.08.2026 in der Produktion beim Aufbau haengen
/// und zeigte nur eine graue Flaeche.
const String _echteAntwort = r'''{"n": 39, "fehler": 0, "fehlerquote": 0, "down_avg": 117.53, "down_min": 8.01, "down_max": 156.48, "down_p05": 15, "down_p50": 100, "up_avg": 10.69, "up_p05": 0, "up_p50": 5, "ping_avg": 71.5, "lastlatenz_avg": null, "lastlatenz_max": null, "generationen": {"5G-NSA": 39}, "nicht_bewertbar": {"wlan": 0, "nur_latenz": 0, "fenster_kurz": 5, "netz_unbekannt": 0}, "rollups_ohne_trennung": 0, "abdeckung": {"erwartet": 48, "vorhanden": 44, "anteil": 0.9167, "je_stunde": {"0": 2, "1": 2, "2": 2, "3": 2, "4": 2, "5": 2, "6": 2, "7": 2, "8": 2, "9": 2, "10": 2, "11": 2, "12": 2, "13": 2, "14": 0, "15": 0, "16": 2, "17": 2, "18": 2, "19": 2, "20": 2, "21": 2, "22": 2, "23": 2}, "geraete": 1}, "profil": {"stunde_down": {"0": 123.9, "1": 106.1, "2": 151.3, "3": 136.2, "4": 145.7, "5": 149.5, "6": 148.3, "7": 146.6, "8": 128, "9": 140, "10": 26.2, "11": 101.7, "12": 143.1, "13": null, "14": null, "15": null, "16": 13.1, "17": 115.8, "18": 116, "19": 78.3, "20": 108.5, "21": 103.8, "22": 116, "23": 156.5}, "stunde_n": {"0": 2, "1": 2, "2": 2, "3": 2, "4": 2, "5": 2, "6": 2, "7": 2, "8": 2, "9": 2, "10": 1, "11": 2, "12": 1, "13": 0, "14": 0, "15": 0, "16": 2, "17": 2, "18": 2, "19": 2, "20": 2, "21": 2, "22": 2, "23": 1}, "wochentag_down": {"0": null, "1": 97.3, "2": 130.2, "3": null, "4": null, "5": null, "6": null}, "wochentag_n": {"0": 0, "1": 15, "2": 24, "3": 0, "4": 0, "5": 0, "6": 0}, "funk": {"gut": {"n": 6, "down": 98.8}, "mittel": {"n": 28, "down": 129.6}, "schwach": {"n": 5, "down": 72.4}}}, "schwelle": 45, "unter_schwelle": {"anteil": 0.0769, "unter": 3, "gesamt": 39}, "tagesbestwerte": {"je_geraet": [{"geraet_key": "05172c6c0742d0fb6478545a3be84317ba110596ca70071327dbe6402e798721", "tage_gesamt": 2, "tage_unter": 0, "anteil_tage": 0, "schlechteste": [], "vfg_fenster": [], "vfg_anzahl": 0, "vfg_erfuellt": false, "vfg_erstes": null}], "mehrere_geraete": false, "tage_gesamt": 2, "tage_unter": 0, "anteil_tage": 0, "schlechteste": [], "betrifft_geraet": "05172c6c0742d0fb6478545a3be84317ba110596ca70071327dbe6402e798721", "vfg_erfuellt": false, "vfg_anzahl": 0, "vfg_erstes": null, "vfg_fenster": [], "grundlage": "nur Mobilfunk, ohne Nur-Latenz- und Kurzfenster-Laeufe"}}''';

void main() {
  group('Serverantwort vertraegt beide JSON-Formen', () {
    test('die echte Antwort laesst sich vollstaendig lesen', () {
      final s = jsonDecode(_echteAntwort) as Map<String, dynamic>;
      final werte = speedtestNachIndex((s['profil'] as Map)['stunde_down']);
      expect(werte, isNotEmpty);
      // 13 bis 15 Uhr lagen keine Messungen vor — die Luecke muss erhalten
      // bleiben, nicht als 0 erscheinen.
      expect(werte.containsKey(13), isFalse);
      expect(werte[0], closeTo(123.9, 0.01));
    });

    test('eine LISTE wird genauso gelesen wie ein Objekt', () {
      // Genau der Fall, der den Bildschirm grau werden liess.
      final ausListe = speedtestNachIndex([10.0, null, 30.0]);
      final ausObjekt = speedtestNachIndex({'0': 10.0, '2': 30.0});
      expect(ausListe, ausObjekt);
      expect(ausListe[0], 10.0);
      expect(ausListe.containsKey(1), isFalse);
    });

    test('leer, null und Unsinn ergeben eine leere Reihe statt eines Absturzes', () {
      expect(speedtestNachIndex(const []), isEmpty);
      expect(speedtestNachIndex(const <String, dynamic>{}), isEmpty);
      expect(speedtestNachIndex(null), isEmpty);
      expect(speedtestNachIndex('kaputt'), isEmpty);
    });

    test('alsMap liefert null statt zu werfen, wenn eine Liste ankommt', () {
      // Ein leeres PHP-Array kodiert als `[]`. Ohne bewertbare Laeufe trifft
      // das `generationen`, `abdeckung` und `nicht_bewertbar` gleichermassen.
      expect(speedtestAlsMap(const []), isNull);
      expect(speedtestAlsMap(const {'a': 1}), {'a': 1});
      expect(speedtestAlsMap(null), isNull);
      expect(speedtestAlsMap(42), isNull);
    });
  });
}
