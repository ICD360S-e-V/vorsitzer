import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/bussgeld_korrespondenz_dialog.dart';
import 'package:icd360sev_vorsitzer/widgets/bussgeld_vorfall_details_dialog.dart';

/// Der Vorgang: vier Reiter, und die Wörter darin müssen stimmen.
void main() {
  final quelle = File('lib/widgets/bussgeld_vorfall_details_dialog.dart').readAsStringSync();

  group('Ergebnisse des Einspruchs', () {
    test('jede Möglichkeit hat einen deutschen Text', () {
      for (final e in kEinspruchErgebnisse.entries) {
        expect(e.value.trim(), isNotEmpty, reason: '${e.key} ohne Beschriftung');
      }
    });

    test('Schlüssel decken sich mit dem ENUM der Datenbank', () {
      // ⚠️ Dieselbe Liste steht im ENUM bussgeld_einspruch.ergebnis. Laufen
      // sie auseinander, kürzt MariaDB einen unbekannten Wert stillschweigend
      // auf '' — das Ergebnis des Verfahrens wäre dann einfach weg.
      expect(kEinspruchErgebnisse.keys.toSet(), {
        'offen', 'abgeholfen', 'eingestellt', 'an_gericht', 'verworfen', 'zurueckgenommen',
      });
    });

    test('Rücknahme ist von "nie eingelegt" unterscheidbar', () {
      // Die Rücknahme lässt den Bescheid rechtskräftig werden. Sie darf
      // nicht dasselbe bedeuten wie "es gab keinen Einspruch".
      expect(kEinspruchErgebnisse.containsKey('zurueckgenommen'), isTrue);
      expect(kEinspruchErgebnisse['zurueckgenommen'], isNot(kEinspruchErgebnisse['offen']));
    });
  });

  group('Einspruch ist nicht Widerspruch', () {
    test('der Bildschirm sagt, wie der Rechtsbehelf wirklich heißt', () {
      // Der Reiter heißt "Widerspruch", weil er so gesucht wird. Das
      // Schreiben heißt Einspruch (§ 67 OWiG) und geht an die Behörde, nicht
      // ans Gericht. Steht das nicht auf dem Schirm, schreibt jemand
      // "Widerspruch" auf ein fristgebundenes Dokument.
      expect(quelle.contains('EINSPRUCH'), isTrue,
          reason: 'Der Hinweistext auf den richtigen Rechtsbehelf fehlt');
      expect(quelle.contains('§ 67 OWiG'), isTrue);
      expect(quelle.contains('nicht an das Gericht'), isTrue);
    });

    test('die Frist wird mit ihrer Grundlage genannt', () {
      expect(quelle.contains('§ 67 Abs. 1 OWiG'), isTrue);
      // Der Vorbehalt gehört dazu, sonst liest sich ein Rechenwert wie eine
      // Zusage.
      expect(quelle.contains('Feiertage sind nicht berücksichtigt'), isTrue);
    });

    test('bei versäumter Frist wird der Weg genannt, nicht nur der Fehler', () {
      // Eine rote Zeile "zu spät" hilft niemandem weiter.
      expect(quelle.contains('Wiedereinsetzung'), isTrue);
      expect(quelle.contains('§ 52 OWiG'), isTrue);
    });
  });

  group('Vollmacht', () {
    test('die Grenzen kommen vom Server, nicht aus einer zweiten Kopie', () {
      // ⚠️ Eine zweite Liste im Client liefe der auf dem PDF davon, und dann
      // verspricht der Bildschirm etwas anderes als das Blatt.
      expect(quelle.contains("_vmOptionen?['grenzen']"), isTrue);
      expect(quelle.contains('§ 2 Abs. 1 RDG'), isFalse,
          reason: 'Rechtstexte gehören auf den Server, nicht in den Client');
    });

    test('das PDF wird an der Magic Number erkannt, nicht am Statuscode', () {
      // Ein JSON-Fehler kommt ebenfalls mit HTTP 200 und würde sonst als
      // "PDF" durchgehen.
      expect(quelle.contains("== '%PDF'"), isTrue);
    });
  });

  group('Versand der Vollmacht', () {
    test('die Wege decken sich mit dem ENUM der Datenbank', () {
      // ⚠️ Dieselbe Liste steht im ENUM bussgeld_vollmacht_versand.weg.
      // Ein Wert daneben würde stillschweigend auf '' gekürzt — der Nachweis,
      // WIE die Vollmacht hinausging, wäre dann weg.
      expect(kVersandWege.keys.toSet(), {'post', 'fax', 'email', 'persoenlich', 'sonstige'});
    });

    test('der Versand wird auch angezeigt, nicht nur erfasst', () {
      // Eine Vollmacht, die im Ordner liegt, wirkt nicht — die Behörde muss
      // sie haben. Wer den Versand nur speichert und nie zeigt, hat die
      // Frage „ist sie schon dort?" nicht beantwortet.
      expect(quelle.contains("_liste(vm['versand'])"), isTrue);
      expect(quelle.contains('_versandVermerken'), isTrue);
    });
  });

  _abgleich();
  _anhaenge();
  _zustaendigkeit();
  _schreiben();
  _antwortAnlagen();

  group('Der Weg über das "+"', () {
    final manager = File('lib/widgets/bussgeld_vorgaenge_manager.dart').readAsStringSync();

    test('die Schnellanlage fragt nur nach dem Aktenzeichen und den Daten', () {
      // Wer ein Schreiben in der Hand hält, hat zuerst das Aktenzeichen.
      // Ein Formular mit zwanzig Feldern führt dazu, dass der Vorgang gar
      // nicht erst angelegt wird.
      expect(manager.contains('_schnellAnlegen'), isTrue);
      expect(manager.contains("Key('bg_schnell_az')"), isTrue);
      for (final feld in ['betrag_geldbusse', 'tatort_strasse', 'punkte']) {
        expect(manager.contains("'$feld':"), isFalse,
            reason: 'Die Schnellanlage soll nicht nach $feld fragen');
      }
    });

    test('nach dem Anlegen öffnet sich der Vorgang', () {
      expect(manager.contains("await _oeffnen({'id': r['id']})"), isTrue);
    });

    test('ein Tippen auf die Zeile führt in den Vorgang', () {
      expect(manager.contains('onTap: () => _oeffnen(v)'), isTrue);
    });
  });
}

