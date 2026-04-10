import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'eastern.dart';
import '../services/api_service.dart';
import '../services/chat_service.dart';
import '../services/voice_call_service.dart';
import '../services/logger_service.dart';
import 'incoming_call_dialog.dart';
import '../utils/file_picker_helper.dart';

final _log = LoggerService();

/// Live Chat Dialog for members to chat with support
class LiveChatDialog extends StatefulWidget {
  final String mitgliedernummer;
  final String userName;
  final CallOfferEvent? pendingCall;

  const LiveChatDialog({
    super.key,
    required this.mitgliedernummer,
    required this.userName,
    this.pendingCall,
  });

  @override
  State<LiveChatDialog> createState() => _LiveChatDialogState();
}

class _LiveChatDialogState extends State<LiveChatDialog> {
  final _apiService = ApiService();
  final _chatService = ChatService();
  final _voiceCallService = VoiceCallService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  int? _conversationId;
  bool _isLoading = true;
  bool _isConnected = false;
  bool _isSending = false;
  String? _typingUser;
  Timer? _typingTimer;

  // Voice call state - most WebRTC state now managed by VoiceCallService
  Timer? _callDurationTimer;
  Duration _callDuration = Duration.zero;
  String _remoteName = 'Support';

  // Incoming call state (when admin calls member)
  String? _pendingSdp;
  String? _pendingSdpType;
  int? _incomingCallConvId;

  // File upload state
  List<File> _selectedFiles = [];
  bool _isUploading = false;

  // Stream subscriptions
  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _callAnswerSubscription;
  StreamSubscription? _callRejectedSubscription;
  StreamSubscription? _callEndedSubscription;
  StreamSubscription? _iceCandidateSubscription;
  StreamSubscription? _callBusySubscription;
  StreamSubscription? _readReceiptSubscription;
  StreamSubscription? _callOfferSubscription;
  StreamSubscription? _callStateSubscription;
  StreamSubscription? _remoteStreamSubscription;
  StreamSubscription? _iceConnectionStateSubscription;

  // Remote audio stream for playback (Windows fix)
  MediaStream? _remoteAudioStream;
  RTCIceConnectionState? _iceConnectionState;

