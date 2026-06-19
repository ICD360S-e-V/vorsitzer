import 'package:flutter/material.dart';
import '../utils/anonymous_chat_helper.dart';

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
  final bool hasActiveScheduled;

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
    this.hasActiveScheduled = false,
  });

  @override
  Widget build(BuildContext context) {
    final mitgliedernummer = conversation['mitgliedernummer']?.toString()
        ?? conversation['member_nr']?.toString()
        ?? '';
    final isAnonymous = AnonymousChatHelper.isAnonymousConversation(conversation);
    final anonMeta = isAnonymous ? AnonymousChatHelper.metadataFrom(conversation) : null;
    final displayName = isAnonymous
        ? AnonymousChatHelper.displayName(conversation)
        : (mitgliedernummer.isNotEmpty ? mitgliedernummer : 'Unbekannt');

    final container = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAnonymous ? const Color(0xFFE65100) : const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isAnonymous ? const Color(0xFFFFB74D) : Colors.blue,
            child: Icon(
              isAnonymous ? Icons.help_outline : Icons.person,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (isAnonymous)
                  const Text(
                    'Vizitator anonim',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
              ],
            ),
          ),
          // Member info — disabled for anonymous (no profile to view)
          if (!isAnonymous)
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.lightBlueAccent),
              onPressed: onInfoTap,
              tooltip: 'Mitglied-Informationen',
            ),
          // Aufgaben — only for real members (anonymous users have no record/Akte)
          if (!isAnonymous && onAufgabenTap != null)
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
          // Scheduled messages — anonymous chat is reactive only, no auto-replies
          if (!isAnonymous && isOpen && onScheduledSettings != null)
            IconButton(
              icon: Icon(
                Icons.schedule_send,
                color: hasActiveScheduled ? Colors.greenAccent.shade400 : Colors.amber.shade300,
              ),
              onPressed: onScheduledSettings,
              tooltip: hasActiveScheduled
                  ? 'Automatische Nachrichten (aktiv)'
                  : 'Automatische Nachrichten',
            ),
          // Mute toggle (works for both)
          if (isOpen)
            IconButton(
              icon: Icon(
                isMuted ? Icons.notifications_off : Icons.notifications_active,
                color: isMuted ? Colors.orange : Colors.grey.shade400,
              ),
              onPressed: onMuteToggle,
              tooltip: isMuted ? 'Stummschaltung aufheben' : 'Stummschalten',
            ),
          // Voice/video call — text-only for anonymous visitors by design
          if (!isAnonymous && isOpen && canCall)
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

    if (!isAnonymous) return container;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        container,
        const SizedBox(height: 6),
        _AnonymousMetadataPanel(metadata: anonMeta),
      ],
    );
  }
}

class _AnonymousMetadataPanel extends StatelessWidget {
  final AnonymousMetadata? metadata;
  const _AnonymousMetadataPanel({this.metadata});

  String _relative(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return 'gerade eben';
    if (d.inMinutes < 60) return 'vor ${d.inMinutes} Min';
    if (d.inHours < 24) return 'vor ${d.inHours} Std';
    if (d.inDays < 7) return 'vor ${d.inDays} Tag${d.inDays > 1 ? 'en' : ''}';
    return 'vor ${(d.inDays / 7).floor()} Wochen';
  }

  @override
  Widget build(BuildContext context) {
    final m = metadata;
    final rows = <Widget>[];

    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(icon, size: 14, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: Text(label,
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.w600)),
              ),
              Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
            ],
          ),
        );

    if (m?.language != null) rows.add(row(Icons.language, 'Gewählte Sprache', m!.languageLabel));
    if (m?.platform != null) {
      final v = m!.appVersion != null ? ' (v${m.appVersion})' : '';
      rows.add(row(Icons.devices, 'System', '${m.platform}$v'));
    }
    if (m?.lastActive != null) {
      rows.add(row(Icons.access_time, 'Aktiv', _relative(m!.lastActive!)));
    }
    if (m?.firstOpenAt != null) {
      rows.add(row(Icons.event, 'Erste Nutzung', _relative(m!.firstOpenAt!)));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade300, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...rows,
          if (rows.isNotEmpty) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Kein Mitglied — keine sensiblen Dokumente senden, keine persönlichen Daten erfragen.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.red.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
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
