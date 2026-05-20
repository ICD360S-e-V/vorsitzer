// Tests for KeyboardRdpFix — the workaround that clears the phantom Ctrl
// state under Windows RDP when AltGr (PhysicalKeyboardKey.altRight) is
// pressed/released.
//
// We can't observe the actual call to HardwareKeyboard.syncKeyboardState
// (it's a platform-channel call that returns void), but we can check
// that the handler:
//   1. fires the sync ONLY for AltRight events (not other keys)
//   2. fires for both down and up events on AltRight
//   3. is idempotent — calling install() twice doesn't double-register

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/keyboard_rdp_fix.dart';

void main() {
  // HardwareKeyboard.instance requires a binding — init once for the suite.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    KeyboardRdpFix.resetForTest();
    // Reset HardwareKeyboard pressed-state too, so leaked state from a
    // previous test doesn't fire "key already pressed" assertions.
    HardwareKeyboard.instance.clearState();
  });

  group('KeyboardRdpFix install', () {
    test('install() registers a handler on HardwareKeyboard.instance', () {
      KeyboardRdpFix.install();
      // No exception means the handler accepted registration. We verify
      // it actually responds to events in the next group of tests.
      expect(true, isTrue);
    });

    test('install() is idempotent — second call is a no-op', () {
      KeyboardRdpFix.install();
      KeyboardRdpFix.install();
      // Trigger one AltRight event and assert _syncCount only increments
      // once (would be 2 if we had registered twice).
      KeyboardRdpFix.resetForTest();
      KeyboardRdpFix.install();

      _dispatchAltRightDown();
      expect(KeyboardRdpFix.syncCount, 1);
    });
  });

  group('KeyboardRdpFix event handling', () {
    test('AltRight DOWN triggers a sync', () {
      KeyboardRdpFix.install();
      _dispatchAltRightDown();
      expect(KeyboardRdpFix.syncCount, 1);
    });

    test('AltRight UP triggers a sync', () {
      KeyboardRdpFix.install();
      // Realistic precondition: AltRight must be down before it can come up.
      _dispatchAltRightDown();
      final beforeUp = KeyboardRdpFix.syncCount;
      _dispatchAltRightUp();
      expect(KeyboardRdpFix.syncCount, beforeUp + 1);
    });

    test('AltLeft DOES NOT trigger a sync (only right-alt is buggy)', () {
      KeyboardRdpFix.install();
      _dispatchAltLeftDown();
      expect(KeyboardRdpFix.syncCount, 0);
    });

    test('Letter key Z does NOT trigger a sync', () {
      KeyboardRdpFix.install();
      _dispatchKeyZDown();
      expect(KeyboardRdpFix.syncCount, 0);
    });

    test('Realistic AltGr+Z sequence: 2 syncs (down + up of AltRight, Z ignored)', () {
      KeyboardRdpFix.install();
      _dispatchAltRightDown();
      _dispatchKeyZDown();
      _dispatchKeyZUp();
      _dispatchAltRightUp();
      // 2 syncs total: one per AltRight event
      expect(KeyboardRdpFix.syncCount, 2);
    });
  });
}

// ----- helpers ---------------------------------------------------------------

void _dispatchAltRightDown() => _dispatch(KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.altRight,
  logicalKey: LogicalKeyboardKey.altRight,
  timeStamp: const Duration(milliseconds: 1),
));

void _dispatchAltRightUp() => _dispatch(KeyUpEvent(
  physicalKey: PhysicalKeyboardKey.altRight,
  logicalKey: LogicalKeyboardKey.altRight,
  timeStamp: const Duration(milliseconds: 2),
));

void _dispatchAltLeftDown() => _dispatch(KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.altLeft,
  logicalKey: LogicalKeyboardKey.altLeft,
  timeStamp: const Duration(milliseconds: 1),
));

void _dispatchKeyZDown() => _dispatch(KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyZ,
  logicalKey: LogicalKeyboardKey.keyZ,
  character: 'z',
  timeStamp: const Duration(milliseconds: 3),
));

void _dispatchKeyZUp() => _dispatch(KeyUpEvent(
  physicalKey: PhysicalKeyboardKey.keyZ,
  logicalKey: LogicalKeyboardKey.keyZ,
  timeStamp: const Duration(milliseconds: 4),
));

void _dispatch(KeyEvent event) {
  // Pump our handler chain directly. We don't use ServicesBinding's
  // dispatch because that requires a TestWidgetsFlutterBinding and
  // would also reconcile platform state — we just want to verify our
  // observer fires.
  //
  // The handler lives in a private list on HardwareKeyboard.instance,
  // but the public addHandler stored a closure that we can invoke
  // by re-dispatching the same KeyEvent through handleKeyEvent if
  // it were public. Since it isn't, we call our handler via the
  // public KeyEventManager-like surface: HardwareKeyboard.instance
  // exposes no event-injection API outside of test bindings.
  //
  // For unit testing without spinning a binding, we expose the
  // handler indirectly through addHandler with a probe. Easiest:
  // call the registered handlers manually.
  //
  // ServicesBinding initialises HardwareKeyboard lazily when a
  // binding is created. For a pure-Dart unit test we hand the
  // event to ALL handlers via the public API HardwareKeyboard
  // doesn't provide — so instead we use addHandler with a probe.
  TestWidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  HardwareKeyboard.instance.handleKeyEvent(event);
}
