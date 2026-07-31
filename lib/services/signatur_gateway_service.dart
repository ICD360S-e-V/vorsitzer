import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'device_key_service.dart';
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
  /// Wie viele Durchläufe hintereinander gescheitert sind.
  int _fehlerInFolge = 0;

  /// Was zuletzt schiefging — wörtlich, nicht geraten. Steht in der
  /// Benachrichtigung.
  String _letzterGrund = '';

  /// Ist ApiService in DIESEM Isolate angemeldet?
  ///
  /// Der Dienst läuft in einem eigenen Isolate mit eigenen Singletons. Ein
  /// frisches ApiService hat weder Device-Key noch JWT, und `_headers` WIRFT
  /// dann, bevor überhaupt eine Anfrage gebaut wird. Genau daran hing der
  /// Dienst 236 Durchläufe lang fest, während im Serverlog nichts ankam.
  /// Der WorkManager-Pfad macht das seit jeher richtig
  /// (smsGatewayCallbackDispatcher ruft initialize() vor runOnce).
  bool _angemeldet = false;

  /// Läuft der Log-Versand an den Server aus DIESEM Isolate?
  bool _fernprotokollLaeuft = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[SIG_GW] Dienst gestartet ($starter)');
    await _anmelden();
  }

  /// Meldet dieses Isolate an. Darf scheitern — beim Gerätestart ist oft noch
  /// kein Netz da; dann wird es beim nächsten Takt erneut versucht, statt den
  /// Dienst dauerhaft blind laufen zu lassen.
  Future<bool> _anmelden() async {
    if (_angemeldet) return true;
    try {
      _angemeldet = await ApiService().initialize();

      // initialize() sagt nur „nicht sauber angemeldet" — das ist nicht
      // dasselbe wie „kann nicht senden". Liegt ein Device-Key im Speicher,
      // baut _headers, und die Anfrage geht raus. Dann lieber senden und ein
      // 403 im Serverlog erzeugen, als hier stumm stehenzubleiben: ein
      // sichtbarer Fehler ist mehr wert als gar keiner. Genau daran ist diese
      // Störung 80 Minuten lang unsichtbar geblieben.
      if (!_angemeldet && DeviceKeyService().deviceKey != null) {
        _angemeldet = true;
        _log.warning(
            'Anmeldung unbestätigt, Device-Key vorhanden — Versand läuft trotzdem',
            tag: 'SIG_GW');
      } else if (!_angemeldet) {
        _letzterGrund = 'Kein Device-Key im Dienst — Gerät neu anmelden';
      }
    } catch (e) {
      _angemeldet = false;
      _letzterGrund = 'Anmeldung fehlgeschlagen: $e';
      debugPrint('[SIG_GW] initialize(): $e');
    }

    if (_angemeldet) await _fernprotokollStarten();
    return _angemeldet;
  }

  /// Schaltet den Log-Versand an den Server für DIESES Isolate ein.
  ///
  /// Ohne das bleibt jede Störung des Dienstes auf dem Tablet liegen: der
  /// Upload wird sonst nur vom Dashboard gestartet (dashboard_screen.dart:200),
  /// und das läuft in einem anderen Isolate. Bei dieser Störung gab es deshalb
  /// serverseitig keine einzige Spur — weder eine Anfrage noch eine Logzeile.
  Future<void> _fernprotokollStarten() async {
    if (_fernprotokollLaeuft) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final mgnr = prefs.getString('mitgliedernummer');
      if (mgnr == null || mgnr.isEmpty) return;
      await _log.init();
      _log.startUpload(mgnr);
      _fernprotokollLaeuft = true;
    } catch (e) {
      debugPrint('[SIG_GW] Fernprotokoll nicht gestartet: $e');
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    if (!await _anmelden()) {
      _scheitern(_letzterGrund, timestamp);
      return;
    }

    try {
      final lauf = await TerminSmsGatewayService.runOnce(background: true);

      // Ein Durchlauf mit `note` ist kein Absturz, aber auch kein Erfolg —
      // z. B. fehlende SMS-Berechtigung. Das gehört sichtbar gemacht, sonst
      // steht die Benachrichtigung auf „aktiv", während nichts rausgeht.
      if (lauf.note != null) {
        _scheitern(lauf.note!, timestamp);
        return;
      }

      _fehlerInFolge = 0;
      _letzterGrund = '';
      _seit = null;
      FlutterForegroundTask.updateService(
        notificationTitle: 'SMS-Gateway aktiv',
        notificationText: lauf.didSomething
            ? 'Zuletzt ${_uhrzeit(timestamp)}: $lauf'
            : 'Bereit — zuletzt geprüft ${_uhrzeit(timestamp)}',
      );
    } catch (e) {
      // Sollte nach dem Fix nicht mehr vorkommen: die Warteschlangen-Aufrufe
      // fangen inzwischen selbst. Bleibt als Netz, damit ein unerwarteter
      // Fehler den Dienst nicht beendet.
      _scheitern('Unerwartet: $e', timestamp);
    }
  }

  /// Zählt den Fehlschlag und schreibt den GRUND in die Benachrichtigung.
  ///
  /// Vorher stand dort pauschal „keine Verbindung — Codes gehen nicht raus".
  /// Das war eine Behauptung, die niemand geprüft hatte: in Wahrheit war das
  /// Gerät in diesem Isolate nicht angemeldet, es gab nie einen
  /// Verbindungsversuch. Die falsche Meldung hat die Suche 80 Minuten lang zum
  /// WLAN und zum Server geschickt, wo nichts zu finden war.
  ///
  /// Deshalb steht jetzt drei Dinge in der Meldung: WAS schiefging (wörtlich,
  /// vom Aufrufer durchgereicht), SEIT WANN (Uhrzeit statt nur Anzahl) und ob
  /// überhaupt jemand außer dem Tablet davon weiß (Fernprotokoll).
  void _scheitern(String grund, DateTime zeitpunkt) {
    _fehlerInFolge++;
    _letzterGrund = grund;
    _seit ??= zeitpunkt;
    debugPrint('[SIG_GW] Durchlauf $_fehlerInFolge gescheitert: $grund');

    // Erst ab drei in Folge protokollieren und melden. Ein einzelner Aussetzer
    // ist normal (Funkloch, Serverneustart) und soll weder blinken noch das
    // Serverprotokoll fluten.
    if (_fehlerInFolge < 3) return;

    // Nur an den Schwellen, sonst schriebe der Dienst alle 20 Sekunden eine
    // Zeile: bei 3, dann alle 15 Fehlschläge (= alle 5 Minuten).
    if (_fehlerInFolge == 3 || _fehlerInFolge % 15 == 0) {
      _log.error('TAN-Gateway steht seit $_fehlerInFolge Versuchen: $grund',
          tag: 'SIG_GW');
    }

    FlutterForegroundTask.updateService(
      notificationTitle: 'SMS-Gateway gestört — TAN geht nicht raus',
      notificationText: '$grund (seit ${_uhrzeit(_seit!)}, '
          '$_fehlerInFolge Versuche)'
          '${_fernprotokollLaeuft ? '' : ' — nur auf diesem Gerät sichtbar'}',
    );
  }

  /// Wann die aktuelle Störung begann. Eine Uhrzeit sagt mehr als eine Anzahl:
  /// „seit 09:14" lässt sich mit dem Serverprotokoll vergleichen, „236
  /// Versuche" nicht.
  DateTime? _seit;

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
