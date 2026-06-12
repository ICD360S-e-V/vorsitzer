import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/external_browser_service.dart';
import '../services/platform_service.dart';
import '../utils/file_picker_helper.dart';

// Platform-specific imports
import 'package:webview_flutter/webview_flutter.dart' as mobile_webview;
import 'package:webview_flutter_android/webview_flutter_android.dart' as android_webview;

// Windows-specific WebView (conditional)
import 'package:webview_windows/webview_windows.dart' as windows_webview;

/// Cross-Platform WebView Screen
/// - Windows: webview_windows (Edge WebView2)
/// - macOS: webview_flutter (WKWebView)
/// - Android/iOS: webview_flutter (native WebView)
/// - Linux: driven external Chromium via CDP (see ExternalBrowserService) —
///   webview_cef was removed because libcef.so crashed inside the
///   freedesktop-Platform Flatpak (~3 s splash, then exit).
class WebViewScreen extends StatefulWidget {
  final String title;
  final String url;
  final String? autoFillUsername;
  final String? autoFillPassword;
  final Map<String, String>? go2docAutoFill;
  final String? customJs;

  const WebViewScreen({
    super.key,
    required this.title,
    required this.url,
    this.autoFillUsername,
    this.autoFillPassword,
    this.go2docAutoFill,
    this.customJs,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  // Windows WebView controller
  windows_webview.WebviewController? _windowsController;

  // Mobile WebView controller
  mobile_webview.WebViewController? _mobileController;

  // Linux: external Chromium error message (if launch failed)
  String? _linuxError;
  bool _linuxBusy = false;

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
    } else if (Platform.isLinux) {
      // Linux: hand off to the host Chromium-Flatpak via CDP. Nothing to
      // render in our own window — the user works in the external tab.
      await _launchLinuxExternal();
    } else {
      await _openInExternalBrowser();
    }
  }

  Future<void> _launchLinuxExternal() async {
    if (mounted) setState(() { _linuxBusy = true; _isInitialized = true; _isLoading = false; });

    // Prefer customJs (pre-built by the caller for sites like Rundfunkbeitrag).
    // Otherwise build the Go2Doc-style patient JS from the structured data
    // — same logic the Win/macOS path uses via _tryGo2DocAutoFill, just
    // applied once via CDP instead of retried in-tab.
    var js = widget.customJs ?? '';
    if (js.isEmpty && widget.go2docAutoFill != null && widget.go2docAutoFill!.isNotEmpty) {
      js = _buildGo2DocJs(widget.go2docAutoFill!);
    }

    final err = await ExternalBrowserService.openWithAutoFill(
      url: widget.url,
      autoFillJs: js,
    );
    if (!mounted) return;
    setState(() { _linuxBusy = false; _linuxError = err; });
    if (err == null) {
      // Browser is up with the page loaded — close our placeholder.
      Navigator.of(context).maybePop();
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
      // File upload support
      if (Platform.isAndroid) {
        final androidController = controller.platform as android_webview.AndroidWebViewController;
        await androidController.setOnShowFileSelector(_androidFilePicker);
      }

      // JS channel fallback for file upload (macOS WKWebView)
      await controller.addJavaScriptChannel('FlutterFilePicker', onMessageReceived: (message) async {
        await _handleFilePickerRequest(message.message);
      });

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

  /// Fallback (no longer used by default — kept for unknown platforms): Open
  /// URL in system browser. On Flatpak url_launcher may fail because the
  /// sandbox can't see host's xdg-open — we then try flatpak-spawn --host
  /// and common browsers.
  Future<void> _openInExternalBrowser() async {
    final uri = Uri.parse(widget.url);

    // Try url_launcher first (works on standard Linux, macOS, mobile).
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) Navigator.pop(context);
        return;
      }
    } catch (_) {}

    // Linux fallback chain: detached Process.start, first one that doesn't
    // throw wins. flatpak-spawn first so Flatpak builds escape the sandbox
    // via org.freedesktop.portal.Flatpak.Spawn.
    final attempts = <List<String>>[
      ['flatpak-spawn', '--host', 'xdg-open', widget.url],
      ['xdg-open', widget.url],
      ['gio', 'open', widget.url],
      ['kde-open5', widget.url],
      ['flatpak', 'run', 'org.mozilla.firefox', widget.url],
      ['firefox', widget.url],
      ['flatpak', 'run', 'org.chromium.Chromium', widget.url],
      ['chromium', widget.url],
      ['chromium-browser', widget.url],
      ['google-chrome', widget.url],
    ];

