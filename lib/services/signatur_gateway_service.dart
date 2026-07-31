import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'logger_service.dart';
import 'termin_sms_gateway_service.dart';

final _log = LoggerService();

/// Hält die TAN-Warteschlange auf dem Vereins-Tablet im Blick, auch wenn die
/// App zu ist.
///
/// WARUM ES DAS GEBEN MUSS
/// Der Server hat kein Mobilfunkmodem; jede SMS verlässt das Haus über die SIM
/// dieses Tablets. Für Termin-Erinnerungen reicht der WorkManager-Takt von 30
/// Minuten — die haben einen Tag Vorlauf. Für die TAN der digitalen
/// Unterschrift reicht er nicht: sie gilt fünf Minuten, und das Mitglied sitzt
/// in diesem Moment vor dem Unterschriftsfeld. Android lässt periodische Jobs
/// frühestens alle 15 Minuten laufen, also ist das auch nicht nachregelbar.
///
/// Der ntfy-Weckruf löst das nur, solange die App offen ist: der Stream hängt
/// am Dashboard und stirbt mit ihm. Ein Firebase-Push wäre die übliche Antwort
/// — den gibt es hier bewusst nicht, weil die App ohne Play Services über ein
/// eigenes F-Droid-Repo ausgeliefert wird.
///
/// Bleibt der Weg, den auch die F-Droid-Fassung von ntfy selbst geht: ein
/// laufender Dienst mit dauerhafter Verbindung.
///
/// WARUM ABFRAGEN STATT STREAM
/// Der Dienst fragt alle [_takt] Sekunden nach, statt den ntfy-Stream in den
/// Dienst zu verlegen. Ein Stream, der stirbt, sieht von außen genauso aus wie
/// einer, über den gerade nichts kommt — und das wäre hier der teuerste Fehler:
/// niemand merkt es, bis ein Mitglied vergeblich auf einen Code wartet. Eine
/// Abfrage, die scheitert, scheitert sichtbar und wird beim nächsten Takt
/// wiederholt. Zwanzig Sekunden sind gegenüber fünf Minuten Gültigkeit
/// reichlich, und der ntfy-Weckruf bleibt bei offener App zusätzlich aktiv.
///
/// WO ER NICHT LÄUFT
/// Nur auf dem Gerät, dessen Gateway-Schalter an ist. Auf den übrigen
/// Vorsitzer-Geräten und auf dem Desktop wird er nie gestartet — sonst ginge
/// dieselbe TAN mehrfach raus, und der Akku der anderen Geräte hinge daran.
class SignaturGatewayService {
  /// Abstand zwischen zwei Blicken in die Warteschlange.
  static const _takt = Duration(seconds: 20);

  static bool get istUnterstuetzt => Platform.isAndroid;

  /// Einmal beim App-Start einrichten. Startet nichts von allein.
  static Future<void> initialisieren() async {
    if (!istUnterstuetzt) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'signatur_gateway',
        channelName: 'SMS-Gateway des Vereins',
        // Die Dauerbenachrichtigung lässt sich nicht wegdrücken — also soll
        // sie wenigstens erklären, wofür sie da ist. Wer sie nicht versteht,
        // schaltet den Dienst ab, und dann kommt keine TAN mehr an.
        channelDescription:
            'Zeigt an, dass dieses Gerät die Bestätigungscodes des Vereins '
            'als SMS verschickt.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(_takt.inMilliseconds),
        autoRunOnBoot: true,
        // Nach einem erzwungenen Beenden von allein wiederkommen. Samsung
        // beendet Hintergrundarbeit aggressiv; ohne das bliebe der Dienst
        // nach dem ersten Eingriff für immer weg.
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<bool> laeuft() async {
    if (!istUnterstuetzt) return false;
    return FlutterForegroundTask.isRunningService;
  }

  /// Startet den Dienst. Nur aufrufen, wenn dieses Gerät Gateway ist.
  static Future<bool> starten() async {
    if (!istUnterstuetzt) return false;
    if (await laeuft()) return true;

    // Ohne Benachrichtigungsrecht zeigt Android die Dauerbenachrichtigung
    // nicht an und verweigert den Dienst. Lieber hier fragen als später
    // rätseln, warum nichts läuft.
    final recht = await FlutterForegroundTask.checkNotificationPermission();
    if (recht != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    final ergebnis = await FlutterForegroundTask.startService(
      serviceTypes: const [ForegroundServiceTypes.specialUse],
      notificationTitle: 'SMS-Gateway aktiv',
      notificationText: 'Bereit, Bestätigungscodes zu verschicken',
      callback: signaturGatewayCallback,
    );

    final ok = ergebnis is ServiceRequestSuccess;
    _log.info('Signatur-Gateway-Dienst: ${ok ? 'gestartet' : 'FEHLGESCHLAGEN ($ergebnis)'}',
        tag: 'SIG_GW');
    return ok;
  }

  static Future<void> stoppen() async {
    if (!istUnterstuetzt) return;
    await FlutterForegroundTask.stopService();
    _log.info('Signatur-Gateway-Dienst gestoppt', tag: 'SIG_GW');
  }
}

/// Einstiegspunkt des Dienst-Isolates. Muss oberste Ebene sein.
@pragma('vm:entry-point')
void signaturGatewayCallback() {
  FlutterForegroundTask.setTaskHandler(_SignaturGatewayHandler());
}

class _SignaturGatewayHandler extends TaskHandler {
  /// Wie viele Durchläufe hintereinander gescheitert sind. Steht in der
  /// Benachrichtigung, damit ein Netz- oder Anmeldeproblem am Tablet sichtbar
  /// wird, statt still zu bleiben, bis jemand einen Code vermisst.
  int _fehlerInFolge = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[SIG_GW] Dienst gestartet ($starter)');
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    try {
      final lauf = await TerminSmsGatewayService.runOnce(background: true);
      _fehlerInFolge = 0;

      if (lauf.didSomething) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'SMS-Gateway aktiv',
          notificationText: 'Zuletzt ${_uhrzeit(timestamp)}: $lauf',
        );
      }
    } catch (e) {
      _fehlerInFolge++;
      debugPrint('[SIG_GW] Durchlauf fehlgeschlagen ($_fehlerInFolge): $e');

      // Ein Aussetzer ist normal (Funkloch, Serverneustart). Erst wenn es
      // mehrfach hintereinander scheitert, gehört das auf den Bildschirm —
      // sonst blinkt die Benachrichtigung bei jedem kurzen Netzausfall.
      if (_fehlerInFolge >= 3) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'SMS-Gateway gestört',
          notificationText:
              'Seit $_fehlerInFolge Versuchen keine Verbindung — Codes gehen nicht raus',
        );
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[SIG_GW] Dienst beendet (Zeitüberschreitung: $isTimeout)');
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  static String _uhrzeit(DateTime d) {
    String zwei(int n) => n.toString().padLeft(2, '0');
    return '${zwei(d.hour)}:${zwei(d.minute)}';
  }
}
