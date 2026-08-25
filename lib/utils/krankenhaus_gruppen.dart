import 'arzt_quelle.dart';

/// Ein Krankenhaus mit den Abteilungen, die für dieses Mitglied erfasst sind.
///
/// Die Krankenhaus-Ansicht speichert jede Abteilung als eigene *Instanz*
/// (`gesundheit_krankenhaus`, `…_2`, `…_3` …). Zu welchem Haus eine Instanz
/// gehört, steht nicht extra in der Datenbank — es steckt im ausgewählten
/// Eintrag: `kliniken_datenbank` führt für jede Fachabteilung die Spalte
/// `krankenhaus`. Die Gruppierung wird daraus abgeleitet, es gibt dafür
/// keinen zweiten Speicher, der veralten könnte.
class KrankenhausGruppe {
  /// Anzeigename des Hauses.
  final String haus;

  /// Indizes der zugehörigen Instanzen — **global**, also so, wie sie
  /// `getActiveType()` und `_multiArztSelected` erwarten. Eine gefilterte
  /// Nummerierung würde beim Speichern in die falsche Instanz schreiben.
  final List<int> instanzen;

  const KrankenhausGruppe(this.haus, this.instanzen);
}

/// Beschriftung, unter der eine Instanz ohne ausgewähltes Haus erscheint.
///
/// ⚠️ Diese Gruppe MUSS es geben: eine frisch angelegte Instanz hat noch
/// keinen `selected_arzt`. Fiele sie aus der Gruppierung, wäre sie auf dem
/// Schirm nicht mehr erreichbar — angelegt, gespeichert und unsichtbar.
const String kOhneHaus = 'Noch kein Haus gewählt';

String? _feld(Map<dynamic, dynamic> m, String k) {
  final v = m[k];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Zu welchem Haus gehört diese Instanz?
String hausAusInstanz(Map<String, dynamic>? daten) {
  final roh = daten?['selected_arzt'];
  if (roh is! Map || roh.isEmpty) return kOhneHaus;
  // `krankenhaus` gibt es nur in kliniken_datenbank — siehe arzt_quelle.dart.
  if (istKlinikEintrag(roh)) {
    final h = _feld(roh, 'krankenhaus');
    if (h != null) return h;
  }
  return _feld(roh, 'praxis_name') ?? _feld(roh, 'arzt_name') ?? kOhneHaus;
}

/// Beschriftung einer Abteilung innerhalb ihres Hauses.
///
/// Der Hausname wird vorn abgeschnitten, wenn er in der Bezeichnung steckt —
/// über dem Reiter steht er ohnehin schon, und zwölf Reiter, die alle mit
/// „Bundeswehrkrankenhaus Ulm" anfangen, sind nicht auseinanderzuhalten.
String abteilungsName(Map<String, dynamic>? daten, {required int nummer}) {
  final roh = daten?['selected_arzt'];
  if (roh is! Map || roh.isEmpty) return 'Abteilung $nummer';
  final haus = hausAusInstanz(daten);
  var name = _feld(roh, 'name') ?? _feld(roh, 'arzt_name') ?? '';
  if (name.isEmpty) return _feld(roh, 'fachrichtung') ?? 'Abteilung $nummer';
  if (haus != kOhneHaus && name.length > haus.length) {
    for (final trenner in const [' — ', ' – ', ' - ']) {
      final teile = name.split(trenner);
      if (teile.length > 1 && teile.last.trim() == haus) {
        name = teile.sublist(0, teile.length - 1).join(trenner).trim();
        break;
      }
    }
  }
  if (name == haus) return _feld(roh, 'fachrichtung') ?? name;
  return name;
}

/// Gruppiert die Instanzen nach Haus, in der Reihenfolge ihres ersten Auftretens.
///
/// [instanzDaten] ist die Liste aller Instanzen in globaler Reihenfolge;
/// ein `null`-Eintrag steht für „noch nicht geladen".
List<KrankenhausGruppe> krankenhausGruppieren(List<Map<String, dynamic>?> instanzDaten) {
  final reihenfolge = <String>[];
  final nach = <String, List<int>>{};
  for (var i = 0; i < instanzDaten.length; i++) {
    final haus = hausAusInstanz(instanzDaten[i]);
    if (!nach.containsKey(haus)) {
      nach[haus] = <int>[];
      reihenfolge.add(haus);
    }
    nach[haus]!.add(i);
  }
  return [for (final h in reihenfolge) KrankenhausGruppe(h, nach[h]!)];
}

/// In welcher Gruppe steckt die aktuell gewählte Instanz?
/// Gibt 0 zurück, wenn der Index zu nichts passt — der Schirm bleibt so
/// immer auf einem gültigen Haus stehen.
int gruppeVonInstanz(List<KrankenhausGruppe> gruppen, int instanz) {
  for (var g = 0; g < gruppen.length; g++) {
    if (gruppen[g].instanzen.contains(instanz)) return g;
  }
  return 0;
}
