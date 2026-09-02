import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/mitschrift_sprachen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Die Sprachwahl der Live-Mitschrift.
///
/// 🔴 WARUM DAS GEPRÜFT WIRD
/// Auf dem Server gemessen: rumänische Rede durch das deutsche Modell ergibt
/// 99,3 % Wortfehler — aber als flüssige deutsche Wörter („wohne seo ab was so
/// nen libretto der programmierer"). Wer den Text liest, um das Gespräch zu
/// verstehen, sieht daran keinen Fehler. Eine falsche Sprachwahl ist deshalb
/// nicht ein bisschen schlechter als die richtige, sondern schlechter als gar
/// keine Mitschrift.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('welche Sprachen es gibt', () {
    test('genau die fünf mit Modell', () {
      // ⚠️ Gekoppelt an `ASR_MODELLE` und `ASR_PARAKEET_SPRACHEN` auf dem
      // Server. Weicht die Liste ab, weist der Server ab (Code 1003) — das
      // fällt auf, kostet aber ein Gespräch.
      expect(kMitschriftSprachen, {'de', 'en', 'ro', 'ru', 'uk'});
    });

    test('erkennt auch Schreibweisen mit Land', () {
      for (final r in ['de', 'DE', 'de-DE', 'de_DE', ' De ']) {
        expect(mitschriftSprache(r), 'de', reason: r);
      }
      expect(mitschriftSprache('ro-RO'), 'ro');
      expect(mitschriftSprache('en-GB'), 'en');
    });

    test('ohne Modell heisst null, nicht Deutsch', () {
      // ⚠️ Der Kern der Sache. Türkisch hat ein Mitglied im Bestand — es
      // still auf Deutsch zu erkennen wäre genau der Fehler, der wie ein
      // Ergebnis aussieht. (ru und uk sind seit dem 02.09.2026 abgedeckt.)
      for (final r in ['tr', 'ar', 'pl', 'it', '', '  ', 'xx', 'deutsch']) {
        expect(mitschriftSprache(r), isNull, reason: r);
      }
      expect(mitschriftSprache(null), isNull);
    });
  });

  group('welche Sprache ein Gespräch bekommt', () {
    test('die eigene Wahl schlägt den Vorschlag', () {
      // Ein Mitglied mit rumänischer Oberfläche, das am Telefon Deutsch
      // spricht: einmal umgeschaltet, und es bleibt dabei.
      expect(
        mitschriftSpracheWaehlen(gemerkt: 'de', vorschlag: 'ro'),
        'de',
      );
    });

    test('ohne eigene Wahl gilt der Vorschlag', () {
      expect(mitschriftSpracheWaehlen(vorschlag: 'ro'), 'ro');
    });

    test('ein Vorschlag ohne Modell fällt auf Deutsch, nicht auf sich selbst',
        () {
      expect(mitschriftSpracheWaehlen(vorschlag: 'tr'), 'de');
    });

    test('Russisch und Ukrainisch werden jetzt vorgeschlagen', () {
      // Neun Mitglieder im Bestand; vor dem 02.09.2026 fielen sie auf Deutsch.
      expect(mitschriftSpracheWaehlen(vorschlag: 'ru'), 'ru');
      expect(mitschriftSpracheWaehlen(vorschlag: 'uk'), 'uk');
    });

    test('eine gemerkte Sprache ohne Modell wird übergangen', () {
      // Kann entstehen, wenn eine Sprache später vom Server verschwindet.
      expect(mitschriftSpracheWaehlen(gemerkt: 'tr', vorschlag: 'ro'), 'ro');
    });

    test('ohne alles Deutsch', () {
      expect(mitschriftSpracheWaehlen(), kMitschriftStandard);
      expect(kMitschriftStandard, 'de');
    });
  });

  group('was sich die App merkt', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('dieselbe Nummer in drei Schreibweisen ist ein Anschluss', () {
      final a = MitschriftSprachwahl.schluessel('+49 731 80159736');
      expect(MitschriftSprachwahl.schluessel('073180159736'), a);
      expect(MitschriftSprachwahl.schluessel('004973180159736'), a);
      expect(MitschriftSprachwahl.schluessel('+49-731-801 597 36'), a);
    });

    test('verschiedene Nummern sind verschieden', () {
      expect(MitschriftSprachwahl.schluessel('+4973180159736'),
          isNot(MitschriftSprachwahl.schluessel('+4973180159737')));
    });

    test('die Nummer steht nirgends im Klartext', () async {
      // 🔴 In den Einstellungen läge sonst mit der Zeit eine offene Liste
      // aller Anschlüsse, mit denen der Verein telefoniert hat —
      // unverschlüsselt, und für eine Einstellung, die den Klartext gar nicht
      // braucht.
      const nummer = '+4973180159736';
      await MitschriftSprachwahl.merken(nummer, 'ro');
      final p = await SharedPreferences.getInstance();
      for (final k in p.getKeys()) {
        expect(k.contains('80159736'), isFalse, reason: k);
        expect(k.contains('4973180159736'), isFalse, reason: k);
        expect('${p.get(k)}'.contains('80159736'), isFalse);
      }
    });

    test('gemerkt wird nur, was ein Modell hat', () async {
      const nummer = '+4973180159736';
      await MitschriftSprachwahl.merken(nummer, 'tr');
      expect(await MitschriftSprachwahl.gemerkt(nummer), isNull);
      await MitschriftSprachwahl.merken(nummer, 'ro');
      expect(await MitschriftSprachwahl.gemerkt(nummer), 'ro');
    });

    test('eine leere Nummer merkt gar nichts', () async {
      await MitschriftSprachwahl.merken('', 'ro');
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      expect(await MitschriftSprachwahl.gemerkt(''), isNull);
    });
  });

  group('der Rückfall aufs Gerät', () {
    // Im Gerät liegt EIN Modell (`vosk-model-small-de-0.15`). Es für Englisch
    // oder Rumänisch zu benutzen wäre derselbe Fehler wie oben — deshalb steht
    // die Bedingung im Quelltext, und deshalb wird hier der Quelltext gelesen.
    // Sie sitzt in einem Zweig, den nur ein abreissender Server auslöst.
    final quelle =
        File('lib/services/untertitel_service.dart').readAsStringSync();

    test('nur Deutsch darf im Gerät gerechnet werden', () {
      expect(quelle.contains("if (spr != 'de') {"), isTrue,
          reason: 'Der Rückfall aufs Gerät ist nicht mehr auf Deutsch begrenzt');
    });

    test('auch der Abbruch mitten im Gespräch schaltet nur bei Deutsch um', () {
      final i = quelle.indexOf('aufDemServer.value = false;');
      expect(i, greaterThan(0));
      final block = quelle.substring(i, i + 400);
      expect(block.contains("_letzteSprache == 'de'"), isTrue,
          reason: 'Nach einem Abriss würde auch fremde Sprache im Gerät laufen');
    });
  });
}
