import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/bussgeld_vorfall_details_dialog.dart';

/// Der Vorgang: vier Reiter, und die Wörter darin müssen stimmen.
void main() {
  final quelle = File('lib/widgets/bussgeld_vorfall_details_dialog.dart').readAsStringSync();
  final stelle = File('lib/widgets/behorde_bussgeldstelle.dart').readAsStringSync();

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

  group('Der Weg über das "+"', () {
    test('die Schnellanlage fragt nur nach dem Aktenzeichen und den Daten', () {
      // Wer ein Schreiben in der Hand hält, hat zuerst das Aktenzeichen.
      // Ein Formular mit zwanzig Feldern führt dazu, dass der Vorgang gar
      // nicht erst angelegt wird.
      expect(stelle.contains('_vorfallSchnellAnlegen'), isTrue);
      expect(stelle.contains("Key('bg_schnell_az')"), isTrue);
      for (final feld in ['betrag_geldbusse', 'tatort_strasse', 'punkte', 'kennzeichen']) {
        expect(stelle.contains("'$feld':"), isFalse,
            reason: 'Die Schnellanlage soll nicht nach $feld fragen');
      }
    });

    test('nach dem Anlegen öffnet sich der Vorgang', () {
      expect(stelle.contains('_detailsOeffnen(r[\'id\'] as int)'), isTrue);
    });

    test('ein Tippen auf die Zeile führt in den Vorgang, nicht ins Formular', () {
      expect(stelle.contains("onTap: () => _detailsOeffnen(v['id'] as int)"), isTrue);
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
    'add_korrespondenz', 'delete_korrespondenz', 'save_einspruch', 'delete_einspruch',
    // bussgeld_vollmacht_manage.php
    'create', 'revoke', 'add_versand',
    // user_bussgeldstelle.php
    'save_stelle', 'save_vorfall', 'delete_vorfall',
    // bussgeld_vorfall_dok.php
    'delete',
  };

  test('jede Server-Aktion wird vom Client auch benutzt', () {
    final quellen = [
      File('lib/widgets/bussgeld_vorfall_details_dialog.dart').readAsStringSync(),
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

    test('die heruntergeladene Datei landet nicht in /tmp', () {
      // Dort läge ein Bußgeldbescheid für jedes andere Programm lesbar.
      expect(dialog.contains('getApplicationDocumentsDirectory'), isTrue);
      expect(dialog.contains("Directory.systemTemp"), isFalse);
    });
  });

  group('Vorgänge stehen in der Karte der Stelle', () {
    test('es gibt keinen zweiten Reiter mehr daneben', () {
      // ⚠️ Der User hat ausdrücklich gesagt: beim Klick auf die zuständige
      // Stelle sollen die Vorgänge DORT erscheinen, nicht in einem Reiter
      // daneben. Ein TabController hier wäre ein Rückfall.
      expect(stelle.contains('TabController'), isFalse);
      expect(stelle.contains('TabBarView'), isFalse);
      expect(stelle.contains('SingleTickerProviderStateMixin'), isFalse);
    });

    test('die Vorgänge hängen in der Stellen-Karte', () {
      expect(stelle.contains('_vorgaengeImKarten()'), isTrue);
      expect(stelle.contains('_vorfaelleKarte'), isFalse);
    });

    test('das Plus sitzt bei den Vorgängen', () {
      expect(stelle.contains("Key('bg_neuer_vorfall')"), isTrue);
      expect(stelle.contains('onPressed: _vorfallSchnellAnlegen'), isTrue);
    });
  });
}

/// Die Zuständigkeit speichert sich selbst — es gibt keinen Knopf mehr.
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