  @override
  void initState() {
    super.initState();

    // Configure VoiceCallService signaling via ChatService
    _voiceCallService.onSignalingMessage = (message) {
      final type = message['type'] as String;
      final convId = message['conversation_id'] as int;

      switch (type) {
        case 'call_offer':
          _chatService.sendCallOffer(convId, message['sdp'] as String, message['sdp_type'] as String);
          break;
        case 'call_answer':
          _chatService.sendCallAnswer(convId, message['sdp'] as String, message['sdp_type'] as String);
          break;
        case 'call_reject':
          _chatService.sendCallReject(convId, message['reason'] as String);
          break;
        case 'call_end':
          _chatService.sendCallEnd(convId);
          break;
        case 'ice_candidate':
          _chatService.sendIceCandidate(
            convId,
            message['candidate'] as String,
            message['sdp_mid'] as String,
            message['sdp_mline_index'] as int,
          );
          break;
      }
    };

    // Listen to VoiceCallService state changes to update UI
    _callStateSubscription = _voiceCallService.callStateStream.listen((state) {
      _log.info('LiveChat: VoiceCallService state changed to: $state', tag: 'CALL');
      if (mounted) {
        setState(() {}); // Trigger UI rebuild
      }
    });

    // Listen to remote audio stream for playback (Windows fix)
    _remoteStreamSubscription = _voiceCallService.remoteStreamStream.listen((stream) {
      _log.info('LiveChat: Remote stream updated: ${stream != null ? "RECEIVED" : "NULL"}', tag: 'CALL');
      if (mounted) {
        setState(() {
          _remoteAudioStream = stream;
        });
      }
    });

    // Listen to ICE connection state for network quality indicator
    _iceConnectionStateSubscription = _voiceCallService.iceConnectionStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _iceConnectionState = state;
        });
      }
    });

    _initChat();

    // Handle pending call if passed from dashboard
    if (widget.pendingCall != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handlePendingCall(widget.pendingCall!);
      });
    }
  }

  void _handlePendingCall(CallOfferEvent event) async {
    _log.info('LiveChat: _handlePendingCall() from ${event.callerName} (conv: ${event.conversationId})', tag: 'CALL');
    // Wait a bit for WebSocket to connect
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) {
      _log.warning('LiveChat: _handlePendingCall() - not mounted, aborting', tag: 'CALL');
      return;
    }

    _incomingCallConvId = event.conversationId;
    _pendingSdp = event.sdp;
    _pendingSdpType = event.sdpType;
    _remoteName = event.callerName;
    _log.debug('LiveChat: Pending call data set - SDP type: ${event.sdpType}', tag: 'CALL');

    // CRITICAL FIX: Inform VoiceCallService about incoming call BEFORE accepting
    // This sets the call state to ringing, which is required for acceptCall() to work
    _log.info('LiveChat: Informing VoiceCallService about incoming call...', tag: 'CALL');
    _voiceCallService.handleIncomingCall(
      event.conversationId,
      event.callerId,
      event.callerName,
      event.sdp,
      event.sdpType,
    );

    // Wait a tiny bit for state to update
    await Future.delayed(const Duration(milliseconds: 100));

    // Auto-accept the call (user already accepted in the dialog)
    if (mounted) {
      _log.info('LiveChat: Auto-accepting pending call', tag: 'CALL');
      _acceptCall();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _callDurationTimer?.cancel();
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _connectionSubscription?.cancel();
    _errorSubscription?.cancel();
    _callAnswerSubscription?.cancel();
    _callRejectedSubscription?.cancel();
    _callEndedSubscription?.cancel();
    _iceCandidateSubscription?.cancel();
    _callBusySubscription?.cancel();
    _readReceiptSubscription?.cancel();
    _callOfferSubscription?.cancel();
    _callStateSubscription?.cancel();
    _remoteStreamSubscription?.cancel();
    _iceConnectionStateSubscription?.cancel();
    _endCallCleanup();
    // Don't leave conversation - dashboard maintains the subscription for background notifications
    super.dispose();
  }

  Future<void> _initChat() async {
    _log.info('LiveChat: _initChat() starting for ${widget.mitgliedernummer}', tag: 'CHAT');
    try {
      // Start or get existing conversation via REST API
      _log.debug('LiveChat: Calling startChat API...', tag: 'CHAT');
      final result = await _apiService.startChat(widget.mitgliedernummer);

      if (result['success'] == true) {
        // Parse conversation_id as int (API may return string)
        final convId = result['conversation_id'];
        _conversationId = convId is int ? convId : int.tryParse(convId.toString());
        _log.info('LiveChat: Got conversation_id=$_conversationId', tag: 'CHAT');

        // Load existing messages
        await _loadMessages();

        // Connect to WebSocket for real-time updates
        await _connectWebSocket();
      } else {
        _log.error('LiveChat: startChat failed: ${result['message']}', tag: 'CHAT');
        _showError(result['message'] ?? 'Fehler beim Starten des Chats');
      }
    } catch (e) {
      _log.error('LiveChat: _initChat exception: $e', tag: 'CHAT');
      _showError('Verbindungsfehler: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMessages() async {
    if (_conversationId == null) return;
    _log.debug('LiveChat: _loadMessages() for conversation $_conversationId', tag: 'CHAT');

    try {
      final result = await _apiService.getChatMessages(
        _conversationId!,
        widget.mitgliedernummer,
      );

      if (result['success'] == true && mounted) {
        // API returns messages in data.messages (with translation support)
        final data = result['data'] as Map<String, dynamic>? ?? result;
        final messagesList = List<Map<String, dynamic>>.from(data['messages'] ?? result['messages'] ?? []);
        _log.info('LiveChat: Loaded ${messagesList.length} messages', tag: 'CHAT');
        setState(() {
          _messages = messagesList;
        });
        _scrollToBottom();
      } else {
        _log.warning('LiveChat: _loadMessages failed: ${result['message']}', tag: 'CHAT');
      }
    } catch (e) {
      _log.error('LiveChat: _loadMessages exception: $e', tag: 'CHAT');
    }
  }

  Future<void> _connectWebSocket() async {
    _log.info('LiveChat: _connectWebSocket() starting...', tag: 'CHAT');
    // Set up chat listeners
    _messageSubscription = _chatService.messageStream.listen((message) {
      if (message.conversationId == _conversationId && mounted) {
        // Skip messages from ourselves (already added locally when sent)
        if (message.senderName == widget.userName) {
          _log.debug('LiveChat: Skipping own message from WebSocket', tag: 'CHAT');
          return;
        }
        setState(() {
          _messages.add({
            'id': message.id,
            'message': message.message,
            'sender_id': message.senderId,
            'sender_name': message.senderName,
            'sender_role': message.senderRole,
            'is_own': false,
            'created_at': message.createdAt.toIso8601String(),
          });
        });
        _scrollToBottom();

        // Fetch translated version from API
        if (_conversationId != null) {
          Future.delayed(const Duration(milliseconds: 500), () async {
            if (!mounted) return;
            try {
              final result = await _apiService.getChatMessages(_conversationId!, widget.mitgliedernummer, lastMessageId: message.id - 1);
              if (!mounted) return;
              if (result['success'] == true) {
                final data = result['data'] as Map<String, dynamic>? ?? result;
                final translated = List<Map<String, dynamic>>.from(data['messages'] ?? result['messages'] ?? []);
                for (final tm in translated) {
                  if (tm['id'] == message.id && tm['is_translated'] == true) {
                    setState(() {
                      final idx = _messages.indexWhere((m) => m['id'] == message.id);
                      if (idx >= 0) {
                        _messages[idx]['message'] = tm['message'];
                        _messages[idx]['original_message'] = tm['original_message'];
                        _messages[idx]['is_translated'] = true;
                      }
                    });
                    break;
                  }
                }
              }
            } catch (_) {}
          });
        }
      }
    });

    _typingSubscription = _chatService.typingStream.listen((event) {
      if (mounted) {
        setState(() => _typingUser = event.userName);
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _typingUser = null);
        });
      }
    });

    _connectionSubscription = _chatService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() => _isConnected = connected);
      }
    });

    _errorSubscription = _chatService.errorStream.listen((error) {
      debugPrint('Chat error: $error');
    });

    // Set up voice call listeners
    _callAnswerSubscription = _chatService.callAnswerStream.listen((event) {
      _log.info('LiveChat: [WS] Received call_answer from ${event.answererName} (conv: ${event.conversationId})', tag: 'CALL');
      if (!mounted) return;
      if (event.conversationId == _conversationId) {
        _handleCallAnswer(event.sdp, event.sdpType, event.answererName);
      } else {
        _log.warning('LiveChat: call_answer ignored - conversationId mismatch (expected: $_conversationId)', tag: 'CALL');
      }
    });

    _callRejectedSubscription = _chatService.callRejectedStream.listen((event) {
      _log.info('LiveChat: [WS] Received call_rejected (conv: ${event.conversationId}, reason: ${event.reason})', tag: 'CALL');
      if (!mounted) return;
      if (event.conversationId == _conversationId) {
        _handleCallRejected(event.reason);
      }
    });

    _callEndedSubscription = _chatService.callEndedStream.listen((event) {
      _log.info('LiveChat: [WS] Received call_ended (conv: ${event.conversationId})', tag: 'CALL');
      if (!mounted) return;
      if (event.conversationId == _conversationId) {
        _handleCallEnded();
      }
    });

    _iceCandidateSubscription = _chatService.iceCandidateStream.listen((event) {
      _log.debug('LiveChat: [WS] Received ice_candidate (conv: ${event.conversationId})', tag: 'CALL');
      if (!mounted) return;
      if (event.conversationId == _conversationId) {
        _handleIceCandidate(event.candidate, event.sdpMid, event.sdpMLineIndex);
      }
    });

    _callBusySubscription = _chatService.callBusyStream.listen((convId) {
      _log.info('LiveChat: [WS] Received call_busy (conv: $convId)', tag: 'CALL');
      if (!mounted) return;
      if (convId == _conversationId) {
        _showError('Der Support ist bereits in einem anderen Anruf');
        _endCallCleanup();
      }
    });

    // Incoming call listener (when admin calls while member has chat open)
    _callOfferSubscription = _chatService.callOfferStream.listen((event) {
      _log.info('LiveChat: [WS] Received call_offer from ${event.callerName} (conv: ${event.conversationId})', tag: 'CALL');
      if (!mounted) return;
      if (event.conversationId == _conversationId) {
        _handleIncomingCall(event);
      }
    });

    // Read receipt listener
    _readReceiptSubscription = _chatService.readReceiptStream.listen((event) {
      if (!mounted) return;
      if (event.conversationId == _conversationId) {
        setState(() {
          for (var msg in _messages) {
            if (event.messageIds.contains(msg['id'])) {
              msg['status'] = event.status;
              if (event.status == 'read') {
                msg['is_read'] = true;
              }
            }
          }
        });
      }
    });

    // Connect and authenticate
    _log.info('LiveChat: Calling chatService.connect(${widget.mitgliedernummer})', tag: 'CHAT');
    final connected = await _chatService.connect(widget.mitgliedernummer, userName: widget.userName);
    _log.info('LiveChat: connect() returned: $connected', tag: 'CHAT');

    if (connected && _conversationId != null) {
      _log.info('LiveChat: Joining conversation $_conversationId', tag: 'CHAT');
      _chatService.joinConversation(_conversationId!);
      if (mounted) {
        setState(() => _isConnected = true);
        _log.info('LiveChat: Connected and joined successfully!', tag: 'CHAT');
      }
    } else {
      _log.warning('LiveChat: Failed to connect or conversationId is null (connected=$connected, convId=$_conversationId)', tag: 'CHAT');
    }
  }

  // ==================== Voice Call Methods ====================

  /// Start call to support - REFACTORED to use VoiceCallService
  Future<void> _startCall() async {
    _log.info('LiveChat: _startCall() initiated by member (using VoiceCallService)', tag: 'CALL');
    if (_conversationId == null || _voiceCallService.callState != CallState.idle) {
      _log.warning('LiveChat: _startCall() aborted - convId: $_conversationId, status: ${_voiceCallService.callState}', tag: 'CALL');
      return;
    }
    if (!mounted) return;

    try {
      // Use VoiceCallService to start the call
      // For member calling support, we use "support" as targetUserId
      final success = await _voiceCallService.startCall(_conversationId!, 'support', 'Support');

      if (!success) {
        throw Exception('Failed to start call via VoiceCallService');
      }

      _log.info('LiveChat: Call to support started successfully via VoiceCallService', tag: 'CALL');

      if (mounted) {
        _startCallDurationTimer();
      }

    } catch (e) {
      _log.error('LiveChat: _startCall() error: $e', tag: 'CALL');
      if (e.toString().contains('NO_MICROPHONE')) {
        _showError('Kein Mikrofon gefunden. Bitte schließen Sie ein Mikrofon an und versuchen Sie es erneut.');
      } else {
        _showError('Fehler beim Starten des Anrufs: $e');
      }
      await _voiceCallService.endCall();
    }
  }

  /// Handle answer from support - REFACTORED to use VoiceCallService
  Future<void> _handleCallAnswer(String sdp, String sdpType, String answererName) async {
    _log.info('LiveChat: _handleCallAnswer() from $answererName, sdpType: $sdpType (using VoiceCallService)', tag: 'CALL');

    try {
      _remoteName = answererName;
      await _voiceCallService.handleCallAnswer(sdp, sdpType);
      _log.info('LiveChat: Call answer handled successfully via VoiceCallService', tag: 'CALL');
      if (mounted) {
        _startCallDurationTimer();
      }
    } catch (e) {
      _log.error('LiveChat: _handleCallAnswer() error: $e', tag: 'CALL');
      _showError('Fehler beim Verbinden: $e');
      _endCallCleanup();
    }
  }

  /// Handle call rejection - REFACTORED to use VoiceCallService
  void _handleCallRejected(String reason) {
    _log.info('LiveChat: _handleCallRejected() reason: $reason (using VoiceCallService)', tag: 'CALL');
    String message;
    switch (reason) {
      case 'busy':
        message = 'Support ist beschäftigt';
        break;
      case 'rejected':
        message = 'Anruf wurde abgelehnt';
        break;
      default:
        message = 'Anruf konnte nicht verbunden werden';
    }
    _showError(message);
    _voiceCallService.handleCallRejected(reason);
    _endCallCleanup();
  }

  /// Handle call ended by remote peer - REFACTORED to use VoiceCallService
  void _handleCallEnded() {
    _log.info('LiveChat: _handleCallEnded() received (using VoiceCallService)', tag: 'CALL');
    final wasInCall = _voiceCallService.callState != CallState.idle;
    _voiceCallService.handleCallEnded();
    _endCallCleanup();
    if (wasInCall && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anruf beendet'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  /// Handle ICE candidate - REFACTORED to use VoiceCallService
  Future<void> _handleIceCandidate(String candidate, String sdpMid, int sdpMLineIndex) async {
    if (!mounted) return;
    _log.debug('LiveChat: Handling ICE candidate via VoiceCallService', tag: 'CALL');
    await _voiceCallService.handleIceCandidate(candidate, sdpMid, sdpMLineIndex);
  }

  /// End call - REFACTORED to use VoiceCallService
  void _endCall() {
    _log.info('LiveChat: _endCall() (using VoiceCallService)', tag: 'CALL');
    _voiceCallService.endCall();
    _endCallCleanup();
  }

  /// Cleanup local UI state - WebRTC cleanup now handled by VoiceCallService
  void _endCallCleanup() {
    _log.info('LiveChat: _endCallCleanup() - cleaning up UI state', tag: 'CALL');
    _callDurationTimer?.cancel();
    _pendingSdp = null;
    _pendingSdpType = null;
    if (mounted) {
      setState(() {
        _callDuration = Duration.zero;
      });
    }
    _log.debug('LiveChat: Call cleanup completed', tag: 'CALL');
  }

  /// Handle incoming call while chat dialog is open - Uses VoiceCallService
  void _handleIncomingCall(CallOfferEvent event) {
    _log.info('LiveChat: _handleIncomingCall() from ${event.callerName}', tag: 'CALL');
    if (!mounted) return;

    if (_voiceCallService.callState != CallState.idle) {
      // Check if this is a duplicate offer for the SAME conversation
      if (_incomingCallConvId == event.conversationId) {
        _log.warning('LiveChat: Duplicate call_offer for same conversation (${event.conversationId}) - ignoring (state: ${_voiceCallService.callState})', tag: 'CALL');
        return; // Ignore duplicate, DON'T send reject
      }

      // Different call, we're busy
      _log.warning('LiveChat: Already in call (${_voiceCallService.callState}), auto-rejecting with busy', tag: 'CALL');
      _chatService.sendCallReject(event.conversationId, 'busy');
      return;
    }

    _incomingCallConvId = event.conversationId;
    _pendingSdp = event.sdp;
    _pendingSdpType = event.sdpType;
    _remoteName = event.callerName;

    // Also inform VoiceCallService about the incoming call
    _voiceCallService.handleIncomingCall(
      event.conversationId,
      event.callerId,
      event.callerName,
      event.sdp,
      event.sdpType,
    );

    // Show incoming call dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => IncomingCallDialog(
        callerName: event.callerName,
        onAccept: () {
          _log.info('LiveChat: User pressed ACCEPT in dialog', tag: 'CALL');
          Navigator.of(ctx).pop();
          if (mounted) _acceptCall();
        },
        onReject: () {
          _log.info('LiveChat: User pressed REJECT in dialog', tag: 'CALL');
          Navigator.of(ctx).pop();
          if (mounted) {
            _voiceCallService.rejectCall();
            _pendingSdp = null;
            _pendingSdpType = null;
          }
        },
      ),
    );
  }

  /// Accept an incoming call from admin - REFACTORED to use VoiceCallService
  Future<void> _acceptCall() async {
    _log.info('LiveChat: _acceptCall() - convId: $_incomingCallConvId, hasSdp: ${_pendingSdp != null} (using VoiceCallService)', tag: 'CALL');
    if (_pendingSdp == null || _incomingCallConvId == null || !mounted) {
      _log.warning('LiveChat: _acceptCall() aborted - missing data or not mounted', tag: 'CALL');
      return;
    }

    try {
      // Use VoiceCallService to accept the call
      final success = await _voiceCallService.acceptCall(_pendingSdp!, _pendingSdpType!);

      if (!success) {
        throw Exception('Failed to accept call via VoiceCallService');
      }

      _log.info('LiveChat: Call accepted successfully via VoiceCallService', tag: 'CALL');

      if (mounted) {
        _startCallDurationTimer();
      }

    } catch (e) {
      _log.error('LiveChat: _acceptCall() error: $e', tag: 'CALL');
      if (e.toString().contains('NO_MICROPHONE')) {
        _showError('Kein Mikrofon gefunden. Bitte schließen Sie ein Mikrofon an und versuchen Sie es erneut.');
      } else {
        _showError('Fehler beim Annehmen: $e');
      }
      await _voiceCallService.endCall();
    }
  }

  /// Toggle mute - REFACTORED to use VoiceCallService
  void _toggleMute() {
    if (!mounted) return;
    _voiceCallService.toggleMute();
    if (mounted) {
      setState(() {}); // Trigger UI update
    }
  }

  void _toggleSpeaker() {
    if (!mounted) return;
    _voiceCallService.toggleSpeaker();
    if (mounted) {
      setState(() {}); // Trigger UI update
    }
  }

  void _startCallDurationTimer() {
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callDuration += const Duration(seconds: 1));
      }
    });
  }

  // ==================== Chat Methods ====================

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _conversationId == null || _isSending) return;
    _log.info('LiveChat: _sendMessage() - sending to conversation $_conversationId', tag: 'CHAT');

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final result = await _apiService.sendChatMessage(
        _conversationId!,
        widget.mitgliedernummer,
        message,
      );
      _log.debug('LiveChat: sendChatMessage API result: ${result['success']}', tag: 'CHAT');

      if (result['success'] == true && mounted) {
        setState(() {
          _messages.add({
            'id': result['message_id'],
            'message': message,
            'sender_name': widget.userName,
            'sender_role': 'vorsitzer',
            'is_own': true,
            'created_at': result['created_at'] ?? DateTime.now().toIso8601String(),
          });
        });
        _scrollToBottom();

        if (_isConnected) {
          _log.debug('LiveChat: Broadcasting message via WebSocket', tag: 'CHAT');
          _chatService.sendMessage(_conversationId!, message);
        } else {
          _log.warning('LiveChat: Not connected, message sent via API only', tag: 'CHAT');
        }
      } else {
        _log.error('LiveChat: sendChatMessage failed: ${result['message']}', tag: 'CHAT');
        _showError(result['message'] ?? 'Fehler beim Senden');
        _messageController.text = message;
      }
    } catch (e) {
      _log.error('LiveChat: _sendMessage exception: $e', tag: 'CHAT');
      _showError('Fehler beim Senden: $e');
      _messageController.text = message;
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _onTyping() {
    if (_isConnected && _conversationId != null) {
      _chatService.sendTyping(_conversationId!);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ==================== File Upload Methods ====================

  Future<void> _pickFiles() async {
    try {
      final result = await FilePickerHelper.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'txt'],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final files = result.files
            .where((f) => f.path != null)
            .take(10)
            .map((f) => File(f.path!))
            .toList();

        // Check total size (max 100MB)
        int totalSize = 0;
        for (var file in files) {
          totalSize += await file.length();
        }

        if (totalSize > 100 * 1024 * 1024) {
          _showError('Maximale Gesamtgröße: 100 MB');
          return;
        }

        setState(() => _selectedFiles = files);
        await _uploadFiles();
      }
    } catch (e) {
      _log.error('LiveChat: File picker error: $e', tag: 'CHAT');
      _showError('Fehler beim Auswählen der Dateien');
    }
  }

  Future<void> _uploadFiles() async {
    if (_selectedFiles.isEmpty || _conversationId == null || _isUploading) return;

    setState(() => _isUploading = true);

    try {
      final result = await _apiService.uploadChatAttachments(
        conversationId: _conversationId!,
        mitgliedernummer: widget.mitgliedernummer,
        files: _selectedFiles,
        message: _messageController.text.trim().isNotEmpty ? _messageController.text.trim() : null,
      );

      if (result['success'] == true && mounted) {
        _messageController.clear();
        setState(() => _selectedFiles = []);

        // Add message to local list
        final msgData = result['data'];
        if (msgData != null) {
          setState(() {
            _messages.add({
              'id': msgData['message_id'],
              'message': msgData['message'] ?? '',
              'sender_name': widget.userName,
              'sender_role': 'vorsitzer',
              'is_own': true,
              'status': 'sent',
              'created_at': msgData['created_at'] ?? DateTime.now().toIso8601String(),
              'attachments': msgData['attachments'] ?? [],
            });
          });
          _scrollToBottom();

          // Broadcast via WebSocket
          if (_isConnected) {
            _chatService.sendMessage(_conversationId!, msgData['message'] ?? '[Dateien]');
          }
        }
      } else {
        _showError(result['message'] ?? 'Fehler beim Hochladen');
      }
    } catch (e) {
      _log.error('LiveChat: Upload error: $e', tag: 'CHAT');
      _showError('Fehler beim Hochladen: $e');
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _downloadAttachment(Map<String, dynamic> attachment) async {
    try {
      final result = await _apiService.downloadChatAttachment(
        attachmentId: attachment['id'],
        mitgliedernummer: widget.mitgliedernummer,
      );

      if (result['success'] == true && mounted) {
        final base64Data = result['data']['file_data'];
        final filename = result['data']['filename'];

        // Decode and save file
        final bytes = base64Decode(base64Data);
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$filename');
        await file.writeAsBytes(bytes);

        // Open file
        await OpenFilex.open(file.path);
      } else {
        _showError(result['message'] ?? 'Fehler beim Herunterladen');
      }
    } catch (e) {
      _log.error('LiveChat: Download error: $e', tag: 'CHAT');
      _showError('Fehler beim Herunterladen: $e');
    }
  }

  /// Mark all unread messages as read when user focuses on input
  Future<void> _markMessagesAsRead() async {
    if (_conversationId == null) return;

    // Find unread messages from others
    final unreadIds = _messages
        .where((m) => m['is_own'] != true && m['status'] != 'read')
        .map((m) => m['id'] as int)
        .toList();

    if (unreadIds.isEmpty) return;

    try {
      final result = await _apiService.markMessagesRead(
        conversationId: _conversationId!,
        mitgliedernummer: widget.mitgliedernummer,
        status: 'read',
        messageIds: unreadIds,
      );

      if (result['success'] == true && mounted) {
        // Update local state
        setState(() {
          for (var msg in _messages) {
            if (unreadIds.contains(msg['id'])) {
              msg['status'] = 'read';
              msg['is_read'] = true;
            }
          }
        });

        // Broadcast via WebSocket
        if (_isConnected) {
          _chatService.sendReadReceipt(_conversationId!, unreadIds, 'read');
        }
      }
    } catch (e) {
      _log.error('LiveChat: Mark read error: $e', tag: 'CHAT');
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    // For critical errors (NO_MICROPHONE), show persistent SnackBar
    final isCritical = message.contains('Mikrofon') || message.contains('Microphone');
    final duration = isCritical ? const Duration(seconds: 15) : const Duration(seconds: 4);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isCritical ? Icons.mic_off : Icons.error_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        action: isCritical
            ? SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SeasonalBackground(child: Container(
        width: 500,
        height: 550,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            _buildHeader(),
            const Divider(),

            // Messages area
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildMessagesList(),
            ),

            // Typing indicator
            if (_typingUser != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Text(
                      '$_typingUser schreibt...',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),

            // Call overlay - moved to bottom (above input area)
            if (_voiceCallService.callState != CallState.idle) _buildCallOverlay(),

            // Input area
            _buildInputArea(),
          ],
        ),
      )),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.chat, color: Color(0xFF4a90d9), size: 28),
        const SizedBox(width: 12),
        const Text(
          'Live Chat',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Spacer(),

        // Voice call button
        if (_voiceCallService.callState == CallState.idle)
          IconButton(
            icon: const Icon(Icons.call, color: Colors.green),
            onPressed: _isConnected ? _startCall : null,
            tooltip: 'Anrufen',
          ),

        // Connection status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _isConnected ? Colors.green.shade100 : Colors.orange.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _isConnected ? Colors.green : Colors.orange,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _isConnected ? 'Verbunden' : 'Offline',
                style: TextStyle(
                  color: _isConnected ? Colors.green.shade700 : Colors.orange.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (_voiceCallService.callState != CallState.idle) {
              _endCall();
            }
            Navigator.pop(context);
          },
          tooltip: 'Schließen',
        ),
      ],
    );
  }

  Widget _buildCallOverlay() {
    if (_voiceCallService.callState == CallState.calling) {
      return CallingOverlay(
        targetName: 'Support',
        onCancel: _endCall,
      );
    } else if (_voiceCallService.callState == CallState.inCall) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InCallOverlay(
          remoteName: _remoteName,
          callDuration: _callDuration,
          isMuted: _voiceCallService.isMuted,
          isSpeakerOn: _voiceCallService.isSpeakerOn,
          onToggleMute: _toggleMute,
          onToggleSpeaker: _toggleSpeaker,
          onEndCall: _endCall,
          remoteStream: _remoteAudioStream,
          iceConnectionState: _iceConnectionState,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Starten Sie eine Konversation!',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Ein Mitarbeiter wird Ihnen bald antworten.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SeasonalBackground(paintBehind: true, child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final msg = _messages[index];
          final isOwn = msg['is_own'] == true;
          return _buildMessageBubble(msg, isOwn);
        },
      )),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isOwn) {
    final senderRole = msg['sender_role'] ?? 'vorsitzer';
    final isAdmin = ['vorsitzer', 'schatzmeister', 'kassierer'].contains(senderRole);
    final attachments = msg['attachments'] as List? ?? [];
    final messageText = msg['message'] ?? '';

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 8,
          left: isOwn ? 50 : 0,
          right: isOwn ? 0 : 50,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isOwn ? const Color(0xFF4a90d9) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isOwn)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      msg['sender_name'] ?? 'Support',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isAdmin ? Colors.purple.shade700 : const Color(0xFF4a90d9),
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Support',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.purple.shade700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (messageText.isNotEmpty)
              Text(
                messageText,
                style: TextStyle(
                  color: isOwn ? Colors.white : Colors.black87,
                ),
              ),
            // Attachments
            if (attachments.isNotEmpty) ...[
              if (messageText.isNotEmpty) const SizedBox(height: 8),
              ...attachments.map((att) => _buildAttachmentItem(att, isOwn)),
            ],
            // Time and read receipt
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(msg['created_at']),
                    style: TextStyle(
                      fontSize: 10,
                      color: isOwn ? Colors.white70 : Colors.grey.shade500,
                    ),
                  ),
                  if (isOwn) ...[
                    const SizedBox(width: 4),
                    _buildReadReceipt(msg),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentItem(Map<String, dynamic> attachment, bool isOwn) {
    final filename = attachment['filename'] ?? 'Datei';
    final size = attachment['size'] ?? 0;
    final extension = (attachment['extension'] ?? '').toString().toLowerCase();

    IconData icon;
    switch (extension) {
      case 'pdf':
        icon = Icons.picture_as_pdf;
        break;
      case 'png':
      case 'jpg':
      case 'jpeg':
        icon = Icons.image;
        break;
      case 'txt':
        icon = Icons.description;
        break;
      default:
        icon = Icons.attach_file;
    }

    return InkWell(
      onTap: () => _downloadAttachment(attachment),
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isOwn ? Colors.white.withValues(alpha: 0.2) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isOwn ? Colors.white : const Color(0xFF4a90d9)),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    filename,
                    style: TextStyle(
                      fontSize: 12,
                      color: isOwn ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _formatFileSize(size),
                    style: TextStyle(
                      fontSize: 10,
                      color: isOwn ? Colors.white70 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.download, size: 16, color: isOwn ? Colors.white70 : Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  Widget _buildReadReceipt(Map<String, dynamic> msg) {
    final status = msg['status'] ?? 'sent';
    final isRead = msg['is_read'] == true;

    if (isRead || status == 'read') {
      // Double blue checkmarks - read
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.done_all, size: 14, color: Colors.lightBlueAccent),
        ],
      );
    } else if (status == 'delivered') {
      // Double gray checkmarks - delivered
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.done_all, size: 14, color: Colors.white.withValues(alpha: 0.7)),
        ],
      );
    } else {
      // Single checkmark - sent
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.done, size: 14, color: Colors.white.withValues(alpha: 0.7)),
        ],
      );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildInputArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected files preview
        if (_selectedFiles.isNotEmpty)
          Container(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _selectedFiles.map((file) {
                final name = file.path.split(Platform.pathSeparator).last;
                return Chip(
                  label: Text(name, style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() => _selectedFiles.remove(file));
                  },
                );
              }).toList(),
            ),
          ),
        Row(
          children: [
            // Attachment button
            IconButton(
              icon: _isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file, color: Color(0xFF4a90d9)),
              onPressed: _isUploading || _isLoading ? null : _pickFiles,
              tooltip: 'Dateien anhängen (PDF, PNG, JPEG, TXT)',
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                onChanged: (_) => _onTyping(),
                onSubmitted: (_) => _sendMessage(),
                onTap: _markMessagesAsRead,
                decoration: InputDecoration(
                  hintText: 'Nachricht eingeben...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                enabled: !_isLoading,
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: const Color(0xFF4a90d9),
              child: IconButton(
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _isSending ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final messageDate = DateTime(date.year, date.month, date.day);

      if (messageDate == today) {
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else {
        return '${date.day}.${date.month}. ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return '';
    }
  }
}
