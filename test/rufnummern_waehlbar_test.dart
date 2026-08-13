import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bleibt jede angezeigte Rufnummer in der App wählbar?
///
/// ⚠️ WARUM DIESER TEST DIE QUELLTEXTE LIEST STATT WIDGETS ZU BAUEN
/// Die Rufnummern stehen über ~50 Bildschirme verteilt, jeder mit eigenem
/// Zeilen-Helfer (`_infoRow`, `_detailRow`, `_kv`, `_pdInfoRow` …) — die
/// Behörden- und Arzt-Widgets sind bewusst entkoppelte Kopien. Ein Widget-Test
/// müsste jeden einzeln aufbauen, mit API-Doppel und Zustand. Ein Durchgang
/// durch den Quelltext prüft dagegen die eine Eigenschaft, auf die es ankommt:
/// steht hinter einem Telefon-Icon ein Wert, muss die Zeile wählbar sein.
///
/// Gefunden hat dieser Durchgang beim ersten Lauf vier Stellen, an denen eine
/// Rufnummer nur dastand: das Telefon und das Termin-Telefon des Finanzamts in
/// der Vereinverwaltung, die Nummer des Pflegedienstes in der Pflegegrad-Akte
/// und die des Sanitätshauses im Rezeptabschnitt.
///
/// Derselbe Aufbau wie die Notruf-Prüfung in `sipgate_nummer_test.dart`.
void main() {
  /// Icons, hinter denen in diesem Projekt eine Rufnummer stehen kann.
  /// Muss zu `_phoneIcons` in `lib/widgets/phone_link.dart` passen.
  const telefonIkonen = [
    'Icons.phone',
    'Icons.phone_in_talk',
    'Icons.phone_callback',
    'Icons.phone_forwarded',
    'Icons.phone_android',
    'Icons.phone_iphone',
    'Icons.local_phone',
    'Icons.contact_phone',
    'Icons.call',
    'Icons.smartphone',
    'Icons.support_agent',
  ];

  /// Was einen Helfer wählbar macht — irgendeines davon muss im Rumpf stehen.
  const waehlbar = [
    'phoneAwareText',
    'PhoneTapTarget',
    'PhoneText(',
    'PhoneCallButton',
  ];

  /// Stellen, an denen hinter einem Telefon-Icon KEINE Rufnummer steht.
  ///
  /// ⚠️ Jede Ausnahme braucht einen Grund. Wer hier etwas einträgt, um den Test
  /// grün zu bekommen, macht genau den Fehler rückgängig, den er verhindern
  /// soll — eine tote Rufnummer sieht auf dem Schirm aus wie eine lebende.
  const ausnahmen = <String, String>{
    'lib/screens/vr_bank_screen.dart:_infoRow':
        'Wert ist „Telefon, Filiale, Online" — eine Aufzählung der Kanäle',
    'lib/widgets/arbeitgeber_bewerbungsuebersicht.dart:_legalRow':
        'Wert ist der Name des Ansprechpartners, nicht seine Nummer',
    'lib/widgets/behorde_tab_content.dart:_buildBehoerdeSectionHeader':
        'Abschnittsüberschrift, sie trägt überhaupt keinen Wert',
    'lib/widgets/behorde_tab_content.dart:_terminInfoRow':
        'Wert ist der Name des Arbeitsvermittlers',
    'lib/widgets/login_approval_dialog.dart:_infoRow':
        'Wert ist der Gerätename des anfragenden Geräts',
    'lib/widgets/mitglieder_device.dart:_sectionHeader':
        'Abschnittsüberschrift „Registrierte Geräte"',
    'lib/widgets/sipgate_anruf_overlay.dart:_rundKnopf':
        'Das ist der Annehmen-Knopf selbst, kein angezeigter Wert',
    'lib/widgets/ticket_details_dialog.dart:_buildInfoRow':
        'Wert ist der Name des bearbeitenden Admins',
  };

  final ikonenAlternative = telefonIkonen.map(RegExp.escape).join('|');
  final aufruf = RegExp(r'(_\w+)\(\s*(?:' + ikonenAlternative + r')\s*,([^\n]{0,120})');

  List<File> quellen() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('jede Zeile mit Telefon-Icon ist wählbar oder begründet ausgenommen', () {
    final offen = <String>[];
    final unbenutzt = ausnahmen.keys.toSet();

    for (final datei in quellen()) {
      final quelle = datei.readAsStringSync();
      for (final treffer in aufruf.allMatches(quelle)) {
        final helfer = treffer.group(1)!;
        final rest = treffer.group(2)!;

        // Der Helfer wird in derselben Datei definiert? Sonst nicht prüfbar.
        final definition =
            RegExp('Widget\\s+${RegExp.escape(helfer)}\\s*\\(').firstMatch(quelle);
        if (definition == null) continue;

        final ende = definition.end + 3000;
        final rumpf =
            quelle.substring(definition.end, ende > quelle.length ? quelle.length : ende);
        if (waehlbar.any(rumpf.contains)) continue;

        // ⚠️ Der Wählweg muss nicht im Helfer stecken — er kann an der
        // Aufrufstelle stehen. Zwei Bauarten kommen vor, und beide sind in
        // Ordnung:
        //   `_kontaktZeile(Icons.phone, PhoneText(…))`  — der Helfer nimmt ein
        //       fertiges Widget entgegen (Visitenkarte)
        //   `_kontaktRow(Icons.phone, …, onTap: … PhoneCallService.call(…))`
        //       — der Aufrufer reicht die Handlung durch (Vesperkirche)
        // Die erste Fassung dieses Tests kannte nur den Helfer-Rumpf und hat
        // deshalb die Visitenkarte fälschlich gemeldet — auf dem Runner, nicht
        // hier, weil origin/main sie inzwischen umgebaut hatte.
        final nachAufruf = treffer.end + 300;
        final umfeld = quelle.substring(
            treffer.end, nachAufruf > quelle.length ? quelle.length : nachAufruf);
        if (rest.contains('onTap:') ||
            umfeld.contains('PhoneCallService.call') ||
            waehlbar.any(umfeld.contains)) {
          continue;
        }

        final schluessel = '${datei.path}:$helfer';
        if (ausnahmen.containsKey(schluessel)) {
          unbenutzt.remove(schluessel);
          continue;
        }
        final zeile = '\n'.allMatches(quelle.substring(0, treffer.start)).length + 1;
        offen.add('$schluessel (Zeile $zeile) — $rest');
      }
    }

    expect(
      offen,
      isEmpty,
      reason: 'Hinter einem Telefon-Icon steht ein Wert, den man nicht anrufen '
          'kann. Entweder den Zeilen-Helfer auf phoneAwareText(icon, wert) '
          'umstellen — der entscheidet selbst und lässt Nicht-Nummern in Ruhe '
          '— oder die Stelle mit Grund in `ausnahmen` eintragen:\n'
          '${offen.join('\n')}',
    );

    expect(
      unbenutzt,
      isEmpty,
      reason: 'Diese Ausnahmen greifen nicht mehr — die Stelle wurde umgebaut '
          'oder entfernt. Bitte aus der Liste nehmen, sonst deckt sie '
          'irgendwann etwas anderes zu: $unbenutzt',
    );
  });

  /// Zweiter Durchgang: Rufnummern, die ohne Icon einfach als Text dastehen.
  ///
  /// Der häufigste Ort dafür sind Auswahllisten — „Amt suchen", „Praxis
  /// suchen", „Apotheke suchen". Dort darf die Nummer selbst KEINE Wählfläche
  /// sein: der Tipp auf die Zeile muss auswählen, sonst stiehlt ein
  /// Wähl-InkWell den Griff, den man eigentlich machen wollte. Stattdessen
  /// gehört ein `PhoneCallButton` ins `trailing` der Zeile — auswählen bleibt
  /// auswählen, anrufen bekommt eine eigene Fläche.
  test('eine angezeigte Rufnummer hat immer einen Weg zum Anruf', () {
    /// Ein Kartenzugriff auf ein Rufnummernfeld, in einen Text gesetzt.
    /// ⚠️ Bewusst NUR Kartenzugriffe: `Text('Telefon')` ist eine Beschriftung
    /// in einem Auswahlmenü, keine Nummer — die dürfen hier nicht auftauchen,
    /// sonst füllt sich die Ausnahmeliste mit Nicht-Problemen und deckt dabei
    /// irgendwann ein echtes zu.
    final anzeige = RegExp(
        r"""Text\([^\n]{0,120}?\[\s*'[a-z_]*(?:telefon|rufnummer|mobil)[a-z_]*'\s*\]""");

    const eigeneNummern = 'unsere eigene Vertragsnummer — sich selbst anzurufen '
        'hilft niemandem';
    const imAuswahlmenue = 'steht in einem DropdownMenuItem; Flutter reicht '
        'Berührungen dort an das Menü weiter, ein Knopf darin wäre tot. Nach der '
        'Auswahl ist die Nummer im Formular wählbar';
    const imAufklappmenue = 'Eintrag in einem Aufklappmenü zum Übernehmen des '
        'Anbieters, kein Anzeigefeld';

    // ⚠️ Der Schlüssel ist Datei + Anfang der Zeile, NICHT die Zeilennummer:
    // eine eingefügte Zeile weiter oben würde sonst jede Ausnahme verschieben,
    // und der Test meldete Fehler, wo keine sind — oder schwiege, wo welche
    // sind. Der Text der Zeile bleibt, wo die Zeile bleibt.
    const ausnahmen = <String, String>{
      "lib/screens/telekom_screen.dart|subtitle: Text('\${v['rufnummer":
          eigeneNummern,
      "lib/screens/telekom_screen.dart|if (v['rufnummer']?.toString()":
          eigeneNummern,
      "lib/widgets/mitgliederverwaltung_vertraege.dart|Text('Tel: \${v['telefonnummer'":
          eigeneNummern,
      "lib/widgets/finanzen_kredit.dart|Text('\${v['telefon'] ?? ''}  ·":
          imAufklappmenue,
      "lib/widgets/gesundheit_tab_content.dart|Text('Tel: \${p['telefon']}', s":
          imAuswahlmenue,
      "lib/widgets/mitgliederverwaltung_arzten_augenarzt.dart|Text('Tel: \${p['telefon']}', s":
          imAuswahlmenue,
      "lib/widgets/mitgliederverwaltung_arzten_hno.dart|Text('Tel: \${p['telefon']}', s":
          imAuswahlmenue,
      "lib/widgets/mitgliederverwaltung_arzten_krankenhaus.dart|Text('Tel: \${p['telefon']}', s":
          imAuswahlmenue,
      "lib/widgets/mitgliederverwaltung_arzten_md.dart|Text('Tel: \${p['telefon']}', s":
          imAuswahlmenue,
      "lib/widgets/mitgliederverwaltung_arzten_rheumatologie.dart|Text('Tel: \${p['telefon']}', s":
          imAuswahlmenue,
    };

    final offen = <String>[];
    final unbenutzt = ausnahmen.keys.toSet();

    for (final datei in quellen()) {
      final zeilen = datei.readAsStringSync().split('\n');
      for (var i = 0; i < zeilen.length; i++) {
        final zeile = zeilen[i];
        if (!anzeige.hasMatch(zeile)) continue;
        if (waehlbar.any(zeile.contains)) continue;
        if (zeile.contains('controller:') || zeile.contains('labelText')) continue;

        // Ein Wählweg in derselben Zeile der Liste zählt: der Knopf im
        // `trailing` steht ein paar Zeilen über der Nummer.
        final von = i - 22 < 0 ? 0 : i - 22;
        final bis = i + 22 > zeilen.length ? zeilen.length : i + 22;
        final umfeld = zeilen.sublist(von, bis).join('\n');
        if (waehlbar.any(umfeld.contains)) continue;

        final gekuerzt = zeile.trim();
        final schluessel = '${datei.path}|'
            '${gekuerzt.substring(0, gekuerzt.length < 30 ? gekuerzt.length : 30)}';
        if (ausnahmen.containsKey(schluessel)) {
          unbenutzt.remove(schluessel);
          continue;
        }
        offen.add('${datei.path}:${i + 1} — $gekuerzt\n      Schlüssel: "$schluessel"');
      }
    }

    expect(
      offen,
      isEmpty,
      reason: 'Hier steht eine Rufnummer auf dem Schirm, ohne dass es einen Weg '
          'zum Anruf gibt. In einer Auswahlliste gehört ein PhoneCallButton ins '
          '`trailing` (auswählen bleibt auswählen), sonst genügt PhoneText:\n'
          '${offen.join('\n')}',
    );
    expect(unbenutzt, isEmpty,
        reason: 'Diese Ausnahmen greifen nicht mehr, bitte entfernen: $unbenutzt');
  });

  test('die Icon-Liste hier deckt sich mit der in phone_link.dart', () {
    // ⚠️ Läuft die Liste auseinander, prüft dieser Test einen Teil der App
    // nicht mehr — und meldet trotzdem grün. Genau die Sorte Lücke, die man
    // erst bemerkt, wenn jemand vergeblich auf eine Nummer tippt.
    final quelle = File('lib/widgets/phone_link.dart').readAsStringSync();
    final block = quelle.substring(
      quelle.indexOf('_phoneIcons'),
      quelle.indexOf('bool isPhoneIcon'),
    );
    final dort = RegExp(r'Icons\.\w+')
        .allMatches(block)
        .map((m) => m.group(0)!)
        .toSet();
    expect(dort, telefonIkonen.toSet());
  });
}
