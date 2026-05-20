import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../widgets/user_details_dialog.dart';
import 'role_helpers.dart';

/// Entry point for opening a member's profile from any "click on member" UI.
///
/// Flow:
///   1. Fetch the member's family info (vormund + kinder) via getUserDetails.
///   2. If the member has no family connections -> open UserDetailsDialog
///      directly (no extra friction for childless members).
///   3. Otherwise -> show a small selector listing the parent and each child
///      (with child icons). The picked profile then opens in UserDetailsDialog.
///
/// This replaces direct `showDialog(builder: (_) => UserDetailsDialog(...))`
/// calls so the family-selector UX is consistent everywhere.
Future<void> openMitgliedProfile({
  required BuildContext context,
  required ApiService apiService,
  required User user,
  required String adminMitgliedernummer,
  required VoidCallback onUpdated,
}) async {
  Map<String, dynamic>? vormund;
  List<Map<String, dynamic>> kinder = [];

  try {
    final result = await apiService.getUserDetails(user.id);
    if (result['success'] == true) {
      vormund = result['vormund'] is Map
          ? Map<String, dynamic>.from(result['vormund'] as Map)
          : null;
      kinder = List<Map<String, dynamic>>.from(result['kinder'] ?? []);
    }
  } catch (_) {
    // On error, fall through to direct open — the dialog itself will surface
    // the failure when it tries to load.
  }

  if (!context.mounted) return;

  if (vormund == null && kinder.isEmpty) {
    _openDetailsDirectly(context, apiService, user, adminMitgliedernummer, onUpdated);
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (selCtx) => FamilieSelectorDialog(
      activeUser: user,
      vormund: vormund,
      kinder: kinder,
      onProfileSelected: (targetUser) {
        Navigator.of(selCtx).pop();
        if (context.mounted) {
          _openDetailsDirectly(context, apiService, targetUser, adminMitgliedernummer, onUpdated);
        }
      },
    ),
  );
}

void _openDetailsDirectly(
  BuildContext context,
  ApiService apiService,
  User user,
  String adminMitgliedernummer,
  VoidCallback onUpdated,
) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UserDetailsDialog(
      user: user,
      apiService: apiService,
      adminMitgliedernummer: adminMitgliedernummer,
      onUpdated: onUpdated,
    ),
  );
}

/// Selector dialog: lists the member + their vormund (if child) + their
/// kinder (if parent) so the admin can pick which profile to open.
class FamilieSelectorDialog extends StatelessWidget {
  final User activeUser;
  final Map<String, dynamic>? vormund;
  final List<Map<String, dynamic>> kinder;
  final void Function(User target) onProfileSelected;

  const FamilieSelectorDialog({
    super.key,
    required this.activeUser,
    required this.vormund,
    required this.kinder,
    required this.onProfileSelected,
  });

  @override
  Widget build(BuildContext context) {
    final entries = <_FamilieEntry>[];

    if (vormund != null) {
      entries.add(_FamilieEntry.fromMap(vormund!, isVormund: true));
    }
    entries.add(_FamilieEntry.fromActiveUser(activeUser));
    for (final k in kinder) {
      entries.add(_FamilieEntry.fromMap(k));
    }

    return AlertDialog(
      title: Row(children: [
        Icon(Icons.family_restroom, color: Colors.indigo.shade700, size: 22),
        const SizedBox(width: 8),
        const Expanded(child: Text('Welches Profil öffnen?', style: TextStyle(fontSize: 16))),
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      content: SizedBox(
        width: 420,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: entries.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
          itemBuilder: (_, i) => _buildEntryTile(context, entries[i]),
        ),
      ),
    );
  }

  Widget _buildEntryTile(BuildContext context, _FamilieEntry e) {
    final isChild = isJugendmitglied(e.role);
    final color = isChild ? Colors.pink : (e.isVormund ? Colors.amber.shade700 : Colors.blue);
    final icon = isChild
        ? Icons.child_care
        : (e.isVormund ? Icons.supervisor_account : Icons.person);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (color is MaterialColor ? color.shade100 : Colors.amber.shade100),
        child: Icon(icon, color: (color is MaterialColor ? color.shade700 : color), size: 22),
      ),
      title: Text(e.displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(e.mitgliedernummer, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          if (e.age != null)
            Text('· ${e.age} J.', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          Text('· ${getRoleText(e.role)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          if (e.isVormund)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(4)),
              child: Text('Vormund', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => onProfileSelected(e.toUser(fallback: activeUser)),
    );
  }
}

class _FamilieEntry {
  final int id;
  final String mitgliedernummer;
  final String? vorname;
  final String? nachname;
  final String? name;
  final String? email;
  final String role;
  final String status;
  final String? geburtsdatum;
  final int? age;
  final bool isVormund;

  _FamilieEntry({
    required this.id,
    required this.mitgliedernummer,
    required this.role,
    required this.status,
    this.vorname,
    this.nachname,
    this.name,
    this.email,
    this.geburtsdatum,
    this.isVormund = false,
  }) : age = calculateAge(geburtsdatum);

  factory _FamilieEntry.fromMap(Map<String, dynamic> m, {bool isVormund = false}) {
    return _FamilieEntry(
      id: m['id'] is int ? m['id'] as int : int.tryParse(m['id'].toString()) ?? 0,
      mitgliedernummer: m['mitgliedernummer']?.toString() ?? '',
      vorname: m['vorname']?.toString(),
      nachname: m['nachname']?.toString(),
      name: m['name']?.toString(),
      email: m['email']?.toString(),
      role: m['role']?.toString() ?? (isVormund ? 'mitglied' : 'jugendmitglied'),
      status: m['status']?.toString() ?? 'active',
      geburtsdatum: m['geburtsdatum']?.toString(),
      isVormund: isVormund,
    );
  }

  factory _FamilieEntry.fromActiveUser(User u) {
    return _FamilieEntry(
      id: u.id,
      mitgliedernummer: u.mitgliedernummer,
      vorname: u.vorname,
      nachname: u.nachname,
      name: u.name,
      email: u.email,
      role: u.role,
      status: u.status,
      geburtsdatum: u.geburtsdatum,
    );
  }

  String get displayName {
    final composed = [vorname ?? '', nachname ?? ''].where((p) => p.isNotEmpty).join(' ').trim();
    return composed.isNotEmpty ? composed : (name ?? 'Unbekannt');
  }

  /// Convert this entry to a User for showing the details dialog.
  /// If id matches fallback (= same user we already loaded), returns fallback
  /// to avoid re-parsing.
  User toUser({required User fallback}) {
    if (id == fallback.id) return fallback;
    return User.fromJson({
      'id': id,
      'mitgliedernummer': mitgliedernummer,
      'email': email ?? '',
      'name': name ?? displayName,
      'vorname': vorname,
      'nachname': nachname,
      'role': role,
      'status': status,
      'geburtsdatum': geburtsdatum,
    });
  }
}
