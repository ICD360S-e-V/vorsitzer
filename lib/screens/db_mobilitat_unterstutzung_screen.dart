import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/platform_service.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile_webview;
import 'package:webview_windows/webview_windows.dart' as windows_webview;

class DbMobilitaetUnterstuetzungScreen extends StatefulWidget {
  final VoidCallback onBack;

  const DbMobilitaetUnterstuetzungScreen({super.key, required this.onBack});

  @override
  State<DbMobilitaetUnterstuetzungScreen> createState() =>
      _DbMobilitaetUnterstuetzungScreenState();
}

class _DbMobilitaetUnterstuetzungScreenState
    extends State<DbMobilitaetUnterstuetzungScreen> {
  static const String _url = 'https://msz.bahnhof.de/unterstuetzungsbedarf';

  windows_webview.WebviewController? _windowsController;
  mobile_webview.WebViewController? _mobileController;
  bool _isLoading = true;
  bool _isInitialized = false;
  String _currentUrl = _url;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    if (Platform.isWindows) {
      await _initWindowsWebView();
    } else if (Platform.isMacOS || PlatformService.isMobile) {
      await _initMobileWebView();
    }
  }

  Future<void> _initWindowsWebView() async {
    try {
      _windowsController = windows_webview.WebviewController();
      await _windowsController!.initialize();

      _windowsController!.url.listen((url) {
        if (mounted) setState(() => _currentUrl = url);
      });

      _windowsController!.loadingState.listen((state) {
        if (mounted) {
          setState(() =>
              _isLoading = state == windows_webview.LoadingState.loading);
        }
      });

      await _windowsController!.setBackgroundColor(Colors.white);
      await _windowsController!.loadUrl(_url);

      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('[DB WebView] Windows init error: $e');
    }
  }

  Future<void> _initMobileWebView() async {
    try {
      final controller = mobile_webview.WebViewController();
      await controller
          .setJavaScriptMode(mobile_webview.JavaScriptMode.unrestricted);
      if (!Platform.isMacOS) {
        await controller.setBackgroundColor(Colors.white);
      }
      await controller.setNavigationDelegate(
        mobile_webview.NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() { _isLoading = true; _currentUrl = url; });
          },
          onPageFinished: (url) {
            if (mounted) setState(() { _isLoading = false; _currentUrl = url; });
          },
        ),
      );
      await controller.loadRequest(Uri.parse(_url));
      _mobileController = controller;
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('[DB WebView] Init error: $e');
    }
  }

  @override
  void dispose() {
    _windowsController?.dispose();
    super.dispose();
  }

  Future<void> _goBack() async {
    if (Platform.isWindows) {
      _windowsController?.goBack();
    } else if (_mobileController != null) {
      if (await _mobileController!.canGoBack()) {
        _mobileController!.goBack();
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
      _windowsController?.loadUrl(_url);
    } else {
      _mobileController?.loadRequest(Uri.parse(_url));
    }
  }

  Future<void> _openExternal() async {
    final url = _currentUrl.isNotEmpty ? _currentUrl : _url;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
                tooltip: 'Zurück',
              ),
              const SizedBox(width: 4),
              Icon(Icons.train, color: Colors.blue.shade700, size: 24),
              const SizedBox(width: 8),
              const Text(
                'DB Mobilitätsservice',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // Navigation buttons
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 18),
                onPressed: _goBack,
                tooltip: 'Zurück',
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _reload,
                tooltip: 'Aktualisieren',
              ),
              IconButton(
                icon: const Icon(Icons.home, size: 20),
                onPressed: _loadHome,
                tooltip: 'Startseite',
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 20),
                onPressed: _openExternal,
                tooltip: 'Im Browser öffnen',
              ),
            ],
          ),
        ),
        // URL bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              Icon(
                Icons.lock,
                size: 14,
                color: _currentUrl.startsWith('https')
                    ? Colors.green
                    : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentUrl,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // Loading indicator
        if (_isLoading)
          const LinearProgressIndicator(
            backgroundColor: Colors.grey,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4a90d9)),
          ),
        // WebView
        Expanded(child: _buildWebView()),
      ],
    );
  }

  Widget _buildWebView() {
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
    } else if ((Platform.isMacOS || PlatformService.isMobile) &&
        _mobileController != null) {
      return mobile_webview.WebViewWidget(controller: _mobileController!);
    }

    return const Center(
      child: Text('WebView nicht unterstützt'),
    );
  }
}
