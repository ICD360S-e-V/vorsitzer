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

      return null;
    } catch (e, stack) {
      debugPrint('[CDP] openWithAutoFill failed: $e\n$stack');
      // Reset so the next call retries from scratch instead of reusing
      // a half-dead Browser object.
      await _resetBrowser();
      return 'Browser konnte nicht geöffnet werden.\n\n'
          'Bitte installiere Chromium (oder Brave/Chrome):\n'
          '  flatpak install flathub org.chromium.Chromium\n\n'
          'Fehlerdetails: $e';
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

    // Probe order: Chromium Flatpak → Brave Flatpak → Chrome Flatpak →
    // host-native binaries. flatpak-spawn --host is necessary because we
    // ourselves run inside the org.freedesktop.Platform sandbox.
    final attempts = <List<String>>[
      [
        'flatpak-spawn', '--host',
        'flatpak', 'run', '--branch=stable',
        'org.chromium.Chromium', ...commonArgs,
      ],
      [
        'flatpak-spawn', '--host',
        'flatpak', 'run', '--branch=stable',
        'com.brave.Browser', ...commonArgs,
      ],
      [
        'flatpak-spawn', '--host',
        'flatpak', 'run', '--branch=stable',
        'com.google.Chrome', ...commonArgs,
      ],
      ['flatpak-spawn', '--host', 'chromium', ...commonArgs],
      ['flatpak-spawn', '--host', 'chromium-browser', ...commonArgs],
      ['flatpak-spawn', '--host', 'google-chrome', ...commonArgs],
      ['flatpak-spawn', '--host', 'brave-browser', ...commonArgs],
    ];

    Object? lastError;
    for (final cmd in attempts) {
      try {
        await Process.start(
          cmd.first,
          cmd.sublist(1),
          mode: ProcessStartMode.detached,
        );
        debugPrint('[CDP] launched: ${cmd.join(' ')}');
        final ws = await _waitForCdpReady();
        if (ws != null) return ws;
      } catch (e) {
        lastError = e;
        debugPrint('[CDP] launch attempt failed (${cmd[2]}): $e');
        continue;
      }
    }

    throw Exception(
      'Kein Chromium-Browser gefunden. '
      'Letzte Fehlermeldung: $lastError',
    );
  }

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
