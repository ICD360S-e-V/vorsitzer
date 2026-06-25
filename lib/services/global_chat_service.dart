import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset;
import 'chat_service.dart';
import 'logger_service.dart';

/// One floating chat bubble on the global overlay.
class GlobalChatBubble {
  final int conversationId;
  final String senderName;
  final int unreadCount;
  final String? lastMessagePreview;
  const GlobalChatBubble({
    required this.conversationId,
    required this.senderName,
    this.unreadCount = 0,
    this.lastMessagePreview,
  });

  GlobalChatBubble copyWith({int? unreadCount, String? lastMessagePreview, String? senderName}) {
    return GlobalChatBubble(
      conversationId: conversationId,
      senderName: senderName ?? this.senderName,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
    );
  }
}

/// Geometric state for one expanded panel.
class PanelGeometry {
  final double width;
  final double height;
  const PanelGeometry({this.width = 320, this.height = 460});
  PanelGeometry copyWith({double? width, double? height}) =>
      PanelGeometry(width: width ?? this.width, height: height ?? this.height);
}

/// Singleton state for the global chat-head overlay (Facebook Messenger style).
///
/// Holds:
/// - registered bubbles (one per conversation that currently surfaces),
/// - up-to-3 expanded panels (FIFO eviction when a 4th opens),
/// - draggable anchor position for the bubble column,
/// - per-panel size for resizing.
///
/// Listens to [ChatService.newMessageStream] globally so messages arriving
/// while the user is on any page automatically appear as bubbles. Dashboard
/// no longer owns this state — it just calls into the service.
class GlobalChatService extends ChangeNotifier {
  static final GlobalChatService _instance = GlobalChatService._internal();
  factory GlobalChatService() => _instance;
  GlobalChatService._internal();

  final _chat = ChatService();
  final _log = LoggerService();
  StreamSubscription? _messageSub;
  bool _started = false;

  /// Maximum panels open simultaneously. Older ones get auto-minimized.
  static const int maxOpenPanels = 3;

  /// All bubbles, keyed by conversation id.
  final Map<int, GlobalChatBubble> _bubbles = {};
  Map<int, GlobalChatBubble> get bubbles => Map.unmodifiable(_bubbles);

  /// Currently expanded panels, in open-order (oldest first).
  final List<int> _openPanels = [];
  List<int> get openPanels => List.unmodifiable(_openPanels);

  /// Per-panel geometry (size). Position is always anchored bottom-right
  /// with horizontal stacking; only size is user-customizable.
  final Map<int, PanelGeometry> _panelGeometry = {};
  PanelGeometry geometryFor(int convId) => _panelGeometry[convId] ?? const PanelGeometry();

  /// Bubble column draggable position (relative to right/bottom edges).
  Offset _bubbleColumnAnchor = const Offset(16, 120);
  Offset get bubbleColumnAnchor => _bubbleColumnAnchor;

  /// Self user id — used to filter own messages (don't bubble outgoing).
  int? get currentUserId => _chat.currentUserId;

  /// Whether the full AdminChatDialog is currently open. While open, we
  /// suppress bubble creation to avoid duplicate badges.
  bool _adminDialogOpen = false;
  bool get adminDialogOpen => _adminDialogOpen;
  set adminDialogOpen(bool v) {
    if (_adminDialogOpen == v) return;
    _adminDialogOpen = v;
    notifyListeners();
  }

  /// Whether the overlay should render at all. Set false on login screen,
  /// true after dashboard mounts.
  bool _enabled = false;
  bool get enabled => _enabled;
  set enabled(bool v) {
    if (_enabled == v) return;
    _enabled = v;
    notifyListeners();
  }

  /// Logged-in user's mitgliedernummer — used by the global overlay to spawn
  /// [ChatMiniPanel] widgets without needing access to the dashboard's
  /// widget tree. Set when dashboard mounts; cleared on logout.
  String? _currentMitgliedernummer;
  String? get currentMitgliedernummer => _currentMitgliedernummer;
  set currentMitgliedernummer(String? v) {
    if (_currentMitgliedernummer == v) return;
    _currentMitgliedernummer = v;
    notifyListeners();
  }

