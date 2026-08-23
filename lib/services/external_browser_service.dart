import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:puppeteer/puppeteer.dart' as pup;

/// Drives an external Chromium process on the host via Chrome DevTools
/// Protocol. Used on Linux (native /opt/.deb build; früher auch Flatpak) where
/// the in-app webview_cef is too unstable for production. On Windows/macOS/mobile
/// we keep the embedded
/// webview path in WebViewScreen.
///
/// Flow:
///   1. Locate a Chromium-family browser on the host (system
///      chromium/chrome/brave; unter Flatpak zusätzlich das Chromium-Flatpak).
///   2. Spawn it with --remote-debugging-port=0 (ephemeral) und einem eigenen
///      Profil. Der Kernel wählt einen freien Port; Chrome schreibt ihn in
///      `<profile>/DevToolsActivePort`. Unter Flatpak geht der Start über
///      `flatpak-spawn --host`, im nativen /opt/.deb-Build direkt.
///   3. Read the chosen port + WS path from that DevToolsActivePort file.
///   4. Connect puppeteer over the WebSocket endpoint and open a new tab.
///   5. Inject the same auto-fill JS we used in webview_cef.
///
/// ⚠️ Sicherheit (Punkt 3 des Audits, 2026-08-23): KEIN fester Port und KEIN
/// Wiederverwenden einer FREMDEN Instanz. Ein CDP-Port hat keinerlei
/// Authentifizierung — wer sich verbindet, steuert den Browser voll (liest das
/// BA-Passwort beim Tippen mit, stiehlt Cookies). Früher lauschte Chrome auf
/// dem festen Port 9242 und wir übernahmen JEDEN dort laufenden CDP-Server;
/// ein lokaler Prozess konnte vorab einen Browser auf 9242 öffnen, und der
/// Auto-Login tippte Benutzer, Passwort und TOTP in SEINEN Browser. Jetzt:
/// zufälliger Port, den nur unser Profil kennt, und Verbindung ausschließlich
/// zu einer Instanz, deren WS-Pfad-GUID zu genau unserem Start passt.
/// Bewusst KEIN --remote-allow-origins: ohne es weist Chrome jede WS-Anfrage
/// MIT Origin-Header (also jede Webseite) von selbst ab — `=*` würde diese
/// eingebaute Abwehr gegen bösartige Seiten AUFHEBEN.
///
/// The Chromium window stays open after this call returns — the user closes
/// it manually like any normal browser tab. We keep the Browser object alive
/// and reuse it for follow-up calls in the same Vorsitzer session.
class ExternalBrowserService {
  static pup.Browser? _browser;

