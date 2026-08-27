import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/sehhilfen_muster.dart';

/// ⚠️ Diese Datei ist die EINZIGE Stelle, an der ein Auseinanderlaufen mit dem
/// Server auffallen kann: das PHP der sechs `*_hilfsmittel_manage.php` liegt in
/// keinem Repo. Wer die Liste hier ändert, ändert sie dort mit — sonst weist
/// der Server den neuen Wert mit HTTP 400 ab, der Client nimmt zurück, und für
/// den Vorsitzenden passiert beim Speichern einfach nichts.
void main() {
  group('Whitelist, gespiegelt gegen MUSTER_ERLAUBT auf dem Server', () {
    test('genau diese drei Schlüssel, in dieser Reihenfolge', () {
      expect(kMusterSchluessel, ['m16', 'm8', 'm8a']);
    });

    test('jeder Schlüssel hat genau einen Vordruck', () {
      expect(kMusterVordrucke.map((m) => m.key).toList(), kMusterSchluessel);
    });

    test('die Spalte ist VARCHAR(4) — kein Schlüssel darf länger sein', () {
      // Ein längerer Wert würde von MariaDB nicht gekürzt, sondern (STRICT)
      // die Zeile ablehnen. Die Grenze steht deshalb hier fest.
      for (final k in kMusterSchluessel) {
        expect(k.length, lessThanOrEqualTo(4), reason: k);
      }
    });
  });

  group('musterVordruck', () {
    test('unbekannt, leer und null fallen auf Muster 16', () {
      // Beim ANZEIGEN ist der Rückfall richtig: ein Datensatz aus einer
      // neueren Fassung muss darstellbar bleiben. Beim SPEICHERN weist der
      // Server denselben Wert dagegen ab — das ist Absicht, nicht Widerspruch.
      expect(musterVordruck(null).key, kMuster16);
      expect(musterVordruck('').key, kMuster16);
      expect(musterVordruck('m99').key, kMuster16);
      expect(musterVordruck('M8').key, kMuster16, reason: 'Groß/klein zählt');
    });

    test('trifft die richtige Einlösestelle', () {
      // Der Kern des ganzen Reiters: Sehhilfen gehen zum Optiker, alles
      // andere zum Sanitätshaus. Genau das stand vorher falsch im Banner.
      expect(musterVordruck(kMuster16).einloesestelle, 'Sanitätshaus');
      expect(musterVordruck(kMuster8).einloesestelle, 'Augenoptiker');
      expect(musterVordruck(kMuster8a).einloesestelle, 'Augenoptiker');
    });

    test('Anzahl Paare gibt es nur bei Muster 16', () {
      expect(musterVordruck(kMuster16).zeigtAnzahlPaare, isTrue);
      expect(musterVordruck(kMuster8).zeigtAnzahlPaare, isFalse);
      expect(musterVordruck(kMuster8a).zeigtAnzahlPaare, isFalse);
    });
  });

  group('Indikationslisten', () {
    test('jeder Vordruck bekommt seine eigene Liste', () {
      expect(musterIndikationen(kMuster16), same(kIndikationenMuster16));
      expect(musterIndikationen(kMuster8), same(kIndikationenMuster8));
      expect(musterIndikationen(kMuster8a), same(kIndikationenMuster8a));
      expect(musterIndikationen(null), same(kIndikationenMuster16));
    });

    test('keine orthopädische Diagnose unter einer Sehhilfenverordnung', () {
      // Die Umschaltung ist der eigentliche Zweck: „Hallux valgus" auf einem
      // Muster 8 wäre nicht bloß hässlich, sondern eine falsche Angabe in
      // der Akte.
      for (final liste in [kIndikationenMuster8, kIndikationenMuster8a]) {
        for (final i in liste) {
          expect(i.label, isNot(contains('Hallux')));
          expect(i.label, isNot(contains('Fuß')));
          expect(i.ref, startsWith('§'), reason: '${i.label} braucht eine Fundstelle');
        }
      }
      for (final i in kIndikationenMuster16) {
        expect(i.ref, isNot(startsWith('§')), reason: 'Muster 16 trägt ICD-10');
      }
    });

    test('die Fundstelle passt in diagnose_icd10 (VARCHAR(30))', () {
      for (final liste in [kIndikationenMuster16, kIndikationenMuster8, kIndikationenMuster8a]) {
        for (final i in liste) {
          expect(i.ref.length, lessThanOrEqualTo(30), reason: i.ref);
          expect(i.ref, isNotEmpty);
          expect(i.label, isNotEmpty);
        }
      }
    });

    test('Fundstellen dürfen sich wiederholen — die Radio-Werte nicht', () {
      // ⚠️ Genau hier lag die Falle: „§ 12 Abs. 1 Nr. 3" trägt Myopie UND
      // Astigmatismus, „§ 16 Abs. 3" gleich drei Einträge. Wäre die
      // Fundstelle der Radio-Wert, leuchteten zwei Knöpfe gemeinsam und die
      // Auswahl wäre mehrdeutig. Der Wert ist deshalb `ref|label`.
      expect(
        kIndikationenMuster8.map((i) => i.ref).toSet().length,
        lessThan(kIndikationenMuster8.length),
        reason: 'Voraussetzung des Tests: Fundstellen wiederholen sich wirklich',
      );
      for (final liste in [kIndikationenMuster16, kIndikationenMuster8, kIndikationenMuster8a]) {
        final werte = liste.map((i) => '${i.ref}|${i.label}').toList();
        expect(werte.toSet().length, werte.length, reason: 'Radio-Werte doppelt');
        expect(werte, isNot(contains('andere')), reason: 'kollidiert mit dem Freitext-Knopf');
      }
    });

    test('Muster 8 trägt beide Anspruchswege — § 12 und § 17', () {
      // Der Unterschied, an dem im Betrieb alles hängt: § 12 hängt an Alter
      // und Dioptrien, § 17 allein an der Diagnose. Fiele einer der beiden
      // weg, wäre die Hälfte der Fälle nicht erfassbar.
      expect(kIndikationenMuster8.any((i) => i.ref.startsWith('§ 12')), isTrue);
      expect(kIndikationenMuster8.any((i) => i.ref.startsWith('§ 17')), isTrue);
    });

    test('die Dioptrien-Schwellen sind die der Richtlinie, nicht die des Gesetzes', () {
      // § 33 Abs. 2 SGB V sagt „mehr als 6" / „mehr als 4"; § 12 Abs. 1 Nr. 3
      // HilfsM-RL setzt das als ≥ 6,25 / ≥ 4,25 um. Auf dem Rezept steht die
      // Richtlinien-Schwelle — die Gesetzeszahl wäre hier schlicht falsch.
      final texte = kIndikationenMuster8.map((i) => i.label).join(' ');
      expect(texte, contains('6,25'));
      expect(texte, contains('4,25'));
      expect(texte, isNot(contains('6,0 dpt')));
    });
  });

  group('Wiederversorgung', () {
    test('nur Muster 16 bekommt ein Erinnerungs-Ticket', () {
      // Spiegelt `$muster !== 'm16'` im Server-Endpunkt. Für Sehhilfen gibt es
      // keine Frist, sondern eine Bedingung — ein Ticket „nach 6 Monaten"
      // würde dem Mitglied einen Termin ankündigen, den es nicht gibt.
      expect(musterHatWiederversorgungsTicket(kMuster16), isTrue);
      expect(musterHatWiederversorgungsTicket(kMuster8), isFalse);
      expect(musterHatWiederversorgungsTicket(kMuster8a), isFalse);
      expect(musterHatWiederversorgungsTicket(null), isTrue, reason: 'Altdaten sind m16');
    });

    test('der Regeltext nennt bei Sehhilfen keine Monatsfrist', () {
      expect(wiederversorgungRegel(kMuster16), contains('6 Monaten'));
      expect(wiederversorgungRegel(kMuster8), contains('0,5 dpt'));
      expect(wiederversorgungRegel(kMuster8), isNot(contains('Monaten')));
      expect(wiederversorgungRegel(kMuster8a), contains('Vergrößerungsbedarf'));
      expect(wiederversorgungRegel(kMuster8a), isNot(contains('Monaten')));
    });
  });
}
