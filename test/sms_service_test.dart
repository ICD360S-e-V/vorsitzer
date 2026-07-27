import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sms_service.dart';

/// Die Termin-SMS kostet Geld und geht an echte Mitglieder — beides macht die
/// beiden Prüfungen hier wichtig:
///
///  * [SmsService.check] darf nur auf Mobilnummern senden. Eine SMS an eine
///    Festnetznummer verschwindet spurlos (Telekom/Vodafone haben den Dienst
///    2023 abgeschaltet), das Mitglied bekäme nie eine Erinnerung und niemand
///    würde es merken.
///  * [SmsService.buildTerminSms] muss in EIN Segment passen und im
///    GSM-7-Alphabet bleiben. Ein einziges Emoji kippt die ganze Nachricht in
///    UCS-2 — statt 160 passen dann 70 Zeichen, aus einer SMS werden vier.
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

    test('bleibt bei einer SMS und enthält Datum, Uhrzeit und Ort', () {
      final text = SmsService.buildTerminSms(
        terminDate: termin,
        title: 'Beratung Jobcenter',
        location: 'Rathaus Stuttgart',
      );

      expect(text, contains('28.07.2026'));
      expect(text, contains('10:30'));
      expect(text, contains('Rathaus Stuttgart'));
      expect(text, contains('Beratung Jobcenter'));
      expect(SmsService.segments(text), 1);
    });

    test('überlange Angaben werden gekürzt statt in eine zweite SMS zu laufen', () {
      final text = SmsService.buildTerminSms(
        terminDate: termin,
        title: 'Sehr langer Betreff ' * 10,
        location: 'Ein ausgesprochen langer Ortsname mit Zusatzangaben ' * 5,
      );

      expect(SmsService.segments(text), 1);
      expect(text, contains('28.07.2026'));
    });

    test('kein Emoji, egal was in Titel oder Ort steht', () {
      final text = SmsService.buildTerminSms(
        terminDate: termin,
        title: '📋 Beratung',
        location: '📍 Rathaus',
      );

      expect(text, isNot(contains('📋')));
      expect(text, isNot(contains('📍')));
      expect(SmsService.segments(text), 1);
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
}
