// Tests for KeyboardRdpFix — the workaround that clears the phantom
// Ctrl state under Windows RDP when AltGr (PhysicalKeyboardKey.altRight)
// is pressed/released.
//
// Strategy: drive the real HardwareKeyboard via handleKeyEvent and
// then assert on HardwareKeyboard.instance.isControlPressed AFTER the
// sequence. If the phantom Ctrl was correctly cleared, isControlPressed
// returns false. If the fix is broken, isControlPressed stays true.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/keyboard_rdp_fix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    KeyboardRdpFix.resetForTest();
    HardwareKeyboard.instance.clearState();
  });

  group('KeyboardRdpFix install', () {
    test('install() is idempotent', () {
      KeyboardRdpFix.install();
      KeyboardRdpFix.install();
      // Run a phantom sequence — should result in exactly 1 injection,
      // not 2 (proving handler isn't registered twice).
      _phantomSequence();
      // Wait for microtask
      return Future<void>.delayed(Duration.zero).then((_) {
        expect(KeyboardRdpFix.injectedCount, 1);
      });
    });
  });

  group('Phantom Ctrl detection + injection', () {
    test('phantom CtrlLeft+AltRight sequence clears Ctrl state on AltRight up', () async {
      KeyboardRdpFix.install();
      _phantomSequence();

      // Microtask must run to let the injection happen
      await Future<void>.delayed(Duration.zero);

      // The synthetic CtrlLeft up should have removed it from _pressedKeys
      expect(HardwareKeyboard.instance.isControlPressed, isFalse,
          reason: 'phantom Ctrl must be cleared after AltGr up');
      expect(KeyboardRdpFix.injectedCount, 1);
    });

    test('Real Ctrl+letter (user-held Ctrl) is NOT cleared by AltRight up', () async {
      KeyboardRdpFix.install();

      // User explicitly presses CtrlLeft (no AltRight following within window)
      _dispatchCtrlLeftDown();
      // Wait beyond phantom window
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Then user presses AltRight — this is NOT a phantom, real CtrlLeft is held
      _dispatchAltRightDown();
      _dispatchAltRightUp();
      await Future<void>.delayed(Duration.zero);

      // CtrlLeft is still really held — fix must NOT inject anything
      expect(HardwareKeyboard.instance.isControlPressed, isTrue,
          reason: 'real user-held Ctrl must remain pressed');
      expect(KeyboardRdpFix.injectedCount, 0);
    });

    test('AltRight alone (no preceding Ctrl) does nothing', () async {
      KeyboardRdpFix.install();
      _dispatchAltRightDown();
      _dispatchAltRightUp();
      await Future<void>.delayed(Duration.zero);

      expect(KeyboardRdpFix.injectedCount, 0);
      expect(HardwareKeyboard.instance.isControlPressed, isFalse);
    });

    test('CtrlLeft up before AltRight up cancels phantom flag', () async {
      KeyboardRdpFix.install();
      // Phantom-looking sequence
      _dispatchCtrlLeftDown();
      _dispatchAltRightDown();
      // But user actually released Ctrl normally before releasing AltRight
      _dispatchCtrlLeftUp();
      _dispatchAltRightUp();
      await Future<void>.delayed(Duration.zero);

      // No injection (real Ctrl was already up; no phantom to clear)
      expect(KeyboardRdpFix.injectedCount, 0);
      expect(HardwareKeyboard.instance.isControlPressed, isFalse);
    });

    test('AltLeft does NOT trigger fix (only right-Alt is buggy)', () async {
      KeyboardRdpFix.install();
      _dispatchCtrlLeftDown();
      // AltLeft instead of AltRight
      HardwareKeyboard.instance.handleKeyEvent(KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.altLeft,
        logicalKey: LogicalKeyboardKey.altLeft,
        timeStamp: const Duration(milliseconds: 1),
      ));
      HardwareKeyboard.instance.handleKeyEvent(KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.altLeft,
        logicalKey: LogicalKeyboardKey.altLeft,
        timeStamp: const Duration(milliseconds: 2),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(KeyboardRdpFix.injectedCount, 0);
    });
  });
}

// ----- helpers ---------------------------------------------------------------

void _phantomSequence() {
  // Reproduces the exact Win32 sequence under AltGr:
  //   1. Phantom CtrlLeft down (instantaneous, <2ms before AltRight)
  //   2. Real AltRight down
  //   3. Real AltRight up — phantom CtrlLeft up is NEVER sent by Win32
  _dispatchCtrlLeftDown();
  _dispatchAltRightDown();
  _dispatchAltRightUp();
}

void _dispatchCtrlLeftDown() => HardwareKeyboard.instance.handleKeyEvent(KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.controlLeft,
  logicalKey: LogicalKeyboardKey.controlLeft,
  timeStamp: const Duration(milliseconds: 1),
));

void _dispatchCtrlLeftUp() => HardwareKeyboard.instance.handleKeyEvent(KeyUpEvent(
  physicalKey: PhysicalKeyboardKey.controlLeft,
  logicalKey: LogicalKeyboardKey.controlLeft,
  timeStamp: const Duration(milliseconds: 2),
));

void _dispatchAltRightDown() => HardwareKeyboard.instance.handleKeyEvent(KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.altRight,
  logicalKey: LogicalKeyboardKey.altRight,
  timeStamp: const Duration(milliseconds: 3),
));

void _dispatchAltRightUp() => HardwareKeyboard.instance.handleKeyEvent(KeyUpEvent(
  physicalKey: PhysicalKeyboardKey.altRight,
  logicalKey: LogicalKeyboardKey.altRight,
  timeStamp: const Duration(milliseconds: 4),
));
