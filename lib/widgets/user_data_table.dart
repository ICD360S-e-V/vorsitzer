import 'package:flutter/material.dart';
import '../models/user.dart';
import '../utils/role_helpers.dart';

/// Data table displaying all users with actions
class UserDataTable extends StatelessWidget {
  final List<User> users;
  final String currentMitgliedernummer;
  final Function(User) onUserTap;
  final Function(User, String) onStatusChange;
  final Function(User) onDelete;

  const UserDataTable({
    super.key,
    required this.users,
    required this.currentMitgliedernummer,
    required this.onUserTap,
    required this.onStatusChange,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const Center(child: Text('Keine Benutzer gefunden'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 20,
            headingRowColor: WidgetStateProperty.all(
              const Color(0xFF1a1a2e).withValues(alpha: 0.1),
            ),
            columns: const [
              DataColumn(label: Text('Nr.')),
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Rolle')),
              DataColumn(label: Text('Email')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Registriert')),
              DataColumn(label: Text('Aktionen')),
            ],
            rows: users.map((user) => _buildUserRow(user)).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _buildUserRow(User user) {
    final isCurrentUser = user.mitgliedernummer == currentMitgliedernummer;

    return DataRow(
      onSelectChanged: (selected) {
        if (selected == true) {
          onUserTap(user);
        }
      },
      cells: [
        DataCell(Text(user.mitgliedernummer)),
        DataCell(_buildNameCell(user)),
        DataCell(_buildRoleBadge(user.role)),
        DataCell(Text(user.email)),
        DataCell(_buildStatusBadge(user.status)),
        DataCell(Text(_formatDate(user.createdAt))),
        DataCell(_buildActions(user, isCurrentUser)),
      ],
    );
  }

  Widget _buildNameCell(User user) {
    IconData genderIcon;
    Color genderColor;
    switch (user.geschlecht) {
      case 'M':
        genderIcon = Icons.male;
        genderColor = Colors.blue;
      case 'W':
        genderIcon = Icons.female;
        genderColor = Colors.pink;
      case 'D':
        genderIcon = Icons.transgender;
        genderColor = Colors.purple;
      default:
        genderIcon = Icons.person;
        genderColor = Colors.grey;
    }

    // Birthday calculation
    Widget? birthdayWidget;
    if (user.geburtsdatum != null && user.geburtsdatum!.isNotEmpty) {
      try {
        final parts = user.geburtsdatum!.split('-');
        if (parts.length == 3) {
          final birthMonth = int.parse(parts[1]);
          final birthDay = int.parse(parts[2]);
          final now = DateTime.now();
          var nextBirthday = DateTime(now.year, birthMonth, birthDay);
          final isToday = nextBirthday.day == now.day && nextBirthday.month == now.month;
          if (!isToday && (nextBirthday.isBefore(now))) {
            nextBirthday = DateTime(now.year + 1, birthMonth, birthDay);
          }
          final daysLeft = isToday ? 0 : nextBirthday.difference(now).inDays;

          if (isToday) {
            birthdayWidget = Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(12)),
              child: const Text('🎂 Heute!', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
            );
          } else if (daysLeft <= 7) {
            birthdayWidget = Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
              child: Text('🎂 $daysLeft T.', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
            );
          } else if (daysLeft <= 30) {
            birthdayWidget = Text('🎂 $daysLeft T.', style: TextStyle(fontSize: 10, color: Colors.grey.shade600));
          } else {
            birthdayWidget = Text('🎂 $daysLeft T.', style: TextStyle(fontSize: 10, color: Colors.grey.shade400));
          }
        }
      } catch (_) {}
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(genderIcon, size: 18, color: genderColor),
      const SizedBox(width: 4),
      Text(user.name),
      if (birthdayWidget != null) ...[
        const SizedBox(width: 6),
        birthdayWidget,
      ],
    ]);
  }

  Widget _buildRoleBadge(String role) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: getRoleColor(role).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        getRoleText(role),
        style: TextStyle(
          color: getRoleColor(role),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: getStatusColor(status).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        getStatusText(status),
        style: TextStyle(
          color: getStatusColor(status),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildActions(User user, bool isCurrentUser) {
    return SizedBox(
      width: 160,
      child: isCurrentUser
          ? const Tooltip(
              message: 'Eigenes Konto - keine Aktionen möglich',
              child: Icon(Icons.lock, color: Colors.grey),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!user.isActive)
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    tooltip: 'Aktivieren',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: () => onStatusChange(user, 'active'),
                  ),
                if (user.isActive)
                  IconButton(
                    icon: const Icon(Icons.pause_circle, color: Colors.orange, size: 20),
                    tooltip: 'Sperren',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: () => onStatusChange(user, 'suspended'),
                  ),
                if (user.isActive)
                  IconButton(
                    icon: const Icon(Icons.exit_to_app, color: Colors.brown, size: 20),
                    tooltip: 'Kündigen',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: () => onStatusChange(user, 'gekuendigt'),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  tooltip: 'Löschen',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: () => onDelete(user),
                ),
              ],
            ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return '${date.day}.${date.month}.${date.year}';
  }
}