  /// Open [url] in the external Chromium and run [autoFillJs] after page load.
  ///
  /// Returns null on success, or a German error string for the caller to
  /// surface in a snackbar / dialog.
  static Future<String?> openWithAutoFill({
    required String url,
    required String autoFillJs,
    /// (deprecated, no-op acum) Cookie-clearing prin Dart-side puppeteer API
    /// e inconsistent între versiuni. Pentru Keycloak/BA preferăm să gestionăm
    /// stale-session prin JS-ul nostru (sessionStorage flags + detectError),
    /// nu prin ștergere de cookies.
    bool clearCookies = false,

    /// CSS selector of a file input to populate, and the file to put in it.
    ///
    /// JavaScript may not assign a path to `input.files` — that restriction is
    /// the browser's, and it is why the embedded-webview path has to rebuild a
    /// File object from bytes via DataTransfer. Over CDP we do not need that
    /// trick: DOM.setFileInputFiles takes a real path, which is what
    /// ElementHandle.uploadFile() calls underneath. Used for the ELSTER login,
    /// where the .pfx keystore has to land in the page's file picker.
    String? fileInputSelector,
    File? fileToUpload,
  }) async {
    if (!Platform.isLinux) {
      return 'Externer Browser nur unter Linux verfügbar';
    }

    try {
      await _ensureBrowser();

      final page = await _browser!.newPage();

      // Re-inject auto-fill on EVERY navigation. Go2Doc (and many German
      // booking portals) navigate full-page from /praxis/... → /buchung/...
      // → /buchung/person. evaluate() alone fires only once and the form
      // appears on a later page where our JS is no longer present.
      // evaluateOnNewDocument hooks into every fresh document the page
      // loads in this tab.
      try {
        await page.evaluateOnNewDocument(autoFillJs);
      } catch (e) {
        debugPrint('[CDP] evaluateOnNewDocument failed: $e');
      }

      // Also listen for load events explicitly — on some sites the form
      // is injected after DOMContentLoaded by jQuery, so we run again then.
      page.onLoad.listen((_) async {
        try { await page.evaluate(autoFillJs); }
        catch (e) { debugPrint('[CDP] post-load re-eval error: $e'); }
      });

      try {
        await page.goto(url, wait: pup.Until.domContentLoaded)
            .timeout(const Duration(seconds: 30));
      } on TimeoutException {
        // Page may still be useful even if some sub-resources stalled.
        debugPrint('[CDP] goto timed out — continuing with auto-fill anyway');
      }

      // Bring the new tab to the front so the user actually sees it.
      try {
        await page.bringToFront();
      } catch (_) {}

      // Run once now for the initial page (covers Bootstrap forms rendered
      // server-side that are already in the DOM at DOMContentLoaded).
      try {
        await page.evaluate(autoFillJs);
      } catch (e) {
        debugPrint('[CDP] auto-fill JS error (page may still work): $e');
      }

      // Populate a file input, if the caller asked for one. Deliberately AFTER
      // the auto-fill JS: on ELSTER the file picker only exists once the
      // certificate-login pane is selected, which that JS is what triggers.
      if (fileInputSelector != null && fileToUpload != null) {
        final err = await _setFileInput(page, fileInputSelector, fileToUpload);
        if (err != null) {
          // The page is open and usable — the user can still pick the file by
          // hand — so this is reported, not treated as a failure to open.
          debugPrint('[CDP] file input: $err');
          return err;
        }
      }

      return null;
    } catch (e, stack) {
      debugPrint('[CDP] openWithAutoFill failed: $e\n$stack');
      // Reset so the next call retries from scratch instead of reusing
      // a half-dead Browser object.
      await _resetBrowser();
      return 'Browser konnte nicht geöffnet werden.\n\n'
          '${_notFoundMessage()}\n\n'
          'Fehlerdetails: $e';
    }
  }

  /// Put [file] into the file input matching [selector], via CDP.
  ///
  /// Returns null on success, or a German message naming what went wrong —
  /// silence here would look identical to "it worked", and the user would sit
  /// in front of an empty file picker wondering why.
  static Future<String?> _setFileInput(pup.Page page, String selector, File file) async {
    if (!await file.exists()) {
      return 'Zertifikatsdatei nicht gefunden.';
    }
    try {
      // The pane holding the input can appear a moment after load.
      final handle = await page
          .waitForSelector(selector, timeout: const Duration(seconds: 10));
      if (handle == null) {
        return 'Dateifeld auf der Seite nicht gefunden ($selector) — '
            'bitte die Zertifikatsdatei manuell auswählen.';
      }
      // DOM.setFileInputFiles under the hood: a real path, no DataTransfer.
      await handle.uploadFile([file]);
      return null;
    } on TimeoutException {
      return 'Dateifeld auf der Seite nicht gefunden ($selector) — '
          'bitte die Zertifikatsdatei manuell auswählen.';
    } catch (e) {
      return 'Zertifikat konnte nicht eingesetzt werden: $e';
    }
  }

  /// Locate or spawn the external browser, then connect puppeteer.
  static Future<void> _ensureBrowser() async {
    if (_browser != null && _browser!.isConnected) return;

    // Zuerst versuchen, uns wieder mit UNSERER eigenen, noch offenen Instanz zu
    // verbinden (App-Neustart, Browser blieb offen). Das ist sicher: die Adresse
    // kommt aus <profile>/DevToolsActivePort — unserem Profil — und der WS-Pfad
    // trägt eine GUID, die genau zu diesem Browserstart gehört. Ist der Browser
    // weg, hat kein Server diese GUID → connect scheitert → wir starten neu.
    final reuse = await _tryReuseOwnInstance();
    if (reuse != null) {
      _browser = reuse;
      return;
    }

    final wsEndpoint = await _spawnAndAwaitCdp();
    _browser = await pup.puppeteer.connect(browserWsEndpoint: wsEndpoint);
  }

