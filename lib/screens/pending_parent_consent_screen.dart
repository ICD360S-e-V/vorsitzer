import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../services/pending_parent_consent_service.dart';
import '../widgets/eastern.dart';

/// "Eltern-Liste" / "Părinți de contactat" — coadă de minori (16-17)
/// pe care wizardul mitglieder a marcat-o `waiting_for_parent_consent`
/// după ce au completat datele unui părinte / Sorgeberechtigter.
/// Vorsitzer sună, notează apelul, leagă părintele (când e gata) și
/// validează semnătura digitală.
class PendingParentConsentScreen extends StatefulWidget {
  final String currentMitgliedernummer;

  const PendingParentConsentScreen({
    super.key,
    required this.currentMitgliedernummer,
  });

  @override
  State<PendingParentConsentScreen> createState() => _PendingParentConsentScreenState();
}

class _PendingParentConsentScreenState extends State<PendingParentConsentScreen> {
  final _service = PendingParentConsentService();
  bool _loading = true;
  List<PendingParentConsent> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _service.list(callerMitgliedernummer: widget.currentMitgliedernummer);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Color _urgencyColor(int days) {
    if (days >= 5) return Colors.red.shade700;
    if (days >= 3) return Colors.orange.shade700;
    return Colors.green.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return SeasonalBackground(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Row(
              children: [
                Icon(Icons.family_restroom, size: 32, color: Colors.purple.shade700),
                const SizedBox(width: 12),
                const Text(
                  'Eltern-Liste · Minder­jährige',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_items.length}',
                    style: TextStyle(color: Colors.purple.shade900, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Aktualisieren',
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Jugendliche (16-17 J.), die das Onboarding gestartet und einen Elternteil '
              'als Sorgeberechtigte/n hinterlegt haben. Vorstand kontaktiert den Elternteil, '
              'protokolliert den Anruf und verknüpft das Konto nach dessen Anmeldung.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _items.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.5,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade300),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Keine wartenden Anmeldungen',
                                        style: TextStyle(color: Colors.grey.shade700, fontSize: 16, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Sobald ein/e Jugendliche/r das Onboarding mit Elternangaben\nabschließt, erscheint hier eine Karte.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12, height: 1.4),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => _buildCard(_items[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(PendingParentConsent it) {
    final urgency = _urgencyColor(it.daysWaiting);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: urgency.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Child row
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.purple.shade100,
                  child: Icon(Icons.child_care, color: Colors.purple.shade700, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.childFullName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(
                        '${it.mitgliedernummer} · ${it.age} J.${it.geburtsdatum != null ? " · geb. ${it.geburtsdatum}" : ""}',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: urgency.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    it.daysWaiting <= 0 ? 'heute' : 'seit ${it.daysWaiting} Tag${it.daysWaiting > 1 ? "en" : ""}',
                    style: TextStyle(color: urgency, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            // Parent row
            Row(
              children: [
                Icon(Icons.person, size: 18, color: Colors.indigo.shade600),
                const SizedBox(width: 6),
                Text('Elternteil zum Kontaktieren',
                    style: TextStyle(fontSize: 11, color: Colors.indigo.shade800, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    it.parentFullName.isEmpty ? '— (kein Name hinterlegt)' : it.parentFullName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text('Beziehung: ${it.relationLabel}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  if (it.parentTelefon != null && it.parentTelefon!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.phone, size: 14, color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text(it.parentTelefon!,
                            style: TextStyle(fontSize: 13, color: Colors.green.shade800, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: it.parentTelefon == null || it.parentTelefon!.trim().isEmpty
                      ? null
                      : () => _call(it.parentTelefon),
                  icon: const Icon(Icons.call, size: 16),
                  label: const Text('Anrufen', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openLogCall(it),
                  icon: const Icon(Icons.note_add, size: 16),
                  label: Text(
                    it.callsLogged > 0 ? 'Anruf notieren (${it.callsLogged})' : 'Anruf notieren',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openLinkWizard(it),
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('Elternteil verknüpfen', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.indigo.shade700),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openSignature(it),
                  icon: const Icon(Icons.draw, size: 16),
                  label: const Text('Unterschrift prüfen', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.deepPurple.shade700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLogCall(PendingParentConsent it) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _LogCallDialog(
        child: it,
        service: _service,
        callerMnr: widget.currentMitgliedernummer,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openLinkWizard(PendingParentConsent it) async {
    final linked = await showDialog<bool>(
      context: context,
      builder: (ctx) => _LinkParentDialog(
        child: it,
        service: _service,
      ),
    );
    if (linked == true) _load();
  }

  Future<void> _openSignature(PendingParentConsent it) async {
    await showDialog(
      context: context,
      builder: (ctx) => _SignatureDialog(
        child: it,
        service: _service,
        callerMnr: widget.currentMitgliedernummer,
      ),
    );
    _load();
  }
}

// ═══════════════════════════════════════════════════════
// MODAL 1: Notează apel
// ═══════════════════════════════════════════════════════
class _LogCallDialog extends StatefulWidget {
  final PendingParentConsent child;
  final PendingParentConsentService service;
  final String callerMnr;
  const _LogCallDialog({required this.child, required this.service, required this.callerMnr});
  @override
  State<_LogCallDialog> createState() => _LogCallDialogState();
}

class _LogCallDialogState extends State<_LogCallDialog> {
  String _result = 'nu_raspunde';
  final _durationC = TextEditingController(text: '5');
  final _noteC = TextEditingController();
  DateTime? _meetingAt;
  bool _saving = false;
  List<ParentCallLogEntry> _history = [];

  static const _resultOptions = [
    ('stabilit_intalnire', 'Termin vereinbart', Icons.event_available, Colors.green),
    ('stabilit_videoapel', 'Videoanruf vereinbart', Icons.videocam, Colors.teal),
    ('refuz', 'Abgelehnt', Icons.block, Colors.red),
    ('nu_raspunde', 'Nicht erreicht', Icons.phone_disabled, Colors.orange),
    ('gresit_numar', 'Falsche Nummer', Icons.error_outline, Colors.brown),
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _durationC.dispose();
    _noteC.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final h = await widget.service.listCalls(
      callerMitgliedernummer: widget.callerMnr,
      childUserId: widget.child.id,
    );
    if (mounted) setState(() => _history = h);
  }

  Future<void> _pickMeeting() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 2)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (t == null || !mounted) return;
    setState(() => _meetingAt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await widget.service.logCall(
      callerMitgliedernummer: widget.callerMnr,
      childUserId: widget.child.id,
      result: _result,
      durationMin: int.tryParse(_durationC.text.trim()) ?? 0,
      meetingScheduledAt: _meetingAt == null
          ? null
          : DateFormat('yyyy-MM-dd HH:mm:ss').format(_meetingAt!),
      note: _noteC.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speichern fehlgeschlagen'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: [
        Icon(Icons.note_add, color: Colors.indigo.shade700, size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text('Anruf protokollieren — ${widget.child.parentFullName}',
          style: const TextStyle(fontSize: 16))),
      ]),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Kind: ${widget.child.childFullName} (${widget.child.mitgliedernummer})',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            const SizedBox(height: 12),
            const Text('Ergebnis *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: _resultOptions.map((o) {
              final selected = _result == o.$1;
              return ChoiceChip(
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(o.$3, size: 14, color: selected ? Colors.white : o.$4),
                  const SizedBox(width: 4),
                  Text(o.$2, style: TextStyle(fontSize: 11, color: selected ? Colors.white : null)),
                ]),
                selected: selected,
                selectedColor: o.$4,
                showCheckmark: false,
                onSelected: (_) => setState(() => _result = o.$1),
              );
            }).toList()),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(
                controller: _durationC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Dauer (Min.)', isDense: true, border: OutlineInputBorder()),
              )),
              const SizedBox(width: 10),
              Expanded(child: InkWell(
                onTap: _pickMeeting,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Termin (optional)', isDense: true, border: OutlineInputBorder()),
                  child: Text(
                    _meetingAt == null
                        ? 'nicht gesetzt'
                        : DateFormat('dd.MM.yyyy HH:mm').format(_meetingAt!),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _noteC,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder()),
            ),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              Text('Bisherige Anrufe (${_history.length})',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              ..._history.map((h) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.history, size: 12, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    '${h.calledAt != null ? DateFormat('dd.MM.yy HH:mm').format(h.calledAt!) : ""} · ${h.resultLabel}${h.durationMin > 0 ? " · ${h.durationMin} min" : ""}${h.note != null && h.note!.isNotEmpty ? " — ${h.note}" : ""}',
                    style: const TextStyle(fontSize: 11),
                  )),
                ]),
              )),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 16),
          label: const Text('Speichern'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// MODAL 2: Wizard "Elternteil verknüpfen" (2 pași)
// ═══════════════════════════════════════════════════════
class _LinkParentDialog extends StatefulWidget {
  final PendingParentConsent child;
  final PendingParentConsentService service;
  const _LinkParentDialog({required this.child, required this.service});
  @override
  State<_LinkParentDialog> createState() => _LinkParentDialogState();
}

class _LinkParentDialogState extends State<_LinkParentDialog> {
  late TextEditingController _searchC;
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selected;
  bool _searching = false;
  bool _linking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill search with parent's phone or name from the hint.
    final seed = widget.child.parentTelefon?.trim().isNotEmpty == true
        ? widget.child.parentTelefon!
        : widget.child.parentFullName;
    _searchC = TextEditingController(text: seed);
    if (seed.isNotEmpty) _search();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _error = null;
    });
    final r = await widget.service.searchParent(_searchC.text.trim());
    if (!mounted) return;
    setState(() {
      _results = r;
      _searching = false;
      if (r.isEmpty) _error = 'Keine Treffer — Elternteil muss sich zuerst normal registrieren.';
    });
  }

  Future<void> _link() async {
    if (_selected == null) return;
    setState(() {
      _linking = true;
      _error = null;
    });
    final vormundTyp = PendingParentConsentService.deriveVormundTyp(widget.child.parentRelation);
    final res = await widget.service.linkExistingParent(
      childUserId: widget.child.id,
      parentUserId: _selected!['id'] is int ? _selected!['id'] : int.parse(_selected!['id'].toString()),
      vormundTyp: vormundTyp,
    );
    if (!mounted) return;
    if (res != null && res['success'] == true) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Verknüpfung erstellt — Status: ${res['data']?['new_role'] ?? 'aktualisiert'}'),
        backgroundColor: Colors.green,
      ));
    } else {
      setState(() {
        _linking = false;
        _error = res?['message']?.toString() ?? 'Verknüpfung fehlgeschlagen';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: [
        Icon(Icons.link, color: Colors.indigo.shade700, size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text('Elternteil verknüpfen — ${widget.child.childFullName}',
          style: const TextStyle(fontSize: 16))),
      ]),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Wizard-Hinweis: ${widget.child.parentFullName}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                Text('Beziehung: ${widget.child.relationLabel} · Tel.: ${widget.child.parentTelefon ?? "—"}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(
                controller: _searchC,
                decoration: const InputDecoration(
                  labelText: 'Suche (Telefon, Name oder M-Nr.)',
                  isDense: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onSubmitted: (_) => _search(),
              )),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _searching ? null : _search,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Suchen'),
              ),
            ]),
            const SizedBox(height: 12),
            if (_searching)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (_results.isEmpty && _error != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  Icon(Icons.warning_amber, color: Colors.orange.shade800, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: TextStyle(fontSize: 12, color: Colors.orange.shade900))),
                ]),
              )
            else
              ..._results.map((r) {
                final isSelected = _selected != null && _selected!['id'] == r['id'];
                final name = '${r['vorname'] ?? ''} ${r['nachname'] ?? ''}'.trim();
                return Card(
                  color: isSelected ? Colors.indigo.shade50 : null,
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: Colors.indigo.shade100,
                      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(color: Colors.indigo.shade700)),
                    ),
                    title: Text(name.isEmpty ? '(unbenannt)' : name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${r['mitgliedernummer'] ?? "—"}${r['telefon_mobil'] != null && r['telefon_mobil'].toString().isNotEmpty ? " · ${r['telefon_mobil']}" : ""}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle, color: Colors.green.shade700)
                        : null,
                    onTap: () => setState(() => _selected = r),
                  ),
                );
              }),
            if (_error != null && _results.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _linking ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton.icon(
          onPressed: (_selected == null || _linking) ? null : _link,
          icon: _linking
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.link, size: 16),
          label: const Text('Verknüpfen'),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade700),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// MODAL 3: Validare semnătură digitală
// ═══════════════════════════════════════════════════════
class _SignatureDialog extends StatefulWidget {
  final PendingParentConsent child;
  final PendingParentConsentService service;
  final String callerMnr;
  const _SignatureDialog({required this.child, required this.service, required this.callerMnr});
  @override
  State<_SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<_SignatureDialog> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await widget.service.getSignature(
      callerMitgliedernummer: widget.callerMnr,
      childUserId: widget.child.id,
    );
    if (!mounted) return;
    setState(() {
      _data = d;
      _loading = false;
    });
  }

  Future<void> _validate(int sigId) async {
    setState(() => _acting = true);
    final ok = await widget.service.validateSignature(
      callerMitgliedernummer: widget.callerMnr,
      signatureId: sigId,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Unterschrift validiert'),
        backgroundColor: Colors.green,
      ));
    } else {
      setState(() => _acting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Validierung fehlgeschlagen'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _reject(int sigId) async {
    final reasonC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unterschrift ablehnen'),
        content: TextField(
          controller: reasonC,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Begründung (Pflicht — wird dem Elternteil angezeigt)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Ablehnen'),
          ),
        ],
      ),
    );
    if (ok != true || reasonC.text.trim().isEmpty || !mounted) return;
    setState(() => _acting = true);
    final r = await widget.service.rejectSignature(
      callerMitgliedernummer: widget.callerMnr,
      signatureId: sigId,
      reason: reasonC.text.trim(),
    );
    if (!mounted) return;
    if (r) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Abgelehnt — Elternteil wird benachrichtigt'),
        backgroundColor: Colors.orange.shade700,
      ));
    } else {
      setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Colors.deepPurple;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: [
        Icon(Icons.draw, color: c.shade700, size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text('Unterschrift prüfen — ${widget.child.childFullName}',
          style: const TextStyle(fontSize: 16))),
      ]),
      content: SizedBox(
        width: 560,
        child: _loading
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            : _data == null
                ? const Padding(padding: EdgeInsets.all(16), child: Text('Keine Unterschrift hinterlegt.'))
                : _buildContent(c),
      ),
      actions: _data == null
          ? [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))]
          : _buildActions(),
    );
  }

  Widget _buildContent(MaterialColor c) {
    final sig = Map<String, dynamic>.from(_data!['signature'] as Map);
    final integ = Map<String, dynamic>.from(_data!['integrity'] as Map);
    final hashOk = integ['hash_ok'] == true;
    final countryOk = integ['country_ok'] == true;
    final manualReview = integ['manual_review_required'] == true;
    final autoValidated = sig['auto_validated'] == 1;
    final svg = (sig['signature_svg'] ?? '').toString();

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Integrity banner
        if (manualReview)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade300)),
            child: Row(children: [
              Icon(Icons.warning_amber, color: Colors.orange.shade800, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Manuelle Prüfung erforderlich — '
                '${!hashOk ? "Hash mismatch" : "Land außerhalb Whitelist (DE/AT/RO/UK/CH)"}',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.w600),
              )),
            ]),
          )
        else if (autoValidated)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade300)),
            child: Row(children: [
              Icon(Icons.verified, color: Colors.green.shade700, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Automatisch validiert (Hash OK + Land ${integ['country_iso'] ?? "—"} in Whitelist)',
                style: TextStyle(fontSize: 12, color: Colors.green.shade900, fontWeight: FontWeight.w600),
              )),
            ]),
          ),
        const SizedBox(height: 12),
        _row('Elternteil',
            '${sig['parent_vorname'] ?? ""} ${sig['parent_nachname'] ?? ""} (${sig['parent_mnr'] ?? "—"})'),
        _row('Signiert (UTC)', sig['signed_at_utc']?.toString() ?? '—'),
        _row('Signiert (lokal)', sig['signed_at_local']?.toString() ?? '—'),
        _row('Standort', '${sig['country_iso'] ?? "—"} (${sig['isp'] ?? "—"})'),
        _row('IP', sig['ip_address']?.toString() ?? '—'),
        _row('Gerät', sig['user_agent']?.toString() ?? '—', isMonospace: true),
        const Divider(),
        const Text('Einwilligungstext:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
          child: SelectableText(
            (sig['consent_text'] ?? '').toString(),
            style: const TextStyle(fontSize: 11, height: 1.4),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Unterschrift:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          height: 110,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
          child: svg.isEmpty
              ? Center(child: Text('— kein SVG hinterlegt', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)))
              : Center(child: Text('[SVG-Vorschau — ${svg.length} Bytes]\nÖffne dezvoltare browser für Render',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontStyle: FontStyle.italic))),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            Icon(
              hashOk ? Icons.check_circle : Icons.error,
              color: hashOk ? Colors.green.shade700 : Colors.red.shade700,
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(
              hashOk
                  ? 'Integrität: full_hash stimmt überein (sha256 neuberechnet OK)'
                  : 'INTEGRITÄT VERLETZT — Hash wurde manipuliert oder Datenfelder geändert',
              style: TextStyle(fontSize: 11, color: hashOk ? Colors.green.shade800 : Colors.red.shade800),
            )),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _buildActions() {
    if (_data == null) return [];
    final sig = Map<String, dynamic>.from(_data!['signature'] as Map);
    final sigId = sig['id'] is int ? sig['id'] : int.parse(sig['id'].toString());
    final alreadyValidated = sig['validated_at'] != null;
    final alreadyRejected = sig['rejected_at'] != null;

    return [
      TextButton(onPressed: _acting ? null : () => Navigator.pop(context), child: const Text('Schließen')),
      OutlinedButton.icon(
        onPressed: (_acting || alreadyRejected) ? null : () => _reject(sigId),
        icon: const Icon(Icons.close, size: 16),
        label: Text(alreadyRejected ? 'Bereits abgelehnt' : 'Ablehnen'),
        style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
      ),
      FilledButton.icon(
        onPressed: (_acting || alreadyValidated) ? null : () => _validate(sigId),
        icon: _acting
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check, size: 16),
        label: Text(alreadyValidated ? 'Bereits validiert' : 'Validieren'),
        style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
      ),
    ];
  }

  Widget _row(String label, String value, {bool isMonospace = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          Expanded(child: Text(
            value,
            style: TextStyle(fontSize: 11, fontFamily: isMonospace ? 'monospace' : null),
          )),
        ]),
      );
}
