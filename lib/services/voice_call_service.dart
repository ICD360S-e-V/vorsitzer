import 'dart:async';
import 'dart:io';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Voice Call Service using WebRTC for real-time audio communication
class VoiceCallService {
  // WebRTC configuration - STUN + own TURN server for NAT traversal
  static const Map<String, dynamic> _iceServers = {
    'iceServers': [
      // STUN servers (for discovering public IP)
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},

      // TURN server on icd360sev.icd360s.de (for relay when peer-to-peer fails)
      {
        'urls': 'turn:icd360sev.icd360s.de:3478',
        'username': 'icd360s',
        'credential': 'REDACTED_TURN_CRED'
      },
      {
        'urls': 'turns:icd360sev.icd360s.de:5349',  // TURN over TLS
        'username': 'icd360s',
        'credential': 'REDACTED_TURN_CRED'
      },
    ]
  };

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCVideoRenderer? _remoteAudioRenderer; // Windows audio playback fix

  // Call state
  CallState _callState = CallState.idle;
  int? _currentConversationId;
  bool _isMuted = false;
  bool _isSpeakerOn = true;

  // ICE candidate queuing (fix for race condition)
  final List<Map<String, dynamic>> _pendingIceCandidates = [];

  // Stream controllers for UI updates
  final _callStateController = StreamController<CallState>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _incomingCallController = StreamController<IncomingCall>.broadcast();
  final _iceConnectionStateController = StreamController<RTCIceConnectionState?>.broadcast();

  // Public streams
  Stream<CallState> get callStateStream => _callStateController.stream;
  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;
  Stream<IncomingCall> get incomingCallStream => _incomingCallController.stream;
  Stream<RTCIceConnectionState?> get iceConnectionStateStream => _iceConnectionStateController.stream;

  // Getters
  CallState get callState => _callState;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  int? get currentConversationId => _currentConversationId;

  // Callback for sending signaling messages via WebSocket
  Function(Map<String, dynamic>)? onSignalingMessage;

  // Singleton
  static final VoiceCallService _instance = VoiceCallService._internal();
  factory VoiceCallService() => _instance;
  VoiceCallService._internal();

  /// Initialize a call (caller side)
  Future<bool> startCall(int conversationId, String targetUserId, String targetUserName) async {
    _log.info('VoiceCallService: ========================================', tag: 'CALL');
    _log.info('VoiceCallService: 📞 START CALL - conv: $conversationId, target: $targetUserName', tag: 'CALL');
    _log.info('VoiceCallService: Current state: $_callState', tag: 'CALL');

    if (_callState != CallState.idle) {
      _log.warning('VoiceCallService: ❌ startCall() aborted - already in state: $_callState', tag: 'CALL');
      return false;
    }

    try {
      _currentConversationId = conversationId;
      _setCallState(CallState.calling);
      _log.info('VoiceCallService: ✓ State changed to: calling', tag: 'CALL');

      // Get local audio stream
      _log.info('VoiceCallService: [1/5] Getting local audio stream...', tag: 'CALL');
      final streamStart = DateTime.now();
      _localStream = await _getLocalStream();
      final streamDuration = DateTime.now().difference(streamStart);

      if (_localStream == null) {
        _log.error('VoiceCallService: ❌ Failed to get local stream', tag: 'CALL');
        _setCallState(CallState.idle);
        return false;
      }
      _log.info('VoiceCallService: ✓ Local stream acquired in ${streamDuration.inMilliseconds}ms', tag: 'CALL');
      _log.info('VoiceCallService: Stream ID: ${_localStream!.id}', tag: 'CALL');

      // Create peer connection
      _log.info('VoiceCallService: [2/5] Creating peer connection...', tag: 'CALL');
      final peerStart = DateTime.now();
      await _createPeerConnection();
      final peerDuration = DateTime.now().difference(peerStart);
      _log.info('VoiceCallService: ✓ Peer connection created in ${peerDuration.inMilliseconds}ms', tag: 'CALL');

      // Add local stream tracks
      _log.info('VoiceCallService: [3/5] Adding local tracks to peer connection...', tag: 'CALL');
      final tracks = _localStream!.getTracks();
      _log.info('VoiceCallService: Number of tracks to add: ${tracks.length}', tag: 'CALL');
      for (var i = 0; i < tracks.length; i++) {
        final track = tracks[i];
        _log.info('VoiceCallService: Adding track $i: kind=${track.kind}, enabled=${track.enabled}', tag: 'CALL');
        _peerConnection!.addTrack(track, _localStream!);
      }
      _log.info('VoiceCallService: ✓ All local tracks added to peer connection', tag: 'CALL');

      // Create offer
      _log.info('VoiceCallService: [4/5] Creating SDP offer...', tag: 'CALL');
      final offerStart = DateTime.now();
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      final offerDuration = DateTime.now().difference(offerStart);
      _log.info('VoiceCallService: ✓ SDP offer created in ${offerDuration.inMilliseconds}ms', tag: 'CALL');
      _log.info('VoiceCallService: Offer SDP type: ${offer.type}', tag: 'CALL');
      _log.info('VoiceCallService: Offer SDP length: ${offer.sdp?.length ?? 0} characters', tag: 'CALL');

      await _peerConnection!.setLocalDescription(offer);
      _log.info('VoiceCallService: ✓ Local description set', tag: 'CALL');

      // Send offer via WebSocket
      _log.info('VoiceCallService: [5/5] Sending call_offer via signaling...', tag: 'CALL');
      _log.info('VoiceCallService: Signaling message: type=call_offer, conv=$conversationId, target=$targetUserId', tag: 'CALL');
      onSignalingMessage?.call({
        'type': 'call_offer',
        'conversation_id': conversationId,
        'target_user_id': targetUserId,
        'sdp': offer.sdp,
        'sdp_type': offer.type,
      });
      _log.info('VoiceCallService: ✓ Call offer sent via WebSocket', tag: 'CALL');
      _log.info('VoiceCallService: 📞 CALL INITIATED - Waiting for answer...', tag: 'CALL');

      return true;
    } catch (e, stackTrace) {
      _log.error('VoiceCallService: ❌ startCall() error: $e', tag: 'CALL');
      _log.error('VoiceCallService: Stack trace: $stackTrace', tag: 'CALL');
      await endCall();
      return false;
    }
  }

  /// Handle incoming call offer (callee side)
  Future<void> handleIncomingCall(int conversationId, String callerId, String callerName, String sdp, String sdpType) async {
    _log.info('VoiceCallService: handleIncomingCall() - from: $callerName (conv: $conversationId), current state: $_callState', tag: 'CALL');
    if (_callState != CallState.idle) {
      // Already in a call, reject
      _log.warning('VoiceCallService: Already in call ($_callState), auto-rejecting with busy', tag: 'CALL');
      onSignalingMessage?.call({
        'type': 'call_reject',
        'conversation_id': conversationId,
        'reason': 'busy',
      });
      return;
    }

    _currentConversationId = conversationId;
    _setCallState(CallState.ringing);

    // Notify UI about incoming call
    _log.info('VoiceCallService: Notifying UI about incoming call via incomingCallController', tag: 'CALL');
    _incomingCallController.add(IncomingCall(
      conversationId: conversationId,
      callerId: callerId,
      callerName: callerName,
      sdp: sdp,
      sdpType: sdpType,
    ));
  }

  /// Accept incoming call
  Future<bool> acceptCall(String sdp, String sdpType) async {
    _log.info('VoiceCallService: ========================================', tag: 'CALL');
    _log.info('VoiceCallService: 📞 ACCEPT CALL - current state: $_callState', tag: 'CALL');
    _log.info('VoiceCallService: Incoming SDP type: $sdpType, length: ${sdp.length} chars', tag: 'CALL');

    if (_callState != CallState.ringing) {
      _log.warning('VoiceCallService: ❌ acceptCall() aborted - wrong state: $_callState (expected: ringing)', tag: 'CALL');
      return false;
    }

    try {
      _setCallState(CallState.connecting);
      _log.info('VoiceCallService: ✓ State changed to: connecting', tag: 'CALL');

      // Get local audio stream
      _log.info('VoiceCallService: [1/6] Getting local audio stream...', tag: 'CALL');
      final streamStart = DateTime.now();
      _localStream = await _getLocalStream();
      final streamDuration = DateTime.now().difference(streamStart);

      if (_localStream == null) {
        _log.error('VoiceCallService: ❌ Failed to get local stream for accept', tag: 'CALL');
        await endCall();
        return false;
      }
      _log.info('VoiceCallService: ✓ Local stream acquired in ${streamDuration.inMilliseconds}ms', tag: 'CALL');
      _log.info('VoiceCallService: Stream ID: ${_localStream!.id}', tag: 'CALL');

      // Create peer connection
      _log.info('VoiceCallService: [2/6] Creating peer connection...', tag: 'CALL');
      final peerStart = DateTime.now();
      await _createPeerConnection();
      final peerDuration = DateTime.now().difference(peerStart);
      _log.info('VoiceCallService: ✓ Peer connection created in ${peerDuration.inMilliseconds}ms', tag: 'CALL');

      // Add local stream tracks
      _log.info('VoiceCallService: [3/6] Adding local tracks...', tag: 'CALL');
      final tracks = _localStream!.getTracks();
      _log.info('VoiceCallService: Number of tracks: ${tracks.length}', tag: 'CALL');
      for (var i = 0; i < tracks.length; i++) {
        final track = tracks[i];
        _log.info('VoiceCallService: Adding track $i: kind=${track.kind}, enabled=${track.enabled}', tag: 'CALL');
        _peerConnection!.addTrack(track, _localStream!);
      }
      _log.info('VoiceCallService: ✓ All tracks added', tag: 'CALL');

      // Set remote description (the offer)
      _log.info('VoiceCallService: [4/6] Setting remote description (offer from caller)...', tag: 'CALL');
      final remoteStart = DateTime.now();
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, sdpType),
      );
      final remoteDuration = DateTime.now().difference(remoteStart);
      _log.info('VoiceCallService: ✓ Remote description set in ${remoteDuration.inMilliseconds}ms', tag: 'CALL');

      // Create answer
      _log.info('VoiceCallService: [5/6] Creating SDP answer...', tag: 'CALL');
      final answerStart = DateTime.now();
      final answer = await _peerConnection!.createAnswer();
      final answerDuration = DateTime.now().difference(answerStart);
      _log.info('VoiceCallService: ✓ SDP answer created in ${answerDuration.inMilliseconds}ms', tag: 'CALL');
      _log.info('VoiceCallService: Answer SDP type: ${answer.type}', tag: 'CALL');
      _log.info('VoiceCallService: Answer SDP length: ${answer.sdp?.length ?? 0} characters', tag: 'CALL');

      await _peerConnection!.setLocalDescription(answer);
      _log.info('VoiceCallService: ✓ Local description set', tag: 'CALL');

      // Send answer via WebSocket
      _log.info('VoiceCallService: [6/6] Sending call_answer via signaling...', tag: 'CALL');
      _log.info('VoiceCallService: Conversation ID: $_currentConversationId', tag: 'CALL');
      onSignalingMessage?.call({
        'type': 'call_answer',
        'conversation_id': _currentConversationId,
        'sdp': answer.sdp,
        'sdp_type': answer.type,
      });
      _log.info('VoiceCallService: ✓ Call answer sent via WebSocket', tag: 'CALL');
      _log.info('VoiceCallService: 📞 CALL ACCEPTED - Waiting for connection...', tag: 'CALL');

      return true;
    } catch (e, stackTrace) {
      _log.error('VoiceCallService: ❌ acceptCall() error: $e', tag: 'CALL');
      _log.error('VoiceCallService: Stack trace: $stackTrace', tag: 'CALL');
      await endCall();
      return false;
    }
  }

  /// Reject incoming call
  void rejectCall() {
    _log.info('VoiceCallService: rejectCall() - current state: $_callState', tag: 'CALL');
    if (_callState != CallState.ringing) {
      _log.warning('VoiceCallService: rejectCall() aborted - wrong state: $_callState', tag: 'CALL');
      return;
    }

    _log.info('VoiceCallService: Sending call_reject via signaling', tag: 'CALL');
    onSignalingMessage?.call({
      'type': 'call_reject',
      'conversation_id': _currentConversationId,
      'reason': 'rejected',
    });

    _cleanup();
  }

  /// Handle call answer (caller side)
  Future<void> handleCallAnswer(String sdp, String sdpType) async {
    _log.info('VoiceCallService: ========================================', tag: 'CALL');
    _log.info('VoiceCallService: 📞 RECEIVED CALL ANSWER', tag: 'CALL');
    _log.info('VoiceCallService: Current state: $_callState', tag: 'CALL');
    _log.info('VoiceCallService: Answer SDP type: $sdpType, length: ${sdp.length} chars', tag: 'CALL');

    if (_callState != CallState.calling) {
      _log.warning('VoiceCallService: ❌ handleCallAnswer() aborted - wrong state: $_callState (expected: calling)', tag: 'CALL');
      return;
    }

    try {
      _log.info('VoiceCallService: Setting remote description (answer from callee)...', tag: 'CALL');
      final remoteStart = DateTime.now();
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, sdpType),
      );
      final remoteDuration = DateTime.now().difference(remoteStart);
      _log.info('VoiceCallService: ✓ Remote description (answer) set in ${remoteDuration.inMilliseconds}ms', tag: 'CALL');
      _log.info('VoiceCallService: ⏳ Waiting for ICE negotiation to complete...', tag: 'CALL');
      _log.info('VoiceCallService: (Watch for ICE states and onTrack event)', tag: 'CALL');
      // Note: State will change to inCall via onConnectionState callback when connected
    } catch (e, stackTrace) {
      _log.error('VoiceCallService: ❌ handleCallAnswer() error: $e', tag: 'CALL');
      _log.error('VoiceCallService: Stack trace: $stackTrace', tag: 'CALL');
      await endCall();
    }
  }

  /// Handle call rejection
  void handleCallRejected(String reason) {
    _log.info('VoiceCallService: handleCallRejected() - reason: $reason, current state: $_callState', tag: 'CALL');
    if (_callState == CallState.calling) {
      _cleanup();
    } else {
      _log.debug('VoiceCallService: handleCallRejected() - not in calling state, ignoring', tag: 'CALL');
    }
  }

  /// Handle ICE candidate from remote peer
  Future<void> handleIceCandidate(String candidate, String sdpMid, int sdpMLineIndex) async {
    if (_peerConnection == null) {
      _log.warning('VoiceCallService: ⚠️ Peer connection not ready - QUEUING ICE candidate!', tag: 'CALL');
      _log.info('VoiceCallService: Queued candidate: mid=$sdpMid, index=$sdpMLineIndex', tag: 'CALL');
      _pendingIceCandidates.add({
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
      });
      _log.info('VoiceCallService: Total queued candidates: ${_pendingIceCandidates.length}', tag: 'CALL');
      return;
    }

    await _addIceCandidate(candidate, sdpMid, sdpMLineIndex);
  }

  /// Add ICE candidate to peer connection
  Future<void> _addIceCandidate(String candidate, String sdpMid, int sdpMLineIndex) async {
    try {
      _log.debug('VoiceCallService: ✓ Adding ICE candidate (mid: $sdpMid)', tag: 'CALL');
      await _peerConnection!.addCandidate(
        RTCIceCandidate(candidate, sdpMid, sdpMLineIndex),
      );
      _log.info('VoiceCallService: ✓ ICE candidate added successfully', tag: 'CALL');
    } catch (e) {
      _log.error('VoiceCallService: ❌ ICE candidate error: $e', tag: 'CALL');
    }
  }

  /// End the current call
  Future<void> endCall() async {
    _log.info('VoiceCallService: endCall() - current state: $_callState', tag: 'CALL');
    if (_callState == CallState.idle) {
      _log.debug('VoiceCallService: endCall() - already idle, nothing to do', tag: 'CALL');
      return;
    }

    // Notify remote peer
    _log.info('VoiceCallService: Sending call_end via signaling', tag: 'CALL');
    onSignalingMessage?.call({
      'type': 'call_end',
      'conversation_id': _currentConversationId,
    });

    _cleanup();
  }

  /// Handle call ended by remote peer
  void handleCallEnded() {
    _log.info('VoiceCallService: handleCallEnded() - cleaning up', tag: 'CALL');
    _cleanup();
  }

  /// Toggle microphone mute
  void toggleMute() {
    if (_localStream == null) {
      _log.warning('VoiceCallService: toggleMute() - no local stream', tag: 'CALL');
      return;
    }

    _isMuted = !_isMuted;
    _log.info('VoiceCallService: Microphone muted: $_isMuted', tag: 'CALL');
    _localStream!.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
  }

  /// Toggle speaker (for mobile, on desktop this is usually not needed)
  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    // On Windows, speaker toggle is handled by system audio
  }

  /// Create WebRTC peer connection
  Future<void> _createPeerConnection() async {
    _log.debug('VoiceCallService: Creating RTCPeerConnection with STUN/TURN servers...', tag: 'CALL');
    _peerConnection = await createPeerConnection(_iceServers);
    _log.info('VoiceCallService: RTCPeerConnection created successfully', tag: 'CALL');

    // Initialize remote audio renderer for Windows playback
    _log.debug('VoiceCallService: Initializing remote audio renderer...', tag: 'CALL');
    _remoteAudioRenderer = RTCVideoRenderer();
    await _remoteAudioRenderer!.initialize();
    _log.info('VoiceCallService: ✓ Remote audio renderer initialized', tag: 'CALL');

    // Process queued ICE candidates (fix for race condition)
    if (_pendingIceCandidates.isNotEmpty) {
      _log.info('VoiceCallService: ⚡ Processing ${_pendingIceCandidates.length} queued ICE candidates', tag: 'CALL');
      for (var ice in _pendingIceCandidates) {
        await _addIceCandidate(ice['candidate'], ice['sdpMid'], ice['sdpMLineIndex']);
      }
      _pendingIceCandidates.clear();
      _log.info('VoiceCallService: ✓ All queued ICE candidates processed', tag: 'CALL');
    }

    // Handle ICE candidates (our local candidates to send to remote peer)
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _log.info('VoiceCallService: ➤ Generated local ICE candidate (mid: ${candidate.sdpMid}, index: ${candidate.sdpMLineIndex})', tag: 'CALL');
        _log.debug('VoiceCallService: ➤ Candidate: ${candidate.candidate}', tag: 'CALL');
        _log.info('VoiceCallService: ➤ Sending ICE candidate to remote peer via signaling', tag: 'CALL');
        onSignalingMessage?.call({
          'type': 'ice_candidate',
          'conversation_id': _currentConversationId,
          'candidate': candidate.candidate,
          'sdp_mid': candidate.sdpMid,
          'sdp_mline_index': candidate.sdpMLineIndex,
        });
      } else {
        _log.debug('VoiceCallService: onIceCandidate with null candidate (gathering complete)', tag: 'CALL');
      }
    };

    // Handle ICE gathering state
    _peerConnection!.onIceGatheringState = (state) {
      _log.info('VoiceCallService: ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', tag: 'CALL');
      _log.info('VoiceCallService: 🔍 ICE GATHERING STATE CHANGED: $state', tag: 'CALL');
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        _log.info('VoiceCallService: ✓ ICE gathering completed - all candidates collected', tag: 'CALL');
      } else if (state == RTCIceGatheringState.RTCIceGatheringStateGathering) {
        _log.info('VoiceCallService: ⚡ ICE gathering in progress...', tag: 'CALL');
      } else {
        _log.info('VoiceCallService: ICE gathering state: $state', tag: 'CALL');
      }
      _log.info('VoiceCallService: ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', tag: 'CALL');
    };

    // Handle ICE connection state
    _peerConnection!.onIceConnectionState = (state) {
      _log.info('VoiceCallService: ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', tag: 'CALL');
      _log.info('VoiceCallService: 🌐 ICE CONNECTION STATE CHANGED: $state', tag: 'CALL');

      // Notify UI for network quality indicator
      _iceConnectionStateController.add(state);

      if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
        _log.info('VoiceCallService: ⚡ Checking ICE connectivity...', tag: 'CALL');
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        _log.info('VoiceCallService: ✓✓✓ ICE CONNECTION ESTABLISHED!', tag: 'CALL');
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _log.info('VoiceCallService: ✓ ICE connection completed (all checks done)', tag: 'CALL');
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _log.error('VoiceCallService: ❌ ICE CONNECTION FAILED!', tag: 'CALL');
        _log.error('VoiceCallService: Possible causes: firewall, no TURN server, NAT issues', tag: 'CALL');
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _log.warning('VoiceCallService: ⚠️ ICE connection disconnected', tag: 'CALL');
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _log.info('VoiceCallService: ICE connection closed', tag: 'CALL');
      }
      _log.info('VoiceCallService: ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', tag: 'CALL');
    };

    // Handle signaling state
    _peerConnection!.onSignalingState = (state) {
      _log.info('VoiceCallService: ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', tag: 'CALL');
      _log.info('VoiceCallService: 📡 SIGNALING STATE CHANGED: $state', tag: 'CALL');

      if (state == RTCSignalingState.RTCSignalingStateStable) {
        _log.info('VoiceCallService: ✓ Signaling stable - negotiation complete', tag: 'CALL');
      } else if (state == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        _log.info('VoiceCallService: Have local offer - waiting for answer', tag: 'CALL');
      } else if (state == RTCSignalingState.RTCSignalingStateHaveRemoteOffer) {
        _log.info('VoiceCallService: Have remote offer - need to create answer', tag: 'CALL');
      }
      _log.info('VoiceCallService: ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', tag: 'CALL');
    };

    // Handle connection state changes (CRITICAL for moving to inCall)
    _peerConnection!.onConnectionState = (state) {
      _log.info('VoiceCallService: ✓✓✓ RTCPeerConnection State: $state ✓✓✓', tag: 'CALL');

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateNew) {
        _log.debug('VoiceCallService: Connection state: NEW', tag: 'CALL');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
        _log.info('VoiceCallService: Connection state: CONNECTING (ICE negotiation in progress)', tag: 'CALL');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _log.info('VoiceCallService: ★★★ WebRTC connection ESTABLISHED! Changing to inCall state ★★★', tag: 'CALL');
        _setCallState(CallState.inCall);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _log.warning('VoiceCallService: Connection state: DISCONNECTED, notifying remote and cleaning up', tag: 'CALL');
        // Send call_end notification to remote peer before cleanup
        if (_currentConversationId != null) {
          _log.info('VoiceCallService: Sending call_end due to DISCONNECTED state', tag: 'CALL');
          onSignalingMessage?.call({
            'type': 'call_end',
            'conversation_id': _currentConversationId,
          });
        }
        _cleanup();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _log.error('VoiceCallService: Connection state: FAILED, notifying remote and cleaning up', tag: 'CALL');
        // Send call_end notification to remote peer before cleanup
        if (_currentConversationId != null) {
          _log.info('VoiceCallService: Sending call_end due to FAILED state', tag: 'CALL');
          onSignalingMessage?.call({
            'type': 'call_end',
            'conversation_id': _currentConversationId,
          });
        }
        _cleanup();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _log.debug('VoiceCallService: Connection state: CLOSED', tag: 'CALL');
      } else {
        _log.warning('VoiceCallService: Connection state: UNKNOWN ($state)', tag: 'CALL');
      }
    };

    // Handle remote track
    _peerConnection!.onTrack = (event) async {
      _log.info('VoiceCallService: ★ onTrack event received', tag: 'CALL');
      if (event.streams.isNotEmpty) {
        _log.info('VoiceCallService: ★ Remote audio stream received (${event.streams.length} streams)', tag: 'CALL');
        _remoteStream = event.streams[0];

        // Attach to audio renderer for Windows playback (CRITICAL FIX)
        if (_remoteAudioRenderer != null) {
          _remoteAudioRenderer!.srcObject = _remoteStream;
          _log.info('VoiceCallService: ✓✓✓ Remote stream attached to audio renderer (Windows playback enabled)', tag: 'CALL');
        } else {
          _log.error('VoiceCallService: ❌ Remote audio renderer is NULL - audio will NOT play!', tag: 'CALL');
        }

        _remoteStreamController.add(_remoteStream);

        // WORKAROUND for flutter_webrtc bug #1668 on Windows:
        // onConnectionState callback doesn't fire, so we use onTrack as indicator
        // If we receive remote stream, connection IS established!
        if (_callState == CallState.connecting || _callState == CallState.calling) {
          _log.info('VoiceCallService: ★★★ WORKAROUND: Remote stream received → assuming connection established!', tag: 'CALL');
          _log.info('VoiceCallService: ★★★ Changing to inCall state (onConnectionState bug workaround)', tag: 'CALL');
          _setCallState(CallState.inCall);
        }
      } else {
        _log.warning('VoiceCallService: onTrack event but no streams!', tag: 'CALL');
      }
    };
  }

  /// Get local audio stream with detailed logging
  Future<MediaStream?> _getLocalStream() async {
    try {
      // macOS flutter_webrtc bug #2018: CoreAudio ADM returns 0 audio devices
      // from enumerateDevices() until audio session is started.
      // Workaround: skip enumeration on macOS, call getUserMedia directly.
      if (Platform.isMacOS) {
        _log.info('VoiceCallService: macOS - skipping enumerateDevices (flutter_webrtc bug #2018), calling getUserMedia directly', tag: 'CALL');
        final stream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': false,
        });
        final audioTracks = stream.getAudioTracks();
        _log.info('VoiceCallService: ✓ macOS audio stream acquired: ${audioTracks.length} track(s)', tag: 'CALL');
        return stream;
      }

      // Windows/Linux: enumerate devices first, then select explicitly
      _log.info('VoiceCallService: Enumerating audio devices...', tag: 'CALL');
      final devices = await navigator.mediaDevices.enumerateDevices();
      _log.info('VoiceCallService: Total devices found: ${devices.length}', tag: 'CALL');

      for (var i = 0; i < devices.length; i++) {
        final device = devices[i];
        _log.info('VoiceCallService: Device $i: kind=${device.kind}, label="${device.label}"', tag: 'CALL');
      }

      final audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
      _log.info('VoiceCallService: Audio inputs: ${audioInputs.length}', tag: 'CALL');

      if (audioInputs.isEmpty) {
        _log.error('VoiceCallService: NO MICROPHONE FOUND!', tag: 'CALL');
        throw Exception('NO_MICROPHONE');
      }

      final selectedDevice = audioInputs.first;
      _log.info('VoiceCallService: Using microphone: "${selectedDevice.label}"', tag: 'CALL');

      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'deviceId': selectedDevice.deviceId,
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });

      final audioTracks = stream.getAudioTracks();
      _log.info('VoiceCallService: Audio stream acquired: ${audioTracks.length} track(s)', tag: 'CALL');
      return stream;
    } catch (e) {
      _log.error('VoiceCallService: _getLocalStream() failed: $e', tag: 'CALL');
      rethrow;
    }
  }

  /// Set call state and notify listeners
  void _setCallState(CallState state) {
    _log.info('VoiceCallService: STATE CHANGE: $_callState → $state (notifying listeners)', tag: 'CALL');
    _callState = state;
    _callStateController.add(state);
  }

  /// Cleanup resources
  void _cleanup() {
    _log.info('VoiceCallService: _cleanup() - releasing WebRTC resources', tag: 'CALL');

    // Stop all local tracks explicitly before disposing stream
    _localStream?.getTracks().forEach((track) {
      track.stop();
    });
    _localStream?.dispose();
    _localStream = null;

    // Stop all remote tracks explicitly before disposing stream
    _remoteStream?.getTracks().forEach((track) {
      track.stop();
    });
    _remoteStream?.dispose();
    _remoteStream = null;
    _remoteStreamController.add(null);

    // Dispose remote audio renderer
    _remoteAudioRenderer?.dispose();
    _remoteAudioRenderer = null;
    _log.debug('VoiceCallService: Remote audio renderer disposed', tag: 'CALL');

    // Close peer connection (fire-and-forget, but log errors)
    _peerConnection?.close().catchError((e) {
      _log.error('VoiceCallService: Error closing peer connection: $e', tag: 'CALL');
    });
    _peerConnection = null;

    // Clear pending ICE candidates
    if (_pendingIceCandidates.isNotEmpty) {
      _log.info('VoiceCallService: Clearing ${_pendingIceCandidates.length} pending ICE candidates', tag: 'CALL');
      _pendingIceCandidates.clear();
    }

    _currentConversationId = null;
    _isMuted = false;
    _isSpeakerOn = true;

    _setCallState(CallState.idle);
    _log.debug('VoiceCallService: Cleanup completed, state reset to idle', tag: 'CALL');
  }

  /// Dispose service
  void dispose() {
    _cleanup();
    _callStateController.close();
    _remoteStreamController.close();
    _incomingCallController.close();
    _iceConnectionStateController.close();
  }
}

/// Call states
enum CallState {
  idle,       // No active call
  calling,    // Initiating a call (waiting for answer)
  ringing,    // Receiving an incoming call
  connecting, // Call accepted, establishing connection
  inCall,     // Active call in progress
}

/// Incoming call data
class IncomingCall {
  final int conversationId;
  final String callerId;
  final String callerName;
  final String sdp;
  final String sdpType;

  IncomingCall({
    required this.conversationId,
    required this.callerId,
    required this.callerName,
    required this.sdp,
    required this.sdpType,
  });
}
