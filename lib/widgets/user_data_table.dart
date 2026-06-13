import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/member_activity.dart';
import '../utils/role_helpers.dart';

/// Data table displaying all users with actions.
///
/// Layout: tree-style — Vormund members appear as top-level rows; their
/// linked kinder (full members with vormund_user_id pointing back) appear
/// indented directly below their Vormund, with a soft background and
/// Verknüpfungstyp badge. Orphan members (vormund_user_id set but parent
/// not in the current filtered list) fall through as normal top-level rows.
class UserDataTable extends StatelessWidget {
  final List<User> users;
  final String currentMitgliedernummer;
  final Function(User) onUserTap;
  final Function(User, String) onStatusChange;
  final Function(User) onDelete;
  final Map<String, MemberActivity> memberActivity;

  const UserDataTable({
    super.key,
    required this.users,
    required this.currentMitgliedernummer,
    required this.onUserTap,
    required this.onStatusChange,
    required this.onDelete,
    this.memberActivity = const {},
  });

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const Center(child: Text('Keine Benutzer gefunden'));
    }

    // Group kinder by their vormund id
    final byVormund = <int, List<User>>{};
    for (final u in users) {
      if (u.vormundUserId != null) {
        byVormund.putIfAbsent(u.vormundUserId!, () => []).add(u);
      }
    }

    // Set of ids that are children of someone in the current list
    final shownAsChildren = <int>{};
    for (final entries in byVormund.entries) {
      // only count as child if the parent is also in the list
      final parentInList = users.any((x) => x.id == entries.key);
      if (parentInList) {
        for (final k in entries.value) {
          shownAsChildren.add(k.id);
        }
      }
    }

    final rows = <DataRow>[];
    for (final u in users) {
      if (shownAsChildren.contains(u.id)) continue; // shown later under parent
      final kids = byVormund[u.id] ?? const <User>[];
      rows.add(_buildUserRow(u, kidCount: kids.length, isChild: false));
      // Sort kinder by birthdate (oldest first), nulls last
      final sortedKids = [...kids]..sort((a, b) {
        final ag = a.geburtsdatum ?? '9999-99-99';
        final bg = b.geburtsdatum ?? '9999-99-99';
        return ag.compareTo(bg);
      });
      for (final k in sortedKids) {
        rows.add(_buildUserRow(k, kidCount: 0, isChild: true));
      }
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
              DataColumn(label: Text('Diese Woche')),
              DataColumn(label: Text('Aktionen')),
            ],
            rows: rows,
          ),
        ),
      ),
    );
  }

  DataRow _buildUserRow(User user, {required int kidCount, required bool isChild}) {
    final isCurrentUser = user.mitgliedernummer == currentMitgliedernummer;
    final bg = isChild ? Colors.indigo.shade50.withValues(alpha: 0.4) : null;

    return DataRow(
      color: bg != null ? WidgetStateProperty.all(bg) : null,
      onSelectChanged: (selected) {
        if (selected == true) {
          onUserTap(user);
        }
      },
      cells: [
        DataCell(_buildMnrCell(user, isChild: isChild)),
        DataCell(_buildNameCell(user, kidCount: kidCount, isChild: isChild)),
        DataCell(_buildRoleBadge(user.role)),
        DataCell(Text(user.email)),
        DataCell(_buildStatusBadge(user.status)),
        DataCell(Text(_formatDate(user.createdAt))),
        DataCell(_buildWeekIndicators(memberActivity[user.mitgliedernummer] ?? MemberActivity.empty)),
        DataCell(_buildActions(user, isCurrentUser)),
      ],
    );
  }

  Widget _buildMnrCell(User user, {required bool isChild}) {
    if (!isChild) return Text(user.mitgliedernummer);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, right: 6),
        child: Text('└─', style: TextStyle(color: Colors.indigo.shade300, fontWeight: FontWeight.bold)),
      ),
      Text(user.mitgliedernummer, style: TextStyle(fontSize: 12, color: Colors.indigo.shade900)),
    ]);
  }

  Widget _buildWeekIndicators(MemberActivity activity) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _indicator(Icons.event, 'Termin diese Woche', activity.hasTermin),
      const SizedBox(width: 4),
      _indicator(Icons.confirmation_number, 'Ticket diese Woche', activity.hasTicket),
      const SizedBox(width: 4),
      _indicator(Icons.repeat, 'Routine-Aufgabe diese Woche', activity.hasRoutine),
    ]);
  }

  Widget _indicator(IconData icon, String tooltip, bool active) {
    final color = active ? Colors.green.shade600 : Colors.grey.shade300;
    return Tooltip(
      message: active ? tooltip : '$tooltip — keine',
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color, width: 1.2),
        ),
        child: Icon(icon, size: 13, color: color),
      ),
    );
  }

  Widget _buildNameCell(User user, {required int kidCount, required bool isChild}) {
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

    return Padding(
      padding: EdgeInsets.only(left: isChild ? 16 : 0),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(genderIcon, size: 18, color: genderColor),
        const SizedBox(width: 4),
        if (isChild) ...[
          Icon(Icons.subdirectory_arrow_right, size: 12, color: Colors.indigo.shade300),
          const SizedBox(width: 2),
        ],
        Text(user.name, style: TextStyle(fontWeight: isChild ? FontWeight.w500 : FontWeight.w600, color: isChild ? Colors.indigo.shade900 : null)),
        if (isChild && (user.vormundTyp?.isNotEmpty ?? false)) ...[
          const SizedBox(width: 6),
          _vormundTypBadge(user.vormundTyp!),
        ],
        if (kidCount > 0) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: 'Hat $kidCount verknüpfte${kidCount == 1 ? 's' : ''} Konto${kidCount == 1 ? '' : 'en'} unter sich (Kinder / Betreute)',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.pink.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.pink.shade200, width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.family_restroom, size: 11, color: Colors.pink.shade700),
                const SizedBox(width: 3),
                Text('+$kidCount', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.pink.shade800)),
              ]),
            ),
          ),
        ],
        if (birthdayWidget != null) ...[
          const SizedBox(width: 6),
          birthdayWidget,
        ],
      ]),
    );
  }

  Widget _vormundTypBadge(String typ) {
    final (label, color) = switch (typ) {
      'familienangehoeriger' => ('Familie', Colors.pink),
      'sorgeberechtigter'    => ('Sorgeberecht.', Colors.teal),
      'ehrenamtlich'         => ('Ehrenamt', Colors.green),
      'vorlaeufig'           => ('vorläufig', Colors.orange),
      'vorsorgevollmacht'    => ('Vollmacht', Colors.purple),
      'berufsbetreuer'       => ('Berufsbetreuer', Colors.blue),
      _                      => (typ, Colors.grey),
    };
    return Tooltip(
      message: 'Verknüpfungstyp: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: color.shade200, width: 1)),
        child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color.shade800)),
      ),
    );
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
