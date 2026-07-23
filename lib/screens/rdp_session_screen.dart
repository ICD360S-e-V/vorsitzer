import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile_webview;

/// Fullscreen (immersive) WebView that hosts a Guacamole HTML5 RDP session.
/// Android/iOS only — Guacamole needs an in-app WebView, which the desktop
/// builds don't provide. On unsupported platforms the caller opens externally.
class RdpSessionScreen extends StatefulWidget {
  final String sessionUrl;
  final String title;
  const RdpSessionScreen({super.key, required this.sessionUrl, required this.title});

  @override
  State<RdpSessionScreen> createState() => _RdpSessionScreenState();
}

class _RdpSessionScreenState extends State<RdpSessionScreen> {
  mobile_webview.WebViewController? _controller;
  bool _loading = true;
  String? _error;
  bool _showBar = true;
  final Map<int, int> _downSyms = {}; // physicalKey.usbHidUsage -> keysym sent on press

  @override
  void initState() {
    super.initState();
    // Go fullscreen; allow any orientation (RDP is nicer in landscape).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _init();
  }

  Future<void> _init() async {
    try {
      final c = mobile_webview.WebViewController();
      await c.setJavaScriptMode(mobile_webview.JavaScriptMode.unrestricted);
      await c.setBackgroundColor(Colors.black);
      await c.setNavigationDelegate(mobile_webview.NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (e) {
          if (mounted) {
            setState(() {
              _error = e.description;
              _loading = false;
            });
          }
        },
      ));
      await c.loadRequest(Uri.parse(widget.sessionUrl));
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

  @override
  void dispose() {
    // Restore the normal system UI + orientations.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _exit() {
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
                      _circleBtn(Icons.refresh, 'Neu laden', () => _controller?.reload()),
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
              setState(() {
                _error = null;
                _loading = true;
              });
              _init();
            },
            child: const Text('Erneut'),
          ),
        ]),
      ]),
    );
  }
}
