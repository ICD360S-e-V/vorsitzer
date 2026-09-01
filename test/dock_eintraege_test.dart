import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/models/dock_eintrag.dart';
import 'package:icd360sev_vorsitzer/models/user.dart';
import 'package:icd360sev_vorsitzer/services/termin_service.dart';
import 'package:icd360sev_vorsitzer/utils/dock_eintraege_bauen.dart';

/// Was die Schnellstart-Leiste anzeigt.
///
/// ⚠️ Diese Prüfungen laufen ohne Fenster, ohne Server und ohne Anmeldung —
/// das ist der Grund, warum `DockZeilen` überhaupt eine eigene Datei ist. Im
/// Dashboard läge dieselbe Logik hinter einem angemeldeten Bildschirm und
/// wäre nur im Betrieb zu prüfen.
void main() {
  User mitglied({
    int id = 1,
    String nr = 'M00001',
    String? vorname,
    String? nachname,
    String name = '',
    String? ort,
    String status = 'aktiv',
  }) =>
      User(
        id: id,
        mitgliedernummer: nr,
        email: '',
        name: name,
        vorname: vorname,
        nachname: nachname,
        ort: ort,
        status: status,
        role: 'mitglied',
      );

  Termin termin({
    int id = 1,
    String titel = 'Vorstandssitzung',
    required DateTime wann,
    String ort = 'Geschäftsstelle',
    String status = 'scheduled',
    bool notfall = false,
    String kategorie = 'vorstandssitzung',
  }) =>
      Termin(
        id: id,
        title: titel,
        category: kategorie,
        description: '',
        terminDate: wann,
        durationMinutes: 60,
        location: ort,
        createdBy: 2,
        isNotfall: notfall,
        status: status,
        createdAt: DateTime(2026, 1, 1),
      );

  // ══════════════════════════════════════════════════════════════════
  group('Mitglieder', () {
    test('nach Namen sortiert, nicht nach id', () {
      final zeilen = DockZeilen.mitglieder([
        mitglied(id: 1, vorname: 'Zora', nachname: 'Albescu'),
        mitglied(id: 2, vorname: 'Anton', nachname: 'Zimmermann'),
        mitglied(id: 3, vorname: 'Bianca', nachname: 'Mach'),
      ]);
      expect(zeilen.map((z) => z.titel).toList(),
          ['Anton Zimmermann', 'Bianca Mach', 'Zora Albescu']);
    });

    test('ohne Vor- und Nachnamen bleibt die Zeile antippbar', () {
      // Zwei Mitglieder haben in `users` weder Vor- noch Nachnamen. Eine
      // leere Zeile wäre nicht bedienbar — man wüsste nicht, wen man anklickt.
      expect(
        DockZeilen.mitglieder([mitglied(name: 'Kanzlei Meier')]).single.titel,
        'Kanzlei Meier',
      );
      expect(
        DockZeilen.mitglieder([mitglied(nr: 'M77777', name: '')]).single.titel,
        'M77777',
      );
    });

    test('Ort steht neben der Nummer, fehlt er, steht nur die Nummer', () {
      expect(
        DockZeilen.mitglieder([mitglied(nr: 'M12345', ort: 'Neu-Ulm')])
            .single
            .unterzeile,
        'M12345 · Neu-Ulm',
      );
      expect(
        DockZeilen.mitglieder([mitglied(nr: 'M12345')]).single.unterzeile,
        'M12345',
      );
    });

    test('nur der ABWEICHENDE Status wird geschrieben', () {
      // Sonst steht hinter vierzig Namen „aktiv" — und genau dann fällt das
      // eine „gesperrt" nicht mehr auf.
      expect(DockZeilen.mitglieder([mitglied()]).single.zusatz, '');
      expect(
        DockZeilen.mitglieder([mitglied(status: 'suspended')]).single.zusatz,
        'gesperrt',
      );
    });

    test('gedeckelt auf maxZeilen', () {
      final viele = List.generate(
          200, (i) => mitglied(id: i, nr: 'M$i', nachname: 'Nach$i'));
      expect(DockZeilen.mitglieder(viele).length, DockZeilen.maxZeilen);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('Termine', () {
    final jetzt = DateTime(2026, 9, 1, 14, 30); // Dienstag

    test('abgesagte Termine erscheinen nicht', () {
      final zeilen = DockZeilen.termine([
        termin(id: 1, wann: jetzt.add(const Duration(days: 1))),
        termin(
            id: 2,
            wann: jetzt.add(const Duration(days: 1)),
            status: 'cancelled'),
      ], jetzt);
      expect(zeilen.map((z) => z.id).toList(), [1]);
    });

    test('ein Termin von heute früh bleibt bis Mitternacht stehen', () {
      // ⚠️ Der eigentliche Punkt: um 9 Uhr verschwände er sonst um 9:01 —
      // an genau dem Tag, an dem man das Ergebnis noch nachtragen muss.
      final heuteFrueh = DateTime(2026, 9, 1, 9, 0);
      final zeilen = DockZeilen.termine([termin(wann: heuteFrueh)], jetzt);
      expect(zeilen, hasLength(1));
      expect(zeilen.single.zusatz, 'Heute 09:00');
    });

    test('was gestern war, ist weg', () {
      final gestern = DateTime(2026, 8, 31, 23, 59);
      expect(DockZeilen.termine([termin(wann: gestern)], jetzt), isEmpty);
    });

    test('jenseits des Fensters wird nichts gezeigt', () {
      final spaet = jetzt.add(DockZeilen.terminFenster + const Duration(days: 1));
      expect(DockZeilen.termine([termin(wann: spaet)], jetzt), isEmpty);
    });

    test('aufsteigend nach Datum', () {
      final zeilen = DockZeilen.termine([
        termin(id: 3, wann: jetzt.add(const Duration(days: 3))),
        termin(id: 1, wann: jetzt.add(const Duration(hours: 2))),
        termin(id: 2, wann: jetzt.add(const Duration(days: 1))),
      ], jetzt);
      expect(zeilen.map((z) => z.id).toList(), [1, 2, 3]);
    });

    test('heute und Notfall werden hervorgehoben, sonst nicht', () {
      expect(
        DockZeilen.termine(
            [termin(wann: jetzt.add(const Duration(hours: 1)))], jetzt)
            .single
            .betont,
        isTrue,
      );
      expect(
        DockZeilen.termine(
            [termin(wann: jetzt.add(const Duration(days: 4)))], jetzt)
            .single
            .betont,
        isFalse,
      );
      expect(
        DockZeilen.termine([
          termin(wann: jetzt.add(const Duration(days: 4)), notfall: true)
        ], jetzt)
            .single
            .betont,
        isTrue,
      );
    });

    test('ohne Ort steht die Kategorie da', () {
      expect(
        DockZeilen.termine([
          termin(
              wann: jetzt.add(const Duration(days: 1)),
              ort: '   ',
              kategorie: 'mitgliederversammlung')
        ], jetzt)
            .single
            .unterzeile,
        'Mitgliederversammlung',
      );
    });

    group('wannText', () {
      test('heute und morgen beim Namen genannt', () {
        expect(DockZeilen.wannText(DateTime(2026, 9, 1, 8, 5), jetzt),
            'Heute 08:05');
        expect(DockZeilen.wannText(DateTime(2026, 9, 2, 9, 0), jetzt),
            'Morgen 09:00');
      });

      test('innerhalb der Woche der Wochentag', () {
        // 4.9.2026 ist ein Freitag.
        expect(DockZeilen.wannText(DateTime(2026, 9, 4, 9, 0), jetzt),
            'Fr 09:00');
      });

      test('ab einer Woche das Datum', () {
        expect(DockZeilen.wannText(DateTime(2026, 9, 12, 9, 0), jetzt),
            '12.09. 09:00');
      });

      test('„morgen" richtet sich nach dem TAG, nicht nach 24 Stunden', () {
        // ⚠️ Um 14:30 sind 24 Stunden später 14:30 des Folgetags — aber
        // 00:30 des Folgetags ist auch „morgen", obwohl nur 10 Stunden
        // dazwischen liegen. Eine Rechnung über `inHours` läge hier falsch.
        expect(DockZeilen.wannText(DateTime(2026, 9, 2, 0, 30), jetzt),
            'Morgen 00:30');
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('Live-Chat', () {
    Map<String, dynamic> unterhaltung(int id,
            {int ungelesen = 0,
            String name = 'Name',
            String letzte = '',
            String status = 'open'}) =>
        {
          'id': id,
          'unread_count': ungelesen,
          'member_name': name,
          'last_message': letzte,
          'status': status,
        };

    test('geschlossene Unterhaltungen erscheinen nicht', () {
      final zeilen = DockZeilen.chat([
        unterhaltung(1),
        unterhaltung(2, status: 'closed'),
      ]);
      expect(zeilen.map((z) => z.id).toList(), [1]);
    });

    test('ungelesene stehen oben, die Serverreihenfolge bleibt sonst erhalten',
        () {
      // ⚠️ Der zweite Teil ist der wichtigere: `List.sort` ist in Dart nicht
      // stabil. Mit einem Vergleich, der für gleichwertige Zeilen 0 liefert,
      // stünden die gelesenen bei jedem Öffnen anders.
      final zeilen = DockZeilen.chat([
        unterhaltung(1),
        unterhaltung(2),
        unterhaltung(3, ungelesen: 2),
        unterhaltung(4),
        unterhaltung(5, ungelesen: 1),
        unterhaltung(6),
      ]);
      expect(zeilen.map((z) => z.id).toList(), [3, 5, 1, 2, 4, 6]);
    });

    test('Zahl und Hervorhebung hängen an den ungelesenen', () {
      final z = DockZeilen.chat([unterhaltung(1, ungelesen: 4)]).single;
      expect(z.abzeichen, 4);
      expect(z.betont, isTrue);

      final ohne = DockZeilen.chat([unterhaltung(1)]).single;
      expect(ohne.abzeichen, 0);
      expect(ohne.betont, isFalse);
    });

    test('der Anriss wird gekürzt und einzeilig gemacht', () {
      // Die Leiste liegt über allen Fenstern; ein ganzer Absatz wäre ein
      // Aushang, kein Hinweis.
      final lang = 'A' * 200;
      final z = DockZeilen.chat([unterhaltung(1, letzte: lang)]).single;
      expect(z.unterzeile.length, lessThanOrEqualTo(61));
      expect(z.unterzeile, endsWith('…'));

      final umbruch =
          DockZeilen.chat([unterhaltung(1, letzte: 'a\n\n  b\tc')]).single;
      expect(umbruch.unterzeile, 'a b c');
    });

    test('ohne Namen steht nicht die leere Zeile da', () {
      expect(DockZeilen.chat([unterhaltung(1, name: '  ')]).single.titel,
          'Unbekannt');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  group('DockEintrag über den Kanal', () {
    test('hin und zurück, ohne Verlust', () {
      const e = DockEintrag(
        id: 7,
        titel: 'Titel',
        unterzeile: 'Unten',
        zusatz: 'Rechts',
        abzeichen: 3,
        betont: true,
      );
      final zurueck = DockEintrag.fromJson(e.toJson());
      expect(zurueck.id, 7);
      expect(zurueck.titel, 'Titel');
      expect(zurueck.unterzeile, 'Unten');
      expect(zurueck.zusatz, 'Rechts');
      expect(zurueck.abzeichen, 3);
      expect(zurueck.betont, isTrue);
    });

    test('eine halbe Karte kippt die Liste nicht', () {
      // ⚠️ Die Gegenseite ist unser eigener Code, aber eine ANDERE Engine:
      // nach einem Update läuft dort für einen Augenblick die alte Fassung.
      final liste = DockEintrag.listeAusJson([
        {'titel': 'nur Titel'},
        'Unsinn',
        {'id': 'keine Zahl', 'titel': 'zweiter'},
      ]);
      expect(liste, hasLength(2));
      expect(liste.first.unterzeile, '');
      expect(liste.first.abzeichen, 0);
      expect(liste.last.id, isNull);
    });

    test('Unsinn statt einer Liste ergibt eine leere Liste, keinen Absturz',
        () {
      expect(DockEintrag.listeAusJson(null), isEmpty);
      expect(DockEintrag.listeAusJson('nein'), isEmpty);
    });

    test('Nutzlast aus dem Fensterargument', () {
      final n = DockEintrag.nutzlastLesen('dock:{"dunkel":true,"zaehler":{"chat":2}}');
      expect(n['dunkel'], isTrue);
      expect((n['zaehler'] as Map)['chat'], 2);
    });

    test('kaputtes Argument hindert die Leiste nicht am Erscheinen', () {
      expect(DockEintrag.nutzlastLesen('dock:{kaputt'), isEmpty);
      expect(DockEintrag.nutzlastLesen('dock'), isEmpty);
    });
  });
}
