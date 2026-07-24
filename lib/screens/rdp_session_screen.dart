import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile_webview;

/// Fullscreen (immersive) WebView that hosts a Guacamole HTML5 RDP session.
/// Android/iOS only — Guacamole needs an in-app WebView, which the desktop
/// builds don't provide. On unsupported platforms the caller opens externally.
class RdpSessionScreen extends StatefulWidget {
  final String sessionUrl;
  final String title;

  /// Mints a FRESH session URL server-side (`/api/rdp/session.php`). A Guacamole
  /// token is the session credential and dies shortly after its tunnel closes,
  /// so a dropped connection must be recovered with a new token — reloading the
  /// old URL always fails once the server-side grace window has passed. Null
  /// disables automatic recovery.
  final Future<String> Function()? onNeedNewUrl;

  const RdpSessionScreen({
    super.key,
    required this.sessionUrl,
    required this.title,
    this.onNeedNewUrl,
  });

  @override
  State<RdpSessionScreen> createState() => _RdpSessionScreenState();
}

class _RdpSessionScreenState extends State<RdpSessionScreen>
    with WidgetsBindingObserver {
  mobile_webview.WebViewController? _controller;
  bool _loading = true;
  String? _error;
  bool _showBar = true;
  final Map<int, int> _downSyms = {}; // physicalKey.usbHidUsage -> keysym sent on press

  /// Kept just under the gateway's GUAC_TOKEN_GRACE_SEC (60 s): back within it
  /// and the old token still works, past it we must re-mint.
  static const _grace = Duration(seconds: 45);

  /// The URL actually loaded — replaced on every re-mint, never reused after a
  /// failure. [RdpSessionScreen.sessionUrl] is only the initial value.
  late String _url = widget.sessionUrl;
  bool _recovering = false;

  /// Stops a re-mint loop when the failure is permanent (guacd down, server
  /// unreachable): one automatic attempt, then surface the error. Cleared once
  /// the page reports a live tunnel or the user explicitly retries.
  bool _retried = false;
  DateTime? _bgAt;

  /// Set the moment the user leaves on purpose. The page reports the resulting
  /// disconnect asynchronously, which would otherwise re-mint a session the
  /// user just closed and leave it orphaned on the server.
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Fullscreen + any orientation — only meaningful on mobile.
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    _init();
  }

  Future<void> _init() async {
    try {
      // A key held when the tunnel died never sends its release, which would
      // leave the modifier stuck down in the new session.
      _downSyms.clear();
      final c = mobile_webview.WebViewController();
      await c.setJavaScriptMode(mobile_webview.JavaScriptMode.unrestricted);
      // setBackgroundColor throws "opaque is not implemented on macOS" (NSView
      // lacks the opacity control UIView has) — only call it where supported.
      if (!Platform.isMacOS) {
        await c.setBackgroundColor(Colors.black);
      }
      // client.html posts tunnel state here — see _onBridge.
      await c.addJavaScriptChannel('RdpBridge',
          onMessageReceived: (m) => _onBridge(m.message));
      await c.setNavigationDelegate(mobile_webview.NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (e) {
          // Subresource failures (icons, fonts) don't mean the session is gone.
          if (e.isForMainFrame == false) return;
          _recover(e.description);
        },
      ));
      await c.loadRequest(Uri.parse(_url));
      if (mounted) setState(() => _controller = c);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  /// Tunnel state from client.html. 'connected' means the session is live;
  /// anything else (Guacamole `error` instruction, tunnel closed) means the
  /// token is spent — the status code is deliberately not parsed, since
  /// Guacamole sends non-numeric codes like CONFIG_ERROR.
  void _onBridge(String msg) {
    if (msg == 'connected') {
      _retried = false;
      return;
    }
    _recover('Sitzung getrennt');
  }

  /// Ask the caller for a brand-new session URL and load that. The desktop
  /// itself survives — xrdp re-attaches to the same X display, so the user
  /// lands back in the same session.
  Future<void> _recover(String reason) async {
    if (_recovering || _closing || !mounted) return;
    final mint = widget.onNeedNewUrl;
    if (mint == null || _retried) {
      setState(() {
        _error = reason;
        _loading = false;
      });
      return;
    }
    setState(() {
      _recovering = true;
      _retried = true;
      _error = null;
      _loading = true;
    });
    try {
      final fresh = await mint();
      if (!mounted) return;
      _url = fresh;
      setState(() => _recovering = false);
      await _init();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recovering = false;
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// A backgrounded app (locked screen, call, task switch) comes back to a
  /// token the server has already destroyed, and the WebView gives no error for
  /// that — it just sits on a dead tunnel. Re-mint proactively instead.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _bgAt = DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final since = _bgAt;
    _bgAt = null;
    if (since == null || _controller == null || _error != null) return;
    if (DateTime.now().difference(since) < _grace) return; // old token still valid
    _retried = false; // a real user-visible event, not a retry loop
    _recover('Sitzung abgelaufen');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Restore the normal system UI + orientations (mobile only).
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    super.dispose();
  }

  void _exit() {
    _closing = true;
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  // ── Hardware keyboard → Guacamole (X11 keysym) forwarding ──────────────────

  static final Map<LogicalKeyboardKey, int> _special = {
    LogicalKeyboardKey.enter: 0xFF0D,
    LogicalKeyboardKey.numpadEnter: 0xFF0D,
    LogicalKeyboardKey.backspace: 0xFF08,
    LogicalKeyboardKey.tab: 0xFF09,
    LogicalKeyboardKey.escape: 0xFF1B,
    LogicalKeyboardKey.space: 0x0020,
    LogicalKeyboardKey.delete: 0xFFFF,
    LogicalKeyboardKey.home: 0xFF50,
    LogicalKeyboardKey.end: 0xFF57,
    LogicalKeyboardKey.pageUp: 0xFF55,
    LogicalKeyboardKey.pageDown: 0xFF56,
    LogicalKeyboardKey.arrowLeft: 0xFF51,
    LogicalKeyboardKey.arrowUp: 0xFF52,
    LogicalKeyboardKey.arrowRight: 0xFF53,
    LogicalKeyboardKey.arrowDown: 0xFF54,
    LogicalKeyboardKey.insert: 0xFF63,
    LogicalKeyboardKey.shiftLeft: 0xFFE1,
    LogicalKeyboardKey.shiftRight: 0xFFE2,
    LogicalKeyboardKey.controlLeft: 0xFFE3,
    LogicalKeyboardKey.controlRight: 0xFFE4,
    LogicalKeyboardKey.altLeft: 0xFFE9,
    LogicalKeyboardKey.altRight: 0xFFEA, // AltGr
    LogicalKeyboardKey.metaLeft: 0xFFEB,
    LogicalKeyboardKey.metaRight: 0xFFEC,
    LogicalKeyboardKey.capsLock: 0xFFE5,
    LogicalKeyboardKey.f1: 0xFFBE,
    LogicalKeyboardKey.f2: 0xFFBF,
    LogicalKeyboardKey.f3: 0xFFC0,
    LogicalKeyboardKey.f4: 0xFFC1,
    LogicalKeyboardKey.f5: 0xFFC2,
    LogicalKeyboardKey.f6: 0xFFC3,
    LogicalKeyboardKey.f7: 0xFFC4,
    LogicalKeyboardKey.f8: 0xFFC5,
    LogicalKeyboardKey.f9: 0xFFC6,
    LogicalKeyboardKey.f10: 0xFFC7,
    LogicalKeyboardKey.f11: 0xFFC8,
    LogicalKeyboardKey.f12: 0xFFC9,
  };

  /// Map a Flutter [KeyEvent] to an X11 keysym. On press we prefer the resolved
  /// character (respects layout/Shift); the same keysym is replayed on release.
  int? _keysymFor(KeyEvent e, bool isDown) {
    final special = _special[e.logicalKey];
    if (special != null) return special;
    if (isDown) {
      final ch = e.character;
      if (ch != null && ch.isNotEmpty) {
        final cp = ch.runes.first;
        if (cp >= 0x20) return cp < 0x100 ? cp : (0x01000000 + cp);
      }
    }
    final label = e.logicalKey.keyLabel;
    if (label.length == 1) {
      final cp = label.toLowerCase().codeUnitAt(0);
      if (cp >= 0x20 && cp < 0x100) return cp;
    }
    return null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    // Only Android's WebView drops hardware/Bluetooth keys; iOS/macOS WKWebView
    // deliver them natively, so bridging there would double-type.
    if (!Platform.isAndroid) return KeyEventResult.ignored;
    final ctrl = _controller;
    if (ctrl == null || _error != null) return KeyEventResult.ignored;
    final phys = e.physicalKey.usbHidUsage;
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      final sym = _keysymFor(e, true);
      if (sym == null) return KeyEventResult.ignored;
      _downSyms[phys] = sym;
      _injectKey(ctrl, sym, 1);
      return KeyEventResult.handled;
    } else if (e is KeyUpEvent) {
      final sym = _downSyms.remove(phys) ?? _keysymFor(e, false);
      if (sym == null) return KeyEventResult.ignored;
      _injectKey(ctrl, sym, 0);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _injectKey(mobile_webview.WebViewController ctrl, int keysym, int pressed) {
    ctrl.runJavaScript('window.__guacKey && window.__guacKey($keysym, $pressed);');
  }

  @override
  Widget build(BuildContext context) {
    // Focus captures hardware/Bluetooth keyboard events (webview_flutter on
    // Android doesn't deliver them to the page) and forwards them into Guacamole.
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_controller != null && _error == null)
              Positioned.fill(
                  child: mobile_webview.WebViewWidget(controller: _controller!)),
            if (_error != null) Center(child: _errorView()),
            if (_loading && _error == null)
              const Center(child: CircularProgressIndicator(color: Colors.white)),
            Positioned(
              bottom: 6,
              left: 6,
              child: _showBar
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      _circleBtn(Icons.close, 'Trennen', _exit),
                      const SizedBox(width: 6),
                      // Re-mint rather than reload(): the loaded URL's token is
                      // single-session and reloading it would fail.
                      _circleBtn(Icons.refresh, 'Neu laden', () {
                        _retried = false;
                        _recover('Neu laden fehlgeschlagen');
                      }),
                      const SizedBox(width: 6),
                      _circleBtn(Icons.keyboard, 'Tastatur', () {
                        _controller?.runJavaScript(
                            "var e=document.querySelector('input,textarea,[contenteditable]');if(e){e.focus();}");
                      }),
                      const SizedBox(width: 6),
                      _circleBtn(Icons.visibility_off, 'Ausblenden',
                          () => setState(() => _showBar = false)),
                    ])
                  : _circleBtn(
                      Icons.menu, 'Menü', () => setState(() => _showBar = true)),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _circleBtn(IconData icon, String tip, VoidCallback onTap) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      ),
    );
  }

  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.desktop_access_disabled, color: Colors.white54, size: 48),
        const SizedBox(height: 12),
        const Text('Verbindung fehlgeschlagen',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 6),
        Text(_error ?? '',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Wrap(spacing: 10, children: [
          OutlinedButton(
            onPressed: _exit,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Zurück'),
          ),
          FilledButton(
            onPressed: () {
              _retried = false; // explicit user action, allow a fresh attempt
              _recover('Verbindung fehlgeschlagen');
            },
            child: const Text('Erneut'),
          ),
        ]),
      ]),
    );
  }
}
