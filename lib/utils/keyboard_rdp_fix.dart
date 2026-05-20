import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../services/logger_service.dart';

/// Workaround for a Flutter engine bug that bites hardest under Windows RDP:
///
///   1. User presses AltGr (PhysicalKeyboardKey.altRight).
///   2. Win32 dispatches a phantom `CtrlLeft down` immediately before
///      the real `AltRight down`.
///   3. User releases AltGr. The engine emits `AltRight up` — but NOT
///      the phantom `CtrlLeft up`.
///   4. The engine now thinks Ctrl is held. Next time the user types
///      Z / Y / X / C / V those keystrokes are interpreted as
///      Ctrl+shortcuts (undo, redo, cut, copy, paste) and the printable
///      character is swallowed.
///
/// RDP makes step 3 happen more often because the RDP client re-injects
/// modifier state on focus events and the up-event for the phantom
/// gets lost in flight.
///
/// Upstream tracking: flutter/flutter #154069, #177822, #87400, #78005.
/// Engine PR #27266 fixed a related case but was undone by PR #179136
/// in the 3.41 line.
///
/// **What this fix does:** on every key event that involves the right
/// Alt key, queues a `HardwareKeyboard.syncKeyboardState()` call. That
/// method asks the OS which keys are *physically* held and reconciles
/// the engine's pressed-set, so the phantom Ctrl is cleared
/// automatically. The sync is cheap (one IPC + diff) and idempotent.
///
/// Install once at app startup with `KeyboardRdpFix.install()`.
class KeyboardRdpFix {
  static bool _installed = false;
  static int _syncCount = 0;

  /// Number of times the keyboard state has been sync'd. Exposed for
  /// tests; not meant for production callers.
  @visibleForTesting
  static int get syncCount => _syncCount;

  @visibleForTesting
  static void resetForTest() {
    _syncCount = 0;
    if (_installed) {
      HardwareKeyboard.instance.removeHandler(_onKeyEvent);
      _installed = false;
    }
  }

  /// Install the keyboard handler. Safe to call multiple times — the
  /// second and further calls are no-ops.
  static void install() {
    if (_installed) return;
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    _installed = true;
    LoggerService().info('KeyboardRdpFix installed (AltGr-phantom-Ctrl workaround)', tag: 'KEYBOARD');
  }

  static bool _onKeyEvent(KeyEvent event) {
    // We only care about the right Alt key — that's the one that
    // triggers the phantom Ctrl behaviour. Catching both down AND up
    // covers the case where a user holds AltGr across focus changes
    // (common under RDP) and the up-event arrives "stale".
    if (event.physicalKey == PhysicalKeyboardKey.altRight) {
      _syncCount++;
      // Schedule the sync after this event is fully processed by other
      // handlers — clearing state mid-dispatch can confuse listeners.
      Future.microtask(_syncSafely);
    }
    // Never claim the event; we just observe.
    return false;
  }

  static Future<void> _syncSafely() async {
    try {
      await HardwareKeyboard.instance.syncKeyboardState();
    } catch (e) {
      // syncKeyboardState may throw on platforms that don't support it
      // (web, mobile). Swallow — this fix is Windows-only.
      LoggerService().debug('KeyboardRdpFix: syncKeyboardState skipped ($e)', tag: 'KEYBOARD');
    }
  }
}
