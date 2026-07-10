import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'logger_service.dart';
import 'notification_service.dart';
import 'transit_service.dart';

/// Persistent Ausstieg-Alarm — supraviețuiește închiderii OpnvDialog.
///
/// Când userul selectează un `targetStopId` în trip-map și pornește
/// monitorizarea via [startRide], creăm un stream GPS de foreground (Android)
/// + notificare persistentă "Alarm aktiv: N stații rămase". Când distanța
/// la stop < 150m → HapticFeedback + notificare max-priority + close.
///
/// UI-ul (TripMapView) poate consuma streamul acestui service ca să nu
/// mai deschidă un al doilea GPS listener paralel.
class TransitOngoingRideService {
  static final TransitOngoingRideService _instance = TransitOngoingRideService._();
  factory TransitOngoingRideService() => _instance;
  TransitOngoingRideService._();

  final _log = LoggerService();
  StreamSubscription<Position>? _positionSub;
  final _positionController = StreamController<Position>.broadcast();

  /// Stream pe care TripMapView îl folosește ca să afișeze poziția userului
  /// și să ruleze proximity checks fără propriul GPS stream (evită dublu-drain).
  Stream<Position> get positions => _positionController.stream;

  Departure? _dep;
  TripStop? _target;
  List<TripStop> _allStops = const [];
  bool _targetAlarmFired = false;
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  TripStop? get target => _target;
  Departure? get departure => _dep;

  /// Callback opțional pentru UI (TripMapView) ca să știe când alarm-ul
  /// a fost declanșat de background service.
  void Function()? onAlarmFired;

  /// Start monitoring. Idempotent: apel a doua oară cu target diferit doar
  /// swap-ează target-ul (fără să restarteze stream-ul GPS).
  Future<void> startRide({
    required Departure dep,
    required TripStop target,
    required List<TripStop> allStops,
  }) async {
    _dep = dep;
    _target = target;
    _allStops = allStops;
    _targetAlarmFired = false;

    if (_positionSub != null) {
      // Deja rulează — doar update target + notificare.
      _updatePersistentNotification();
      return;
    }
    _isRunning = true;

    final settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: '🚌 ÖPNV-Alarm aktiv',
              notificationText: 'Vibriert wenn du deine Ausstieg-Haltestelle erreichst.',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          );

    _log.info('OngoingRide: started for line ${dep.line} → ${target.name}', tag: 'RIDE');
    try {
      _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen(
        (pos) {
          _positionController.add(pos);
          _handleProximity(LatLng(pos.latitude, pos.longitude));
        },
        onError: (e) {
          _log.debug('OngoingRide: GPS error: $e', tag: 'RIDE');
        },
      );
      await _updatePersistentNotification();
    } catch (e) {
      _log.error('OngoingRide: startRide failed: $e', tag: 'RIDE');
      _isRunning = false;
    }
  }

  /// Update the target stop mid-ride (user changed intent).
  void updateTarget(TripStop newTarget) {
    _target = newTarget;
    _targetAlarmFired = false;
    _updatePersistentNotification();
  }

  Future<void> stopRide() async {
    _log.info('OngoingRide: stopped', tag: 'RIDE');
    _isRunning = false;
    await _positionSub?.cancel();
    _positionSub = null;
    _dep = null;
    _target = null;
    _allStops = const [];
    _targetAlarmFired = false;
  }

  /// Haversine (metri).
  double _distMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(s), math.sqrt(1 - s));
  }

  void _handleProximity(LatLng user) {
    final t = _target;
    if (t == null || t.lat == null || t.lon == null) return;
    final d = _distMeters(user, LatLng(t.lat!, t.lon!));
    if (_targetAlarmFired && d > 400) _targetAlarmFired = false;
    if (!_targetAlarmFired && d < 150) {
      _targetAlarmFired = true;
      _fireAlarm(t);
    }
  }

  Future<void> _fireAlarm(TripStop target) async {
    _log.info('OngoingRide: ALARM at ${target.name}!', tag: 'RIDE');
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 250), HapticFeedback.heavyImpact);
    Future.delayed(const Duration(milliseconds: 500), HapticFeedback.heavyImpact);
    await NotificationService().show(
      title: '🚨 Aussteigen: ${target.name}',
      body: 'Deine Ziel-Haltestelle ist erreicht — jetzt aussteigen!',
      payload: 'opnv:ausstieg:${target.stopID}',
      duration: const Duration(seconds: 10),
      androidChannelId: NotificationService.channelIdOpnvAlarm,
    );
    onAlarmFired?.call();
    // Auto-stop after 15s so foreground service doesn't linger.
    Future.delayed(const Duration(seconds: 15), () {
      if (_targetAlarmFired) stopRide();
    });
  }

  Future<void> _updatePersistentNotification() async {
    final t = _target;
    final d = _dep;
    if (t == null || d == null) return;
    // Compute cât mai sunt stații până la target.
    int remaining = 0;
    for (int i = 0; i < _allStops.length; i++) {
      if (_allStops[i].stopID == t.stopID) {
        remaining = _allStops.length - i - 1;
        break;
      }
    }
    // (Non-blocking — persistentul deja e creat de ForegroundNotificationConfig.
    // Această e o notificare secundară cu progresul.)
    try {
      await NotificationService().show(
        title: '🚌 Linie ${d.line} → ${t.name}',
        body: remaining > 0
            ? 'Noch $remaining Haltestellen bis zum Ausstieg.'
            : 'Bald ankommen — bereite dich auf den Ausstieg vor.',
        payload: 'opnv:ride:${t.stopID}',
        duration: const Duration(seconds: 2),
        androidChannelId: NotificationService.channelIdOpnvReminder,
      );
    } catch (_) {}
  }
}
