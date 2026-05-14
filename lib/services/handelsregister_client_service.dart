import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'http_client_factory.dart';

/// Direct client-side scraping of handelsregister.de.
/// Each user's desktop makes requests from their own IP,
/// avoiding server-side rate limiting.
class HandelsregisterClientService {
  static const String _baseUrl = 'https://www.handelsregister.de/rp_web';

  static final HandelsregisterClientService _instance =
      HandelsregisterClientService._internal();
  factory HandelsregisterClientService() => _instance;
  HandelsregisterClientService._internal();

  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';

  static const _knownGerichtCodes = {
    'memmingen': 'D2505',
    'münchen': 'R3101',
    'berlin': 'D1201',
    'hamburg': 'D2101',
    'stuttgart': 'D3101',
    'köln': 'R2103',
    'frankfurt': 'R2609',
  };

  // Session cache: after search(), reuse session for fast downloads (skip steps 1-3)
  String? _cachedResultsHtml;
  String? _cachedViewState;
  String? _cachedFormUrl;
  String? _cachedResultPageUrl;
  Map<String, String> _sessionCookies = {};
  DateTime? _sessionTime;
  static const _sessionMaxAge = Duration(minutes: 3);

  bool get _hasValidSession =>
      _cachedResultsHtml != null &&
      _cachedViewState != null &&
      _sessionTime != null &&
      DateTime.now().difference(_sessionTime!) < _sessionMaxAge;

  void _cacheSession(String html, String viewState, String formUrl, String resultPageUrl) {
    _cachedResultsHtml = html;
    _cachedViewState = viewState;
    _cachedFormUrl = formUrl;
    _cachedResultPageUrl = resultPageUrl;
    _sessionCookies = Map.from(_cookies);
    _sessionTime = DateTime.now();
    debugPrint('[HR-CLIENT] Session cached for fast document downloads');
  }

  void _clearSession() {
    _cachedResultsHtml = null;
    _cachedViewState = null;
    _cachedFormUrl = null;
    _cachedResultPageUrl = null;
    _sessionCookies.clear();
    _sessionTime = null;
  }

  /// Fresh HttpClient per operation (clean cookie jar each time).
  HttpClient _newSession() {
    return HttpClientFactory.createDefaultHttpClient(connectionTimeout: const Duration(seconds: 15))
      ..userAgent = _userAgent;
  }

  // ---------------------------------------------------------------------------
  // Public: search
  // ---------------------------------------------------------------------------

