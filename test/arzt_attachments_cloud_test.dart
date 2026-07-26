import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/korrespondenz_attachments_widget.dart';

/// Augenarzt, HNO und Krankenhaus legen ihre Anhänge über eigene Endpunkte in
/// eigenen Ordnern ab. Genau deshalb war „Cloud" dort früher ausgeschaltet:
/// der Übernahme-Weg zeigte fest auf den Standard-Endpunkt und hätte ins Leere
/// geladen. Diese Tests halten fest, dass der Knopf jetzt erscheint — und dass
/// er ohne Mitglieds-ID wegbleibt, statt still im falschen Ordner zu landen.
void main() {
  group('zeigeCloudKnopf — Sonderspeicher (Augenarzt/HNO/Krankenhaus)', () {
    test('mit Mitglieds-ID: Knopf erscheint', () {
      expect(
        zeigeCloudKnopf(eigenerSpeicher: true, memberId: 17, adminCloud: null),
        isTrue,
      );
    });

    test('eigene Akte des Vorsitzenden: Knopf erscheint', () {
      expect(
        zeigeCloudKnopf(eigenerSpeicher: true, memberId: 2, adminCloud: 'V27655'),
        isTrue,
      );
    });

    test('ohne Mitglieds-ID: Knopf bleibt weg, auch mit gesetztem Admin-Cloud', () {
      // Der entscheidende Fall. Früher hätte der Knopf hier gezeigt und die
      // Datei über den Standard-Endpunkt im falschen Ordner abgelegt —
      // ohne dass irgendetwas nach einem Fehler ausgesehen hätte.
      expect(
        zeigeCloudKnopf(eigenerSpeicher: true, memberId: null, adminCloud: 'V27655'),
        isFalse,
      );
      expect(
        zeigeCloudKnopf(eigenerSpeicher: true, memberId: null, adminCloud: null),
        isFalse,
      );
    });
  });

  group('zeigeCloudKnopf — Standardpfad', () {
    test('mit Mitglieds-ID: Knopf erscheint', () {
      expect(
        zeigeCloudKnopf(eigenerSpeicher: false, memberId: 17, adminCloud: null),
        isTrue,
      );
    });

    test('nur mit ausdrücklich gesetztem Admin-Cloud: Knopf erscheint', () {
      // Hier ist es unschädlich: der Standard-Endpunkt ist ohnehin der
      // richtige, die Mitglieds-ID wird für den Weg nicht gebraucht.
      expect(
        zeigeCloudKnopf(eigenerSpeicher: false, memberId: null, adminCloud: 'V27655'),
        isTrue,
      );
    });

    test('ohne beides: kein Knopf', () {
      expect(
        zeigeCloudKnopf(eigenerSpeicher: false, memberId: null, adminCloud: null),
        isFalse,
      );
    });
  });
}
