import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sms_service.dart';

/// Die Termin-SMS kostet Geld und geht an echte Mitglieder — beides macht die
/// beiden Prüfungen hier wichtig:
///
///  * [SmsService.check] darf nur auf Mobilnummern senden. Eine SMS an eine
///    Festnetznummer verschwindet spurlos (Telekom/Vodafone haben den Dienst
///    2023 abgeschaltet), das Mitglied bekäme nie eine Erinnerung und niemand
///    würde es merken.
///  * [SmsService.buildTerminSms] muss im Kostenrahmen bleiben. Lateinische
///    Sprachen werden dafür nach GSM-7 transliteriert (160 Zeichen je
///    Segment); Kyrillisch und Arabisch gehen zwangsläufig als UCS-2 raus und
///    fassen nur 70 — dort zählt jede eingesparte Zeile doppelt.
void main() {
  group('check — Rufnummern aus Verifizierung Stufe 1', () {
    test('nationale Mobilnummern werden zu E.164', () {
      expect(SmsService.check('0176 12345678').e164, '+4917612345678');
      expect(SmsService.check('0151-23456789').e164, '+4915123456789');
      expect(SmsService.check('0162 / 345 6789').e164, '+491623456789');
    });

    test('internationale Schreibweisen landen auf derselben Nummer', () {
      const erwartet = '+4917612345678';
      expect(SmsService.check('+49 176 12345678').e164, erwartet);
      expect(SmsService.check('0049 176 12345678').e164, erwartet);
      expect(SmsService.check('+49 (0)176 12345678').e164, erwartet);
    });

    test('Festnetz wird abgelehnt — SMS ins Festnetz gibt es nicht mehr', () {
      final fest = SmsService.check('0711 123456');
      expect(fest.canSend, isFalse);
      expect(fest.issue, SmsNumberIssue.landline);

      expect(SmsService.check('+49 30 12345678').issue, SmsNumberIssue.landline);
      // 0180 ist Servicerufnummer, kein Mobilfunk.
      expect(SmsService.check('01806 999555').issue, SmsNumberIssue.landline);
    });

    test('leeres Feld meldet "fehlt", Buchstabensalat meldet "unlesbar"', () {
      expect(SmsService.check(null).issue, SmsNumberIssue.missing);
      expect(SmsService.check('   ').issue, SmsNumberIssue.missing);
      expect(SmsService.check('kein Telefon').issue, SmsNumberIssue.invalid);
    });

    test('zu kurze Nummern gelten nicht als Mobilnummer', () {
      expect(SmsService.check('0176 123').canSend, isFalse);
    });

    test('Auslandsnummern gehen raus, aber als ungeprüft markiert', () {
      final ro = SmsService.check('+40 721 234 567');
      expect(ro.canSend, isTrue);
      expect(ro.unverifiedForeign, isTrue);
      expect(ro.label, contains('Ausland'));
    });
  });

  group('toGsm7 — alles, was UCS-2 erzwingen würde, fliegt raus', () {
    test('Umlaute und ß bleiben (sind in GSM-7 enthalten)', () {
      expect(SmsService.toGsm7('Grüße aus Öhringen'), 'Grüße aus Öhringen');
    });

    test('Emoji und typografische Zeichen werden ersetzt', () {
      expect(SmsService.toGsm7('Termin 📅 morgen'), 'Termin morgen');
      expect(SmsService.toGsm7('„Beratung" – 10 Uhr'), '"Beratung" - 10 Uhr');
      expect(SmsService.toGsm7('Kosten 5 €'), 'Kosten 5 EUR');
    });

    test('rumänische Diakritika werden transliteriert statt verworfen', () {
      expect(SmsService.toGsm7('Ședință'), 'Sedinta');
    });
  });

  group('segments — Kostenrechnung', () {
    test('bis 160 Zeichen ist eine SMS', () {
      expect(SmsService.segments('a' * 160), 1);
      expect(SmsService.segments('a' * 161), 2);
    });

    test('Erweiterungszeichen zählen doppelt', () {
      // 80 mal '[' = 160 Einheiten = noch genau eine SMS.
      expect(SmsService.segments('[' * 80), 1);
      expect(SmsService.segments('[' * 81), 2);
    });
  });

  group('buildTerminSms', () {
    final termin = DateTime(2026, 7, 28, 10, 30);

    test('enthält Datum, Uhrzeit mit Ende, Ort, Betreff und Notiz', () {
      final text = SmsService.buildTerminSms(
        terminDate: termin,
        title: 'Beratung Jobcenter',
        location: 'Rathaus Stuttgart',
        description: 'Leistungsbescheid mitbringen',
        durationMinutes: 60,
      );

      expect(text, contains('Di 28.07.2026'));
      expect(text, contains('10:30-11:30'));
      expect(text, contains('60 Min.'));
      expect(text, contains('Rathaus Stuttgart'));
      expect(text, contains('Beratung Jobcenter'));
      expect(text, contains('Leistungsbescheid mitbringen'));
    });

    test('überlange Angaben werden gekürzt statt endlos zu wachsen', () {
      final text = SmsService.buildTerminSms(
        terminDate: termin,
        title: 'Sehr langer Betreff ' * 10,
        location: 'Ein ausgesprochen langer Ortsname mit Zusatzangaben ' * 5,
        description: 'Eine sehr ausführliche Notiz mit vielen Hinweisen ' * 10,
      );

      expect(SmsService.segments(text), lessThanOrEqualTo(6));
      // Datum und Uhrzeit überleben jede Kürzung.
      expect(text, contains('28.07.2026'));
      expect(text, contains('10:30'));
    });

    test('kein Emoji, egal was in Titel oder Ort steht', () {
      final text = SmsService.buildTerminSms(
        terminDate: termin,
        title: '📋 Beratung',
        location: '📍 Rathaus',
      );

      expect(text, isNot(contains('📋')));
      expect(text, isNot(contains('📍')));
      expect(SmsService.isGsm7(text), isTrue);
    });

    test('fehlender Ort lässt die Zeile weg statt "null" zu schreiben', () {
      final text = SmsService.buildTerminSms(
        terminDate: termin,
        title: 'Beratung',
        location: '',
      );

      expect(text, isNot(contains('Ort:')));
      expect(text, contains('Beratung'));
    });
  });

  group('Sprache des Mitglieds', () {
    final termin = DateTime(2026, 7, 28, 10, 30);
    String bau(String? sprache) => SmsService.buildTerminSms(
          terminDate: termin,
          title: 'Beratung Jobcenter',
          location: 'Rathaus Stuttgart',
          description: 'Bescheid mitbringen',
          durationMinutes: 60,
          language: sprache,
        );

    test('jede der sieben genutzten Sprachen hat eine Vorlage', () {
      // Genau die Sprachen, die in users.preferred_language vorkommen.
      for (final s in ['de', 'en', 'ro', 'ru', 'uk', 'tr', 'ar']) {
        expect(SmsService.hasLanguage(s), isTrue, reason: 'Vorlage für $s fehlt');
      }
    });

    test('übersetzt die festen Teile, lässt Ort und Betreff unangetastet', () {
      // Feldnamen und Schlusssatz in der Profilsprache, Ort und Betreff so,
      // wie sie im Termin stehen.
      expect(bau('ro'), contains('Data:'));
      expect(bau('ro'), contains('Va rugam sa confirmati'));
      expect(bau('ro'), contains('Rathaus Stuttgart'));
      expect(bau('ru'), contains('Дата:'));
      expect(bau('tr'), contains('Tarih:'));
      expect(bau('ar'), contains('التاريخ:'));
    });

    test('unbekannte oder fehlende Sprache fällt auf Deutsch zurück', () {
      expect(bau(null), contains('Mit freundlichen Grüßen'));
      expect(bau('kl'), contains('Mit freundlichen Grüßen'));
      expect(SmsService.hasLanguage('kl'), isFalse);
    });

    test('Regionalvarianten werden erkannt (de-DE, RO, ru_RU)', () {
      expect(bau('de-DE'), contains('Datum:'));
      expect(bau('RO'), contains('Cu stima'));
      expect(bau('ru_RU'), contains('С уважением'));
    });

    test('lateinische Sprachen bleiben in GSM-7, kyrillisch/arabisch nicht', () {
      // Rumänisch und Türkisch werden transliteriert — sonst wären es
      // UCS-2-Nachrichten mit 70 statt 160 Zeichen je Segment.
      expect(SmsService.isGsm7(bau('ro')), isTrue);
      expect(SmsService.isGsm7(bau('tr')), isTrue);
      expect(SmsService.isGsm7(bau('ru')), isFalse);
      expect(SmsService.isGsm7(bau('ar')), isFalse);
    });

    test('auch in UCS-2-Sprachen bleibt die Nachricht im Kostenrahmen', () {
      for (final s in ['ru', 'uk', 'ar']) {
        expect(SmsService.segments(bau(s)), lessThanOrEqualTo(6), reason: s);
      }
    });

    test('die Notiz kommt in JEDER Sprache mit — auch in UCS-2', () {
      // Der Grund für den Termin ist der wichtigste Teil der Erinnerung. Bei
      // vier Segmenten fiel er in ru/uk/ar noch weg, weil dort nur 67 Zeichen
      // je Segment passen.
      for (final s in ['de', 'en', 'ro', 'tr', 'ru', 'uk', 'ar']) {
        expect(bau(s), contains('Bescheid mitbringen'), reason: s);
      }
    });

    test('Wochentag und Zeitangabe stehen in der jeweiligen Sprache', () {
      expect(bau('ro'), contains('Ma 28.07.2026'));   // marți
      expect(bau('en'), contains('Tue 28.07.2026'));
      expect(bau('ru'), contains('Вт 28.07.2026'));
      expect(bau('tr'), contains('60 dk'));
    });
  });

  group('Anrede aus Verifizierung Stufe 1', () {
    final termin = DateTime(2026, 7, 28, 10, 30);
    String bau({String? geschlecht, String sprache = 'de',
            String vorname = 'Anna', String nachname = 'Weber'}) =>
        SmsService.buildTerminSms(
          terminDate: termin,
          title: 'Beratung',
          location: 'Rathaus',
          language: sprache,
          vorname: vorname,
          nachname: nachname,
          geschlecht: geschlecht,
        );

    test('alle fünf Schreibweisen aus der Datenbank werden erkannt', () {
      // Gewachsener Bestand: `weiblich` (13), `maennlich` (12), `W` (3),
      // `M` (4) und NULL (18). Eine Prüfung auf `== 'W'` traf nur 7 von 50.
      for (final w in ['W', 'w', 'weiblich', 'Weiblich', 'frau']) {
        expect(bau(geschlecht: w), startsWith('Sehr geehrte Frau Weber'), reason: w);
      }
      for (final m in ['M', 'm', 'maennlich', 'männlich', 'herr']) {
        expect(bau(geschlecht: m), startsWith('Sehr geehrter Herr Weber'), reason: m);
      }
    });

    test('ohne Geschlecht wird ohne Frau/Herr angeredet, nicht geraten', () {
      for (final leer in [null, '', '   ', 'divers', 'd']) {
        final text = bau(geschlecht: leer);
        expect(text, startsWith('Guten Tag Anna Weber'), reason: '$leer');
        expect(text, isNot(contains('geehrte(r)')));
      }
    });

    test('förmlich wird nur der Nachname genannt', () {
      expect(bau(geschlecht: 'weiblich'), startsWith('Sehr geehrte Frau Weber,'));
      expect(bau(geschlecht: 'weiblich'), isNot(contains('Frau Anna Weber')));
    });

    test('fehlt der Nachname, tut es der Vorname', () {
      expect(bau(geschlecht: 'weiblich', nachname: ''),
          startsWith('Sehr geehrte Frau Anna'));
    });

    test('ohne jeden Namen bleibt der Gruß allein stehen', () {
      final text = bau(geschlecht: 'weiblich', vorname: '', nachname: '');
      expect(text, startsWith('Guten Tag,'));
    });

    test('jede Sprache hat Anrede und Grußformel', () {
      final erwartet = {
        'de': ['Sehr geehrte Frau Weber', 'Mit freundlichen Grüßen'],
        'en': ['Dear Ms Weber', 'Kind regards'],
        'ro': ['Stimata doamna Weber', 'Cu stima'],
        'ru': ['Уважаемая г-жа Weber', 'С уважением'],
        'uk': ['Шановна пані Weber', 'З повагою'],
        'tr': ['Sayin Anna Weber', 'Saygilarimizla'],
      };
      erwartet.forEach((sprache, teile) {
        final text = bau(geschlecht: 'weiblich', sprache: sprache);
        for (final teil in teile) {
          expect(text, contains(teil), reason: '$sprache: $teil');
        }
      });
    });

    test('Anrede und Grußformel kippen die SMS nicht in UCS-2', () {
      // „Cu stimă" und „Saygılarımızla" tragen Diakritika, die nicht ins
      // GSM-7-Alphabet passen — ohne Transliteration hätte allein die
      // Grußformel die Kosten der ganzen Nachricht verdoppelt.
      for (final s in ['de', 'en', 'ro', 'tr']) {
        expect(SmsService.isGsm7(bau(geschlecht: 'weiblich', sprache: s)), isTrue,
            reason: s);
      }
    });
  });

  group('Medikamenten-Erinnerung', () {
    String bau({
      String slot = 'morgens',
      String liste = 'Marcumar 5 mg; Ramipril 2,5 mg',
      String sprache = 'de',
      String? geschlecht = 'weiblich',
    }) =>
        SmsService.buildMedikamentSms(
          slot: slot,
          medikamente: liste,
          language: sprache,
          geschlecht: geschlecht,
          vorname: 'Anna',
          nachname: 'Weber',
        );

    test('nennt Anrede, Tageszeit und die Präparate', () {
      final text = bau();
      expect(text, startsWith('Sehr geehrte Frau Weber,'));
      expect(text, contains('am Morgen'));
      expect(text, contains('Marcumar 5 mg'));
      expect(text, contains('Ramipril 2,5 mg'));
      expect(text, contains('Mit freundlichen Grüßen'));
    });

    test('jede Tageszeit hat ihr eigenes Wort', () {
      expect(bau(slot: 'morgens'), contains('am Morgen'));
      expect(bau(slot: 'mittags'), contains('am Mittag'));
      expect(bau(slot: 'abends'), contains('am Abend'));
      expect(bau(slot: 'nachts'), contains('in der Nacht'));
    });

    test('in der Sprache des Mitglieds', () {
      expect(bau(sprache: 'ro'), contains('va rugam sa nu uitati medicamentele'));
      expect(bau(sprache: 'ro'), contains('dimineata'));
      expect(bau(sprache: 'ru'), contains('не забудьте принять лекарства'));
      expect(bau(sprache: 'tr'), contains('ilaclarinizi'));
      expect(bau(sprache: 'ar'), contains('أدويتك'));
    });

    test('ohne Geschlecht wird neutral angeredet', () {
      expect(bau(geschlecht: null), startsWith('Guten Tag Anna Weber,'));
    });

    test('lateinische Sprachen bleiben in GSM-7', () {
      for (final s in ['de', 'en', 'ro', 'tr']) {
        expect(SmsService.isGsm7(bau(sprache: s)), isTrue, reason: s);
      }
    });

    test('sehr viele Präparate sprengen die Nachricht nicht', () {
      // Lieber eine gekürzte Liste als gar keine Erinnerung.
      final text = bau(liste: List.filled(40, 'Irgendein Praeparat 10 mg').join('; '));
      expect(SmsService.segments(text), lessThanOrEqualTo(6));
      expect(text, contains('am Morgen'));
    });

    test('unbekannte Tageszeit fällt auf den Morgen zurück statt zu werfen', () {
      expect(() => bau(slot: 'zwischendurch'), returnsNormally);
    });
  });

  group('Wetterwarnung', () {
    String bau({
      String sprache = 'de',
      String severity = 'severe',
      String event = 'Sturmböen',
      String headline = 'Amtliche WARNUNG vor STURMBÖEN, Böen bis 90 km/h',
    }) =>
        SmsService.buildWetterSms(
          event: event,
          headline: headline,
          severity: severity,
          language: sprache,
          geschlecht: 'weiblich',
          vorname: 'Anna',
          nachname: 'Weber',
        );

    test('nennt Anrede, Ereignis, Stufe und den amtlichen Wortlaut', () {
      final text = bau();
      expect(text, startsWith('Sehr geehrte Frau Weber,'));
      expect(text, contains('Wetterwarnung für Ihren Wohnort'));
      expect(text, contains('Sturmböen'));
      expect(text, contains('(Schwer)'));
      expect(text, contains('90 km/h'));
    });

    test('extreme Warnungen sind als AKUT gekennzeichnet', () {
      expect(bau(severity: 'extreme'), contains('(AKUT)'));
      // Unterhalb von „schwer" wird keine Stufe genannt — solche Warnungen
      // kommen ohnehin nicht als SMS, der Server filtert sie vorher weg.
      expect(bau(severity: 'moderate'), isNot(contains('(Schwer)')));
    });

    test('in der Sprache des Mitglieds, DWD-Wortlaut bleibt im Original', () {
      expect(bau(sprache: 'ro'), contains('Avertizare meteo'));
      expect(bau(sprache: 'ro'), contains('Sturm'));
      expect(bau(sprache: 'ru'), contains('Штормовое предупреждение'));
      expect(bau(sprache: 'tr'), contains('hava uyarisi'));
      expect(bau(sprache: 'ar'), contains('تحذير من الطقس'));
    });

    test('lange DWD-Wortlaute werden gekürzt statt zu explodieren', () {
      final text = bau(headline: 'Amtliche Unwetterwarnung mit sehr langem Text ' * 12);
      expect(SmsService.segments(text), lessThanOrEqualTo(6));
      expect(text, contains('Wetterwarnung'));
    });

    test('lateinische Sprachen bleiben in GSM-7', () {
      for (final s in ['de', 'en', 'ro', 'tr']) {
        expect(SmsService.isGsm7(bau(sprache: s)), isTrue, reason: s);
      }
    });
  });
}
