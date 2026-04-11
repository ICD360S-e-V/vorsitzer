import 'package:flutter/material.dart';

/// A single conversation item in the admin chat list
class ConversationListItem extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final bool isSelected;
  final bool hasActiveCall;
  final bool isOnline;
  final bool isMuted;
  final Map<String, dynamic>? networkData;
  final VoidCallback onTap;

  const ConversationListItem({
    super.key,
    required this.conversation,
    required this.isSelected,
    required this.hasActiveCall,
    required this.isOnline,
    required this.onTap,
    this.isMuted = false,
    this.networkData,
  });

  @override
  Widget build(BuildContext context) {
    final unreadCount = conversation['unread_count'] ?? 0;
    final status = conversation['status'] ?? 'open';
    final memberName = conversation['member_name'] ?? 'Unbekannt';
    final lastSeenStr = conversation['last_seen'] as String?;

    return Container(
      color: isSelected ? const Color(0xFF1a1a2e).withValues(alpha: 0.1) : null,
      child: ListTile(
        dense: true,
        leading: _buildAvatar(memberName, status),
        title: _buildTitle(memberName, unreadCount),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Network status row (connection type, ping, battery)
            if (networkData != null || hasActiveCall)
              _buildNetworkRow(),
            // Last seen (offline only)
            if (!isOnline && !hasActiveCall && lastSeenStr != null)
              Text(
                _formatLastSeen(lastSeenStr),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildNetworkRow() {
    if (hasActiveCall) {
      return Text(
        'Im Anruf...',
        style: TextStyle(fontSize: 11, color: Colors.green.shade700),
      );
    }

    final connType = networkData?['connection_type']?.toString();
    final latency = networkData?['latency_ms'];
    final batteryLevel = networkData?['battery_level'];
    final batteryState = networkData?['battery_state']?.toString();

    if (connType == null && latency == null && batteryLevel == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Connection type icon
          if (connType != null) ...[
            Icon(
              connType.toLowerCase().contains('wifi')
                  ? Icons.wifi
                  : connType.toLowerCase().contains('ethernet')
                      ? Icons.lan
                      : Icons.signal_cellular_alt,
              size: 11,
              color: Colors.grey.shade600,
            ),
            const SizedBox(width: 2),
          ],
          // Ping
          if (latency != null) ...[
            Text(
              '${latency}ms',
              style: TextStyle(
                fontSize: 9,
                color: latency <= 50
                    ? Colors.green.shade700
                    : latency <= 150
                        ? Colors.orange.shade700
                        : Colors.red.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
          ],
          // Battery
          if (batteryLevel != null && batteryLevel >= 0) ...[
            Icon(
              batteryState == 'charging' || batteryState == 'full'
                  ? Icons.battery_charging_full
                  : batteryLevel <= 15
                      ? Icons.battery_alert
                      : batteryLevel <= 50
                          ? Icons.battery_3_bar
                          : Icons.battery_full,
              size: 11,
              color: batteryLevel <= 15
                  ? Colors.red.shade700
                  : batteryLevel <= 30
                      ? Colors.orange.shade700
                      : Colors.grey.shade600,
            ),
            const SizedBox(width: 1),
            Text(
              '$batteryLevel%',
              style: TextStyle(
                fontSize: 9,
                color: batteryLevel <= 15
                    ? Colors.red.shade700
                    : batteryLevel <= 30
                        ? Colors.orange.shade700
                        : Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Format last seen timestamp to human-readable German text
  String _formatLastSeen(String lastSeenStr) {
    try {
      final lastSeen = DateTime.parse(lastSeenStr);
      final now = DateTime.now();
      final difference = now.difference(lastSeen);

      if (difference.inSeconds < 60) {
        return 'zuletzt aktiv vor ${difference.inSeconds} Sekunden';
      } else if (difference.inMinutes < 60) {
        final minutes = difference.inMinutes;
        return 'zuletzt aktiv vor $minutes ${minutes == 1 ? "Minute" : "Minuten"}';
      } else if (difference.inHours < 24) {
        final hours = difference.inHours;
        return 'zuletzt aktiv vor $hours ${hours == 1 ? "Stunde" : "Stunden"}';
      } else if (difference.inDays < 7) {
        final days = difference.inDays;
        return 'zuletzt aktiv vor $days ${days == 1 ? "Tag" : "Tagen"}';
      } else if (difference.inDays < 30) {
        final weeks = (difference.inDays / 7).floor();
        return 'zuletzt aktiv vor $weeks ${weeks == 1 ? "Woche" : "Wochen"}';
      } else if (difference.inDays < 365) {
        final months = (difference.inDays / 30).floor();
        return 'zuletzt aktiv vor $months ${months == 1 ? "Monat" : "Monaten"}';
      } else {
        final years = (difference.inDays / 365).floor();
        return 'zuletzt aktiv vor $years ${years == 1 ? "Jahr" : "Jahren"}';
      }
    } catch (e) {
      return '';
    }
  }

  Widget _buildAvatar(String memberName, String status) {
    return Stack(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: hasActiveCall ? Colors.green.shade100 : Colors.blue.shade100,
          child: hasActiveCall
              ? Icon(Icons.call, color: Colors.green.shade700, size: 20)
              : Text(
                  memberName.isNotEmpty ? memberName[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        // Show online/offline indicator (green for online, red for offline)
        if (!hasActiveCall)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTitle(String memberName, int unreadCount) {
    return Row(
      children: [
        Expanded(
          child: Text(
            memberName,
            style: TextStyle(
              fontWeight: isSelected || unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isMuted)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.notifications_off, size: 14, color: Colors.orange.shade700),
          ),
        if (unreadCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$unreadCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}