  /// Reconnect to the browser WE launched earlier in a previous app run, if it
  /// is still open. Reads the WS URL from our own profile's DevToolsActivePort;
  /// returns null (→ launch fresh) on any staleness. Never touches a fixed port
  /// or the HTTP discovery endpoint.
  static Future<pup.Browser?> _tryReuseOwnInstance() async {
    try {
      final ws = await _wsFromProfile();
      if (ws == null) return null;
      return await pup.puppeteer
          .connect(browserWsEndpoint: ws)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

  /// Path to the ephemeral DevToolsActivePort file inside our isolated profile.
  static Future<File> _devToolsPortFile() async {
    final dataDir = await getApplicationSupportDirectory();
    return File('${dataDir.path}/cdp-profile/DevToolsActivePort');
  }

  /// Build `ws://127.0.0.1:<port><path>` from our profile's DevToolsActivePort.
  static Future<String?> _wsFromProfile() async =>
      _wsFromPortFile(await _devToolsPortFile());

  /// Parse a DevToolsActivePort file into a browser WS URL, or null if it is
  /// missing/malformed. Line 1 = port, line 2 = `/devtools/browser/<guid>`.
  static String? _wsFromPortFile(File f) {
    try {
      if (!f.existsSync()) return null;
      final lines = f.readAsLinesSync();
      if (lines.length < 2) return null;
      final port = int.tryParse(lines[0].trim());
      final path = lines[1].trim();
      if (port == null || port <= 0 || !path.startsWith('/')) return null;
      return 'ws://127.0.0.1:$port$path';
    } catch (_) {
      return null;
    }
  }

  /// Spawn a Chromium-family browser with an EPHEMERAL debugging port and
  /// return the WebSocket debugger URL of the instance WE just launched.
  static Future<String> _spawnAndAwaitCdp() async {
    final dataDir = await getApplicationSupportDirectory();
    final cdpProfile = Directory('${dataDir.path}/cdp-profile');
    if (!cdpProfile.existsSync()) {
      cdpProfile.createSync(recursive: true);
    }

    // Stale DevToolsActivePort aus einem früheren Start entfernen — sonst läse
    // _waitForDevToolsPort() im Rennen mit dem frisch startenden Chrome
    // womöglich den ALTEN Port und wir verbänden uns mit der falschen Instanz.
    final portFile = File('${cdpProfile.path}/DevToolsActivePort');
    try {
      if (portFile.existsSync()) portFile.deleteSync();
    } catch (_) {}

    final commonArgs = <String>[
      // 0 = der Kernel wählt einen freien Port; der Wert landet in
      // DevToolsActivePort. Kein fester, von außen erratbarer Port mehr.
      '--remote-debugging-port=0',
      '--remote-debugging-address=127.0.0.1',
      '--user-data-dir=${cdpProfile.path}',
      '--no-first-run',
      '--no-default-browser-check',
    ];

    // Only launch browsers that actually exist. Probing first matters twice
    // over: a candidate that was never installed would otherwise cost a full
    // _waitForDevToolsPort() timeout each, and under Flatpak `flatpak-spawn`
    // keeps Process.start from ever throwing, so a dead command looks live.
    final attempts = await _availableBrowsers(commonArgs);

    if (attempts.isEmpty) {
      throw Exception(_notFoundMessage());
    }

    Object? lastError;
    for (final cmd in attempts) {
      try {
        await Process.start(
          cmd.first,
          cmd.sublist(1),
          mode: ProcessStartMode.detached,
        );
        debugPrint('[CDP] launched: ${cmd.join(' ')}');
        final ws = await _waitForDevToolsPort(portFile);
        if (ws != null) return ws;
        debugPrint('[CDP] no DevToolsActivePort after launch: ${cmd.join(' ')}');
      } catch (e) {
        lastError = e;
        debugPrint('[CDP] launch attempt failed (${cmd.join(' ')}): $e');
        continue;
      }
    }

    throw Exception(
      '${_notFoundMessage()}\n'
      'Letzte Fehlermeldung: ${lastError ?? 'DevTools-Port antwortet nicht'}',
    );
  }

  /// True when this process runs inside a Flatpak sandbox.
  ///
  /// The distinction is not cosmetic: `flatpak-spawn` exists ONLY inside the
  /// sandbox. The native /opt build (and any `flutter run` on a dev box) has no
  /// such binary, so prefixing every candidate with it made Process.start throw
  /// before Chromium was ever considered — the browser was installed and
  /// working, and we still reported "Kein Chromium-Browser gefunden".
  static bool? _inFlatpakCache;
  static bool get _inFlatpak => _inFlatpakCache ??=
      File('/.flatpak-info').existsSync() ||
      Platform.environment.containsKey('FLATPAK_ID');

  /// Wrap [cmd] so it runs in the user's session regardless of packaging.
  static List<String> _hostCmd(List<String> cmd) =>
      _inFlatpak ? ['flatpak-spawn', '--host', ...cmd] : cmd;

  /// Run [cmd] on the host and report whether it exited 0.
  static Future<bool> _hostProbe(List<String> cmd) async {
    final full = _hostCmd(cmd);
    try {
      final r = await Process.run(full.first, full.sublist(1))
          .timeout(const Duration(seconds: 5));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Locate [bin], returning the name (or an absolute path) to launch it with,
  /// or null when it is not installed.
  ///
  /// The absolute-path sweep is not redundant: a .desktop launcher can start us
  /// with a minimal PATH, and then `which` itself is unreachable and every
  /// probe would answer "not installed" on a machine full of browsers.
  static Future<String?> _resolveBinary(String bin) async {
    if (await _hostProbe(['which', bin])) return bin;
    for (final dir in const ['/usr/bin', '/usr/local/bin', '/snap/bin']) {
      final path = '$dir/$bin';
      if (_inFlatpak) {
        if (await _hostProbe(['test', '-x', path])) return path;
      } else if (File(path).existsSync()) {
        return path;
      }
    }
    return null;
  }

  /// Browser launch commands that are actually installed, best candidate first.
  static Future<List<List<String>>> _availableBrowsers(
      List<String> commonArgs) async {
    final found = <List<String>>[];

    // Flatpak-packaged browsers. Checked only when the host has a flatpak CLI
    // at all — on a plain Mint/Debian box it usually does not.
    if (await _hostProbe(['flatpak', '--version'])) {
      for (final id in const [
        'org.chromium.Chromium',
        'com.brave.Browser',
        'com.google.Chrome',
      ]) {
        if (await _hostProbe(['flatpak', 'info', id])) {
          found.add(_hostCmd(
              ['flatpak', 'run', '--branch=stable', id, ...commonArgs]));
        }
      }
    }

    // Host-native binaries — the normal case for the /opt build on Linux Mint,
    // including inside an xrdp/XFCE session (DISPLAY is inherited from us).
    for (final bin in const [
      'chromium',
      'chromium-browser',
      'google-chrome',
      'google-chrome-stable',
      'brave-browser',
    ]) {
      final resolved = await _resolveBinary(bin);
      if (resolved != null) {
        found.add(_hostCmd([resolved, ...commonArgs]));
      }
    }

    debugPrint('[CDP] flatpak=$_inFlatpak, ${found.length} browser(s) found');
    return found;
  }

  /// Browser launch commands detected on this machine, best candidate first.
  /// Exposed so the packaging-dependent probe path can be checked without
  /// actually spawning a browser.
  @visibleForTesting
  static Future<List<List<String>>> debugDetectBrowsers() =>
      _availableBrowsers(const ['--remote-debugging-port=0']);

  /// Install hint that matches how this build is actually packaged — telling a
  /// native Mint user to run `flatpak install` sends them down the wrong path.
  static String _notFoundMessage() => _inFlatpak
      ? 'Kein Chromium-Browser gefunden.\n'
          'Bitte installiere Chromium (oder Brave/Chrome), z. B.:\n'
          '  flatpak install flathub org.chromium.Chromium'
      : 'Kein Chromium-Browser gefunden.\n'
          'Bitte installiere Chromium (oder Brave/Chrome), z. B.:\n'
          '  sudo apt install chromium';

  /// Poll until Chrome has written its freshly-chosen port into
  /// [portFile] (DevToolsActivePort), then build the WS URL from it. We never
  /// touch the HTTP /json/version endpoint or a fixed port — the file names the
  /// exact instance we launched (port + `/devtools/browser/<guid>`).
  static Future<String?> _waitForDevToolsPort(File portFile) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      final ws = _wsFromPortFile(portFile);
      if (ws != null) return ws;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return null;
  }

  static Future<void> _resetBrowser() async {
    try {
      _browser?.disconnect();
    } catch (_) {}
    _browser = null;
  }

  /// Detach from the external browser. Does NOT close the user's tabs —
  /// they keep using Chromium normally after Vorsitzer exits.
  static Future<void> dispose() async {
    await _resetBrowser();
  }
}