    for (final cmd in attempts) {
      try {
        await Process.start(cmd.first, cmd.sublist(1), mode: ProcessStartMode.detached);
        if (mounted) Navigator.pop(context);
        return;
      } catch (_) {
        continue;
      }
    }

    // All failed: copy URL to clipboard so user can paste into a browser.
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    _showError('Browser konnte nicht geöffnet werden. URL wurde in die Zwischenablage kopiert.');
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

  bool _go2docInjected = false;

  /// Build the patient-form auto-fill JS. Works on any portal that exposes
  /// inputs with German-style name/id/placeholder/label (Vorname, Nachname,
  /// Geburtsdatum, E-Mail, Versicherung) — not just Go2Doc. The Linux/CDP
  /// path uses this directly; the Win/mobile/macOS path wraps it in retry.
  static String _buildGo2DocJs(Map<String, String> d) {
    final vorname = (d['vorname'] ?? '').replaceAll("'", "\\'");
    final nachname = (d['nachname'] ?? '').replaceAll("'", "\\'");
    final gebTag = d['geb_tag'] ?? '';
    final gebMonat = d['geb_monat'] ?? '';
    final gebJahr = d['geb_jahr'] ?? '';
    final gebDatumISO = (gebTag.isNotEmpty && gebMonat.isNotEmpty && gebJahr.isNotEmpty)
        ? '$gebJahr-${gebMonat.padLeft(2, '0')}-${gebTag.padLeft(2, '0')}'
        : '';
    final gebDatumDE = (gebTag.isNotEmpty && gebMonat.isNotEmpty && gebJahr.isNotEmpty)
        ? '${gebTag.padLeft(2, '0')}.${gebMonat.padLeft(2, '0')}.$gebJahr'
        : '';
    final gebDatumSlash = (gebTag.isNotEmpty && gebMonat.isNotEmpty && gebJahr.isNotEmpty)
        ? '${gebMonat.padLeft(2, '0')}/${gebTag.padLeft(2, '0')}/$gebJahr'
        : '';
    final email = (d['email'] ?? '').toString().replaceAll("'", "\\'");
    final telefon = (d['telefon'] ?? '').toString().replaceAll("'", "\\'");
    final plz = (d['plz'] ?? '').toString().replaceAll("'", "\\'");
    final ort = (d['ort'] ?? '').toString().replaceAll("'", "\\'");
    final strasse = (d['strasse'] ?? '').toString().replaceAll("'", "\\'");
    final versicherung = d['versicherung'] ?? 'gesetzlich';
    final versNr = (d['versichertennummer'] ?? '').toString().replaceAll("'", "\\'");

    return '''
(function() {
  function setVal(el, val) {
    if (!el || !val) return false;
    var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
    if (setter) setter.call(el, val);
    else el.value = val;
    el.dispatchEvent(new Event('input', {bubbles: true}));
    el.dispatchEvent(new Event('change', {bubbles: true}));
    return true;
  }
  function setSelect(el, val) {
    if (!el || !val) return false;
    for (var i = 0; i < el.options.length; i++) {
      if (el.options[i].value == val || el.options[i].text.toLowerCase().indexOf(val.toLowerCase()) >= 0) {
        el.selectedIndex = i;
        el.dispatchEvent(new Event('change', {bubbles: true}));
        return true;
      }
    }
    return false;
  }

  var inputs = document.querySelectorAll('input, select, textarea');
  var filled = 0;
  for (var el of inputs) {
    var ph = (el.placeholder || '').toLowerCase();
    var nm = (el.name || '').toLowerCase();
    var id = (el.id || '').toLowerCase();
    var lbl = '';
    if (el.id) { var l = document.querySelector('label[for="' + el.id + '"]'); if (l) lbl = l.textContent.toLowerCase(); }
    var aria = (el.getAttribute('aria-label') || '').toLowerCase();
    var combined = ph + ' ' + nm + ' ' + id + ' ' + lbl + ' ' + aria;

    if (combined.indexOf('vorname') >= 0 || combined.indexOf('firstname') >= 0 || combined.indexOf('first name') >= 0) {
      if (setVal(el, '$vorname')) filled++;
    } else if (combined.indexOf('nachname') >= 0 || combined.indexOf('familienname') >= 0 || combined.indexOf('lastname') >= 0 || combined.indexOf('surname') >= 0 || combined.indexOf('last name') >= 0) {
      if (setVal(el, '$nachname')) filled++;
    } else if (combined.indexOf('geburtsdatum') >= 0 || combined.indexOf('birthdate') >= 0 || combined.indexOf('geburt') >= 0 || combined.indexOf('tt.mm') >= 0 || combined.indexOf('date of birth') >= 0) {
      if ('$gebDatumISO') {
        if (el.type === 'date') { if (setVal(el, '$gebDatumISO')) filled++; }
        else { if (setVal(el, '$gebDatumDE') || setVal(el, '$gebDatumSlash') || setVal(el, '$gebDatumISO')) filled++; }
        try {
          var ngEl = window.ng && window.ng.getComponent ? window.ng.getComponent(el) : null;
          if (!ngEl) { var scope = angular && angular.element && angular.element(el).scope(); if (scope) { scope.Birthdate = '$gebDatumDE'; scope.\$apply(); filled++; } }
        } catch(e2) {}
      }
    } else if (combined.indexOf('e-mail') >= 0 || combined.indexOf('email') >= 0 || el.type === 'email') {
      if (setVal(el, '$email')) filled++;
    } else if (combined.indexOf('telefon') >= 0 || combined.indexOf('telephone') >= 0 || combined.indexOf('phone') >= 0 || combined.indexOf('mobil') >= 0 || el.type === 'tel') {
      if (setVal(el, '$telefon')) filled++;
    } else if (combined.indexOf('plz') >= 0 || combined.indexOf('postleitzahl') >= 0 || combined.indexOf('zip') >= 0 || combined.indexOf('postal') >= 0) {
      if (setVal(el, '$plz')) filled++;
    } else if (combined.indexOf('ort') >= 0 && combined.indexOf('geburt') < 0) {
      if (setVal(el, '$ort')) filled++;
    } else if (combined.indexOf('straße') >= 0 || combined.indexOf('strasse') >= 0 || combined.indexOf('street') >= 0) {
      if (setVal(el, '$strasse')) filled++;
    } else if (combined.indexOf('versichertennummer') >= 0 || combined.indexOf('versicherungsnummer') >= 0 || combined.indexOf('kvnr') >= 0 || combined.indexOf('insurance number') >= 0) {
      if (setVal(el, '$versNr')) filled++;
    } else if (el.tagName === 'SELECT' && (combined.indexOf('versicher') >= 0 || combined.indexOf('kranken') >= 0 || combined.indexOf('kassenart') >= 0)) {
      if (setSelect(el, '$versicherung')) filled++;
    }
  }

  // Fallback: find Geburtsdatum via label scan (Angular SPA / custom layouts)
  if ('$gebDatumDE') {
    var labels = document.querySelectorAll('label');
    for (var lb of labels) {
      if (lb.textContent.trim().toLowerCase().indexOf('geburtsdatum') >= 0) {
        var container = lb.closest('.form-group') || lb.closest('div') || lb.parentElement;
        if (container) {
          var inp = container.querySelector('input');
          if (inp && !inp.value) {
            var dateVal = inp.type === 'date' ? '$gebDatumISO' : '$gebDatumDE';
            if (setVal(inp, dateVal)) filled++;
          }
        }
      }
    }
  }

  // Auto-check consent checkboxes
  var checkboxes = document.querySelectorAll('input[type="checkbox"]');
  for (var cb of checkboxes) {
    var parent = cb.closest('label') || cb.parentElement;
    var txt = parent ? parent.textContent.toLowerCase() : '';
    if (txt.indexOf('willige ein') >= 0 || txt.indexOf('einwillig') >= 0 || txt.indexOf('datenschutz') >= 0 || txt.indexOf('akzeptier') >= 0) {
      if (!cb.checked) { cb.click(); filled++; }
    }
  }

  return filled;
})();
''';
  }

