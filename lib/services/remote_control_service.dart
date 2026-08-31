import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'api_service.dart';
import 'chat_service.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Lifecycle of a Fernwartung session on the CONTROLLER (Vorsitzer) side.
/// ⚠️ `antwort` liegt zwischen `calling` und `connected`, weil genau dieser
/// Schritt bisher unsichtbar war: der Bildschirm sagte bis zum Verbinden
/// „Warten auf Zustimmung von …", obwohl das Mitglied laengst zugestimmt hatte
/// und seinen Bildschirm teilte. Blieb ICE haengen, zeigte der Vorsitz auf den
/// falschen Schritt und wartete auf etwas, das schon passiert war.
enum RemoteControlState { idle, calling, antwort, connected, ended }

/// Why a session ended / failed, so the UI can explain it.
enum RemoteControlEnd { declined, memberStopped, disconnected, error, timeout, none }

/// RemoteControlService — the Vorsitzer side of Fernwartung (RustDesk-style
/// remote support). Separate from voice calls and from the RDP/Guacamole office
/// remote desktop.
///
/// WebRTC roles: this side is the OFFERER. It creates the offer, an "input"
/// RTCDataChannel (controller → member), and a recvonly video transceiver to
/// receive the member's screen. The member answers with its screen track.
/// Input events are serialized to JSON and pushed over the data channel; the
/// member denormalizes and injects them natively.
class RemoteControlService {
  static final RemoteControlService _instance = RemoteControlService._internal();
  factory RemoteControlService() => _instance;
  RemoteControlService._internal();

  final ChatService _chat = ChatService();

  RTCPeerConnection? _pc;
  RTCDataChannel? _inputChannel;
  bool _inputOpen = false;
  MediaStream? _remoteStream;
  MediaStream? _mikroStream;

  int? _conversationId;
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _queuedIce = [];

  // Audit trail (remote_sessions) — best-effort, never blocks signaling.
  int? _sessionId;
  String? _controllerMnr;

  // Gives up if the member never answers (no consent) within the window.
  Timer? _answerTimeout;

  StreamSubscription<RemoteAnswerEvent>? _answerSub;
  StreamSubscription<RemoteRejectedEvent>? _rejectSub;
  StreamSubscription<RemoteEndedEvent>? _endedSub;
  StreamSubscription<RemoteIceEvent>? _iceSub;

  final _stateController = StreamController<RemoteControlState>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _zielSteuerbarController = StreamController<bool>.broadcast();
  RemoteControlState _state = RemoteControlState.idle;
  RemoteControlEnd _lastEnd = RemoteControlEnd.none;

  Stream<RemoteControlState> get stateStream => _stateController.stream;
  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;

  /// Feuert, sobald das Mitglied gemeldet hat, ob gesteuert werden kann.
  Stream<bool> get zielSteuerbarStream => _zielSteuerbarController.stream;

  /// Was wirklich am Bild ankommt. Ohne diese Zahlen ist „schwarz" nicht von
  /// „nichts empfangen" und nicht von „empfangen, aber nicht dekodiert" zu
  /// unterscheiden — drei völlig verschiedene Ursachen, die alle gleich
  /// aussehen.
  Stream<BildBefund> get bildBefundStream => _bildController.stream;
  final _bildController = StreamController<BildBefund>.broadcast();
  Timer? _bildUhr;
  BildBefund? _letzterBefund;
  DateTime? _letzteMessung;
  BildBefund? get letzterBefund => _letzterBefund;
  RemoteControlState get state => _state;
  RemoteControlEnd get lastEnd => _lastEnd;
  MediaStream? get remoteStream => _remoteStream;
  bool get canSendInput => _inputChannel != null && _inputOpen;

  /// Plattform des Mitglieds, sobald es geantwortet hat (`android`, `windows`,
  /// `linux`, `macos`, `ios`) — vorher null.
  String? get zielPlattform => _zielPlattform;

  /// Kann auf dem Gerät des Mitglieds gesteuert werden?
  ///
  /// ⚠️ Das weiß nur das Mitglied, und es sagt es erst mit der Antwort. Bis
  /// dahin false — lieber „Ansicht" anzeigen und sich korrigieren, als
  /// Steuerung zu versprechen und Klicks ins Leere gehen zu lassen.
  bool get zielSteuerbar => _zielSteuerbar;

