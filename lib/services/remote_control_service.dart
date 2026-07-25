import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'api_service.dart';
import 'chat_service.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Lifecycle of a Fernwartung session on the CONTROLLER (Vorsitzer) side.
enum RemoteControlState { idle, calling, connected, ended }

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
  RemoteControlState _state = RemoteControlState.idle;
  RemoteControlEnd _lastEnd = RemoteControlEnd.none;

  Stream<RemoteControlState> get stateStream => _stateController.stream;
  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;
  RemoteControlState get state => _state;
  RemoteControlEnd get lastEnd => _lastEnd;
  MediaStream? get remoteStream => _remoteStream;
  bool get canSendInput => _inputChannel != null && _inputOpen;

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
        controlAllowed: true,
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
        await _flushQueuedIce();
        // Audit: the member answered → consented and the session is live.
        if (_controllerMnr != null && _sessionId != null) {
          ApiService().remoteSession(
            mitgliedernummer: _controllerMnr!, action: 'active', sessionId: _sessionId);
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

  Future<void> _flushQueuedIce() async {
    for (final c in _queuedIce) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
    _queuedIce.clear();
  }

  void _cleanup() {
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
    if (!_remoteStreamController.isClosed) _remoteStreamController.add(null);
    _remoteDescriptionSet = false;
    _queuedIce.clear();
    _conversationId = null;
    _sessionId = null;
    _controllerMnr = null;
  }
}
