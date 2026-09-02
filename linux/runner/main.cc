#include "my_application.h"

// ⚠️ IMPELLER AUS — sonst bleibt das Blitz-Fenster SCHWARZ.
//
// Seit dem Sprung auf Flutter 3.47 (CI-Umstellung 3.44.8 → 3.47.2) ist
// Impeller unter Linux die Voreinstellung. Für das Hauptfenster ist das
// unauffällig; das ZWEITE Fenster von `desktop_multi_window` (die
// Blitz-Karte) zeichnet damit aber nur noch seine unterste Ebene — der
// Karteninhalt kommt nie an.
//
// Gemessen am 02.09.2026 auf dem Rechner des Vorsitzenden (X11/xfwm4 über
// RDP, Software-Rendering: `libEGL warning: DRI3 error`), an der laufenden
// Fassung 6.183.0:
//   * ausgeliefert:            Fenster 380×243, ALLE 92.340 Pixel #000000
//   * eigener Bau, Impeller an: nur der Scaffold-Hintergrund, 100 % Fläche,
//                               dazu `Timed out waiting for OpenGL frame of
//                               size 380x130 (have 1x1)`
//   * derselbe Bau, Impeller aus: Karte vollständig, 0 GL-Warnungen
// Ein Unterschied, eine Ursache — der einzige Unterschied zwischen den
// letzten beiden Läufen war dieser Schalter.
//
// ⚠️ WARUM ÜBER DIE UMGEBUNG UND NICHT ÜBER `fl_dart_project_*`.
// `fl_dart_project_set_enable_impeller()` gälte nur für das Projekt, das
// dieser Runner selbst anlegt — also nur für das Hauptfenster. Das
// Blitz-Fenster bekommt sein `FlDartProject` INNERHALB von
// desktop_multi_window (`multi_window_manager.cc`), wo wir nicht hinreichen.
// Die Umgebungsvariablen liest der Einbetter bei JEDEM Engine-Start neu, also
// auch für die zweite Engine. Deshalb hier, vor dem ersten Fenster.
//
// ⚠️ `--enable-impeller=false` ist von Flutter als veraltet markiert
// („Impeller opt-out deprecated … going to go away in an upcoming Flutter
// release"). Das ist eine Brücke, keine Dauerlösung. Fällt der Schalter weg,
// bleibt nur, die Karte unter Linux nicht mehr in ein eigenes Fenster zu
// legen, sondern als Überlagerung ins Hauptfenster.
//
// ⚠️ NICHT „aufräumen", solange das Blitz-Fenster existiert. Es gibt keinen
// Fehler, keine Meldung und keinen roten Test, wenn diese Zeilen fehlen — nur
// ein schwarzes Rechteck mitten auf dem Bildschirm.
static void impeller_abschalten() {
  // Ein bereits gesetzter Wert von aussen hat Vorrang: so lässt sich zum
  // Nachmessen jederzeit wieder mit Impeller starten, ohne neu zu bauen.
  if (g_getenv("FLUTTER_ENGINE_SWITCHES") != nullptr) return;
  g_setenv("FLUTTER_ENGINE_SWITCHES", "1", TRUE);
  g_setenv("FLUTTER_ENGINE_SWITCH_1", "enable-impeller=false", TRUE);
}

int main(int argc, char** argv) {
  impeller_abschalten();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