/// ⚠️ Serverseitige Aktionen, die kein Client aufruft, sind totes Gewicht —
/// und man merkt es nicht, weil nichts rot wird. `add_versand` war genau das,
/// bis dieser Abgleich es gezeigt hat.
///
/// Die Liste der Server-Aktionen steht hier als Literal, weil das PHP in
/// keinem Repo liegt. Sie ist damit zugleich die einzige Stelle, an der ein
/// Auseinanderlaufen von Client und Server überhaupt auffallen kann —
/// dieselbe Rolle wie `_serverWhitelist` bei den Chat-Reaktionen.
void _abgleich() {
  const serverAktionen = {
    // bussgeld_vorfall_details.php
    'add_korrespondenz', 'update_korrespondenz', 'delete_korrespondenz',
    'save_einspruch', 'delete_einspruch',
    // bussgeld_vollmacht_manage.php
    'create', 'revoke', 'add_versand',
    // user_bussgeldstelle.php
    'save_stelle', 'save_vorfall', 'delete_vorfall',
    // bussgeld_vorfall_dok.php
    'delete',
  };

  test('jede Server-Aktion wird vom Client auch benutzt', () {
    // ⚠️ Jede Datei, die Aktionen schickt, gehört hier hinein. Fehlt eine,
    // meldet der Abgleich totes Gewicht, das gar keines ist — und beim
    // nächsten Mal glaubt ihm niemand mehr.
    final quellen = [
      File('lib/widgets/bussgeld_vorfall_details_dialog.dart').readAsStringSync(),
      File('lib/widgets/bussgeld_korrespondenz_dialog.dart').readAsStringSync(),
      File('lib/widgets/bussgeld_vorgaenge_manager.dart').readAsStringSync(),
      File('lib/widgets/behorde_bussgeldstelle.dart').readAsStringSync(),
      File('lib/services/api_service.dart').readAsStringSync(),
    ].join('\n');
    for (final a in serverAktionen) {
      expect(quellen.contains("'$a'"), isTrue,
          reason: 'Der Server kennt "$a", aber kein Client ruft es auf');
    }
  });
}

