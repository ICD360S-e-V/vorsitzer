// Wer die Vollmacht für ein Kinderkonto erteilen darf.
//
// ⚠️ `kVormundTypen` bildet die Aufzählung von `users.vormund_typ` ab.
// Die Spalte liegt auf dem Server, das PHP liegt in keinem Repo — dieser
// Test ist die EINZIGE Stelle, an der die Kopplung überhaupt auffallen
// kann. Kommt serverseitig ein siebter Wert dazu, muss er hier ergänzt
// werden; bis dahin zeigt der Bildschirm ihn roh an, statt ihn zu
// verschlucken (dafür der letzte Fall unten).
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_kindergarten_zahlung_akte.dart';

void main() {
  group('vormund_typ', () {
    // Wortgleich aus der Spaltendefinition auf dem Server:
    //   enum('familienangehoeriger','ehrenamtlich','vorlaeufig',
    //        'vorsorgevollmacht','berufsbetreuer','sorgeberechtigter')
    const serverEnum = {
      'familienangehoeriger',
      'ehrenamtlich',
      'vorlaeufig',
      'vorsorgevollmacht',
      'berufsbetreuer',
      'sorgeberechtigter',
    };

    test('jeder Wert der Spalte hat einen Klartext', () {
      final fehlend = serverEnum.difference(kVormundTypen.keys.toSet());
      expect(fehlend, isEmpty,
          reason: 'Ohne Klartext stünde der rohe Datenbankwert auf dem Schirm');
    });

    test('kein Klartext ohne Wert in der Spalte', () {
      final ueberzaehlig = kVormundTypen.keys.toSet().difference(serverEnum);
      expect(ueberzaehlig, isEmpty,
          reason: 'Ein Eintrag, den die Spalte nicht kennt, wird nie angezeigt '
              'und täuscht Abdeckung vor');
    });

    // 🔴 Der Unterschied, um den es fachlich geht: nur die elterliche
    // Sorge (§ 1629 BGB) belegt die Vertretungsbefugnis. „Familie" ist
    // eine Beziehung, keine Befugnis — eine Großmutter ist Familie und
    // trotzdem nicht sorgeberechtigt.
    test('nur sorgeberechtigter belegt die Vertretungsbefugnis', () {
      expect(kVormundTypen['sorgeberechtigter'], 'sorgeberechtigt');
      for (final t in serverEnum.where((t) => t != 'sorgeberechtigter')) {
        expect(kVormundTypen[t], isNot('sorgeberechtigt'),
            reason: '$t darf nicht wie elterliche Sorge klingen');
      }
    });

    test('ein unbekannter Wert fällt durch, statt zu verschwinden', () {
      // Der Bildschirm zeigt in diesem Fall den rohen Wert. Der Test hält
      // fest, dass die Abbildung ihn NICHT kennt — sonst wäre die Prüfung
      // oben tautologisch.
      expect(kVormundTypen['nachlasspfleger'], isNull);
    });
  });

  // Dieselbe Kopplung, andere Spalte: `kiga_zahlung_vollmacht_versand.weg`.
  // Auch sie liegt nur in der Datenbank; ohne diesen Test fiele ein neuer
  // Weg erst auf, wenn im Versandprotokoll ein roher Wert steht.
  group('versand weg', () {
    const serverEnum = {'chat', 'email', 'de_mail', 'fax', 'post', 'persoenlich'};

    test('jeder Weg hat einen Klartext', () {
      expect(serverEnum.difference(kVersandWege.keys.toSet()), isEmpty);
    });

    test('kein Klartext ohne Weg in der Spalte', () {
      expect(kVersandWege.keys.toSet().difference(serverEnum), isEmpty);
    });

    // 🔴 Die Regel des Vorsitzenden (18.08.2026): Chat trägt nur das
    // Leseexemplar, E-Mail und Fax nur die von beiden unterschriebene
    // Fassung. Der Server setzt das durch; hier steht fest, dass alle drei
    // Wege überhaupt existieren — verschwände einer aus der Aufzählung,
    // liefe die Durchsetzung ins Leere.
    test('die drei Wege der Vollmacht sind vorhanden', () {
      for (final w in ['chat', 'email', 'fax']) {
        expect(kVersandWege.containsKey(w), isTrue, reason: '$w fehlt');
      }
    });

    test('ein unbekannter Weg fällt durch', () {
      expect(kVersandWege['bea'], isNull);
    });
  });
}
