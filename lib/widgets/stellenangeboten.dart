import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user.dart';
import '../services/api_service.dart';

/// Stellenangebote — searches the Bundesagentur fuer Arbeit Jobboerse and
/// displays results. Sits next to "Bewerbungsuebersicht" so the Vorsitzer can
/// hand a member a fresh list of open positions during the same session.
///
/// Default search: free-text was=Member's letzter Beruf (if any) + wo=user.plz +
/// umkreis=25. The user can override everything before searching.
class StellenangebotenContent extends StatefulWidget {
  final ApiService apiService;
  final User user;
  const StellenangebotenContent({super.key, required this.apiService, required this.user});

  @override
  State<StellenangebotenContent> createState() => _StellenangebotenContentState();
}

class _StellenangebotenContentState extends State<StellenangebotenContent> {
  final _wasC = TextEditingController();
  final _woC = TextEditingController();
  int _umkreis = 0;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];
  int _page = 1;
  int? _total;
  int? _initial;

  @override
  void initState() {
    super.initState();
    // Zuerst Ort (aus Verifizierung Stufe 1) — falls leer fallback auf PLZ.
    // Damit sucht der Tab standardmaessig nur in der Stadt des Mitglieds.
    final ort = (widget.user.ort ?? '').trim();
    final plz = (widget.user.plz ?? '').trim();
    _woC.text = ort.isNotEmpty ? ort : plz;
  }

  @override
  void dispose() { _wasC.dispose(); _woC.dispose(); super.dispose(); }

  Future<void> _search({bool resetPage = true}) async {
    if (resetPage) _page = 1;
    setState(() { _loading = true; _error = null; });
    final res = await widget.apiService.searchArbeitsagenturJobs(
      was: _wasC.text,
      wo: _woC.text,
      umkreis: _umkreis,
      page: _page,
      size: 25,
    );
    if (!mounted) return;
    if (res['success'] != true) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Suche fehlgeschlagen';
        _results = [];
      });
      return;
    }
    final items = List<Map<String, dynamic>>.from(
      (res['stellenangebote'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    setState(() {
      _loading = false;
      _results = items;
      _total = res['maxErgebnisse'] as int?;
      _initial ??= _total;
    });
  }

  String _arbeitsort(Map<String, dynamic> ag) {
    final ort = (ag['arbeitsort']?['ort'] ?? ag['arbeitsorte']?[0]?['ort'] ?? '').toString();
    final plz = (ag['arbeitsort']?['plz'] ?? ag['arbeitsorte']?[0]?['plz'] ?? '').toString();
    return [if (plz.isNotEmpty) plz, ort].where((s) => s.isNotEmpty).join(' ');
  }

  Future<void> _openExtern(String refnr) async {
    final url = Uri.parse('https://www.arbeitsagentur.de/jobsuche/jobdetail/$refnr');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Konnte $url nicht oeffnen')));
    }
  }

  void _openDetails(Map<String, dynamic> ag) {
    showDialog(context: context, builder: (_) {
      final titel = (ag['titel'] ?? ag['beruf'] ?? '').toString();
      final beruf = (ag['beruf'] ?? '').toString();
      final firma = (ag['arbeitgeber'] ?? '').toString();
      final ort = _arbeitsort(ag);
      final eintritt = (ag['eintrittsdatum'] ?? '').toString().split('T').first;
      final refnr = (ag['refnr'] ?? '').toString();
      final modi = (ag['modifikationsTimestamp'] ?? '').toString().split('T').first;
      return AlertDialog(
        title: Row(children: [
          Icon(Icons.work_outline, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(titel.isEmpty ? beruf : titel, style: const TextStyle(fontSize: 15))),
        ]),
        content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (beruf.isNotEmpty && beruf != titel) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Beruf: $beruf', style: const TextStyle(fontSize: 13))),
          if (firma.isNotEmpty) _row(Icons.business, firma),
          if (ort.isNotEmpty) _row(Icons.location_on, ort),
          if (eintritt.isNotEmpty) _row(Icons.event, 'Eintritt: $eintritt'),
          if (modi.isNotEmpty) _row(Icons.update, 'Aktualisiert: $modi'),
          if (refnr.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText('Ref-Nr.: $refnr', style: const TextStyle(fontSize: 11, color: Colors.grey))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schliessen')),
          if (refnr.isNotEmpty) ElevatedButton.icon(
            onPressed: () { Navigator.pop(context); _openExtern(refnr); },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Auf arbeitsagentur.de oeffnen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white),
          ),
        ],
      );
    });
  }

  Widget _row(IconData icon, String text) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 6),
    Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
  ]));

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.indigo.shade50, border: Border(bottom: BorderSide(color: Colors.indigo.shade200))),
        child: Column(children: [
          Row(children: [
            Icon(Icons.search, size: 18, color: Colors.indigo.shade800),
            const SizedBox(width: 6),
            Text('Bundesagentur fuer Arbeit – Jobsuche', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
            const SizedBox(width: 8),
            Text(_umkreis == 0 ? 'nur ${_woC.text}' : '${_woC.text} +${_umkreis}km',
                style: TextStyle(fontSize: 11, color: Colors.indigo.shade600, fontStyle: FontStyle.italic)),
            const Spacer(),
            if (_total != null) Text('${_total!} Treffer', style: TextStyle(fontSize: 11, color: Colors.indigo.shade700)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(flex: 3, child: TextField(
              controller: _wasC,
              decoration: const InputDecoration(
                labelText: 'Was (Beruf, Stichwort)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.work, size: 16),
              ),
              onSubmitted: (_) => _search(),
            )),
            const SizedBox(width: 6),
            Expanded(flex: 2, child: TextField(
              controller: _woC,
              decoration: const InputDecoration(
                labelText: 'Wo (PLZ/Ort)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on, size: 16),
              ),
              onSubmitted: (_) => _search(),
            )),
            const SizedBox(width: 6),
            SizedBox(width: 112, child: DropdownButtonFormField<int>(
              initialValue: _umkreis,
              decoration: const InputDecoration(labelText: 'Umkreis', isDense: true, border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 0,   child: Text('nur Stadt')),
                DropdownMenuItem(value: 5,   child: Text('5 km')),
                DropdownMenuItem(value: 10,  child: Text('10 km')),
                DropdownMenuItem(value: 25,  child: Text('25 km')),
                DropdownMenuItem(value: 50,  child: Text('50 km')),
                DropdownMenuItem(value: 100, child: Text('100 km')),
              ],
              onChanged: (v) => setState(() => _umkreis = v ?? 0),
            )),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              onPressed: _loading ? null : () => _search(),
              icon: _loading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.search, size: 16),
              label: const Text('Suchen'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white),
            ),
          ]),
        ]),
      ),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 8),
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))),
            ]))
          : _results.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text(_initial == null ? 'Suche starten' : 'Keine Treffer', style: TextStyle(color: Colors.grey.shade600)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final s = _results[i];
                  final titel = (s['titel'] ?? s['beruf'] ?? '(ohne Titel)').toString();
                  final firma = (s['arbeitgeber'] ?? '').toString();
                  final ort = _arbeitsort(s);
                  final eintritt = (s['eintrittsdatum'] ?? '').toString().split('T').first;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: InkWell(
                      onTap: () => _openDetails(s),
                      child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(titel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        if (firma.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                          Icon(Icons.business, size: 13, color: Colors.grey.shade600), const SizedBox(width: 4),
                          Expanded(child: Text(firma, style: const TextStyle(fontSize: 12))),
                        ])),
                        if (ort.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [
                          Icon(Icons.location_on, size: 13, color: Colors.grey.shade600), const SizedBox(width: 4),
                          Text(ort, style: const TextStyle(fontSize: 12)),
                          if (eintritt.isNotEmpty) ...[
                            const Spacer(),
                            Icon(Icons.event, size: 12, color: Colors.grey.shade600), const SizedBox(width: 3),
                            Text(eintritt, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ])),
                      ])),
                    ),
                  );
                },
              ),
      ),
      if (_total != null && _total! > _results.length && _results.isNotEmpty) Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(top: BorderSide(color: Colors.grey.shade300))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton.icon(
            onPressed: _page == 1 || _loading ? null : () { _page--; _search(resetPage: false); },
            icon: const Icon(Icons.chevron_left, size: 16), label: const Text('Zurueck'),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('Seite $_page')),
          TextButton.icon(
            onPressed: _loading ? null : () { _page++; _search(resetPage: false); },
            icon: const Icon(Icons.chevron_right, size: 16), label: const Text('Weiter'),
          ),
        ]),
      ),
    ]);
  }
}
