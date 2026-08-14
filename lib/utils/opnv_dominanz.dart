import '../services/transit_service.dart';

/// Entfernt Fahrten, die von einer anderen in jeder Hinsicht geschlagen werden.
///
/// Eine Fahrt A ist **dominiert**, wenn es ein B gibt, das
///   * nicht früher losfährt,
///   * nicht später ankommt und
///   * nicht öfter umsteigen lässt,
/// und in mindestens einem Punkt echt besser ist. Wer B nehmen kann, hat
/// keinen Grund für A — später aufstehen, gleich früh da, seltener umsteigen.
///
/// ⚠️ Der Anlass ist gemessen, nicht ausgedacht. Saarbrücken → Ulm am
/// 14.08.2026 um 23:07 zeigte als erste Fahrt:
///
///     02:23  Fußweg, dann Tram 1 für DREI Minuten
///            danach 36 Minuten Wartezeit
///     03:06  Nachtbus N2 …                     Ankunft 10:51, 6× umsteigen
///
/// und weiter unten in derselben Liste:
///
///     02:54  Fußweg zum selben Halt
///     03:06  derselbe Nachtbus N2 …            Ankunft 10:51, 5× umsteigen
///
/// Beide erreichen denselben Bus. Die erste holt einen bloss 31 Minuten
/// früher aus dem Bett, für drei Minuten Straßenbahn und eine
/// Dreiviertelstunde Warten — und stand oben, weil sie „am frühesten
/// abfährt". Genau das liest sich von aussen wie eine erfundene Auskunft.
///
/// ⚠️ Bewusst KEIN Abwägen zwischen ungleichen Vorteilen: eine Fahrt, die
/// später ankommt, dafür aber seltener umsteigen lässt, bleibt stehen. Dort
/// hat der Fahrgast zu entscheiden, nicht der Filter — für jemanden im
/// Rollstuhl kann ein Umstieg weniger eine Stunde später wert sein.
List<Journey> entferneDominierte(List<Journey> fahrten) {
  if (fahrten.length < 2) return fahrten;

  final behalten = <Journey>[];
  for (var i = 0; i < fahrten.length; i++) {
    final a = fahrten[i];
    var dominiert = false;
    for (var j = 0; j < fahrten.length && !dominiert; j++) {
      if (i == j) continue;
      final b = fahrten[j];
      final nichtFrueher = !b.depTime.isBefore(a.depTime);
      final nichtSpaeter = !b.arrTime.isAfter(a.arrTime);
      final nichtOefter = b.transfers <= a.transfers;
      if (!(nichtFrueher && nichtSpaeter && nichtOefter)) continue;

      final echtBesser = b.depTime.isAfter(a.depTime) ||
          b.arrTime.isBefore(a.arrTime) ||
          b.transfers < a.transfers;
      if (!echtBesser) continue;

      // ⚠️ Zwei Fahrten mit denselben drei Werten überleben BEIDE: `echtBesser`
      // ist dann falsch, keine verdrängt die andere. Das ist Absicht — gleiche
      // Zeiten heissen nicht gleiche Fahrt. Da kann derselbe Bahnhof über zwei
      // verschiedene Linien erreicht werden, und welche davon fährt, ist bei
      // Verspätung oder Ausfall ein Unterschied. Hier wird verglichen, nicht
      // dedupliziert.
      dominiert = true;
    }
    if (!dominiert) behalten.add(a);
  }
  // Kann nicht leer werden: die früheste Ankunft mit den wenigsten Umstiegen
  // wird von niemandem dominiert. Der Rückfall ist trotzdem da, weil eine
  // leere Liste hier der schlimmste denkbare Ausgang wäre.
  return behalten.isEmpty ? fahrten : behalten;
}
