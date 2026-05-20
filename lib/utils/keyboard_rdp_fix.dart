import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../services/logger_service.dart';

/// Workaround for a Flutter engine bug that bites hardest under Windows RDP:
///
///   1. User presses AltGr (PhysicalKeyboardKey.altRight).
///   2. Win32 dispatches a phantom `CtrlLeft down` immediately before
///      the real `AltRight down` (<2ms apart in practice).
///   3. User releases AltGr. The engine emits `AltRight up` — but NOT
///      the phantom `CtrlLeft up`.
///   4. The engine's `_pressedKeys` map now still contains `CtrlLeft`,
///      so the next time the user types Z / Y / X / C / V, those
///      keystrokes are interpreted as Ctrl+shortcuts (undo / redo /
///      cut / copy / paste) and the printable character is swallowed.
///
/// RDP makes step 3 happen more often because the RDP client re-injects
/// modifier state on focus events and the up-event for the phantom
/// can get lost in flight.
///
/// Upstream tracking: flutter/flutter #154069, #177822, #87400, #78005.
/// Engine PR #27266 fixed a related case; PR #179097 was a follow-up but
/// was reverted by PR #179136 in the 3.41 line — Flutter 3.41.x still
/// ships the bug.
///
/// **What this fix does:**
///   1. Track the timestamp of every `CtrlLeft down`.
///   2. When `AltRight down` arrives, if `CtrlLeft down` happened within
///      the last 10ms it must be the phantom — set a flag.
///   3. When `AltRight up` arrives and the flag is set, inject a
///      synthetic `KeyUpEvent` for CtrlLeft via the public
///      `HardwareKeyboard.handleKeyEvent` API. The engine processes it
///      exactly as if Win32 had finally sent the missing up event:
///      `_pressedKeys.remove(CtrlLeft)`. Phantom cleared.
///   4. The flag is cleared so a *real* CtrlLeft hold (followed later
///      by AltGr) is not affected.
///
/// Install once at app startup with `KeyboardRdpFix.install()`.
class KeyboardRdpFix {
  static bool _installed = false;

  /// Maximum gap between a phantom `CtrlLeft down` and the following
  /// `AltRight down`. Empirically <2ms; 10ms is a generous safety
  /// margin without enclosing realistic Ctrl-then-AltGr user input
  /// (a human can't press two distinct keys in under ~50ms).
  static const Duration _phantomWindow = Duration(milliseconds: 10);

  static DateTime? _lastCtrlLeftDown;
  static bool _phantomActive = false;
  static int _injectedCount = 0;

  /// Number of synthetic CtrlLeft up events injected since install.
  /// Exposed for tests; not meant for production callers.
  @visibleForTesting
  static int get injectedCount => _injectedCount;

  @visibleForTesting
  static bool get phantomActive => _phantomActive;

  @visibleForTesting
  static void resetForTest() {
    _injectedCount = 0;
    _lastCtrlLeftDown = null;
    _phantomActive = false;
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
    final phys = event.physicalKey;
    final now = DateTime.now();

    if (phys == PhysicalKeyboardKey.controlLeft) {
      if (event is KeyDownEvent) {
        _lastCtrlLeftDown = now;
      } else if (event is KeyUpEvent) {
        // Real CtrlLeft was released — no longer a candidate phantom.
        _lastCtrlLeftDown = null;
        _phantomActive = false;
      }
      return false;
    }

    if (phys == PhysicalKeyboardKey.altRight) {
      if (event is KeyDownEvent) {
        // Phantom semantics: CtrlLeft down arrived <10ms ago.
        if (_lastCtrlLeftDown != null &&
            now.difference(_lastCtrlLeftDown!) <= _phantomWindow) {
          _phantomActive = true;
        }
      } else if (event is KeyUpEvent) {
        if (_phantomActive && HardwareKeyboard.instance.isControlPressed) {
          _phantomActive = false;
          _lastCtrlLeftDown = null;
          // Inject synthetic CtrlLeft up to clear the phantom from the
          // engine's pressed-keys map. Public API, processed identically
          // to a real Win32 KeyUp.
          Future.microtask(() {
            try {
              HardwareKeyboard.instance.handleKeyEvent(KeyUpEvent(
                physicalKey: PhysicalKeyboardKey.controlLeft,
                logicalKey: LogicalKeyboardKey.controlLeft,
                timeStamp: Duration(milliseconds: now.millisecondsSinceEpoch),
              ));
              _injectedCount++;
            } catch (e) {
              // _assertEventIsRegular may throw if Ctrl was already
              // released by the time the microtask runs; that means
              // the phantom is already gone, no harm done.
              LoggerService().debug('KeyboardRdpFix: synthetic CtrlLeft up skipped ($e)', tag: 'KEYBOARD');
            }
          });
        }
      }
    }

    return false;
  }
}
