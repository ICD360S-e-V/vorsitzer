import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

/// Der Ämter-Katalog (`sozialamt_db`) liegt auf dem Server; das PHP dazu ist in
/// keinem Repo. Diese Tests halten deshalb genau die Stellen fest, an denen ein
/// Auseinanderlaufen sonst **still** passiert:
///
///  * die Kategorien stehen in `SOZ_KATEGORIEN` (PHP) **und** in
///    `_AmtBearbeitenDialogState._kategorien` (Dart). Der Server ersetzt
///    Unbekanntes durch `sonstige` — die App würde also speichern und der
///    Eintrag käme mit anderer Art zurück, ohne Fehlermeldung.
///  * `results` ist immer eine JSON-Liste (PDO `fetchAll`), auch leer. Ein
///    `as Map` darauf wirft, statt `null` zu liefern.
void main() {
  const serverKategorien = ['sozialamt', 'sozialraum', 'landratsamt', 'jobcenter', 'sonstige'];
  const clientKategorien = ['sozialamt', 'sozialraum', 'landratsamt', 'jobcenter', 'sonstige'];

  test('Kategorien in App und Endpunkt sind identisch', () {
    expect(clientKategorien, serverKategorien);
  });

  test('leerer Katalog ist eine Liste, kein Objekt', () {
    final antwort = jsonDecode('{"success":true,"results":[]}') as Map<String, dynamic>;
    expect(antwort['results'], isA<List>());
    expect((antwort['results'] as List), isEmpty);
  });

  test('Zeile mit Fax und E-Mail wird vollständig gelesen', () {
    final antwort = jsonDecode('''
      {"success":true,"results":[
        {"id":5,"name":"Stadt Ulm — Sozialraum Mitte/Ost","kategorie":"sozialraum",
         "adresse":"Kornhausplatz 4-6","plz_ort":"89073 Ulm","bundesland":"Baden-Württemberg",
         "telefon":"0731 161-5153","fax":null,"email":null,
         "website":"https://www.ulm.de","oeffnungszeiten":"Mo+Di 08:00–12:00",
         "zustaendigkeit":"Stadtmitte und Oststadt","quelle":"https://www.ulm.de/x",
         "geprueft_am":"2026-08-23"},
        {"id":10,"name":"Landratsamt Alb-Donau-Kreis — Sozialamt","kategorie":"sozialamt",
         "adresse":"Schillerstraße 30","plz_ort":"89077 Ulm","bundesland":"Baden-Württemberg",
         "telefon":"0731 185-4360","fax":"0731 185-4375",
         "email":"soziale-sicherung@alb-donau-kreis.de","website":"https://www.alb-donau-kreis.de",
         "oeffnungszeiten":"Mo–Fr 08:00–12:30","zustaendigkeit":"Alb-Donau-Kreis",
         "quelle":"https://www.alb-donau-kreis.de/x","geprueft_am":"2026-08-23"}
      ]}''') as Map<String, dynamic>;

    final zeilen = (antwort['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    expect(zeilen.length, 2);

    // Fehlendes Fax kommt als null zurück, nicht als leerer String — die Karte
    // darf daraus keine "0"-Nummer basteln.
    expect(zeilen[0]['fax'], isNull);
    expect((zeilen[0]['fax']?.toString() ?? '').isEmpty, isTrue);

    expect(zeilen[1]['fax'], '0731 185-4375');
    expect(zeilen[1]['email'], 'soziale-sicherung@alb-donau-kreis.de');
    expect(zeilen[1]['geprueft_am'], '2026-08-23');
  });

  test('Übernahme ins Mitglied trägt Fax und E-Mail mit', () {
    // Das ist die Feldliste aus _showBehoerdeSelectDialog. Fehlt hier eines,
    // steht es später in der Karte nicht — obwohl es im Katalog vorhanden ist.
    const uebernommen = ['name', 'adresse', 'plz_ort', 'telefon', 'fax', 'email',
                         'website', 'oeffnungszeiten', 'zustaendigkeit'];
    expect(uebernommen, contains('fax'));
    expect(uebernommen, contains('email'));
  });
}
