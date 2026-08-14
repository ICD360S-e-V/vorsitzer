import 'package:flutter/material.dart';

import '../services/transit_service.dart';

/// Reihenfolge der Trefferliste in „Verbindung suchen".
///
/// ⚠️ Das sind SORTIERUNGEN, keine Filter — sie verstecken nichts. Der
/// Unterschied ist wichtig genug, um ihn in der Oberfläche sichtbar zu machen:
/// „Barrierefrei" blendet Fahrten aus, „Schnellste" stellt sie nur nach vorn.
/// Wer beides in dieselbe Reihe Knöpfe legt, muss dafür sorgen, dass man sie
/// auseinanderhalten kann.
enum OpnvSortierung {
  abfahrt('Abfahrt', Icons.schedule),
  schnell('Schnellste', Icons.bolt),
  umstiege('Wenig Umsteigen', Icons.swap_horiz),
  billig('Günstigste', Icons.savings);

  const OpnvSortierung(this.titel, this.symbol);
  final String titel;
  final IconData symbol;

  /// Aus dem gespeicherten Namen. ⚠️ Nach Name, nicht nach Index: eine neue
  /// Sortierung in der Mitte der Aufzählung würde sonst eine gespeicherte
  /// Wahl still auf etwas anderes verschieben.
  static OpnvSortierung ausName(String? name) => OpnvSortierung.values
      .firstWhere((s) => s.name == name, orElse: () => OpnvSortierung.abfahrt);
}

/// Ordnet [sichtbar] — eine Liste von **Original-Indizes** in [alle] — nach
/// [nach] um, an Ort und Stelle.
///
/// ⚠️ Es wird bewusst die Index-Liste sortiert und nicht die Fahrten selbst:
/// die Barrierefreiheits-Prüfungen sind nach der ursprünglichen Position
/// abgelegt. Wer hier die Fahrten umsortiert, hängt jeder Verbindung das
/// Aufzugs-Ergebnis einer anderen an — und das fällt niemandem auf, weil
/// beides plausibel aussieht.
///
/// [preis] liefert die geschätzten Mehrkosten einer Fahrt in Euro (0, wenn das
/// Deutschlandticket sie deckt). Wird hereingereicht, damit diese Datei nichts
/// über Tarife wissen muss.
void sortiereOpnvTreffer(
  List<int> sichtbar,
  List<Journey> alle,
  OpnvSortierung nach, {
  required int Function(Journey) preis,
}) {
  if (nach == OpnvSortierung.abfahrt) return;

  int nachDauer(int a, int b) => alle[a].duration.compareTo(alle[b].duration);

  switch (nach) {
    case OpnvSortierung.schnell:
      // Gleich lange Fahrten: die frühere zuerst.
      sichtbar.sort((a, b) {
        final d = nachDauer(a, b);
        return d != 0 ? d : alle[a].depTime.compareTo(alle[b].depTime);
      });
    case OpnvSortierung.umstiege:
      // Für Mitglieder mit Rollstuhl oder Rollator ist jeder Umstieg ein
      // eigenes Risiko — die Fahrt darf dafür länger dauern.
      sichtbar.sort((a, b) {
        final u = alle[a].transfers.compareTo(alle[b].transfers);
        return u != 0 ? u : nachDauer(a, b);
      });
    case OpnvSortierung.billig:
      // Was das Deutschlandticket deckt, kostet nichts extra und steht vorn.
      // Erst danach zählt der Aufpreis, bei gleichem Preis die kürzere Fahrt.
      sichtbar.sort((a, b) {
        final p = preis(alle[a]).compareTo(preis(alle[b]));
        return p != 0 ? p : nachDauer(a, b);
      });
    case OpnvSortierung.abfahrt:
      break;
  }
}
