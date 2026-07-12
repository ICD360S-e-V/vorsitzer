import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';
import 'notification_service.dart';

/// Active disruption fetched from a public transit feed.
class TransitDisruption {
  final String id;
  final String headline;
  final String? text;
  final DateTime? validFrom;
  final DateTime? validUntil;
  /// "HIGH" / "MEDIUM" / "LOW" — from bahn.de priority; heuristic if missing.
  final String priority;
  /// Comma-separated list of affected products or lines, e.g. "S1, IC 2013".
  final String? affected;
  /// 2026-07-13: source tag pentru adapter pattern (research confirmat
  /// că unified list + source badge e best-practice — Öffi/bahn.expert/
  /// DB Navigator, https://gitlab.com/oeffi/public-transport-enabler).
  /// "HIM" = bahn.de HIM (national rail)
  /// "EFA" = XSLT_ADDINFO_REQUEST (local EFA providers)
  /// "HAFAS" = HimSearch (local HAFAS providers)
  final String source;
  /// providerId pentru filter în UI (ex. "ding", "vvs", "mvv", "hvv").
  final String? providerId;

  const TransitDisruption({
    required this.id,
    required this.headline,
    this.text,
    this.validFrom,
    this.validUntil,
    this.priority = 'MEDIUM',
    this.affected,
    this.source = 'HIM',
    this.providerId,
  });

  bool get isHigh => priority.toUpperCase() == 'HIGH';
}

/// Fetches active traffic disruptions from bahn.de's public
/// `reiseloesung/verkehrsmeldungen` endpoint and exposes them as a badge
/// count + list. Refresh runs every 15 minutes; single-shot fetches are
/// cached for 5 minutes to avoid dashboard spam.
class TransitDisruptionsService extends ChangeNotifier {
  static final TransitDisruptionsService _instance = TransitDisruptionsService._();
  factory TransitDisruptionsService() => _instance;
  TransitDisruptionsService._();

  static const _url = 'https://www.bahn.de/web/api/reiseloesung/verkehrsmeldungen';
  static const _refresh = Duration(minutes: 15);
  static const _cacheTtl = Duration(minutes: 5);
  static const _kPrefsBypassKey = 'opnv.disruption.bypass_region';
  // 2026-07-12 Sprint 1: push notification pentru HIM HIGH
  // Match e pe region tokens (deja setat de dashboard). Nu spam-uim — ID-urile
  // deja notificate sunt persistate ca să nu re-notificăm după restart.
  static const _kPrefsPushEnabledKey = 'opnv.disruption.push_enabled';
  static const _kPrefsNotifiedIdsKey = 'opnv.disruption.notified_ids';
  static const _maxNotifiedIds = 200;

  final _log = LoggerService();
  final http.Client _client = IOClient(HttpClientFactory.createDefaultHttpClient());

  List<TransitDisruption> _disruptions = [];
  DateTime? _lastFetch;
  Timer? _timer;

  /// When non-empty, only disruptions whose headline+text+affected mention
  /// one of these tokens (lowercased substring match) are counted / shown.
  /// Tokens come from user's Stufe-1-Adresse (city, bundesland), current GPS
  /// city, and active transit provider name.
  ///
  /// Empty set → national mode: everything is shown (fallback while profile
  /// still loading).
  final Set<String> _regionTokens = {};

  /// When true, the region filter is bypassed and every active nationwide
  /// disruption is surfaced. Persisted via SharedPreferences so the toggle
  /// survives app restarts.
  bool _bypassRegionFilter = false;
  bool _bypassLoaded = false;
  bool get bypassRegionFilter => _bypassRegionFilter;
  set bypassRegionFilter(bool v) {
    if (v == _bypassRegionFilter) return;
    _bypassRegionFilter = v;
    notifyListeners();
    // Fire-and-forget persistence.
    SharedPreferences.getInstance().then((sp) => sp.setBool(_kPrefsBypassKey, v));
  }

  /// When true, push notifications are shown when a new HIGH priority
  /// disruption matches the user's region tokens. Off by default (privacy).
  bool _pushEnabled = false;
  bool get pushEnabled => _pushEnabled;
  set pushEnabled(bool v) {
    if (v == _pushEnabled) return;
    _pushEnabled = v;
    notifyListeners();
    SharedPreferences.getInstance().then((sp) => sp.setBool(_kPrefsPushEnabledKey, v));
  }

