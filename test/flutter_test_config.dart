import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

/// Läuft einmal vor allen Tests unter `test/`.
///
/// Einziger Zweck: die OpenCV-Tests sollen bei einem schlichten `flutter test`
/// laufen, statt acht rote Zeilen zu hinterlassen, die wie ein kaputter
/// Detektor aussehen und in Wahrheit eine fehlende Datei sind.
///
/// `dartcv4` öffnet seine native Bibliothek mit dem BLOSSEN Namen
/// `libdartcv.so` (`native_lib.dart`, `loadNativeLibrary`). Im Test-VM gibt es
/// keinen App-Build daneben, also findet der Lader nichts, und jeder Aufruf
/// endet in `Failed to load dynamic library`. Die Fehlermeldung ist obendrein
/// leicht zu übersehen, weil der Detektor sie in `catch (_) { return null; }`
/// verschluckt — dann sieht es aus, als fände er einfach nichts.
///
/// ⚠️ Der Trick funktioniert nur, weil die Bibliothek einen SONAME trägt
/// (`readelf -d` sagt `SONAME libdartcv.so`). Wird sie einmal über ihren
/// vollen Pfad geladen, kennt der dynamische Lader sie unter diesem Namen —
/// das spätere `DynamicLibrary.open('libdartcv.so')` von dartcv findet dann
/// die bereits geladene. Ohne SONAME ginge das nicht, und ein zweiter Ladeweg
/// müsste her.
///
/// ⚠️ Wird `DARTCV_LIB_PATH` gesetzt, passiert hier NICHTS. So macht es
/// `pr-checks.yml` auf dem Runner (es sucht die Datei im frischen Linux-Build),
/// und diese Datei darf ihm nicht dazwischenreden.
///
/// ⚠️ Nichts hier darf je einen Test zum Scheitern bringen. Fehlt die
/// Bibliothek, bleibt es bei den bekannten roten Zeilen — das ist ehrlicher
/// als ein übersprungener Test, der so aussieht, als sei er gelaufen.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  _dartcvVorladen();
  await testMain();
}

/// Orte, an denen eine gebaute `libdartcv.so` auf einem Entwicklerrechner liegt.
///
/// Der erste Treffer gewinnt. Absichtlich eine kurze, feste Liste statt einer
/// Suche über die Platte: ein Test-Vorlauf, der Sekunden im Dateisystem
/// verbringt, wird beim ersten Ärger wieder herausgeworfen.
const _orte = [
  // Die auf diesem Rechner installierte Anwendung.
  '/opt/icd360sev-vorsitzer/lib/libdartcv.so',
  // Ein Linux-Build im Arbeitsverzeichnis (dasselbe, was der Runner benutzt).
  'build/linux/x64/debug/bundle/lib/libdartcv.so',
  'build/linux/x64/release/bundle/lib/libdartcv.so',
];

void _dartcvVorladen() {
  if (!Platform.isLinux) return;
  final gesetzt = Platform.environment['DARTCV_LIB_PATH'];
  if (gesetzt != null && gesetzt.isNotEmpty) return;

  for (final ort in _orte) {
    try {
      if (!File(ort).existsSync()) continue;
      ffi.DynamicLibrary.open(File(ort).absolute.path);
      return;
    } catch (_) {
      // Nächster Ort. Eine unpassende Datei ist kein Grund aufzugeben.
    }
  }
  // Nichts gefunden: die OpenCV-Tests scheitern wie bisher, alle anderen
  // laufen. Kein Hinweis auf der Ausgabe — er stünde bei jedem einzelnen
  // Testlauf und hätte nach dem zweiten Mal niemanden mehr, der ihn liest.
}
