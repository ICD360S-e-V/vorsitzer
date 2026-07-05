import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'logger_service.dart';
import 'notification_service.dart';
import 'termin_service.dart';
import 'termin_route_service.dart';
import 'transit_service.dart';

/// Checks upcoming Termine, pre-computes their ÖPNV route from the Verein
/// address, and pushes a local notification when the departure time is
/// getting close.
///
/// Because Termine sind nicht recurring — der Service ersetzt Serientermin-
/// Planning durch: bei jedem App-Start alle Termine der nächsten 24h scannen
/// und für jeden mit Ort einen "In X Min. losfahren"-Reminder anzeigen falls
/// die Abfahrt in den nächsten 3h ansteht und heute noch nicht erinnert wurde.
///
/// Persistiert `termin_id → last_reminder_iso` in SharedPreferences damit
/// derselbe Termin nicht bei jedem Foreground-Switch neu erinnert wird.
class TransitTerminReminderService {
  static const _kPrefsKey = 'transit.termin_reminders.v1';
  static const _leadWindow = Duration(hours: 3);
  static const _bufferMinutes = 15;

  static bool _running = false;

  static final _log = LoggerService();
  static final _termin = TerminService();
  static final _notif = NotificationService();

  static TerminRouteService? _routeSvc;
  static TerminRouteService _route() {
    // TerminRouteService takes explicit ApiService + TransitService — build once
    // on first use so the singleton lasts app lifetime.
    return _routeSvc ??= TerminRouteService(ApiService(), TransitService());
  }

  /// Kick off a scan. Safe to call from dashboard init or resume.
  /// De-dupes if already in flight so overlapping calls don't race.
  static Future<void> checkUpcoming() async {
    if (_running) return;
    _running = true;
    try {
      final res = await _termin.getMyTermine(filter: 'upcoming');
      if (res['success'] != true) return;
      final List<dynamic> raw = res['termine'] as List? ?? [];
      // Filter out terminal states rather than whitelisting 'scheduled' —
      // backend may return 'confirmed', 'geplant', 'aktiv', etc. Excluding
      // completed/cancelled catches every non-terminal case regardless of
      // spelling. Empty string also passes through (treat as scheduled).
      const terminalStatuses = {'completed', 'cancelled', 'canceled', 'abgesagt', 'storniert'};
      final termine = raw
          .map((j) => Termin.fromJson(j as Map<String, dynamic>))
          .where((t) => !terminalStatuses.contains(t.status.toLowerCase()))
          .where((t) => t.location.trim().isNotEmpty)
          .toList();

      final now = DateTime.now();
      final horizon = now.add(const Duration(hours: 24));
      final soon = termine.where((t) => t.terminDate.isAfter(now) && t.terminDate.isBefore(horizon));

      final sp = await SharedPreferences.getInstance();
      final rawMap = sp.getString(_kPrefsKey);
      final Map<String, dynamic> reminded = rawMap == null || rawMap.isEmpty
          ? {}
          : (jsonDecode(rawMap) as Map<String, dynamic>);
      // Purge entries older than 48h.
      reminded.removeWhere((k, v) {
        final ts = DateTime.tryParse(v as String? ?? '');
        return ts == null || now.difference(ts).inHours > 48;
      });

      for (final t in soon) {
        try {
          final result = await _route().calculateRoute(t, bufferMinutes: _bufferMinutes);
          if (!result.isSuccess || result.route == null) continue;
          final journey = result.route!.primary;
          final depTime = journey.depTime;
          final minsUntilDep = depTime.difference(now).inMinutes;
          // Skip if bus already left or leaves >3h away — user doesn't need reminder yet.
          if (minsUntilDep < 0 || minsUntilDep > _leadWindow.inMinutes) continue;

          final key = 't${t.id}_d${depTime.toIso8601String().substring(0, 10)}';
          if (reminded.containsKey(key)) continue;
          reminded[key] = now.toIso8601String();

          final leg = journey.legs.firstWhere(
            (l) => !l.isWalk,
            orElse: () => journey.legs.first,
          );
          final title = 'ÖPNV-Erinnerung: ${t.title}';
          final body = _formatBody(t, depTime, minsUntilDep, leg.line, leg.fromName);
          await _notif.show(
            title: title,
            body: body,
            eventTime: t.terminDate,
            payload: 'termin:${t.id}',
          );
          _log.info('TerminReminder: showed reminder for termin ${t.id} in ${minsUntilDep}min', tag: 'TERMIN_REMIND');
        } catch (e) {
          _log.debug('TerminReminder: failed for termin ${t.id}: $e', tag: 'TERMIN_REMIND');
        }
      }

      await sp.setString(_kPrefsKey, jsonEncode(reminded));
    } catch (e) {
      _log.debug('TerminReminder: scan failed: $e', tag: 'TERMIN_REMIND');
    } finally {
      _running = false;
    }
  }

  static String _formatBody(Termin t, DateTime dep, int minsUntilDep, String line, String fromName) {
    final depTime = '${dep.hour}:${dep.minute.toString().padLeft(2, '0')}';
    final terminTime = '${t.terminDate.hour}:${t.terminDate.minute.toString().padLeft(2, '0')}';
    if (minsUntilDep < 15) {
      return 'JETZT losfahren! Linie $line ab $fromName um $depTime.\n'
             'Termin: $terminTime bei ${t.location}';
    }
    return 'In $minsUntilDep Min. losfahren: Linie $line ab $fromName um $depTime.\n'
           'Termin: $terminTime bei ${t.location}';
  }
}
