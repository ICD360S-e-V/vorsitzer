/// Herkunft eines in `selected_arzt` gespeicherten Datenbank-Eintrags.
///
/// ⚠️ Jede Arzt-Tabelle hat ihre EIGENE id-Folge. `id 10` ist in
/// `kliniken_datenbank` die Gastroenterologie des Bundeswehrkrankenhauses Ulm
/// und in `aerzte_datenbank` eine völlig andere Praxis. Der Auffrisch-Pfad in
/// den Arzt-Widgets sucht den gespeicherten Eintrag allein über seine id — wer
/// dabei die falsche Tabelle fragt, ersetzt den Eintrag lautlos durch einen
/// fremden: anderer Name, andere Anschrift, andere Faxnummer. Es gibt keine
/// Fehlermeldung und keinen sichtbaren Unterschied zu einer echten Aktualisierung.
///
/// Deshalb trägt jeder ausgewählte Eintrag seine Herkunft mit sich.
const String kArztQuelleFeld = 'quelle_tabelle';

/// Marke für Einträge aus `kliniken_datenbank` (Krankenhäuser und deren
/// Fachabteilungen), die über `searchKliniken()` gefunden wurden.
const String kArztQuelleKliniken = 'kliniken';

/// Bildet eine Zeile aus `kliniken_datenbank` auf die Feldnamen ab, die die
/// Arzt-Widgets erwarten — und setzt dabei die Herkunftsmarke.
///
/// ⚠️ Diese Abbildung stand bisher wortgleich in fünf Widgets. Sie gehört
/// genau hierher: weicht eine Kopie ab, zeigt ein Modul andere Daten als die
/// anderen, ohne dass irgendetwas fehlschlägt.
Map<String, dynamic> klinikAlsArzt(Map<String, dynamic> k) => <String, dynamic>{
      ...k,
      'arzt_name': k['name'] ?? '',
      'praxis_name': k['krankenhaus'] ?? k['name'] ?? '',
      'online_termin_url': k['online_termin_url'] ?? '',
      kArztQuelleFeld: kArztQuelleKliniken,
    };

/// Stammt dieser gespeicherte Eintrag aus `kliniken_datenbank`?
///
/// Für Altbestand ohne Herkunftsmarke entscheidet das Feld `krankenhaus`:
/// diese Spalte gibt es ausschließlich in `kliniken_datenbank`, in keiner der
/// Praxis-Tabellen. Ein Eintrag ohne Marke und ohne `krankenhaus` gilt als
/// Praxis-Eintrag — also genau das Verhalten von vorher.
bool istKlinikEintrag(Map<dynamic, dynamic> arzt) {
  final marke = arzt[kArztQuelleFeld]?.toString() ?? '';
  if (marke.isNotEmpty) return marke == kArztQuelleKliniken;
  return arzt.containsKey('krankenhaus');
}