  /// Inject Go2Doc patient form auto-fill on Win/macOS/mobile webviews —
  /// retries because Angular SPAs load inputs lazily.
  Future<void> _tryGo2DocAutoFill() async {
    if (_go2docInjected || widget.go2docAutoFill == null || widget.go2docAutoFill!.isEmpty) return;
    final js = _buildGo2DocJs(widget.go2docAutoFill!);

    // Retry up to 10 times (Angular SPA loads fields dynamically)
    for (int attempt = 0; attempt < 10; attempt++) {
      await Future.delayed(Duration(milliseconds: attempt < 3 ? 1000 : 2000));
      try {
        dynamic result;
        if (_mobileController != null) {
          result = await _mobileController!.runJavaScriptReturningResult(js);
        } else if (_windowsController != null) {
          result = await _windowsController!.executeScript(js);
        }
        final filled = int.tryParse(result?.toString() ?? '0') ?? 0;
        if (filled > 0) {
          debugPrint('[WebView] Go2Doc auto-fill: $filled fields filled (attempt ${attempt + 1})');
          _go2docInjected = true;
          return;
        }
      } catch (e) {
        debugPrint('[WebView] Go2Doc auto-fill attempt ${attempt + 1} error: $e');
      }
    }
  }

  /// Auto-fill login credentials via JavaScript injection
  /// Retries up to 5 times with delay for SPA sites that load fields dynamically
  bool _customJsInjected = false;

