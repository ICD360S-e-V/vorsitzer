import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'notification_service.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// ChatService handles WebSocket connection for real-time chat and voice calls
class ChatService {
  static const String wsUrl = 'wss://icd360sev.icd360s.de/wss/';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;

  // Auto-reconnect logic
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _shouldReconnect = false;
  String? _storedMitgliedernummer;
  String? _storedUserName;
  static const int _maxReconnectAttempts = 10;
  static const Duration _initialReconnectDelay = Duration(seconds: 2);
  static const Duration _maxReconnectDelay = Duration(seconds: 60);

  // Stream controllers for chat events
  final _messageController = StreamController<ChatMessage>.broadcast();
  final _typingController = StreamController<TypingEvent>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  // Stream controllers for call events
  final _callOfferController = StreamController<CallOfferEvent>.broadcast();
  final _callAnswerController = StreamController<CallAnswerEvent>.broadcast();
  final _callRejectedController = StreamController<CallRejectedEvent>.broadcast();
  final _callEndedController = StreamController<CallEndedEvent>.broadcast();
  final _iceCandidateController = StreamController<IceCandidateEvent>.broadcast();
  final _callBusyController = StreamController<int>.broadcast();
  final _loginApprovalController = StreamController<Map<String, dynamic>>.broadcast();

  // Stream controller for read receipts
  final _readReceiptController = StreamController<ReadReceiptEvent>.broadcast();

  // Stream controller for new device login notifications
  final _newDeviceLoginController = StreamController<NewDeviceLoginEvent>.broadcast();

  // Stream controller for online users tracking
  final _onlineUsersController = StreamController<Set<String>>.broadcast();

  // Stream controller for ticket notifications
  final _ticketNotificationController = StreamController<TicketNotificationEvent>.broadcast();

  // Set to track online users by mitgliedernummer
  final Set<String> _onlineUsers = {};

  // Set to track muted conversation IDs (suppress notifications)
  final Set<int> _mutedConversations = {};

  // Store current logged-in user's name and ID to filter out our own messages from notifications
  String? _currentUserName;
  int? _currentUserId;

  int? get currentUserId => _currentUserId;

  // Public streams - Chat
  Stream<ChatMessage> get messageStream => _messageController.stream;
  Stream<TypingEvent> get typingStream => _typingController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get errorStream => _errorController.stream;

  // Public stream - Online Users
  Stream<Set<String>> get onlineUsersStream => _onlineUsersController.stream;

  // Public streams - Voice Call
  Stream<CallOfferEvent> get callOfferStream => _callOfferController.stream;
  Stream<CallAnswerEvent> get callAnswerStream => _callAnswerController.stream;
  Stream<CallRejectedEvent> get callRejectedStream => _callRejectedController.stream;
  Stream<CallEndedEvent> get callEndedStream => _callEndedController.stream;
  Stream<IceCandidateEvent> get iceCandidateStream => _iceCandidateController.stream;
  Stream<int> get callBusyStream => _callBusyController.stream;
  Stream<Map<String, dynamic>> get loginApprovalStream => _loginApprovalController.stream;

  // Public stream - Read Receipts
  Stream<ReadReceiptEvent> get readReceiptStream => _readReceiptController.stream;

  // Public stream - New Device Login
  Stream<NewDeviceLoginEvent> get newDeviceLoginStream => _newDeviceLoginController.stream;

  // Public stream - Ticket Notifications
  Stream<TicketNotificationEvent> get ticketNotificationStream => _ticketNotificationController.stream;

  bool get isConnected => _isConnected;

  /// Check if a user is currently online
  bool isUserOnline(String mitgliedernummer) {
    return _onlineUsers.contains(mitgliedernummer);
  }

  /// Get the set of currently online users
  Set<String> get onlineUsers => Set.from(_onlineUsers);

  /// Mark a conversation as muted (suppress notifications)
  void muteConversation(int conversationId) {
    _mutedConversations.add(conversationId);
  }

  /// Unmute a conversation (restore notifications)
  void unmuteConversation(int conversationId) {
    _mutedConversations.remove(conversationId);
  }

