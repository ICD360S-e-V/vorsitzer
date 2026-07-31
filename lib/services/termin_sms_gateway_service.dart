import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api_service.dart';
import 'device_key_service.dart';
import 'logger_service.dart';
import 'sms_service.dart';

final _log = LoggerService();

/// Name des Hintergrundjobs (muss in [smsGatewayCallbackDispatcher] wieder
/// erkannt werden).
const String kTerminSmsTask = 'de.icd360sev.vorsitzer.termin-sms';
const String _kTerminSmsUniqueName = 'termin-sms-gateway';

/// Ergebnis eines Durchlaufs — für die Anzeige in den Einstellungen.
class SmsGatewayRun {
  final int sent;
  final int failed;
  final int skipped;
  final String? note;

  const SmsGatewayRun({this.sent = 0, this.failed = 0, this.skipped = 0, this.note});

  bool get didSomething => sent > 0 || failed > 0;

  @override
  String toString() =>
      note ?? 'gesendet: $sent, fehlgeschlagen: $failed, übersprungen: $skipped';
}

/// Verschickt die automatischen Termin-Erinnerungen am Vortag.
///
/// Arbeitsteilung: der Cron auf dem Server (`check_termine_sms.php`) reiht um
/// 9 Uhr die Termine von morgen ein, dieses Gerät holt die Warteschlange ab
/// und verschickt sie über die eigene SIM. Der Server kann das nicht — er hat
/// kein Mobilfunkmodem.
///
/// Genau EIN Gerät darf Gateway sein (das Vereins-Tablet). Sonst bekäme das
/// Mitglied dieselbe Erinnerung von jedem Vorsitzer-Gerät einmal. Zusätzlich
/// sichert der Server das mit `claim` ab, aber der Schalter hier ist die
/// eigentliche Entscheidung.
class TerminSmsGatewayService {
  static const _kEnabledKey = 'sms.gateway_enabled';
  static const _kLastRunKey = 'sms.gateway_last_run';
  static const _kLastResultKey = 'sms.gateway_last_result';

  static const _powerChannel = MethodChannel('de.icd360sev.vorsitzer/power');

  /// Wie oft im Hintergrund nachgesehen wird. Android erlaubt periodische
  /// Jobs frühestens alle 15 Minuten; 30 reichen für eine Erinnerung, die
  /// einen ganzen Tag Vorlauf hat, und schonen den Akku.
  static const _interval = Duration(minutes: 30);

  // ── Schalter ────────────────────────────────────────────────────────────

