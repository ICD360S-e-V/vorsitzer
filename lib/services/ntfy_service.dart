import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'logger_service.dart';
import 'http_client_factory.dart';

/// Service for receiving push notifications via ntfy (self-hosted).
/// Connects to the ntfy server using HTTP streaming (NDJSON).
/// Topic pattern: vorsitzer_{mitgliedernummer}
/// Auth: fetches ntfy token from server (never hardcoded).
class NtfyService {
  static final NtfyService _instance = NtfyService._internal();
  factory NtfyService() => _instance;
  NtfyService._internal();

  static const String _ntfyUrl = 'https://icd360sev.icd360s.de/ntfy';
  static const String _tokenUrl = 'https://icd360sev.icd360s.de/api/auth/ntfy_token.php';
  static const String _topicPrefix = 'vorsitzer_';
  static const Duration _baseReconnectDelay = Duration(seconds: 5);
  static const Duration _maxReconnectDelay = Duration(minutes: 5);

  final _log = LoggerService();

  /// Wird bei einem stillen Gateway-Auftrag gerufen. Als Callback statt als
  /// direkter Aufruf, damit dieser Dienst nichts vom SMS-Gateway wissen muss.
  static void Function()? onGatewayWake;

  /// Dasselbe für einen Wählauftrag der Fernwahl.
  ///
  /// Eigener Rückruf statt eines geteilten: ein Wählauftrag gilt zwei Minuten
  /// und soll sofort laufen, eine SMS hat einen Tag Vorlauf. Über einen
  /// gemeinsamen Weckruf liefen beide Warteschlangen bei jedem Anlass, und das
  /// sind fünf Anfragen für einen Anruf.
  static void Function()? onAnrufWake;

  /// Steht die Leitung gerade?
  ///
  /// Das ist der Schalter, an dem die Abfragetakte hängen: solange der Strom
  /// hängt, darf langsam gefragt werden, weil ein Auftrag von selbst
  /// hereinkommt. Reißt er, muss wieder schnell gefragt werden — sonst wäre
  /// genau der Einwand berechtigt, der die Abfrage überhaupt erst begründet
  /// hat: ein toter Strom sieht von außen aus wie einer, über den nichts kommt.
  bool _verbunden = false;
  bool get istVerbunden => _verbunden;

  String? _mitgliedernummer;
  String? _jwtToken;
  String? _ntfyToken;
  http.Client? _client;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;

  /// Wacht darüber, dass überhaupt noch etwas hereinkommt.
  Timer? _stillstandsWache;

  /// Nach dieser Stille gilt der Strom als tot.
  ///
  /// ⚠️ WARUM ES DIESE WACHE BRAUCHT — und warum ihr Fehlen lange unsichtbar war:
  /// Läuft die NAT-Zuordnung des Mobilfunkbetreibers ab, ist die Verbindung
  /// tot, OHNE dass irgendetwas davon erfährt. Es kommt kein FIN, kein RST,
  /// kein Fehler — der Strom wird einfach still. `onDone` feuert nicht,
  /// `onError` feuert nicht, und [_verbunden] blieb deshalb bis in alle
  /// Ewigkeit auf `true`. Die App hielt sich für erreichbar, während sie es
  /// nicht mehr war, und niemand hätte es gemerkt.
  ///
  /// Das Erkennungsmerkmal lag die ganze Zeit da: ntfy schickt alle
  /// **45 Sekunden** ein `keepalive`-Ereignis über denselben Strom
  /// (`keepalive-interval`, Vorgabe des Servers, bei uns nicht überschrieben).
  /// [_handleLine] hat es bisher als „kein message-Ereignis" weggeworfen.
  /// Bleibt es aus, ist die Leitung tot — eine andere Erklärung gibt es nicht.
  ///
  /// ⚠️ 150 Sekunden = gut drei ausgefallene Lebenszeichen. Kürzer hiesse: ein
  /// verzögertes Paket beendet eine gesunde Verbindung. Wer am Server
  /// `keepalive-interval` ändert, ändert diesen Wert mit — es ist die einzige
  /// Stelle, an der die beiden zusammenhängen, und ein Fehler meldet sich
  /// nicht, er sieht nur aus wie „ntfy ist wieder mal instabil".
  ///
  /// ⚠️ Die Wache ist selbst ein Zeitgeber im Benutzerraum: schläft der
  /// Prozessor, läuft sie nicht. Das ist hier richtig so — solange niemand
  /// wach ist, tut auch der tote Strom niemandem weh. Beim nächsten Aufwachen
  /// schlägt sie an und der Zustand wird korrigiert.
  static const _stillstandsfrist = Duration(seconds: 150);
  bool _running = false;
  int _reconnectAttempts = 0;

