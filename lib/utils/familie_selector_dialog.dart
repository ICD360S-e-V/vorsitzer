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
      onLinkExistingKind: () async {
        Navigator.of(selCtx).pop();
        if (!context.mounted) return;
        final linked = await showDialog<bool>(
          context: context,
          builder: (_) => LinkExistingMitgliedDialog(
            apiService: apiService,
            vormundUser: user,
          ),
        );
        if (linked == true && context.mounted) {
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
      onUnlinkKind: (kindMap) async {
        final kindId = kindMap['id'] is int ? kindMap['id'] as int : int.tryParse(kindMap['id'].toString());
        final kindName = '${kindMap['vorname'] ?? ''} ${kindMap['nachname'] ?? ''}'.trim();
        final typ = kindMap['vormund_typ']?.toString() ?? '';
        if (kindId == null) return;
        final isFamily = typ == 'familienangehoeriger';
        final confirm = await showDialog<bool>(
          context: selCtx,
          builder: (cctx) => AlertDialog(
            title: Row(children: [
              Icon(Icons.link_off, color: isFamily ? Colors.red : Colors.orange, size: 22),
              const SizedBox(width: 8),
              const Expanded(child: Text('Verknuepfung loesen?', style: TextStyle(fontSize: 16))),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('"$kindName" wird vom Vormund-Konto getrennt. Das Konto bleibt aktiv und kann eigenstaendig genutzt werden.', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              if (isFamily)
                Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.shade200)),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      'Dieser Eintrag ist als FAMILIENANGEHOERIGER markiert. Familienverknuepfungen sollten normalerweise nicht geloest werden.',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade900),
                    )),
                  ]),
                ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(cctx, false), child: const Text('Abbrechen')),
              ElevatedButton(
                onPressed: () => Navigator.pop(cctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: isFamily ? Colors.red : Colors.orange, foregroundColor: Colors.white),
                child: const Text('Verknuepfung loesen'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        final res = await apiService.unlinkVormund(kindId);
        if (!context.mounted) return;
        if (res['success'] == true) {
          Navigator.of(selCtx).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Verknuepfung geloest — Konto bleibt aktiv'), backgroundColor: Colors.green),
          );
          openMitgliedProfile(
            context: context,
            apiService: apiService,
            user: user,
            adminMitgliedernummer: adminMitgliedernummer,
            onUpdated: onUpdated,
          );
          onUpdated();
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message']?.toString() ?? 'Fehler beim Loesen'), backgroundColor: Colors.red),
          );
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
  final VoidCallback? onLinkExistingKind;
  final void Function(Map<String, dynamic> kind)? onUnlinkKind;

  const FamilieSelectorDialog({
    super.key,
    required this.activeUser,
    required this.vormund,
    required this.kinder,
    required this.onProfileSelected,
    this.onAddKind,
    this.onLinkExistingKind,
    this.onUnlinkKind,
  });

  @override
  Widget build(BuildContext context) {
    final entries = <_FamilieEntry>[];

    if (vormund != null) {
      entries.add(_FamilieEntry.fromMap(vormund!, isVormund: true));
    }
    entries.add(_FamilieEntry.fromActiveUser(activeUser));
    for (final k in kinder) {
      entries.add(_FamilieEntry.fromMap(k, sourceRaw: k));
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
                subtitle: Text('Neues Konto unter diesem Vormund anlegen',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                trailing: Icon(Icons.add_circle_outline, size: 20, color: Colors.pink.shade400),
                onTap: onAddKind,
              ),
            ],
            if (onLinkExistingKind != null) ...[
              Divider(height: 1, color: Colors.grey.shade200),
              ListTile(
                key: const Key('link-existing-kind-tile'),
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo.shade50,
                  child: Icon(Icons.link, color: Colors.indigo.shade700, size: 22),
                ),
                title: Text('Bestehendes Mitglied verknuepfen',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo.shade700)),
                subtitle: Text('Bestehendes Konto als Kind / Betreutes Mitglied verknuepfen (Familie, Ehrenamt, Betreuung)',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                trailing: Icon(Icons.person_search, size: 20, color: Colors.indigo.shade400),
                onTap: onLinkExistingKind,
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
    // Is this entry a kind of the activeUser (eligible for unlink)?
    final isKindEntry = e.sourceRaw != null && e.sourceRaw!.containsKey('vormund_typ');
    final vormundTyp = (e.sourceRaw?['vormund_typ'] ?? '').toString();
    final canUnlink = isKindEntry && onUnlinkKind != null;

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
          if (vormundTyp.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: _vormundTypColor(vormundTyp).shade50, borderRadius: BorderRadius.circular(4)),
              child: Text(
                _vormundTypLabel(vormundTyp),
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _vormundTypColor(vormundTyp).shade800),
              ),
            ),
        ],
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (canUnlink)
          IconButton(
            tooltip: vormundTyp == 'familienangehoeriger'
                ? 'Familienverknuepfung loesen (Konto bleibt aktiv)'
                : 'Verknuepfung loesen (Konto bleibt aktiv)',
            icon: Icon(Icons.link_off, size: 18, color: Colors.red.shade300),
            onPressed: () => onUnlinkKind!(e.sourceRaw!),
          ),
        const Icon(Icons.chevron_right, size: 20),
      ]),
      onTap: () => onProfileSelected(e.toUser(fallback: activeUser)),
    );
  }

  static MaterialColor _vormundTypColor(String typ) {
    switch (typ) {
      case 'familienangehoeriger': return Colors.pink;
      case 'ehrenamtlich': return Colors.green;
      case 'vorlaeufig': return Colors.orange;
      case 'vorsorgevollmacht': return Colors.purple;
      case 'berufsbetreuer': return Colors.blue;
      case 'sorgeberechtigter': return Colors.teal;
      default: return Colors.grey;
    }
  }

  static String _vormundTypLabel(String typ) {
    switch (typ) {
      case 'familienangehoeriger': return 'Familie';
      case 'ehrenamtlich': return 'Ehrenamt';
      case 'vorlaeufig': return 'vorlaeufig';
      case 'vorsorgevollmacht': return 'Vollmacht';
      case 'berufsbetreuer': return 'Berufsbetreuer';
      case 'sorgeberechtigter': return 'Sorgeberecht.';
      default: return typ;
    }
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
  DateTime? _geburtsdatum;
  bool _saving = false;

  @override
  void dispose() {
    _vornameC.dispose();
    _nachnameC.dispose();
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
      // Email + password are auto-generated server-side for jugendmitglied —
      // child has no login; parent manages everything.
      final res = await widget.apiService.adminRegisterMember(
        name: fullName,
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
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                  child: Row(children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      'Mitgliedernummer (J + 5 Ziffern) wird automatisch generiert. '
                      'Das Konto ist verwaltet — kein Login durch das Kind moeglich.',
                      style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
                    )),
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
  final Map<String, dynamic>? sourceRaw;

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
    this.sourceRaw,
  }) : age = calculateAge(geburtsdatum);

  factory _FamilieEntry.fromMap(Map<String, dynamic> m, {bool isVormund = false, Map<String, dynamic>? sourceRaw}) {
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
      sourceRaw: sourceRaw,
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

// ============================================================================
// LinkExistingMitgliedDialog — search + link an existing member as Kind
// ============================================================================

class LinkExistingMitgliedDialog extends StatefulWidget {
  final ApiService apiService;
  final User vormundUser;
  const LinkExistingMitgliedDialog({super.key, required this.apiService, required this.vormundUser});
  @override
  State<LinkExistingMitgliedDialog> createState() => _LinkExistingMitgliedDialogState();
}

class _LinkExistingMitgliedDialogState extends State<LinkExistingMitgliedDialog> {
  final _searchC = TextEditingController();
  List<Map<String, dynamic>> _candidates = [];
  Map<String, dynamic>? _selected;
  String _vormundTyp = 'familienangehoeriger';
  bool _searching = false;
  bool _linking = false;

  static const _typLabels = {
    'familienangehoeriger': 'Familienangehoeriger (Eltern / Kind / Geschwister)',
    'sorgeberechtigter': 'Sorgeberechtigter (§ 1626 BGB — Eltern minderjaehriger Kinder)',
    'ehrenamtlich': 'Ehrenamtliche Betreuung (§ 1816 Abs. 4 BGB — Freunde, Nachbarn)',
    'vorlaeufig': 'Vorlaeufige Betreuung (§ 300 FamFG — Gerichtsbeschluss, max. 1 Jahr)',
    'vorsorgevollmacht': 'Vorsorgevollmacht (§ 1820 BGB — vorher festgelegt)',
    'berufsbetreuer': 'Berufsbetreuung (§ 1818 BGB — beruflich, bezahlt)',
  };

  @override
  void dispose() { _searchC.dispose(); super.dispose(); }

  Future<void> _search() async {
    final q = _searchC.text.trim();
    if (q.length < 2) return;
    setState(() { _searching = true; _candidates = []; _selected = null; });
    try {
      final res = await widget.apiService.searchMembersForLink(query: q, excludeVormundId: widget.vormundUser.id);
      if (res['success'] == true) {
        _candidates = (res['candidates'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      }
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _doLink({bool forceOverwrite = false}) async {
    if (_selected == null) return;
    setState(() => _linking = true);
    try {
      final targetId = _selected!['id'] is int ? _selected!['id'] as int : int.tryParse(_selected!['id'].toString())!;
      final res = await widget.apiService.linkVormund(
        targetUserId: targetId,
        vormundUserId: widget.vormundUser.id,
        vormundTyp: _vormundTyp,
        forceOverwrite: forceOverwrite,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Verknuepft (neue Rolle: ${res['new_role'] ?? 'mitglied'})'),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context, true);
      } else if (res['requires_confirmation'] == true || res['existing_vormund_id'] != null) {
        // Confirm umtragen
        final confirm = await showDialog<bool>(context: context, builder: (cctx) => AlertDialog(
          title: Row(children: [Icon(Icons.swap_horiz, color: Colors.orange.shade700, size: 22), const SizedBox(width: 8), const Text('Vormund umtragen?', style: TextStyle(fontSize: 16))]),
          content: Text(
            'Mitglied hat bereits einen Vormund (Typ: ${res['existing_vormund_typ'] ?? '—'}). '
            'Soll die alte Verknuepfung geloest und auf ${widget.vormundUser.vorname ?? widget.vormundUser.name} umgetragen werden?',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(cctx, false), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: () => Navigator.pop(cctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white), child: const Text('Umtragen')),
          ],
        ));
        if (confirm == true && mounted) {
          _doLink(forceOverwrite: true);
          return;
        }
        setState(() => _linking = false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['message']?.toString() ?? 'Verknuepfung fehlgeschlagen'),
          backgroundColor: Colors.red,
        ));
        setState(() => _linking = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
        setState(() => _linking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.person_search, color: Colors.indigo.shade700, size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text('Verknuepfen mit ${widget.vormundUser.vorname ?? widget.vormundUser.name}', style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis)),
      ]),
      content: SizedBox(width: 520, height: 520, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: TextField(controller: _searchC,
            decoration: InputDecoration(
              hintText: 'ID / Mitgliedernummer / Name suchen...',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (_) => _search(),
          )),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _searching ? null : _search,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white),
            child: _searching ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Suchen'),
          ),
        ]),
        const SizedBox(height: 10),
        Expanded(child: _candidates.isEmpty
          ? Center(child: Text(_searching ? '' : 'Geben Sie Name oder Nummer ein und suchen.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)))
          : ListView.separated(
              itemCount: _candidates.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (lctx, i) {
                final c = _candidates[i];
                final isSel = _selected != null && _selected!['id'] == c['id'];
                final age = c['age'];
                final hasExistingVormund = c['has_existing_vormund'] == true;
                final isVormundOfOthers = c['is_vormund_of_others'] == true;
                return ListTile(
                  dense: true,
                  selected: isSel,
                  selectedTileColor: Colors.indigo.shade50,
                  leading: CircleAvatar(
                    backgroundColor: isVormundOfOthers ? Colors.red.shade50 : Colors.grey.shade100,
                    child: Icon(isVormundOfOthers ? Icons.block : Icons.person, color: isVormundOfOthers ? Colors.red.shade400 : Colors.grey.shade700, size: 18),
                  ),
                  title: Text('${c['vorname'] ?? ''} ${c['nachname'] ?? ''}'.trim(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Wrap(spacing: 6, children: [
                    Text(c['mitgliedernummer']?.toString() ?? '#${c['id']}', style: const TextStyle(fontSize: 10)),
                    if (age != null) Text('· $age J.', style: const TextStyle(fontSize: 10)),
                    if (c['role'] != null) Text('· ${c['role']}', style: const TextStyle(fontSize: 10)),
                    if (hasExistingVormund) Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Text('hat Vormund', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange.shade900))),
                    if (isVormundOfOthers) Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Text('ist Vormund', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red.shade900))),
                  ]),
                  trailing: isVormundOfOthers
                    ? Tooltip(message: 'Kann nicht verknuepft werden — ist selbst Vormund anderer Mitglieder', child: Icon(Icons.do_not_disturb, color: Colors.red.shade400, size: 18))
                    : (isSel ? Icon(Icons.check_circle, color: Colors.indigo.shade700, size: 20) : const Icon(Icons.radio_button_unchecked, size: 18)),
                  onTap: isVormundOfOthers ? null : () => setState(() => _selected = c),
                );
              },
            )),
        if (_selected != null) ...[
          const Divider(height: 16),
          Text('Verknuepfungstyp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _vormundTyp, isExpanded: true,
            decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _typLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _vormundTyp = v ?? _vormundTyp),
          ),
          if (_selected!['age'] != null && (_selected!['age'] as int) >= 18 && _vormundTyp == 'familienangehoeriger')
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(
              '! Volljaehriges Mitglied wird als Familienangehoeriger verknuepft — bei Betreuungs-/Vollmacht-Faellen besseren Typ waehlen.',
              style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontStyle: FontStyle.italic),
            )),
        ],
      ])),
      actions: [
        TextButton(onPressed: _linking ? null : () => Navigator.pop(context, false), child: const Text('Abbrechen')),
        ElevatedButton.icon(
          onPressed: (_selected == null || _linking) ? null : () => _doLink(),
          icon: _linking ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.link, size: 18),
          label: const Text('Verknuepfen'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white),
        ),
      ],
    );
  }
}
