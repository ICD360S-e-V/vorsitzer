#include <cstdlib>

#include "my_application.h"

#include <webview_cef/webview_cef_plugin.h>

int main(int argc, char** argv) {
  // webview_cef spawns CEF helper subprocesses by re-exec'ing this binary
  // with --type=… flags. initCEFProcesses detects that and runs the CEF
  // subprocess loop directly, then returns >= 0 so we exit BEFORE booting
  // GTK/Flutter. Without this the helpers each open a blank Vorsitzer window
  // (the multi-instance bug fixed in webview_cef PR #195).
  int cef_exit_code = initCEFProcesses(argc, argv);
  if (cef_exit_code >= 0) {
    return cef_exit_code;
  }

  // Force GTK to use the X11 backend (via XWayland on Plasma/Wayland).
  // CEF's Ozone/X11 path is the only one that's stable inside the
  // org.freedesktop.Platform 24.08 Flatpak sandbox — running native Wayland
  // currently opens blank top-level windows. setenv must happen before
  // gtk_init() is reached by g_application_run.
  setenv("GDK_BACKEND", "x11", 1);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