  Future<void> _tryCustomJs() async {
    if (_customJsInjected || widget.customJs == null || widget.customJs!.isEmpty) return;
    _customJsInjected = true;
    try {
      if (_mobileController != null) {
        await _mobileController!.runJavaScript(widget.customJs!);
      }
    } catch (_) {}
  }

  bool _fileInterceptorInjected = false;

  Future<void> _injectFilePickerInterceptor() async {
    if (_fileInterceptorInjected || _mobileController == null) return;
    _fileInterceptorInjected = true;
    try {
      await _mobileController!.runJavaScript('''
(function() {
  var _picking = false;
  function requestPick(inp) {
    if (_picking) return;
    _picking = true;
    setTimeout(function() { _picking = false; }, 1000);
    window._flutterFileInput = inp;
    var accept = inp.accept || '.pdf,.jpg,.jpeg,.png,.tif,.txt';
    FlutterFilePicker.postMessage(JSON.stringify({action: 'pick', accept: accept, multiple: inp.multiple || false}));
  }

  var origClick = HTMLInputElement.prototype.click;
  HTMLInputElement.prototype.click = function() {
    if (this.type === 'file') { requestPick(this); return; }
    return origClick.apply(this, arguments);
  };

  document.addEventListener('click', function(e) {
    if (_picking) return;
    var el = e.target;
    if (el.tagName === 'INPUT' && el.type === 'file') {
      e.preventDefault(); e.stopPropagation(); requestPick(el); return false;
    }
    var parent = el.closest('.zdforms-file, .zdforms-fileDragZone, label, button, [role="button"], .upload, .file-upload, [class*="upload"], [class*="file"]');
    if (parent) {
      var inp = parent.querySelector('input[type="file"]') || document.querySelector('input[type="file"]');
      if (inp) { e.preventDefault(); e.stopPropagation(); requestPick(inp); return false; }
    }
    var txt = (el.textContent || '').toLowerCase();
    if (txt.indexOf('datei') >= 0 || txt.indexOf('upload') >= 0 || txt.indexOf('auswählen') >= 0) {
      var inp = document.querySelector('input[type="file"]');
      if (inp) { e.preventDefault(); e.stopPropagation(); requestPick(inp); return false; }
    }
  }, true);
})();
''');
    } catch (_) {}
  }