  /// Check if a conversation is muted
  bool isConversationMuted(int conversationId) {
    return _mutedConversations.contains(conversationId);
  }

  /// Sync muted conversations from loaded conversation list
  void syncMutedConversations(List<Map<String, dynamic>> conversations) {
    _mutedConversations.clear();
    for (final conv in conversations) {
      if (conv['is_muted'] == true) {
        final id = conv['id'];
        if (id is int) {
          _mutedConversations.add(id);
        } else if (id != null) {
          _mutedConversations.add(int.tryParse(id.toString()) ?? 0);
        }
      }
    }
  }

  // Singleton
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  /// Connect to WebSocket server and authenticate
  Future<bool> connect(String mitgliedernummer, {String? userName}) async {
    _log.info('WebSocket connect($mitgliedernummer) called', tag: 'WS');

    // Store credentials for auto-reconnect
    _storedMitgliedernummer = mitgliedernummer;
    _storedUserName = userName;
    _shouldReconnect = true;

    // Store current user name for notification filtering
    if (userName != null) {
      _currentUserName = userName;
      _log.debug('Stored current user name: $_currentUserName', tag: 'WS');
    }

    if (_isConnected) {
      _log.info('Already connected, returning true', tag: 'WS');
      return true;
    }

    try {
      _log.info('Connecting to $wsUrl...', tag: 'WS');

      // Connect using IOWebSocketChannel with default SSL validation.
      // Note: WebSocket.connect() uses the system's default SSL certificate
      // validation, which is already secure. Certificate pinning for REST calls
      // is handled at the HttpClient level via HttpClientFactory. Pinning
      // WebSocket would require global HttpOverrides, which could interfere
      // with other HTTP connections. The system SSL validation provides
      // adequate protection for the WebSocket connection.
      // ignore: close_sinks - managed by IOWebSocketChannel
      final webSocket = await WebSocket.connect(
        wsUrl,
      );
      _channel = IOWebSocketChannel(webSocket);

      final completer = Completer<bool>();

      _subscription = _channel!.stream.listen(
        (data) {
          _log.debug('WS received: ${data.toString().substring(0, data.toString().length > 100 ? 100 : data.toString().length)}...', tag: 'WS');
          _handleMessage(data, completer);
        },
        onError: (error) {
          _log.error('WS error: $error', tag: 'WS');
          _isConnected = false;
          _connectionController.add(false);
          _errorController.add('Connection error: $error');
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          // Auto-reconnect on error
          _scheduleReconnect();
        },
        onDone: () {
          _log.warning('WS connection closed', tag: 'WS');
          _isConnected = false;
          _connectionController.add(false);
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          // Auto-reconnect when connection is closed
          _scheduleReconnect();
        },
      );

      // Send authentication message
      _log.info('Sending auth for $mitgliedernummer', tag: 'WS');
      _send({
        'type': 'auth',
        'mitgliedernummer': mitgliedernummer,
      });

      // Wait for auth response with timeout
      final result = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _log.error('Connection timeout after 10s', tag: 'WS');
          _errorController.add('Connection timeout');
          return false;
        },
      );
      _log.info('Connect result: $result', tag: 'WS');
      return result;
    } catch (e) {
      _log.error('Connect failed: $e', tag: 'WS');
      _errorController.add('Failed to connect: $e');
      return false;
    }
  }

  /// Disconnect from WebSocket server
  void disconnect() {
    _log.info('Manual disconnect called', tag: 'WS');

    // Disable auto-reconnect for manual disconnect
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _connectionController.add(false);
  }

  /// Schedule a reconnection attempt with exponential backoff
  void _scheduleReconnect() {
    if (!_shouldReconnect) {
      _log.info('Auto-reconnect disabled, skipping', tag: 'WS-RECONNECT');
      return;
    }

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _log.error('Max reconnect attempts reached ($_maxReconnectAttempts), giving up', tag: 'WS-RECONNECT');
      _shouldReconnect = false;
      return;
    }

    // Cancel any existing reconnect timer
    _reconnectTimer?.cancel();

    // Calculate delay with exponential backoff: 2s, 4s, 8s, 16s, 32s, 60s (max)
    final delaySeconds = (_initialReconnectDelay.inSeconds * (1 << _reconnectAttempts))
        .clamp(0, _maxReconnectDelay.inSeconds);
    final delay = Duration(seconds: delaySeconds);

    _reconnectAttempts++;
    _log.info('Scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s', tag: 'WS-RECONNECT');

    _reconnectTimer = Timer(delay, () {
      _reconnect();
    });
  }

  /// Attempt to reconnect to WebSocket
  Future<void> _reconnect() async {
    if (!_shouldReconnect || _storedMitgliedernummer == null) {
      _log.warning('Cannot reconnect: shouldReconnect=$_shouldReconnect, hasCreds=${_storedMitgliedernummer != null}', tag: 'WS-RECONNECT');
      return;
    }

    _log.info('Attempting reconnect (attempt $_reconnectAttempts)...', tag: 'WS-RECONNECT');

    // Clean up old connection
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;

    // Attempt to reconnect
    final success = await connect(_storedMitgliedernummer!, userName: _storedUserName);

    if (success) {
      _log.info('Reconnection successful!', tag: 'WS-RECONNECT');
      _reconnectAttempts = 0;
    } else {
      _log.warning('Reconnection failed, will retry...', tag: 'WS-RECONNECT');
      // _scheduleReconnect() is already called in connect() on failure
    }
  }

  /// Join a conversation room
  void joinConversation(int conversationId) {
    _log.info('Joining conversation $conversationId', tag: 'WS');
    _send({
      'type': 'join',
      'conversation_id': conversationId,
    });
  }

  /// Leave a conversation room
  void leaveConversation(int conversationId) {
    _send({
      'type': 'leave',
      'conversation_id': conversationId,
    });
  }

  /// Send a chat message
  void sendMessage(int conversationId, String message) {
    _send({
      'type': 'message',
      'conversation_id': conversationId,
      'message': message,
    });
  }

  /// Send typing indicator
  void sendTyping(int conversationId) {
    _send({
      'type': 'typing',
      'conversation_id': conversationId,
    });
  }

  // ==================== Voice Call Methods ====================

  /// Send call offer (initiate call)
  void sendCallOffer(int conversationId, String sdp, String sdpType) {
    _send({
      'type': 'call_offer',
      'conversation_id': conversationId,
      'sdp': sdp,
      'sdp_type': sdpType,
    });
  }

  /// Send call answer (accept call)
  void sendCallAnswer(int conversationId, String sdp, String sdpType) {
    _send({
      'type': 'call_answer',
      'conversation_id': conversationId,
      'sdp': sdp,
      'sdp_type': sdpType,
    });
  }

  /// Send call rejection
  void sendCallReject(int conversationId, String reason) {
    _send({
      'type': 'call_reject',
      'conversation_id': conversationId,
      'reason': reason,
    });
  }

  /// Send call end
  void sendCallEnd(int conversationId) {
    _send({
      'type': 'call_end',
      'conversation_id': conversationId,
    });
  }

  /// Send ICE candidate
  void sendIceCandidate(int conversationId, String candidate, String sdpMid, int sdpMLineIndex) {
    _send({
      'type': 'ice_candidate',
      'conversation_id': conversationId,
      'candidate': candidate,
      'sdp_mid': sdpMid,
      'sdp_mline_index': sdpMLineIndex,
    });
  }

  /// Send read receipt (mark messages as delivered or read)
  void sendReadReceipt(int conversationId, List<int> messageIds, String status) {
    _send({
      'type': 'read_receipt',
      'conversation_id': conversationId,
      'message_ids': messageIds,
      'status': status, // 'delivered' or 'read'
    });
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void _handleMessage(dynamic data, [Completer<bool>? authCompleter]) {
    try {
      final json = jsonDecode(data);
      final type = json['type'];

      // DEBUG: Log ALL incoming WebSocket messages
      _log.debug('WS received type: $type', tag: 'WS-DEBUG');

      switch (type) {
        case 'auth_success':
          _isConnected = true;
          _reconnectAttempts = 0; // Reset reconnect attempts on successful connection
          _currentUserId = json['user_id'] as int?;
          _connectionController.add(true);
          // Parse initial online users list if provided
          if (json['online_users'] != null) {
            final List<dynamic> onlineList = json['online_users'];
            _onlineUsers.clear();
            for (var user in onlineList) {
              _onlineUsers.add(user.toString());
            }
            _onlineUsersController.add(Set.from(_onlineUsers));
            _log.info('Loaded ${_onlineUsers.length} online users on connect', tag: 'WS');
          }
          authCompleter?.complete(true);
          break;

        case 'auth_error':
          _isConnected = false;
          _errorController.add(json['error'] ?? 'Authentication failed');
          authCompleter?.complete(false);
          break;

        case 'joined':
          // Successfully joined conversation
          break;

        case 'new_message':
          final chatMsg = ChatMessage.fromJson(json);
          _messageController.add(chatMsg);

          // DEBUG: Log all message details for notification debugging
          _log.info('NEW_MESSAGE received: sender="${chatMsg.senderName}", isAdmin=${chatMsg.isAdmin}, role="${chatMsg.senderRole}", currentUser="$_currentUserName"', tag: 'NOTIF');

          // DON'T show notification for our own messages
          // Vorsitzer Portal: show notifications from ALL users (members AND admins)
          // Only skip own messages and muted conversations
          final isOwnMessage = (_currentUserId != null && chatMsg.senderId == _currentUserId) ||
              (_currentUserName != null && chatMsg.senderName == _currentUserName);

          _log.debug('Notification check: isOwnMessage=$isOwnMessage, isAdmin=${chatMsg.isAdmin}, sender="${chatMsg.senderName}"', tag: 'NOTIF');

          // Check if conversation is muted
          final isMuted = _mutedConversations.contains(chatMsg.conversationId);

          if (!isOwnMessage && !isMuted) {
            // Message from anyone else → show notification
            _log.info('TRIGGERING notification for: ${chatMsg.senderName} (isAdmin=${chatMsg.isAdmin})', tag: 'NOTIF');
            NotificationService().showChatMessage(
              senderName: chatMsg.senderName,
              message: chatMsg.message,
              conversationId: chatMsg.conversationId,
            );
          } else if (isMuted && !isOwnMessage) {
            _log.debug('SKIPPED notification - conversation muted (from: ${chatMsg.senderName})', tag: 'NOTIF');
          } else {
            _log.debug('SKIPPED notification - own message (from: ${chatMsg.senderName})', tag: 'NOTIF');
          }
          break;

        case 'typing':
          _typingController.add(TypingEvent(
            userName: json['user_name'] ?? '',
            isAdmin: json['is_admin'] ?? false,
          ));
          break;

        case 'new_device_login':
          final newDeviceEvent = NewDeviceLoginEvent.fromJson(json);
          _newDeviceLoginController.add(newDeviceEvent);
          // Show native notification
          NotificationService().show(
            title: 'Neue Anmeldung erkannt',
            body: '${newDeviceEvent.deviceName} • ${newDeviceEvent.ipAddress}',
          );
          break;

        case 'system_notification':
          final ticketEvent = TicketNotificationEvent.fromJson(json);
          _ticketNotificationController.add(ticketEvent);
          // Show native notification
          NotificationService().show(
            title: ticketEvent.title,
            body: ticketEvent.message,
          );
          _log.info('System notification received: ${ticketEvent.title}', tag: 'TICKET');
          break;

        case 'ticket_notification':
          final ticketEvent = TicketNotificationEvent.fromJson(json);
          _ticketNotificationController.add(ticketEvent);
          // Show native notification
          NotificationService().show(
            title: ticketEvent.title,
            body: ticketEvent.message,
          );
          _log.info('Ticket notification received: ${ticketEvent.title}', tag: 'TICKET');
          break;

        case 'online_users':
          // Full list of online users (periodic update from server)
          if (json['users'] != null) {
            final List<dynamic> onlineList = json['users'];
            _onlineUsers.clear();
            for (var user in onlineList) {
              _onlineUsers.add(user.toString());
            }
            _onlineUsersController.add(Set.from(_onlineUsers));
            _log.debug('Online users sync: ${_onlineUsers.length} online', tag: 'WS');
          }
          break;

        case 'user_joined':
          final joinedUser = json['mitgliedernummer']?.toString();
          if (joinedUser != null) {
            _onlineUsers.add(joinedUser);
            _onlineUsersController.add(Set.from(_onlineUsers));
            _log.debug('User joined: $joinedUser (total online: ${_onlineUsers.length})', tag: 'WS');
          }
          break;

        case 'user_left':
        case 'user_disconnected':
          final leftUser = json['mitgliedernummer']?.toString();
          if (leftUser != null) {
            _onlineUsers.remove(leftUser);
            _onlineUsersController.add(Set.from(_onlineUsers));
            _log.debug('User left: $leftUser (total online: ${_onlineUsers.length})', tag: 'WS');
          }
          break;

        // Voice call events
        case 'call_offer':
          final callEvent = CallOfferEvent(
            conversationId: json['conversation_id'] ?? 0,
            callerId: json['caller_id']?.toString() ?? '',
            callerName: json['caller_name'] ?? '',
            sdp: json['sdp'] ?? '',
            sdpType: json['sdp_type'] ?? 'offer',
          );
          _callOfferController.add(callEvent);
          // Show notification for incoming call
          NotificationService().showIncomingCall(
            callerName: callEvent.callerName,
            conversationId: callEvent.conversationId,
          );
          break;

        case 'call_answer':
          _callAnswerController.add(CallAnswerEvent(
            conversationId: json['conversation_id'] ?? 0,
            answererId: json['answerer_id']?.toString() ?? '',
            answererName: json['answerer_name'] ?? '',
            sdp: json['sdp'] ?? '',
            sdpType: json['sdp_type'] ?? 'answer',
          ));
          break;

        case 'call_rejected':
          _callRejectedController.add(CallRejectedEvent(
            conversationId: json['conversation_id'] ?? 0,
            rejectedBy: json['rejected_by'] ?? '',
            reason: json['reason'] ?? 'rejected',
          ));
          break;

        case 'call_ended':
          _callEndedController.add(CallEndedEvent(
            conversationId: json['conversation_id'] ?? 0,
            endedBy: json['ended_by'] ?? '',
            reason: json['reason'],
          ));
          break;

        case 'ice_candidate':
          _iceCandidateController.add(IceCandidateEvent(
            conversationId: json['conversation_id'] ?? 0,
            candidate: json['candidate'] ?? '',
            sdpMid: json['sdp_mid'] ?? '',
            sdpMLineIndex: json['sdp_mline_index'] ?? 0,
          ));
          break;

        case 'call_busy':
          _callBusyController.add(json['conversation_id'] ?? 0);
          break;

        case 'read_receipt':
          _readReceiptController.add(ReadReceiptEvent.fromJson(json));
          break;

        case 'error':
          _errorController.add(json['error'] ?? 'Unknown error');
          break;

        case 'login_approval_request':
          _loginApprovalController.add(json);
          break;

        default:
          _log.warning('UNKNOWN WS message type: $type', tag: 'WS-UNKNOWN');
          break;
      }
    } catch (e) {
      _errorController.add('Failed to parse message: $e');
    }
  }

  /// Clean up resources
  void dispose() {
    disconnect();
    _messageController.close();
    _typingController.close();
    _connectionController.close();
    _errorController.close();
    _callOfferController.close();
    _callAnswerController.close();
    _callRejectedController.close();
    _callEndedController.close();
    _iceCandidateController.close();
    _callBusyController.close();
    _loginApprovalController.close();
    _readReceiptController.close();
    _onlineUsersController.close();
    _newDeviceLoginController.close();
    _ticketNotificationController.close();
  }
}

