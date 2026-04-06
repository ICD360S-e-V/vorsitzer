import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'logger_service.dart';
import 'http_client_factory.dart';

final _log = LoggerService();

/// A single nearby transit stop
class TransitStop {
  final String id;
  final String name;
  final int distance; // meters
  final String? platform;

  TransitStop({
    required this.id,
    required this.name,
    required this.distance,
    this.platform,
  });
}

/// A single departure from a stop
class Departure {
  final String line;
  final String direction;
  final DateTime plannedTime;
  final DateTime? realtimeTime;
  final int delay; // minutes
  final String? platform;
  final String productType; // bus, tram, train, etc.
  final String operator;
  final String stopName;

  Departure({
    required this.line,
    required this.direction,
    required this.plannedTime,
    this.realtimeTime,
    required this.delay,
    this.platform,
    required this.productType,
    required this.operator,
    required this.stopName,
  });

  /// Minutes until departure (from now, using realtime if available)
  int get minutesUntil {
    final departureTime = realtimeTime ?? plannedTime;
    return departureTime.difference(DateTime.now()).inMinutes;
  }

  /// Icon for product type
  String get icon {
    switch (productType) {
      case 'tram':
        return '🚊';
      case 'train':
      case 'regional':
        return '🚆';
      case 'suburban':
        return '🚈';
      default:
        return '🚌';
    }
  }

  /// Formatted departure time
  String get timeString {
    final t = realtimeTime ?? plannedTime;
    return '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
  }
}

// ══════════════════════════════════════════════════════════════
// Transit Providers — auto-detected by GPS coordinates
// ══════════════════════════════════════════════════════════════

enum TransitProviderType { ding, mvv, saarvv }

class TransitProviderConfig {
  final TransitProviderType type;
  final String name;        // short name
  final String displayName; // shown in UI footer
  final double minLat, maxLat, minLon, maxLon; // bounding box

