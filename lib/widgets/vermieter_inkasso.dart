import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'vermieter_dokumente.dart';
import 'vermieter_korrespondenz.dart';

/// Inkasso unterhalb eines MIETVERTRAGS:
///
///   Zuständige Inkasso  ·  Vorfall
///                            └─ Aktenzeichen
///                                 └─ Details · Korrespondenz · Vollmacht · Akteneinsicht
///
/// ⚠️ Der Vorfall ist die Ebene, die es beim Vertrag (Strom) nicht gibt:
/// Ein Mietverhältnis erzeugt über die Jahre mehrere getrennte Vorgänge —
/// Mietrückstand 2024, Nebenkostennachzahlung 2025 — und jeder davon kann
/// beim Inkassobüro unter mehreren Aktenzeichen laufen. Ohne diese Ebene
/// lägen alle Aktenzeichen in einem Topf, und niemand könnte mehr sagen,
/// welche Forderung zu welchem Vorgang gehört.
///
/// ⚠️ Seit 20.08.2026 hängt das Ganze am MIETVERTRAG, nicht mehr am
/// Vermieter. Eine Forderung entsteht aus einer bestimmten Wohnung — bei
/// zwei Wohnungen desselben Vermieters wäre sonst nicht mehr zu sagen,
/// aus welcher.
class VermieterInkassoTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int mietvertragId;
  final String vertragBezeichnung;

  const VermieterInkassoTab({
    super.key,
    required this.apiService,
    required this.userId,
    required this.mietvertragId,
    required this.vertragBezeichnung,
  });

  @override
  State<VermieterInkassoTab> createState() => _VermieterInkassoTabState();
}

const _kStatusFarben = <String, MaterialColor>{
  'offen': Colors.orange,
  'in_bearbeitung': Colors.blue,
  'vergleich': Colors.teal,
  'ratenzahlung': Colors.indigo,
  'widerspruch': Colors.deepOrange,
  'gerichtlich': Colors.red,
  'abgeschlossen': Colors.green,
  'zurueckgewiesen': Colors.grey,
};

const _kStatusNamen = <String, String>{
  'offen': 'Offen',
  'in_bearbeitung': 'In Bearbeitung',
  'vergleich': 'Vergleich',
  'ratenzahlung': 'Ratenzahlung',
  'widerspruch': 'Widerspruch',
  'gerichtlich': 'Gerichtlich',
  'abgeschlossen': 'Abgeschlossen',
  'zurueckgewiesen': 'Zurückgewiesen',
};

String _datumDeutsch(Object? iso) {
  final s = iso?.toString() ?? '';
  if (s.length < 10) return '';
  return '${s.substring(8, 10)}.${s.substring(5, 7)}.${s.substring(0, 4)}';
}

Widget _statusChip(String? status) {
  final s = status ?? 'offen';
  final f = _kStatusFarben[s] ?? Colors.grey;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: f.shade50, borderRadius: BorderRadius.circular(12)),
    child: Text(_kStatusNamen[s] ?? s,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: f.shade800)),
  );
}

/// Ein Datumsfeld, das ISO an den Server gibt und deutsch anzeigt.
Widget _datumFeld({
  required BuildContext context,
  required TextEditingController controller,
  required String label,
  required VoidCallback onChanged,
}) {
  return TextField(
    controller: controller,
    readOnly: true,
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      prefixIcon: const Icon(Icons.calendar_today, size: 16),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.clear, size: 16),
              onPressed: () {
                controller.clear();
                onChanged();
              },
            ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    ),
    onTap: () async {
      final d = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(controller.text) ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2040),
        locale: const Locale('de'),
      );
      if (d != null) {
        controller.text = d.toIso8601String().substring(0, 10);
        onChanged();
      }
    },
  );
}

