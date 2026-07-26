import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:puppeteer/puppeteer.dart' as pup;

/// Drives an external Chromium process on the host via Chrome DevTools
/// Protocol. Used on Linux (Flatpak) where the in-app webview_cef is too
/// unstable for production. On Windows/macOS/mobile we keep the embedded
/// webview path in WebViewScreen.
///
/// Flow:
///   1. Locate a Chromium-family browser on the host (Chromium Flatpak,
///      system chromium/chrome/brave, or already-running CDP instance).
///   2. Spawn it with --remote-debugging-port=9242 via `flatpak-spawn --host`
///      so it lives in the user's session, not in our sandbox.
///   3. Poll http://127.0.0.1:9242/json/version until DevTools is ready.
///   4. Connect puppeteer over the WebSocket endpoint and open a new tab.
///   5. Inject the same auto-fill JS we used in webview_cef.
///
/// The Chromium window stays open after this call returns — the user closes
/// it manually like any normal browser tab. We keep the Browser object alive
/// and reuse it for follow-up calls in the same Vorsitzer session.
class ExternalBrowserService {
  static const int _cdpPort = 9242;
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
      // Surface what actually went wrong. This used to return a fixed "please
      // install Chromium" text, which threw away the real diagnosis and told
      // users to install a browser they already had running.
      final detail = e is Exception ? e.toString().replaceFirst('Exception: ', '') : '$e';
      return 'Browser konnte nicht geöffnet werden.\n\n$detail';
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

    final wsEndpoint = await _spawnAndAwaitCdp();
    _browser = await pup.puppeteer.connect(browserWsEndpoint: wsEndpoint);
  }

  /// Spawn a Chromium-family browser if one isn't already listening on
  /// [_cdpPort], then return the WebSocket debugger URL.
  static Future<String> _spawnAndAwaitCdp() async {
    final existing = await _fetchWsEndpoint();
    if (existing != null) {
      debugPrint('[CDP] reusing existing browser on port $_cdpPort');
      return existing;
    }

    final dataDir = await getApplicationSupportDirectory();
    final cdpProfile = Directory('${dataDir.path}/cdp-profile');
    if (!cdpProfile.existsSync()) {
      cdpProfile.createSync(recursive: true);
    }

    final commonArgs = <String>[
      '--remote-debugging-port=$_cdpPort',
      '--remote-debugging-address=127.0.0.1',
      '--user-data-dir=${cdpProfile.path}',
      '--no-first-run',
      '--no-default-browser-check',
    ];

    // Find out what is ACTUALLY installed before launching anything.
    //
    // The previous version tried three Flatpak browsers blind, and because
    // Process.start(detached) never reports that `flatpak run` failed, each
    // dead candidate burnt the full 12 s CDP poll — 36 s before it even reached
    // the native binary that was installed all along. Worse, the final error
    // said "install Chromium" on machines where Chromium was installed and
    // running, which sends the user looking in exactly the wrong place.
    final candidates = await _discoverBrowsers();

    if (candidates.isEmpty) {
      throw Exception(
        'Kein Chromium-Browser gefunden.\n\n'
        'Gesucht wurde nach: chromium, chromium-browser, google-chrome, '
        'brave-browser (nativ) sowie den Flatpaks org.chromium.Chromium, '
        'com.brave.Browser, com.google.Chrome.\n\n'
        'Installation z.B.:  sudo apt install chromium\n'
        'oder:  flatpak install flathub org.chromium.Chromium',
      );
    }

    final tried = <String>[];
    for (final c in candidates) {
      final cmd = [...c.launcher, ...commonArgs];
      try {
        await Process.start(cmd.first, cmd.sublist(1),
            mode: ProcessStartMode.detached);
        debugPrint('[CDP] launched ${c.label}: ${cmd.join(' ')}');
        final ws = await _waitForCdpReady();
        if (ws != null) return ws;
        tried.add('${c.label}: gestartet, aber kein Debug-Port auf $_cdpPort');
      } catch (e) {
        tried.add('${c.label}: $e');
        debugPrint('[CDP] launch failed (${c.label}): $e');
      }
    }

    // Everything that exists was tried and none came up. Name them, so the
    // message describes what actually happened instead of guessing.
    throw Exception(
      'Browser gefunden, aber die Fernsteuerung kam nicht zustande.\n\n'
      '${tried.join('\n')}\n\n'
      'Tipp: Läuft bereits ein Browser mit diesem Profil, bitte schließen '
      'und erneut versuchen.',
    );
  }

  /// Browsers that are actually present, best first.
  ///
  /// Native binaries are probed before Flatpaks: if both exist the native one
  /// starts faster and needs no portal round-trip.
  static Future<List<_BrowserCandidate>> _discoverBrowsers() async {
    final sandboxed = File('/.flatpak-info').existsSync();
    // Outside the sandbox we must NOT prefix with flatpak-spawn — it does not
    // exist there, and every launch would fail with ProcessException.
    List<String> host(List<String> argv) =>
        sandboxed ? ['flatpak-spawn', '--host', ...argv] : argv;

    final found = <_BrowserCandidate>[];

    Future<bool> hostHas(String bin) async {
      try {
        final r = await Process.run(
          host(['sh', '-c', 'command -v ${_shellQuote(bin)}']).first,
          host(['sh', '-c', 'command -v ${_shellQuote(bin)}']).sublist(1),
        ).timeout(const Duration(seconds: 4));
        return r.exitCode == 0 && r.stdout.toString().trim().isNotEmpty;
      } catch (_) {
        return false;
      }
    }

    for (final bin in const [
      'chromium', 'chromium-browser', 'google-chrome', 'google-chrome-stable',
      'brave-browser'
    ]) {
      if (await hostHas(bin)) {
        found.add(_BrowserCandidate(bin, host([bin])));
      }
    }

    // Flatpak browsers — only those the host reports as installed.
    try {
      final listCmd = host(['flatpak', 'list', '--app', '--columns=application']);
      final r = await Process.run(listCmd.first, listCmd.sublist(1))
          .timeout(const Duration(seconds: 6));
      final installed = r.stdout.toString();
      for (final id in const [
        'org.chromium.Chromium', 'com.brave.Browser', 'com.google.Chrome'
      ]) {
        if (installed.contains(id)) {
          found.add(_BrowserCandidate(
              'flatpak $id', host(['flatpak', 'run', '--branch=stable', id])));
        }
      }
    } catch (e) {
      debugPrint('[CDP] flatpak list failed (ignored): $e');
    }

    debugPrint('[CDP] browsers found: ${found.map((c) => c.label).join(', ')}');
    return found;
  }

  static String _shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

  /// Poll until /json/version responds or we hit the deadline.
  static Future<String?> _waitForCdpReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      final ws = await _fetchWsEndpoint();
      if (ws != null) return ws;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return null;
  }

  /// Returns the WebSocket debugger URL if a CDP server is up on
  /// 127.0.0.1:[_cdpPort], otherwise null.
  static Future<String?> _fetchWsEndpoint() async {
    try {
      final r = await http
          .get(Uri.parse('http://127.0.0.1:$_cdpPort/json/version'))
          .timeout(const Duration(seconds: 1));
      if (r.statusCode != 200) return null;
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return data['webSocketDebuggerUrl'] as String?;
    } catch (_) {
      return null;
    }
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

/// One browser that is actually installed, with the argv prefix needed to
/// launch it from wherever we happen to be running (sandboxed or not).
class _BrowserCandidate {
  final String label;
  final List<String> launcher;
  const _BrowserCandidate(this.label, this.launcher);
}
