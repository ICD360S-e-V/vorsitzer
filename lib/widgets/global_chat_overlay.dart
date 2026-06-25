import 'package:flutter/material.dart';
import '../services/global_chat_service.dart';
import 'chat_mini_panel.dart';

/// Global Messenger-style overlay rendered above every route via
/// MaterialApp.builder. Contains:
///
/// - A draggable column of chat-head bubbles (initials, unread count).
/// - Up to 3 expanded [ChatMiniPanel] cards stacked horizontally along the
///   bottom edge. Each panel can be resized by dragging its top-left corner.
///
/// All state lives in [GlobalChatService] — this widget is purely view.
class GlobalChatOverlay extends StatefulWidget {
  const GlobalChatOverlay({super.key});

  @override
  State<GlobalChatOverlay> createState() => _GlobalChatOverlayState();
}

class _GlobalChatOverlayState extends State<GlobalChatOverlay> {
  final _service = GlobalChatService();

  @override
  void initState() {
    super.initState();
    _service.start();
    _service.addListener(_onChange);
  }

  @override
  void dispose() {
    _service.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.enabled) {
      debugPrint('[GlobalChatOverlay] hidden — enabled=false');
      return const SizedBox.shrink();
    }
    final mn = _service.currentMitgliedernummer;
    if (mn == null || mn.isEmpty) {
      debugPrint('[GlobalChatOverlay] hidden — mitgliedernummer not set');
      return const SizedBox.shrink();
    }
    final media = MediaQuery.of(context).size;
    debugPrint('[GlobalChatOverlay] render bubbles=${_service.bubbles.length} '
               'panels=${_service.openPanels.length} media=$media');
    // Stack.expand → forces full-screen so Positioned children get the
    // correct origin (without this, Stack collapses to 0×0 because all
    // children are Positioned and the bubbles render outside the viewport).
    return Stack(
      fit: StackFit.expand,
      children: [
        // Panels (stacked horizontally from right, bottom-aligned)
        ..._buildPanels(media, mn),
        // Bubble column (draggable)
        _buildBubbleColumn(media),
      ],
    );
  }

  // ────────────────────────── PANELS ──────────────────────────
  List<Widget> _buildPanels(Size media, String mn) {
    final widgets = <Widget>[];
    // Right-edge offset: start at right and walk left as we add panels.
    double rightOffset = 16;
    // Bubble column may overlap — give panels priority by starting beyond it.
    for (final convId in _service.openPanels) {
      final bubble = _service.bubbles[convId];
      if (bubble == null) continue;
      final geom = _service.geometryFor(convId);
      // Constrain size so it never exceeds viewport
      final w = geom.width.clamp(260.0, media.width - 40);
      final h = geom.height.clamp(280.0, media.height - 60);
      widgets.add(Positioned(
        right: rightOffset,
        bottom: 16,
        width: w,
        height: h,
        child: Stack(children: [
          ChatMiniPanel(
            key: ValueKey('panel-$convId'),
            conversationId: convId,
            senderName: bubble.senderName,
            currentMitgliedernummer: mn,
            onMinimize: () => _service.minimizePanel(convId),
            onClose: () => _service.closeConversation(convId),
          ),
          // Resize grip — top-left corner
          Positioned(
            top: 0, left: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  // Dragging the corner inward shrinks; outward grows.
                  final newW = (w - d.delta.dx).clamp(260.0, media.width - 40);
                  final newH = (h - d.delta.dy).clamp(280.0, media.height - 60);
                  _service.setPanelGeometry(convId, PanelGeometry(width: newW, height: newH));
                },
                child: Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border: Border(
                      left: BorderSide(color: Colors.white.withValues(alpha: 0.7), width: 2),
                      top: BorderSide(color: Colors.white.withValues(alpha: 0.7), width: 2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ));
      rightOffset += w + 12;
    }
    return widgets;
  }

  // ────────────────────────── BUBBLE COLUMN ──────────────────────────
  Widget _buildBubbleColumn(Size media) {
    // Bubbles not currently expanded as panels
    final hidden = _service.bubbles.values
        .where((b) => !_service.openPanels.contains(b.conversationId))
        .toList();
    if (hidden.isEmpty) return const SizedBox.shrink();
    final anchor = _service.bubbleColumnAnchor;
    // Anchor is offset from right + bottom (so window resizes keep bubbles visible)
    return Positioned(
      right: anchor.dx.clamp(0, media.width - 70).toDouble(),
      bottom: anchor.dy.clamp(0, media.height - 80).toDouble(),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) {
            final newX = (anchor.dx - d.delta.dx).clamp(0.0, media.width - 70);
            final newY = (anchor.dy - d.delta.dy).clamp(0.0, media.height - 80);
            _service.setBubbleColumnAnchor(Offset(newX, newY));
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final b in hidden.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _Bubble(
                    bubble: b,
                    onTap: () => _service.openPanel(b.conversationId, senderName: b.senderName, lastMessagePreview: b.lastMessagePreview),
                    onClose: () => _service.removeBubble(b.conversationId),
                  ),
                ),
              if (hidden.length > 8)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  width: 56, height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.grey.shade700, shape: BoxShape.circle),
                  child: Text('+${hidden.length - 8}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final GlobalChatBubble bubble;
  final VoidCallback onTap;
  final VoidCallback onClose;
  const _Bubble({required this.bubble, required this.onTap, required this.onClose});

  Color _color(String name) {
    const palette = <Color>[
      Color(0xFF1976D2), Color(0xFF388E3C), Color(0xFFD32F2F),
      Color(0xFF7B1FA2), Color(0xFFF57C00), Color(0xFF00838F),
      Color(0xFFC2185B), Color(0xFF5D4037), Color(0xFF455A64),
    ];
    if (name.isEmpty) return Colors.grey;
    var hash = 0;
    for (final c in name.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final initial = bubble.senderName.trim().isNotEmpty
        ? bubble.senderName.trim()[0].toUpperCase()
        : '?';
    final tooltip = (bubble.lastMessagePreview ?? '').isNotEmpty
        ? '${bubble.senderName}\n${bubble.lastMessagePreview}'
        : bubble.senderName;
    return SizedBox(
      width: 64, height: 64,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          right: 0, bottom: 0,
          child: Tooltip(
            message: tooltip,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: 56, height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _color(bubble.senderName),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Text(initial,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                  if (bubble.unreadCount > 0)
                    Positioned(
                      right: -2, top: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                        decoration: BoxDecoration(
                          color: Colors.red.shade600,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          bubble.unreadCount > 99 ? '99+' : '${bubble.unreadCount}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0, top: 0,
          child: Tooltip(
            message: 'Bubble ausblenden',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onClose,
                child: Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
