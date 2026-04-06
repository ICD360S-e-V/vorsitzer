import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/platform_service.dart';

// Platform-specific imports
import 'package:webview_flutter/webview_flutter.dart' as mobile_webview;

// Windows-specific WebView (conditional)
import 'package:webview_windows/webview_windows.dart' as windows_webview;

/// Cross-Platform WebView Screen
/// - Windows: webview_windows (Edge WebView2)
/// - macOS/Linux: Opens in external browser (webview_flutter desktop not stable)
/// - Android/iOS: webview_flutter (native WebView)
class WebViewScreen extends StatefulWidget {
  final String title;
  final String url;
  final String? autoFillUsername;
  final String? autoFillPassword;

  const WebViewScreen({
    super.key,
    required this.title,
    required this.url,
    this.autoFillUsername,
    this.autoFillPassword,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  // Windows WebView controller
  windows_webview.WebviewController? _windowsController;

  // Mobile WebView controller
  mobile_webview.WebViewController? _mobileController;

  bool _isLoading = true;
  bool _isInitialized = false;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    if (Platform.isWindows) {
      await _initWindowsWebView();
    } else if (Platform.isMacOS || PlatformService.isMobile) {
      // macOS uses WKWebView via webview_flutter (same as iOS)
      await _initMobileWebView();
    } else {
      // Linux: Open in external browser
      await _openInExternalBrowser();
    }
  }

  /// Initialize Windows WebView (Edge WebView2)
  Future<void> _initWindowsWebView() async {
    try {
      _windowsController = windows_webview.WebviewController();
      await _windowsController!.initialize();

      _windowsController!.url.listen((url) {
        if (mounted) {
          setState(() {
            _currentUrl = url;
          });
        }
      });

      _windowsController!.loadingState.listen((state) {
        if (mounted) {
          setState(() {
            _isLoading = state == windows_webview.LoadingState.loading;
          });
          if (state == windows_webview.LoadingState.navigationCompleted) {
            _tryAutoFill();
          }
        }
      });

      await _windowsController!.setBackgroundColor(Colors.white);
      await _windowsController!.loadUrl(widget.url);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      _showError('Windows WebView Fehler: $e');
    }
  }

  /// Initialize WebView (macOS/iOS/Android via WKWebView/native)
  Future<void> _initMobileWebView() async {
    try {
      debugPrint('[WebView] Initializing for ${Platform.operatingSystem}...');
      final controller = mobile_webview.WebViewController();
      await controller.setJavaScriptMode(mobile_webview.JavaScriptMode.unrestricted);
      // setBackgroundColor not supported on macOS WKWebView (opaque not implemented)
      if (!Platform.isMacOS) {
        await controller.setBackgroundColor(Colors.white);
      }
      await controller.setNavigationDelegate(
        mobile_webview.NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url;
            final urlLower = url.toLowerCase();
            // Intercept flutterdownload:// scheme from JS interceptor
            if (urlLower.startsWith('flutterdownload://')) {
              final realUrl = Uri.decodeComponent(url.substring('flutterdownload://'.length));
              debugPrint('[WebView] JS download intercepted: $realUrl');
              _downloadFile(realUrl);
              return mobile_webview.NavigationDecision.prevent;
            }
            return mobile_webview.NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            debugPrint('[WebView] Page started: $url');
            if (mounted) {
              setState(() {
                _isLoading = true;
                _currentUrl = url;
              });
            }
          },
          onPageFinished: (url) {
            debugPrint('[WebView] Page finished: $url');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _currentUrl = url;
              });
            }
            // Auto-fill credentials if provided
            _tryAutoFill();
            // Inject download interceptor for blob/dynamic downloads
            _injectDownloadInterceptor();
          },
          onWebResourceError: (error) {
            debugPrint('[WebView] Error: ${error.description}');
          },
        ),
      );
      await controller.loadRequest(Uri.parse(widget.url));
      _mobileController = controller;

      debugPrint('[WebView] Initialized successfully');
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e, stack) {
      debugPrint('[WebView] Init ERROR: $e');
      debugPrint('[WebView] Stack: $stack');
      _showError('WebView Fehler: $e');
    }
  }

  /// macOS/Linux: Open URL in system browser
  Future<void> _openInExternalBrowser() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      // Close this screen since we opened external browser
      if (mounted) {
        Navigator.pop(context);
      }
    } else {
      _showError('Konnte Browser nicht öffnen');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _windowsController?.dispose();
    super.dispose();
  }

  bool _autoFillDone = false;
  int _autoFillAttempts = 0;

  /// Auto-fill login credentials via JavaScript injection
  /// Retries up to 5 times with delay for SPA sites that load fields dynamically
  Future<void> _tryAutoFill() async {
    if (_autoFillDone) return;
    final user = widget.autoFillUsername;
    final pass = widget.autoFillPassword;
    if (user == null || user.isEmpty) return;

    // Escape quotes for JS string safety
    final jsUser = user.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    final jsPass = (pass ?? '').replaceAll('\\', '\\\\').replaceAll("'", "\\'");

    final js = '''
(function() {
  function setNativeValue(el, val) {
    var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
    setter.call(el, val);
    el.dispatchEvent(new Event('input', {bubbles: true}));
    el.dispatchEvent(new Event('change', {bubbles: true}));
    el.dispatchEvent(new KeyboardEvent('keydown', {bubbles: true}));
    el.dispatchEvent(new KeyboardEvent('keyup', {bubbles: true}));
  }

  var userField = document.querySelector('input[type="email"]')
    || document.querySelector('input[name*="user" i]')
    || document.querySelector('input[name*="email" i]')
    || document.querySelector('input[name*="login" i]')
    || document.querySelector('input[autocomplete="username"]')
    || document.querySelector('input[autocomplete="email"]')
    || document.querySelector('input[id*="email" i]')
    || document.querySelector('input[id*="user" i]')
    || document.querySelector('input[placeholder*="email" i]')
    || document.querySelector('input[placeholder*="E-Mail" i]')
    || document.querySelector('input[type="text"]');

  var passField = document.querySelector('input[type="password"]');

  var filled = 0;
  if (userField) {
    userField.focus();
    setNativeValue(userField, '$jsUser');
    userField.blur();
    filled++;
  }
  if (passField) {
    passField.focus();
    setNativeValue(passField, '$jsPass');
    passField.blur();
    filled++;
  }
  return filled;
})();
''';

    try {
      if (Platform.isWindows && _windowsController != null) {
        await _windowsController!.executeScript(js);
        _autoFillDone = true;
        debugPrint('[WebView] Auto-fill injected (Windows)');
      } else if (_mobileController != null) {
        final result = await _mobileController!.runJavaScriptReturningResult(js);
        debugPrint('[WebView] Auto-fill result: $result (attempt ${_autoFillAttempts + 1})');
        if (result.toString() == '2') {
          _autoFillDone = true;
        } else if (_autoFillAttempts < 5) {
          _autoFillAttempts++;
          await Future.delayed(Duration(milliseconds: 500 * _autoFillAttempts));
          if (mounted) _tryAutoFill();
          return;
        } else {
          _autoFillDone = true;
        }
      }
    } catch (e) {
      debugPrint('[WebView] Auto-fill error: $e');
      if (_autoFillAttempts < 5) {
        _autoFillAttempts++;
        await Future.delayed(Duration(milliseconds: 500 * _autoFillAttempts));
        if (mounted) _tryAutoFill();
      }
    }
  }

  // ── Download files (PDF, images) to Downloads folder ──
  Future<void> _downloadFile(String url) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            const SizedBox(width: 12),
            const Text('Datei wird heruntergeladen...'),
          ]), backgroundColor: Colors.blue, duration: const Duration(seconds: 2)),
        );
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        if (mounted) _showError('Download fehlgeschlagen (${response.statusCode})');
        return;
      }

      // Determine filename from URL or Content-Disposition header
      String fileName = Uri.parse(url).pathSegments.isNotEmpty ? Uri.parse(url).pathSegments.last : 'download';
      final contentDisp = response.headers['content-disposition'];
      if (contentDisp != null) {
        final match = RegExp(r'filename[*]?=["\s]*([^";\s]+)').firstMatch(contentDisp);
        if (match != null) fileName = Uri.decodeComponent(match.group(1)!);
      }
      // Ensure it has an extension
      if (!fileName.contains('.')) {
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('pdf')) {
          fileName += '.pdf';
        } else if (contentType.contains('jpeg') || contentType.contains('jpg')) {
          fileName += '.jpg';
        } else if (contentType.contains('png')) {
          fileName += '.png';
        } else {
          fileName += '.pdf';
        }
      }

      // Save to Downloads folder
      Directory downloadsDir;
      if (Platform.isMacOS) {
        downloadsDir = Directory('${Platform.environment['HOME']}/Downloads');
      } else if (Platform.isWindows) {
        downloadsDir = Directory('${Platform.environment['USERPROFILE']}\\Downloads');
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      // Avoid overwriting - add number if exists
      var destFile = File('${downloadsDir.path}${Platform.pathSeparator}$fileName');
      int counter = 1;
      while (destFile.existsSync()) {
        final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
        final base = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
        destFile = File('${downloadsDir.path}${Platform.pathSeparator}${base}_($counter)$ext');
        counter++;
      }

      await destFile.writeAsBytes(response.bodyBytes);
      debugPrint('[WebView] Downloaded: ${destFile.path}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ $fileName gespeichert in Downloads'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(label: 'Öffnen', textColor: Colors.white, onPressed: () {
              Process.run('open', [destFile.path]);
            }),
          ),
        );
      }
    } catch (e) {
      debugPrint('[WebView] Download error: $e');
      if (mounted) _showError('Download-Fehler: $e');
    }
  }

  /// Inject JS to intercept dynamic downloads (blob URLs, JS-triggered downloads)
  Future<void> _injectDownloadInterceptor() async {
    if (_mobileController == null) return;
    const js = '''
(function() {
  if (window.__downloadInterceptorInjected) return;
  window.__downloadInterceptorInjected = true;

  // Intercept anchor clicks with download attribute or PDF links
  document.addEventListener('click', function(e) {
    var el = e.target;
    while (el && el.tagName !== 'A') el = el.parentElement;
    if (!el || !el.href) return;
    var href = el.href.toLowerCase();
    if (el.hasAttribute('download') || href.endsWith('.pdf') || href.endsWith('.jpg') || href.endsWith('.png')) {
      e.preventDefault();
      e.stopPropagation();
      // Send to Flutter via URL scheme change
      window.location.href = 'flutterdownload://' + encodeURIComponent(el.href);
    }
  }, true);
})();
''';
    try {
      await _mobileController!.runJavaScript(js);
      debugPrint('[WebView] Download interceptor injected');
    } catch (e) {
      debugPrint('[WebView] Download interceptor error: $e');
    }
  }

  // Navigation methods
  Future<void> _goBack() async {
    if (Platform.isWindows) {
      _windowsController?.goBack();
    } else if (_mobileController != null) {
      if (await _mobileController!.canGoBack()) {
        _mobileController!.goBack();
      }
    }
  }

  Future<void> _goForward() async {
    if (Platform.isWindows) {
      _windowsController?.goForward();
    } else if (_mobileController != null) {
      if (await _mobileController!.canGoForward()) {
        _mobileController!.goForward();
      }
    }
  }

  Future<void> _reload() async {
    if (Platform.isWindows) {
      _windowsController?.reload();
    } else {
      _mobileController?.reload();
    }
  }

  Future<void> _loadHome() async {
    if (Platform.isWindows) {
      _windowsController?.loadUrl(widget.url);
    } else {
      _mobileController?.loadRequest(Uri.parse(widget.url));
    }
  }

  Future<void> _openExternal() async {
    final url = _currentUrl.isNotEmpty ? _currentUrl : widget.url;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFF4a90d9),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBack,
            tooltip: 'Zurück',
          ),
          // Forward button
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: _goForward,
            tooltip: 'Vorwärts',
          ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
            tooltip: 'Aktualisieren',
          ),
          // Home button
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: _loadHome,
            tooltip: 'Startseite',
          ),
          // Download current page (PDF)
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              final url = _currentUrl.isNotEmpty ? _currentUrl : widget.url;
              _downloadFile(url);
            },
            tooltip: 'Seite herunterladen',
          ),
          // Open in external browser
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: _openExternal,
            tooltip: 'Im Browser öffnen',
          ),
        ],
      ),
      body: Column(
        children: [
          // Loading indicator
          if (_isLoading)
            const LinearProgressIndicator(
              backgroundColor: Colors.grey,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4a90d9)),
            ),
          // URL bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                Icon(
                  Icons.lock,
                  size: 16,
                  color: _currentUrl.startsWith('https')
                      ? Colors.green
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentUrl.isNotEmpty ? _currentUrl : widget.url,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // WebView content (platform-specific)
          Expanded(
            child: _buildWebViewContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildWebViewContent() {
    if (!_isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Browser wird geladen...'),
          ],
        ),
      );
    }

    if (Platform.isWindows && _windowsController != null) {
      return windows_webview.Webview(_windowsController!);
    } else if ((Platform.isMacOS || PlatformService.isMobile) && _mobileController != null) {
      return mobile_webview.WebViewWidget(controller: _mobileController!);
    }

    // Fallback - should not reach here
    return const Center(
      child: Text('WebView nicht unterstützt auf dieser Plattform'),
    );
  }
}
