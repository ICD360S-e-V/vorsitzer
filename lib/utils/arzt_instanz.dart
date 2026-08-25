/// Welche Arzt-Instanz in einem `type`-Schlüssel steckt.
///
/// Die Arzt-Tabs halten mehrere Einträge derselben Fachrichtung als
/// `gesundheit_hno`, `gesundheit_hno_2`, `gesundheit_hno_3` … Die Zahl im
/// Schlüssel ist zugleich die Spalte `instance` in den `*_arzt`-Tabellen und
/// steckt im `modul`-Schlüssel der Anhänge.
///
/// ⚠️ Bis 2026-08-25 lautete die Regel `_([2-9])$` — also **einstellig**.
/// `gesundheit_krankenhaus_10` traf auf kein Muster und galt damit als
/// Instanz 1. Weil das Speichern die Nummer allein aus dem Schlüssel
/// ableitet, schrieb der zehnte Eintrag in den ersten: Ein Haus wurde durch
/// ein anderes ersetzt, ein Löschen traf das falsche, und die Anhänge zweier
/// Häuser landeten unter demselben `modul`. Es gab weder eine Obergrenze am
/// „+"-Knopf noch eine Meldung. Die Grenze war unsichtbar, nicht gesetzt.
///
/// Kein Basis-Schlüssel endet auf `_<Ziffern>` (`gesundheit_augenarzt`,
/// `gesundheit_hno`, `gesundheit_md`, `gesundheit_rheumatologie`,
/// `gesundheit_krankenhaus`), deshalb ist `_(\d+)$` eindeutig.
int arztInstanzAusType(String type) {
  final m = RegExp(r'_(\d+)$').firstMatch(type);
  if (m == null) return 1;
  return int.tryParse(m.group(1)!) ?? 1;
}

/// Die Umkehrung: Instanz 1 trägt keinen Zusatz, ab 2 hängt die Nummer an.
String arztTypeFuerInstanz(String basis, int instanz) =>
    instanz <= 1 ? basis : '${basis}_$instanz';

/// Instanznummer als Zeichenkette — für Schlüssel, die sie einbetten.
String arztInstanzZeichen(String type) => '${arztInstanzAusType(type)}';