/// Anhänge: der Teil, den der User als fehlend gemeldet hat.
void _anhaenge() {
  final dialog = File('lib/widgets/bussgeld_vorfall_details_dialog.dart').readAsStringSync();
  final stelle = File('lib/widgets/behorde_bussgeldstelle.dart').readAsStringSync();

  group('PDF am Schreiben', () {
    test('jede Korrespondenz-Zeile hat einen Knopf zum Anhängen', () {
      expect(dialog.contains('_anhangHochladen'), isTrue);
      expect(dialog.contains('Icons.attach_file'), isTrue);
    });

    test('die Anhänge stehen unter ihrem Schreiben, nicht in einer Extraliste', () {
      // Der Bescheid, sein Messprotokoll und das Lichtbild gehören zusammen.
      expect(dialog.contains("_liste(k['anhaenge'])"), isTrue);
    });

    test('das Ergebnis des Uploads wird ausgewertet, nicht weggeworfen', () {
      // ⚠️ Genau das fehlte bei den fünf *_attachment.php-Pfaden: dort
      // verschwand ein HTTP 500 wortlos und die leere Liste sah aus wie
      // "ich habe wohl nichts ausgewählt".
      expect(dialog.contains("r['success'] == true"), isTrue);
      expect(dialog.contains('Nicht hochgeladen'), isTrue);
      expect(dialog.contains('fehlerTexte'), isTrue);
    });

    test('gewählt wird über den Helfer des Projekts, nicht über FilePicker direkt', () {
      // Auf macOS geht FilePickerHelper einen eigenen Weg; die Datei-Knöpfe
      // der App sind an der direkten Verwendung schon einmal gescheitert.
      expect(dialog.contains('FilePickerHelper.pickFiles'), isTrue);
      expect(dialog.contains('FilePicker.platform'), isFalse);
    });

    test('die Datei berührt die Platte überhaupt nicht', () {
      // ⚠️ Dieser Test forderte zuerst das Dokumentenverzeichnis der App —
      // besser als /tmp, aber immer noch entschlüsselt auf der Platte. Der
      // User hat zu Recht darauf bestanden, dass die Anzeige im Programm
      // und aus dem Arbeitsspeicher geschieht.
      expect(dialog.contains('getApplicationDocumentsDirectory'), isFalse);
      expect(dialog.contains('Directory.systemTemp'), isFalse);
      expect(dialog.contains('writeAsBytes'), isFalse);
      expect(dialog.contains('FileViewerDialog.showFromBytes'), isTrue);
    });
  });

  group('Die Karte öffnet den Vorgangs-Manager', () {
    final manager = File('lib/widgets/bussgeld_vorgaenge_manager.dart').readAsStringSync();

    test('kein zweiter Reiter daneben', () {
      // Erster Anlauf: Reiter neben der Stelle. Falsch.
      expect(stelle.contains('TabController'), isFalse);
      expect(stelle.contains('TabBarView'), isFalse);
    });

    test('und auch keine Liste unter der Karte', () {
      // ⚠️ Zweiter Anlauf: die Liste unter die Karte gehängt. Auch falsch —
      // ein Tipp auf die Karte soll den MANAGER öffnen. Unter der Karte
      // wächst die Liste mit jedem Schreiben, bis die Anschrift der Stelle
      // nach unten aus dem Bild wandert.
      expect(stelle.contains('_vorgaengeImKarten'), isFalse);
      expect(stelle.contains('_vorfallZeile'), isFalse,
          reason: 'die Zeilendarstellung gehört in den Manager');
      expect(stelle.contains('_vorgaengeOeffnen'), isTrue);
      expect(stelle.contains('BussgeldVorgaengeManager'), isTrue);
    });

    test('die Karte sagt, was dahinter liegt und was drängt', () {
      // Sonst müsste man den Manager öffnen, um zu erfahren, dass man ihn
      // öffnen sollte.
      expect(stelle.contains('Vorgänge verwalten'), isTrue);
      expect(stelle.contains('Frist'), isTrue);
    });

    test('🔴 jeder Vorgang gehört zu der Stelle, bei der er angelegt wurde', () {
      // Der Manager einer Stelle zeigt ihre Vorgänge — nicht alles, was das
      // Mitglied je erfasst hat.
      expect(manager.contains('_gehoertZurStelle'), isTrue);
      expect(manager.contains("'stelle_id': _stelleId"), isTrue);
    });

    test('Vorgänge anderer Stellen werden nicht versteckt', () {
      // ⚠️ Wer die zuständige Stelle wechselt, verlöre sonst den Zugang zu
      // allem, was vorher lief. Unerreichbare Daten sind schlimmer als eine
      // Zeile zu viel.
      expect(manager.contains('_Filter.andere'), isTrue);
      expect(manager.contains('Andere Stelle'), isTrue);
    });

    test('ohne zuständige Stelle wird kein Vorgang angelegt', () {
      expect(manager.contains('ein Vorgang gehört immer zu einer Behörde'), isTrue);
    });

    test('die Liste lässt sich durchsuchen und filtern', () {
      // Eine Akte, keine Aufzählung.
      expect(manager.contains("Key('bg_mgr_suche')"), isTrue);
      for (final f in ['alle', 'offen', 'frist', 'erledigt']) {
        expect(manager.contains('_Filter.$f'), isTrue, reason: 'Filter $f fehlt');
      }
    });

    test('„Frist läuft" zählt nur, was noch offen ist', () {
      // Ein bezahlter Bescheid mit abgelaufener Frist ließe sonst dauerhaft
      // eine rote Zahl stehen, die niemand mehr wegbekommt.
      expect(manager.contains('if (!_istOffen(v)) return false;'), isTrue);
    });
  });
}

