#include <dlfcn.h>
#include <flutter_linux/flutter_linux.h>

#include "my_application.h"

// ⚠️ IMPELLER AUS — sonst bleibt das Blitz-Fenster ein leeres Rechteck.
//
// Seit Flutter 3.47 (CI-Umstellung 3.44.8 → 3.47.2, #541) ist Impeller unter
// Linux die Voreinstellung. Das Hauptfenster verträgt das; das ZWEITE Fenster
// von desktop_multi_window (die Blitz-Karte) zeichnet damit nur noch seine
// unterste Ebene — der Karteninhalt kommt nie an. Im Protokoll dazu
// `Timed out waiting for OpenGL frame of size 380x130 (have 1x1)`.
//
// 🔴 WARUM ES NICHT ÜBER `FLUTTER_ENGINE_SWITCHES` GEHT — der erste Anlauf
// (#557) hat genau das versucht und war im ausgelieferten Programm WIRKUNGSLOS.
// Der Einbetter liest die Umgebungsvariablen nur ausserhalb von Release; in
// `engine_switches.cc` steht die Auswertung hinter `#ifndef FLUTTER_RELEASE`.
// Nachgemessen an den beiden Engines auf dieser Maschine:
//     debug   libflutter_linux_gtk.so : „FLUTTER_ENGINE_SWITCHES" 1×
//     release libflutter_linux_gtk.so : „FLUTTER_ENGINE_SWITCHES" 0×
// Ein Debug-Bau beweist hier also NICHTS. Wer diese Zeilen ändert, prüft am
// Release-Paket nach, nicht an `flutter run`.
//
// ⚠️ WARUM ÜBERLAGERT UND NICHT SCHLICHT GESETZT.
// `fl_dart_project_set_enable_impeller()` wirkt auf das FlDartProject, dem man
// es mitgibt. Das des Hauptfensters legt dieser Runner selbst an — an das des
// Blitz-Fensters kommen wir nicht heran: es entsteht INNERHALB von
// desktop_multi_window (`multi_window_manager.cc`, `fl_dart_project_new()`),
// und der Rückruf, den das Paket uns anbietet, läuft erst, wenn die Engine
// schon steht. Deshalb wird die Fabrik selbst überlagert: das Programm
// definiert `fl_dart_project_new` und liegt in der Symbolsuche vor der
// Engine-Bibliothek, also landen ALLE Projekte hier — auch die des Pakets.
// `dlsym(RTLD_NEXT, …)` holt danach das echte.
//
// ⚠️ Dafür braucht das Programm `ENABLE_EXPORTS` (siehe runner/CMakeLists.txt).
// Ohne das steht `fl_dart_project_new` nicht in seiner dynamischen
// Symboltabelle, das Plugin bindet direkt an die Engine, und diese Datei ist
// wieder wirkungslos — ohne Fehler, ohne Meldung.
//
// ⚠️ Die Meldung unten ist keine Zierde: sie ist die einzige Stelle, an der
// sich im Betrieb ablesen lässt, dass die Überlagerung wirklich greift.
//
// ⚠️ Das ist eine Brücke. Flutter meldet den Opt-out bereits als veraltet
// („Impeller opt-out deprecated … going to go away in an upcoming Flutter
// release"). Fällt er weg, bleibt nur, die Blitz-Karte unter Linux nicht mehr
// in ein eigenes Fenster zu legen, sondern als Überlagerung ins Hauptfenster.
extern "C" FlDartProject* fl_dart_project_new(void) {
  using FabrikFn = FlDartProject* (*)(void);
  static FabrikFn echte_fabrik = nullptr;
  if (echte_fabrik == nullptr) {
    echte_fabrik =
        reinterpret_cast<FabrikFn>(dlsym(RTLD_NEXT, "fl_dart_project_new"));
    if (echte_fabrik == nullptr) {
      // Ohne die echte Fabrik gibt es kein Fenster — laut scheitern ist besser
      // als ein Programm, das ohne Grund gar nicht erst hochkommt.
      g_error("fl_dart_project_new nicht auffindbar: %s", dlerror());
    }
  }
  FlDartProject* projekt = echte_fabrik();
  fl_dart_project_set_enable_impeller(projekt, FALSE);
  g_message("[RENDER] Impeller fuer diese Engine abgeschaltet");
  return projekt;
}

int main(int argc, char** argv) {
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
