import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/logger_service.dart';

final _log = LoggerService();

/// Incoming Call Dialog - shown when receiving a voice call
class IncomingCallDialog extends StatefulWidget {
  final String callerName;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const IncomingCallDialog({
    super.key,
    required this.callerName,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<IncomingCallDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;
  Timer? _timeoutTimer;
  int _ringCount = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // Auto-reject after 5 minutes (300 seconds)
    _timeoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _ringCount++);
      if (_ringCount >= 300) {
        timer.cancel();
        widget.onReject();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Full-screen modal overlay
    return Material(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(40),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // Incoming call text
            const Text(
              'Eingehender Anruf',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),

            // Animated caller avatar
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.green.shade400,
                      Colors.green.shade700,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.phone_in_talk,
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Caller name
            Text(
              widget.callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Ring duration
            Text(
              'Klingelt seit ${_ringCount}s',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 30),

            // Accept / Reject buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Reject button
                _buildCallButton(
                  icon: Icons.call_end,
                  color: Colors.red,
                  label: 'Ablehnen',
                  onPressed: widget.onReject,
                ),

                // Accept button
                _buildCallButton(
                  icon: Icons.call,
                  color: Colors.green,
                  label: 'Annehmen',
                  onPressed: widget.onAccept,
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            onPressed();
          },
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// In-Call Overlay - shown during an active call with voice activity indicator
class InCallOverlay extends StatefulWidget {
  final String remoteName;
  final Duration callDuration;
  final bool isMuted;
  final bool isSpeakerOn;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onEndCall;
  final MediaStream? remoteStream; // CRITICAL: Remote audio stream for playback
  final RTCIceConnectionState? iceConnectionState; // Network quality indicator

  const InCallOverlay({
    super.key,
    required this.remoteName,
    required this.callDuration,
    required this.isMuted,
    required this.isSpeakerOn,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onEndCall,
    this.remoteStream,
    this.iceConnectionState,
  });

  @override
  State<InCallOverlay> createState() => _InCallOverlayState();
}

class _InCallOverlayState extends State<InCallOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _activityTimer;
  List<double> _barHeights = [0.3, 0.5, 0.7, 0.5, 0.3];

  // Simulated voice activity animation (cross-platform)
  final Random _random = Random();

  // Remote audio renderer for Windows playback (CRITICAL FIX)
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _rendererInitialized = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Initialize remote audio renderer
    _initRemoteRenderer();

    // Start real audio level monitoring
    _startAudioMonitoring();
  }

  Future<void> _initRemoteRenderer() async {
    try {
      await _remoteRenderer.initialize();
      _rendererInitialized = true;
      _log.info('InCallOverlay: ✓ Remote audio renderer initialized', tag: 'CALL-UI');

      // Set explicit audio output device (CRITICAL for Windows playback)
      await _setAudioOutputDevice();

      // Attach remote stream if available
      if (widget.remoteStream != null) {
        _remoteRenderer.srcObject = widget.remoteStream;
        _log.info('InCallOverlay: ✓✓✓ Remote stream attached to renderer - AUDIO PLAYBACK ENABLED!', tag: 'CALL-UI');
      }
    } catch (e) {
      _log.error('InCallOverlay: ❌ Failed to initialize remote renderer: $e', tag: 'CALL-UI');
    }
  }

  Future<void> _setAudioOutputDevice() async {
    try {
      _log.info('InCallOverlay: Enumerating audio output devices...', tag: 'CALL-UI');

      final devices = await navigator.mediaDevices.enumerateDevices();
      final audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();

      _log.info('InCallOverlay: Found ${audioOutputs.length} audio output devices', tag: 'CALL-UI');

      for (var i = 0; i < audioOutputs.length; i++) {
        final device = audioOutputs[i];
        _log.info('InCallOverlay: Output $i: "${device.label}" (${device.deviceId})', tag: 'CALL-UI');
      }

      if (audioOutputs.isNotEmpty) {
        // CRITICAL: Prefer "Speakers" over "HP/Display/Monitor" (monitors don't have audio!)
        var selectedOutput = audioOutputs.firstWhere(
          (d) => d.label.toLowerCase().contains('speaker'),
          orElse: () => audioOutputs.last, // Fallback to last device if no "Speakers" found
        );

        _log.info('InCallOverlay: Selected audio output: "${selectedOutput.label}"', tag: 'CALL-UI');
        _log.info('InCallOverlay: Setting audio output device...', tag: 'CALL-UI');

        final success = await _remoteRenderer.audioOutput(selectedOutput.deviceId);

        if (success) {
          _log.info('InCallOverlay: ✓✓✓ Audio output set successfully to: "${selectedOutput.label}"', tag: 'CALL-UI');
        } else {
          _log.warning('InCallOverlay: ⚠️ Failed to set "${selectedOutput.label}", trying all devices...', tag: 'CALL-UI');

          // Try all devices one by one
          bool anySuccess = false;
          for (var device in audioOutputs) {
            if (device.deviceId == selectedOutput.deviceId) continue; // Skip already tried

            _log.info('InCallOverlay: Trying: "${device.label}"', tag: 'CALL-UI');
            final trySuccess = await _remoteRenderer.audioOutput(device.deviceId);

            if (trySuccess) {
              _log.info('InCallOverlay: ✓ Audio output set to: "${device.label}"', tag: 'CALL-UI');
              anySuccess = true;
              break;
            }
          }

          if (!anySuccess) {
            _log.error('InCallOverlay: ❌ All audio output devices failed!', tag: 'CALL-UI');
          }
        }
      } else {
        _log.warning('InCallOverlay: ⚠️ No audio output devices found!', tag: 'CALL-UI');
      }
    } catch (e) {
      _log.error('InCallOverlay: ❌ Audio output selection error: $e', tag: 'CALL-UI');
    }
  }

  @override
  void didUpdateWidget(InCallOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update remote stream when it changes
    if (widget.remoteStream != oldWidget.remoteStream && _rendererInitialized) {
      _remoteRenderer.srcObject = widget.remoteStream;
      if (widget.remoteStream != null) {
        _log.info('InCallOverlay: ✓ Remote stream updated on renderer', tag: 'CALL-UI');
      }
    }
  }

  @override
  void dispose() {
    _stopAudioMonitoring();
    _activityTimer?.cancel();
    _pulseController.dispose();
    if (_rendererInitialized) _remoteRenderer.dispose(); // Cleanup remote renderer
    super.dispose();
  }

  /// Start simulated voice activity animation (cross-platform)
  void _startAudioMonitoring() {
    _activityTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (mounted && !widget.isMuted) {
        setState(() {
          // Generate random bar heights for visual voice activity effect
          _barHeights = List.generate(5, (i) {
            return 0.2 + _random.nextDouble() * 0.6;
          });
        });
        if (!_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        }
      } else if (widget.isMuted) {
        _pulseController.stop();
        _pulseController.reset();
      }
    });
  }

  /// Stop voice activity animation
  void _stopAudioMonitoring() {
    _activityTimer?.cancel();
    _activityTimer = null;
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) {
      return '${twoDigits(d.inHours)}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // CRITICAL FIX: RTCVideoView for Windows audio playback
        // Widget must have REAL SIZE and be in widget tree for audio to play!
        // Using Offstage to hide it visually but keep it active
        if (_rendererInitialized && widget.remoteStream != null)
          Offstage(
            offstage: true,
            child: SizedBox(
              width: 1,
              height: 1,
              child: RTCVideoView(
                _remoteRenderer,
                mirror: false,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),
          ),

        // Visible UI
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.green.shade700,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
          // Voice activity indicator (bars)
          _buildVoiceActivityIndicator(),
          const SizedBox(width: 12),

          // Remote name, duration, and network quality
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      widget.remoteName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildNetworkQualityIndicator(),
                  ],
                ),
                Text(
                  _formatDuration(widget.callDuration),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Speaker button
          IconButton(
            icon: Icon(
              widget.isSpeakerOn ? Icons.volume_up : Icons.volume_off,
              color: widget.isSpeakerOn ? Colors.white : Colors.red.shade300,
            ),
            onPressed: widget.onToggleSpeaker,
            tooltip: widget.isSpeakerOn ? 'Lautsprecher aus' : 'Lautsprecher an',
          ),

          // Mute button
          IconButton(
            icon: Icon(
              widget.isMuted ? Icons.mic_off : Icons.mic,
              color: widget.isMuted ? Colors.red.shade300 : Colors.white,
            ),
            onPressed: widget.onToggleMute,
            tooltip: widget.isMuted ? 'Stummschaltung aufheben' : 'Stummschalten',
          ),

          // End call button
          IconButton(
            icon: const Icon(Icons.call_end, color: Colors.white),
            onPressed: widget.onEndCall,
            style: IconButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            tooltip: 'Auflegen',
          ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceActivityIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(5, (index) {
        final height = widget.isMuted ? 4.0 : (_barHeights[index] * 20);
        final color = widget.isMuted ? Colors.red.shade300 : Colors.white;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 3,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildNetworkQualityIndicator() {
    if (widget.iceConnectionState == null) {
      return const SizedBox.shrink();
    }

    IconData icon;
    Color color;
    String tooltip;

    switch (widget.iceConnectionState!) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        icon = Icons.signal_cellular_alt;
        color = Colors.green;
        tooltip = 'Verbindung: Ausgezeichnet';
        break;
      case RTCIceConnectionState.RTCIceConnectionStateChecking:
        icon = Icons.signal_cellular_alt_2_bar;
        color = Colors.orange;
        tooltip = 'Verbindung: Wird hergestellt...';
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        icon = Icons.signal_cellular_alt_1_bar;
        color = Colors.red;
        tooltip = 'Verbindung: Getrennt';
        break;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        icon = Icons.signal_cellular_off;
        color = Colors.red;
        tooltip = 'Verbindung: Fehlgeschlagen';
        break;
      default:
        icon = Icons.signal_cellular_alt_1_bar;
        color = Colors.grey;
        tooltip = 'Verbindung: Unbekannt';
    }

    return Tooltip(
      message: tooltip,
      child: Icon(
        icon,
        size: 16,
        color: color,
      ),
    );
  }
}

/// Calling Overlay - shown when initiating a call
class CallingOverlay extends StatelessWidget {
  final String targetName;
  final VoidCallback onCancel;

  const CallingOverlay({
    super.key,
    required this.targetName,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade700,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing indicator
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(width: 12),

          // Calling text
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Anrufen...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
              Text(
                targetName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),

          // Cancel button
          IconButton(
            icon: const Icon(Icons.call_end, color: Colors.white),
            onPressed: onCancel,
            style: IconButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            tooltip: 'Abbrechen',
          ),
        ],
      ),
    );
  }
}