void _zustaendigkeit() {
  final stelle = File('lib/widgets/behorde_bussgeldstelle.dart').readAsStringSync();

  group('Zuständige Stelle ohne Speichern-Knopf', () {
    test('der Knopf ist weg', () {
      // ⚠️ Er war die Folge eines Entwurfsfehlers: das Feld war Suchschlitz
      // UND gespeicherter Name zugleich, also musste irgendwer entscheiden,
      // wann aus einem Suchbegriff eine Zuständigkeit wird. Wer eine Stelle
      // antippt, hat das entschieden.
      expect(stelle.contains("Key('bg_stelle_speichern')"), isFalse);
      expect(stelle.contains('_stelleSpeichern'), isFalse);
    });

    test('Antippen eines Treffers speichert sofort', () {
      expect(stelle.contains('_stelleUebernehmen'), isTrue);
      expect(stelle.contains('onTap: schonGesetzt ? null : () => _stelleUebernehmen(s)'), isTrue);
    });

    test('eine bereits gesetzte Stelle wird im Treffer markiert', () {
      // Sonst tippt man sie ein zweites Mal an und weiß nicht, ob etwas
      // geschehen ist.
      expect(stelle.contains('schonGesetzt'), isTrue);
    });

    test('ein Fehlschlag beim automatischen Speichern wird gezeigt', () {
      // ⚠️ Ohne Knopf gibt es keinen zweiten Versuch, den jemand von sich
      // aus unternähme — ein stiller Fehler bliebe für immer stumm.
      expect(stelle.contains('Nicht gespeichert:'), isTrue);
    });

    test('Freitext bleibt möglich, aber nur mit eigenem Tipper', () {
      // Der Katalog hat erst drei Einträge. Automatisches Speichern beim
      // Tippen würde jeden halben Suchbegriff zur Zuständigkeit machen.
      expect(stelle.contains("Key('bg_stelle_freitext')"), isTrue);
      expect(stelle.contains('_stelleUebernehmen(null)'), isTrue);
    });

    test('es gibt einen Weg zurück', () {
      // Ohne Knopf ließe sich eine gesetzte Zuständigkeit sonst nur noch
      // überschreiben, nie aufheben.
      expect(stelle.contains("Key('bg_stelle_entfernen')"), isTrue);
      expect(stelle.contains('_stelleEntfernen'), isTrue);
    });

    test('beim Entfernen wird auf die bleibenden Vorgänge hingewiesen', () {
      // Sie hängen am Mitglied, nicht an der Auswahl.
      expect(stelle.contains('bleiben bestehen'), isTrue);
    });
  });
}

