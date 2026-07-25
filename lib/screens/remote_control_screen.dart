import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/remote_control_service.dart';

/// Fernwartung viewer (Vorsitzer side): shows the member's screen live and
/// forwards local mouse + keyboard to the member over the input data channel.
/// Separate from the RDP/Guacamole office remote desktop.
///
/// Coordinates are normalized against the displayed video rect (contain fit) so
/// they stay correct regardless of the member's resolution or window size.
class RemoteControlScreen extends StatefulWidget {
  final int conversationId;
  final String targetUserId;
  final String targetName;
  final String controllerMitgliedernummer;
  final String? controllerName;

  const RemoteControlScreen({
    super.key,
    required this.conversationId,
    required this.targetUserId,
    required this.targetName,
    required this.controllerMitgliedernummer,
    this.controllerName,
  });

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  final RemoteControlService _svc = RemoteControlService();
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  final FocusNode _focus = FocusNode();

  StreamSubscription<RemoteControlState>? _stateSub;
  StreamSubscription<MediaStream?>? _streamSub;

  RemoteControlState _state = RemoteControlState.idle;
  bool _hasVideo = false;
  bool _popped = false;
  int _downButton = 0; // remembered so pointer-up releases the right button

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _renderer.initialize();
    _streamSub = _svc.remoteStreamStream.listen((stream) {
      if (!mounted) return;
      setState(() {
        _renderer.srcObject = stream;
        _hasVideo = stream != null;
      });
    });
    _stateSub = _svc.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
      // Session over → leave the viewer and explain why.
      if (s == RemoteControlState.idle) _leave(_endMessage(_svc.lastEnd));
    });

    final ok = await _svc.start(
      conversationId: widget.conversationId,
      targetUserId: widget.targetUserId,
      controllerMitgliedernummer: widget.controllerMitgliedernummer,
      controllerName: widget.controllerName,
    );
    if (!ok && mounted) {
      _leave('Verbindung konnte nicht aufgebaut werden.');
    }
  }

  String? _endMessage(RemoteControlEnd end) {
    switch (end) {
      case RemoteControlEnd.declined:
        return '${widget.targetName} hat die Fernwartung abgelehnt.';
      case RemoteControlEnd.memberStopped:
        return '${widget.targetName} hat die Sitzung beendet.';
      case RemoteControlEnd.disconnected:
        return 'Verbindung getrennt.';
      case RemoteControlEnd.error:
        return 'Fehler bei der Fernwartung.';
      case RemoteControlEnd.timeout:
        return '${widget.targetName} hat nicht geantwortet.';
      case RemoteControlEnd.none:
        return null;
    }
  }

  void _leave(String? message) {
    if (_popped || !mounted) return;
    _popped = true;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _streamSub?.cancel();
    _focus.dispose();
    _renderer.srcObject = null;
    _renderer.dispose();
    // Ensure the session is torn down if the user backed out of the screen.
    if (_svc.state != RemoteControlState.idle) {
      _svc.end(notifyPeer: true);
    }
    super.dispose();
  }

  // ─── Coordinate mapping (contain fit) ───────────────────────────────────────
  Offset? _normalize(Offset local, Size box) {
    final vw = _renderer.videoWidth.toDouble();
    final vh = _renderer.videoHeight.toDouble();
    if (vw <= 0 || vh <= 0 || box.width <= 0 || box.height <= 0) return null;
    final a = vw / vh;
    double dispW, dispH, mx, my;
    if (box.width / box.height > a) {
      dispH = box.height;
      dispW = dispH * a;
      mx = (box.width - dispW) / 2;
      my = 0;
    } else {
      dispW = box.width;
      dispH = dispW / a;
      mx = 0;
      my = (box.height - dispH) / 2;
    }
    final nx = ((local.dx - mx) / dispW).clamp(0.0, 1.0);
    final ny = ((local.dy - my) / dispH).clamp(0.0, 1.0);
    return Offset(nx, ny);
  }

  int _buttonOf(int buttons) {
    if (buttons & kSecondaryMouseButton != 0) return 2;
    if (buttons & kMiddleMouseButton != 0) return 1;
    return 0; // primary / default
  }

  void _onPointerDown(PointerDownEvent e, Size box) {
    final n = _normalize(e.localPosition, box);
    if (n == null) return;
    _svc.sendMouseMove(n.dx, n.dy);
    _downButton = _buttonOf(e.buttons);
    _svc.sendMouseButton(_downButton, true);
  }

  void _onPointerMove(Offset local, Size box) {
    final n = _normalize(local, box);
    if (n != null) _svc.sendMouseMove(n.dx, n.dy);
  }

  void _onPointerUp() {
    _svc.sendMouseButton(_downButton, false);
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      _svc.sendWheel(e.scrollDelta.dx, e.scrollDelta.dy);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_svc.canSendInput) return KeyEventResult.ignored;
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    final isUp = event is KeyUpEvent;
    if (!isDown && !isUp) return KeyEventResult.ignored;
    _svc.sendKey(
      hid: event.physicalKey.usbHidUsage,
      character: isDown ? event.character : null,
      down: isDown,
    );
    // Consume so local shortcuts don't also fire while controlling remotely.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final connecting = _state != RemoteControlState.connected || !_hasVideo;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Fernwartung — ${widget.targetName}'),
        actions: [
          TextButton.icon(
            onPressed: () => _svc.end(notifyPeer: true, reason: RemoteControlEnd.none),
            icon: const Icon(Icons.call_end, color: Colors.redAccent),
            label: const Text('Beenden', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final box = Size(constraints.maxWidth, constraints.maxHeight);
            return MouseRegion(
              cursor: SystemMouseCursors.precise,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  _focus.requestFocus();
                  _onPointerDown(e, box);
                },
                onPointerMove: (e) => _onPointerMove(e.localPosition, box),
                onPointerHover: (e) => _onPointerMove(e.localPosition, box),
                onPointerUp: (_) => _onPointerUp(),
                onPointerSignal: _onPointerSignal,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_hasVideo)
                      RTCVideoView(
                        _renderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      ),
                    if (connecting) _statusOverlay(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _statusOverlay() {
    final waiting = _state == RemoteControlState.calling;
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 20),
            Text(
              waiting
                  ? 'Warten auf Zustimmung von ${widget.targetName} …'
                  : 'Bildschirm wird geladen …',
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