/// Chat message model
class ChatMessage {
  final int id;
  final int conversationId;
  final int senderId;
  final String senderName;
  final String senderRole;
  final bool isAdmin;
  final String message;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.isAdmin,
    required this.message,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['message_id'] ?? 0,
      conversationId: json['conversation_id'] ?? 0,
      senderId: json['sender_id'] ?? 0,
      senderName: json['sender_name'] ?? '',
      senderRole: json['sender_role'] ?? '',
      isAdmin: json['is_admin'] ?? false,
      message: json['message'] ?? '',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

/// Typing event model
class TypingEvent {
  final String userName;
  final bool isAdmin;

  TypingEvent({required this.userName, required this.isAdmin});
}

// ==================== Voice Call Event Models ====================

/// Call offer event (incoming call)
class CallOfferEvent {
  final int conversationId;
  final String callerId;
  final String callerName;
  final String sdp;
  final String sdpType;

  CallOfferEvent({
    required this.conversationId,
    required this.callerId,
    required this.callerName,
    required this.sdp,
    required this.sdpType,
  });
}

/// Call answer event
class CallAnswerEvent {
  final int conversationId;
  final String answererId;
  final String answererName;
  final String sdp;
  final String sdpType;

  CallAnswerEvent({
    required this.conversationId,
    required this.answererId,
    required this.answererName,
    required this.sdp,
    required this.sdpType,
  });
}

/// Call rejected event
class CallRejectedEvent {
  final int conversationId;
  final String rejectedBy;
  final String reason;