  /// Search handelsregister.de. Returns same structure as the old PHP API.
  Future<Map<String, dynamic>> search({
    String registerArt = 'HRB',
    String registerNummer = '',
    String registerGericht = '',
    String schlagwoerter = '',
  }) async {
    _cookies.clear();
    final client = _newSession();
    try {
      // Step 1: GET welcome page → ViewState
      debugPrint('[HR-CLIENT] Step 1: GET welcome.xhtml');
      final html1 = await _get(client, '$_baseUrl/welcome.xhtml');
      debugPrint('[HR-CLIENT] Step 1 OK, html length: ${html1.length}');
      final vs1 = _extractViewState(html1);
      if (vs1 == null) {
        debugPrint('[HR-CLIENT] Step 1 FAILED: no ViewState');
        return _err('Handelsregister nicht erreichbar');
      }
      debugPrint('[HR-CLIENT] Step 1 ViewState: ${vs1.substring(0, vs1.length > 30 ? 30 : vs1.length)}...');

      // Small delay between steps (simulate human browsing)
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 2: POST navigate to erweiterte Suche
      debugPrint('[HR-CLIENT] Step 2: POST navigate to erweiterte Suche');
      final welcomeUrl = '$_baseUrl/welcome.xhtml';
      final html2 = await _post(client, welcomeUrl, {
        'naviForm': 'naviForm',
        'naviForm:erweiterteSucheLink': 'naviForm:erweiterteSucheLink',
        'javax.faces.ViewState': vs1,
      }, referer: welcomeUrl);
      debugPrint('[HR-CLIENT] Step 2 OK, html length: ${html2.length}');
      final vs2 = _extractViewState(html2);
      if (vs2 == null) {
        debugPrint('[HR-CLIENT] Step 2 FAILED: no ViewState');
        return _err('Navigation zur Suche fehlgeschlagen');
      }

      // Resolve Gericht code from dropdown
      final gerichtCode = _resolveGerichtCode(html2, registerGericht);
      debugPrint('[HR-CLIENT] Gericht: "$registerGericht" → code: "$gerichtCode"');

      await Future.delayed(const Duration(milliseconds: 500));

      // Step 3: POST search (use _postRaw to capture redirect URL for session cache)
      final sucheUrl = '$_baseUrl/erweitertesuche/welcome.xhtml';
      debugPrint('[HR-CLIENT] Step 3: POST search (art=$registerArt, nr=$registerNummer, gericht=$gerichtCode, schlagwoerter=$schlagwoerter)');
      final resp3 = await _postRaw(client, sucheUrl, {
        'form': 'form',
        'form:registerNummer': registerNummer,
        'form:registerArt_input': registerArt,
        'form:registergericht_input': gerichtCode,
        'form:schlagwoerter': schlagwoerter,
        'form:schlagwortOptionen': '1',
        'form:btnSuche': 'Suchen',
        'javax.faces.ViewState': vs2,
      }, extraHeaders: {'Referer': sucheUrl});
      _storeCookies(resp3);
      String resultUrl = sucheUrl;
      String html3;
      if (resp3.statusCode == 301 || resp3.statusCode == 302 || resp3.statusCode == 303) {
        final location = resp3.headers.value('location');
        await _readBytes(resp3);
        if (location != null) {
          resultUrl = Uri.parse(sucheUrl).resolve(location).toString();
          html3 = await _get(client, resultUrl, referer: sucheUrl);
        } else {
          html3 = '';
        }
      } else {
        html3 = await _readString(resp3);
      }
      debugPrint('[HR-CLIENT] Step 3 OK, html length: ${html3.length}');

      // Cache session for fast document downloads (skip steps 1-3 next time)
      final vs3 = _extractViewState(html3);
      if (vs3 != null) {
        final doc3 = html_parser.parse(html3);
        final form3 = doc3.querySelector('form#ergebnissForm');
        if (form3 != null) {
          final formAction = form3.attributes['action'] ?? '';
          final formUrl = 'https://www.handelsregister.de$formAction';
          _cacheSession(html3, vs3, formUrl, resultUrl);
        }
      }

      final entries = _parseSearchResults(html3);
      debugPrint('[HR-CLIENT] Parsed ${entries.length} entries');
      return {
        'success': true,
        'data': {
          'register_data': {
            'entries': entries,
            'total': entries.length,
          }
        }
      };
    } catch (e) {
      debugPrint('[HR-CLIENT] EXCEPTION: $e');
      return _err('$e');
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Public: downloadDocument
  // ---------------------------------------------------------------------------

  /// Download a document (AD, CD, SI, DK, UT, VÖ).
  /// Returns raw PDF bytes (no base64).
  /// Uses cached session from search() when available (skips steps 1-3).
  Future<Map<String, dynamic>> downloadDocument({
    String registerArt = 'VR',
    required String registerNummer,
    String registerGericht = '',
    required String documentType,
  }) async {
    // Try fast path: reuse cached session from search()
    if (_hasValidSession) {
      debugPrint('[HR-CLIENT-DL] Using cached session for $documentType');
      final result = await _downloadWithCachedSession(documentType, registerArt, registerNummer);
      if (result != null) return result;
      debugPrint('[HR-CLIENT-DL] Cached session expired, doing full flow');
      _clearSession();
    }

    // Full flow: steps 1-4
    return _downloadFull(
      registerArt: registerArt,
      registerNummer: registerNummer,
      registerGericht: registerGericht,
      documentType: documentType,
    );
  }

  /// Fast download using cached session (step 4 only).
  /// Returns null if cache is invalid → caller falls back to full flow.
  Future<Map<String, dynamic>?> _downloadWithCachedSession(
    String documentType, String registerArt, String registerNummer,
  ) async {
    try {
      // Restore cookies from cached session
      _cookies.clear();
      _cookies.addAll(_sessionCookies);
      final client = _newSession();
      try {
        // Parse document link from cached results HTML
        final doc = html_parser.parse(_cachedResultsHtml!);
        final rows = doc.querySelectorAll('table[role="grid"] tr[data-ri]');
        if (rows.isEmpty) return null;

        final links = rows.first.querySelectorAll('a.dokumentList');
        String? docOnclick;
        for (final link in links) {
          final onclick = link.attributes['onclick'] ?? '';
          if (onclick.contains('Dokumentart.$documentType')) {
            docOnclick = onclick;
            break;
          }
        }
        if (docOnclick == null) {
          return _err("Dokumenttyp '$documentType' nicht verfügbar");
        }

        final params = _parseOnclickParams(docOnclick);
        if (params == null) return null;
        params['ergebnissForm'] = 'ergebnissForm';
        params['javax.faces.ViewState'] = _cachedViewState!;

        // Step 4 directly (no delay needed)
        debugPrint('[HR-CLIENT-DL] FAST Step 4: POST download $documentType');
        var resp4 = await _postRaw(client, _cachedFormUrl!, params, extraHeaders: {
          'Referer': _cachedResultPageUrl!,
          'Origin': 'https://www.handelsregister.de',
        });
        _storeCookies(resp4);

        String effectiveUrl = _cachedFormUrl!;
        if (resp4.statusCode == 301 || resp4.statusCode == 302 || resp4.statusCode == 303) {
          final location = resp4.headers.value('location');
          await _readBytes(resp4);
          if (location != null) {
            effectiveUrl = Uri.parse(_cachedFormUrl!).resolve(location).toString();
            debugPrint('[HR-CLIENT-DL] FAST redirect → $effectiveUrl');
            final getReq = await client.getUrl(Uri.parse(effectiveUrl));
            _applyCookies(getReq);
            getReq.headers.set('Accept', '*/*');
            resp4 = await getReq.close();
          }
        }

        // Check if session expired (redirected to error/timeout page)
        if (effectiveUrl.contains('cstimeout') || effectiveUrl.contains('error')) {
          return null; // fall back to full flow
        }

        final bytes = await _readBytes(resp4);
        if (bytes.isEmpty) return null;

        final isPdf = (bytes.length >= 4 &&
                bytes[0] == 0x25 && bytes[1] == 0x50 &&
                bytes[2] == 0x44 && bytes[3] == 0x46) ||
            (resp4.headers.contentType?.mimeType.contains('pdf') ?? false) ||
            (resp4.headers.contentType?.mimeType.contains('octet') ?? false);

        if (!isPdf) return null; // fall back to full flow

        final fileName = 'Handelsregister_${registerArt}_${registerNummer}_$documentType.pdf';
        debugPrint('[HR-CLIENT-DL] FAST download OK: ${bytes.length} bytes');
        return {
          'success': true,
          'data': {'bytes': bytes, 'document_name': fileName}
        };
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[HR-CLIENT-DL] Cached session error: $e');
      return null; // fall back to full flow
    }
  }

  /// Full 4-step download (steps 1-4).
  Future<Map<String, dynamic>> _downloadFull({
    required String registerArt,
    required String registerNummer,
    required String registerGericht,
    required String documentType,
  }) async {
    _cookies.clear();
    final client = _newSession();
    try {
      // Step 1
      debugPrint('[HR-CLIENT-DL] Step 1: GET welcome');
      final welcomeUrl = '$_baseUrl/welcome.xhtml';
      final html1 = await _get(client, welcomeUrl);
      final vs1 = _extractViewState(html1);
      if (vs1 == null) return _err('Handelsregister nicht erreichbar');

      await Future.delayed(const Duration(milliseconds: 300));

      // Step 2
      debugPrint('[HR-CLIENT-DL] Step 2: POST navigate to erweiterte Suche');
      final html2 = await _post(client, welcomeUrl, {
        'naviForm': 'naviForm',
        'naviForm:erweiterteSucheLink': 'naviForm:erweiterteSucheLink',
        'javax.faces.ViewState': vs1,
      }, referer: welcomeUrl);
      final vs2 = _extractViewState(html2);
      if (vs2 == null) return _err('Navigation zur Suche fehlgeschlagen');

      final gerichtCode = _resolveGerichtCode(html2, registerGericht);

      await Future.delayed(const Duration(milliseconds: 300));

      // Step 3
      debugPrint('[HR-CLIENT-DL] Step 3: POST search');
      final step3Url = '$_baseUrl/erweitertesuche/welcome.xhtml';
      final resp3 = await _postRaw(
        client,
        step3Url,
        {
          'form': 'form',
          'form:registerNummer': registerNummer,
          'form:registerArt_input': registerArt,
          'form:registergericht_input': gerichtCode,
          'form:schlagwoerter': '',
          'form:schlagwortOptionen': '1',
          'form:btnSuche': 'Suchen',
          'javax.faces.ViewState': vs2,
        },
        extraHeaders: {'Referer': step3Url},
      );

      _storeCookies(resp3);
      String resultUrl = step3Url;
      String html3;
      if (resp3.statusCode == 301 || resp3.statusCode == 302 || resp3.statusCode == 303) {
        final location = resp3.headers.value('location');
        await _readBytes(resp3);
        if (location != null) {
          resultUrl = Uri.parse(step3Url).resolve(location).toString();
          debugPrint('[HR-CLIENT-DL] Step 3 redirect → $resultUrl');
          html3 = await _get(client, resultUrl, referer: step3Url);
        } else {
          html3 = '';
        }
      } else {
        html3 = await _readString(resp3);
      }
      debugPrint('[HR-CLIENT-DL] Step 3 html length: ${html3.length}');

      if (resultUrl.contains('cstimeout')) {
        return _err('Zu viele Anfragen. Bitte später erneut versuchen.');
      }
      if (resultUrl.contains('error')) {
        return _err('Session-Fehler. Bitte erneut versuchen.');
      }

      final vs3 = _extractViewState(html3);
      if (vs3 == null) return _err('Keine Ergebnisse gefunden');

      // Cache this session for subsequent downloads
      final doc = html_parser.parse(html3);
      final form = doc.querySelector('form#ergebnissForm');
      if (form == null) return _err('Keine Ergebnisse gefunden');
      final formAction = form.attributes['action'] ?? '';
      final formUrl = 'https://www.handelsregister.de$formAction';
      _cacheSession(html3, vs3, formUrl, resultUrl);

      // Find result rows
      final rows = doc.querySelectorAll('table[role="grid"] tr[data-ri]');
      if (rows.isEmpty) return _err('Keine Ergebnisse gefunden');

      // Find document link
      final links = rows.first.querySelectorAll('a.dokumentList');
      String? docOnclick;
      for (final link in links) {
        final onclick = link.attributes['onclick'] ?? '';
        if (onclick.contains('Dokumentart.$documentType')) {
          docOnclick = onclick;
          break;
        }
      }
      if (docOnclick == null) {
        return _err("Dokumenttyp '$documentType' nicht verfügbar");
      }

      final params = _parseOnclickParams(docOnclick);
      if (params == null) {
        return _err('Dokument-Link konnte nicht gelesen werden');
      }
      params['ergebnissForm'] = 'ergebnissForm';
      params['javax.faces.ViewState'] = vs3;

      await Future.delayed(const Duration(milliseconds: 500));

      // Step 4: Download document
      debugPrint('[HR-CLIENT-DL] Step 4: POST download $documentType');
      var resp4 = await _postRaw(
        client,
        formUrl,
        params,
        extraHeaders: {
          'Referer': resultUrl,
          'Origin': 'https://www.handelsregister.de',
        },
      );

      String effectiveUrl4 = formUrl;
      if (resp4.statusCode == 301 || resp4.statusCode == 302 || resp4.statusCode == 303) {
        final location = resp4.headers.value('location');
        await _readBytes(resp4);
        if (location != null) {
          effectiveUrl4 = Uri.parse(formUrl).resolve(location).toString();
          debugPrint('[HR-CLIENT-DL] Step 4 redirect → $effectiveUrl4');
          final getReq = await client.getUrl(Uri.parse(effectiveUrl4));
          _applyCookies(getReq);
          getReq.headers.set('Accept', '*/*');
          resp4 = await getReq.close();
        }
      }

      final bytes = await _readBytes(resp4);
      final contentType = resp4.headers.contentType?.mimeType ?? '';

      if (effectiveUrl4.contains('cstimeout')) {
        return _err('Zu viele Anfragen. Bitte später erneut versuchen.');
      }
      if (bytes.isEmpty) {
        return _err('Leere Antwort vom Server');
      }

      final isPdf = (bytes.length >= 4 &&
              bytes[0] == 0x25 && bytes[1] == 0x50 &&
              bytes[2] == 0x44 && bytes[3] == 0x46) ||
          contentType.contains('pdf') ||
          contentType.contains('octet');

      if (!isPdf) {
        return _err('Kein PDF erhalten (${bytes.length} bytes, $contentType)');
      }

      final fileName =
          'Handelsregister_${registerArt}_${registerNummer}_$documentType.pdf';
      return {
        'success': true,
        'data': {
          'bytes': bytes,
          'document_name': fileName,
        }
      };
    } catch (e) {
      return _err('Download fehlgeschlagen: $e');
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // HTTP helpers — explicit cookie management
  // ---------------------------------------------------------------------------

  /// Manual cookie jar: cookies[name] = value
  final Map<String, String> _cookies = {};

  void _storeCookies(HttpClientResponse response) {
    for (final cookie in response.cookies) {
      _cookies[cookie.name] = cookie.value;
    }
    if (_cookies.isNotEmpty) {
      debugPrint('[HR-CLIENT] Cookies: ${_cookies.keys.join(', ')}');
    }
  }

  void _applyCookies(HttpClientRequest request) {
    if (_cookies.isNotEmpty) {
      final cookieStr = _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
      request.headers.set('Cookie', cookieStr);
    }
  }

  Future<String> _get(HttpClient client, String url, {String? referer, int retries = 2}) async {
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final request = await client.getUrl(Uri.parse(url));
        _applyCookies(request);
        request.headers.set('Accept',
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
        request.headers.set('Accept-Language', 'de-DE,de;q=0.9,en;q=0.8');
        if (referer != null) {
          request.headers.set('Referer', referer);
        }
        final response = await request.close();
        _storeCookies(response);
        return _readString(response);
      } on HttpException {
        if (attempt < retries) {
          debugPrint('[HR-CLIENT] GET retry ${attempt + 1}/$retries for $url');
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
        rethrow;
      }
    }
    throw const HttpException('Max retries exceeded');
  }

  Future<String> _post(
    HttpClient client,
    String url,
    Map<String, String> fields, {
    String? referer,
  }) async {
    final response = await _postRaw(client, url, fields,
        extraHeaders: referer != null ? {'Referer': referer} : null);
    _storeCookies(response);
    // Follow redirect manually: POST→302→GET at Location
    if (response.isRedirect ||
        response.statusCode == 301 ||
        response.statusCode == 302 ||
        response.statusCode == 303) {
      final location = response.headers.value('location');
      await _readBytes(response); // drain the body
      if (location != null) {
        final redirectUrl = Uri.parse(url).resolve(location).toString();
        debugPrint('[HR-CLIENT] POST redirect → GET $redirectUrl');
        return _get(client, redirectUrl, referer: url);
      }
    }
    return _readString(response);
  }

  Future<HttpClientResponse> _postRaw(
    HttpClient client,
    String url,
    Map<String, String> fields, {
    Map<String, String>? extraHeaders,
  }) async {
    final request = await client.postUrl(Uri.parse(url));
    request.followRedirects = false; // handle redirects manually
    _applyCookies(request);
    request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
    request.headers.set('Accept',
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    request.headers.set('Accept-Language', 'de-DE,de;q=0.9,en;q=0.8');
    if (extraHeaders != null) {
      extraHeaders.forEach((k, v) => request.headers.set(k, v));
    }

    final body = fields.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    request.write(body);
    return request.close();
  }

  Future<String> _readString(HttpClientResponse response) async {
    final bytes = await _readBytes(response);
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<Uint8List> _readBytes(HttpClientResponse response) async {
    final builder = BytesBuilder();
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  // ---------------------------------------------------------------------------
  // Parsing helpers
  // ---------------------------------------------------------------------------

  String? _extractViewState(String html) {
    // Regex approach (faster than full DOM parse for this)
    final m = RegExp(r'name="javax\.faces\.ViewState"[^>]*value="([^"]+)"')
        .firstMatch(html);
    if (m != null) return m.group(1);
    final m2 = RegExp(r'id="javax\.faces\.ViewState"[^>]*value="([^"]+)"')
        .firstMatch(html);
    return m2?.group(1);
  }

  String _resolveGerichtCode(String html, String gerichtName) {
    if (gerichtName.isEmpty) return '';

    // Parse dropdown from HTML
    final selectMatch = RegExp(
      r'<select[^>]*id="form:registergericht_input"[^>]*>(.*?)</select>',
      dotAll: true,
    ).firstMatch(html);

    if (selectMatch != null) {
      final optMatches = RegExp(r'<option[^>]*value="([^"]*)"[^>]*>([^<]*)</option>')
          .allMatches(selectMatch.group(1)!);
      for (final opt in optMatches) {
        if (opt.group(2)!.toLowerCase().contains(gerichtName.toLowerCase())) {
          return opt.group(1)!;
        }
      }
    }

    // Fallback known codes
    return _knownGerichtCodes[gerichtName.toLowerCase()] ?? '';
  }

  List<Map<String, dynamic>> _parseSearchResults(String html) {
    final doc = html_parser.parse(html);
    final entries = <Map<String, dynamic>>[];

    // Result rows: table[role="grid"] tr[data-ri]
    final rows = doc.querySelectorAll('table[role="grid"] tr[data-ri]');
    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 5) continue;

      // Cell structure: [0]=combined, [1]=Gericht+Register, [2]=Name, [3]=Sitz, [4]=Status
      final gerichtField = _clean(cells[1].text);
      final entry = <String, dynamic>{
        'gericht': gerichtField,
        'name': _clean(cells[2].text),
        'sitz': _clean(cells[3].text),
        'status': _clean(cells[4].text),
      };

      // Parse: "Bayern Amtsgericht Memmingen VR 201335"
      final m = RegExp(r'^(\S+)\s+(.+?)\s+(VR|HRA|HRB|GnR|PR|GsR)\s+(\d+)$')
          .firstMatch(gerichtField);
      if (m != null) {
        entry['bundesland'] = m.group(1);
        entry['register_gericht'] = m.group(2);
        entry['register_art'] = m.group(3);
        entry['register_nummer'] = '${m.group(3)} ${m.group(4)}';
      }

      entries.add(entry);
    }
    return entries;
  }

  Map<String, String>? _parseOnclickParams(String onclick) {
    // Pattern: addSubmitParam('ergebnissForm',{'key1':'val1','key2':'val2'})
    final m =
        RegExp(r"addSubmitParam\('ergebnissForm',\{(.+?)\}\)").firstMatch(onclick);
    if (m == null) return null;

    final params = <String, String>{};
    final pairs = RegExp(r"'([^']+)'\s*:\s*'([^']*)'").allMatches(m.group(1)!);
    for (final pair in pairs) {
      params[pair.group(1)!] = pair.group(2)!;
    }
    return params.isEmpty ? null : params;
  }

  String _clean(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');

  Map<String, dynamic> _err(String message) =>
      {'success': false, 'message': message};
}