class _VermieterInkassoTabState extends State<VermieterInkassoTab> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Container(
          color: Colors.purple.shade50,
          child: TabBar(
            labelColor: Colors.purple.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.purple.shade700,
            tabs: const [
              Tab(icon: Icon(Icons.business_center, size: 16), text: 'Zuständige Inkasso'),
              Tab(icon: Icon(Icons.folder_special, size: 16), text: 'Vorfall'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(children: [
            _ZustaendigeInkasso(
              apiService: widget.apiService,
              mietvertragId: widget.mietvertragId,
            ),
            _VorfallListe(
              apiService: widget.apiService,
              userId: widget.userId,
              mietvertragId: widget.mietvertragId,
            ),
          ]),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Zuständige Inkasso — Firma aus der Datenbank + eigener Ansprechpartner
// ══════════════════════════════════════════════════════════════════════

class _ZustaendigeInkasso extends StatefulWidget {
  final ApiService apiService;
  final int mietvertragId;
  const _ZustaendigeInkasso({required this.apiService, required this.mietvertragId});

  @override
  State<_ZustaendigeInkasso> createState() => _ZustaendigeInkassoState();
}

class _ZustaendigeInkassoState extends State<_ZustaendigeInkasso> {
  List<Map<String, dynamic>> _firmen = [];
  Map<String, dynamic>? _aktuell;
  int? _gewaehlt;
  bool _geladen = false;
  bool _speichert = false;

  final _ansprechC = TextEditingController();
  final _durchwahlC = TextEditingController();
  final _emailC = TextEditingController();
  final _refC = TextEditingController();
  final _notizC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    for (final c in [_ansprechC, _durchwahlC, _emailC, _refC, _notizC]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _laden() async {
    final firmen = await widget.apiService.listVermieterInkassoDatenbank();
    final eigen = await widget.apiService.getVermieterInkasso(widget.mietvertragId);
    if (!mounted) return;
    // ⚠️ `exists` steht auf der Wurzel der Antwort, nicht in `data`.
    final vorhanden = eigen['exists'] == true;
    final d = vorhanden ? (eigen['data'] as Map<String, dynamic>?) : null;
    setState(() {
      _firmen = List<Map<String, dynamic>>.from(firmen['items'] as List? ?? []);
      _aktuell = d;
      _gewaehlt = d?['inkasso_id'] as int?;
      _ansprechC.text = d?['ansprechpartner']?.toString() ?? '';
      _durchwahlC.text = d?['telefon_durchwahl']?.toString() ?? '';
      _emailC.text = d?['email_ansprechpartner']?.toString() ?? '';
      _refC.text = d?['ref_intern']?.toString() ?? '';
      _notizC.text = d?['notizen']?.toString() ?? '';
      _geladen = true;
    });
  }

  Future<void> _speichern() async {
    setState(() => _speichert = true);
    final res = await widget.apiService.saveVermieterInkasso(widget.mietvertragId, {
      'inkasso_id': _gewaehlt,
      'ansprechpartner': _ansprechC.text.trim(),
      'telefon_durchwahl': _durchwahlC.text.trim(),
      'email_ansprechpartner': _emailC.text.trim(),
      'ref_intern': _refC.text.trim(),
      'notizen': _notizC.text.trim(),
    });
    if (!mounted) return;
    setState(() => _speichert = false);
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Gespeichert' : 'Nicht gespeichert: ${res['message'] ?? 'unbekannter Grund'}'),
      backgroundColor: ok ? Colors.green.shade600 : Colors.red,
    ));
    if (ok) _laden();
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    final lookup = _aktuell?['inkasso_lookup'] as Map<String, dynamic>?;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Inkasso-Firma', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: _gewaehlt,
          decoration: InputDecoration(
            hintText: 'Firma auswählen…',
            isDense: true,
            prefixIcon: const Icon(Icons.business, size: 18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: _firmen
              .map((f) => DropdownMenuItem(
                    value: f['id'] as int,
                    child: Text(f['firmenname']?.toString() ?? '',
                        style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _gewaehlt = v),
        ),
        if (lookup != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.shade100),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final e in <String, String?>{
                'Anschrift': [lookup['strasse'], lookup['plz_ort']]
                    .where((x) => (x?.toString() ?? '').isNotEmpty)
                    .join(', '),
                'Telefon': lookup['telefon']?.toString(),
                'Fax': lookup['fax']?.toString(),
                'E-Mail': lookup['email']?.toString(),
                'Geschäftsführung': lookup['geschaeftsfuehrer']?.toString(),
                'HRB': lookup['hrb']?.toString(),
                // Die Erlaubnis nach dem RDG ist der Grund, warum ein
                // Inkassobüro überhaupt fordern darf — sie gehört sichtbar
                // in die Akte, nicht in eine Fußnote.
                'RDG-Lizenz': lookup['rdg_lizenz']?.toString(),
              }.entries)
                if ((e.value ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 120,
                        child: Text(e.key,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ),
                      Expanded(child: Text(e.value!, style: const TextStyle(fontSize: 12.5))),
                    ]),
                  ),
            ]),
          ),
        ],
        const SizedBox(height: 18),
        Text('Unser Ansprechpartner dort',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ansprechC,
              decoration: InputDecoration(
                labelText: 'Name',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _durchwahlC,
              decoration: InputDecoration(
                labelText: 'Durchwahl',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _emailC,
          decoration: InputDecoration(
            labelText: 'E-Mail',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _refC,
          decoration: InputDecoration(
            labelText: 'Unser Zeichen',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notizC,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Notizen',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          ElevatedButton.icon(
            onPressed: _speichert ? null : _speichern,
            icon: _speichert
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 16),
            label: const Text('Speichern'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple, foregroundColor: Colors.white),
          ),
          const Spacer(),
          if (_aktuell != null)
            TextButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Zuordnung entfernen?'),
                    content: const Text(
                        'Nur die Firma wird entfernt. Vorfälle und Aktenzeichen '
                        'bleiben erhalten — sie gehören zum Mietverhältnis, nicht zur Firma.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Entfernen', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                await widget.apiService.deleteVermieterInkasso(widget.mietvertragId);
                _laden();
              },
              icon: Icon(Icons.link_off, size: 16, color: Colors.red.shade400),
              label: Text('Entfernen',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
            ),
        ]),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Vorfall-Liste → ein Vorfall → seine Aktenzeichen
// ══════════════════════════════════════════════════════════════════════

class _VorfallListe extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int mietvertragId;
  const _VorfallListe({
    required this.apiService,
    required this.userId,
    required this.mietvertragId,
  });

  @override
  State<_VorfallListe> createState() => _VorfallListeState();
}

class _VorfallListeState extends State<_VorfallListe> {
  List<Map<String, dynamic>> _items = [];
  bool _geladen = false;
  Map<String, dynamic>? _offen;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final res = await widget.apiService.listVermieterVorfaelle(widget.mietvertragId);
    if (!mounted) return;
    setState(() {
      _items = List<Map<String, dynamic>>.from(res['items'] as List? ?? []);
      _geladen = true;
      // Der geöffnete Vorfall wird mitgezogen, damit nach dem Speichern
      // nicht plötzlich der alte Stand im Kopf des Detailbereichs steht.
      if (_offen != null) {
        final id = _offen!['id'];
        _offen = _items.where((v) => v['id'] == id).firstOrNull;
      }
    });
  }

  void _bearbeiten([Map<String, dynamic>? v]) {
    final istNeu = v == null;
    final bezC = TextEditingController(text: v?['bezeichnung']?.toString() ?? '');
    final grundC = TextEditingController(text: v?['grund']?.toString() ?? '');
    final fordC = TextEditingController(text: v?['forderung_brutto']?.toString() ?? '');
    final gezahltC = TextEditingController(text: v?['gezahlt']?.toString() ?? '');
    final notizC = TextEditingController(text: v?['notizen']?.toString() ?? '');
    final eroeffnetC = TextEditingController(text: v?['eroeffnet_am']?.toString() ?? '');
    final fristC = TextEditingController(text: v?['naechste_frist']?.toString() ?? '');
    final geschlossenC = TextEditingController(text: v?['geschlossen_am']?.toString() ?? '');
    String status = v?['status']?.toString() ?? 'offen';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
        title: Text(istNeu ? 'Neuer Vorfall' : 'Vorfall bearbeiten',
            style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: bezC,
                decoration: InputDecoration(
                  labelText: 'Bezeichnung *',
                  hintText: 'z. B. Mietrückstand 2026',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: grundC,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Grund der Forderung',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: fordC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Forderung €',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: gezahltC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Davon gezahlt €',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: status,
                decoration: InputDecoration(
                  labelText: 'Status',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: _kStatusNamen.entries
                    .map((e) => DropdownMenuItem(
                        value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (x) => setDlg(() => status = x ?? status),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _datumFeld(
                    context: ctx2,
                    controller: eroeffnetC,
                    label: 'Eröffnet am',
                    onChanged: () => setDlg(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _datumFeld(
                    context: ctx2,
                    controller: fristC,
                    label: 'Nächste Frist',
                    onChanged: () => setDlg(() {}),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              _datumFeld(
                context: ctx2,
                controller: geschlossenC,
                label: 'Geschlossen am',
                onChanged: () => setDlg(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notizC,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Notizen',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () async {
              if (bezC.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(
                  content: Text('Ohne Bezeichnung lässt sich der Vorfall später nicht wiederfinden'),
                  backgroundColor: Colors.orange,
                ));
                return;
              }
              Navigator.pop(ctx);
              final res = await widget.apiService.saveVermieterVorfall(widget.mietvertragId, {
                if (!istNeu) 'id': v['id'],
                'bezeichnung': bezC.text.trim(),
                'grund': grundC.text.trim(),
                'forderung_brutto': fordC.text.trim(),
                'gezahlt': gezahltC.text.trim(),
                'notizen': notizC.text.trim(),
                'status': status,
                'eroeffnet_am': eroeffnetC.text,
                'naechste_frist': fristC.text,
                'geschlossen_am': geschlossenC.text,
              });
              if (!mounted) return;
              if (res['success'] != true) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Nicht gespeichert: ${res['message'] ?? 'unbekannter Grund'}'),
                  backgroundColor: Colors.red,
                ));
                return;
              }
              _laden();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple, foregroundColor: Colors.white),
            child: Text(istNeu ? 'Anlegen' : 'Speichern'),
          ),
        ],
      )),
    );
  }

  Future<void> _loeschen(Map<String, dynamic> v) async {
    final anzahl = int.tryParse(v['aktenzeichen_count']?.toString() ?? '0') ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vorfall löschen?'),
        content: Text(anzahl > 0
            ? 'Mit dem Vorfall verschwinden auch seine $anzahl Aktenzeichen, '
                'deren Schriftverkehr und alle hinterlegten Dokumente.'
            : 'Der Vorfall wird endgültig entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.apiService.deleteVermieterVorfall(v['id'] as int);
    if (!mounted) return;
    if (_offen?['id'] == v['id']) setState(() => _offen = null);
    _laden();
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());

    if (_offen != null) {
      return _VorfallDetail(
        apiService: widget.apiService,
        userId: widget.userId,
        vorfall: _offen!,
        onZurueck: () => setState(() => _offen = null),
        onBearbeiten: () => _bearbeiten(_offen),
      );
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          // Dieselbe Vorsicht wie bei der Korrespondenz-Überschrift:
          // ein freier Text in einer Row nimmt sich seine volle Breite.
          Expanded(
            child: Text('Vorfälle (${_items.length})',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15, color: Colors.purple.shade800),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _bearbeiten(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: _items.isEmpty
            // Scrollbar aus demselben Grund wie in der Vermieterliste:
            // bei großer Schrift läuft der Erklärtext sonst unten heraus.
            ? SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.folder_special, size: 56, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('Kein Vorfall erfasst',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500)),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        'Ein Vorfall bündelt einen Vorgang — etwa einen Mietrückstand — '
                        'mit allen Aktenzeichen, unter denen er beim Inkassobüro läuft.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400, height: 1.4),
                      ),
                    ),
                  ]),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final v = _items[i];
                  final anzahl = int.tryParse(v['aktenzeichen_count']?.toString() ?? '0') ?? 0;
                  final frist = v['naechste_frist']?.toString() ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => setState(() => _offen = v),
                      leading: CircleAvatar(
                        backgroundColor: (_kStatusFarben[v['status']] ?? Colors.grey).shade50,
                        child: Icon(Icons.gavel,
                            size: 20,
                            color: (_kStatusFarben[v['status']] ?? Colors.grey).shade700),
                      ),
                      title: Text(v['bezeichnung']?.toString() ?? '(ohne Bezeichnung)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$anzahl Aktenzeichen'
                            '${(v['forderung_brutto']?.toString() ?? '').isNotEmpty ? ' · ${v['forderung_brutto']} €' : ''}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          if (frist.isNotEmpty)
                            Text('Nächste Frist: ${_datumDeutsch(frist)}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.red.shade400,
                                    fontWeight: FontWeight.w600)),
                        ],
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        _statusChip(v['status']?.toString()),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                          onPressed: () => _loeschen(v),
                        ),
                        const Icon(Icons.chevron_right, size: 18),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════
