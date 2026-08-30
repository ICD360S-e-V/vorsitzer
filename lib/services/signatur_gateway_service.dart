import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'anruf_gateway_service.dart';
import 'api_service.dart';
import 'device_key_service.dart';
import 'logger_service.dart';
import 'ntfy_service.dart';
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

  /// Abstand zwischen zwei Blicken in die SMS-Warteschlangen.
  ///
  /// Bewusst unabhängig vom Dienst-Takt: schlägt der Dienst wegen der Fernwahl
  /// alle fünf Sekunden, gilt das für den Wählauftrag — nicht für eine
  /// Termin-Erinnerung, die einen Tag Vorlauf hat. Siehe [_letzteSmsPruefung].
  static const smsTakt = _takt;

  /// Takt, sobald dieses Gerät auch Anrufe entgegennimmt.
  ///
  /// Eine TAN hat fünf Minuten Zeit, ein Wählauftrag zwei — und vor allem
  /// sitzt beim Anruf jemand vor dem Bildschirm und wartet. Zwanzig Sekunden
  /// Stille nach einem Klick sind von einem Ausfall nicht zu unterscheiden.
  static const _taktMitAnruf = Duration(seconds: 5);

  /// Welcher Takt gerade richtig ist.
  static Future<Duration> _passenderTakt() async =>
      await AnrufGatewayService.isEnabled() ? _taktMitAnruf : _takt;

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
        eventAction: ForegroundTaskEventAction.repeat(
            (await _passenderTakt()).inMilliseconds),
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

  /// Stellt den Takt des laufenden Dienstes auf die aktuelle Aufgabenlage um.
  ///
  /// Nötig, weil der Takt beim Start festgelegt wird: wer das Anruf-Gateway
  /// erst danach einschaltet, bekäme sonst weiter den 20-Sekunden-Takt und
  /// wartete nach jedem Klick am Rechner bis zu zwanzig Sekunden — ohne dass
  /// irgendwo stünde, warum.
  static Future<void> taktAnpassen() async {
    if (!istUnterstuetzt) return;
    if (!await laeuft()) return;
    final takt = await _passenderTakt();
    await FlutterForegroundTask.updateService(
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(takt.inMilliseconds),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _log.info('Wachdienst-Takt: ${takt.inSeconds} s', tag: 'SIG_GW');
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

  /// Ob die sipgate-Anmeldung diesen Prozess braucht.
  ///
  /// ⚠️ WARUM EIN GESETZTES FELD UND NICHT `SipgateService.autoAktiv()`.
  /// Der Schalter steht auf Android **voreingestellt an** — auch auf einem
  /// Gerät, das gar kein eigenes VoIP-Telefon hat und deshalb nie eine
  /// Anmeldung hält (Zustand `fremdesTelefon`). Würde hier der Schalter
  /// gelesen, zöge ausgerechnet der RDP-Kiosk eine Dauerbenachrichtigung samt
  /// Wachdienst hoch, für eine Registrierung, die er nie eingeht.
  /// [SipgateService] setzt das Feld deshalb genau dann, wenn es wirklich
  /// registriert — und nimmt es zurück, sobald nicht mehr.
  ///
  /// Nebenbei bleibt dieser Dienst damit frei von einem Import auf
  /// `sipgate_service.dart`, der einen Kreis schlösse.
  static bool sipgateHaeltRegistrierung = false;

  /// Braucht ihn überhaupt noch jemand?
  ///
  /// ⚠️ DIESE FRAGE STAND BIS ZUM 30.08.2026 AN ZWEI STELLEN, UND BEIDE
  /// KANNTEN NUR DIE JEWEILS ANDERE HÄLFTE: `AnrufGatewayService` fragte nur
  /// nach dem SMS-Gateway, `TerminSmsGatewayService` nur nach der Fernwahl.
  /// Solange es zwei Gründe gab, ging das auf. Mit dem dritten — der
  /// sipgate-Anmeldung, die im Haupt-Isolat lebt und ohne diesen Dienst von
  /// Android eingefroren werden darf — hätte jede der beiden Stellen den
  /// Wachdienst gestoppt, während der dritte ihn noch braucht. Sichtbar wäre
  /// davon nur gewesen, dass es irgendwann nicht mehr klingelt.
  static Future<bool> nochGebraucht() async =>
      sipgateHaeltRegistrierung ||
      await TerminSmsGatewayService.isEnabled() ||
      await AnrufGatewayService.isEnabled();

  /// Stoppt den Dienst — aber nur, wenn ihn niemand mehr braucht.
  static Future<void> stoppenWennUnnoetig() async {
    if (!istUnterstuetzt) return;
    if (await nochGebraucht()) return;
    await stoppen();
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

  /// Hängt DIESES Isolate am ntfy-Strom? Siehe [_weckleitungStarten].
  bool _weckleitungLaeuft = false;

  /// Wann zuletzt nach einem Wählauftrag gefragt wurde.
  DateTime? _letzteAnrufPruefung;

  /// Abstand, sobald die Weckleitung steht.
  ///
  /// Eine Minute, nicht länger: ein Wählauftrag verfällt nach zwei Minuten,
  /// eine TAN nach fünf. Reißt der Strom unbemerkt, wird beides trotzdem noch
  /// innerhalb seiner Gültigkeit gefunden — die Abfrage bleibt also eine echte
  /// Absicherung und nicht bloß eine beruhigende Zeile im Code.
  static const _langsam = Duration(minutes: 1);

  /// Ist diese Warteschlange wieder an der Reihe?
  ///
  /// [schnell] gilt ohne Weckleitung, [langsam] mit. Der Umschalter ist der
  /// Verbindungszustand, nicht ein Schalter in den Einstellungen: nur so fällt
  /// der Takt von allein zurück, wenn der Strom reißt, ohne dass jemand
  /// eingreifen muss.
  bool _faellig(
      DateTime jetzt, DateTime? zuletzt, Duration schnell, Duration langsam) {
    if (zuletzt == null) return true;
    final abstand = NtfyService().istVerbunden ? langsam : schnell;
    return jetzt.difference(zuletzt) >= abstand;
  }

  /// Wann zuletzt in die SMS-Warteschlangen geschaut wurde.
  ///
  /// ⚠️ Ohne das hängt der SMS-Teil am Takt des Anruf-Teils. Genau das ist am
  /// 08.08. passiert: `taktAnpassen()` stellte den Dienst wegen der Fernwahl
  /// von 20 auf 5 Sekunden, und die SMS-Abfrage wurde stillschweigend
  /// mitbeschleunigt — obwohl eine Termin-Erinnerung einen Tag Vorlauf hat.
  /// Im Serverprotokoll stieg jeder der fünf Warteschlangen-Endpunkte von
  /// 46 auf 750 Anfragen pro Stunde, und das Telefon war um 05:46 leer.
  DateTime? _letzteSmsPruefung;

  /// Was in der Benachrichtigung steht. Nur bei Änderung neu setzen.
  ///
  /// `updateService` bei JEDEM Takt heißt im 5-Sekunden-Rhythmus rund 17.000
  /// Neuzeichnungen der Dauerbenachrichtigung am Tag — für einen Text, der
  /// sich nur in der Uhrzeit unterscheidet und den niemand mitliest.
  String _letzterTitel = '';
  String _letzterText = '';

  /// Setzt die Benachrichtigung nur, wenn sich der Wortlaut wirklich ändert.
  void _melden(String titel, String text) {
    if (titel == _letzterTitel && text == _letzterText) return;
    _letzterTitel = titel;
    _letzterText = text;
    FlutterForegroundTask.updateService(
      notificationTitle: titel,
      notificationText: text,
    );
  }

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

    if (_angemeldet) {
      await _fernprotokollStarten();
      await _weckleitungStarten();
    }
    return _angemeldet;
  }

  /// Hängt DIESES Isolate an den ntfy-Strom.
  ///
  /// WARUM HIER UND NICHT NUR IM DASHBOARD
  /// Der Weckruf gab es längst — aber nur im Isolate der Oberfläche, und das
  /// stirbt mit dem Bildschirm. Genau dann, wenn das Telefon in der Tasche
  /// liegt, blieb also nur die Abfrage übrig, und die musste deshalb alle fünf
  /// Sekunden laufen. Das waren 17.280 Fragen am Tag für zwei, drei Anrufe.
  ///
  /// Ein Strom, den dieser Dienst selbst hält, lebt so lange wie der Dienst —
  /// also auch bei geschlossener App. Denselben Weg geht die F-Droid-Fassung
  /// von ntfy: ein laufender Dienst mit einer stehenden Verbindung.
  ///
  /// ⚠️ Er ERSETZT die Abfrage nicht. Der ursprüngliche Einwand bleibt
  /// richtig: ein toter Strom sieht von außen aus wie einer, über den nichts
  /// kommt. Deshalb wird weiter gefragt — nur eben im Minutentakt statt alle
  /// fünf Sekunden, und nur solange die Leitung steht. Reißt sie, fällt der
  /// Takt von allein auf schnell zurück (siehe [_faellig]).
  Future<void> _weckleitungStarten() async {
    if (_weckleitungLaeuft) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final mgnr = prefs.getString('mitgliedernummer');
      if (mgnr == null || mgnr.isEmpty) return;

      // Stumme Aufträge an die Warteschlangen. Kein Umweg über das Dashboard:
      // in diesem Isolate gibt es keins.
      NtfyService.onAnrufWake = () {
        _log.info('Weckruf: Wählauftrag', tag: 'SIG_GW');
        AnrufGatewayService.runOnce(background: true);
      };
      NtfyService.onGatewayWake = () {
        _log.info('Weckruf: SMS-Warteschlange', tag: 'SIG_GW');
        TerminSmsGatewayService.runOnce(background: true);
      };

      // nurMaschine: der Dienst soll wecken, nicht melden. Die Oberfläche hängt
      // am selben Thema, und was beide anzeigen, sieht der Nutzer doppelt.
      NtfyService().start(mgnr, jwtToken: ApiService().token, nurMaschine: true);
      _weckleitungLaeuft = true;
    } catch (e) {
      // Kein Grund aufzugeben: ohne Weckruf bleibt die Abfrage im schnellen
      // Takt, also genau das Verhalten von vorher.
      debugPrint('[SIG_GW] Weckleitung nicht gestartet: $e');
    }
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
      // Anrufe ZUERST. Ein Wählauftrag gilt zwei Minuten, und am anderen Ende
      // sitzt jemand, der gerade geklickt hat — die SMS-Warteschlange hat
      // dagegen einen ganzen Tag Vorlauf. Liefe sie zuerst, könnten ihre
      // Netzwege den Anruf um Sekunden verzögern, in denen niemand weiß,
      // warum das Telefon schweigt.
      //
      // Steht die Weckleitung, kommt der Auftrag von selbst herein und diese
      // Abfrage ist nur noch die Kontrolle, ob der Strom überhaupt trägt.
      var anruf = const AnrufGatewayLauf();
      if (_faellig(timestamp, _letzteAnrufPruefung, Duration.zero, _langsam)) {
        _letzteAnrufPruefung = timestamp;
        anruf = await AnrufGatewayService.runOnce(background: true);
        if (anruf.didSomething) {
          _melden('Gateway aktiv', 'Zuletzt ${_uhrzeit(timestamp)}: $anruf');
        }
      }

      // Nur fragen, wenn dieses Gerät überhaupt SMS-Gateway ist. Sonst
      // antwortet runOnce mit „Gerät ist nicht als SMS-Gateway eingerichtet",
      // das läuft in _scheitern, und ein reines Anruf-Gerät stünde dauerhaft
      // auf „SMS-Gateway gestört — TAN geht nicht raus". Eine Störmeldung für
      // eine Aufgabe, die dieses Gerät gar nicht hat, macht jede echte
      // Störmeldung wertlos.
      if (!await TerminSmsGatewayService.isEnabled()) {
        _fehlerInFolge = 0;
        _letzterGrund = '';
        _seit = null;
        if (!anruf.didSomething) {
          _melden('Anruf-Gateway aktiv', 'Bereit — zuletzt geprüft ${_uhrzeit(timestamp)}');
        }
        return;
      }

      // Die SMS-Warteschlangen höchstens im eigenen Takt abfragen, auch wenn
      // der Dienst wegen der Fernwahl viermal so schnell schlägt. Ein Durchlauf
      // kostet FÜNF Anfragen (Termine, Signatur-TAN, Medikamente, Wetter,
      // chat/sms_outbox) — der Unterschied zwischen 5 und 20 Sekunden sind
      // 2.700 Funkweckrufe am Tag, für eine Erinnerung mit einem Tag Vorlauf.
      if (!_faellig(timestamp, _letzteSmsPruefung,
          SignaturGatewayService.smsTakt, _langsam)) {
        return;
      }
      _letzteSmsPruefung = timestamp;

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
      _melden(
        'SMS-Gateway aktiv',
        lauf.didSomething
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
    // Die Weckleitung mitnehmen. Ohne das bliebe eine stehende Verbindung samt
    // Wiederverbindungs-Timer in einem Isolate zurück, dessen Dienst es nicht
    // mehr gibt — sie würde niemanden mehr wecken und trotzdem weiter Strom
    // und Funk kosten.
    if (_weckleitungLaeuft) {
      NtfyService().stop();
      NtfyService.onAnrufWake = null;
      NtfyService.onGatewayWake = null;
      _weckleitungLaeuft = false;
    }
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
