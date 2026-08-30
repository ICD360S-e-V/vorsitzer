import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/chat_service.dart';
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

  StreamSubscription<bool>? _steuerSub;
  bool _steuerbar = false;
  bool _stumm = false;

  // Chatstreifen neben dem Bild. Bewusst schmal und ohne Anhänge: er soll
  // „schauen Sie mal oben rechts" ermöglichen, nicht den Chatdialog ersetzen.
  StreamSubscription<ChatMessage>? _nachrichtSub;
  final TextEditingController _eingabe = TextEditingController();
  final List<_Zeile> _zeilen = [];
  bool _chatOffen = false;

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
      if (s == RemoteControlState.idle) {
        FernwartungRueckkehr.vergessen();
        _leave(_endMessage(_svc.lastEnd));
      }
    });

    _steuerSub = _svc.zielSteuerbarStream.listen((frei) {
      if (mounted) setState(() => _steuerbar = frei);
    });
    _nachrichtSub = ChatService().messageStream.listen((m) {
      if (!mounted || m.conversationId != widget.conversationId) return;
      setState(() => _zeilen.add(_Zeile(m.displayMessage, m.isAdmin)));
    });
    FernwartungRueckkehr.merken(widget);

    // ⚠️ Schon eine Sitzung am Laufen? Dann NICHT neu starten, sondern
    // andocken. `start()` gibt bei belegtem Dienst false zurück, und dieser
    // Bildschirm hätte sich mit „Verbindung konnte nicht aufgebaut werden"
    // sofort wieder verabschiedet — also genau beim Zurückkehren aus dem Chat.
    if (_svc.state != RemoteControlState.idle) {
      setState(() {
        _state = _svc.state;
        _steuerbar = _svc.zielSteuerbar;
        _renderer.srcObject = _svc.remoteStream;
        _hasVideo = _svc.remoteStream != null;
      });
      return;
    }

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
    _steuerSub?.cancel();
    _nachrichtSub?.cancel();
    _eingabe.dispose();
    _focus.dispose();
    _renderer.srcObject = null;
    _renderer.dispose();
    // ⚠️ Die Sitzung wird hier NICHT mehr beendet.
    //
    // Vorher stand hier `_svc.end(notifyPeer: true)`. Damit riss jeder Schritt
    // zurück in den Chat die Fernwartung ab — genau der Schritt, den man tut,
    // um dem Mitglied etwas zu schreiben oder es anzurufen. Beenden ist jetzt
    // ausschließlich der rote Knopf oben, und der Dienst ist ein Singleton, der
    // die Sitzung ohne diesen Bildschirm weiterträgt.
    //
    // Der Preis dafür ist ein Rückweg: [FernwartungRueckkehr] merkt sich, wie
    // dieser Bildschirm zu öffnen war, damit eine laufende Sitzung nicht
    // unerreichbar wird.
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

  void _senden() {
    final text = _eingabe.text.trim();
    if (text.isEmpty) return;
    ChatService().sendMessage(widget.conversationId, text);
    setState(() {
      _zeilen.add(_Zeile(text, true));
      _eingabe.clear();
    });
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Flexible(
              child: Text('Fernwartung — ${widget.targetName}',
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 10),
            if (_state == RemoteControlState.connected) _steuerChip(),
          ],
        ),
        actions: [
          // Systemtasten. Auf einem Telefon mit Gestennavigation gibt es keine
          // Fläche, die man dafür anklicken könnte — ohne diese Knöpfe käme man
          // aus jeder geöffneten App nicht mehr heraus.
          if (_steuerbar && _istHandy) ...[
            IconButton(
              tooltip: 'Zurück',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => _svc.sendSystemAktion('back'),
            ),
            IconButton(
              tooltip: 'Startbildschirm',
              icon: const Icon(Icons.home_outlined),
              onPressed: () => _svc.sendSystemAktion('home'),
            ),
            IconButton(
              tooltip: 'Übersicht',
              icon: const Icon(Icons.crop_square_outlined),
              onPressed: () => _svc.sendSystemAktion('recents'),
            ),
            const SizedBox(width: 8),
          ],
          // Sprechen waehrend der Sitzung. Ohne eigenes Mikrofon wird nur
          // zugehoert — dann waere ein Stummschalter eine Luege.
          if (_svc.hatMikrofon)
            IconButton(
              tooltip: _stumm ? 'Mikrofon einschalten' : 'Mikrofon stummschalten',
              icon: Icon(_stumm ? Icons.mic_off : Icons.mic,
                  color: _stumm ? Colors.redAccent : Colors.white),
              onPressed: () {
                _svc.mikrofonStumm(!_stumm);
                setState(() => _stumm = !_stumm);
              },
            ),
          IconButton(
            tooltip: _chatOffen ? 'Chat ausblenden' : 'Chat einblenden',
            icon: Icon(_chatOffen ? Icons.chat : Icons.chat_bubble_outline,
                color: _chatOffen ? Colors.lightBlueAccent : Colors.white),
            onPressed: () => setState(() => _chatOffen = !_chatOffen),
          ),
          TextButton.icon(
            onPressed: () {
              FernwartungRueckkehr.vergessen();
              _svc.end(notifyPeer: true, reason: RemoteControlEnd.none);
            },
            icon: const Icon(Icons.call_end, color: Colors.redAccent),
            label: const Text('Beenden', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(child: _bildbereich()),
          if (_chatOffen) _chatStreifen(),
        ],
      ),
    );
  }

  /// Android ohne eingeschalteten Bedienungshilfen-Dienst, iOS immer: der
  /// Bildschirm kommt an, Klicks gehen ins Leere. Vorher stand nirgends etwas —
  /// man klickte und nichts geschah, ununterscheidbar von einer hängenden
  /// Leitung.
  Widget _steuerChip() {
    final an = _steuerbar;
    final plattform = _svc.zielPlattform;
    return Tooltip(
      message: an
          ? 'Tippen, Wischen und Zurück gehen an das Gerät.'
          : (plattform == 'ios'
              ? 'iOS lässt keine Fernsteuerung zu — nur Ansicht.'
              : 'Nur Ansicht: ${widget.targetName} hat die Steuerung nicht '
                  'freigegeben (Profil ▸ Fernwartung).'),
      child: Chip(
        visualDensity: VisualDensity.compact,
        backgroundColor: an ? Colors.green.shade800 : Colors.orange.shade900,
        side: BorderSide.none,
        avatar: Icon(an ? Icons.touch_app : Icons.visibility,
            size: 16, color: Colors.white),
        label: Text(an ? 'Steuerung' : 'Nur Ansicht',
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }

  bool get _istHandy =>
      _svc.zielPlattform == 'android' || _svc.zielPlattform == 'ios';

  Widget _chatStreifen() {
    return Container(
      width: 300,
      color: const Color(0xFF15151F),
      child: Column(
        children: [
          Expanded(
            child: _zeilen.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Nachrichten aus dieser Sitzung erscheinen hier.\n'
                        'Der ganze Verlauf steht im Chat.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: _zeilen.length,
                    itemBuilder: (_, i) {
                      final z = _zeilen[_zeilen.length - 1 - i];
                      return Align(
                        alignment: z.eigen
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: z.eigen
                                ? Colors.blue.shade700
                                : const Color(0xFF2A2A3A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(z.text,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: Colors.white24),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _eingabe,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    // ⚠️ Eigener Fokus: der Bildbereich verschluckt sonst jede
                    // Taste, weil er alle Tastendrücke an das Mitglied
                    // weiterreicht und als „verarbeitet" meldet.
                    onSubmitted: (_) => _senden(),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Nachricht …',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.lightBlueAccent),
                  onPressed: _senden,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bildbereich() {
    final connecting = _state != RemoteControlState.connected || !_hasVideo;
    return Focus(
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
                  : '${widget.targetName} hat zugestimmt und teilt den '
                      'Bildschirm.\nVerbindung wird hergestellt …',
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            if (!waiting) ...[
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Bleibt es hier stehen, kommt kein Bild durch — nicht die '
                  'Zustimmung fehlt, sondern die Medienverbindung.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


class _Zeile {
  final String text;
  final bool eigen;
  _Zeile(this.text, this.eigen);
}

/// Merkt sich, wie eine LAUFENDE Fernwartung wieder zu öffnen ist.
///
/// ⚠️ Nötig geworden durch die Reparatur nebenan: seit der Bildschirm die
/// Sitzung beim Verlassen nicht mehr abreißt, kann man ihn schließen, ohne dass
/// die Sitzung endet — und wäre ohne Rückweg mit einem geteilten Bildschirm
/// allein, den niemand mehr sieht und den nur noch das Mitglied beenden kann.
///
/// Bewusst nur die Öffnungsdaten, kein Zustand: die Sitzung selbst lebt im
/// [RemoteControlService], der ohnehin ein Singleton ist. Zwei Orte mit
/// Sitzungszustand wären zwei Wahrheiten.
class FernwartungRueckkehr {
  static RemoteControlScreen? _offen;

  static void merken(RemoteControlScreen s) => _offen = s;
  static void vergessen() => _offen = null;

  /// Läuft gerade eine Sitzung, zu der man zurückkehren kann?
  static bool get laeuft =>
      _offen != null && RemoteControlService().state != RemoteControlState.idle;

  /// Öffnet den Betrachter der laufenden Sitzung erneut. Tut nichts, wenn keine
  /// läuft.
  static void zurueck(BuildContext context) {
    final s = _offen;
    if (s == null || !laeuft) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => s));
  }
}
