import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/api_service.dart';
import '../services/chat_service.dart';
import '../services/voice_call_service.dart';
import '../services/notification_service.dart';
import '../services/logger_service.dart';
import 'incoming_call_dialog.dart';
import 'conversation_list_item.dart';
import 'chat_message_bubble.dart';
import 'chat_input_area.dart';
import 'chat_header.dart';
import 'file_viewer_dialog.dart';
import 'eastern.dart';

final _log = LoggerService();

/// Admin Chat Dialog for Vorsitzer to manage and respond to member chats
class AdminChatDialog extends StatefulWidget {
  final String mitgliedernummer;
  final String userName;
  final CallOfferEvent? pendingCall;

  const AdminChatDialog({
    super.key,
    required this.mitgliedernummer,
    required this.userName,
    this.pendingCall,
  });

  @override
  State<AdminChatDialog> createState() => _AdminChatDialogState();
}

class _AdminChatDialogState extends State<AdminChatDialog> {
  final _apiService = ApiService();
  final _chatService = ChatService();
  final _voiceCallService = VoiceCallService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  // Helper to safely parse conversation ID (API may return string)
  int _parseConvId(dynamic id) {
    if (id is int) return id;
    return int.tryParse(id.toString()) ?? 0;
  }

  List<Map<String, dynamic>> _conversations = [];
  Map<String, dynamic>? _selectedConversation;
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _stats;

  bool _isLoadingConversations = true;
  bool _isLoadingMessages = false;

  // Network status polling
  Timer? _networkPollTimer;
  String? _memberConnectionType;
  int? _memberLatencyMs;
  String? _memberNetworkQuality;
  int? _memberBatteryLevel;
  String? _memberBatteryState;
  bool _isConnected = false;
  bool _isSending = false;
  bool _isUrgent = false;  // 🆕 URGENT notifications flag
  String? _typingUser;
  Timer? _typingTimer;
  Timer? _refreshTimer;

  // Voice call state - most WebRTC state now managed by VoiceCallService
  Timer? _callDurationTimer;
  Duration _callDuration = Duration.zero;
  String _callerName = '';
  int? _incomingCallConvId;
  String? _pendingSdp;
  String? _pendingSdpType;

  // Stream subscriptions
  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _callOfferSubscription;
  StreamSubscription? _callAnswerSubscription;
  StreamSubscription? _callRejectedSubscription;
  StreamSubscription? _callBusySubscription;
  StreamSubscription? _callEndedSubscription;
  StreamSubscription? _iceCandidateSubscription;
  StreamSubscription? _readReceiptSubscription;
  StreamSubscription? _callStateSubscription;
  StreamSubscription? _onlineUsersSubscription;
  StreamSubscription? _remoteStreamSubscription;
  StreamSubscription? _iceConnectionStateSubscription;

  // Remote audio stream for playback (Windows fix)
  MediaStream? _remoteAudioStream;
  RTCIceConnectionState? _iceConnectionState;

  // File upload state
  List<File> _selectedFiles = [];
  bool _isUploading = false;

  // Admin status message (red banner)
  String? _statusMessage;

  // Disposal flag to prevent setState after dispose starts
  bool _isDisposed = false;

  // Safe setState that checks both mounted and _isDisposed
  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();

