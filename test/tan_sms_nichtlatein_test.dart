import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sms_service.dart';

/// Was das Gateway mit dem fertigen TAN-Text machen darf — und was nicht.
///
/// Der Text kommt fertig vom Server, in der Sprache des Mitglieds
/// (users.preferred_language). Von 52 Mitgliedern lesen 13 kyrillisch oder
/// arabisch. Auf dem Tablet passiert damit genau EINS: [SmsService.sanitize].
///
/// Beide Eigenschaften, die hier festgehalten werden, sind heute erfüllt und
/// wurden von Hand geprüft. Sie stehen als Test da, weil sie leise brechen:
///
///  1. `sanitize` entfernt Symbole und Typografie. Würde jemand es später um
///     eine Kategorie erweitern, die Buchstaben mitnimmt, kämen bei 13
///     Mitgliedern verstümmelte oder leere Codes an — und niemand merkte es,
///     weil die deutschen SMS weiter sauber aussähen.
///
///  2. `toGsm7` darf auf diesen Text NIE angewendet werden. Es bildet auf den
///     GSM-7-Zeichensatz ab und würde Kyrillisch und Arabisch zerstören. Für
///     Termin- und Wetter-SMS ist es richtig, hier wäre es fatal.
void main() {
  // Genau die Texte, die der Server erzeugt (SignaturHelper::smsText).
  const texte = <String, String>{
    'de': 'Sehr geehrter Herr Duinea,\n'
        'Ihr Code zum Unterschreiben: 047961\n'
        'Gueltig 5 Minuten. Nicht weitergeben.\n'
        'Nicht angefordert? Bitte ignorieren.\n'
        'ICD360S e.V.',
    'ro': 'Stimate domnule Duinea,\n'
        'Codul pentru semnare: 047961\n'
        'Valabil 5 minute. Nu il transmiteti nimanui.\n'
        'Nu l-ati cerut? Ignorati acest mesaj.\n'
        'ICD360S e.V.',
    'ru': 'Уважаемый г-н Duinea,\n'
        'Ваш код для подписи: 047961\n'
        'Действует 5 минут. Никому не сообщайте.\n'
        'Не запрашивали? Игнорируйте.\n'
        'ICD360S e.V.',
    'uk': 'Шановний пане Duinea,\n'
        'Ваш код для підпису: 047961\n'
        'Дійсний 5 хвилин. Нікому не повідомляйте.\n'
        'Не запитували? Проігноруйте.\n'
        'ICD360S e.V.',
    'ar': 'السيد المحترم Duinea،\n'
        'رمز التوقيع الخاص بك: 047961\n'
        'صالح 5 دقائق. لا تشاركه مع أحد.\n'
        'لم تطلبه؟ يرجى تجاهل الرسالة.\n'
        'ICD360S e.V.',
    'tr': 'Sayin Duinea,\n'
        'Imzalama kodunuz: 047961\n'
        '5 dakika gecerli. Kimseyle paylasmayin.\n'
        'Talep etmediyseniz dikkate almayin.\n'
        'ICD360S e.V.',
    'en': 'Dear Mr Duinea,\n'
        'Your code for signing: 047961\n'
        'Valid 5 minutes. Do not share it.\n'
        'Did not request it? Please ignore.\n'
        'ICD360S e.V.',
  };

  group('TAN-Text ueberlebt das Gateway', () {
    texte.forEach((sprache, text) {
      test('[$sprache] sanitize laesst den Text unveraendert', () {
        expect(SmsService.sanitize(text), text,
            reason: 'sanitize darf an diesem Text nichts aendern — er kommt '
                'fertig vom Server. Schlaegt das fehl, wurde sanitize um eine '
                'Kategorie erweitert, die Buchstaben mitnimmt.');
      });

      test('[$sprache] der Code ueberlebt', () {
        expect(SmsService.sanitize(text), contains('047961'));
      });
    });

    test('kein einziger kyrillischer Buchstabe geht verloren', () {
      // Nicht auf Fragezeichen prüfen: der Text enthält selbst eines
      // („Не запрашивали?"). Gezählt wird stattdessen, wie viele kyrillische
      // Buchstaben vorher und nachher dastehen — das ist die Eigenschaft,
      // um die es geht.
      final kyrillisch = RegExp(r'\p{Script=Cyrillic}', unicode: true);
      final vorher = kyrillisch.allMatches(texte['ru']!).length;
      final nachher = kyrillisch.allMatches(SmsService.sanitize(texte['ru']!)).length;

      expect(vorher, greaterThan(50), reason: 'Der Prüftext muss echt kyrillisch sein.');
      expect(nachher, vorher,
          reason: 'sanitize hat kyrillische Buchstaben verschluckt — bei 12 '
              'Mitgliedern käme ein verstümmelter Code an.');
    });

    test('arabische Zeichen bleiben arabisch', () {
      expect(SmsService.sanitize(texte['ar']!), contains('رمز التوقيع'));
    });

    test('toGsm7 wuerde Kyrillisch zerstoeren — deshalb nie auf diesem Weg', () {
      // Kein Vorwurf an toGsm7: fuer Termin- und Wetter-SMS ist es richtig.
      // Dieser Test haelt nur fest, WARUM der TAN-Pfad es nicht benutzt.
      final zerstoert = SmsService.toGsm7(texte['ru']!);
      expect(zerstoert, isNot(contains('Ваш код')),
          reason: 'Wenn toGsm7 Kyrillisch plötzlich erhält, ist die Annahme '
              'hinter dieser Trennung hinfällig und der TAN-Pfad gehoert '
              'neu bewertet.');
    });

    test('Emoji werden weiterhin entfernt, Buchstaben nicht', () {
      expect(SmsService.sanitize('Код 123 🎉'), 'Код 123');
    });
  });
}