  /// Zeigt dieser Strom nur Maschinen-Aufträge aus oder auch Meldungen?
  ///
  /// ⚠️ Seit der Wachdienst einen eigenen Strom hält, hängen ZWEI Abonnenten
  /// am selben Thema: die Oberfläche und der Dienst, jeder in seinem Isolate.
  /// ntfy stellt jede Nachricht beiden zu — also erschien seit dem 10.08. jede
  /// Chatmeldung doppelt auf dem Bildschirm. Im Protokoll steht derselbe
  /// Wortlaut zur selben Sekunde mehrfach.
  ///
  /// Der Dienst braucht den Strom nur für die stummen Marken `sms_gateway` und
  /// `anruf_gateway`. Alles, was ein Mensch lesen soll, bleibt Sache der
  /// Oberfläche — sie ist der einzige Abonnent, der auch weiß, ob der Nutzer
  /// gerade hinschaut.
  bool _nurMaschine = false;

  /// Wie oft dieser Strom eine Meldung auf den Bildschirm gebracht hat.
  ///
  /// Klein genug, um im Betrieb nicht zu stören, und der einzige Weg, die
  /// Doppelmeldung festzuhalten, ohne einen Plattformkanal nachzubauen: der
  /// Zähler eines Maschinen-Stroms muss null bleiben.
  int angezeigteMeldungen = 0;

  /// Start listening for ntfy notifications.
  /// [mitgliedernummer] - e.g. "V12345" (will be lowercased)
  /// [jwtToken] - JWT token for fetching ntfy auth token from server
  /// [nurMaschine] - nur stumme Marken abarbeiten, keine Meldungen anzeigen
  void start(String mitgliedernummer, {String? jwtToken, bool nurMaschine = false}) {
    if (_running && _mitgliedernummer == mitgliedernummer.toLowerCase()) return;
    stop();
    _mitgliedernummer = mitgliedernummer.toLowerCase();
    _jwtToken = jwtToken;
    _nurMaschine = nurMaschine;
    _running = true;
    _reconnectAttempts = 0;
    _log.info('ntfy: Starting for $_mitgliedernummer', tag: 'NTFY');
    _fetchTokenAndConnect();
  }

  /// Update JWT token (e.g. after token refresh)
  void updateJwtToken(String jwtToken) {
    _jwtToken = jwtToken;
  }

  /// Stop listening.
  void stop() {
    _running = false;
    _verbunden = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stillstandsWache?.cancel();
    _stillstandsWache = null;
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
    if (_mitgliedernummer != null) {
      _log.info('ntfy: Stopped', tag: 'NTFY');
    }
    _mitgliedernummer = null;
    _ntfyToken = null;
  }