// Ein Vorfall: Kopfdaten + seine Aktenzeichen
// ══════════════════════════════════════════════════════════════════════

class _VorfallDetail extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> vorfall;
  final VoidCallback onZurueck;
  final VoidCallback onBearbeiten;

  const _VorfallDetail({
    required this.apiService,
    required this.userId,
    required this.vorfall,
    required this.onZurueck,
    required this.onBearbeiten,
  });

  @override
  State<_VorfallDetail> createState() => _VorfallDetailState();
}

class _VorfallDetailState extends State<_VorfallDetail> {
  List<Map<String, dynamic>> _akten = [];
  bool _geladen = false;

  int get _vorfallId => widget.vorfall['id'] as int;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void didUpdateWidget(_VorfallDetail alt) {
    super.didUpdateWidget(alt);
    if (alt.vorfall['id'] != widget.vorfall['id']) _laden();
  }

  Future<void> _laden() async {
    final res = await widget.apiService.listVermieterAktenzeichen(_vorfallId);
    if (!mounted) return;
    setState(() {
      _akten = List<Map<String, dynamic>>.from(res['items'] as List? ?? []);
      _geladen = true;
    });
  }

  void _bearbeiten([Map<String, dynamic>? a]) {
    final istNeu = a == null;
    final azC = TextEditingController(text: a?['aktenzeichen']?.toString() ?? '');
    final bezC = TextEditingController(text: a?['bezeichnung']?.toString() ?? '');
    final fordC = TextEditingController(text: a?['forderung_brutto']?.toString() ?? '');
    final gezahltC = TextEditingController(text: a?['gezahlt']?.toString() ?? '');
    final notizC = TextEditingController(text: a?['notizen']?.toString() ?? '');
    final eroeffnetC = TextEditingController(text: a?['eroeffnet_am']?.toString() ?? '');
    final fristC = TextEditingController(text: a?['naechste_frist']?.toString() ?? '');
    final geschlossenC = TextEditingController(text: a?['geschlossen_am']?.toString() ?? '');
    String status = a?['status']?.toString() ?? 'offen';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
        title: Text(istNeu ? 'Neues Aktenzeichen' : 'Aktenzeichen bearbeiten',
            style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: azC,
                decoration: InputDecoration(
                  labelText: 'Aktenzeichen *',
                  hintText: 'wie im Schreiben des Inkassobüros',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bezC,
                decoration: InputDecoration(
                  labelText: 'Bezeichnung',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: fordC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Forderung €',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: gezahltC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Davon gezahlt €',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: status,
                decoration: InputDecoration(
                  labelText: 'Status',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: _kStatusNamen.entries
                    .map((e) => DropdownMenuItem(
                        value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (x) => setDlg(() => status = x ?? status),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: _datumFeld(
                    context: ctx2,
                    controller: eroeffnetC,
                    label: 'Eröffnet am',
                    onChanged: () => setDlg(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _datumFeld(
                    context: ctx2,
                    controller: fristC,
                    label: 'Nächste Frist',
                    onChanged: () => setDlg(() {}),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              _datumFeld(
                context: ctx2,
                controller: geschlossenC,
                label: 'Geschlossen am',
                onChanged: () => setDlg(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notizC,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Notizen',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () async {
              if (azC.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(
                  content: Text('Das Aktenzeichen ist die Kennung, unter der das Büro schreibt'),
                  backgroundColor: Colors.orange,
                ));
                return;
              }
              Navigator.pop(ctx);
              final res = await widget.apiService.saveVermieterAktenzeichen(_vorfallId, {
                if (!istNeu) 'id': a['id'],
                'aktenzeichen': azC.text.trim(),
                'bezeichnung': bezC.text.trim(),
                'forderung_brutto': fordC.text.trim(),
                'gezahlt': gezahltC.text.trim(),
                'notizen': notizC.text.trim(),
                'status': status,
                'eroeffnet_am': eroeffnetC.text,
                'naechste_frist': fristC.text,
                'geschlossen_am': geschlossenC.text,
              });
              if (!mounted) return;
              if (res['success'] != true) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Nicht gespeichert: ${res['message'] ?? 'unbekannter Grund'}'),
                  backgroundColor: Colors.red,
                ));
                return;
              }
              _laden();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple, foregroundColor: Colors.white),
            child: Text(istNeu ? 'Anlegen' : 'Speichern'),
          ),
        ],
      )),
    );
  }

  void _oeffnen(Map<String, dynamic> a) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: SizedBox(
          width: 820,
          height: 640,
          child: VermieterAktenzeichenDetail(
            apiService: widget.apiService,
            userId: widget.userId,
            aktenzeichen: a,
            onBearbeiten: () {
              Navigator.pop(ctx);
              _bearbeiten(a);
            },
          ),
        ),
      ),
    ).then((_) => _laden());
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vorfall;
    return Column(children: [
      Container(
        color: Colors.purple.shade50,
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 8),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: 'Zurück zu den Vorfällen',
            onPressed: widget.onZurueck,
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v['bezeichnung']?.toString() ?? '(ohne Bezeichnung)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14, color: Colors.purple.shade900),
                  overflow: TextOverflow.ellipsis),
              Text(
                [
                  if ((v['forderung_brutto']?.toString() ?? '').isNotEmpty)
                    '${v['forderung_brutto']} €',
                  if ((v['gezahlt']?.toString() ?? '').isNotEmpty) 'gezahlt ${v['gezahlt']} €',
                  if ((v['eroeffnet_am']?.toString() ?? '').isNotEmpty)
                    'seit ${_datumDeutsch(v['eroeffnet_am'])}',
                ].join(' · '),
                style: const TextStyle(fontSize: 11),
              ),
            ]),
          ),
          _statusChip(v['status']?.toString()),
          IconButton(
            icon: Icon(Icons.edit_outlined, size: 18, color: Colors.purple.shade400),
            tooltip: 'Vorfall bearbeiten',
            onPressed: widget.onBearbeiten,
          ),
        ]),
      ),
      if ((v['grund']?.toString() ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(v['grund'].toString(),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ),
        ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: Text('Aktenzeichen (${_akten.length})',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: Colors.purple.shade800),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _bearbeiten(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: !_geladen
            ? const Center(child: CircularProgressIndicator())
            : _akten.isEmpty
                ? Center(
                    child: Text('Noch kein Aktenzeichen zu diesem Vorfall',
                        style: TextStyle(color: Colors.grey.shade500)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _akten.length,
                    itemBuilder: (_, i) {
                      final a = _akten[i];
                      final frist = a['naechste_frist']?.toString() ?? '';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () => _oeffnen(a),
                          leading: CircleAvatar(
                            backgroundColor: (_kStatusFarben[a['status']] ?? Colors.grey).shade50,
                            child: Icon(Icons.description,
                                size: 20,
                                color: (_kStatusFarben[a['status']] ?? Colors.grey).shade700),
                          ),
                          title: Text(a['aktenzeichen']?.toString() ?? '',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((a['bezeichnung']?.toString() ?? '').isNotEmpty)
                                Text(a['bezeichnung'].toString(),
                                    style: const TextStyle(fontSize: 11)),
                              if ((a['forderung_brutto']?.toString() ?? '').isNotEmpty)
                                Text('${a['forderung_brutto']} €'
                                    '${(a['gezahlt']?.toString() ?? '').isNotEmpty ? ' · gezahlt ${a['gezahlt']} €' : ''}',
                                    style: const TextStyle(fontSize: 11)),
                              if (frist.isNotEmpty)
                                Text('Nächste Frist: ${_datumDeutsch(frist)}',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        color: Colors.red.shade400,
                                        fontWeight: FontWeight.w600)),
                            ],
                          ),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            _statusChip(a['status']?.toString()),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 18, color: Colors.red.shade300),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Aktenzeichen löschen?'),
                                    content: const Text(
                                        'Schriftverkehr und Dokumente dieses Aktenzeichens '
                                        'werden mit entfernt.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('Abbrechen')),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Löschen',
                                            style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                await widget.apiService
                                    .deleteVermieterAktenzeichen(a['id'] as int);
                                _laden();
                              },
                            ),
                            const Icon(Icons.chevron_right, size: 18),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════
// Ein Aktenzeichen: Details · Korrespondenz · Vollmacht · Akteneinsicht
// ══════════════════════════════════════════════════════════════════════

class VermieterAktenzeichenDetail extends StatelessWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> aktenzeichen;
  final VoidCallback onBearbeiten;

  const VermieterAktenzeichenDetail({
    super.key,
    required this.apiService,
    required this.userId,
    required this.aktenzeichen,
    required this.onBearbeiten,
  });

  @override
  Widget build(BuildContext context) {
    final a = aktenzeichen;
    final id = a['id'] as int;
    return DefaultTabController(
      length: 4,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          color: Colors.purple.shade50,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a['aktenzeichen']?.toString() ?? '',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15, color: Colors.purple.shade900)),
                if ((a['bezeichnung']?.toString() ?? '').isNotEmpty)
                  Text(a['bezeichnung'].toString(), style: const TextStyle(fontSize: 11.5)),
              ]),
            ),
            _statusChip(a['status']?.toString()),
            IconButton(
              icon: Icon(Icons.edit_outlined, size: 18, color: Colors.purple.shade400),
              tooltip: 'Bearbeiten',
              onPressed: onBearbeiten,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Colors.purple.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.purple.shade700,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
            Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
            Tab(icon: Icon(Icons.assignment_ind, size: 18), text: 'Vollmacht'),
            Tab(icon: Icon(Icons.fact_check, size: 18), text: 'Akteneinsicht'),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            _AktenzeichenDetails(aktenzeichen: a),
            VermieterKorrespondenz(
              apiService: apiService,
              userId: userId,
              ebene: VermieterKorrEbene.inkasso,
              parentId: id,
              farbe: Colors.purple,
            ),
            const VermieterVollmachtPlatzhalter(bezug: 'das Inkassobüro'),
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: VermieterDokumente(
                apiService: apiService,
                userId: userId,
                typ: 'ink_akteneinsicht',
                parentId: id,
                farbe: Colors.purple,
                titel: 'Unterlagen aus der Akteneinsicht',
                hinweis: 'Hier liegen die Unterlagen, die beim Inkassobüro zu diesem '
                    'Aktenzeichen angefordert wurden — nicht die eigenen Schreiben. '
                    'Die stehen unter Korrespondenz.',
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _AktenzeichenDetails extends StatelessWidget {
  final Map<String, dynamic> aktenzeichen;
  const _AktenzeichenDetails({required this.aktenzeichen});

  @override
  Widget build(BuildContext context) {
    final a = aktenzeichen;
    final zeilen = <String, String>{
      'Aktenzeichen': a['aktenzeichen']?.toString() ?? '',
      'Bezeichnung': a['bezeichnung']?.toString() ?? '',
      'Status': _kStatusNamen[a['status']] ?? (a['status']?.toString() ?? ''),
      'Forderung': (a['forderung_brutto']?.toString() ?? '').isEmpty
          ? ''
          : '${a['forderung_brutto']} €',
      'Davon gezahlt': (a['gezahlt']?.toString() ?? '').isEmpty ? '' : '${a['gezahlt']} €',
      'Eröffnet am': _datumDeutsch(a['eroeffnet_am']),
      'Nächste Frist': _datumDeutsch(a['naechste_frist']),
      'Geschlossen am': _datumDeutsch(a['geschlossen_am']),
    };
    // Offener Rest nur zeigen, wenn beide Zahlen da sind — sonst stünde
    // eine ausgerechnete Forderung da, die auf einer Lücke beruht.
    final f = double.tryParse((a['forderung_brutto']?.toString() ?? '').replaceAll(',', '.'));
    final g = double.tryParse((a['gezahlt']?.toString() ?? '').replaceAll(',', '.'));
    if (f != null && g != null) {
      zeilen['Offener Rest'] = '${(f - g).toStringAsFixed(2)} €';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final e in zeilen.entries)
          if (e.value.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 130,
                  child: Text(e.key, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                ),
                Expanded(child: Text(e.value, style: const TextStyle(fontSize: 13))),
              ]),
            ),
        if ((a['notizen']?.toString() ?? '').isNotEmpty) ...[
          const Divider(height: 24),
          Text('Notizen', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Text(a['notizen'].toString(), style: const TextStyle(fontSize: 13, height: 1.4)),
        ],
      ]),
    );
  }
}