  CallRejectedEvent({
    required this.conversationId,
    required this.rejectedBy,
    required this.reason,
  });
}

/// Call ended event
class CallEndedEvent {
  final int conversationId;
  final String endedBy;
  final String? reason;

  CallEndedEvent({
    required this.conversationId,
    required this.endedBy,
    this.reason,
  });
}

/// ICE candidate event
class IceCandidateEvent {
  final int conversationId;
  final String candidate;
  final String sdpMid;
  final int sdpMLineIndex;

  IceCandidateEvent({
    required this.conversationId,
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });
}

/// Read receipt event (WhatsApp-style: sent -> delivered -> read)
class ReadReceiptEvent {
  final int conversationId;
  final List<int> messageIds;
  final String status; // 'delivered' or 'read'
  final String? readBy;
  final DateTime timestamp;

  ReadReceiptEvent({
    required this.conversationId,
    required this.messageIds,
    required this.status,
    this.readBy,
    required this.timestamp,
  });

  factory ReadReceiptEvent.fromJson(Map<String, dynamic> json) {
    return ReadReceiptEvent(
      conversationId: json['conversation_id'] ?? 0,
      messageIds: List<int>.from(json['message_ids'] ?? []),
      status: json['status'] ?? 'delivered',
      readBy: json['read_by'],
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    );
  }
}

class NewDeviceLoginEvent {
  final String deviceName;
  final String ipAddress;
  final String platform;
  final DateTime timestamp;