  Future<void> _pickAndInjectFile() async {
    try {
      final result = await FilePickerHelper.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'tif', 'txt'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${result.files.length} Datei(en) werden angehängt...'), duration: const Duration(seconds: 2)));

      for (final file in result.files) {
        if (file.path == null) continue;
        final bytes = await File(file.path!).readAsBytes();
        final b64 = base64Encode(bytes);
        final ext = file.extension?.toLowerCase() ?? '';
        final mime = {'pdf': 'application/pdf', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'tif': 'image/tiff', 'txt': 'text/plain'}[ext] ?? 'application/octet-stream';
        final fileName = file.name.replaceAll("'", "\\'").replaceAll('\\', '\\\\');

        await _mobileController?.runJavaScript('''
(function() {
  var b64 = '$b64';
  var byteChars = atob(b64);
  var byteArray = new Uint8Array(byteChars.length);
  for (var i = 0; i < byteChars.length; i++) byteArray[i] = byteChars.charCodeAt(i);
  var blob = new Blob([byteArray], {type: '$mime'});
  var f = new File([blob], '$fileName', {type: '$mime'});
  var dt = new DataTransfer();
  dt.items.add(f);
  // Find file input and set files
  var inp = document.querySelector('input[type="file"]');
  if (inp) {
    inp.files = dt.files;
    inp.dispatchEvent(new Event('change', {bubbles: true}));
    inp.dispatchEvent(new Event('input', {bubbles: true}));
  }
  // Also try drag-drop zone
  var dropZone = document.querySelector('.zdforms-fileDragZone, [class*="drop"], [class*="upload"]');
  if (dropZone) {
    var dropEvent = new DragEvent('drop', {bubbles: true, dataTransfer: dt});
    dropZone.dispatchEvent(dropEvent);
  }
})();
''');
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Datei(en) angehängt'), backgroundColor: Colors.green));
    } catch (e) {
      debugPrint('[WebView] Pick and inject error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  Future<List<String>> _androidFilePicker(android_webview.FileSelectorParams params) async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: params.mode == android_webview.FileSelectorMode.openMultiple);
      if (result != null && result.files.isNotEmpty) {
        return result.files.where((f) => f.path != null).map((f) => File(f.path!).uri.toString()).toList();
      }
    } catch (e) {
      debugPrint('[WebView] Android file picker error: $e');
    }
    return [];
  }

  Future<void> _handleFilePickerRequest(String message) async {
    try {
      final data = jsonDecode(message);
      if (data['action'] != 'pick') return;

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'tif', 'txt'],
        allowMultiple: data['multiple'] == true,
      );
      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        if (file.path == null) continue;
        final bytes = await File(file.path!).readAsBytes();
        final b64 = base64Encode(bytes);
        final ext = file.extension?.toLowerCase() ?? '';
        final mime = {'pdf': 'application/pdf', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'tif': 'image/tiff', 'txt': 'text/plain'}[ext] ?? 'application/octet-stream';
        final fileName = file.name.replaceAll("'", "\\'");

        await _mobileController?.runJavaScript('''
(function() {
  var b64 = '$b64';
  var byteChars = atob(b64);
  var byteArray = new Uint8Array(byteChars.length);
  for (var i = 0; i < byteChars.length; i++) byteArray[i] = byteChars.charCodeAt(i);
  var blob = new Blob([byteArray], {type: '$mime'});
  var f = new File([blob], '$fileName', {type: '$mime'});
  var dt = new DataTransfer();
  dt.items.add(f);
  var inp = window._flutterFileInput;
  if (inp) {
    inp.files = dt.files;
    inp.dispatchEvent(new Event('change', {bubbles: true}));
    inp.dispatchEvent(new Event('input', {bubbles: true}));
  }
})();
''');
      }
    } catch (e) {
      debugPrint('[WebView] File picker error: $e');
    }
  }

  Future<void> _tryAutoFill() async {
    if (_autoFillDone) return;
    // Also try Go2Doc patient auto-fill
    _tryGo2DocAutoFill();
    // Custom JS injection
    _tryCustomJs();
    // File picker interceptor for macOS
    _injectFilePickerInterceptor();
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
      floatingActionButton: (widget.customJs != null && _mobileController != null) ? FloatingActionButton.extended(
        onPressed: _pickAndInjectFile,
        icon: const Icon(Icons.attach_file),
        label: const Text('Datei anhängen'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ) : null,
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
    } else if (Platform.isLinux) {
      // The page is now served by the host Chromium-Flatpak via CDP — this
      // screen is just a courtesy placeholder while ExternalBrowserService
      // launches and connects.
      if (_linuxBusy) {
        return const Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Chromium wird gestartet…'),
          ]),
        );
      }
      if (_linuxError != null) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.warning_amber, size: 48, color: Colors.orange.shade700),
            const SizedBox(height: 16),
            Text(_linuxError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _launchLinuxExternal,
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut versuchen'),
            ),
          ]),
        );
      }
      return const SizedBox.shrink();
    }

    // Fallback - should not reach here
    return const Center(
      child: Text('WebView nicht unterstützt auf dieser Plattform'),
    );
  }
}
