import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'logger_service.dart';
import 'transit_service.dart';

/// geOps Tralis WebSocket client — LIVE vehicle positions worldwide.
///
/// Docs: https://backend.developer.geops.io/tralis-docs/asyncapi_html/
/// Endpoint: wss://api.geops.io/realtime-ws/v1/?key=<KEY>
///
/// Cover: SBB + DB + BVG + HVV + MVG + more via geOps partnerships.
/// API key: gratis via `support@geops.io` cu use-case scurt.
///
/// User trebuie să obțină API key manual și să-l salveze în app settings
/// (`opnv.geops.api_key`). Fără key → serviciul e no-op (fallback la
/// HAFAS radar deja implementat).
///
/// Protocol:
///   Client trimite: `BBOX <x_min> <y_min> <x_max> <y_max> <zoom_level>`
///                   (WGS84 lat/lon direct)
///   Server trimite: `PartialTrajectoryMessage` JSON cu:
///     - content.geometry.coordinates: LineString [[lon, lat, timestamp], ...]
///     - content.properties.line: {name, color, ...}
///     - content.properties.train_id: string
///     - content.properties.route_identifier: string
class TransitLiveTrackerService extends ChangeNotifier {
  static final TransitLiveTrackerService _instance = TransitLiveTrackerService._();
  factory TransitLiveTrackerService() => _instance;
  TransitLiveTrackerService._();

  static const _wsUrl = 'wss://api.geops.io/realtime-ws/v1/';
  static const _kPrefsApiKey = 'opnv.geops.api_key';

  final _log = LoggerService();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? _apiKey;
  bool _connected = false;
  String? _currentBbox;
  final Map<String, VehiclePosition> _vehicles = {};

  bool get isConnected => _connected;
  int get vehicleCount => _vehicles.length;
  List<VehiclePosition> get vehicles => List.unmodifiable(_vehicles.values);

  Future<void> loadApiKey() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _apiKey = sp.getString(_kPrefsApiKey);
    } catch (_) {}
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key.trim().isEmpty ? null : key.trim();
    try {
      final sp = await SharedPreferences.getInstance();
      if (_apiKey == null) {
        await sp.remove(_kPrefsApiKey);
      } else {
        await sp.setString(_kPrefsApiKey, _apiKey!);
      }
    } catch (_) {}
    // Reconnect dacă e conectat + avem bbox curent.
    if (_currentBbox != null) {
      await disconnect();
      if (_apiKey != null) {
        await connect(_currentBbox!);
      }
    }
  }

  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  /// Connect to geOps WSS with a bbox filter.
  /// bbox format: "lonMin latMin lonMax latMax zoom" (space-separated).
  /// Zoom 11-15 typical for city view.
  Future<bool> connect(String bbox) async {
    if (!hasApiKey) return false;
    if (_channel != null) await disconnect();
    _currentBbox = bbox;
    try {
      final uri = Uri.parse('$_wsUrl?key=$_apiKey');
      _channel = IOWebSocketChannel.connect(uri);
      await _channel!.ready.timeout(const Duration(seconds: 8));
      _connected = true;
      _log.info('LiveTracker: geOps WSS connected', tag: 'LIVE');
      // Subscribe la bbox.
      _channel!.sink.add('BBOX $bbox');
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (e) {
          _log.debug('LiveTracker: WS error: $e', tag: 'LIVE');
          _connected = false;
          notifyListeners();
        },
        onDone: () {
          _connected = false;
          notifyListeners();
        },
      );
      notifyListeners();
      return true;
    } catch (e) {
      _log.debug('LiveTracker: connect failed: $e', tag: 'LIVE');
      _connected = false;
      notifyListeners();
      return false;
    }
  }

  /// Update bbox filter (fara reconnect).
  void updateBbox(String bbox) {
    if (_channel == null || !_connected) return;
    _currentBbox = bbox;
    try {
      _channel!.sink.add('BBOX $bbox');
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _connected = false;
    _vehicles.clear();
    notifyListeners();
  }

  void _onMessage(dynamic raw) {
    try {
      final txt = raw is String ? raw : raw.toString();
      final data = jsonDecode(txt);
      if (data is! Map) return;
      // geOps Tralis PartialTrajectoryMessage format:
      // { source: 'trajectory', client_reference: null,
      //   content: {
      //     geometry: {type: 'LineString', coordinates: [[lon,lat,ts],...]},
      //     properties: {train_id, line: {name}, route_identifier, ...}
      //   }
      // }
      final source = data['source']?.toString() ?? '';
      if (source != 'trajectory') return;
      final content = data['content'];
      if (content is! Map) return;
      final props = content['properties'] as Map? ?? {};
      final geom = content['geometry'] as Map? ?? {};
      final coords = geom['coordinates'] as List? ?? [];
      if (coords.isEmpty) return;
      // Ultima poziție din LineString = poziția curentă (chronological).
      final last = coords.last;
      if (last is! List || last.length < 2) return;
      final lon = (last[0] as num?)?.toDouble();
      final lat = (last[1] as num?)?.toDouble();
      if (lon == null || lat == null) return;
      final trainId = props['train_id']?.toString() ?? '';
      if (trainId.isEmpty) return;
      final lineMap = props['line'];
      String line = '';
      if (lineMap is Map) line = lineMap['name']?.toString() ?? '';
      if (line.isEmpty) line = props['route_identifier']?.toString() ?? '';
      final direction = props['destination_name']?.toString()
          ?? props['long_name']?.toString() ?? '';
      final vehType = (props['vehicle_type'] ?? props['type'] ?? '').toString().toLowerCase();
      String productType = 'bus';
      if (vehType.contains('rail') || vehType.contains('train')) productType = 'train';
      else if (vehType.contains('sbahn') || vehType.contains('suburban')) productType = 'suburban';
      else if (vehType.contains('subway') || vehType.contains('ubahn') || vehType.contains('metro')) productType = 'subway';
      else if (vehType.contains('tram') || vehType.contains('street')) productType = 'tram';

      _vehicles[trainId] = VehiclePosition(
        tripId: trainId, line: line, direction: direction,
        lat: lat, lon: lon,
        productType: productType,
        updatedAt: DateTime.now(),
        source: 'GEOPS_TRALIS',
      );
      // Curat vehicule vechi > 60s.
      final cutoff = DateTime.now().subtract(const Duration(seconds: 60));
      _vehicles.removeWhere((_, v) => v.updatedAt.isBefore(cutoff));
      notifyListeners();
    } catch (e) {
      _log.debug('LiveTracker: parse msg failed: $e', tag: 'LIVE');
    }
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
