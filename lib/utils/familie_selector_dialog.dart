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

  // Selectorul apare INTOTDEAUNA — chiar daca nu sunt kinder, vrem ca user-ul
  // sa vada Konto-ul activ + butonul + pentru a adauga un copil.
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
      onAddKind: () async {
        Navigator.of(selCtx).pop();
        if (!context.mounted) return;
        final created = await showDialog<bool>(
          context: context,
          builder: (_) => NeuesKindDialog(
            apiService: apiService,
            vormundUserId: user.id,
          ),
        );
        if (created == true && context.mounted) {
          // Re-trigger the selector with refreshed data
          openMitgliedProfile(
            context: context,
            apiService: apiService,
            user: user,
            adminMitgliedernummer: adminMitgliedernummer,
            onUpdated: onUpdated,
          );
          onUpdated();
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
  final VoidCallback? onAddKind;

  const FamilieSelectorDialog({
    super.key,
    required this.activeUser,
    required this.vormund,
    required this.kinder,
    required this.onProfileSelected,
    this.onAddKind,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: entries.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (_, i) => _buildEntryTile(context, entries[i]),
              ),
            ),
            if (onAddKind != null) ...[
              Divider(height: 1, color: Colors.grey.shade300),
              ListTile(
                key: const Key('add-kind-tile'),
                leading: CircleAvatar(
                  backgroundColor: Colors.pink.shade50,
                  child: Icon(Icons.add, color: Colors.pink.shade700, size: 22),
                ),
                title: Text('Neues Kind hinzufuegen',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.pink.shade700)),
                subtitle: Text('Jugendmitglied unter diesem Vormund-Konto anlegen',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                trailing: Icon(Icons.add_circle_outline, size: 20, color: Colors.pink.shade400),
                onTap: onAddKind,
              ),
            ],
          ],
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

/// Form-dialog pentru creare cont copil (jugendmitglied) sub un vormund.
/// Returneaza `true` daca user-ul a fost creat cu succes.
class NeuesKindDialog extends StatefulWidget {
  final ApiService apiService;
  final int vormundUserId;
  const NeuesKindDialog({
    super.key,
    required this.apiService,
    required this.vormundUserId,
  });
  @override
  State<NeuesKindDialog> createState() => _NeuesKindDialogState();
}

class _NeuesKindDialogState extends State<NeuesKindDialog> {
  final _formKey = GlobalKey<FormState>();
  final _vornameC = TextEditingController();
  final _nachnameC = TextEditingController();
  final _emailC = TextEditingController();
  final _passwordC = TextEditingController();
  DateTime? _geburtsdatum;
  bool _saving = false;

  @override
  void dispose() {
    _vornameC.dispose();
    _nachnameC.dispose();
    _emailC.dispose();
    _passwordC.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_geburtsdatum == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Geburtsdatum wählen'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final vorname = _vornameC.text.trim();
      final nachname = _nachnameC.text.trim();
      final fullName = '$vorname $nachname'.trim();
      final res = await widget.apiService.adminRegisterMember(
        name: fullName,
        email: _emailC.text.trim(),
        password: _passwordC.text,
        role: 'jugendmitglied',
        vormundUserId: widget.vormundUserId,
        geburtsdatum: _formatDate(_geburtsdatum!),
        vorname: vorname,
        nachname: nachname,
      );

      if (!mounted) return;
      if (res['success'] == true) {
        final mnr = res['user']?['mitgliedernummer']?.toString() ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kind angelegt: $fullName ($mnr)'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message']?.toString() ?? 'Anlage fehlgeschlagen'), backgroundColor: Colors.red),
        );
        setState(() => _saving = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.child_care, color: Colors.pink.shade700, size: 22),
        const SizedBox(width: 8),
        const Expanded(child: Text('Neues Kind anlegen', style: TextStyle(fontSize: 16))),
      ]),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('kind-vorname'),
                  controller: _vornameC,
                  decoration: const InputDecoration(labelText: 'Vorname', isDense: true, border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().length < 2) ? 'mindestens 2 Zeichen' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('kind-nachname'),
                  controller: _nachnameC,
                  decoration: const InputDecoration(labelText: 'Nachname', isDense: true, border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().length < 2) ? 'mindestens 2 Zeichen' : null,
                ),
                const SizedBox(height: 10),
                InkWell(
                  key: const Key('kind-geburtsdatum'),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime(now.year - 10, now.month, now.day),
                      firstDate: DateTime(now.year - 30),
                      lastDate: now,
                      locale: const Locale('de'),
                    );
                    if (picked != null) setState(() => _geburtsdatum = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Geburtsdatum', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_today, size: 18)),
                    child: Text(_geburtsdatum == null ? 'auswählen...' : _formatDate(_geburtsdatum!), style: TextStyle(color: _geburtsdatum == null ? Colors.grey.shade600 : Colors.black)),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('kind-email'),
                  controller: _emailC,
                  decoration: const InputDecoration(labelText: 'E-Mail (z. B. kind@familie.de)', isDense: true, border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'erforderlich';
                    if (!v.contains('@') || !v.contains('.')) return 'ungültige E-Mail';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('kind-password'),
                  controller: _passwordC,
                  decoration: const InputDecoration(labelText: 'Initialer Passwort (mind. 6 Zeichen)', isDense: true, border: OutlineInputBorder()),
                  obscureText: true,
                  validator: (v) => (v == null || v.length < 6) ? 'mindestens 6 Zeichen' : null,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                  child: Row(children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Mitgliedernummer wird automatisch (J + 5 Ziffern) generiert.',
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade900))),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 16),
          label: Text(_saving ? 'Speichert...' : 'Anlegen'),
          style: FilledButton.styleFrom(backgroundColor: Colors.pink.shade600),
        ),
      ],
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
