import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Secure clipboard helper - auto-clears clipboard after 30 seconds
/// to prevent other apps from reading sensitive data (passwords, PINs, etc.)
class ClipboardHelper {
  static Timer? _clearTimer;

  /// Copy text to clipboard and auto-clear after 30 seconds.
  /// Shows a SnackBar with the label and a countdown hint.
  static void copy(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));

    // Cancel any previous timer
    _clearTimer?.cancel();

    // Auto-clear after 30 seconds
    _clearTimer = Timer(const Duration(seconds: 30), () {
      Clipboard.setData(const ClipboardData(text: ''));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label kopiert! Zwischenablage wird in 30s gelöscht.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
