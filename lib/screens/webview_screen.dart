import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/platform_service.dart';
import '../utils/file_picker_helper.dart';

// Platform-specific imports
import 'package:webview_flutter/webview_flutter.dart' as mobile_webview;
import 'package:webview_flutter_android/webview_flutter_android.dart' as android_webview;

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
          // Angular SPA routes change the URL without firing navigationCompleted.
          // Re-kick the go2doc filler so newly-mounted form inputs get filled.
          _tryGo2DocAutoFill();
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


  /// Inject Go2Doc patient form auto-fill. Safe to call repeatedly — the JS
  /// installs itself once per window via `window.__icdGo2DocFiller`; subsequent
  /// calls just `kick()` to re-fill any newly appeared inputs.
  Future<void> _tryGo2DocAutoFill() async {
    if (widget.go2docAutoFill == null || widget.go2docAutoFill!.isEmpty) return;
    final d = widget.go2docAutoFill!;
    final vorname = (d['vorname'] ?? '').replaceAll("'", "\\'");
    final nachname = (d['nachname'] ?? '').replaceAll("'", "\\'");
    final gebTag = d['geb_tag'] ?? '';
    final gebMonat = d['geb_monat'] ?? '';
    final gebJahr = d['geb_jahr'] ?? '';
    // Go2Doc: try multiple date formats depending on input type
    final gebDatumISO = (gebTag.isNotEmpty && gebMonat.isNotEmpty && gebJahr.isNotEmpty)
        ? '$gebJahr-${gebMonat.padLeft(2, '0')}-${gebTag.padLeft(2, '0')}'
        : '';
    final gebDatumDE = (gebTag.isNotEmpty && gebMonat.isNotEmpty && gebJahr.isNotEmpty)
        ? '${gebTag.padLeft(2, '0')}.${gebMonat.padLeft(2, '0')}.$gebJahr'
        : '';
    final gebDatumSlash = (gebTag.isNotEmpty && gebMonat.isNotEmpty && gebJahr.isNotEmpty)
        ? '${gebMonat.padLeft(2, '0')}/${gebTag.padLeft(2, '0')}/$gebJahr'
        : '';
    final email = (d['email'] ?? 'icd@icd360s.de').replaceAll("'", "\\'");
    final versicherung = d['versicherung'] ?? 'gesetzlich';

    // Persistent self-installing filler: injects ONCE, then watches the DOM
    // forever via MutationObserver (handles Angular SPA route changes where
    // the form appears after the user clicks "Termin vereinbaren") and also
    // polls every second for up to 5 minutes as a fallback.
    final js = '''
(function() {
  if (window.__icdGo2DocFiller) { window.__icdGo2DocFiller.kick(); return 'already-installed'; }

  var d = {
    vorname: '$vorname',
    nachname: '$nachname',
    gebTag: '$gebTag',
    gebMonat: '$gebMonat',
    gebJahr: '$gebJahr',
    gebISO: '$gebDatumISO',
    gebDE: '$gebDatumDE',
    gebSlash: '$gebDatumSlash',
    email: '$email',
    versicherung: '$versicherung'
  };

  function setVal(el, val) {
    if (!el) return false;
    try {
      var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
      if (setter) setter.call(el, val);
      else el.value = val;
      el.dispatchEvent(new Event('input', {bubbles: true}));
      el.dispatchEvent(new Event('change', {bubbles: true}));
      el.dispatchEvent(new KeyboardEvent('keyup', {bubbles: true}));
      el.dispatchEvent(new Event('blur', {bubbles: true}));
      return true;
    } catch(e) { return false; }
  }
  function setSelect(el, val) {
    if (!el) return false;
    var v = (val || '').toLowerCase();
    for (var i = 0; i < el.options.length; i++) {
      var opt = el.options[i];
      if ((opt.value || '').toLowerCase() == v || (opt.text || '').toLowerCase().indexOf(v) >= 0) {
        el.selectedIndex = i;
        el.dispatchEvent(new Event('change', {bubbles: true}));
        return true;
      }
    }
    return false;
  }
  function labelFor(el) {
    if (!el.id) return '';
    var l = document.querySelector('label[for="' + el.id + '"]');
    return l ? (l.textContent || '').toLowerCase() : '';
  }

  function tryFill() {
    var inputs = document.querySelectorAll('input, select, textarea');
    var filled = 0;
    for (var el of inputs) {
      if (el.dataset.__icdFilled === '1') continue;        // skip already filled
      var ph = (el.placeholder || '').toLowerCase();
      var nm = (el.name || '').toLowerCase();
      var id = (el.id || '').toLowerCase();
      var lbl = labelFor(el);
      var hay = ph + ' ' + nm + ' ' + id + ' ' + lbl;
      var didFill = false;

      if (/vorname|firstname|first.name/.test(hay) && d.vorname) {
        didFill = setVal(el, d.vorname);
      } else if (/nachname|lastname|surname|last.name|family.name/.test(hay) && d.nachname) {
        didFill = setVal(el, d.nachname);
      } else if (el.tagName === 'SELECT' && /\\btag\\b/.test(hay) && d.gebTag) {
        // Split day-of-month dropdown (common in German medical forms)
        didFill = setSelect(el, d.gebTag);
      } else if (el.tagName === 'SELECT' && /\\bmonat\\b/.test(hay) && d.gebMonat) {
        didFill = setSelect(el, d.gebMonat);
      } else if (el.tagName === 'SELECT' && /\\bjahr\\b/.test(hay) && d.gebJahr) {
        didFill = setSelect(el, d.gebJahr);
      } else if (/geburtsdatum|geburtstag|birth.?date|geburt|dob/.test(hay) && d.gebISO) {
        if (el.type === 'date') didFill = setVal(el, d.gebISO);
        else didFill = setVal(el, d.gebDE) || setVal(el, d.gebSlash) || setVal(el, d.gebISO);
      } else if ((el.type === 'email' || /e.?mail/.test(hay)) && d.email) {
        didFill = setVal(el, d.email);
      } else if (el.tagName === 'SELECT' && /versicher|kranken|kassenart|insurance/.test(hay) && d.versicherung) {
        didFill = setSelect(el, d.versicherung);
      } else if (/(^| )name( |\$)/.test(hay) && d.nachname && !el.value) {
        // Fallback: very generic input named just "name" (no firstname/vorname/email markers)
        // Only fire if the field is empty to avoid clobbering separate firstname inputs
        didFill = setVal(el, d.nachname);
      }

      if (didFill) { el.dataset.__icdFilled = '1'; filled++; }
    }

    // Fallback: hunt Geburtsdatum by scanning labels in Angular forms
    if (d.gebDE) {
      var labels = document.querySelectorAll('label');
      for (var lb of labels) {
        var t = (lb.textContent || '').trim().toLowerCase();
        if (t.indexOf('geburtsdatum') >= 0 || t.indexOf('geburtstag') >= 0) {
          var container = lb.closest('.form-group') || lb.closest('div') || lb.parentElement;
          if (container) {
            var inp = container.querySelector('input');
            if (inp && !inp.value && inp.dataset.__icdFilled !== '1') {
              var v = inp.type === 'date' ? d.gebISO : d.gebDE;
              if (setVal(inp, v)) { inp.dataset.__icdFilled = '1'; filled++; }
            }
          }
        }
      }
    }

    // Auto-check Einwilligung / Datenschutz / Go2Doc consent
    var checkboxes = document.querySelectorAll('input[type="checkbox"]');
    for (var cb of checkboxes) {
      if (cb.dataset.__icdFilled === '1') continue;
      var parent = cb.closest('label') || cb.parentElement;
      var txt = parent ? (parent.textContent || '').toLowerCase() : '';
      if (/willige ein|einwillig|datenschutz|go2doc|akzeptier/.test(txt)) {
        if (!cb.checked) { cb.click(); cb.dataset.__icdFilled = '1'; filled++; }
      }
    }

    return filled;
  }

  var totalFilled = 0;
  var pollCount = 0;
  var pollMax = 300; // 5 minutes of 1-second polls

  function kick() {
    var n = tryFill();
    totalFilled += n;
    if (n > 0) { try { console.log('[ICD-Autofill] +' + n + ' fields (total: ' + totalFilled + ')'); } catch(e) {} }
  }

  // 1) Run now (form may already be on the page).
  kick();

  // 2) Watch DOM mutations — fires immediately when Angular swaps the route
  //    (Termin vereinbaren button → patient form), no page reload needed.
  try {
    var observer = new MutationObserver(function(mutations) {
      // Cheap throttle: only kick if at least one mutation actually added nodes
      var dirty = false;
      for (var m of mutations) {
        if (m.addedNodes && m.addedNodes.length > 0) { dirty = true; break; }
      }
      if (dirty) kick();
    });
    observer.observe(document.documentElement, {childList: true, subtree: true});
  } catch(e) {}

  // 3) Fallback poll — slow heartbeat for cases where MutationObserver misses
  //    (e.g., inputs get a new attribute but no node-add).
  var pollTimer = setInterval(function() {
    pollCount++;
    kick();
    if (pollCount >= pollMax) clearInterval(pollTimer);
  }, 1000);

  window.__icdGo2DocFiller = { kick: kick, totalFilled: function() { return totalFilled; } };
  return 'installed';
})();
''';

    // Inject the JS. It's safe to call repeatedly — the JS guards on
    // `window.__icdGo2DocFiller` and just `kick()`s on re-installation calls.
    try {
      if (_mobileController != null) {
        await _mobileController!.runJavaScriptReturningResult(js);
      } else if (_windowsController != null) {
        await _windowsController!.executeScript(js);
      }
      debugPrint('[WebView] Go2Doc filler installed (self-polling + MutationObserver)');
    } catch (e) {
      debugPrint('[WebView] Go2Doc filler install error: $e');
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
    }

    // Fallback - should not reach here
    return const Center(
      child: Text('WebView nicht unterstützt auf dieser Plattform'),
    );
  }
}
