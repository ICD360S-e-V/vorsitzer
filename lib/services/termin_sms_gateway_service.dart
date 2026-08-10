import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'anruf_gateway_service.dart';
import 'api_service.dart';
import 'device_key_service.dart';
import 'logger_service.dart';
import 'ntfy_service.dart';
import 'signatur_gateway_service.dart';
import 'sms_service.dart';
import 'speedtest_service.dart';

final _log = LoggerService();

/// Name des Hintergrundjobs (muss in [icdHintergrundDispatcher] wieder
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

  /// Takt, solange die App läuft.
  ///
  /// Das Vereins-Tablet steht praktisch immer mit offener App da — und genau
  /// dann feuert `resumed` nie, weil die App nie in den Hintergrund geht.
  /// Übrig blieb der WorkManager-Job, den Samsung zuverlässig einschläfert:
  /// am 30.07. gingen drei Medikamenten-Erinnerungen gar nicht raus, am 31.07.
  /// kamen Morgen- und Mittagsdosis gemeinsam um 17 Uhr an. Ein simpler Timer
  /// im laufenden Prozess ist für dieses Gerät die verlässlichste Uhr, die es
  /// gibt — er ersetzt den Job nicht, er deckt die Lücke, die er hinterlässt.
  static const _vordergrundTakt = Duration(minutes: 5);

  static Timer? _vordergrundTimer;

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
      _starteVordergrundTimer();
      // Der Wachdienst hängt am selben Schalter: er ist der einzige Weg, auf
      // dem eine TAN bei geschlossener App noch rechtzeitig rausgeht.
      await SignaturGatewayService.starten();
    } else {
      await _cancelPeriodic();
      _vordergrundTimer?.cancel();
      _vordergrundTimer = null;
      // Der Wachdienst bedient inzwischen zwei Warteschlangen. Ihn hier
      // bedingungslos zu stoppen würde auf einem Gerät, das nur die Anrufe
      // übernimmt, die Fernwahl still mit abschalten — sichtbar wäre nur,
      // dass ein Klick am Rechner nichts mehr bewirkt.
      if (!await AnrufGatewayService.isEnabled()) {
        await SignaturGatewayService.stoppen();
      }
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
      // Sofort reagieren, wenn jemand von einem Gerät ohne SIM eine SMS
      // einreiht — sonst läge sie bis zum nächsten 30-Minuten-Takt herum.
      NtfyService.onGatewayWake = () {
        _log.info('SMS-Gateway: Weckruf erhalten', tag: 'SMS_GW');
        runOnce();
      };

      // Der EINZIGE initialize()-Aufruf der App — siehe Kommentar bei
      // [icdHintergrundDispatcher]. Auch der Speedtest hängt daran, deshalb
      // läuft dieser Aufruf unabhängig davon, ob das Gerät SMS-Gateway ist.
      //
      // SpeedtestService.jobNachziehen() steht bewusst NICHT hier, sondern
      // beim Aufrufer: diese Methode kehrt oben bei !isAndroid sofort zurück,
      // der Speedtest lief dadurch auf Desktop nie an.
      await Workmanager().initialize(icdHintergrundDispatcher);
      await SignaturGatewayService.initialisieren();

      // Nicht blind neu registrieren, sondern nur wenn der Job fehlt — das
      // fängt genau die Fälle ab, in denen Samsung ihn stillschweigend
      // entsorgt hat (Force Stop, Speicher geleert, großes Update).
      if (await isEnabled()) {
        await ensureJobScheduled();
        _starteVordergrundTimer();
        // Dasselbe für den Wachdienst: nach einem Force Stop ist er weg, der
        // Schalter steht aber weiter auf an. Ohne diese Zeile liefe das
        // Tablet scheinbar als Gateway und ließe jede TAN verfallen.
        await SignaturGatewayService.starten();
      }
    } catch (e) {
      _log.warning('WorkManager-Init fehlgeschlagen: $e', tag: 'SMS_GW');
    }
  }

  /// Prüft die Warteschlangen, solange die App läuft.
  static void _starteVordergrundTimer() {
    _vordergrundTimer?.cancel();
    _vordergrundTimer = Timer.periodic(_vordergrundTakt, (_) => runOnce());
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

    // TAN-SMS zuerst — als einzige hat sie eine Uhr im Nacken. Der Code gilt
    // fünf Minuten, und das Mitglied sitzt in diesem Moment vor dem
    // Unterschriftsfeld und wartet. Eine Terminerinnerung, die dafür eine
    // Runde später rausgeht, kostet niemanden etwas.
    final tan = await _signaturTanAbarbeiten(api);

    final queueRes = await api.getTerminSmsQueue();
    if (queueRes['success'] != true) {
      return SmsGatewayRun(
        sent: tan.sent,
        failed: tan.failed,
        skipped: tan.skipped,
        note: 'Warteschlange nicht erreichbar: ${queueRes['message'] ?? ''}',
      );
    }

    var sent = tan.sent;
    var failed = tan.failed;
    var skipped = tan.skipped;

    final rows = (queueRes['queue'] as List? ?? []).cast<Map<String, dynamic>>();
    if (rows.isNotEmpty) {
      final termine = await _termineAbarbeiten(api, rows);
      sent += termine.sent;
      failed += termine.failed;
      skipped += termine.skipped;
    }

    return _restAbarbeiten(api, sent: sent, failed: failed, skipped: skipped);
  }

  /// Die Terminerinnerungen eines Durchlaufs.
  ///
  /// Früher stand das direkt in [runOnce] — mit der Folge, dass eine leere
  /// Terminwarteschlange die Methode verließ, bevor Medikamente und Wetter
  /// überhaupt drankamen. Die beiden gingen also nur raus, wenn zufällig auch
  /// eine Terminerinnerung anstand.
  static Future<SmsGatewayRun> _termineAbarbeiten(
    ApiService api,
    List<Map<String, dynamic>> rows,
  ) async {

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

    return SmsGatewayRun(sent: sent, failed: failed, skipped: skipped);
  }

  /// Medikamente und Wetter, dazu das Protokoll des Durchlaufs.
  static Future<SmsGatewayRun> _restAbarbeiten(
    ApiService api, {
    required int sent,
    required int failed,
    required int skipped,
  }) async {
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

    // Zuletzt der Live-Chat: von Hand geschriebene Nachrichten, die der
    // Vorsitzer vom Schreibtisch aus als SMS abgeschickt hat. Bewusst ans
    // Ende — die automatischen Erinnerungen haben eine Frist, diese hier
    // wartet nur auf den nächsten Weckruf, der ohnehin sofort kommt.
    final chatSms = await _chatSmsAbarbeiten(api);
    sent += chatSms.sent;
    failed += chatSms.failed;
    skipped += chatSms.skipped;

    // Gegenrichtung: was das Mitglied per SMS geantwortet hat, in den Verlauf
    // holen. Ganz zum Schluss und mit eigenem Takt — hier wartet niemand auf
    // eine Frist, und es ist der einzige Schritt, der nichts verschickt.
    final eingang = await _eingehendeSmsHolen(api);

    final result = SmsGatewayRun(sent: sent, failed: failed, skipped: skipped);
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kLastRunKey, DateTime.now().toIso8601String());
    await sp.setString(_kLastResultKey,
        eingang.isEmpty ? result.toString() : '$result · $eingang');
    // Nur schreiben, wenn wirklich etwas geschehen ist.
    //
    // ⚠️ Diese eine Zeile lief bisher bei JEDEM Durchlauf, also alle 20
    // Sekunden, rund um die Uhr — am Vormittag des 10.08. waren es 1.178
    // Zeilen „gesendet: 0, fehlgeschlagen: 0, übersprungen: 0". Jede davon
    // füllte die Warteschlange des Protokollversands, und weil die dadurch nie
    // leer wurde, ging alle 30 Sekunden eine Übertragung ans Netz. Ein
    // Ereignisprotokoll, das im Ruhezustand schreibt, protokolliert nichts —
    // es hält nur das Funkmodul wach.
    //
    // ⚠️ `eingang` gehört mit in die Bedingung. Ein empfangenes SMS ist ein
    // Ereignis, auch wenn kein einziges verschickt wurde — hinge die Zeile nur
    // an [SmsGatewayRun.didSomething], verschwände ausgerechnet die
    // Gegenrichtung stillschweigend aus dem Protokoll.
    //
    // Der letzte Lauf steht weiterhin vollständig in den Einstellungen
    // (_kLastRunKey / _kLastResultKey), inklusive der Nullen. Sichtbar bleibt
    // also alles; verschickt wird nur, was jemand lesen würde.
    if (result.didSomething || eingang.isNotEmpty) {
      _log.info('SMS-Gateway-Durchlauf: $result'
          '${eingang.isEmpty ? '' : ' · Eingang: $eingang'}', tag: 'SMS_GW');
    }
    return result;
  }

  /// Wie oft der Posteingang durchsucht wird.
  ///
  /// Der Gateway-Takt liegt bei 20 Sekunden, weil eine TAN fünf Minuten gilt.
  /// Für eine Antwort des Mitglieds ist das unnötig scharf: sie wartet auch
  /// zwei Minuten, und jeder Durchgang kostet eine Abfrage an den Server plus
  /// eine an den Posteingang.
  static const _eingangTakt = Duration(minutes: 2);
  static const _kEingangZuletztKey = 'sms_eingang_zuletzt';

  /// Holt die SMS, die Mitglieder an diese SIM geschickt haben.
  ///
  /// Gibt einen kurzen Zustandstext zurück, der in `lastResult` landet — sonst
  /// wäre von aussen nicht zu unterscheiden, ob nichts ankam oder ob das Lesen
  /// gar nicht erlaubt ist. Genau diese Verwechslung ist der teuerste Fehler
  /// des ganzen Wegs: bei `MODE_IGNORED` liefert Android null Zeilen, ohne zu
  /// scheitern.
  static Future<String> _eingehendeSmsHolen(ApiService api) async {
    final sp = await SharedPreferences.getInstance();
    final zuletzt = DateTime.tryParse(sp.getString(_kEingangZuletztKey) ?? '');
    if (zuletzt != null &&
        DateTime.now().difference(zuletzt) < _eingangTakt) {
      return '';
    }

    try {
      final nummern = await api.getSmsEingangNummern();
      if (nummern['success'] != true) {
        return 'Eingang: Warteschlange nicht erreichbar';
      }
      final daten = (nummern['data'] as Map?) ?? nummern;
      // Erst NACH der erfolgreichen Abfrage stempeln — aber VOR dem Ausstieg
      // bei leerer Liste: bei Netzfehler soll der nächste Takt es sofort
      // wieder versuchen, bei „niemand hat eine Nummer" aber nicht alle
      // 20 Sekunden erneut fragen.
      await sp.setString(_kEingangZuletztKey, DateTime.now().toIso8601String());

      final mitglieder =
          ((daten['mitglieder'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (mitglieder.isEmpty) return '';

      final seitMs = (daten['seit_ms'] as num?)?.toInt() ?? 0;
      final verlauf = await SmsService.readConversations(
        mitglieder.map((m) => m['nummer'].toString()).toList(),
        seit: seitMs > 0 ? DateTime.fromMillisecondsSinceEpoch(seitMs) : null,
      );

      if (!verlauf.gelesen) {
        // Das ist der Fall, den niemand raten können soll.
        _log.warning('SMS-Eingang nicht lesbar: ${verlauf.lage.name}'
            '${verlauf.fehler != null ? ' (${verlauf.fehler})' : ''}', tag: 'SMS_GW');
        return 'Eingang gesperrt: ${verlauf.lage.name}';
      }
      if (verlauf.nachrichten.isEmpty) {
        // ⚠️ Hier NICHT schweigen. „Es kam nichts an" und „es kam etwas an,
        // gehörte aber zu keiner hinterlegten Rufnummer" sind zwei völlig
        // verschiedene Lagen — und nur die zweite ist ein Hinweis darauf, dass
        // eine Nummer in Stufe 1 fehlt oder falsch geschrieben ist. Ohne die
        // Unterscheidung sucht man den Fehler beim Lesen, wo keiner ist.
        return verlauf.geprueft == 0
            ? ''
            : 'Eingang: ${verlauf.geprueft} gelesen, keine zugeordnet';
      }

      // Nummer -> Mitglied, aus derselben Liste, die der Server ausgegeben hat.
      // Die user_id mitzuschicken ist kein Vertrauensvorschuss: der Server
      // prüft sie gegen seine eigene Zuordnung und verwirft bei Widerspruch.
      final nachNummer = {
        for (final m in mitglieder) m['nummer'].toString(): m['user_id'],
      };

      final ergebnis = await api.importSmsEingang(
        deviceId: await _deviceId(),
        nachrichten: [
          for (final n in verlauf.nachrichten)
            {
              'geraet_id': n.geraetId,
              'nummer': n.nummer,
              if (nachNummer[n.nummer] != null) 'user_id': nachNummer[n.nummer],
              'text': n.text,
              'empfangen_ms': n.empfangen.millisecondsSinceEpoch,
            }
        ],
      );

      final e = (ergebnis['data'] as Map?) ?? ergebnis;
      final importiert = (e['importiert'] as num?)?.toInt() ?? 0;
      final verworfen = ((e['verworfen'] as List?) ?? const []).length;
      if (importiert == 0 && verworfen == 0) return '';
      // Abgeschnitten heisst: es lag mehr bereit. Der nächste Takt holt den
      // Rest, aber verschweigen darf man es nicht.
      return 'Eingang: $importiert von ${verlauf.geprueft} übernommen'
          '${verworfen > 0 ? ", $verworfen verworfen" : ""}'
          '${verlauf.abgeschnitten ? ", mehr wartet" : ""}';
    } catch (e) {
      _log.warning('SMS-Eingang fehlgeschlagen: $e', tag: 'SMS_GW');
      return 'Eingang: Fehler';
    }
  }

  /// Verschickt die TANs der digitalen Unterschrift.
  ///
  /// Anders als bei Termin, Medikament und Wetter gibt es keine Vorlage: den
  /// Text hat der Server schon fertig gebaut, inklusive Code. Er wird nur noch
  /// von Emoji und Zierrat befreit ([SmsService.sanitize]) — mehr darf mit
  /// einer TAN nicht passieren, jedes umgeschriebene Zeichen macht sie falsch.
  static Future<SmsGatewayRun> _signaturTanAbarbeiten(ApiService api) async {
    final res = await api.getSignaturTanQueue();
    if (res['success'] != true) return const SmsGatewayRun();

    final rows = (res['queue'] as List? ?? []).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return const SmsGatewayRun();

    final sendbar = <Map<String, dynamic>, SmsNumberCheck>{};
    var skipped = 0;
    for (final row in rows) {
      final check = SmsService.check(row['telefon']?.toString());
      if (check.canSend) {
        sendbar[row] = check;
      } else {
        skipped++;
        await api.reportSignaturTan(
          id: _asInt(row['id']),
          status: 'fehler',
          error: check.label,
        );
      }
    }
    if (sendbar.isEmpty) return SmsGatewayRun(skipped: skipped);

    final claimRes = await api.claimSignaturTan(
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

      final text = SmsService.sanitize(row['body']?.toString() ?? '');
      if (text.isEmpty) {
        // Leerer Text heißt: der Server hat die Zeile nach dem Versand schon
        // geräumt. Nichts zu tun, und nichts zu melden.
        continue;
      }

      final outcome = await SmsService.send(number: entry.value.e164!, text: text);

      if (outcome.isSuccess) {
        sent++;
      } else {
        failed++;
      }
      await api.reportSignaturTan(
        id: id,
        status: outcome.isSuccess ? 'gesendet' : 'fehler',
        error: outcome.isSuccess ? null : outcome.message,
      );

      if (!outcome.isSuccess && !outcome.isRetryable) break;
    }

    return SmsGatewayRun(sent: sent, failed: failed, skipped: skipped);
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

  /// Verschickt die im Live-Chat als SMS abgeschickten Nachrichten.
  ///
  /// Anders als bei Termin, Medikament und Wetter gibt es hier keine Vorlage:
  /// den Text hat der Vorsitzer selbst geschrieben. Er wird nur noch von
  /// Emoji und typografischem Zierrat befreit ([SmsService.sanitize]) —
  /// [SmsService.toGsm7] bleibt bewusst aus, weil es kyrillische und arabische
  /// Nachrichten zerstören und die eigenen Worte des Vorsitzers umschreiben
  /// würde. Kostet im Zweifel ein Segment mehr; der Verein hat eine SMS-Flat.
  static Future<SmsGatewayRun> _chatSmsAbarbeiten(ApiService api) async {
    final res = await api.getChatSmsOutbox();
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
        // Sollte nicht vorkommen — der Schalter im Chat ist ohne Nummer
        // gesperrt. Kann aber, wenn die Nummer nach dem Absenden gelöscht
        // wurde; dann steht der Grund am Vorgang statt ihn stumm zu verlieren.
        await api.reportChatSms(
          id: _asInt(row['id']),
          status: 'skipped',
          error: check.label,
        );
      }
    }
    if (sendbar.isEmpty) return SmsGatewayRun(skipped: skipped);

    final claimRes = await api.claimChatSms(
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

      final text = SmsService.sanitize(row['body']?.toString() ?? '');
      if (text.isEmpty) {
        skipped++;
        await api.reportChatSms(
          id: id,
          status: 'skipped',
          error: 'Text nach Bereinigung leer',
        );
        continue;
      }

      final outcome = await SmsService.send(number: entry.value.e164!, text: text);

      if (outcome.isSuccess) {
        sent++;
      } else {
        failed++;
      }
      await api.reportChatSms(
        id: id,
        status: outcome.isSuccess ? 'sent' : 'failed',
        segments: SmsService.segments(text),
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

/// Einstiegspunkt des WorkManager-Isolats — für ALLE Hintergrundjobs der App.
///
/// ES DARF NUR DIESEN EINEN GEBEN. `Workmanager().initialize()` merkt sich
/// genau einen Dispatcher; ein zweiter Aufruf mit einer anderen Funktion
/// überschreibt den ersten, und der überschriebene Job hört still auf zu
/// laufen — der Schalter in den Einstellungen bliebe dabei an. Neue
/// Hintergrundjobs kommen deshalb hier als weiterer Zweig dazu, statt sich
/// selbst zu registrieren.
///
/// Läuft in einer eigenen Flutter-Engine ohne UI: ApiService muss hier von
/// vorn initialisiert werden (Device-Key + JWT aus dem sicheren Speicher).
@pragma('vm:entry-point')
void icdHintergrundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      // ⚠️ VOR der Bereitschaftsprüfung. Der Lücken-Job läuft gerade dann,
      // wenn kein Netz da ist — er soll nur lokal vermerken, warum nicht
      // gemessen werden konnte, und braucht dafür weder API noch Anmeldung.
      // Hinter dem Gate stünde er genau in dem Fall still, für den es ihn gibt.
      if (taskName == kSpeedtestLueckeTask) {
        await SpeedtestService.lueckeProtokollieren();
        return true;
      }

      final ready = await ApiService().initialize();
      if (!ready) {
        _log.warning('Hintergrundjob $taskName: ApiService nicht bereit', tag: 'SMS_GW');
        // true, damit WorkManager nicht sofort erneut startet — der nächste
        // reguläre Durchlauf versucht es wieder.
        return true;
      }

      switch (taskName) {
        case kTerminSmsTask:
          await TerminSmsGatewayService.runOnce(background: true);
        case kSpeedtestTask:
          // Wirft nie: ein fehlgeschlagener Durchlauf wird selbst als Messwert
          // gespeichert. Genau der Ausfall ist ja das, was belegt werden soll.
          // imHintergrund: misst gerade eines der anderen beiden angemeldeten
          // Geräte, wird dieser Takt ausgelassen statt sich die Leitung zu
          // teilen — hier sieht niemand zu, der nächste kommt in 30 Minuten.
          await SpeedtestService.messen(imHintergrund: true);
        default:
          return true;
      }
      return true;
    } catch (e) {
      _log.error('Hintergrundjob $taskName fehlgeschlagen: $e', tag: 'SMS_GW');
      return false;
    }
  });
}
