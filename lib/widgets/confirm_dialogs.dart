import 'package:flutter/material.dart';
import '../models/user.dart';

String _statusLabel(String status) {
  switch (status) {
    case 'active':
      return 'Aktiv';
    case 'suspended':
      return 'Gesperrt';
    case 'gekuendigt':
      return 'Gekündigt';
    default:
      return status;
  }
}

/// Shows a confirmation dialog for changing user status
/// Returns true if confirmed, false otherwise
Future<bool> showStatusChangeDialog({
  required BuildContext context,
  required User user,
  required String newStatus,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Status ändern'),
      content: Text(
        'Möchten Sie den Status von "${user.name}" auf "${_statusLabel(newStatus)}" ändern?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: newStatus == 'active'
                ? Colors.green
                : newStatus == 'suspended'
                    ? Colors.orange
                    : newStatus == 'gekuendigt'
                        ? Colors.brown
                        : Colors.red,
          ),
          child: const Text('Bestätigen'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shows a confirmation dialog for deleting a user
/// Returns true if confirmed, false otherwise
Future<bool> showDeleteUserDialog({
  required BuildContext context,
  required User user,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Benutzer löschen'),
      content: Text(
        'Möchten Sie "${user.name}" (${user.mitgliedernummer}) wirklich löschen?\n\nDiese Aktion kann nicht rückgängig gemacht werden!',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Löschen'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shows a generic confirmation dialog
/// Returns true if confirmed, false otherwise
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String content,
  String cancelText = 'Abbrechen',
  String confirmText = 'Bestätigen',
  Color? confirmColor,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancelText),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: confirmColor != null
              ? ElevatedButton.styleFrom(backgroundColor: confirmColor)
              : null,
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}