    // Mark chat dialog as open - stops notifications while viewing
    NotificationService.setChatDialogOpen(true);

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
      _log.info('AdminChat: VoiceCallService state changed to: $state', tag: 'CALL');
      if (mounted) {
        _safeSetState(() {}); // Trigger UI rebuild
      }
    });

    // Listen to remote audio stream for playback (Windows fix)
    _remoteStreamSubscription = _voiceCallService.remoteStreamStream.listen((stream) {
      _log.info('AdminChat: Remote stream updated: ${stream != null ? "RECEIVED" : "NULL"}', tag: 'CALL');
      if (mounted) {
        _safeSetState(() {
          _remoteAudioStream = stream;
        });
      }
    });

    // Listen to ICE connection state for network quality indicator
    _iceConnectionStateSubscription = _voiceCallService.iceConnectionStateStream.listen((state) {
      if (mounted) {
        _safeSetState(() {
          _iceConnectionState = state;
        });
      }
    });

    _loadAdminStatus();
    _loadConversations();
    _connectWebSocket();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _loadConversations(silent: true);
    });

    // Handle pending call passed from dashboard
    if (widget.pendingCall != null) {
      // Wait for conversations to load, then accept the call
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handlePendingCall(widget.pendingCall!);
      });
    }
  }

  void _handlePendingCall(CallOfferEvent event) async {
    _log.info('AdminChat: _handlePendingCall() from ${event.callerName} (conv: ${event.conversationId})', tag: 'CALL');
    // Wait a bit for WebSocket to connect
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) {
      _log.warning('AdminChat: _handlePendingCall() - not mounted, aborting', tag: 'CALL');
      return;
    }

    _incomingCallConvId = event.conversationId;
    _callerName = event.callerName;
    _pendingSdp = event.sdp;
    _pendingSdpType = event.sdpType;
    _log.debug('AdminChat: Pending call data set - SDP type: ${event.sdpType}', tag: 'CALL');

    // Auto-select the conversation
    final conv = _conversations.firstWhere(
      (c) => _parseConvId(c['id']) == event.conversationId,
      orElse: () => <String, dynamic>{},
    );

    if (conv.isNotEmpty && mounted) {
      _log.info('AdminChat: Auto-selecting conversation ${event.conversationId}', tag: 'CALL');
      await _selectConversation(conv);
    } else {
      _log.warning('AdminChat: Conversation ${event.conversationId} not found in list', tag: 'CALL');
    }

    // CRITICAL FIX: Inform VoiceCallService about incoming call BEFORE accepting
    // This sets the call state to ringing, which is required for acceptCall() to work
    _log.info('AdminChat: Informing VoiceCallService about incoming call...', tag: 'CALL');
    _voiceCallService.handleIncomingCall(
      event.conversationId,
      event.callerId,
      event.callerName,
      event.sdp,
      event.sdpType,
    );

    // Wait a tiny bit for state to update
    await Future.delayed(const Duration(milliseconds: 100));

    // Accept the call
    if (mounted) {
      _log.info('AdminChat: Auto-accepting pending call', tag: 'CALL');
      _acceptCall();
    }
  }

  @override
  void dispose() {
    _isDisposed = true; // Set flag FIRST to prevent any setState calls

    // Mark chat dialog as closed - re-enable notifications
    NotificationService.setChatDialogOpen(false);

    _networkPollTimer?.cancel();
    _typingTimer?.cancel();
    _refreshTimer?.cancel();
    _callDurationTimer?.cancel();
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _connectionSubscription?.cancel();
    _callOfferSubscription?.cancel();
    _callAnswerSubscription?.cancel();
    _callRejectedSubscription?.cancel();
    _callBusySubscription?.cancel();
    _callEndedSubscription?.cancel();
    _iceCandidateSubscription?.cancel();
    _readReceiptSubscription?.cancel();
    _callStateSubscription?.cancel();
    _onlineUsersSubscription?.cancel();
    _remoteStreamSubscription?.cancel();
    _iceConnectionStateSubscription?.cancel();
    _endCallCleanup();
    // Don't leave conversation - dashboard maintains the subscription for background notifications
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      _safeSetState(() => _isLoadingConversations = true);
    }

    try {
      final result = await _apiService.getChatConversations(widget.mitgliedernummer);

      if (result['success'] == true && mounted) {
        _safeSetState(() {
          _conversations = List<Map<String, dynamic>>.from(result['conversations'] ?? []);
          _stats = result['stats'];
          _isLoadingConversations = false;
        });
        // Sync muted conversations with ChatService for notification suppression
        _chatService.syncMutedConversations(_conversations);
      }
    } catch (e) {
      if (mounted && !silent) {
        _safeSetState(() => _isLoadingConversations = false);
      }
    }
  }

  // ── Network Status Polling ──
  void _startNetworkPolling(String? mitgliedernummer) {
    _networkPollTimer?.cancel();
    if (mitgliedernummer == null || mitgliedernummer.isEmpty) return;
    // Fetch immediately
    _fetchNetworkStatus(mitgliedernummer);
    // Then every 15 seconds
    _networkPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _fetchNetworkStatus(mitgliedernummer);
    });
  }

  Future<void> _fetchNetworkStatus(String mitgliedernummer) async {
    try {
      final result = await _apiService.getMemberNetworkStatus(mitgliedernummer);
      if (mounted && !_isDisposed) {
        _safeSetState(() {
          _memberConnectionType = result['connection_type']?.toString();
          _memberLatencyMs = int.tryParse(result['latency_ms']?.toString() ?? '');
          _memberNetworkQuality = result['network_quality']?.toString();
          _memberBatteryLevel = int.tryParse(result['battery_level']?.toString() ?? '');
          _memberBatteryState = result['battery_state']?.toString();
        });
      }
    } catch (_) {}
  }

  Widget _buildNetworkStatusBar() {
    final type = _memberConnectionType;
    final latency = _memberLatencyMs;
    final quality = _memberNetworkQuality;

    if (type == null && latency == null && quality == null) return const SizedBox.shrink();

    // Determine icon, color, label
    IconData icon;
    Color color;
    String label;
    String qualityLabel;

    if (type == null || type.isEmpty || type == 'none') {
      icon = Icons.signal_cellular_off;
      color = Colors.grey;
      label = 'Kein Netz';
      qualityLabel = 'Offline';
    } else {
      icon = type.toLowerCase().contains('wifi') ? Icons.wifi : Icons.signal_cellular_alt;
      final typeLabel = type.toLowerCase().contains('wifi') ? 'WiFi' : 'Mobile';

      if (quality == 'good' || (latency != null && latency < 100)) {
        color = Colors.green;
        qualityLabel = 'Gut';
      } else if (quality == 'medium' || (latency != null && latency < 300)) {
        color = Colors.orange;
        qualityLabel = 'Mittel';
      } else {
        color = Colors.red;
        qualityLabel = 'Schlecht';
      }
      label = typeLabel;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border(top: BorderSide(color: color.withValues(alpha: 0.3))),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          if (latency != null) ...[
            const SizedBox(width: 6),
            Text('|', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            const SizedBox(width: 6),
            Text('${latency}ms', style: TextStyle(fontSize: 11, color: color)),
          ],
          const SizedBox(width: 6),
          Text('|', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          const SizedBox(width: 6),
          Text(
            quality == 'good' ? '✅' : (quality == 'medium' ? '⚠️' : (type == null || type.isEmpty || type == 'none' ? '📵' : '❌')),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(width: 4),
          Text(qualityLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
          // Battery info
          if (_memberBatteryLevel != null && _memberBatteryLevel! >= 0) ...[
            const SizedBox(width: 8),
            Text('|', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            const SizedBox(width: 6),
            Icon(
              _memberBatteryState == 'charging' || _memberBatteryState == 'full'
                  ? Icons.battery_charging_full
                  : _memberBatteryLevel! <= 15
                      ? Icons.battery_alert
                      : _memberBatteryLevel! <= 50
                          ? Icons.battery_3_bar
                          : Icons.battery_full,
              size: 14,
              color: _memberBatteryLevel! <= 15
                  ? Colors.red
                  : _memberBatteryLevel! <= 30
                      ? Colors.orange
                      : Colors.green,
            ),
            const SizedBox(width: 3),
            Text(
              '$_memberBatteryLevel%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _memberBatteryLevel! <= 15
                    ? Colors.red
                    : _memberBatteryLevel! <= 30
                        ? Colors.orange
                        : Colors.green,
              ),
            ),
            if (_memberBatteryState == 'charging') ...[
              const SizedBox(width: 2),
              const Text('⚡', style: TextStyle(fontSize: 10)),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _selectConversation(Map<String, dynamic> conversation) async {
    if (!mounted) return;

    if (_selectedConversation != null) {
      _chatService.leaveConversation(_parseConvId(_selectedConversation!['id']));
    }

    if (!mounted) return;
    _safeSetState(() {
      _selectedConversation = conversation;
      _isLoadingMessages = true;
      _messages = [];
    });

    // Start network status polling for this member
    _startNetworkPolling(conversation['mitgliedernummer']?.toString());

    try {
      final result = await _apiService.getChatMessages(
        _parseConvId(conversation['id']),
        widget.mitgliedernummer,
      );

      if (!mounted) return;
      if (result['success'] == true) {
        // API returns messages in data.messages (with translation support)
        final data = result['data'] as Map<String, dynamic>? ?? result;
        final newMessages = List<Map<String, dynamic>>.from(data['messages'] ?? result['messages'] ?? []);

        _safeSetState(() {
          // Get existing message IDs to prevent duplicates
          final existingIds = _messages.map((m) => m['id']).toSet();

          // Only add messages that don't already exist
          for (var msg in newMessages) {
            if (!existingIds.contains(msg['id'])) {
              _messages.add(msg);
            }
          }

          // If no existing messages, just use the new list
          if (existingIds.isEmpty) {
            _messages = newMessages;
          }

          _isLoadingMessages = false;
        });
        _scrollToBottom();

        if (_isConnected && mounted) {
          _chatService.joinConversation(_parseConvId(conversation['id']));
        }
      }
    } catch (e) {
      if (mounted) {
        _safeSetState(() => _isLoadingMessages = false);
      }
    }
  }

  Future<void> _connectWebSocket() async {
    // Chat listeners
    _messageSubscription = _chatService.messageStream.listen((message) {
      if (!mounted) return;
      if (_selectedConversation != null &&
          message.conversationId == _parseConvId(_selectedConversation!['id'])) {
        // CRITICAL: Check if message already exists FIRST (prevent duplicates)
        // Check by ID first, then by content+sender+timestamp (for WebSocket broadcasts)
        final messageExists = _messages.any((m) {
          // Check by ID (most reliable)
          if (m['id'] == message.id) return true;

          // Check by content+sender (for our own messages sent via API then broadcasted via WS)
          // WebSocket may assign different ID than API
          final isSameContent = m['message'] == message.message;
          final isSameSender = m['sender_name'] == message.senderName;
          final createdAt = DateTime.tryParse(m['created_at'] ?? '');
          final timeDiff = createdAt != null ? message.createdAt.difference(createdAt).abs() : Duration(hours: 1);
          final isSameTime = timeDiff.inSeconds < 5; // Within 5 seconds

          return isSameContent && isSameSender && isSameTime;
        });

        if (messageExists) {
          _log.debug('Chat: Skipping duplicate message (id: ${message.id}, sender: ${message.senderName})', tag: 'CHAT');
          return;
        }

        if (!mounted) return;
        final isOwn = message.senderId == _chatService.currentUserId || message.senderName == widget.userName;
        _safeSetState(() {
          _messages.add({
            'id': message.id,
            'message': message.message,
            'sender_id': message.senderId,
            'sender_name': message.senderName,
            'sender_role': message.senderRole,
            'is_own': isOwn,
            'created_at': message.createdAt.toIso8601String(),
          });
        });
        if (mounted) _scrollToBottom();

        // Fetch translated version from API for messages from other users
        if (!isOwn && _selectedConversation != null) {
          Future.delayed(const Duration(milliseconds: 500), () async {
            if (!mounted) return;
            try {
              final convId = _parseConvId(_selectedConversation!['id']);
              final result = await _apiService.getChatMessages(convId, widget.mitgliedernummer, lastMessageId: message.id - 1);
              if (!mounted) return;
              if (result['success'] == true) {
                final data = result['data'] as Map<String, dynamic>? ?? result;
                final translated = List<Map<String, dynamic>>.from(data['messages'] ?? result['messages'] ?? []);
                for (final tm in translated) {
                  if (tm['id'] == message.id && tm['is_translated'] == true) {
                    _safeSetState(() {
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
      if (mounted) {
        _loadConversations(silent: true);
      }
    });

    _typingSubscription = _chatService.typingStream.listen((event) {
      if (mounted) {
        _safeSetState(() => _typingUser = event.userName);
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) _safeSetState(() => _typingUser = null);
        });
      }
    });

    _connectionSubscription = _chatService.connectionStream.listen((connected) {
      if (mounted) {
        _safeSetState(() => _isConnected = connected);
      }
    });

    // Voice call listeners - incoming calls
    _callOfferSubscription = _chatService.callOfferStream.listen((event) {
      _log.info('AdminChat: [WS] Received call_offer from ${event.callerName} (conv: ${event.conversationId})', tag: 'CALL');
      if (!mounted) return;
      _handleIncomingCall(event);
    });

    // Voice call listeners - outgoing calls (admin initiates)
    _callAnswerSubscription = _chatService.callAnswerStream.listen((event) {
      _log.info('AdminChat: [WS] Received call_answer from ${event.answererName} (conv: ${event.conversationId})', tag: 'CALL');
      if (!mounted) return;
      if (_selectedConversation != null &&
          _parseConvId(_selectedConversation!['id']) == event.conversationId) {
        _handleCallAnswer(event.sdp, event.sdpType, event.answererName);
      } else {
        _log.warning('AdminChat: call_answer ignored - selectedConv mismatch', tag: 'CALL');
      }
    });

    _callRejectedSubscription = _chatService.callRejectedStream.listen((event) {
      _log.info('AdminChat: [WS] Received call_rejected (conv: ${event.conversationId}, reason: ${event.reason})', tag: 'CALL');
      if (!mounted) return;
      if (_selectedConversation != null &&
          _parseConvId(_selectedConversation!['id']) == event.conversationId) {
        _handleCallRejected(event.reason);
      }
    });

    _callBusySubscription = _chatService.callBusyStream.listen((convId) {
      _log.info('AdminChat: [WS] Received call_busy (conv: $convId)', tag: 'CALL');
      if (!mounted) return;
      if (_selectedConversation != null &&
          _parseConvId(_selectedConversation!['id']) == convId) {
        _showError('Der Benutzer ist bereits in einem anderen Anruf');
        _endCallCleanup();
      }
    });

    _callEndedSubscription = _chatService.callEndedStream.listen((event) {
      _log.info('AdminChat: [WS] Received call_ended (conv: ${event.conversationId})', tag: 'CALL');
      if (!mounted) return;
      if (_incomingCallConvId == event.conversationId ||
          (_selectedConversation != null &&
           _parseConvId(_selectedConversation!['id']) == event.conversationId)) {
        _handleCallEnded();
      }
    });

    _iceCandidateSubscription = _chatService.iceCandidateStream.listen((event) {
      _log.debug('AdminChat: [WS] Received ice_candidate (conv: ${event.conversationId})', tag: 'CALL');
      if (!mounted) return;
      if (_selectedConversation != null &&
          _parseConvId(_selectedConversation!['id']) == event.conversationId) {
        _handleIceCandidate(event.candidate, event.sdpMid, event.sdpMLineIndex);
      }
    });

    // Read receipt listener
    _readReceiptSubscription = _chatService.readReceiptStream.listen((event) {
      if (!mounted) return;
      if (_selectedConversation != null &&
          _parseConvId(_selectedConversation!['id']) == event.conversationId) {
        _safeSetState(() {
          for (final msgId in event.messageIds) {
            final msgIndex = _messages.indexWhere((m) => m['id'] == msgId);
            if (msgIndex >= 0) {
              _messages[msgIndex]['status'] = event.status;
              if (event.status == 'read') {
                _messages[msgIndex]['read_at'] = event.timestamp.toIso8601String();
              } else if (event.status == 'delivered') {
                _messages[msgIndex]['delivered_at'] = event.timestamp.toIso8601String();
              }
            }
          }
        });
      }
    });

    // Online users listener - update conversation list UI when users go online/offline
    _onlineUsersSubscription = _chatService.onlineUsersStream.listen((onlineUsers) {
      if (!mounted) return;
      _log.debug('AdminChat: Online users updated (${onlineUsers.length} online)', tag: 'WS');
      _safeSetState(() {}); // Trigger UI rebuild to update green dots
    });

    if (!mounted) return;
    final connected = await _chatService.connect(widget.mitgliedernummer, userName: widget.userName);
    if (mounted) {
      _safeSetState(() => _isConnected = connected);
    }
  }

  // ==================== Voice Call Methods ====================

  /// Start a call to the member (admin initiates) - REFACTORED to use VoiceCallService
  Future<void> _startCall() async {
    _log.info('AdminChat: _startCall() initiated (using VoiceCallService)', tag: 'CALL');
    if (_selectedConversation == null || _voiceCallService.callState != CallState.idle) {
      _log.warning('AdminChat: _startCall() aborted - conv: $_selectedConversation, status: ${_voiceCallService.callState}', tag: 'CALL');
      return;
    }
    if (!mounted) return;

    final convId = _parseConvId(_selectedConversation!['id']);
    final memberName = _selectedConversation!['member_name'] ?? 'Benutzer';
    final memberNumber = _selectedConversation!['mitgliedernummer'] ?? '';

    _log.info('AdminChat: Starting call to $memberName (conv: $convId)', tag: 'CALL');

    try {
      _safeSetState(() {
        _callerName = memberName;
        _incomingCallConvId = convId;
      });

      // Use VoiceCallService to start the call
      final success = await _voiceCallService.startCall(convId, memberNumber, memberName);

      if (!success) {
        throw Exception('Failed to start call via VoiceCallService');
      }

      _log.info('AdminChat: Call started successfully via VoiceCallService', tag: 'CALL');

      if (mounted) {
        _startCallDurationTimer();
      }

    } catch (e) {
      _log.error('AdminChat: _startCall() error: $e', tag: 'CALL');
      if (e.toString().contains('NO_MICROPHONE')) {
        _showError('Kein Mikrofon gefunden. Bitte schließen Sie ein Mikrofon an und versuchen Sie es erneut.');
      } else {
        _showError('Fehler beim Starten des Anrufs: $e');
      }
      await _voiceCallService.endCall();
    }
  }

  /// Handle answer from member when admin initiated the call - REFACTORED to use VoiceCallService
  Future<void> _handleCallAnswer(String sdp, String sdpType, String answererName) async {
    _log.info('AdminChat: _handleCallAnswer() from $answererName, sdpType: $sdpType (using VoiceCallService)', tag: 'CALL');

    try {
      _callerName = answererName;
      await _voiceCallService.handleCallAnswer(sdp, sdpType);
      _log.info('AdminChat: Call answer handled successfully via VoiceCallService', tag: 'CALL');
      if (mounted) {
        _startCallDurationTimer();
      }
    } catch (e) {
      _log.error('AdminChat: _handleCallAnswer() error: $e', tag: 'CALL');
      _showError('Fehler beim Verbinden: $e');
      _endCallCleanup();
    }
  }

  /// Handle rejection from member - REFACTORED to use VoiceCallService
  void _handleCallRejected(String reason) {
    _log.info('AdminChat: _handleCallRejected() reason: $reason (using VoiceCallService)', tag: 'CALL');
    String message;
    switch (reason) {
      case 'busy':
        message = 'Der Benutzer ist beschäftigt';
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

  /// Handle incoming call - Uses VoiceCallService for call state management
  void _handleIncomingCall(CallOfferEvent event) {
    _log.info('AdminChat: _handleIncomingCall() from ${event.callerName} (conv: ${event.conversationId})', tag: 'CALL');
    if (!mounted) {
      _log.warning('AdminChat: _handleIncomingCall() - not mounted', tag: 'CALL');
      return;
    }

    if (_voiceCallService.callState != CallState.idle) {
      // Check if this is a duplicate offer for the SAME conversation
      if (_incomingCallConvId == event.conversationId) {
        _log.warning('AdminChat: Duplicate call_offer for same conversation (${event.conversationId}) - ignoring (state: ${_voiceCallService.callState})', tag: 'CALL');
        return; // Ignore duplicate, DON'T send reject
      }

      // Different call, we're busy
      _log.warning('AdminChat: Already in call (${_voiceCallService.callState}), auto-rejecting with busy', tag: 'CALL');
      _chatService.sendCallReject(event.conversationId, 'busy');
      return;
    }

    _incomingCallConvId = event.conversationId;
    _callerName = event.callerName;
    _pendingSdp = event.sdp;
    _pendingSdpType = event.sdpType;
    _log.debug('AdminChat: Incoming call data set - SDP type: ${event.sdpType}', tag: 'CALL');

    // Also inform VoiceCallService about the incoming call
    _voiceCallService.handleIncomingCall(
      event.conversationId,
      event.callerId,
      event.callerName,
      event.sdp,
      event.sdpType,
    );

    _log.info('AdminChat: Showing incoming call dialog...', tag: 'CALL');

    // Show incoming call dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => IncomingCallDialog(
        callerName: event.callerName,
        onAccept: () {
          _log.info('AdminChat: User pressed ACCEPT in dialog', tag: 'CALL');
          Navigator.of(ctx).pop();
          if (mounted) _acceptCall();
        },
        onReject: () {
          _log.info('AdminChat: User pressed REJECT in dialog', tag: 'CALL');
          Navigator.of(ctx).pop();
          if (mounted) _rejectCall();
        },
      ),
    );
  }

  /// Accept incoming call - REFACTORED to use VoiceCallService
  Future<void> _acceptCall() async {
    _log.info('AdminChat: _acceptCall() - convId: $_incomingCallConvId, hasSdp: ${_pendingSdp != null} (using VoiceCallService)', tag: 'CALL');
    if (_pendingSdp == null || _incomingCallConvId == null || !mounted) {
      _log.warning('AdminChat: _acceptCall() aborted - missing data or not mounted', tag: 'CALL');
      return;
    }

    try {
      // Use VoiceCallService to accept the call
      final success = await _voiceCallService.acceptCall(_pendingSdp!, _pendingSdpType!);

      if (!success) {
        throw Exception('Failed to accept call via VoiceCallService');
      }

      _log.info('AdminChat: Call accepted successfully via VoiceCallService', tag: 'CALL');

      if (mounted) {
        _startCallDurationTimer();
      }

      // Auto-select the conversation if not selected
      if (mounted && (_selectedConversation == null ||
          _parseConvId(_selectedConversation!['id']) != _incomingCallConvId)) {
        _log.info('AdminChat: Auto-selecting conversation $_incomingCallConvId', tag: 'CALL');
        final conv = _conversations.firstWhere(
          (c) => _parseConvId(c['id']) == _incomingCallConvId,
          orElse: () => <String, dynamic>{},
        );
        if (conv.isNotEmpty && mounted) {
          _selectConversation(conv);
        }
      }

    } catch (e) {
      _log.error('AdminChat: _acceptCall() error: $e', tag: 'CALL');
      if (e.toString().contains('NO_MICROPHONE')) {
        _showError('Kein Mikrofon gefunden. Bitte schließen Sie ein Mikrofon an und versuchen Sie es erneut.');
      } else {
        _showError('Fehler beim Annehmen: $e');
      }
      await _voiceCallService.endCall();
    }
  }

  /// Reject incoming call - REFACTORED to use VoiceCallService
  void _rejectCall() {
    _log.info('AdminChat: _rejectCall() - convId: $_incomingCallConvId (using VoiceCallService)', tag: 'CALL');
    _voiceCallService.rejectCall();
    _endCallCleanup();
  }

  /// Handle call ended by remote peer - REFACTORED to use VoiceCallService
  void _handleCallEnded() {
    _log.info('AdminChat: _handleCallEnded() received (using VoiceCallService)', tag: 'CALL');
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

  /// Handle ICE candidate from remote peer - REFACTORED to use VoiceCallService
  Future<void> _handleIceCandidate(String candidate, String sdpMid, int sdpMLineIndex) async {
    if (!mounted) return;
    _log.debug('AdminChat: Handling ICE candidate via VoiceCallService', tag: 'CALL');
    await _voiceCallService.handleIceCandidate(candidate, sdpMid, sdpMLineIndex);
  }

  /// End the current call - REFACTORED to use VoiceCallService
  void _endCall() {
    _log.info('AdminChat: _endCall() (using VoiceCallService)', tag: 'CALL');
    _voiceCallService.endCall();
    _endCallCleanup();
  }

  /// Cleanup local UI state after call ends - WebRTC cleanup now handled by VoiceCallService
  void _endCallCleanup() {
    _log.info('AdminChat: _endCallCleanup() - cleaning up UI state', tag: 'CALL');
    _callDurationTimer?.cancel();
    _pendingSdp = null;
    _pendingSdpType = null;
    _incomingCallConvId = null;
    if (mounted) {
      _safeSetState(() {
        _callDuration = Duration.zero;
        _callerName = '';
      });
    }
    _log.debug('AdminChat: Call cleanup completed', tag: 'CALL');
  }

  /// Toggle mute - REFACTORED to use VoiceCallService
  void _toggleMute() {
    if (!mounted) return;
    _voiceCallService.toggleMute();
    if (mounted) {
      _safeSetState(() {}); // Trigger UI update
    }
  }

  void _toggleSpeaker() {
    if (!mounted) return;
    _voiceCallService.toggleSpeaker();
    if (mounted) {
      _safeSetState(() {}); // Trigger UI update
    }
  }

  void _startCallDurationTimer() {
    if (!mounted) return;
    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _safeSetState(() => _callDuration += const Duration(seconds: 1));
      }
    });
  }

  // ==================== File Upload Methods ====================

  Future<void> _pickFiles() async {
    if (_selectedConversation == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'txt'],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        // Check max 10 files
        if (result.files.length > 10) {
          _showError('Maximal 10 Dateien erlaubt');
          return;
        }

        // Check total size (100MB)
        int totalSize = 0;
        for (final file in result.files) {
          totalSize += file.size;
        }
        if (totalSize > 100 * 1024 * 1024) {
          _showError('Maximale Gesamtgröße: 100 MB');
          return;
        }

        _selectedFiles = result.files.map((f) => File(f.path!)).toList();
        await _uploadFiles();
      }
    } catch (e) {
      _showError('Fehler beim Auswählen: $e');
    }
  }

  Future<void> _uploadFiles() async {
    if (_selectedFiles.isEmpty || _selectedConversation == null) return;
    if (!mounted) return;

    _safeSetState(() => _isUploading = true);

    try {
      final result = await _apiService.uploadChatAttachments(
        conversationId: _parseConvId(_selectedConversation!['id']),
        mitgliedernummer: widget.mitgliedernummer,
        files: _selectedFiles,
        message: _messageController.text.trim(),
      );

      if (result['success'] == true && mounted) {
        _messageController.clear();
        _selectedFiles = [];

        // Add message to list
        _safeSetState(() {
          _messages.add({
            'id': result['message_id'],
            'message': result['message'] ?? '[Dateien]',
            'sender_name': widget.userName,
            'sender_role': 'vorsitzer',
            'is_own': true,
            'status': 'sent',
            'created_at': result['created_at'] ?? DateTime.now().toIso8601String(),
            'attachments': result['attachments'] ?? [],
          });
        });
        _scrollToBottom();

        // Broadcast via WebSocket
        if (_isConnected) {
          _chatService.sendMessage(
            _parseConvId(_selectedConversation!['id']),
            result['message'] ?? '[Dateien]',
          );
        }
      } else {
        _showError(result['message'] ?? 'Upload fehlgeschlagen');
      }
    } catch (e) {
      _showError('Upload Fehler: $e');
    } finally {
      if (mounted) {
        _safeSetState(() {
          _isUploading = false;
          _selectedFiles = [];
        });
      }
    }
  }

  Future<void> _downloadAttachment(Map<String, dynamic> attachment) async {
    try {
      final result = await _apiService.downloadChatAttachment(
        attachmentId: attachment['id'],
        mitgliedernummer: widget.mitgliedernummer,
      );

      if (result['success'] != true) {
        _showError(result['message'] ?? 'Download fehlgeschlagen');
        return;
      }

      final fileName = result['filename']?.toString() ?? 'file';

      // Two server response shapes:
      //   1. Inline base64 in `content` (small files, <= 5 MB)
      //   2. `download_url` to chat/stream.php (large files)
      Uint8List? bytes;
      if (result['content'] != null) {
        bytes = base64Decode(result['content']);
      } else if (result['download_url'] != null) {
        bytes = await _apiService.fetchBytesAuthenticated(result['download_url']);
        if (bytes == null) {
          _showError('Download fehlgeschlagen (Streaming-Endpoint nicht erreichbar)');
          return;
        }
      } else {
        _showError('Server hat keine Datei zurückgegeben');
        return;
      }

      await _openAttachmentBytes(bytes, fileName);
    } catch (e) {
      _showError('Download Fehler: $e');
    }
  }

  /// Open an in-memory attachment without ever touching the disk for images
  /// and PDFs (the two formats we can render natively). Other formats fall
  /// back to writing the bytes to the system temp dir and asking the OS to
  /// open them — there is no in-app viewer for arbitrary file types.
  Future<void> _openAttachmentBytes(Uint8List bytes, String fileName) async {
    final ext = fileName.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
    final isPdf = ext == 'pdf';

    if (isImage && mounted) {
      _showInMemoryImageDialog(bytes, fileName);
      return;
    }

    if (isPdf && mounted) {
      // FileViewerDialog supports `fileBytes:` and renders the PDF directly
      // from RAM via PdfViewer.data — no disk write needed, which is critical
      // for unsigned macOS builds where Documents/Caches are restricted.
      showDialog(
        context: context,
        builder: (_) => FileViewerDialog(fileBytes: bytes, fileName: fileName),
      );
      return;
    }

    // Fallback for non-renderable formats: write to temp dir and ask the OS
    // to open it. This is the only path that requires disk access.
    try {
      final filePath = await _writeBytesToWritableDir(bytes, fileName);
      await OpenFilex.open(filePath);
    } catch (e) {
      _showError('Datei konnte nicht geöffnet werden: $e');
    }
  }

  /// Persist [bytes] to a writable on-disk location and return the absolute
  /// path. Tries the system temp dir first, falls back to ApplicationSupport
  /// (always writable for the current user) and finally Documents.
  ///
  /// On macOS without code-signing, `getTemporaryDirectory()` returns
  /// `~/Library/Caches/<bundle-id>/` which may not exist yet — we create the
  /// parent recursively to avoid PathNotFoundException.
  ///
  /// The filename is also sanitized: path separators and reserved characters
  /// are replaced with `_` so we never accidentally try to write into a
  /// non-existent subdirectory.
  Future<String> _writeBytesToWritableDir(Uint8List bytes, String rawName) async {
    final safeName = _sanitizeFilename(rawName);

    // Try in order: temp → application support → documents.
    final candidates = <Future<Directory> Function()>[
      getTemporaryDirectory,
      getApplicationSupportDirectory,
      getApplicationDocumentsDirectory,
    ];

    Object? lastError;
    for (final getDir in candidates) {
      try {
        final dir = await getDir();
        // Make sure the directory actually exists (path_provider does NOT
        // guarantee this for all platforms, e.g. unsigned macOS Caches).
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final filePath = '${dir.path}${Platform.pathSeparator}$safeName';
        await File(filePath).writeAsBytes(bytes, flush: true);
        return filePath;
      } catch (e) {
        lastError = e;
        // try next candidate
      }
    }
    throw lastError ?? Exception('Kein beschreibbares Verzeichnis gefunden');
  }

  /// Strip path separators and characters that are illegal on common
  /// filesystems so we never end up with a sub-path the OS would have to
  /// resolve. Empty result falls back to a generic name.
  String _sanitizeFilename(String name) {
    var s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    // Disallow leading dots (hidden files on unix) — keep extension though.
    s = s.replaceFirst(RegExp(r'^\.+'), '');
    if (s.isEmpty) s = 'attachment';
    return s;
  }

  /// In-memory image viewer (Image.memory + InteractiveViewer + zoom/rotate
  /// controls). The Save button still writes the file to a temp location
  /// because OpenFilex needs a path; for the *primary* view path we never
  /// touch the disk.
  void _showInMemoryImageDialog(Uint8List bytes, String fileName) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (imgCtx) {
        final transformController = TransformationController();
        int rotation = 0; // 0, 90, 180, 270
        return StatefulBuilder(
          builder: (imgCtx, setImgState) => Dialog(
            insetPadding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.image, size: 18, color: Colors.blue.shade300),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fileName,
                          style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.zoom_out, size: 20, color: Colors.white70),
                        tooltip: 'Verkleinern',
                        onPressed: () {
                          final scale = transformController.value.getMaxScaleOnAxis();
                          if (scale > 0.5) {
                            transformController.value = Matrix4.diagonal3Values(scale * 0.75, scale * 0.75, 1.0);
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.fit_screen, size: 20, color: Colors.white70),
                        tooltip: 'Zurücksetzen',
                        onPressed: () => transformController.value = Matrix4.identity(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.zoom_in, size: 20, color: Colors.white70),
                        tooltip: 'Vergrößern',
                        onPressed: () {
                          final scale = transformController.value.getMaxScaleOnAxis();
                          if (scale < 5.0) {
                            transformController.value = Matrix4.diagonal3Values(scale * 1.5, scale * 1.5, 1.0);
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.rotate_right, size: 20, color: Colors.white70),
                        tooltip: 'Drehen (90°)',
                        onPressed: () => setImgState(() => rotation = (rotation + 90) % 360),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.save_alt, size: 20, color: Colors.white70),
                        tooltip: 'Speichern',
                        // The Save button is the only path that touches disk: it
                        // writes the bytes to the system temp dir and asks the OS
                        // to open the saved copy (NSWorkspace / xdg-open / etc.).
                        onPressed: () async {
                          try {
                            final filePath = await _writeBytesToWritableDir(bytes, fileName);
                            await OpenFilex.open(filePath);
                          } catch (e) {
                            _showError('Speichern fehlgeschlagen: $e');
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: Colors.white),
                        tooltip: 'Schließen',
                        onPressed: () => Navigator.pop(imgCtx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: Colors.black87,
                    child: ClipRect(
                      child: InteractiveViewer(
                        transformationController: transformController,
                        constrained: false,
                        minScale: 0.3,
                        maxScale: 5.0,
                        boundaryMargin: const EdgeInsets.all(double.infinity),
                        child: Transform.rotate(
                          angle: rotation * 3.14159265 / 180,
                          child: Image.memory(bytes),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Mark all unread messages as read when user focuses on input
  Future<void> _markMessagesAsRead() async {
    if (_selectedConversation == null) return;

    final convId = _parseConvId(_selectedConversation!['id']);

    // Find unread messages from others
    final unreadIds = _messages
        .where((m) => m['is_own'] != true && m['status'] != 'read')
        .map((m) => m['id'] as int)
        .toList();

    if (unreadIds.isEmpty) return;

    try {
      final result = await _apiService.markMessagesRead(
        conversationId: convId,
        mitgliedernummer: widget.mitgliedernummer,
        status: 'read',
        messageIds: unreadIds,
      );

      if (result['success'] == true && mounted) {
        // Update local state
        _safeSetState(() {
          for (var msg in _messages) {
            if (unreadIds.contains(msg['id'])) {
              msg['status'] = 'read';
              msg['is_read'] = true;
            }
          }
        });

        // Broadcast via WebSocket
        if (_isConnected) {
          _chatService.sendReadReceipt(convId, unreadIds, 'read');
        }
      }
    } catch (e) {
      debugPrint('AdminChat: Mark read error: $e');
    }
  }

  // ==================== Chat Methods ====================

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _selectedConversation == null || _isSending) return;
    if (!mounted) return;

    _safeSetState(() => _isSending = true);
    _messageController.clear();

    try {
      final result = await _apiService.sendChatMessage(
        _parseConvId(_selectedConversation!['id']),
        widget.mitgliedernummer,
        message,
        urgent: _isUrgent,  // 🆕 Send urgent flag
      );

      if (result['success'] == true && mounted) {
        final messageId = result['message_id'];

        _safeSetState(() {
          _messages.add({
            'id': messageId,
            'message': message,
            'sender_name': widget.userName,
            'sender_role': 'vorsitzer',
            'is_own': true,
            'is_urgent': _isUrgent,  // 🆕 Store urgent flag
            'created_at': result['created_at'] ?? DateTime.now().toIso8601String(),
          });
          _isUrgent = false;  // 🆕 Reset urgent flag after sending
        });
        _scrollToBottom();

        // IMPORTANT: Send via WebSocket to broadcast to other users
        // Our duplicate check in messageStream listener will prevent it from showing twice locally
        if (_isConnected) {
          _chatService.sendMessage(_parseConvId(_selectedConversation!['id']), message);
          _log.debug('Chat: Message sent via API (id: $messageId) and broadcasted via WebSocket', tag: 'CHAT');
        }
      } else {
        _messageController.text = message;
        _showError(result['message'] ?? 'Fehler beim Senden');
      }
    } catch (e) {
      _messageController.text = message;
      _showError('Fehler: $e');
    } finally {
      if (mounted) _safeSetState(() => _isSending = false);
    }
  }

  Future<void> _closeConversation() async {
    if (_selectedConversation == null) return;
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konversation schließen'),
        content: const Text('Möchten Sie diese Konversation wirklich schließen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final result = await _apiService.closeChatConversation(
        _parseConvId(_selectedConversation!['id']),
        widget.mitgliedernummer,
      );

      if (result['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konversation geschlossen'),
            backgroundColor: Colors.green,
          ),
        );
        _safeSetState(() {
          _selectedConversation = null;
          _messages = [];
        });
        _loadConversations();
      }
    } catch (e) {
      _showError('Fehler: $e');
    }
  }

  void _showMuteOptions() {
    if (_selectedConversation == null || !mounted) return;
    final isMuted = _selectedConversation!['is_muted'] == true;

    if (isMuted) {
      // Already muted → unmute directly
      _muteConversation('unmute');
      return;
    }

    // Show duration picker
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stummschalten'),
        content: const Text('Wie lange soll diese Konversation stummgeschaltet werden?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _muteConversation('8h');
            },
            child: const Text('8 Stunden'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _muteConversation('1w');
            },
            child: const Text('1 Woche'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _muteConversation('forever');
            },
            child: const Text('Immer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
  }

  Future<void> _muteConversation(String duration) async {
    if (_selectedConversation == null) return;
    final convId = _parseConvId(_selectedConversation!['id']);

    try {
      final result = await _apiService.muteConversation(
        convId,
        widget.mitgliedernummer,
        duration,
      );

      if (result['success'] == true && mounted) {
        final isMuted = result['is_muted'] == true;

        // Update local state
        _safeSetState(() {
          _selectedConversation!['is_muted'] = isMuted;
          _selectedConversation!['muted_until'] = result['muted_until'];

          // Also update in the conversations list
          for (var i = 0; i < _conversations.length; i++) {
            if (_parseConvId(_conversations[i]['id']) == convId) {
              _conversations[i]['is_muted'] = isMuted;
              _conversations[i]['muted_until'] = result['muted_until'];
              break;
            }
          }
        });

        // Sync with ChatService for notification suppression
        if (isMuted) {
          _chatService.muteConversation(convId);
        } else {
          _chatService.unmuteConversation(convId);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isMuted ? 'Konversation stummgeschaltet' : 'Stummschaltung aufgehoben'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      _showError('Fehler: $e');
    }
  }

  void _scrollToBottom() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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

  // Show dialog to start a new conversation with a member
  void _showStartConversationDialog() async {
    // Load all users
    final result = await _apiService.getUsers();
    if (result['success'] != true || !mounted) return;

    final users = List<Map<String, dynamic>>.from(result['users'] ?? []);
    // Filter to show only members (not admins)
    final members = users.where((u) {
      final role = u['role']?.toString().toLowerCase() ?? '';
      return role == 'mitglied' || role == 'member';
    }).toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_comment, color: Colors.green),
            SizedBox(width: 8),
            Text('Neue Konversation'),
          ],
        ),
        content: SizedBox(
          width: 350,
          height: 400,
          child: members.isEmpty
              ? const Center(child: Text('Keine Mitglieder gefunden'))
              : ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final memberNr = member['mitgliedernummer']?.toString() ?? '';
                    final name = member['name']?.toString() ?? 'Unbekannt';
                    final isOnline = _chatService.isUserOnline(memberNr);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isOnline ? Colors.green : Colors.grey.shade300,
                        child: Icon(
                          Icons.person,
                          color: isOnline ? Colors.white : Colors.grey.shade600,
                        ),
                      ),
                      title: Text(name),
                      subtitle: Text(memberNr),
                      trailing: isOnline
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Online',
                                style: TextStyle(color: Colors.green, fontSize: 11),
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        _startConversationWithMember(memberNr, name);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
  }

  // Start a conversation with a specific member
  Future<void> _startConversationWithMember(String memberMitgliedernummer, String memberName) async {
    try {
      final result = await _apiService.adminStartChat(
        widget.mitgliedernummer,
        memberMitgliedernummer,
      );

      if (result['success'] == true && mounted) {
        // Reload conversations to get the new one
        await _loadConversations();

        // Find and select the new conversation
        final convId = result['conversation_id'];
        if (convId != null) {
          final newConv = _conversations.firstWhere(
            (c) => _parseConvId(c['id']) == convId,
            orElse: () => <String, dynamic>{},
          );
          if (newConv.isNotEmpty) {
            _selectConversation(newConv);
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Konversation mit $memberName gestartet'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (mounted) {
        _showError(result['message'] ?? 'Fehler beim Starten der Konversation');
      }
    } catch (e) {
      _showError('Fehler: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SeasonalBackground(
        child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildHeader(),
            const Divider(),

            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 250,
                    child: _buildConversationList(),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _selectedConversation == null
                        ? _buildNoConversationSelected()
                        : _buildChatArea(),
                  ),
                ],
              ),
            ),

            // In-call overlay - moved to bottom (above footer)
            if (_voiceCallService.callState == CallState.inCall) _buildInCallOverlay(),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.support_agent, color: Color(0xFF1a1a2e), size: 28),
        const SizedBox(width: 12),
        const Text(
          'Live Chat - Support',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        if (_stats != null) ...[
          StatBadge(label: 'Offen', count: _stats!['open'] ?? 0, color: Colors.orange),
          const SizedBox(width: 8),
          StatBadge(label: 'Gesamt', count: _stats!['total'] ?? 0, color: Colors.blue),
          const SizedBox(width: 16),
        ],
        ConnectionStatus(isConnected: _isConnected),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.add_comment, color: Colors.green),
          onPressed: _showStartConversationDialog,
          tooltip: 'Neue Konversation starten',
        ),
        IconButton(
          icon: Badge(
            isLabelVisible: _statusMessage != null,
            backgroundColor: Colors.red,
            smallSize: 8,
            child: Icon(
              Icons.campaign,
              color: _statusMessage != null ? Colors.red : Colors.grey,
            ),
          ),
          onPressed: _showStatusMessageSettings,
          tooltip: 'Statusnachricht verwalten',
        ),
        IconButton(
          icon: Icon(Icons.edit_calendar, color: Colors.teal.shade600),
          onPressed: _showScheduledMessagesDialog,
          tooltip: 'Nachrichten verwalten',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _loadConversations(),
          tooltip: 'Aktualisieren',
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (_voiceCallService.callState != CallState.idle) {
              _endCall();
            }
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  Widget _buildInCallOverlay() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InCallOverlay(
        remoteName: _callerName,
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

  Widget _buildConversationList() {
    if (_isLoadingConversations) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Keine Konversationen',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _conversations.length,
      itemBuilder: (context, index) {
        final conv = _conversations[index];
        final isSelected = _selectedConversation != null &&
            _parseConvId(_selectedConversation!['id']) == _parseConvId(conv['id']);
        final hasActiveCall = _incomingCallConvId == _parseConvId(conv['id']) &&
            _voiceCallService.callState != CallState.idle;

        // Check if member is actually online via WebSocket
        final memberNumber = conv['mitgliedernummer']?.toString() ?? '';
        final isOnline = _chatService.isUserOnline(memberNumber);

        return ConversationListItem(
          conversation: conv,
          isSelected: isSelected,
          hasActiveCall: hasActiveCall,
          isOnline: isOnline,
          isMuted: conv['is_muted'] == true,
          onTap: () => _selectConversation(conv),
        );
      },
    );
  }

  Widget _buildNoConversationSelected() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Wählen Sie eine Konversation',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  // ============= ADMIN STATUS MESSAGE (RED BANNER) =============

  Future<void> _loadAdminStatus() async {
    try {
      final result = await _apiService.getAdminStatusMessage();
      if (mounted && result['success'] == true) {
        _safeSetState(() {
          final data = result['data'];
          _statusMessage = (data != null && data['is_active'] == true)
              ? data['message'] as String?
              : null;
        });
      }
    } catch (e) {
      // Silently ignore - banner is optional
    }
  }

  Widget _buildStatusBanner() {
    if (_statusMessage == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage!,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white, size: 18),
            onPressed: _showStatusMessageSettings,
            tooltip: 'Bearbeiten',
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            onPressed: () async {
              final result = await _apiService.clearAdminStatusMessage();
              if (result['success'] == true && mounted) {
                _safeSetState(() => _statusMessage = null);
              }
            },
            tooltip: 'Entfernen',
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }

  Future<void> _showStatusMessageSettings() async {
    final controller = TextEditingController(text: _statusMessage ?? '');

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
            const SizedBox(width: 8),
            const Text('Statusnachricht'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Nachricht',
              hintText: 'z.B. Notfallintervention - Bin derzeit nicht erreichbar',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          if (_statusMessage != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, '__clear__'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Entfernen'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Speichern', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;

    if (result == '__clear__') {
      final apiResult = await _apiService.clearAdminStatusMessage();
      if (apiResult['success'] == true && mounted) {
        _safeSetState(() => _statusMessage = null);
      }
    } else if (result.trim().isNotEmpty) {
      final apiResult = await _apiService.setAdminStatusMessage(result.trim());
      if (apiResult['success'] == true && mounted) {
        _safeSetState(() => _statusMessage = result.trim());
      }
    }
  }

  // ============= SCHEDULED MESSAGES =============

  Future<void> _showScheduledMessagesDialog() async {
    List<Map<String, dynamic>> messages = [];
    bool isLoading = true;

    Future<void> loadMessages(StateSetter setDialogState) async {
      final result = await _apiService.getScheduledMessages();
      if (result['success'] == true) {
        messages = List<Map<String, dynamic>>.from(result['data'] ?? []);
      }
      setDialogState(() => isLoading = false);
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (isLoading) {
            loadMessages(setDialogState);
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.schedule_send, color: Colors.teal.shade600),
                const SizedBox(width: 8),
                const Text('Automatische Nachrichten', style: TextStyle(fontSize: 16)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.green),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _showAddScheduledMessageDialog();
                    if (mounted) _showScheduledMessagesDialog();
                  },
                  tooltip: 'Neue Nachricht',
                ),
              ],
            ),
            content: SizedBox(
              width: 550,
              height: 400,
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.schedule, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text('Keine automatischen Nachrichten', style: TextStyle(color: Colors.grey.shade500)),
                              const SizedBox(height: 8),
                              Text('Erstellen Sie Erinnerungen für Mahlzeiten, Medikamente, etc.', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: messages.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final m = messages[i];
                            final time = (m['send_time'] as String? ?? '').substring(0, 5);
                            final isActive = m['is_active'] == true;
                            final category = m['category'] as String? ?? 'mahlzeit';
                            final daysStr = m['days_of_week'] as String? ?? '1,2,3,4,5,6,7';

                            IconData catIcon;
                            Color catColor;
                            switch (category) {
                              case 'fruehstueck':
                                catIcon = Icons.free_breakfast;
                                catColor = Colors.orange;
                                break;
                              case 'mittagessen':
                                catIcon = Icons.lunch_dining;
                                catColor = Colors.green;
                                break;
                              case 'abendessen':
                                catIcon = Icons.dinner_dining;
                                catColor = Colors.indigo;
                                break;
                              case 'medikament':
                                catIcon = Icons.medication;
                                catColor = Colors.red;
                                break;
                              default:
                                catIcon = Icons.restaurant;
                                catColor = Colors.teal;
                            }

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: catColor.withValues(alpha: 0.15),
                                child: Icon(catIcon, color: catColor, size: 20),
                              ),
                              title: Text(m['message'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                              subtitle: Row(
                                children: [
                                  Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Text(time, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 8),
                                  Text(_formatDays(daysStr), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: isActive,
                                    activeTrackColor: Colors.green.shade200,
                                    activeThumbColor: Colors.green,
                                    onChanged: (val) async {
                                      await _apiService.updateScheduledMessage(id: m['id'], isActive: val);
                                      setDialogState(() {
                                        messages[i]['is_active'] = val;
                                        isLoading = false;
                                      });
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.edit, size: 18, color: Colors.blue.shade400),
                                    onPressed: () async {
                                      Navigator.pop(ctx);
                                      await _showEditScheduledMessageDialog(m);
                                      if (mounted) _showScheduledMessagesDialog();
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: ctx,
                                        builder: (c) => AlertDialog(
                                          title: const Text('Nachricht löschen?'),
                                          content: Text('„${m['message']}" wird gelöscht.'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
                                            TextButton(
                                              onPressed: () => Navigator.pop(c, true),
                                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                                              child: const Text('Löschen'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await _apiService.deleteScheduledMessage(m['id']);
                                        setDialogState(() {
                                          messages.removeAt(i);
                                          isLoading = false;
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Schließen'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDays(String daysStr) {
    final dayNames = {'1': 'Mo', '2': 'Di', '3': 'Mi', '4': 'Do', '5': 'Fr', '6': 'Sa', '7': 'So'};
    final days = daysStr.split(',').map((d) => d.trim()).toList();
    if (days.length == 7) return 'Täglich';
    if (days.join(',') == '1,2,3,4,5') return 'Mo-Fr';
    if (days.join(',') == '6,7') return 'Sa-So';
    return days.map((d) => dayNames[d] ?? d).join(', ');
  }

  Future<void> _showAddScheduledMessageDialog() async {
    final messageController = TextEditingController();
    TimeOfDay selectedTime = const TimeOfDay(hour: 8, minute: 0);
    String selectedCategory = 'mahlzeit';
    Set<int> selectedDays = {1, 2, 3, 4, 5, 6, 7};

    final categories = [
      {'value': 'fruehstueck', 'label': 'Frühstück', 'icon': Icons.free_breakfast},
      {'value': 'mittagessen', 'label': 'Mittagessen', 'icon': Icons.lunch_dining},
      {'value': 'abendessen', 'label': 'Abendessen', 'icon': Icons.dinner_dining},
      {'value': 'medikament', 'label': 'Medikament', 'icon': Icons.medication},
      {'value': 'mahlzeit', 'label': 'Sonstiges', 'icon': Icons.restaurant},
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.add_circle, color: Colors.green.shade600),
              const SizedBox(width: 8),
              const Text('Neue automatische Nachricht', style: TextStyle(fontSize: 15)),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category
                Text('Kategorie', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: categories.map((cat) {
                    final isSelected = selectedCategory == cat['value'];
                    return ChoiceChip(
                      avatar: Icon(cat['icon'] as IconData, size: 16),
                      label: Text(cat['label'] as String, style: const TextStyle(fontSize: 12)),
                      selected: isSelected,
                      onSelected: (_) => setDialogState(() => selectedCategory = cat['value'] as String),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                // Time
                Row(
                  children: [
                    Text('Uhrzeit: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text('${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}'),
                      onPressed: () async {
                        final picked = await showTimePicker(context: ctx, initialTime: selectedTime);
                        if (picked != null) setDialogState(() => selectedTime = picked);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Days of week
                Text('Wochentage', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final entry in {'1': 'Mo', '2': 'Di', '3': 'Mi', '4': 'Do', '5': 'Fr', '6': 'Sa', '7': 'So'}.entries)
                      FilterChip(
                        label: Text(entry.value, style: const TextStyle(fontSize: 11)),
                        selected: selectedDays.contains(int.parse(entry.key)),
                        onSelected: (val) => setDialogState(() {
                          if (val) {
                            selectedDays.add(int.parse(entry.key));
                          } else {
                            selectedDays.remove(int.parse(entry.key));
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // Message
                TextField(
                  controller: messageController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Nachricht',
                    hintText: 'z.B. Guten Morgen! Haben Sie Ihr Frühstück eingenommen?',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton.icon(
              icon: const Icon(Icons.save, size: 16),
              label: const Text('Speichern'),
              onPressed: () async {
                final msg = messageController.text.trim();
                if (msg.isEmpty || selectedDays.isEmpty) return;
                final timeStr = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}:00';
                final daysStr = (selectedDays.toList()..sort()).join(',');
                await _apiService.createScheduledMessage(
                  sendTime: timeStr,
                  message: msg,
                  category: selectedCategory,
                  daysOfWeek: daysStr,
                  createdBy: widget.mitgliedernummer,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
    messageController.dispose();
  }

  Future<void> _showEditScheduledMessageDialog(Map<String, dynamic> msg) async {
    final messageController = TextEditingController(text: msg['message'] ?? '');
    final timeStr = (msg['send_time'] as String? ?? '08:00').substring(0, 5);
    final timeParts = timeStr.split(':');
    TimeOfDay selectedTime = TimeOfDay(hour: int.tryParse(timeParts[0]) ?? 8, minute: int.tryParse(timeParts[1]) ?? 0);
    String selectedCategory = msg['category'] ?? 'mahlzeit';
    final daysStr = msg['days_of_week'] as String? ?? '1,2,3,4,5,6,7';
    Set<int> selectedDays = daysStr.split(',').map((d) => int.tryParse(d.trim()) ?? 0).where((d) => d > 0).toSet();

    final categories = [
      {'value': 'fruehstueck', 'label': 'Frühstück', 'icon': Icons.free_breakfast},
      {'value': 'mittagessen', 'label': 'Mittagessen', 'icon': Icons.lunch_dining},
      {'value': 'abendessen', 'label': 'Abendessen', 'icon': Icons.dinner_dining},
      {'value': 'medikament', 'label': 'Medikament', 'icon': Icons.medication},
      {'value': 'mahlzeit', 'label': 'Sonstiges', 'icon': Icons.restaurant},
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.edit, color: Colors.blue.shade600),
              const SizedBox(width: 8),
              const Text('Nachricht bearbeiten', style: TextStyle(fontSize: 15)),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kategorie', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: categories.map((cat) {
                    final isSelected = selectedCategory == cat['value'];
                    return ChoiceChip(
                      avatar: Icon(cat['icon'] as IconData, size: 16),
                      label: Text(cat['label'] as String, style: const TextStyle(fontSize: 12)),
                      selected: isSelected,
                      onSelected: (_) => setDialogState(() => selectedCategory = cat['value'] as String),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Uhrzeit: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text('${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}'),
                      onPressed: () async {
                        final picked = await showTimePicker(context: ctx, initialTime: selectedTime);
                        if (picked != null) setDialogState(() => selectedTime = picked);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Wochentage', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final entry in {'1': 'Mo', '2': 'Di', '3': 'Mi', '4': 'Do', '5': 'Fr', '6': 'Sa', '7': 'So'}.entries)
                      FilterChip(
                        label: Text(entry.value, style: const TextStyle(fontSize: 11)),
                        selected: selectedDays.contains(int.parse(entry.key)),
                        onSelected: (val) => setDialogState(() {
                          if (val) {
                            selectedDays.add(int.parse(entry.key));
                          } else {
                            selectedDays.remove(int.parse(entry.key));
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: messageController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Nachricht',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton.icon(
              icon: const Icon(Icons.save, size: 16),
              label: const Text('Speichern'),
              onPressed: () async {
                final text = messageController.text.trim();
                if (text.isEmpty || selectedDays.isEmpty) return;
                final newTimeStr = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}:00';
                final newDaysStr = (selectedDays.toList()..sort()).join(',');
                await _apiService.updateScheduledMessage(
                  id: msg['id'],
                  sendTime: newTimeStr,
                  message: text,
                  category: selectedCategory,
                  daysOfWeek: newDaysStr,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
    messageController.dispose();
  }

  Future<void> _showConversationScheduledDialog(Map<String, dynamic> conversation) async {
    final conversationId = conversation['id'] as int;
    final memberName = conversation['member_name'] ?? 'Unbekannt';

    // Load data BEFORE showing dialog
    List<Map<String, dynamic>> messages = [];
    final result = await _apiService.getConversationScheduled(conversationId);
    if (result['success'] == true) {
      messages = List<Map<String, dynamic>>.from(result['data'] ?? []);
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.schedule_send, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Automatische Nachrichten', style: TextStyle(fontSize: 15)),
                      Text(memberName, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 450,
              height: 400,
              child: messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.schedule_send, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text('Keine automatischen Nachrichten vorhanden', style: TextStyle(color: Colors.grey.shade500)),
                              const SizedBox(height: 8),
                              Text('Erstellen Sie zuerst Nachrichten über das Hauptmenü', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: messages.length,
                          itemBuilder: (_, i) {
                            final m = messages[i];
                            final category = m['category'] ?? 'mahlzeit';
                            final time = (m['send_time'] ?? '').toString();
                            final timeShort = time.length >= 5 ? time.substring(0, 5) : time;
                            final daysStr = m['days_of_week'] ?? '1,2,3,4,5,6,7';
                            final isEnabled = m['is_enabled'] == true;

                            IconData catIcon;
                            Color catColor;
                            switch (category) {
                              case 'fruehstueck':
                                catIcon = Icons.free_breakfast;
                                catColor = Colors.orange;
                                break;
                              case 'mittagessen':
                                catIcon = Icons.lunch_dining;
                                catColor = Colors.green;
                                break;
                              case 'abendessen':
                                catIcon = Icons.dinner_dining;
                                catColor = Colors.indigo;
                                break;
                              case 'medikament':
                                catIcon = Icons.medication;
                                catColor = Colors.red;
                                break;
                              default:
                                catIcon = Icons.restaurant;
                                catColor = Colors.teal;
                            }

                            return Card(
                              elevation: isEnabled ? 2 : 0,
                              color: isEnabled ? null : Colors.grey.shade50,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: catColor.withValues(alpha: isEnabled ? 0.15 : 0.06),
                                  child: Icon(catIcon, color: isEnabled ? catColor : Colors.grey, size: 20),
                                ),
                                title: Text(
                                  m['message'] ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isEnabled ? null : Colors.grey,
                                  ),
                                ),
                                subtitle: Row(
                                  children: [
                                    Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(timeShort, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 8),
                                    Text(_formatDays(daysStr), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                  ],
                                ),
                                trailing: Switch(
                                  value: isEnabled,
                                  activeTrackColor: Colors.green.shade200,
                                  activeThumbColor: Colors.green,
                                  onChanged: (val) async {
                                    await _apiService.toggleConversationScheduled(conversationId, m['id'], val);
                                    setDialogState(() {
                                      messages[i]['is_enabled'] = val;
                                    });
                                  },
                                ),
                              ),
                            );
                          },
                        ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Schließen'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChatArea() {
    final isOpen = _selectedConversation!['status'] == 'open';
    final canCall = _voiceCallService.callState == CallState.idle && _isConnected;

    return Column(
      children: [
        ConversationHeader(
          conversation: _selectedConversation!,
          canCall: canCall,
          isOpen: isOpen,
          isMuted: _selectedConversation!['is_muted'] == true,
          onCall: _startCall,
          onClose: _closeConversation,
          onMuteToggle: _showMuteOptions,
          onScheduledSettings: () => _showConversationScheduledDialog(_selectedConversation!),
        ),
        const SizedBox(height: 8),

        // Red status banner (admin unavailability)
        _buildStatusBanner(),

        Expanded(
          child: _isLoadingMessages
              ? const Center(child: CircularProgressIndicator())
              : _buildMessagesList(),
        ),

        if (_typingUser != null)
          TypingIndicator(userName: _typingUser!),

        // Network status bar
        if (_selectedConversation != null)
          _buildNetworkStatusBar(),

        if (isOpen)
          ChatInputArea(
            controller: _messageController,
            isSending: _isSending,
            isUploading: _isUploading,
            onSend: _sendMessage,
            onPickFiles: _pickFiles,
            onFocus: _markMessagesAsRead,
            hintText: 'Antwort eingeben...',
            // 🆕 URGENT checkbox for admin
            showUrgentCheckbox: true,
            isUrgent: _isUrgent,
            onUrgentChanged: (value) => _safeSetState(() => _isUrgent = value),
          )
        else
          const ClosedConversationIndicator(),
      ],
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'Keine Nachrichten',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SeasonalBackground(paintBehind: true, child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            final msg = _messages[index];
            final isOwn = msg['is_own'] == true;
            return ChatMessageBubble(
              message: msg,
              isOwn: isOwn,
              onDownloadAttachment: _downloadAttachment,
            );
          },
        )),
      ),
    );
  }

}