  /// Subscribe to the global message stream once. Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    _messageSub = _chat.messageStream.listen(_onMessage);
    _log.info('GlobalChatService started — subscribed to ChatService.messageStream', tag: 'GLOBAL_CHAT');
    debugPrint('[GlobalChatService] started, subscribed to messageStream');
  }

  /// Inject a synthetic bubble for visual testing. Used by the dashboard
  /// "Test Bubble" affordance so we can verify the overlay renders even
  /// when no real message has arrived yet.
  void debugInjectTestBubble({String name = 'Test User'}) {
    final id = -DateTime.now().millisecondsSinceEpoch ~/ 1000; // negative id → won't clash
    _bubbles[id] = GlobalChatBubble(
      conversationId: id,
      senderName: name,
      unreadCount: 1,
      lastMessagePreview: 'Test bubble — rendering confirmation',
    );
    debugPrint('[GlobalChatService] TEST bubble injected id=$id');
    notifyListeners();
  }

  void _onMessage(ChatMessage ev) {
    final myId = _chat.currentUserId;
    debugPrint('[GlobalChatService] _onMessage from=${ev.senderName} (sid=${ev.senderId}, '
               'myId=$myId, dialogOpen=$_adminDialogOpen, conv=${ev.conversationId})');
    // Don't bubble our own outgoing messages.
    if (myId != null && ev.senderId == myId) {
      debugPrint('[GlobalChatService] skip — own message');
      return;
    }
    // If full dialog is open, the dialog itself handles UI feedback.
    if (_adminDialogOpen) {
      debugPrint('[GlobalChatService] skip — admin dialog open');
      return;
    }

    final preview = ev.message.length > 80
        ? '${ev.message.substring(0, 80)}…'
        : ev.message;

    final existing = _bubbles[ev.conversationId];
    _bubbles[ev.conversationId] = GlobalChatBubble(
      conversationId: ev.conversationId,
      senderName: ev.senderName,
      unreadCount: ((existing?.unreadCount ?? 0) +
          (_openPanels.contains(ev.conversationId) ? 0 : 1)),
      lastMessagePreview: preview,
    );
    debugPrint('[GlobalChatService] bubble UPSERTED for ${ev.senderName}, total bubbles=${_bubbles.length}');
    notifyListeners();
  }

  /// Manually add or update a bubble (e.g. on app startup from server-side
  /// unread queue, or when the user clicks a conversation in the admin list).
  void upsertBubble({
    required int conversationId,
    required String senderName,
    int unreadCount = 0,
    String? lastMessagePreview,
  }) {
    _bubbles[conversationId] = GlobalChatBubble(
      conversationId: conversationId,
      senderName: senderName,
      unreadCount: unreadCount,
      lastMessagePreview: lastMessagePreview,
    );
    notifyListeners();
  }

  /// Replace the entire bubble set (used on dashboard background-conversation
  /// load).
  void replaceBubbles(Iterable<GlobalChatBubble> all) {
    _bubbles
      ..clear()
      ..addEntries(all.map((b) => MapEntry(b.conversationId, b)));
    notifyListeners();
  }

  /// Drop a bubble and any open panel for it.
  void removeBubble(int conversationId) {
    _bubbles.remove(conversationId);
    _openPanels.remove(conversationId);
    _panelGeometry.remove(conversationId);
    notifyListeners();
  }

  void clearAllBubbles() {
    _bubbles.clear();
    _openPanels.clear();
    _panelGeometry.clear();
    notifyListeners();
  }

  /// Expand a conversation into a floating panel. If a bubble exists,
  /// clears its unread count. Enforces [maxOpenPanels] by FIFO-evicting
  /// the oldest panel (it stays as a bubble).
  void openPanel(int conversationId, {String? senderName, String? lastMessagePreview}) {
    debugPrint('[GlobalChatService] openPanel($conversationId, $senderName) — current panels=$_openPanels');
    if (!_openPanels.contains(conversationId)) {
      if (_openPanels.length >= maxOpenPanels) {
        _openPanels.removeAt(0);
      }
      _openPanels.add(conversationId);
    }
    // Ensure bubble exists so a min/close cycle still works.
    if (!_bubbles.containsKey(conversationId) && senderName != null) {
      _bubbles[conversationId] = GlobalChatBubble(
        conversationId: conversationId,
        senderName: senderName,
        lastMessagePreview: lastMessagePreview,
      );
    } else if (_bubbles.containsKey(conversationId)) {
      _bubbles[conversationId] = _bubbles[conversationId]!.copyWith(unreadCount: 0);
    }
    debugPrint('[GlobalChatService] openPanel after: panels=$_openPanels bubbles=${_bubbles.length}');
    notifyListeners();
  }

  /// Minimize an expanded panel back to its bubble.
  void minimizePanel(int conversationId) {
    _openPanels.remove(conversationId);
    notifyListeners();
  }

  /// Close panel + remove bubble entirely. Messages stay on server.
  void closeConversation(int conversationId) {
    _openPanels.remove(conversationId);
    _bubbles.remove(conversationId);
    _panelGeometry.remove(conversationId);
    notifyListeners();
  }

  void setBubbleColumnAnchor(Offset newAnchor) {
    _bubbleColumnAnchor = newAnchor;
    notifyListeners();
  }

  void setPanelGeometry(int conversationId, PanelGeometry g) {
    _panelGeometry[conversationId] = g;
    notifyListeners();
  }

  /// Mark a conversation as actively read (clears unread badge).
  void markRead(int conversationId) {
    final b = _bubbles[conversationId];
    if (b != null && b.unreadCount > 0) {
      _bubbles[conversationId] = b.copyWith(unreadCount: 0);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }
}