/// Das einzelne Schreiben: Details, Unterlagen, Antwort.
void _schreiben() {
  final dialog = File('lib/widgets/bussgeld_korrespondenz_dialog.dart').readAsStringSync();
  final vorgang = File('lib/widgets/bussgeld_vorfall_details_dialog.dart').readAsStringSync();

  group('Anhänge werden IM PROGRAMM gezeigt', () {
    test('kein fremdes Programm, keine Datei auf der Platte', () {
      // 🔴 Ein Bußgeldbescheid trägt Name, Anschrift, Kennzeichen und
      // Tatvorwurf. Auf der Platte läge er entschlüsselt, und ein fremder
      // Betrachter behielte ihn in Verlauf, Zwischenspeicher und womöglich
      // Wolkensicherung. Was die App danach löscht, ist längst kopiert.
      for (final quelle in [dialog, vorgang]) {
        expect(quelle.contains('OpenFilex'), isFalse,
            reason: 'Anhänge dürfen nicht an ein fremdes Programm gehen');
        expect(quelle.contains('getApplicationDocumentsDirectory'), isFalse,
            reason: 'Anhänge dürfen nicht auf die Platte geschrieben werden');
        expect(quelle.contains('writeAsBytes'), isFalse);
      }
    });

    test('gezeigt wird aus den Bytes', () {
      expect(dialog.contains('FileViewerDialog.showFromBytes'), isTrue);
      expect(vorgang.contains('FileViewerDialog.showFromBytes'), isTrue);
    });

    test('ein nicht anzeigbarer Typ fällt auf', () {
      expect(dialog.contains('lässt sich hier nicht anzeigen'), isTrue);
    });
  });

  group('Ein Schreiben hat drei Reiter', () {
    test('Details, Unterlagen, Antwort', () {
      expect(dialog.contains("text: 'Details'"), isTrue);
      expect(dialog.contains('Unterlagen'), isTrue);
      expect(dialog.contains('Antwort'), isTrue);
      expect(dialog.contains('TabController(length: 3'), isTrue);
    });

    test('ein Tippen auf die Zeile führt hinein', () {
      expect(vorgang.contains('_schreibenOeffnen'), isTrue);
      expect(vorgang.contains('onTap: () => _schreibenOeffnen(k)'), isTrue);
    });

    test('ein unbeantworteter Eingang ist in der Liste zu erkennen', () {
      expect(vorgang.contains('noch nicht beantwortet'), isTrue);
    });
  });

  group('Antwort', () {
    test('die Wege decken sich mit dem ENUM der Datenbank', () {
      // ⚠️ Dieselbe Liste steht im ENUM bussgeld_vorfall_korrespondenz.weg.
      expect(kKorrWege.keys.toSet(),
          {'post', 'fax', 'email', 'persoenlich', 'elektronisch', 'sonstige'});
    });

    test('eine Antwort ist ein Ausgang, kein Textfeld am Eingang', () {
      // Sie hat eigenes Datum, eigenen Weg und eigene Anlagen. Als Feld am
      // Eingang wäre all das verloren.
      expect(dialog.contains("'richtung': 'ausgang'"), isTrue);
      expect(dialog.contains("'antwort_auf_id': _s['id']"), isTrue);
    });

    test('🔴 der Schirm sagt, dass eine Antwort KEINE Frist wahrt', () {
      // Wer das nicht liest, hält ein freundliches Schreiben für einen
      // Einspruch — und die Frist läuft ab.
      expect(dialog.contains('kein Rechtsbehelf'), isTrue);
      expect(dialog.contains('§ 67 OWiG'), isTrue);
    });

    test('auf einen Ausgang wird nicht geantwortet', () {
      expect(dialog.contains('Dies ist ein Ausgang'), isTrue);
    });
  });
}

/// Anlagen an der Antwort — und der Knopf, der verschwinden muss.
void _antwortAnlagen() {
  final dialog = File('lib/widgets/bussgeld_korrespondenz_dialog.dart').readAsStringSync();

  group('Antwort mit Anlagen', () {
    test('beim Verfassen lassen sich Dateien auswählen', () {
      // Das Schreiben selbst gehört zur Antwort, nicht in einen zweiten
      // Arbeitsgang. Wer gerade scannt, hängt es gleich an.
      expect(dialog.contains("Key('bg_antwort_datei')"), isTrue);
      expect(dialog.contains('FilePickerHelper.pickFiles'), isTrue);
    });

    test('PDF, JPG, JPEG und PNG sind erlaubt', () {
      for (final e in ['pdf', 'jpg', 'jpeg', 'png']) {
        expect(dialog.contains("'$e'"), isTrue, reason: '$e fehlt in den erlaubten Endungen');
      }
    });

    test('eine bestehende Antwort nimmt weiter Anlagen an', () {
      // Nachreichen ist kein zweites Antworten.
      expect(dialog.contains("Key('bg_antwort_anlage')"), isTrue);
    });

    test('🔴 ein Fehlschlag beim Hochladen sieht nicht aus wie ein Fehlschlag des Ganzen', () {
      // Die Antwort steht dann bereits. Wer eine gemeinsame Fehlermeldung
      // bekäme, legte sie ein zweites Mal an — und in einer Behördenakte ist
      // eine doppelte Antwort schlimmer als gar keine.
      expect(dialog.contains('Anlagen nicht vollständig'), isTrue);
    });
  });

  group('Der Antwort-Knopf verschwindet, wenn geantwortet wurde', () {
    test('er hängt an "_antworten.isEmpty"', () {
      expect(dialog.contains('if (_antworten.isEmpty)'), isTrue);
      // Ein „Weitere Antwort erfassen" lädt dazu ein, dieselbe Sache zweimal
      // zu schreiben.
      expect(dialog.contains('Weitere Antwort'), isFalse);
    });

    test('stattdessen steht da, dass geantwortet wurde', () {
      expect(dialog.contains('wurde geantwortet'), isTrue);
    });
  });
}
