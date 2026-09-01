import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/models/blitz_nachricht.dart';
import 'package:icd360sev_vorsitzer/models/dock_eintrag.dart';

/// Die Kopplungen der Schnellstart-Leiste, die alle STILL brechen.
///
/// ⚠️ MEHRERE PRÜFUNGEN LESEN DEN QUELLTEXT, UND DAS IST ABSICHT — derselbe
/// Aufbau wie `sipgate_lebenszeichen_test.dart`. Was hier gesichert wird,
/// steckt in Reihenfolgen innerhalb einer Fensterrückrufkette und in
/// `switch`-Zweigen einer zweiten Flutter-Engine. Beides liesse sich nur mit
/// einem echten GTK-Fenster beobachten, und der Fehlschlag wäre in jedem Fall
/// lautlos: eine Leiste in 1280×720, eine Liste, die leer bleibt, ein Symbol
/// ohne Beschriftung.
void main() {
  /// ⚠️ Wirft statt `expect`. Zwei der Gruppen lesen ihre Datei im
  /// GRUPPENRUMPF, also ausserhalb eines Tests — dort ist `expect` nicht
  /// erlaubt und quittiert mit `OutsideTestException`, was wie ein Ladefehler
  /// des ganzen Bündels aussieht statt wie eine fehlende Datei.
  String quelle(String pfad) {
    final f = File(pfad);
    if (!f.existsSync()) throw StateError('Datei fehlt: $pfad');
    return f.readAsStringSync();
  }

  /// Zeilenkommentare weg. Nötig überall dort, wo geprüft wird, dass etwas
  /// NICHT im Quelltext steht — die Begründung der Regel enthält die Regel.
  String ohneKommentare(String q) => q
      .split('\n')
      .map((z) {
        final i = z.indexOf('//');
        return i < 0 ? z : z.substring(0, i);
      })
      .join('\n');

  /// Rumpf einer Funktion ab ihrer Signatur, über die Parameterliste hinweg.
  ///
  /// ⚠️ MIT ENDE, und das ist der ganze Punkt. Die erste Fassung dieses Tests
  /// schnitt mit `substring(indexOf(...))` ab — also bis zum DATEIENDE. Der
  /// Ausschnitt enthielt dann auch die Verzweigung weiter unten, und die
  /// Gegenprobe (Präfix aus der Erkennung entfernt) blieb grün: der gesuchte
  /// Text stand ja noch irgendwo darunter. Ein Test, der seinen Ausschnitt
  /// nicht begrenzt, prüft die ganze Datei und damit fast nichts.
  String rumpfVon(String quelltext, String signatur) {
    final start = quelltext.indexOf(signatur);
    if (start < 0) throw StateError('nicht gefunden: $signatur');
    // Über die Parameterliste hinweg: erst hinter die schliessende `)`.
    var i = quelltext.indexOf('{', quelltext.indexOf(')', start));
    final anfang = i;
    var tiefe = 0;
    for (; i < quelltext.length; i++) {
      if (quelltext[i] == '{') tiefe++;
      if (quelltext[i] == '}') {
        tiefe--;
        if (tiefe == 0) return quelltext.substring(anfang, i + 1);
      }
    }
    throw StateError('Rumpf nicht geschlossen: $signatur');
  }

  group('Kanal und Fensterargument', () {
    test('Leiste und Blitz teilen sich NICHT den Kanal', () {
      // ⚠️ Die eigentliche Falle des Pakets: ein bidirektionaler Kanal lässt
      // genau ZWEI Engines zu, und die Grenze gilt je Kanal. Trüge die Leiste
      // `kBlitzKanal`, fände sie ihn besetzt — und zwar ohne Fehler beim
      // Start: das Registrieren scheitert erst beim dritten Teilnehmer, und
      // der Rückfall sieht aus wie „keine Daten".
      expect(kDockKanal, isNot(kBlitzKanal));
    });

    test('die Fensterargumente sind nicht ineinander enthalten', () {
      // main() entscheidet über `startsWith`. Wäre das eine ein Präfix des
      // anderen, landete ein Fenster in der falschen Wurzel — mit einer
      // Nutzlast, die dort niemand lesen kann.
      expect(kDockFensterArgument, isNot(kBlitzFensterArgument));
      expect(kDockFensterArgument.startsWith(kBlitzFensterArgument), isFalse);
      expect(kBlitzFensterArgument.startsWith(kDockFensterArgument), isFalse);
    });

    test('main() erkennt die Leiste an einer EIGENEN Prüfung', () {
      // ⚠️ Genau EIN Zweig darf Auffangzweig sein, und in ihn darf nichts
      // fallen, was er nicht meint. Geprüft wird deshalb, dass die Leiste
      // ihre eigene Präfixprüfung hat — nicht, in welcher Reihenfolge die
      // beiden Zweige stehen.
      //
      // ⚠️ Die erste Fassung dieses Tests verlangte die Reihenfolge
      // („dock vor blitz") und wurde bei der Gegenprobe rot an einer
      // Umstellung, die vollkommen richtig war: Blitz zuerst zu prüfen ist
      // erlaubt, SOLANGE er dabei ebenfalls eine eigene Prüfung hat. Ein
      // Test, der eine korrekte Fassung ablehnt, wird beim nächsten Umbau
      // gelockert und schützt danach gar nichts mehr.
      final s = quelle('lib/main.dart');
      expect(s, contains('dockFensterStarten('),
          reason: 'Leiste wird in main() nicht gestartet');

      final dockGeprueft =
          s.contains("startsWith('\$kDockFensterArgument:')");
      final blitzGeprueft =
          s.contains("startsWith('\$kBlitzFensterArgument:')");
      expect(dockGeprueft || blitzGeprueft, isTrue,
          reason: 'Kein Nebenfenster wird an seinem Präfix erkannt — '
              'dann bekommt der Auffangzweig alles');

      // Und die Erkennung selbst muss beide Präfixe kennen, sonst kommt ein
      // Fenster gar nicht erst bis zur Verzweigung.
      final erkennung = rumpfVon(s, 'Future<String?> _nebenfensterArgument(');
      expect(erkennung, contains('\$kDockFensterArgument:'),
          reason: 'Die Leiste wird gar nicht als Nebenfenster erkannt — '
              'ihr Fenster liefe dann in den Rumpf des Hauptfensters');
      expect(erkennung, contains('\$kBlitzFensterArgument:'));
    });
  });

  group('Alle drei Bereiche sind überall bedient', () {
    final leiste = quelle('lib/screens/dock_fenster_app.dart');
    final dashboard = quelle('lib/screens/dashboard_screen.dart');

    test('die Leiste kennt Symbol, Titel und Leertext je Bereich', () {
      // Ein fehlender Zweig ist hier kein Fehler: das Symbol würde zum
      // leeren Kreis, die Überschrift zum rohen Schlüssel („termine").
      for (final b in DockBereich.alle) {
        expect(leiste, contains('DockBereich.$b =>'),
            reason: 'Bereich $b fehlt in der Leiste');
      }
      // Jeder Bereich muss in allen DREI Tabellen stehen.
      for (final b in DockBereich.alle) {
        expect('DockBereich.$b =>'.allMatches(leiste).length, greaterThanOrEqualTo(3),
            reason: 'Bereich $b steht nicht in allen drei Tabellen '
                '(_ikone, _titel, _leerText)');
      }
    });

    test('das Dashboard liefert Daten und springt für jeden Bereich', () {
      // Ohne Zweig in `_dockDaten` bleibt die Liste leer — und das sieht auf
      // dem Schirm aus wie „keine Mitglieder", nicht wie ein Fehler.
      for (final b in DockBereich.alle) {
        expect('case DockBereich.$b:'.allMatches(dashboard).length,
            greaterThanOrEqualTo(2),
            reason: 'Bereich $b fehlt in _dockDaten oder _dockOeffnen');
      }
    });
  });

  group('Fenstergeometrie — die Reihenfolgen, an denen es schon hing', () {
    final s = quelle('lib/screens/dock_fenster_app.dart');

    String rumpf(String signatur) => rumpfVon(s, signatur);

    test('erst setSize, dann setAlignment', () {
      // ⚠️ `setAlignment` liest intern die AKTUELLE Grösse und rechnet daraus
      // die Position. Vor dem Verkleinern gerufen, rechnet es mit dem alten,
      // breiteren Fenster — die Leiste rutschte bei jedem Zuklappen vom Rand
      // weg statt bündig zu bleiben.
      //
      // ⚠️ OHNE KOMMENTARE, und das hat sich sofort bewährt: die Begründung
      // im Quelltext nennt `setAlignment` eine Zeile VOR dem `setSize`, das
      // sie erklärt. Der Test wurde dadurch rot, obwohl der Code stimmte.
      final r = ohneKommentare(rumpf('Future<void> _fensterAnpassen('));
      expect(r.indexOf('setSize'), isNot(-1));
      expect(r.indexOf('setAlignment'), isNot(-1));
      expect(r.indexOf('setSize'), lessThan(r.indexOf('setAlignment')));
    });

    test('beim Start kommt show() VOR setSize', () {
      // ⚠️ `desktop_multi_window` ruft beim Erzeugen
      // `gtk_window_set_default_size(window, 1280, 720)`. Mit `hiddenAtLaunch`
      // wird das Fenster nur realisiert, nicht abgebildet — GTK überschreibt
      // beim Abbilden alles, was vorher gesetzt wurde. Beim Blitz-Fenster
      // stand deshalb 1280×720 auf dem Schirm; hier wäre es eine
      // bildschirmfüllende Leiste.
      final r = ohneKommentare(rumpf('Future<void> dockFensterStarten('));
      final show = r.indexOf('windowManager.show()');
      final size = r.indexOf('windowManager.setSize(');
      expect(show, isNot(-1));
      expect(size, isNot(-1));
      expect(show, lessThan(size));
    });

    test('kein setResizable(false)', () {
      // GTK ignoriert `gtk_window_resize` auf einem nicht veränderbaren
      // Fenster — die Leiste bliebe für immer bei der ersten Grösse und
      // liesse sich nie ausklappen.
      //
      // ⚠️ OHNE KOMMENTARE geprüft. Die erste Fassung suchte im ganzen Text
      // und schlug an der Warnung an, die im Quelltext genau davor warnt —
      // ein Test, der die Begründung der Regel für einen Verstoss gegen sie
      // hält, wird beim nächsten Mal entnervt gelöscht.
      expect(ohneKommentare(s), isNot(contains('setResizable(false)')));
    });

    test('die Leiste stiehlt den Eingabefokus nicht', () {
      // Anders als der Blitz, wo genau das gewollt ist: die Leiste darf nicht
      // das Feld übernehmen, in dem gerade getippt wird.
      expect(ohneKommentare(rumpf('Future<void> dockFensterStarten(')),
          isNot(contains('windowManager.focus()')));
    });
  });

  group('Ein Klick muss WIRKLICH ankommen', () {
    // ⚠️ Die Rückmeldung, aus der diese Gruppe entstand: „degeaba apar
    // iconitele alea acolo daca nu sunt 100% functionale". Sie war berechtigt —
    // bei den Mitgliedern wurde die `id` der angetippten Zeile schlicht
    // weggeworfen, es öffnete sich nur der Reiter. Alle drei Fehlschläge hier
    // sind LAUTLOS: das Fenster kommt nach vorn, und dann geschieht nichts.
    final dashboard = quelle('lib/screens/dashboard_screen.dart');
    final termine = quelle('lib/screens/terminverwaltung_screen.dart');
    final chat = quelle('lib/widgets/admin_chat_dialog.dart');

    String sprung(String bereich) {
      final ganz = rumpfVon(dashboard, 'Future<void> _dockOeffnen(');
      final start = ganz.indexOf('case DockBereich.$bereich:');
      if (start < 0) throw StateError('Zweig fehlt: $bereich');
      final naechster = ganz.indexOf('case DockBereich.', start + 10);
      return ganz.substring(start, naechster < 0 ? ganz.length : naechster);
    }

    test('ein Mitglied öffnet seine Karte, nicht nur den Reiter', () {
      final z = ohneKommentare(sprung('mitglieder'));
      expect(z, contains('_showUserDetailsDialog'),
          reason: 'Die id der angetippten Zeile wird weggeworfen — es öffnet '
              'sich nur die Mitgliederverwaltung');
    });

    test('ein Termin reist MIT DATUM, sonst findet ihn nur diese Woche', () {
      final z = ohneKommentare(sprung('termine'));
      expect(z, contains('_pendingFocusTerminId'));
      expect(z, contains('_pendingFocusTerminDatum'),
          reason: 'Ohne Datum lädt der Terminbildschirm nur die laufende '
              'Woche; die Leiste zeigt 14 Tage');
    });

    test('der Terminbildschirm stellt auf die Woche des Ziels', () {
      final i = ohneKommentare(rumpfVon(termine, 'void initState()'));
      expect(i, contains('initialFocusTerminDate'));
      expect(i, contains('_currentWeekStart'));
    });

    test('… auch wenn er schon offen steht', () {
      // ⚠️ `initState` läuft genau einmal. Ohne `didUpdateWidget` bleibt ein
      // zweiter Sprung wirkungslos — und zwar schon für die Sprünge aus
      // Benachrichtigungen, lange vor der Leiste.
      final d = ohneKommentare(
          rumpfVon(termine, 'void didUpdateWidget(TerminverwaltungScreen'));
      expect(d, contains('_pendingFocusTerminId'));
      expect(d, contains('_loadTermine'));
    });

    test('eine zweite Unterhaltung erreicht den schon offenen Chat', () {
      final z = ohneKommentare(sprung('chat'));
      expect(z, contains('_isAdminChatOpen'));
      expect(z, contains('AdminChatDialog.wunschUnterhaltung'),
          reason: 'Bei offenem Dialog greift initialConversationId nicht — '
              'ohne den Wunsch passiert gar nichts');
    });

    test('der Chat nimmt den Wunsch an und gibt ihn wieder ab', () {
      final o = ohneKommentare(chat);
      expect(o, contains('addListener(_wunschAnnehmen)'),
          reason: 'Niemand hört auf den Wunsch');
      expect(o, contains('removeListener(_wunschAnnehmen)'),
          reason: 'Zuhörer überlebt den Dialog');
      // ⚠️ Der Wunsch muss beim Schliessen geleert werden, sonst springt der
      // Chat beim nächsten Öffnen sofort in eine Unterhaltung, die vor
      // Minuten einmal angetippt wurde.
      final d = ohneKommentare(rumpfVon(chat, 'void dispose()'));
      expect(d, contains('wunschUnterhaltung.value = null'));
    });
  });

  group('Abmelden', () {
    test('die Leiste wird entwaffnet, BEVOR die Token fallen', () {
      // ⚠️ Sie steht über allen Fenstern und überlebt das Dashboard. Fragte
      // sie danach noch einmal, lieferte sie die Namen des abgemeldeten
      // Kontos an jemanden, der gerade nicht mehr angemeldet ist.
      final s = quelle('lib/screens/dashboard_screen.dart');
      final start = s.indexOf('Future<void> _logout() async {');
      expect(start, isNot(-1));
      final ab = s.indexOf('DockFensterSteuerung.instanz.abmelden()', start);
      final logout = s.indexOf('_apiService.logout()', start);
      expect(ab, isNot(-1), reason: '_logout entwaffnet die Leiste nicht');
      expect(logout, isNot(-1));
      expect(ab, lessThan(logout));
    });
  });
}