  /// Meldet das Mitglied, dass es seinen Kopierschutz (FLAG_SECURE) abschalten
  /// konnte? Bei false ist das Bild schwarz, und zwar auf der Gegenseite —
  /// nicht unterwegs. Ältere Mitglieds-Apps schicken das Feld nicht; dann wird
  /// nichts behauptet und der Wert bleibt true.
  bool get zielBildFrei => _zielBildFrei;
  bool _zielBildFrei = true;

  String? _zielPlattform;
  bool _zielSteuerbar = false;

  void _setState(RemoteControlState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  // ─── TURN (own coturn only; GDPR: no third-party STUN) ──────────────────────
  static Map<String, dynamic>? _cachedIceServers;
  static DateTime? _cacheExpiry;

  static Future<Map<String, dynamic>> _getIceServers() async {
    if (_cachedIceServers != null && _cacheExpiry != null && DateTime.now().isBefore(_cacheExpiry!)) {
      return _cachedIceServers!;
    }
    const empty = {'iceServers': <Map<String, dynamic>>[]};
    try {
      final creds = await ApiService().getTurnCredentials();
      if (creds == null) return empty;
      final uris = (creds['uris'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
      final username = creds['username']?.toString();
      final password = creds['password']?.toString();
      if (uris.isEmpty || username == null || password == null) return empty;
      final stun = uris.where((u) => u.startsWith('stun:')).toList();
      final turn = uris.where((u) => u.startsWith('turn:') || u.startsWith('turns:')).toList();
      final servers = <Map<String, dynamic>>[
        if (stun.isNotEmpty) {'urls': stun},
        if (turn.isNotEmpty) {'urls': turn, 'username': username, 'credential': password},
      ];
      if (servers.isEmpty) return empty;
      _cachedIceServers = {'iceServers': servers};
      final ttl = (creds['ttl'] as num?)?.toInt() ?? 86400;
      _cacheExpiry = DateTime.now().add(Duration(seconds: ttl > 60 ? (ttl * 9 ~/ 10) : ttl));
      return _cachedIceServers!;
    } catch (e) {
      debugPrint('[RemoteControl] TURN fetch error: $e');
      return empty;
    }
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Begin a session against [targetUserId] over [conversationId]. Returns false
  /// if setup failed (e.g. TURN unavailable). On success the UI should show the
  /// remote screen; [remoteStreamStream] fires when the member's screen arrives.
  Future<bool> start({
    required int conversationId,
    required String targetUserId,
    required String controllerMitgliedernummer,
    String? controllerName,
  }) async {
    if (_state != RemoteControlState.idle) return false;
    _conversationId = conversationId;
    _controllerMnr = controllerMitgliedernummer;
    _lastEnd = RemoteControlEnd.none;
    _setState(RemoteControlState.calling);
    try {
      // Ensure we are in the conversation room so remote_answer/ice/end reach us.
      _chat.joinConversation(conversationId);
      await _createPeerConnection();

      // Input flows controller → member over a reliable, ordered data channel.
      _inputChannel = await _pc!.createDataChannel('input', RTCDataChannelInit()..ordered = true);
      _inputChannel!.onDataChannelState = (s) {
        _inputOpen = s == RTCDataChannelState.RTCDataChannelOpen;
        _log.info('RemoteControl: input channel state $s', tag: 'REMOTE');
      };

      // We only RECEIVE the member's screen.
      await _pc!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      // Sprechen waehrend der Sitzung — in BEIDE Richtungen.
      //
      // ⚠️ Das eigene Mikrofon muss VOR createOffer angelegt sein, sonst steht
      // kein Ton im Angebot und es waere eine Neuverhandlung noetig. Wird es
      // abgelehnt, laeuft die Sitzung ohne Ton weiter; dafuer ist der
      // Chatstreifen da.
      _mikroStream = await _mikrofonHolen();
      if (_mikroStream != null) {
        for (final track in _mikroStream!.getTracks()) {
          await _pc!.addTrack(track, _mikroStream!);
        }
        _tonwegSetzen();
      } else {
        // Ohne eigenes Mikrofon trotzdem ZUHOEREN koennen: sonst gaebe es gar
        // keine Tonspur und das Mitglied redete ins Leere.
        await _pc!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      }

      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      _chat.sendRemoteOffer(
        conversationId,
        targetUserId,
        offer.sdp ?? '',
        offer.type ?? 'offer',
        controllerName: controllerName,
      );

      _subscribe();

      // Give up if the member never answers (no consent) within 60s, so the
      // Vorsitzer doesn't sit on "waiting for consent" forever.
      _answerTimeout = Timer(const Duration(seconds: 60), () {
        if (_state == RemoteControlState.calling) {
          end(notifyPeer: true, reason: RemoteControlEnd.timeout);
        }
      });

      // Audit (fire-and-forget): open a 'requested' row and remember its id.
      ApiService().remoteSession(
        mitgliedernummer: controllerMitgliedernummer,
        action: 'start',
        targetMitgliedernummer: targetUserId,
        conversationId: conversationId,
        // Beim Start ist noch nichts bekannt: die Anfrage ist raus, das
        // Mitglied hat weder zugestimmt noch geantwortet. Der Wert wird beim
        // 'active'-Schritt nachgetragen, wenn er belegt ist.
        controlAllowed: false,
      ).then((r) {
        final id = r?['session_id'];
        if (id is int) {
          _sessionId = id;
        } else if (id != null) {
          _sessionId = int.tryParse(id.toString());
        }
      });

      _log.info('RemoteControl: offer sent to $targetUserId (conv $conversationId)', tag: 'REMOTE');
      return true;
    } catch (e) {
      _log.error('RemoteControl: start failed: $e', tag: 'REMOTE');
      _lastEnd = RemoteControlEnd.error;
      end(notifyPeer: false);
      return false;
    }
  }

  /// End the session (Vorsitzer pressed "Beenden"). [notifyPeer] sends remote_end.
  void end({bool notifyPeer = true, RemoteControlEnd reason = RemoteControlEnd.none}) {
    if (_state == RemoteControlState.idle) return;
    if (reason != RemoteControlEnd.none) _lastEnd = reason;
    if (notifyPeer && _conversationId != null) {
      _chat.sendRemoteEnd(_conversationId!);
    }
    _log.info('RemoteControl: ending session (${_lastEnd.name})', tag: 'REMOTE');
    _auditEnd(); // before cleanup — needs _controllerMnr + _sessionId
    _cleanup();
    // Resting state is idle; the UI reads [lastEnd] to explain why it ended.
    _setState(RemoteControlState.idle);
  }

  void _auditEnd() {
    final mnr = _controllerMnr;
    final id = _sessionId;
    if (mnr == null || id == null) return;
    final api = ApiService();
    if (_lastEnd == RemoteControlEnd.declined) {
      api.remoteSession(mitgliedernummer: mnr, action: 'declined', sessionId: id);
    } else {
      String reason;
      switch (_lastEnd) {
        case RemoteControlEnd.memberStopped:
          reason = 'member_stop';
          break;
        case RemoteControlEnd.disconnected:
          reason = 'disconnect';
          break;
        case RemoteControlEnd.error:
          reason = 'error';
          break;
        default:
          reason = 'controller_end';
      }
      api.remoteSession(mitgliedernummer: mnr, action: 'end', sessionId: id, reason: reason);
    }
  }

  /// Mikrofon des Vorsitzes. Null heisst „stumm zuhoeren", nicht „Fehler".
  Future<MediaStream?> _mikrofonHolen() async {
    try {
      // ⚠️ Kein permission_handler: `getUserMedia` mit Ton fragt RECORD_AUDIO
      // auf Android SELBST ab (GetUserMediaImpl.requestPermissions), und diese
      // Anwendung hat das Paket gar nicht. Lehnt der Mensch ab, wirft der
      // Aufruf und wir landen im catch — die Sitzung laeuft ohne Ton weiter.
      return await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
    } catch (e) {
      _log.warning('RemoteControl: kein Mikrofon ($e) — Sitzung ohne Ton', tag: 'REMOTE');
      return null;
    }
  }

  /// Ton auf eine angeschlossene Kopfhörergarnitur legen, sonst Lautsprecher.
  ///
  /// ⚠️ `setSpeakerphoneOn(true)` ERZWINGT den Lautsprecher und geht an einer
  /// verbundenen Bluetooth-Garnitur vorbei — derselbe Fehler, den
  /// `voice_call_service._applyAudioRoute` schon einmal hatte. Auf dem
  /// Schreibtisch ist es ein Nichtstun; dort entscheidet das Betriebssystem.
  ///
  /// ⚠️ Nach `getUserMedia`, sonst steht der AudioManager noch nicht auf
  /// MODE_IN_COMMUNICATION und die Umleitung verpufft.
  void _tonwegSetzen() {
    try {
      if (Platform.isAndroid) {
        Helper.setSpeakerphoneOnButPreferBluetooth();
      } else if (Platform.isIOS) {
        Helper.setSpeakerphoneOn(true);
      }
      _log.info('RemoteControl: Tonweg gesetzt (Kopfhörer bevorzugt)', tag: 'REMOTE');
    } catch (e) {
      _log.warning('RemoteControl: Tonweg nicht setzbar: $e', tag: 'REMOTE');
    }
  }

  /// Eigenes Mikrofon stummschalten, ohne die Sitzung zu beenden.
  void mikrofonStumm(bool stumm) {
    for (final t in _mikroStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !stumm;
    }
  }

  /// Hat der Vorsitz ein eigenes Mikrofon in der Sitzung?
  bool get hatMikrofon => _mikroStream != null;

  // ─── Input senders (normalized 0..1 coords; member denormalizes) ────────────

  void _sendInput(Map<String, dynamic> event) {
    final ch = _inputChannel;
    if (ch == null || !_inputOpen) return;
    ch.send(RTCDataChannelMessage(jsonEncode(event)));
  }

  void sendMouseMove(double nx, double ny) => _sendInput({'t': 'm', 'x': nx, 'y': ny});
  void sendMouseButton(int button, bool down) => _sendInput({'t': 'b', 'b': button, 'down': down});
  void sendWheel(double dx, double dy) => _sendInput({'t': 'w', 'dx': dx, 'dy': dy});
  void sendKey({required int hid, String? character, required bool down}) =>
      _sendInput({'t': 'k', 'hid': hid, 'ch': character, 'down': down});

  /// Bildgüte am Gerät des Mitglieds einstellen.
  ///
  /// ⚠️ Warum das überhaupt gebraucht wird: die Verzögerung von ein bis zwei
  /// Sekunden kommt nicht von der Entfernung, sondern vom **Bufferbloat** des
  /// Mobilfunk-Uplinks. Die eigene Speedtest-Reihe des Vereins hat ihn
  /// gemessen — Latenz unter Last bis 7402 ms, in 32 % der Läufe über das
  /// Zehnfache des Ruhewerts. WebRTC dreht die Bitrate hoch, bis der Puffer des
  /// Funkmodems voll ist; ab da läuft das Bild hinterher. Die Reparatur ist,
  /// die Leitung bewusst NICHT auszureizen.
  ///
  /// Geht über den Eingabekanal, wird also sofort wirksam und braucht keine
  /// Neuverhandlung. Ältere Mitglieds-Apps übergehen den Rahmen stumm.
  void sendBildguete(String guete) => _sendInput({'t': 'q', 'g': guete});

  /// Systemtaste ohne Koordinaten: `back`, `home`, `recents`, `notifications`.
  ///
  /// Auf einem Telefon gibt es diese Ziele nicht als Fläche, die man anklicken
  /// könnte — die Gesten-Navigation hat keine Knöpfe mehr. Ohne diesen Rahmen
  /// käme der Vorsitz aus jeder App, die er öffnet, nicht wieder heraus.
  /// Ältere Mitglieds-Apps kennen `g` nicht und übergehen es stumm.
  void sendSystemAktion(String aktion) => _sendInput({'t': 'g', 'a': aktion});

  // ─── Internals ────────────────────────────────────────────────────────────

  Future<void> _createPeerConnection() async {
    final iceServers = await _getIceServers();
    if ((iceServers['iceServers'] as List).isEmpty) {
      throw StateError('TURN_UNAVAILABLE');
    }
    _pc = await createPeerConnection({
      ...iceServers,
      'sdpSemantics': 'unified-plan',
      'iceTransportPolicy': 'relay',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });

    _pc!.onIceCandidate = (c) {
      if (c.candidate != null && _conversationId != null) {
        _chat.sendRemoteIce(_conversationId!, c.candidate!, c.sdpMid ?? '', c.sdpMLineIndex ?? 0);
      }
    };

    _pc!.onTrack = (event) {
      // 🔴 NUR die Videospur zählt für die Anzeige.
      //
      // Seit die Sitzung auch Ton überträgt, feuert `onTrack` ZWEIMAL, und das
      // Mikrofon des Mitglieds kommt in einem EIGENEN Stream (es wird drüben
      // mit `addTrack(track, _mikroStream)` angehängt, nicht am Bildschirm).
      // Wer hier blind `streams[0]` nimmt, überschreibt den Bildschirm mit der
      // Tonspur, sobald sie als zweite eintrifft — der Renderer hängt dann an
      // einem Stream OHNE Video und zeigt SCHWARZ.
      //
      // Genau das war der schwarze Bildschirm nach dem Einbau des Mikrofons:
      // im coturn-Log flossen ~180 Byte je Paket in beide Richtungen, also
      // Ton, während vom Bild praktisch nichts ankam. Eine Regression, die
      // erst durch den Ton entstanden ist — vorher gab es nur eine Spur.
      if (event.track.kind != 'video') {
        _log.info('RemoteControl: Tonspur empfangen (nicht für die Anzeige)',
            tag: 'REMOTE');
        return;
      }
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        if (!_remoteStreamController.isClosed) _remoteStreamController.add(_remoteStream);
        _log.info('RemoteControl: remote screen track received', tag: 'REMOTE');
      }
    };

    _pc!.onConnectionState = (s) {
      _log.info('RemoteControl: PC state $s', tag: 'REMOTE');
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setState(RemoteControlState.connected);
        _bildUhrStarten();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        end(notifyPeer: false, reason: RemoteControlEnd.disconnected);
      }
    };
  }

  void _subscribe() {
    _answerSub = _chat.remoteAnswerStream.listen((e) async {
      if (e.conversationId != _conversationId || _pc == null) return;
      _answerTimeout?.cancel();
      try {
        await _pc!.setRemoteDescription(RTCSessionDescription(e.sdp, e.sdpType));
        _remoteDescriptionSet = true;
        // Zustimmung ist da. Ab hier haengt es nur noch an der Verbindung.
        if (_state == RemoteControlState.calling) {
          _setState(RemoteControlState.antwort);
        }
        await _flushQueuedIce();
        // Was das Mitglied über sich meldet, gilt — wir können es nicht wissen.
        _zielPlattform = e.plattform;
        _zielSteuerbar = e.steuerung;
        _zielBildFrei = e.bildFrei;
        if (!_zielSteuerbarController.isClosed) {
          _zielSteuerbarController.add(e.steuerung);
        }
        // Audit: the member answered → consented and the session is live.
        if (_controllerMnr != null && _sessionId != null) {
          ApiService().remoteSession(
            mitgliedernummer: _controllerMnr!,
            action: 'active',
            sessionId: _sessionId,
            // ⚠️ Erst HIER ist beides bekannt. Beim Start stand fest
            // `controlAllowed: true` im Protokoll — eine Behauptung über ein
            // Gerät, das der Vorsitz noch gar nicht erreicht hatte.
            controlAllowed: e.steuerung,
            memberPlatform: e.plattform,
          );
        }
      } catch (err) {
        _log.error('RemoteControl: setRemoteDescription(answer) failed: $err', tag: 'REMOTE');
      }
    });

    _iceSub = _chat.remoteIceStream.listen((e) async {
      if (e.conversationId != _conversationId) return;
      final cand = RTCIceCandidate(e.candidate, e.sdpMid, e.sdpMLineIndex);
      if (_pc == null || !_remoteDescriptionSet) {
        _queuedIce.add(cand);
        return;
      }
      try {
        await _pc!.addCandidate(cand);
      } catch (_) {}
    });

    _rejectSub = _chat.remoteRejectedStream.listen((e) {
      if (e.conversationId != _conversationId) return;
      end(notifyPeer: false, reason: RemoteControlEnd.declined);
    });

    _endedSub = _chat.remoteEndedStream.listen((e) {
      if (e.conversationId != _conversationId) return;
      end(notifyPeer: false, reason: RemoteControlEnd.memberStopped);
    });
  }

  /// Liest alle zwei Sekunden `inbound-rtp` und meldet, was ankommt.
  ///
  /// ⚠️ `framesDecoded` ist die Zahl, an der sich alles entscheidet:
  ///   empfangen 0            → es kommt nichts an (Transport/Spur)
  ///   empfangen >0, dekodiert 0 → der Codec wird hier nicht dekodiert
  ///   dekodiert >0, trotzdem schwarz → die Bilder SIND schwarz (FLAG_SECURE
  ///                              auf der Gegenseite) oder die Anzeige malt nicht
  void _bildUhrStarten() {
    _bildUhr?.cancel();
    _letzteMessung = null;
    _bildUhr = Timer.periodic(const Duration(seconds: 2), (_) async {
      final pc = _pc;
      if (pc == null) return;
      try {
        var empfangen = 0, dekodiert = 0, bytes = 0, breite = 0, hoehe = 0;
        String? codec;
        double? rttMs;
        for (final bericht in await pc.getStats()) {
          final w = bericht.values;
          if (bericht.type == 'inbound-rtp' && w['kind'] == 'video') {
            empfangen = (w['framesReceived'] as num?)?.toInt() ?? empfangen;
            dekodiert = (w['framesDecoded'] as num?)?.toInt() ?? dekodiert;
            bytes = (w['bytesReceived'] as num?)?.toInt() ?? bytes;
            breite = (w['frameWidth'] as num?)?.toInt() ?? breite;
            hoehe = (w['frameHeight'] as num?)?.toInt() ?? hoehe;
          } else if (bericht.type == 'candidate-pair' && w['nominated'] == true) {
            final rtt = w['currentRoundTripTime'];
            if (rtt is num) rttMs = rtt.toDouble() * 1000;
          } else if (bericht.type == 'codec' && w['mimeType'] is String) {
            final m = w['mimeType'] as String;
            if (m.startsWith('video/')) codec = m.split('/').last;
          }
        }
        // Raten aus dem Zuwachs seit dem letzten Takt — nicht aus der Summe.
        // Die Summe wächst monoton und sagt nichts darüber, wie es JETZT läuft.
        //
        // ⚠️ Gemessen wird die WIRKLICH vergangene Zeit, nicht die zwei
        // Sekunden des Zeitgebers. Ein Zeitgeber feuert später, wenn die
        // Anwendung beschäftigt ist — und dann käme genau in dem Moment eine
        // zu hohe Bildrate heraus, in dem es tatsächlich ruckelt.
        final jetzt = DateTime.now();
        final vorher = _letzterBefund;
        final sek = _letzteMessung == null
            ? 0.0
            : jetzt.difference(_letzteMessung!).inMilliseconds / 1000;
        _letzteMessung = jetzt;

        var kbit = 0;
        var fps = 0.0;
        if (vorher != null && sek > 0.2) {
          if (bytes > vorher.bytes) {
            kbit = ((bytes - vorher.bytes) * 8 / 1000 / sek).round();
          }
          if (dekodiert > vorher.dekodiert) {
            fps = (dekodiert - vorher.dekodiert) / sek;
          }
        }

        final befund = BildBefund(
          empfangen: empfangen,
          dekodiert: dekodiert,
          bytes: bytes,
          breite: breite,
          hoehe: hoehe,
          codec: codec,
          kbit: kbit,
          fps: fps,
          rttMs: rttMs,
        );
        _letzterBefund = befund;
        if (!_bildController.isClosed) _bildController.add(befund);
      } catch (e) {
        _log.warning('RemoteControl: Bildbefund nicht lesbar: $e', tag: 'REMOTE');
      }
    });
  }

  Future<void> _flushQueuedIce() async {
    for (final c in _queuedIce) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
    _queuedIce.clear();
  }

  void _cleanup() {
    _bildUhr?.cancel();
    _bildUhr = null;
    _letzterBefund = null;
    _answerTimeout?.cancel();
    _answerTimeout = null;
    _answerSub?.cancel();
    _rejectSub?.cancel();
    _endedSub?.cancel();
    _iceSub?.cancel();
    _answerSub = _rejectSub = null;
    _endedSub = null;
    _iceSub = null;
    try {
      _inputChannel?.close();
    } catch (_) {}
    _inputChannel = null;
    _inputOpen = false;
    try {
      _pc?.close();
    } catch (_) {}
    _pc = null;
    _remoteStream = null;
    try {
      _mikroStream?.getTracks().forEach((t) => t.stop());
      _mikroStream?.dispose();
    } catch (_) {}
    _mikroStream = null;
    if (!_remoteStreamController.isClosed) _remoteStreamController.add(null);
    _remoteDescriptionSet = false;
    _queuedIce.clear();
    _conversationId = null;
    _sessionId = null;
    _controllerMnr = null;
    _zielPlattform = null;
    _zielSteuerbar = false;
    _zielBildFrei = true;
  }
}


/// Was tatsächlich am Bild ankommt — die Zahlen, die „schwarzer Bildschirm"
/// von „nichts empfangen" trennen.
class BildBefund {
  final int empfangen;
  final int dekodiert;
  final int bytes;
  final int breite;
  final int hoehe;
  final String? codec;

  /// Rate des LETZTEN Takts, nicht der Durchschnitt der Sitzung. Nur so sieht
  /// man, wie die Automatik drüben gerade nachregelt.
  final int kbit;

  /// Tatsächlich dargestellte Bilder je Sekunde.
  ///
  /// ⚠️ Aus `framesDecoded`, nicht aus `framesReceived`: gezählt wird, was
  /// wirklich auf dem Schirm landet. Gehen die beiden auseinander, ist nicht
  /// die Leitung das Problem, sondern die Wiedergabe hier.
  final double fps;

  /// Umlaufzeit. Steigt sie deutlich, füllt sich eine Warteschlange — genau
  /// das, worauf die Automatik auf der Gegenseite reagiert.
  final double? rttMs;

  const BildBefund({
    required this.empfangen,
    required this.dekodiert,
    required this.bytes,
    required this.breite,
    required this.hoehe,
    this.codec,
    this.kbit = 0,
    this.fps = 0,
    this.rttMs,
  });

  /// Nichts kommt an — Transport oder Spur.
  bool get stumm => empfangen == 0 && bytes == 0;

  /// Es kommt etwas an, wird aber nicht dekodiert — Codec-Problem.
  bool get nichtDekodiert => empfangen > 0 && dekodiert == 0;

  /// Kurzfassung für den Bildschirm. Bewusst mit Rohzahlen: eine Deutung ohne
  /// die Zahl daneben kann man nicht nachprüfen.
  String get kurz {
    final b = fps > 0 ? '${fps.toStringAsFixed(fps < 10 ? 1 : 0)} fps' : '– fps';
    final d = kbit > 0 ? ' · ${(kbit / 8).round()} kB/s' : '';
    final l = rttMs != null ? ' · ${rttMs!.round()} ms' : '';
    return '$b$d$l';
  }

  /// Zweite Zeile: was die Sitzung insgesamt gekostet hat, und woran man
  /// erkennt, ob das Bild überhaupt ankommt.
  ///
  /// ⚠️ Das Gesamtvolumen steht hier, weil die Gegenseite an einem Mobilfunk-
  /// vertrag hängt. Eine halbe Stunde Fernwartung bei 120 kB/s sind rund
  /// 200 MB — das gehört sichtbar gemacht, nicht dem Zufall überlassen.
  String get zweiteZeile {
    final mb = bytes / 1024 / 1024;
    final grad = (breite > 0 && hoehe > 0) ? '$breite×$hoehe · ' : '';
    final c = codec != null ? '$codec · ' : '';
    return '$grad$c$dekodiert/$empfangen Bilder · '
        '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB gesamt';
  }
}
