import 'package:flutter/material.dart';

/// A single stat card showing a metric with icon
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Stats bar showing user statistics
class UserStatsBar extends StatelessWidget {
  final int totalUsers;
  final int activeUsers;
  final int newUsers;
  final int suspendedUsers;
  final int gekuendigtUsers;

  const UserStatsBar({
    super.key,
    required this.totalUsers,
    required this.activeUsers,
    required this.newUsers,
    required this.suspendedUsers,
    this.gekuendigtUsers = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          StatCard(
            title: 'Gesamt Benutzer',
            value: totalUsers.toString(),
            icon: Icons.people,
            color: Colors.blue,
          ),
          StatCard(
            title: 'Aktiv',
            value: activeUsers.toString(),
            icon: Icons.check_circle,
            color: Colors.green,
          ),
          StatCard(
            title: 'Neu',
            value: newUsers.toString(),
            icon: Icons.fiber_new,
            color: Colors.amber,
          ),
          StatCard(
            title: 'Gesperrt',
            value: suspendedUsers.toString(),
            icon: Icons.pause_circle,
            color: Colors.orange,
          ),
          StatCard(
            title: 'Gekündigt',
            value: gekuendigtUsers.toString(),
            icon: Icons.exit_to_app,
            color: Colors.brown,
          ),
        ],
      ),
    );
  }
}