  const TransitProviderConfig({
    required this.type,
    required this.name,
    required this.displayName,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  bool containsCoord(double lat, double lon) {
    return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
  }
}

/// All supported transit providers with geographic bounding boxes
const _providers = [
  TransitProviderConfig(
    type: TransitProviderType.ding,
    name: 'DING',
    displayName: 'DING (Donau-Iller-Nahverkehrsverbund)',
    minLat: 47.8, maxLat: 48.8, minLon: 9.3, maxLon: 10.5,
  ),
  TransitProviderConfig(
    type: TransitProviderType.mvv,
    name: 'MVV',
    displayName: 'MVV (Münchner Verkehrs- und Tarifverbund)',
    minLat: 47.5, maxLat: 48.6, minLon: 10.8, maxLon: 12.5,
  ),
  TransitProviderConfig(
    type: TransitProviderType.saarvv,
    name: 'saarVV',
    displayName: 'saarVV (Saarländischer Verkehrsverbund)',
    minLat: 49.0, maxLat: 49.7, minLon: 6.3, maxLon: 7.5,
  ),
];

/// Transit service with multi-provider support
/// Providers: DING EFA (Ulm), MVV EFA (München), saarVV HAFAS (Saarland)
/// Auto-detects provider based on GPS coordinates
class TransitService {
  Timer? _refreshTimer;
  double? _latitude;
  double? _longitude;
  String city = '';
  bool _useGps = false;

  List<TransitStop> nearbyStops = [];
  List<Departure> departures = [];
  bool isLoading = false;
  String? locationError;

  /// Current coordinates (for sharing with weather service)
  double? get latitude => _latitude;
  double? get longitude => _longitude;

  /// Currently active provider (detected from GPS)
  TransitProviderConfig? activeProvider;

  // Callbacks
  void Function(List<Departure>)? onDeparturesUpdate;
  /// Called when GPS location changes significantly (new city)
  void Function(double lat, double lon, String city)? onLocationChanged;

  final http.Client _client = IOClient(HttpClientFactory.createDefaultHttpClient());

  /// Actual city name from GPS reverse geocoding
  String? gpsCity;

  /// Start transit monitoring — tries GPS first, falls back to city geocoding
  Future<void> start(String cityName) async {
    city = cityName;

    // Try GPS location first
    final gpsSuccess = await _getGpsLocation();
    if (gpsSuccess) {
      _useGps = true;
      _log.info('Transit: Using GPS location ($_latitude, $_longitude)', tag: 'TRANSIT');
      // Reverse geocode to get actual city name
      await _reverseGeocode();
    } else if (cityName.isNotEmpty) {
      // Fallback: geocode city name
      final geocodeSuccess = await _geocodeCity(city);
      if (!geocodeSuccess) {
        _log.error('Transit: Could not determine location', tag: 'TRANSIT');
        return;
      }
      _log.info('Transit: Using city geocode "$city" ($_latitude, $_longitude)', tag: 'TRANSIT');
    } else {
      _log.info('Transit: No location available, skipping', tag: 'TRANSIT');
      return;
    }

    // Detect provider based on coordinates
    _detectProvider();

    // Initial fetch
    await fetchDepartures();

    // Refresh every 60 seconds (also re-checks GPS position)
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      // Update GPS position each refresh if available
      if (_useGps) {
        final oldLat = _latitude;
        final oldLon = _longitude;
        await _getGpsLocation();
        // If GPS moved >2km, re-geocode and notify listeners (new city)
        if (oldLat != null && oldLon != null && _latitude != null && _longitude != null) {
          final dist = _distanceKm(oldLat, oldLon, _latitude!, _longitude!);
          if (dist > 2.0) {
            _log.info('Transit: Location shifted ${dist.toStringAsFixed(1)}km, re-geocoding', tag: 'TRANSIT');
            await _reverseGeocode();
            _detectProvider();
            onLocationChanged?.call(_latitude!, _longitude!, gpsCity ?? city);
          }
        }
      }
      await fetchDepartures();
    });
  }