  static Future<bool> isEnabled() async {
    if (!Platform.isAndroid) return false;
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kEnabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kEnabledKey, value);
    if (value) {
      await _registerPeriodic();
    } else {
      await _cancelPeriodic();
    }
    _log.info('SMS-Gateway ${value ? 'aktiviert' : 'deaktiviert'}', tag: 'SMS_GW');
  }

  static Future<DateTime?> lastRun() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kLastRunKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<String?> lastResult() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kLastResultKey);
  }

  // ── Akku-Ausnahme ───────────────────────────────────────────────────────

  /// Samsung friert Hintergrundjobs sonst ein; die SMS ginge Tage zu spät raus.
  static Future<bool> isBatteryExempt() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _powerChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Öffnet den Systemdialog „Akku-Optimierung ignorieren?".
  /// @return "already_ignored", "requested", "no_dialog" oder "unsupported".
  static Future<String> requestBatteryExemption() async {
    if (!Platform.isAndroid) return 'unsupported';
    try {
      return await _powerChannel.invokeMethod<String>('requestIgnoreBatteryOptimizations') ??
          'unsupported';
    } on MissingPluginException {
      return 'unsupported';
    } catch (_) {
      return 'unsupported';
    }
  }

  /// Steht die App unter „Akku" auf „Eingeschränkt"?
  ///
  /// Zweite, unabhängige Bremse: sie bleibt aktiv, selbst wenn die
  /// Akku-Optimierung ausgenommen ist, und verbietet Hintergrundarbeit
  /// praktisch vollständig. Ohne diese Abfrage sähe die Diagnose grün aus,
  /// während der Job nie läuft.
  static Future<bool> isBackgroundRestricted() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _powerChannel.invokeMethod<bool>('isBackgroundRestricted') ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Systemseite der App — von dort geht es zu „Akku" und „Berechtigungen".
  static Future<void> openAppSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _powerChannel.invokeMethod('openAppSettings');
    } catch (_) {}
  }

  /// Samsungs Akku-Seite mit der Liste „Apps, die nie in den Ruhezustand
  /// versetzt werden". Fällt auf die normale App-Seite zurück.
  static Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _powerChannel.invokeMethod('openBatterySettings');
    } catch (_) {}
  }

  /// Ist der periodische Job beim System noch angemeldet?
  ///
  /// Samsung wirft ihn beim „Force Stop", nach manchen Updates und beim
  /// Leeren des App-Speichers raus — dann bleibt der Schalter in der App an,
  /// aber es passiert nichts mehr. Der Check macht das sichtbar.
  static Future<bool> isJobScheduled() async {
    if (!Platform.isAndroid) return false;
    try {
      return await Workmanager().isScheduledByUniqueName(_kTerminSmsUniqueName);
    } catch (_) {
      return false;
    }
  }

  /// Meldet den Job neu an, falls er verschwunden ist.
  static Future<bool> ensureJobScheduled() async {
    if (!await isEnabled()) return false;
    if (await isJobScheduled()) return true;
    _log.warning('SMS-Gateway: Job war abgemeldet, wird neu registriert', tag: 'SMS_GW');
    await _registerPeriodic();
    return isJobScheduled();
  }

  // ── WorkManager ─────────────────────────────────────────────────────────

  /// Beim App-Start aufrufen. Registriert den Job nur, wenn dieses Gerät
  /// tatsächlich Gateway ist.
  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    try {
      await Workmanager().initialize(smsGatewayCallbackDispatcher);
      // Nicht blind neu registrieren, sondern nur wenn der Job fehlt — das
      // fängt genau die Fälle ab, in denen Samsung ihn stillschweigend
      // entsorgt hat (Force Stop, Speicher geleert, großes Update).
      if (await isEnabled()) await ensureJobScheduled();
    } catch (e) {
      _log.warning('WorkManager-Init fehlgeschlagen: $e', tag: 'SMS_GW');
    }
  }

  static Future<void> _registerPeriodic() async {
    try {
      await Workmanager().registerPeriodicTask(
        _kTerminSmsUniqueName,
        kTerminSmsTask,
        frequency: _interval,
        // Ohne Netz gibt es keine Warteschlange abzuholen.
        constraints: Constraints(networkType: NetworkType.connected),
        // keep: ein erneuter App-Start soll den laufenden Rhythmus nicht
        // zurücksetzen, sonst verschiebt sich der Job bei jedem Öffnen.
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 10),
      );
    } catch (e) {
      _log.warning('WorkManager-Registrierung fehlgeschlagen: $e', tag: 'SMS_GW');
    }
  }

  static Future<void> _cancelPeriodic() async {
    try {
      await Workmanager().cancelByUniqueName(_kTerminSmsUniqueName);
    } catch (_) {}
  }

  // ── Durchlauf ───────────────────────────────────────────────────────────

  /// Holt die offenen Erinnerungen und verschickt sie.
  ///
  /// [background] = Aufruf aus dem WorkManager-Isolat: dort gibt es keine
  /// Activity, ein Berechtigungsdialog ist unmöglich.
  static Future<SmsGatewayRun> runOnce({bool background = false}) async {
    if (!await isEnabled()) {
      return const SmsGatewayRun(note: 'Gerät ist nicht als SMS-Gateway eingerichtet');
    }
    if (!SmsService.isSupportedPlatform) {
      return const SmsGatewayRun(note: 'Nur auf Android möglich');
    }

    final caps = await SmsService.capabilities();
    if (!caps.messaging) {
      return const SmsGatewayRun(note: 'Gerät hat kein Mobilfunkmodem');
    }
    if (!caps.permission && background) {
      // Im Hintergrund kann niemand zustimmen — beim nächsten manuellen
      // Versand im Vordergrund wird gefragt.
      return const SmsGatewayRun(note: 'SMS-Berechtigung fehlt (App einmal öffnen)');
    }

    final api = ApiService();
    final queueRes = await api.getTerminSmsQueue();
    if (queueRes['success'] != true) {
      return SmsGatewayRun(note: 'Warteschlange nicht erreichbar: ${queueRes['message'] ?? ''}');
    }

    final rows = (queueRes['queue'] as List? ?? []).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return const SmsGatewayRun();

    // Nur Zeilen, deren Nummer hier auch wirklich sendbar ist. Der Cron prüft
    // dasselbe, aber die Nummer kann sich seitdem geändert haben.
    final sendbar = <Map<String, dynamic>, SmsNumberCheck>{};
    var skipped = 0;
    for (final row in rows) {
      final check = SmsService.check(row['telefon_mobil']?.toString());
      if (check.canSend) {
        sendbar[row] = check;
      } else {
        skipped++;
        await api.reportTerminSms(
          terminId: _asInt(row['termin_id']),
          userId: _asInt(row['user_id']),
          status: 'skipped',
          error: check.label,
        );
      }
    }
    if (sendbar.isEmpty) return SmsGatewayRun(skipped: skipped);

    final deviceId = await _deviceId();
    final claimRes = await api.claimTerminSms(
      deviceId: deviceId,
      ids: sendbar.keys.map((r) => _asInt(r['id'])).toList(),
    );
    final claimed = ((claimRes['claimed'] as List?) ?? []).map(_asInt).toSet();

    var sent = 0;
    var failed = 0;
    for (final entry in sendbar.entries) {
      final row = entry.key;
      // Nicht bekommen heißt: ein anderes Gerät war schneller.
      if (!claimed.contains(_asInt(row['id']))) continue;

      final terminDate = DateTime.tryParse(row['termin_date']?.toString() ?? '');
      if (terminDate == null) {
        failed++;
        await api.reportTerminSms(
          terminId: _asInt(row['termin_id']),
          userId: _asInt(row['user_id']),
          status: 'failed',
          error: 'Termindatum unlesbar',
        );
        continue;
      }

      final text = SmsService.buildTerminSms(
        terminDate: terminDate,
        title: row['title']?.toString() ?? '',
        location: row['location']?.toString() ?? '',
        description: row['description']?.toString(),
        durationMinutes: int.tryParse(row['duration_minutes']?.toString() ?? ''),
        // Sprache aus dem Profil des Mitglieds — dieselbe, in die auch der
        // Live-Chat übersetzt. Fehlt sie, fällt buildTerminSms auf Deutsch
        // zurück.
        language: row['preferred_language']?.toString(),
        // Anrede aus Verifizierung Stufe 1.
        vorname: row['vorname']?.toString(),
        nachname: row['nachname']?.toString(),
        geschlecht: row['geschlecht']?.toString(),
      );
      final outcome = await SmsService.send(number: entry.value.e164!, text: text);

      if (outcome.isSuccess) {
        sent++;
      } else {
        failed++;
      }
      await api.reportTerminSms(
        terminId: _asInt(row['termin_id']),
        userId: _asInt(row['user_id']),
        status: outcome.isSuccess ? 'sent' : 'failed',
        error: outcome.isSuccess ? null : outcome.message,
      );

      // Nicht retryable (Berechtigung weg, Nummer kaputt) → der Rest des
      // Durchlaufs würde genauso scheitern.
      if (!outcome.isSuccess && !outcome.isRetryable) break;
    }

    // Medikamenten-Erinnerungen laufen über dieselbe SIM, aber eine eigene
    // Warteschlange. Sie kommen NACH den Terminen dran: ein verpasster Termin
    // ist der teurere Fehler.
    final med = await _medikamenteAbarbeiten(api);
    sent += med.sent;
    failed += med.failed;
    skipped += med.skipped;

    // Wetterwarnungen zuletzt, aber nur, weil sie am seltensten anfallen —
    // inhaltlich sind sie die dringendsten. Der Server hat sie schon auf
    // „schwer" und aufwärts gefiltert.
    final wetter = await _wetterAbarbeiten(api);
    sent += wetter.sent;
    failed += wetter.failed;
    skipped += wetter.skipped;

    final result = SmsGatewayRun(sent: sent, failed: failed, skipped: skipped);
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kLastRunKey, DateTime.now().toIso8601String());
    await sp.setString(_kLastResultKey, result.toString());
    _log.info('SMS-Gateway-Durchlauf: $result', tag: 'SMS_GW');
    return result;
  }

  /// Holt die fälligen Medikamenten-Erinnerungen und verschickt sie.
  ///
  /// Der Server reiht nur ein, was eine ausdrückliche Einwilligung hat
  /// (Art. 9 DSGVO) — hier wird deshalb nicht noch einmal geprüft, sondern
  /// nur noch die Nummer.
  static Future<SmsGatewayRun> _medikamenteAbarbeiten(ApiService api) async {
    final res = await api.getMedikamentSmsQueue();
    if (res['success'] != true) return const SmsGatewayRun();

    final rows = (res['queue'] as List? ?? []).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return const SmsGatewayRun();

    final sendbar = <Map<String, dynamic>, SmsNumberCheck>{};
    var skipped = 0;
    for (final row in rows) {
      final check = SmsService.check(row['telefon_mobil']?.toString());
      if (check.canSend) {
        sendbar[row] = check;
      } else {
        skipped++;
        await api.reportMedikamentSms(
          id: _asInt(row['id']),
          status: 'skipped',
          error: check.label,
        );
      }
    }
    if (sendbar.isEmpty) return SmsGatewayRun(skipped: skipped);

    final claimRes = await api.claimMedikamentSms(
      deviceId: await _deviceId(),
      ids: sendbar.keys.map((r) => _asInt(r['id'])).toList(),
    );
    final claimed = ((claimRes['claimed'] as List?) ?? []).map(_asInt).toSet();

    var sent = 0;
    var failed = 0;
    for (final entry in sendbar.entries) {
      final row = entry.key;
      final id = _asInt(row['id']);
      if (!claimed.contains(id)) continue;

      final text = SmsService.buildMedikamentSms(
        slot: row['slot']?.toString() ?? 'morgens',
        medikamente: row['medikamente']?.toString() ?? '',
        language: row['preferred_language']?.toString(),
        vorname: row['vorname']?.toString(),
        nachname: row['nachname']?.toString(),
        geschlecht: row['geschlecht']?.toString(),
      );
      final outcome = await SmsService.send(number: entry.value.e164!, text: text);

      if (outcome.isSuccess) {
        sent++;
      } else {
        failed++;
      }
      await api.reportMedikamentSms(
        id: id,
        status: outcome.isSuccess ? 'sent' : 'failed',
        error: outcome.isSuccess ? null : outcome.message,
      );

      if (!outcome.isSuccess && !outcome.isRetryable) break;
    }

    return SmsGatewayRun(sent: sent, failed: failed, skipped: skipped);
  }

  /// Verschickt die vom Server eingereihten Wetterwarnungen.
  static Future<SmsGatewayRun> _wetterAbarbeiten(ApiService api) async {
    final res = await api.getWetterSmsQueue();
    if (res['success'] != true) return const SmsGatewayRun();

    final rows = (res['queue'] as List? ?? []).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return const SmsGatewayRun();

    final sendbar = <Map<String, dynamic>, SmsNumberCheck>{};
    var skipped = 0;
    for (final row in rows) {
      final check = SmsService.check(row['telefon_mobil']?.toString());
      if (check.canSend) {
        sendbar[row] = check;
      } else {
        skipped++;
        await api.reportWetterSms(
          id: _asInt(row['id']),
          status: 'skipped',
          error: check.label,
        );
      }
    }
    if (sendbar.isEmpty) return SmsGatewayRun(skipped: skipped);

    final claimRes = await api.claimWetterSms(
      deviceId: await _deviceId(),
      ids: sendbar.keys.map((r) => _asInt(r['id'])).toList(),
    );
    final claimed = ((claimRes['claimed'] as List?) ?? []).map(_asInt).toSet();

    var sent = 0;
    var failed = 0;
    for (final entry in sendbar.entries) {
      final row = entry.key;
      final id = _asInt(row['id']);
      if (!claimed.contains(id)) continue;

      final text = SmsService.buildWetterSms(
        event: row['event']?.toString() ?? '',
        headline: row['headline']?.toString() ?? '',
        severity: row['severity']?.toString() ?? 'severe',
        language: row['preferred_language']?.toString(),
        vorname: row['vorname']?.toString(),
        nachname: row['nachname']?.toString(),
        geschlecht: row['geschlecht']?.toString(),
      );
      final outcome = await SmsService.send(number: entry.value.e164!, text: text);

      if (outcome.isSuccess) {
        sent++;
      } else {
        failed++;
      }
      await api.reportWetterSms(
        id: id,
        status: outcome.isSuccess ? 'sent' : 'failed',
        error: outcome.isSuccess ? null : outcome.message,
      );

      if (!outcome.isSuccess && !outcome.isRetryable) break;
    }

    return SmsGatewayRun(sent: sent, failed: failed, skipped: skipped);
  }

  static Future<String> _deviceId() async {
    try {
      final svc = DeviceKeyService();
      final id = svc.deviceId ?? await svc.loadStoredDeviceId();
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    return Platform.isAndroid ? 'android-unbekannt' : 'unbekannt';
  }

  static int _asInt(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
}

/// Einstiegspunkt des WorkManager-Isolats.
///
/// Läuft in einer eigenen Flutter-Engine ohne UI: ApiService muss hier von
/// vorn initialisiert werden (Device-Key + JWT aus dem sicheren Speicher).
@pragma('vm:entry-point')
void smsGatewayCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != kTerminSmsTask) return true;
    try {
      final ready = await ApiService().initialize();
      if (!ready) {
        _log.warning('SMS-Gateway: ApiService nicht bereit', tag: 'SMS_GW');
        // true, damit WorkManager nicht sofort erneut startet — der nächste
        // reguläre Durchlauf versucht es wieder.
        return true;
      }
      await TerminSmsGatewayService.runOnce(background: true);
      return true;
    } catch (e) {
      _log.error('SMS-Gateway-Hintergrundjob fehlgeschlagen: $e', tag: 'SMS_GW');
      return false;
    }
  });
}
