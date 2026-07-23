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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              top: 6,
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
    );
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
