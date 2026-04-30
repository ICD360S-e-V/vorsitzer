import 'package:flutter/material.dart';

/// Header for the selected conversation showing member info
class ConversationHeader extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final bool canCall;
  final bool isOpen;
  final bool isMuted;
  final VoidCallback onCall;
  final VoidCallback onClose;
  final VoidCallback onMuteToggle;
  final VoidCallback? onScheduledSettings;
  final VoidCallback? onInfoTap;
  final VoidCallback? onAufgabenTap;
  final int aufgabenTotal;
  final int aufgabenOffen;

  const ConversationHeader({
    super.key,
    required this.conversation,
    required this.canCall,
    required this.isOpen,
    required this.onCall,
    required this.onClose,
    this.isMuted = false,
    required this.onMuteToggle,
    this.onScheduledSettings,
    this.onInfoTap,
    this.onAufgabenTap,
    this.aufgabenTotal = 0,
    this.aufgabenOffen = 0,
  });

  @override
  Widget build(BuildContext context) {
    final mitgliedernummer = conversation['mitgliedernummer']?.toString()
        ?? conversation['member_nr']?.toString()
        ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.blue,
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              mitgliedernummer.isNotEmpty ? mitgliedernummer : 'Unbekannt',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          // Member info button
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.lightBlueAccent),
            onPressed: onInfoTap,
            tooltip: 'Mitglied-Informationen',
          ),
          // Aufgaben button with badge
          if (onAufgabenTap != null)
            Stack(
              children: [
                IconButton(
                  icon: Icon(Icons.checklist, color: aufgabenOffen > 0 ? Colors.orange.shade300 : Colors.grey.shade400),
                  onPressed: onAufgabenTap,
                  tooltip: 'Aufgaben',
                ),
                if (aufgabenTotal > 0)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: aufgabenOffen > 0 ? Colors.orange : Colors.green,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${aufgabenTotal - aufgabenOffen}/$aufgabenTotal',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          // Scheduled messages settings
          if (isOpen && onScheduledSettings != null)
            IconButton(
              icon: Icon(Icons.schedule_send, color: Colors.amber.shade300),
              onPressed: onScheduledSettings,
              tooltip: 'Automatische Nachrichten',
            ),
          // Mute toggle button
          if (isOpen)
            IconButton(
              icon: Icon(
                isMuted ? Icons.notifications_off : Icons.notifications_active,
                color: isMuted ? Colors.orange : Colors.grey.shade400,
              ),
              onPressed: onMuteToggle,
              tooltip: isMuted ? 'Stummschaltung aufheben' : 'Stummschalten',
            ),
          // Call button (only when idle and connected)
          if (isOpen && canCall)
            IconButton(
              icon: const Icon(Icons.call, color: Colors.green),
              onPressed: onCall,
              tooltip: 'Benutzer anrufen',
            ),
          if (isOpen)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: onClose,
              tooltip: 'Konversation schließen',
            ),
        ],
      ),
    );
  }
}

/// A stat badge for showing counts (e.g., Open: 5, Total: 10)
class StatBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const StatBadge({
    super.key,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Connection status indicator
class ConnectionStatus extends StatelessWidget {
  final bool isConnected;

  const ConnectionStatus({
    super.key,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isConnected ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? 'Online' : 'Offline',
            style: TextStyle(
              color: isConnected ? Colors.green.shade700 : Colors.orange.shade700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Typing indicator
class TypingIndicator extends StatelessWidget {
  final String userName;

  const TypingIndicator({
    super.key,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$userName schreibt...',
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
