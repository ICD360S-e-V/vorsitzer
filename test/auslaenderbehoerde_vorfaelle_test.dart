import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/auslaenderbehoerde_vorfaelle.dart';

void main() {
  group('Katalog', () {
    test('alle Gruppen sind besetzt und die Summe stimmt', () {
      var summe = 0;
      for (final g in kAbGruppen) {
        final n = abTypenDerGruppe(g).length;
        expect(n, greaterThan(0), reason: 'Gruppe „$g" ist leer');
        summe += n;
      }
      expect(summe, kAbVorfallTypen.length,
          reason: 'ein Typ hängt in einer Gruppe, die kAbGruppen nicht kennt — '
              'er wäre im Dropdown unsichtbar');
    });

    test('keine doppelten Namen', () {
      final namen = kAbVorfallTypen.map((t) => t.name).toList();
      expect(namen.toSet().length, namen.length);
    });

    // ⚠️ Zuständig ist die Staatsangehörigkeitsbehörde, nicht die
    // Ausländerbehörde. Steht sie hier, landet später die falsche Behörde im
    // Anschreiben.
    test('Einbürgerung steht NICHT im Katalog', () {
      for (final t in kAbVorfallTypen) {
        expect(t.name.toLowerCase().contains('einbürgerung'), isFalse,
            reason: '„${t.name}" gehört zur Staatsangehörigkeitsbehörde');
        expect(t.name.toLowerCase().contains('staatsangehörigkeit'), isFalse,
            reason: '„${t.name}" gehört zur Staatsangehörigkeitsbehörde');
      }
    });

    // ⚠️ Das Visum selbst beantragt man vor der Einreise bei der
    // Auslandsvertretung. Nur die Verlängerung im Inland macht die ABH.
    test('Visum heißt „Visumverlängerung", nicht „Visum beantragen"', () {
      final visum = kAbVorfallTypen.where((t) => t.name.toLowerCase().contains('visum'));
      expect(visum, isNotEmpty);
      for (final t in visum) {
        expect(t.name, 'Visumverlängerung');
        expect(t.hinweis, isNotNull,
            reason: 'ohne Hinweis liest sich der Eintrag wie ein Erstantrag');
        expect(t.hinweis, contains('Auslandsvertretung'));
      }
    });

    test('die geteilt zuständigen Vorgänge tragen einen Hinweis', () {
      // Jeder dieser Vorgänge wird NICHT allein von der Ausländerbehörde
      // erledigt. Fehlt der Hinweis, schickt jemand die Person an den
      // falschen Schalter.
      const brauchtHinweis = [
        'Aufenthaltsgestattung verlängern', // Erstausstellung: BAMF
        'Aufenthaltstitel bei Asylantrag beantragen', // Asylantrag: BAMF
        'Beschäftigungserlaubnis bei Duldung', // Zustimmung: Agentur für Arbeit
        'Beschäftigungserlaubnis bei Aufenthaltsgestattung',
        'Integrationskurs — Verpflichtung oder Berechtigungsschein', // Kurs: BAMF
        'Visumverlängerung', // Erstantrag: Auslandsvertretung
      ];
      for (final name in brauchtHinweis) {
        final t = abTypFinden(name);
        expect(t, isNotNull, reason: '„$name" fehlt im Katalog');
        expect(t!.hinweis, isNotNull, reason: '„$name" ohne Zuständigkeitshinweis');
      }
    });

    test('der Auffang-Eintrag ist vorhanden', () {
      // Ausweisung, Anhörung und Widerspruch sind keine beantragbaren
      // Leistungen und stehen in keinem Behördenkatalog — ohne diesen Eintrag
      // lässt sich der häufigste Anlass gar nicht erfassen.
      expect(abTypFinden(kAbSonstigesTyp), isNotNull);
    });
  });

  group('Fristen', () {
    test('die Vorwarnzeit ist NICHT für alle gleich', () {
      final fiktion = abVorwarnungTage('Fiktionsbescheinigung');
      final titel = abVorwarnungTage('Aufenthaltserlaubnis verlängern');
      final duldung = abVorwarnungTage('Duldung — Erteilung oder Verlängerung');
      expect(fiktion, lessThan(duldung));
      expect(duldung, lessThan(titel));
    });

    test('90 Tage wären für die Fiktionsbescheinigung sinnlos', () {
      // Sie gilt oft nur drei Monate: mit der langen Frist stünde die Warnung
      // schon am Ausstellungstag.
      expect(abVorwarnungTage('Fiktionsbescheinigung'), lessThan(90));
    });

    test('unbekannter Typ fällt auf die lange Frist zurück, nicht auf 0', () {
      expect(abVorwarnungTage('gibt es nicht'), kAbFristTitel.vorwarnungTage);
    });

    test('die Niederlassungserlaubnis wird trotz unbefristetem Titel überwacht', () {
      // Der Titel ist unbefristet, die Karte nicht — sonst fällt der
      // Kartentausch durch.
      final t = abTypFinden('Niederlassungserlaubnis beantragen');
      expect(t?.frist, isNotNull);
      expect(t!.frist!.laufzeit.toLowerCase(), contains('karte'));
    });

    test('die Verpflichtungserklärung ist ein Haftungsdatum, kein Ablauf', () {
      final t = abTypFinden('Verpflichtungserklärung abgeben');
      expect(t?.frist, isNotNull);
      expect(t!.frist!.dokument.toLowerCase(), contains('haftung'));
      expect(t.frist!.laufzeit, contains('5 Jahre'));
    });

    test('Vorgänge ohne eigenes Dokument haben keine Frist', () {
      expect(abTypFinden('Rückkehrberatung')?.frist, isNull);
      expect(abTypFinden('Elektronischen Aufenthaltstitel (eAT) abholen')?.frist, isNull);
      expect(abTypFinden(kAbSonstigesTyp)?.frist, isNull);
    });
  });

  group('abLaeuftBaldAb', () {
    final heute = DateTime(2026, 9, 4);

    test('genau an der Grenze ist fällig, einen Tag davor nicht', () {
      const typ = 'Fiktionsbescheinigung'; // 21 Tage
      expect(abLaeuftBaldAb(typ, DateTime(2026, 9, 25), heute: heute), isTrue);
      expect(abLaeuftBaldAb(typ, DateTime(2026, 9, 26), heute: heute), isFalse);
    });

    test('ein bereits abgelaufenes Datum ist IMMER fällig', () {
      // Sonst verschwände die Warnung genau dann, wenn der Druck am größten ist.
      expect(abLaeuftBaldAb('Fiktionsbescheinigung', DateTime(2020, 1, 1), heute: heute),
          isTrue);
      expect(abLaeuftBaldAb(kAbSonstigesTyp, DateTime(2020, 1, 1), heute: heute), isTrue);
    });

    test('ohne Datum wird nicht gewarnt', () {
      expect(abLaeuftBaldAb('Fiktionsbescheinigung', null, heute: heute), isFalse);
    });

    test('derselbe Tag urteilt je nach Typ verschieden', () {
      // Der eigentliche Zweck der typabhängigen Frist.
      final tag = DateTime(2026, 11, 1); // 58 Tage entfernt
      expect(abLaeuftBaldAb('Fiktionsbescheinigung', tag, heute: heute), isFalse);
      expect(abLaeuftBaldAb('Aufenthaltserlaubnis verlängern', tag, heute: heute), isTrue);
    });
  });

  group('abDatumLesen', () {
    test('liest TT.MM.JJJJ', () {
      expect(abDatumLesen('30.11.2026'), DateTime(2026, 11, 30));
    });

    test('leer heißt „nicht erfasst", nicht „unbefristet"', () {
      expect(abDatumLesen(''), isNull);
      expect(abDatumLesen(null), isNull);
      expect(abDatumLesen('   '), isNull);
    });

    test('andere Schreibweisen werden NICHT geraten', () {
      expect(abDatumLesen('2026-11-30'), isNull);
      expect(abDatumLesen('1.1.2026'), isNull);
      expect(abDatumLesen('unbefristet'), isNull);
    });

    test('unmögliche Tage werden abgelehnt statt umgerechnet', () {
      // DateTime(2026,2,31) ergäbe still den 3. März.
      expect(abDatumLesen('31.02.2026'), isNull);
      expect(abDatumLesen('32.01.2026'), isNull);
      expect(abDatumLesen('01.13.2026'), isNull);
    });
  });

  group('§ 24 Ukraine — gesetzliche Fortgeltung', () {
    test('der Typ steht im Katalog und ist als Fortgeltung markiert', () {
      final t = abTypFinden(kUkraineTyp);
      expect(t, isNotNull);
      expect(t!.fortgeltung, isTrue);
      expect(abFortgeltung(kUkraineTyp), isTrue);
    });

    // 🔴 Der Kern. Vor dieser Regel hätte die App einem ukrainischen Mitglied
    // „läuft ab, bitte verlängern" angezeigt — falsch, und es hätte jemanden
    // zu einem Termin geschickt, den es nicht gibt.
    test('es wird NIE an einen Ablauf erinnert, auch nicht bei totem Datum', () {
      final heute = DateTime(2026, 9, 4);
      for (final d in [
        DateTime(2024, 1, 1), // längst „abgelaufen"
        DateTime(2026, 9, 5), // morgen
        DateTime(2030, 1, 1),
      ]) {
        expect(abLaeuftBaldAb(kUkraineTyp, d, heute: heute), isFalse,
            reason: 'für § 24 darf $d keine Ablaufwarnung auslösen');
      }
    });

    test('ein normaler Titel mit demselben Datum warnt sehr wohl', () {
      // Gegenprobe: die Ausnahme gilt NUR für § 24, nicht für alle.
      final heute = DateTime(2026, 9, 4);
      expect(
          abLaeuftBaldAb('Aufenthaltserlaubnis verlängern', DateTime(2024, 1, 1),
              heute: heute),
          isTrue);
    });

    test('der Typ trägt KEINE gewöhnliche Frist', () {
      // Eine Frist hier hieße, das Kartendatum ernst zu nehmen.
      expect(abTypFinden(kUkraineTyp)!.frist, isNull);
    });

    test('das deutsche Datum und das EU-Datum werden nicht vermischt', () {
      // ⚠️ Die EU hat bis 2028 verlängert, Deutschland erst bis 2027. Das
      // EU-Datum als Ablauf anzuzeigen wäre eine Zusage, die hier noch
      // niemand gemacht hat.
      expect(kUkraineFortgeltungBis, '04.03.2027');
      expect(kUkraineEuBeschlossenBis, '04.03.2028');
      expect(kUkraineFortgeltungBis, isNot(kUkraineEuBeschlossenBis));
    });

    test('der Stichtag steht als eigene Angabe bereit', () {
      // Wer am Stichtag keine gültige Erlaubnis hatte, fällt aus der
      // Fortgeltung und braucht die Behörde doch.
      expect(kUkraineStichtag, isNotEmpty);
    });
  });

  group('Kopplung an den Bildschirm', () {
    // ⚠️ Diese Prüfungen lesen den Quelltext, weil die Regeln in Widgets
    // stecken, die ohne laufenden Server nicht zu bauen sind. Kommentarzeilen
    // werden vorher entfernt — sonst bestätigt der Test eine tote Zeile.
    String quelle(String pfad) => File(pfad)
        .readAsLinesSync()
        .where((z) => !z.trimLeft().startsWith('//'))
        .join('\n');

    test('der Vorfall wird als gueltig_bis gespeichert, nicht als ablaufdatum', () {
      // Vor der Umstellung schrieb der Bildschirm „ablaufdatum", während die
      // Übersicht „gueltig_bis" las — das Feld blieb dadurch immer leer.
      final s = quelle('lib/widgets/behorde_auslaenderbehoerde.dart');
      expect(s, contains("'gueltig_bis':"));
      expect(s.contains("'ablaufdatum'"), isFalse,
          reason: 'der alte, nie gelesene Feldname ist zurück');
    });

    test('der Bildschirm bekommt apiService und userId', () {
      final s = quelle('lib/widgets/behorde_tab_content.dart');
      final i = s.indexOf('BehordeAuslaenderbehoerdeContent(');
      expect(i, greaterThan(-1));
      final block = s.substring(i, i + 200);
      expect(block, contains('apiService:'));
      expect(block, contains('userId:'));
    });

    test('der Bildschirm fordert bei § 24 NICHT zur Verlängerung auf', () {
      // Der Fortgeltungs-Zweig muss vor der Ablauflogik greifen, sonst steht
      // trotz richtiger Regel die falsche Karte auf dem Schirm.
      final s = quelle('lib/widgets/behorde_auslaenderbehoerde.dart');
      expect(s, contains('_fortgeltungKarte'));
      final k = s.indexOf('Widget _standKarte');
      final f = s.indexOf('abFortgeltung(typ)', k);
      final a = s.indexOf('abDatumLesen', k);
      expect(f, greaterThan(-1));
      expect(f, lessThan(a),
          reason: 'die Fortgeltung muss VOR dem Ablaufdatum geprüft werden');
    });

    test('die Fortgeltungsdaten kommen vom Server, nicht aus dem Kompilat', () {
      // ⚠️ Die Verordnung wird jährlich neu erlassen; die nächste ist im
      // Herbst 2026 fällig. Ein einkompiliertes Datum stünde nach einem
      // Release monatelang falsch auf dem Schirm.
      final s = quelle('lib/widgets/behorde_auslaenderbehoerde.dart');
      expect(s, contains("res['ukraine']"));
      expect(s, contains(r'Verlängert bis $_uaBis'),
          reason: 'die Karte muss den Serverwert zeigen, nicht die Konstante');
      // Die Konstanten bleiben als Rückfall, aber nur dort.
      expect(s, contains('String _uaBis = kUkraineFortgeltungBis;'));
    });

    test('der Detailschirm zeigt dasselbe Datum wie die Übersicht', () {
      // Zwei Klassen, ein Datum — sonst widersprechen sich zwei Bildschirme
      // über denselben Vorfall.
      final s = quelle('lib/widgets/behorde_auslaenderbehoerde.dart');
      expect(s, contains(r'${widget.uaBis}'));
      expect(s, contains('uaBis: _uaBis,'));
    });

    test('das Amt trägt keine erfundene E-Mail-Adresse', () {
      // Ulm veröffentlicht keine Adresse im Klartext, nur ein Kontaktformular.
      final s = quelle('lib/widgets/behorde_auslaenderbehoerde.dart');
      final ulm = s.indexOf('Stadt Ulm — Ausländer');
      expect(ulm, greaterThan(-1));
      final block = s.substring(ulm, s.indexOf('Alb-Donau', ulm));
      expect(block.contains("'email'"), isFalse,
          reason: 'für Ulm ist keine E-Mail-Adresse belegt');
    });
  });
}