  /// IDs deja notificate (persistate) — nu re-notificăm după restart.
  final Set<String> _notifiedIds = {};
  bool _notifiedIdsLoaded = false;

  /// One-shot load from SharedPreferences on service start.
  Future<void> _loadBypass() async {
    if (_bypassLoaded) return;
    _bypassLoaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getBool(_kPrefsBypassKey) ?? false;
      if (v != _bypassRegionFilter) {
        _bypassRegionFilter = v;
        notifyListeners();
      }
      _pushEnabled = sp.getBool(_kPrefsPushEnabledKey) ?? false;
      if (!_notifiedIdsLoaded) {
        _notifiedIdsLoaded = true;
        final ids = sp.getStringList(_kPrefsNotifiedIdsKey) ?? const [];
        _notifiedIds.addAll(ids);
      }
    } catch (_) {}
  }

  Future<void> _persistNotifiedIds() async {
    try {
      final sp = await SharedPreferences.getInstance();
      // Trim la _maxNotifiedIds cele mai vechi la append (FIFO natural via Set → List).
      final list = _notifiedIds.toList();
      if (list.length > _maxNotifiedIds) {
        list.removeRange(0, list.length - _maxNotifiedIds);
        _notifiedIds..clear()..addAll(list);
      }
      await sp.setStringList(_kPrefsNotifiedIdsKey, list);
    } catch (_) {}
  }

  /// Replace the region-token set. Called by dashboard once user profile
  /// (Verifizierung Stufe 1 = strasse/plz/ort/bundesland from user_details.php)
  /// AND GPS reverse-geocode are both resolved.
  ///
  /// Tokens shorter than 4 chars are dropped — a token like "ding" would
  /// match "bindung" / "verbindung" / "erledigung" as substring and let
  /// most nationwide disruption spam through the filter.
  void setRegionTokens(Iterable<String> tokens) {
    final normalized = tokens
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.length >= 4)
        .toSet();
    if (setEquals(normalized, _regionTokens)) return;
    _regionTokens
      ..clear()
      ..addAll(normalized);
    _log.info('Disruptions: region tokens set to ${_regionTokens.join(", ")}', tag: 'DISRUPT');
    notifyListeners();
  }

  /// Full nationwide list (unfiltered) — used by "Auch bundesweit anzeigen".
  List<TransitDisruption> get allDisruptions => List.unmodifiable(_disruptions);
  int get allCount => _disruptions.length;

  /// Filtered, ranked list (region-relevant first if filter active).
  List<TransitDisruption> get disruptions {
    if (_bypassRegionFilter || _regionTokens.isEmpty) {
      return List.unmodifiable(_disruptions);
    }
    return List.unmodifiable(_disruptions.where(_matchesRegion));
  }

  int get count => disruptions.length;
  int get highPriorityCount => disruptions.where((d) => d.isHigh).length;
  DateTime? get lastFetch => _lastFetch;

  /// Return the currently active disruptions that explicitly mention a line
  /// like "S1", "IC 2013", "Bus 5", "RE 4". Word-boundary substring match
  /// against headline + text + affected. Used by the Verbindung tab to
  /// mark journey cards whose actual line has an active disruption.
  ///
  /// Match is greedy — a disruption that mentions "S1 und S2" surfaces for
  /// both "S1" and "S2" queries.
  List<TransitDisruption> disruptionsMentioning(String line) {
    final needle = line.trim().toLowerCase();
    if (needle.length < 2) return const [];
    return _disruptions.where((d) {
      final hay = '${d.headline} ${d.text ?? ""} ${d.affected ?? ""}'.toLowerCase();
      final idx = hay.indexOf(needle);
      if (idx < 0) return false;
      final startOk = idx == 0 || !_isAlphanumeric(hay.codeUnitAt(idx - 1));
      final endIdx = idx + needle.length;
      final endOk = endIdx >= hay.length || !_isAlphanumeric(hay.codeUnitAt(endIdx));
      return startOk && endOk;
    }).toList();
  }

  bool _isAlphanumeric(int c) {
    return (c >= 0x30 && c <= 0x39) || _isLetter(c);
  }

  /// Word-boundary substring match. Prevents "Ulm" from matching
  /// "Neumünster", "Baden" from matching "Wiesbaden", etc. Boundary
  /// characters are ASCII non-letters (space, punctuation, digits, hyphen).
  bool _matchesRegion(TransitDisruption d) {
    final hay = '${d.headline} ${d.text ?? ""} ${d.affected ?? ""}'.toLowerCase();
    for (final t in _regionTokens) {
      final idx = hay.indexOf(t);
      if (idx < 0) continue;
      // Word start: at index 0 or previous char is non-letter.
      final startOk = idx == 0 || !_isLetter(hay.codeUnitAt(idx - 1));
      // Word end: at end of string or next char is non-letter.
      final endIdx = idx + t.length;
      final endOk = endIdx >= hay.length || !_isLetter(hay.codeUnitAt(endIdx));
      if (startOk && endOk) return true;
    }
    return false;
  }

  /// True for ASCII letters + common German umlauts (ä ö ü ß).
  bool _isLetter(int c) {
    if (c >= 0x61 && c <= 0x7A) return true; // a-z
    if (c >= 0x41 && c <= 0x5A) return true; // A-Z
    return c == 0xE4 || c == 0xF6 || c == 0xFC || c == 0xDF ||
           c == 0xC4 || c == 0xD6 || c == 0xDC;
  }

  /// Kick off periodic fetching. Idempotent — safe to call from dashboard init.
  void start() {
    if (_timer != null) return;
    _loadBypass();
    fetch();
    _timer = Timer.periodic(_refresh, (_) => fetch());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 2026-07-13: hook pt provider local activ — setat de TransitService
  /// (endpoint EFA/HAFAS + provider ID pt fetching local disruptions).
  String? _localEfaBaseUrl;
  String? _localHafasBaseUrl;
  String? _localHafasAid;
  String? _localProviderId;
  void setLocalProvider({
    String? efaBaseUrl,
    String? hafasBaseUrl,
    String? hafasAid,
    String? providerId,
  }) {
    _localEfaBaseUrl = efaBaseUrl;
    _localHafasBaseUrl = hafasBaseUrl;
    _localHafasAid = hafasAid;
    _localProviderId = providerId;
  }

  Future<void> fetch({bool force = false}) async {
    if (!force && _lastFetch != null && DateTime.now().difference(_lastFetch!) < _cacheTtl) {
      return;
    }
    // 2026-07-13: Adapter pattern — fetchers parallel + merge + dedupe.
    // Reference: Öffi (public-transport-enabler), bahn.expert.
    final results = await Future.wait([
      _fetchBahnDeHim(),
      if (_localEfaBaseUrl != null) _fetchEfaAddinfo(_localEfaBaseUrl!, _localProviderId ?? 'efa'),
      if (_localHafasBaseUrl != null) _fetchHafasHimSearch(_localHafasBaseUrl!, _localHafasAid ?? '', _localProviderId ?? 'hafas'),
    ]);
    final all = <TransitDisruption>[];
    for (final list in results) {
      all.addAll(list);
    }
    // Dedupe by (source, id) — same source can't have duplicate id.
    // Cross-source: bahn.de HIM about "S1 Berlin" won't collide with
    // VBB HAFAS about "S1 Berlin" because id-space e diferit; păstrăm
    // ambele (user vede badge source distinct).
    final seen = <String>{};
    _disruptions = all.where((d) {
      final key = '${d.source}|${d.id}';
      if (seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList();
    _lastFetch = DateTime.now();
    _log.info('Disruptions: fetched ${_disruptions.length} total '
        '(HIM:${results[0].length}'
        '${results.length > 1 ? ", EFA:${results[1].length}" : ""}'
        '${results.length > 2 ? ", HAFAS:${results[2].length}" : ""})',
        tag: 'DISRUPT');
    await _maybePushNotifications(_disruptions);
    notifyListeners();
  }

  /// Fetcher 1: bahn.de HIM (national rail).
  Future<List<TransitDisruption>> _fetchBahnDeHim() async {
    try {
      final resp = await _client.get(
        Uri.parse(_url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'ICD360S-eV-App/1.0',
        },
      ).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final list = (data is Map ? data['verkehrsmeldungen'] : null) as List? ?? [];
      return list
          .map<TransitDisruption?>((raw) => _parse(raw as Map<String, dynamic>))
          .whereType<TransitDisruption>()
          .toList();
    } catch (e) {
      _log.debug('Disruptions: HIM fetch failed: $e', tag: 'DISRUPT');
      return [];
    }
  }

  /// Fetcher 2: EFA XSLT_ADDINFO_REQUEST — universal pt EFA providers.
  /// Testat pe DING/MVV/VVS/KVV/DEFAS-Bayern (2026-07-13).
  /// Format response:
  ///   additionalInformation.travelInformations.travelInformation[]
  Future<List<TransitDisruption>> _fetchEfaAddinfo(String baseUrl, String providerId) async {
    try {
      final now = DateTime.now();
      final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final uri = Uri.parse('$baseUrl/XSLT_ADDINFO_REQUEST'
          '?outputFormat=JSON&filterDateValid=$dateStr'
          '&filterPublicationStatus=current&mode=all');
      final resp = await _client.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': 'ICD360S-eV-App/1.0',
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final infos = data is Map ? data['additionalInformation'] : null;
      if (infos is! Map) return [];
      final travelInfos = infos['travelInformations'];
      final list = (travelInfos is Map ? travelInfos['travelInformation'] : null) as List? ?? [];
      final out = <TransitDisruption>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final id = (raw['id'] ?? raw['nr'] ?? '').toString();
        if (id.isEmpty) continue;
        final title = raw['title']?.toString();
        final content = raw['content'];
        String? subtitle;
        String? body;
        if (content is Map) {
          subtitle = content['subtitle']?.toString();
          body = content['description']?.toString() ?? content['text']?.toString();
        } else if (content is String) {
          body = content;
        }
        final headline = (title?.isNotEmpty == true ? title! : (subtitle ?? '')).trim();
        if (headline.isEmpty) continue;
        // Timespan validation.
        DateTime? vFrom, vUntil;
        final ts = raw['timeSpan'];
        final tsList = ts is List ? ts : (ts is Map ? [ts] : []);
        for (final t in tsList) {
          if (t is Map) {
            vFrom ??= _parseDate(t['start'] ?? t['from'] ?? t['begin']);
            vUntil ??= _parseDate(t['end'] ?? t['until'] ?? t['stop']);
          }
        }
        if (vFrom != null && vFrom.isAfter(DateTime.now())) continue;
        if (vUntil != null && vUntil.isBefore(DateTime.now())) continue;
        // Affected lines.
        String? affected;
        final aff = raw['affected'] ?? raw['affectedLines'];
        if (aff is List && aff.isNotEmpty) {
          affected = aff.take(5).map((e) => e is Map
              ? (e['name'] ?? e['line'] ?? e['ref']).toString()
              : e.toString()).join(', ');
        }
        // EFA nu dă priority explicit — heuristic: dacă title include
        // "Ausfall"/"Sperrung" → HIGH, altfel MEDIUM.
        final prio = RegExp(r'ausfall|sperrung|entfällt|gesperrt|unfall',
                    caseSensitive: false).hasMatch(headline) ? 'HIGH' : 'MEDIUM';
        out.add(TransitDisruption(
          id: id, headline: headline, text: body,
          validFrom: vFrom, validUntil: vUntil,
          priority: prio, affected: affected,
          source: 'EFA', providerId: providerId,
        ));
      }
      return out;
    } catch (e) {
      _log.debug('Disruptions: EFA addinfo fetch failed: $e', tag: 'DISRUPT');
      return [];
    }
  }

  /// Fetcher 3: HAFAS HimSearch — pt providerii HAFAS (saarVV, VBB, RMV, etc.).
  Future<List<TransitDisruption>> _fetchHafasHimSearch(String baseUrl, String aid, String providerId) async {
    if (baseUrl.isEmpty) return [];
    try {
      final body = jsonEncode({
        'ver': '1.20',
        'lang': 'de',
        'auth': {'type': 'AID', 'aid': aid},
        'client': {'id': 'HAFAS', 'type': 'WEB', 'name': 'webapp'},
        'svcReqL': [
          {
            'meth': 'HimSearch',
            'req': {
              'himFltrL': [{'type': 'CH', 'mode': 'INC', 'value': 'CUSTOM1'}],
              'sortL': ['PRIO_D'],
              'onlyRT': false,
            },
          }
        ],
      });
      final resp = await _client.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final svc = data['svcResL']?[0]?['res'];
      final msgL = (svc is Map ? svc['msgL'] : null) as List? ?? [];
      final out = <TransitDisruption>[];
      for (final m in msgL) {
        if (m is! Map) continue;
        final id = (m['hid'] ?? m['id'] ?? '').toString();
        final head = (m['head'] ?? m['ttl'] ?? '').toString();
        if (head.isEmpty) continue;
        final text = m['text']?.toString() ?? m['lead']?.toString();
        final prio = (m['prio']?.toString() ?? '');
        final priority = prio == '100' ? 'HIGH' : (prio == '50' ? 'MEDIUM' : 'LOW');
        out.add(TransitDisruption(
          id: id, headline: head, text: text,
          priority: priority,
          source: 'HAFAS', providerId: providerId,
        ));
      }
      return out;
    } catch (e) {
      _log.debug('Disruptions: HAFAS HimSearch failed: $e', tag: 'DISRUPT');
      return [];
    }
  }

  /// Trimite push notification pentru fiecare HIM HIGH nou care matchează
  /// region tokens ale user-ului. Persistă ID-urile ca să nu re-notificăm
  /// aceleași după restart.
  /// Sprint B fix (2026-07-13): max 5 push per fetch (throttle anti-spam).
  /// Dacă apar 500 HIM HIGH deodată → nu vrem 500 notifications într-o
  /// avalanșă — user pierde încrederea în canal. Restul intră în lista
  /// _notifiedIds ca "already-seen" așa că nu re-notificăm.
  static const _maxPushPerFetch = 5;

  Future<void> _maybePushNotifications(List<TransitDisruption> current) async {
    if (!_pushEnabled) return;
    // Fără region tokens NU trimitem push — ar fi spam național.
    if (_regionTokens.isEmpty) return;
    final newHigh = current.where((d) =>
        d.isHigh &&
        !_notifiedIds.contains(d.id) &&
        _matchesRegion(d)).toList();
    var fired = 0;
    var skippedThrottle = 0;
    for (final d in newHigh) {
      if (fired >= _maxPushPerFetch) {
        // Throttle: marcăm ca notificate ca să nu re-trigger la fetch-ul următor.
        _notifiedIds.add(d.id);
        skippedThrottle++;
        continue;
      }
      try {
        await NotificationService().show(
          title: '⚠️ ÖPNV-Störung',
          body: d.headline.length > 120
              ? '${d.headline.substring(0, 117)}…'
              : d.headline,
          androidChannelId: NotificationService.channelIdOpnvStoerung,
          payload: 'opnv://disruption/${d.id}',
        );
        _notifiedIds.add(d.id);
        fired++;
      } catch (e) {
        _log.debug('Disruptions: push fail id=${d.id}: $e', tag: 'DISRUPT');
      }
    }
    if (fired > 0 || skippedThrottle > 0) {
      _log.info('Disruptions: pushed $fired HIGH (${skippedThrottle > 0 ? "throttled $skippedThrottle" : "no throttle"})', tag: 'DISRUPT');
      await _persistNotifiedIds();
    }
  }

  TransitDisruption? _parse(Map<String, dynamic> raw) {
    try {
      final id = (raw['id'] ?? raw['himId'])?.toString();
      final headline = (raw['ueberschrift'] ?? raw['headline'] ?? raw['text'])?.toString();
      if (id == null || headline == null || headline.isEmpty) return null;

      final text = (raw['text'] ?? raw['ausfuehrlicherText'])?.toString();
      final validFrom = _parseDate(raw['gueltigAb'] ?? raw['validFrom']);
      final validUntil = _parseDate(raw['gueltigBis'] ?? raw['validUntil']);

      // Only surface disruptions that are currently valid.
      final now = DateTime.now();
      if (validFrom != null && validFrom.isAfter(now)) return null;
      if (validUntil != null && validUntil.isBefore(now)) return null;

      final prio = (raw['prioritaet'] ?? raw['priority'])?.toString().toUpperCase() ?? 'MEDIUM';

      String? affected;
      final produkte = raw['produkte'] ?? raw['products'];
      if (produkte is List && produkte.isNotEmpty) {
        affected = produkte.take(5).map((p) => p.toString()).join(', ');
      }

      return TransitDisruption(
        id: id, headline: headline, text: text,
        validFrom: validFrom, validUntil: validUntil,
        priority: prio, affected: affected,
      );
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.tryParse(raw.toString());
    } catch (_) {
      return null;
    }
  }
}
