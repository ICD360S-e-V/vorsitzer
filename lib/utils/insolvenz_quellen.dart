/// Lesen der Antwort von `insolvenz_manage.php?type=quellen`.
///
/// WARUM DAS EINE EIGENE DATEI IST
/// -------------------------------
/// ⚠️ PHP kennt nur einen Array-Typ. Eine Liste ohne Lücken wird zu einem
/// JSON-Array, dieselbe Struktur mit einer Lücke zu einem Objekt, und eine
/// leere wieder zu `[]`. Ein `as Map` darauf gibt **nicht null zurück,
/// sondern wirft** — im Release-Build bleibt davon eine graue Fläche ohne
/// jede Meldung übrig. Genau so ist der Speedtest-Bildschirm einmal
/// verschwunden.
///
/// Der Server codiert die Quellen deshalb ausdrücklich mit `(object)`. Das
/// hier ist die zweite Hälfte derselben Vorsichtsmaßnahme: die Codierung ist
/// eine Nebenwirkung der Schlüssel, kein Vertrag.
library;

/// Die Quellen-Karte aus der Serverantwort, in jeder Form lesbar.
///
/// Was nicht als Karte ankommt, ergibt eine leere Karte — nie eine Ausnahme.
Map<String, Map<String, dynamic>> insolvenzQuellenLesen(dynamic roh) {
  if (roh is! Map) return const {};
  final ergebnis = <String, Map<String, dynamic>>{};
  roh.forEach((s, v) {
    ergebnis['$s'] = v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  });
  return ergebnis;
}

/// Die verknüpften Unterlagen einer Quelle.
///
/// ⚠️ Liefert `[]`, wenn die Quelle keine kennt — und **nicht** null, damit
/// „keine Unterlagen" und „Feld fehlt" an der Anzeige gleich behandelt
/// werden. Der Unterschied zwischen „nichts da" und „konnte nicht nachsehen"
/// steht im Feld `zustand`, nicht in der Länge dieser Liste.
List<Map<String, dynamic>> insolvenzQuelleDokumente(Map<String, dynamic>? quelle) {
  final d = quelle?['dokumente'];
  if (d is! List) return const [];
  return d
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .where((e) => (e['id'] is int ? e['id'] as int : int.tryParse('${e['id']}') ?? 0) > 0)
      .toList();
}