  Future<void> _fetchTokenAndConnect() async {
    if (!_running) return;

    if (_ntfyToken == null && _jwtToken == null) {
      // Dashboard can start us before ApiService has settled its tokens, and
      // a cleared session leaves us with nothing to authenticate with. Either
      // way, silently doing nothing is what hid this failure for months.
      _log.warning('ntfy: No JWT yet — requesting one', tag: 'NTFY');
      await ApiService().ensureFreshToken();
      if (_jwtToken == null) {
        _scheduleReconnect();
        return;
      }
    }

    // Fetch ntfy token from server
    if (_ntfyToken == null && _jwtToken != null) {
      try {
        final tokenClient = IOClient(HttpClientFactory.createPinnedHttpClient());
        final response = await tokenClient.get(
          Uri.parse(_tokenUrl),
          headers: {
            'Authorization': 'Bearer $_jwtToken',
            'User-Agent': 'ICD360S-Vorsitzer/1.0',
          },
        ).timeout(const Duration(seconds: 15));
        tokenClient.close();

        if (response.statusCode == 200) {
          try {
            // ⚠️ `antwort`, nicht `body`: das ist die Antwort des Servers auf die
            // Token-Anfrage, NICHT der Text einer Benachrichtigung. Unter demselben
            // Namen war beim Aufräumen der Protokolle nicht zu unterscheiden,
            // welches der beiden hier steht.
            final antwort = jsonDecode(response.body);
            if (antwort['success'] == true && antwort['ntfy_token'] != null) {
              _ntfyToken = antwort['ntfy_token'] as String;
              _log.info('ntfy: Token fetched', tag: 'NTFY');
            } else {
              _log.error('ntfy: Token fetch failed: ${antwort['message'] ?? 'unknown'}', tag: 'NTFY');
              _scheduleReconnect();
              return;
            }
          } on FormatException {
            _log.error('ntfy: Invalid token response', tag: 'NTFY');
            _scheduleReconnect();
            return;
          }
        } else {
          _log.error('ntfy: Token fetch HTTP ${response.statusCode}', tag: 'NTFY');
          if (response.statusCode == 401 || response.statusCode == 403) {
            // A refused JWT never heals by being sent again. Ask ApiService for
            // a live one — it pushes the result back here via updateJwtToken().
            await ApiService().ensureFreshToken();
          }
          _scheduleReconnect();
          return;
        }
      } catch (e) {
        _log.error('ntfy: Token fetch error: $e', tag: 'NTFY');
        _scheduleReconnect();
        return;
      }
    }

    _connect();
  }