  NewDeviceLoginEvent({
    required this.deviceName,
    required this.ipAddress,
    required this.platform,
    required this.timestamp,
  });

  factory NewDeviceLoginEvent.fromJson(Map<String, dynamic> json) {
    return NewDeviceLoginEvent(
      deviceName: json['device_name'] ?? 'Unbekanntes Gerät',
      ipAddress: json['ip_address'] ?? 'Unbekannt',
      platform: json['platform'] ?? 'Unbekannt',
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    );
  }
}

/// Ticket notification event
class TicketNotificationEvent {
  final int ticketId;
  final String notificationType;
  final String title;
  final String message;
  final String ticketSubject;
  final String senderName;
  final DateTime timestamp;

  TicketNotificationEvent({
    required this.ticketId,
    required this.notificationType,
    required this.title,
    required this.message,
    required this.ticketSubject,
    required this.senderName,
    required this.timestamp,
  });

  factory TicketNotificationEvent.fromJson(Map<String, dynamic> json) {
    return TicketNotificationEvent(
      ticketId: json['ticket_id'] ?? 0,
      notificationType: json['notification_type'] ?? 'comment_added',
      title: json['title'] ?? 'Ticket Update',
      message: json['message'] ?? '',
      ticketSubject: json['ticket_subject'] ?? '',
      senderName: json['sender_name'] ?? 'Unknown',
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    );
  }
}
