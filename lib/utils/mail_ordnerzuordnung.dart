/// Welche Zeile liegt in welchem Ordner?
///
/// Klingt nach einer Frage, die sich nicht stellt — und tat es auch nicht,
/// solange eine Liste immer genau einen Ordner zeigte. Seit es die Suche über
/// alle Ordner gibt, stehen Zeilen aus Eingang, Papierkorb und Archiv
/// nebeneinander, und die Antwort entscheidet, welche Nachricht eine Aktion
/// trifft.
///
/// ⚠️ Das ist kein Anzeigedetail. UIDs werden **je Ordner** vergeben: dieselbe
/// Zahl steht im Eingang und im Papierkorb für zwei verschiedene Nachrichten.
/// Ein Löschen, das den gewählten statt den wirklichen Ordner nennt, löscht
/// also nicht die falsche Zeile — es löscht eine fremde Mail, die niemand
/// angesehen hat.
///
/// Deshalb steht die Regel hier und nicht im Bildschirm: sie muss ohne
/// Oberfläche prüfbar sein.
library;

/// Der Ordner einer Listenzeile.
///
/// Der Server hängt bei einer Suche über alle Ordner ein `box` an jede Zeile.
/// Fehlt es — normale Ordneransicht, oder ein älterer Server —, gilt der
/// geöffnete Ordner.
String mailZeileOrdner(Map<String, dynamic> zeile, String gewaehlt) {
  final b = '${zeile['box'] ?? ''}'.trim();
  return b.isEmpty ? gewaehlt : b;
}

/// Der Schlüssel, unter dem eine Zeile ausgewählt wird.
///
/// ⚠️ Ordner UND UID. Nur die UID zu merken markierte bei einer Suche über
/// alle Ordner zwei Zeilen — und die zweite hat der Nutzer nie gesehen.
String mailWahlSchluessel(String box, int uid) => '$box/$uid';

/// Gruppiert eine Auswahl nach ihrem wirklichen Ordner.
///
/// ⚠️ Der Server nimmt je Aufruf genau einen Ordner. Eine gemischte Auswahl
/// muss also in mehrere Aufrufe zerfallen; als ein Block geschickt, landeten
/// die UIDs des einen Ordners im anderen.
///
/// Die Reihenfolge innerhalb eines Ordners bleibt die der Liste — so ist die
/// Rückmeldung „7 verschoben" nachvollziehbar.
Map<String, List<int>> mailNachOrdner(
    Iterable<Map<String, dynamic>> auswahl, String gewaehlt) {
  final proOrdner = <String, List<int>>{};
  for (final m in auswahl) {
    final uid = (m['uid'] as num?)?.toInt() ?? 0;
    if (uid <= 0) continue;
    proOrdner.putIfAbsent(mailZeileOrdner(m, gewaehlt), () => []).add(uid);
  }
  return proOrdner;
}