  void stop() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _log.info('Transit: Stopped', tag: 'TRANSIT');
  }

  /// Detect which transit provider to use based on coordinates
  void _detectProvider() {
    if (_latitude == null || _longitude == null) return;

    for (final p in _providers) {
      if (p.containsCoord(_latitude!, _longitude!)) {
        activeProvider = p;
        _log.info('Transit: Detected provider ${p.name} for ($_latitude, $_longitude)', tag: 'TRANSIT');
        return;
      }
    }

    // Default to DING if no match
    activeProvider = _providers.first;
    _log.info('Transit: No matching provider, defaulting to ${activeProvider!.name}', tag: 'TRANSIT');
  }

  /// Get current GPS position — robust multi-strategy approach for macOS
  Future<bool> _getGpsLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      _log.info('Transit: GPS permission = $permission', tag: 'TRANSIT');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          locationError = 'Standort-Berechtigung verweigert';
          _log.info('Transit: Location permission denied', tag: 'TRANSIT');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        locationError = 'Standort-Berechtigung dauerhaft verweigert';
        _log.info('Transit: Location permission denied forever', tag: 'TRANSIT');
        return false;
      }

      // Strategy 1: Get last known position instantly (cached by OS)
      Position? cachedPosition;
      try {
        cachedPosition = await Geolocator.getLastKnownPosition();
        if (cachedPosition != null) {
          _log.info('Transit: Cached GPS = ${cachedPosition.latitude}, ${cachedPosition.longitude}', tag: 'TRANSIT');
        }
      } catch (e) {
        _log.debug('Transit: getLastKnownPosition failed: $e', tag: 'TRANSIT');
      }

      // Strategy 2: Try fresh position with high accuracy (15s timeout)
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: Platform.isAndroid
              ? AndroidSettings(accuracy: LocationAccuracy.high, forceLocationManager: true)
              : const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception('GPS high accuracy timeout'),
        );

        _latitude = position.latitude;
        _longitude = position.longitude;
        locationError = null;
        _log.info('Transit: Fresh GPS (high) = $_latitude, $_longitude', tag: 'TRANSIT');
        return true;
      } catch (e) {
        _log.debug('Transit: High accuracy failed: $e', tag: 'TRANSIT');
      }

      // Strategy 3: Try with lower accuracy (faster, 8s timeout)
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: Platform.isAndroid
              ? AndroidSettings(accuracy: LocationAccuracy.medium, forceLocationManager: true)
              : const LocationSettings(accuracy: LocationAccuracy.medium),
        ).timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw Exception('GPS medium accuracy timeout'),
        );

        _latitude = position.latitude;
        _longitude = position.longitude;
        locationError = null;
        _log.info('Transit: Fresh GPS (medium) = $_latitude, $_longitude', tag: 'TRANSIT');
        return true;
      } catch (e) {
        _log.debug('Transit: Medium accuracy failed: $e', tag: 'TRANSIT');
      }

      // Strategy 4: Fall back to cached position if fresh ones failed
      if (cachedPosition != null && cachedPosition.latitude != 0.0) {
        _latitude = cachedPosition.latitude;
        _longitude = cachedPosition.longitude;
        locationError = null;
        _log.info('Transit: Using cached GPS fallback = $_latitude, $_longitude', tag: 'TRANSIT');
        return true;
      }

      // Strategy 5: Keep previous known position if we had one
      if (_latitude != null && _longitude != null) {
        _log.info('Transit: Keeping previous position = $_latitude, $_longitude', tag: 'TRANSIT');
        return true;
      }

      locationError = 'GPS nicht verfügbar';
      return false;
    } catch (e) {
      _log.error('Transit: GPS failed completely: $e', tag: 'TRANSIT');

      if (_latitude != null && _longitude != null) {
        _log.info('Transit: Error but keeping previous position', tag: 'TRANSIT');
        return true;
      }

      locationError = 'GPS nicht verfügbar: $e';
      return false;
    }
  }

  /// Haversine distance in km between two GPS points
  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0; // Earth radius in km
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Reverse geocode GPS coordinates → city name (Nominatim / OpenStreetMap)
  Future<void> _reverseGeocode() async {
    if (_latitude == null || _longitude == null) return;
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$_latitude&lon=$_longitude&format=json&accept-language=de',
      );
      final response = await _client.get(uri, headers: {
        'User-Agent': 'ICD360S-eV-App/1.0',
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'];
        if (address != null) {
          final name = address['city'] ?? address['town'] ?? address['village'] ?? address['municipality'];
          if (name != null) {
            gpsCity = name.toString();
            _log.info('Transit: Reverse geocoded → $gpsCity', tag: 'TRANSIT');
          }
        }
      }
    } catch (e) {
      _log.error('Transit: Reverse geocode failed: $e', tag: 'TRANSIT');
    }
  }

  /// Geocode city name to lat/lon (fallback)
  Future<bool> _geocodeCity(String city) async {
    try {
      final uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(city)}&count=1&language=de&format=json',
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          _latitude = (results[0]['latitude'] as num).toDouble();
          _longitude = (results[0]['longitude'] as num).toDouble();
          return true;
        }
      }
      return false;
    } catch (e) {
      _log.error('Transit: Geocoding failed: $e', tag: 'TRANSIT');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // FETCH DEPARTURES — dispatches to correct provider
  // ══════════════════════════════════════════════════════════════

  /// Fetch departures using the detected provider
  Future<void> fetchDepartures() async {
    if (_latitude == null || _longitude == null) return;

    isLoading = true;

    try {
      switch (activeProvider?.type) {
        case TransitProviderType.mvv:
          await _fetchEfaDepartures(
            baseUrl: 'https://efa.mvv-muenchen.de/ng/XSLT_DM_REQUEST',
          );
          break;
        case TransitProviderType.saarvv:
          await _fetchHafasDepartures();
          break;
        case TransitProviderType.ding:
        default:
          await _fetchEfaDepartures(
            baseUrl: 'https://ding.eu/mobile/XSLT_DM_REQUEST',
          );
          break;
      }
    } catch (e) {
      _log.error('Transit: Fetch failed: $e', tag: 'TRANSIT');
    }

    isLoading = false;
    onDeparturesUpdate?.call(departures);
  }

  /// Fetch departures for a specific stop by name (EFA only)
  Future<void> fetchDeparturesForStop(String stopName) async {
    isLoading = true;

    try {
      final baseUrl = activeProvider?.type == TransitProviderType.mvv
          ? 'https://efa.mvv-muenchen.de/ng/XSLT_DM_REQUEST'
          : 'https://ding.eu/mobile/XSLT_DM_REQUEST';

      final uri = Uri.parse(
        '$baseUrl'
        '?outputFormat=JSON'
        '&type_dm=stop'
        '&name_dm=${Uri.encodeComponent(stopName)}'
        '&mode=direct'
        '&useRealtime=1'
        '&locationServerActive=1'
        '&limit=30',
      );

      final response = await _client.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _parseEfaResponse(data);
      }
    } catch (e) {
      _log.error('Transit: Stop fetch failed: $e', tag: 'TRANSIT');
    }

    isLoading = false;
    onDeparturesUpdate?.call(departures);
  }

  /// The closest stop name (for default filter in UI)
  String? closestStopName;

  // ══════════════════════════════════════════════════════════════
  // EFA PROVIDER — used by DING (Ulm) and MVV (München)
  // ══════════════════════════════════════════════════════════════

  Future<void> _fetchEfaDepartures({required String baseUrl}) async {
    final coordStr = '${_longitude!.toStringAsFixed(6)}:${_latitude!.toStringAsFixed(6)}:WGS84';
    final uri = Uri.parse(
      '$baseUrl'
      '?outputFormat=JSON'
      '&coordOutputFormat=WGS84[dd.ddddd]'
      '&type_dm=coord'
      '&name_dm=$coordStr'
      '&mode=direct'
      '&useRealtime=1'
      '&locationServerActive=1'
      '&limit=30',
    );

    final response = await _client.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _parseEfaResponse(data);
      _log.debug('Transit [${activeProvider?.name}]: ${departures.length} departures from ${nearbyStops.length} stops', tag: 'TRANSIT');
    } else {
      _log.error('Transit [${activeProvider?.name}]: API returned ${response.statusCode}', tag: 'TRANSIT');
    }
  }

  /// Parse the EFA JSON response (DING + MVV share the same format)
  void _parseEfaResponse(Map<String, dynamic> data) {
    // Parse assigned stops (sorted by distance)
    nearbyStops = [];
    final dm = data['dm'];
    if (dm != null) {
      final assignedStops = dm['assignedStops'];
      if (assignedStops is List) {
        for (final s in assignedStops) {
          nearbyStops.add(TransitStop(
            id: s['stopID']?.toString() ?? '',
            name: s['name']?.toString() ?? '',
            distance: int.tryParse(s['distance']?.toString() ?? '0') ?? 0,
            platform: s['platform']?.toString(),
          ));
        }
        nearbyStops.sort((a, b) => a.distance.compareTo(b.distance));
      }
    }

    // Keep only the 3 closest stops
    final allowedStops = <String>{};
    for (int i = 0; i < nearbyStops.length && i < 3; i++) {
      allowedStops.add(nearbyStops[i].name);
    }
    closestStopName = nearbyStops.isNotEmpty ? nearbyStops.first.name : null;

    // Parse departures — only from nearest stops
    departures = [];
    final departureList = data['departureList'];
    if (departureList is List) {
      for (final dep in departureList) {
        try {
          final servingLine = dep['servingLine'] ?? {};
          final dateTime = dep['dateTime'] ?? {};
          final realDateTime = dep['realDateTime'];

          final stopName = dep['stopName']?.toString() ?? '';

          // Filter: only keep departures from nearest stops
          if (allowedStops.isNotEmpty && !allowedStops.contains(stopName)) continue;

          final planned = _parseEfaDateTime(dateTime);
          if (planned == null) continue;

          DateTime? realtime;
          if (realDateTime != null) {
            realtime = _parseEfaDateTime(realDateTime);
          }

          final delayStr = dep['servingLine']?['delay']?.toString() ?? '0';
          final delay = int.tryParse(delayStr) ?? 0;

          // Determine product type
          final motType = servingLine['motType']?.toString() ?? '';
          String productType;
          switch (motType) {
            case '0':
              productType = 'train';
              break;
            case '1':
              productType = 'suburban';
              break;
            case '4':
              productType = 'tram';
              break;
            default:
              productType = 'bus';
          }

          final platform = dep['platform']?.toString();

          departures.add(Departure(
            line: servingLine['number']?.toString() ?? servingLine['symbol']?.toString() ?? '?',
            direction: servingLine['direction']?.toString() ?? '',
            plannedTime: planned,
            realtimeTime: realtime,
            delay: delay,
            platform: (platform != null && platform.isNotEmpty && platform != 'null') ? platform : null,
            productType: productType,
            operator: servingLine['operator']?['publicName']?.toString() ?? '',
            stopName: stopName,
          ));
        } catch (e) {
          // Skip malformed entries
        }
      }

      // Sort by departure time
      departures.sort((a, b) {
        final timeA = a.realtimeTime ?? a.plannedTime;
        final timeB = b.realtimeTime ?? b.plannedTime;
        return timeA.compareTo(timeB);
      });
    }
  }

  /// Parse EFA dateTime object → DateTime
  DateTime? _parseEfaDateTime(Map<String, dynamic> dt) {
    try {
      final year = int.tryParse(dt['year']?.toString() ?? '');
      final month = int.tryParse(dt['month']?.toString() ?? '');
      final day = int.tryParse(dt['day']?.toString() ?? '');
      final hour = int.tryParse(dt['hour']?.toString() ?? '');
      final minute = int.tryParse(dt['minute']?.toString() ?? '');
      if (year == null || month == null || day == null || hour == null || minute == null) return null;
      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // HAFAS PROVIDER — used by saarVV (Saarland)
  // ══════════════════════════════════════════════════════════════

  /// HAFAS auth config for saarVV
  static const _hafasEndpoint = 'https://saarfahrplan.de/bin/mgate.exe';
  static const _hafasClientId = 'ZPS-SAAR';
  static const _hafasAuthToken = 'REDACTED_HAFAS_TOKEN';

  Map<String, dynamic> _hafasRequest(List<Map<String, dynamic>> svcReqL) {
    return {
      'ver': '1.40',
      'lang': 'de',
      'auth': {'type': 'AID', 'aid': _hafasAuthToken},
      'client': {'type': 'AND', 'id': _hafasClientId, 'v': '1000070', 'name': 'Saarfahrplan'},
      'svcReqL': svcReqL,
    };
  }

  /// Fetch departures via HAFAS mgate.exe (saarVV)
  /// Two-step: 1) find nearby stops  2) get departures for each
  Future<void> _fetchHafasDepartures() async {
    // Step 1: Find nearby stops via LocGeoPos
    final nearbyRequest = _hafasRequest([
      {
        'meth': 'LocGeoPos',
        'req': {
          'ring': {
            'cCrd': {
              'x': (_longitude! * 1000000).round(),
              'y': (_latitude! * 1000000).round(),
            },
            'maxDist': 1000,
          },
          'getPOIs': false,
          'getStops': true,
        },
      },
    ]);

    final nearbyResponse = await _client.post(
      Uri.parse(_hafasEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(nearbyRequest),
    ).timeout(const Duration(seconds: 15));

    if (nearbyResponse.statusCode != 200) {
      _log.error('Transit [saarVV]: LocGeoPos returned ${nearbyResponse.statusCode}', tag: 'TRANSIT');
      return;
    }

    final nearbyData = jsonDecode(nearbyResponse.body);
    final nearbyRes = nearbyData['svcResL'];
    if (nearbyRes == null || nearbyRes is! List || nearbyRes.isEmpty) {
      _log.error('Transit [saarVV]: Empty LocGeoPos response', tag: 'TRANSIT');
      return;
    }

    final locRes = nearbyRes[0]['res'];
    if (locRes == null) {
      // Check for error
      final err = nearbyRes[0]['err'];
      _log.error('Transit [saarVV]: LocGeoPos error: $err', tag: 'TRANSIT');
      return;
    }

    final locList = locRes['locL'] as List? ?? [];

    // Parse nearby stops
    nearbyStops = [];
    final stopIds = <String>[];
    final stopLids = <String>[];

    for (final loc in locList) {
      if (loc['type'] != 'S') continue; // only stops
      final name = loc['name']?.toString() ?? '';
      final lid = loc['lid']?.toString() ?? '';
      final dist = loc['dist'] as int? ?? 0;
      final extId = loc['extId']?.toString() ?? '';

      nearbyStops.add(TransitStop(
        id: extId.isNotEmpty ? extId : lid,
        name: name,
        distance: dist,
      ));
      stopIds.add(extId.isNotEmpty ? extId : lid);
      stopLids.add(lid);

      // Max 3 closest stops
      if (nearbyStops.length >= 3) break;
    }

    nearbyStops.sort((a, b) => a.distance.compareTo(b.distance));
    closestStopName = nearbyStops.isNotEmpty ? nearbyStops.first.name : null;

    if (stopLids.isEmpty) {
      _log.info('Transit [saarVV]: No nearby stops found', tag: 'TRANSIT');
      departures = [];
      return;
    }

    // Step 2: Get departures for each nearby stop
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timeStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}00';

    final stbRequests = stopLids.map((lid) => {
      'meth': 'StationBoard',
      'req': {
        'type': 'DEP',
        'stbLoc': {'lid': lid},
        'maxJny': 15,
        'date': dateStr,
        'time': timeStr,
      },
    }).toList();

    final depRequest = _hafasRequest(stbRequests);
    final depResponse = await _client.post(
      Uri.parse(_hafasEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(depRequest),
    ).timeout(const Duration(seconds: 15));

    if (depResponse.statusCode != 200) {
      _log.error('Transit [saarVV]: StationBoard returned ${depResponse.statusCode}', tag: 'TRANSIT');
      return;
    }

    final depData = jsonDecode(depResponse.body);
    final depResL = depData['svcResL'] as List? ?? [];

    departures = [];

    for (int svcIdx = 0; svcIdx < depResL.length; svcIdx++) {
      final svc = depResL[svcIdx];
      if (svc['meth'] != 'StationBoard') continue;

      final res = svc['res'];
      if (res == null) continue;

      final stopName = svcIdx < nearbyStops.length ? nearbyStops[svcIdx].name : '';

      // Common products list (referenced by index from jnyL)
      final common = res['common'] ?? {};
      final prodL = common['prodL'] as List? ?? [];

      final jnyL = res['jnyL'] as List? ?? [];

      for (final jny in jnyL) {
        try {
          final stbStop = jny['stbStop'] ?? {};
          final date = jny['date']?.toString() ?? dateStr;

          // Parse scheduled time
          final dTimeS = stbStop['dTimeS']?.toString();
          if (dTimeS == null || dTimeS.length < 4) continue;
          final planned = _parseHafasDateTime(date, dTimeS);
          if (planned == null) continue;

          // Parse realtime time
          DateTime? realtime;
          final dTimeR = stbStop['dTimeR']?.toString();
          if (dTimeR != null && dTimeR.length >= 4) {
            realtime = _parseHafasDateTime(date, dTimeR);
          }

          // Calculate delay
          int delay = 0;
          if (realtime != null) {
            delay = realtime.difference(planned).inMinutes;
            if (delay < 0) delay = 0;
          }

          // Platform
          final dPlatfS = stbStop['dPlatfS']?.toString();
          final dPlatfR = stbStop['dPlatfR']?.toString();
          final platform = dPlatfR ?? dPlatfS;

          // Product info (line name, type)
          final prodIdx = jny['prodX'] as int? ?? (jny['prodL'] is List && (jny['prodL'] as List).isNotEmpty ? (jny['prodL'] as List)[0]['prodX'] ?? 0 : 0);
          String lineName = '?';
          String productType = 'bus';
          String operatorName = '';

          if (prodIdx < prodL.length) {
            final prod = prodL[prodIdx];
            lineName = prod['name']?.toString().trim() ?? '?';
            // Extract short line number from name (e.g. "Bus 101" → "101")
            final nameStr = prod['name']?.toString() ?? '';
            final lineMatch = RegExp(r'(\d+\w*)$').firstMatch(nameStr.trim());
            if (lineMatch != null) {
              lineName = lineMatch.group(1)!;
            }
            operatorName = prod['oprX'] != null ? '' : '';

            // Product class → type
            final cls = prod['cls'] as int? ?? 0;
            if (cls == 1 || cls == 2) {
              productType = 'train'; // ICE, IC
            } else if (cls == 4) {
              productType = 'regional'; // RE, RB
            } else if (cls == 8) {
              productType = 'suburban'; // S-Bahn
            } else if (cls == 16) {
              productType = 'tram'; // Tram
            } else {
              productType = 'bus';
            }
          }

          // Direction
          final direction = jny['dirTxt']?.toString() ?? '';

          departures.add(Departure(
            line: lineName,
            direction: direction,
            plannedTime: planned,
            realtimeTime: realtime,
            delay: delay,
            platform: (platform != null && platform.isNotEmpty) ? platform : null,
            productType: productType,
            operator: operatorName,
            stopName: stopName,
          ));
        } catch (e) {
          // Skip malformed entries
        }
      }
    }

    // Sort all departures by time
    departures.sort((a, b) {
      final timeA = a.realtimeTime ?? a.plannedTime;
      final timeB = b.realtimeTime ?? b.plannedTime;
      return timeA.compareTo(timeB);
    });

    _log.debug('Transit [saarVV]: ${departures.length} departures from ${nearbyStops.length} stops', tag: 'TRANSIT');
  }

  /// Parse HAFAS date+time strings → DateTime
  /// date: "20260301", time: "143500" or "1435"
  DateTime? _parseHafasDateTime(String date, String time) {
    try {
      if (date.length < 8) return null;
      final year = int.parse(date.substring(0, 4));
      final month = int.parse(date.substring(4, 6));
      final day = int.parse(date.substring(6, 8));

      // Time can be "HHMMSS" or "HHMM" — also handle day overflow (e.g. "250000" = next day 01:00)
      int hour = int.parse(time.substring(0, 2));
      final minute = int.parse(time.substring(2, 4));

      var dt = DateTime(year, month, day, 0, minute);
      if (hour >= 24) {
        dt = dt.add(Duration(hours: hour));
      } else {
        dt = DateTime(year, month, day, hour, minute);
      }
      return dt;
    } catch (e) {
      return null;
    }
  }

  /// Force refresh (also updates GPS if available)
  Future<void> refresh() async {
    if (_useGps) await _getGpsLocation();
    _detectProvider(); // re-detect in case position changed significantly
    await fetchDepartures();
  }
}