/// Der Vollmacht-Tab steht, die Urkunde noch nicht.
///
/// ⚠️ Absichtlich kein Knopf, der ein PDF erzeugt: die Vollmacht gegenüber
/// einem Vermieter oder einem Inkassobüro ist rechtsgeschäftliche
/// Vertretung nach § 164 BGB — nicht die Bevollmächtigung im
/// Verwaltungsverfahren nach § 13 SGB X, aus der die vorhandenen Vorlagen
/// stammen. Der Wortlaut muss geschrieben und freigegeben werden. Eine
/// Urkunde mit dem falschen Text wäre schlimmer als gar keine: sie sieht
/// gültig aus und wird eingereicht.
class VermieterVollmachtPlatzhalter extends StatelessWidget {
  final String bezug;
  const VermieterVollmachtPlatzhalter({super.key, required this.bezug});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.assignment_ind_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 14),
          Text('Vollmacht für $bezug',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          SizedBox(
            width: 420,
            child: Text(
              'Die Ablage steht bereit, der Wortlaut der Urkunde ist noch nicht '
              'freigegeben. Eine Vollmacht gegenüber einem privaten Gegenüber ist '
              'rechtsgeschäftliche Vertretung (§ 164 BGB) und nicht dieselbe wie '
              'die gegenüber einer Behörde — deshalb wird hier nichts aus den '
              'vorhandenen Vorlagen erzeugt.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500, height: 1.45),
            ),
          ),
        ]),
      ),
    );
  }
}