  void _connect() async {
    if (!_running || _mitgliedernummer == null) return;

    final topic = '$_topicPrefix$_mitgliedernummer';
    final url = '$_ntfyUrl/$topic/json';

    _log.info('ntfy: Connecting to $topic', tag: 'NTFY');

    try {
      _client?.close();
      _client = IOClient(HttpClientFactory.createPinnedHttpClient());

      final request = http.Request('GET', Uri.parse(url));
      request.headers['Accept'] = 'application/x-ndjson';
      if (_ntfyToken != null) {
        request.headers['Authorization'] = 'Bearer $_ntfyToken';
      }

      final response = await _client!.send(request).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 401 || response.statusCode == 403) {
        _log.error('ntfy: Auth failed (${response.statusCode}), refetching token', tag: 'NTFY');
        _ntfyToken = null;
        _scheduleReconnect();
        return;
      }

      if (response.statusCode != 200) {
        _log.error('ntfy: HTTP ${response.statusCode}', tag: 'NTFY');
        _scheduleReconnect();
        return;
      }

      _log.info('ntfy: Connected to $topic', tag: 'NTFY');
      _reconnectAttempts = 0;
      _verbunden = true;

      _subscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        _handleLine,
        onError: (error) {
          _log.error('ntfy: Stream error: $error', tag: 'NTFY');
          _scheduleReconnect();
        },
        onDone: () {
          _log.info('ntfy: Stream closed', tag: 'NTFY');
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (e) {
      _log.error('ntfy: Connection failed: $e', tag: 'NTFY');
      _scheduleReconnect();
    }
  }

  /// Nur für Tests offen: sonst bräuchte der Nachweis der Doppelmeldung einen
  /// echten ntfy-Strom samt Plattformkanal.
  @visibleForTesting
  void handleLineFuerTest(String line) => _handleLine(line);

  void _handleLine(String line) {
    // ⚠️ VOR jedem Aussteigen. Auch ein `keepalive` und auch eine leere Zeile
    // sind ein Lebenszeichen — sie sind sogar das einzige, das in ruhigen
    // Stunden je ankommt. Stünde das Zurücksetzen weiter unten, hinter dem
    // Filter auf `message`, würde die Wache in genau den Stunden zuschlagen,
    // in denen alles in Ordnung ist.
    _wacheStellen();

    if (line.trim().isEmpty) return;

    try {
      final data = jsonDecode(line);
      if (data is! Map<String, dynamic>) return;

      // Skip non-message events (keepalive, open, etc.)
      final event = data['event'] as String? ?? '';
      if (event != 'message') return;

      // Maschinen-Auftrag statt Nachricht an den Menschen: das Gateway soll
      // die SMS-Warteschlange sofort leeren. Ohne diesen Zweig bekäme der
      // Vorstand bei jeder von Hand ausgelösten SMS eine sinnlose
      // "SMS-Auftrag"-Benachrichtigung auf den Bildschirm.
      final tags = (data['tags'] as List?)?.map((t) => '$t').toList() ?? const [];
      if (tags.contains('sms_gateway')) {
        onGatewayWake?.call();
        return;
      }
      // Wählauftrag der Fernwahl. Ebenfalls stumm: am Telefon soll das Gerät
      // wählen, nicht eine Benachrichtigung aufpoppen, die jemand wegwischt.
      if (tags.contains('anruf_gateway')) {
        onAnrufWake?.call();
        return;
      }

      // Ab hier geht es an einen Menschen — und dafür ist nur die Oberfläche
      // zuständig. Der Dienst hört still mit, sonst stünde jede Meldung
      // zweimal auf dem Bildschirm. Auch das Protokollieren gehört hierher:
      // sonst tauchte derselbe Wortlaut weiter doppelt in der Übertragung auf
      // und täuschte einen Fehler vor, den es nicht mehr gibt.
      if (_nurMaschine) return;

      final title = data['title'] as String? ?? 'ICD360S e.V';
      final body = data['message'] as String? ?? '';

      // 🔴 HIER STAND `'ntfy: Notification: $title - $body'` — ALSO DER VOLLE
      // WORTLAUT JEDER CHAT-NACHRICHT SAMT NAMEN DES ABSENDERS.
      //
      // `LoggerService` lädt die Protokollzeilen zum Server hoch, und dort
      // lagen sie unter `logs/vorsitzer/*.json`. Gemessen am 30.08.2026:
      // 10.824 solcher Zeilen, 566 MB, vom 22.07. bis dahin — darunter
      // Gesundheitsangaben von Mitgliedern. Und dieser Pfad war über HTTPS
      // OHNE ANMELDUNG abrufbar: ein einzelner GET lieferte 8,2 MB.
      // (Die nginx-Sperre aus dem Juli griff nach ENDUNG — `.log`, `.sql`,
      // `.bak` —, die Dateien heissen aber `.json`.)
      //
      // ⚠️ Protokolliert wird ab jetzt NUR, DASS etwas kam, und wie lang es
      // war. Kein Wortlaut, kein Name, kein Betreff. Für die Frage, die dieses
      // Protokoll beantworten soll — „kam die Benachrichtigung an?" — reicht
      // das vollständig; für alles andere ist es das falsche Werkzeug.
      _log.info(
        'ntfy: Benachrichtigung erhalten '
        '(Titel ${title.length} Z., Text ${body.length} Z.)',
        tag: 'NTFY',
      );

      // 🔴 CHAT-NACHRICHT: hier kam bis zum 01.09.2026 der NAME des Mitglieds
      // und der WORTLAUT der Nachricht auf den Bildschirm — unverändert so,
      // wie der Server sie geschickt hat. Nachgesehen in
      // `api/helpers/NtfyVorsitzerService.php`:
      //
      //     notifyNewMessage($nummer, $senderName, $preview)
      //       -> Titel: "Neue Nachricht von {$senderName}"
      //       -> Text:  $preview
      //
      // Eine Benachrichtigung liegt auf dem SPERRBILDSCHIRM. Bei einem
      // Behindertenverein ist der Wortlaut einer Mitgliedsnachricht
      // regelmässig eine Gesundheitsangabe, und der Name daneben macht sie
      // zuordenbar — für jeden, der neben dem Tablet steht.
      //
      // ⚠️ Erkannt wird die Chat-Nachricht an der Marke `speech_balloon`, und
      // die ist dafür belastbar: sie wird serverseitig AUSSCHLIESSLICH von
      // `notifyNewMessage` gesetzt, in allen drei Diensten (Mitglieder,
      // Schatzmeister, Vorsitzer) und nirgendwo sonst — nachgezählt am
      // 01.09.2026, drei Fundstellen, alle in dieser einen Methode.
      //
      // ⚠️ Alle anderen Meldungen bleiben unangetastet: Fax, Login-Anfragen,
      // Wächter-Alarme. Die tragen keine Mitgliedsdaten, und sie generisch zu
      // machen würde sie wertlos machen.
      //
      // ⚠️ Die eigentliche Reparatur gehört auf den SERVER — was nicht
      // gesendet wird, kann auch nicht angezeigt werden, und sie würde
      // zugleich für die Mitglieder- und die Schatzmeister-App gelten, ohne
      // dass dort jemand eine neue Fassung installieren muss. Bis dahin ist
      // das hier die Sperre auf unserer Seite.
      final istChatNachricht = tags.contains('speech_balloon');

      angezeigteMeldungen++;
      NotificationService().show(
        title: istChatNachricht
            ? NotificationService.chatBenachrichtigungTitel
            : title,
        body: istChatNachricht ? '' : body,
      );
    } on FormatException {
      // Not valid JSON, ignore (could be keepalive)
    } catch (e) {
      _log.error('ntfy: Parse error: $e', tag: 'NTFY');
    }
  }

  /// Setzt die Stillstandswache neu auf.
  void _wacheStellen() {
    _stillstandsWache?.cancel();
    if (!_running) return;
    _stillstandsWache = Timer(_stillstandsfrist, () {
      _log.warning(
          'ntfy: seit ${_stillstandsfrist.inSeconds}s kein Lebenszeichen — '
          'Leitung gilt als tot, neu verbinden',
          tag: 'NTFY');
      // Nicht nur neu verbinden: _scheduleReconnect setzt zuerst
      // [_verbunden] auf false. Genau daran hängen die Abfragetakte und das
      // Wachlicht des Wachdienstes — ohne diesen Schritt bliebe beides im
      // Sparmodus, während in Wahrheit niemand mehr zuhört.
      _subscription?.cancel();
      _subscription = null;
      _scheduleReconnect();
    });
  }

  void _scheduleReconnect() {
    // Zuerst und immer: die Leitung steht nicht mehr. Auch wenn wir gleich
    // aufgeben, weil gestoppt wurde — sonst bliebe der Schalter auf „steht"
    // stehen und die Abfragetakte blieben langsam, während niemand mehr
    // zuhört. Genau der Fall, für den die Abfrage überhaupt existiert.
    _verbunden = false;
    if (!_running) return;
    _reconnectTimer?.cancel();
    // Exponential backoff, capped. Retrying every 5s against a failure that
    // cannot fix itself — a dead JWT, say — costs thousands of requests a day
    // and buries the real error under its own noise.
    final delay = _reconnectAttempts >= 6
        ? _maxReconnectDelay
        : Duration(seconds: _baseReconnectDelay.inSeconds << _reconnectAttempts);
    _reconnectAttempts++;
    _log.debug('ntfy: Reconnect in ${delay.inSeconds}s', tag: 'NTFY');
    _reconnectTimer = Timer(delay, _fetchTokenAndConnect);
  }
}
