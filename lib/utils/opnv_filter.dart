import '../services/transit_service.dart';

/// Warum eine Trefferliste leer ist. Ohne das steht auf dem Schirm nur
/// „Keine Verbindungen", und niemand kann sehen, welcher Schalter es war.
enum OpnvLeerGrund {
  /// Der Dienst hat schon nichts geliefert.
  keineFahrten,
  barrierefrei,
  fahrrad,
  /// Mehrere Schalter zusammen — einzeln würde jeder etwas übrig lassen.
  mehrere,
}

/// Ergebnis von [sichtbareTreffer]: die Original-Indizes der sichtbaren
/// Fahrten und, falls nichts übrig bleibt, der Grund dafür.
class OpnvSicht {
  final List<int> indizes;
  final OpnvLeerGrund? leerGrund;
  const OpnvSicht(this.indizes, this.leerGrund);
  bool get istLeer => indizes.isEmpty;
}

/// Welche Fahrten die Oberfläche zeigt.
///
/// Gibt **Original-Indizes** zurück, weil die Barrierefreiheits-Auskunft
/// nach der ursprünglichen Position abgelegt ist.
///
/// [aufzugKaputt] beantwortet je Index, ob auf dieser Fahrt ein Aufzug
/// gemeldet defekt ist; `null` heisst „keine Auskunft" und blendet nicht aus
/// — eine Haltestelle ohne Aufzugsdaten ist nicht dasselbe wie eine mit
/// kaputtem Aufzug.
OpnvSicht sichtbareTreffer(
  List<Journey> fahrten, {
  required bool barrierFrei,
  required bool mitRad,
  required bool? Function(int index) aufzugKaputt,
}) {
  if (fahrten.isEmpty) {
    return const OpnvSicht([], OpnvLeerGrund.keineFahrten);
  }

  final sichtbar = <int>[];
  var nurWegenBarriere = 0;
  var nurWegenRad = 0;

  for (int i = 0; i < fahrten.length; i++) {
    final barriere = barrierFrei && (aufzugKaputt(i) ?? false);
    // ⚠️ `fahrradAusgeschlossen`, NICHT `!bikeAllowedHeuristic`: letzteres
    // meldet beim Bus „nicht erlaubt", obwohl es schlicht unbekannt ist, und
    // hat damit jede Busfahrt ausgeblendet.
    final rad = mitRad && fahrten[i].legs.any((l) => l.fahrradAusgeschlossen);

    if (!barriere && !rad) {
      sichtbar.add(i);
    } else if (barriere && !rad) {
      nurWegenBarriere++;
    } else if (rad && !barriere) {
      nurWegenRad++;
    }
  }

  if (sichtbar.isNotEmpty) return OpnvSicht(sichtbar, null);

  // Nichts übrig — sagen, welcher Schalter es war.
  final grund = nurWegenBarriere > 0 && nurWegenRad > 0
      ? OpnvLeerGrund.mehrere
      : nurWegenBarriere > 0
          ? OpnvLeerGrund.barrierefrei
          : nurWegenRad > 0
              ? OpnvLeerGrund.fahrrad
              : OpnvLeerGrund.mehrere;
  return OpnvSicht(const [], grund);
}

/// Satz für den leeren Bildschirm. Nennt den Schalter beim Namen, damit
/// niemand den Fehler bei der Suche sucht.
String opnvLeerText(OpnvLeerGrund grund, {required bool nurDTicket}) {
  switch (grund) {
    case OpnvLeerGrund.keineFahrten:
      return nurDTicket
          ? 'Keine Verbindung, die vollständig mit dem Deutschlandticket '
              'gültig ist.\n\nSchalten Sie „Nur D-Ticket" aus, um auch '
              'Verbindungen mit ICE, IC oder EC zu sehen.'
          : 'Keine Verbindungen gefunden.';
    case OpnvLeerGrund.barrierefrei:
      return 'Alle gefundenen Verbindungen haben einen als defekt gemeldeten '
          'Aufzug.\n\nSchalten Sie „Barrierefrei" aus, um sie trotzdem zu sehen.';
    case OpnvLeerGrund.fahrrad:
      return 'Auf allen gefundenen Verbindungen ist die Fahrradmitnahme '
          'ausgeschlossen.\n\nSchalten Sie „Mit Rad" aus, um sie trotzdem zu sehen.';
    case OpnvLeerGrund.mehrere:
      return 'Die gesetzten Filter lassen keine Verbindung übrig.\n\n'
          'Schalten Sie „Barrierefrei" oder „Mit Rad" aus.';
  }
}
