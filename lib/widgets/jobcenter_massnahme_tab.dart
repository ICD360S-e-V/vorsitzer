import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/app_farben.dart';
import '../utils/massnahme_konstanten.dart';
import 'massnahme_detail_modal.dart';
import 'phone_link.dart';

/// Jobcenter ▸ Arbeitsvermittler ▸ „Maßnahme (Träger)".
///
/// Aufbau wie der Arbeitsvermittler-Reiter selbst: ein Pool (Träger und ihre
/// Angebote) und daneben die Zuordnung zum Mitglied. Der erste Unterreiter
/// „Zuständige Maßnahme" zeigt, wo das Mitglied gerade zugewiesen ist.
///
/// ⚠️ Eigene Datei, obwohl der Reiter im AV-Modal steckt:
/// behorde_jobcenter.dart hat über 12.000 Zeilen.
class JobcenterMassnahmeTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int userAvId;
  final VoidCallback? onChanged;
  const JobcenterMassnahmeTab({
    super.key,
    required this.apiService,
    required this.userId,
    required this.userAvId,
    this.onChanged,
  });

  @override
  State<JobcenterMassnahmeTab> createState() => _JobcenterMassnahmeTabState();
}

class _JobcenterMassnahmeTabState extends State<JobcenterMassnahmeTab>
    with SingleTickerProviderStateMixin {
  late TabController _sub;
  List<Map<String, dynamic>> _alle = [];
  bool _loading = true;

  List<Map<String, dynamic>> get _offen =>
      _alle.where((z) => massnahmeIstOffen(z['status']?.toString())).toList();
  List<Map<String, dynamic>> get _historie =>
      _alle.where((z) => !massnahmeIstOffen(z['status']?.toString())).toList();

  @override
  void initState() {
    super.initState();
    _sub = TabController(length: 2, vsync: this);
    _laden();
  }

  @override
  void dispose() { _sub.dispose(); super.dispose(); }

  Future<void> _laden() async {
    final r = await widget.apiService.massnahmeAction({
      'action': 'list_user_massnahme', 'user_id': widget.userId,
    });
    if (!mounted) return;
    setState(() {
      _alle = (r['success'] == true && r['zuweisungen'] is List)
          ? List<Map<String, dynamic>>.from(
              (r['zuweisungen'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
          : [];
      _loading = false;
    });
  }

  void _melden(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _bearbeiten([Map<String, dynamic>? vorhanden]) async {
    final gespeichert = await showDialog<bool>(
      context: context,
      builder: (_) => _ZuweisungDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        userAvId: widget.userAvId,
        vorhanden: vorhanden,
      ),
    );
    if (gespeichert == true) { widget.onChanged?.call(); _laden(); }
  }

  Future<void> _loeschen(Map<String, dynamic> z) async {
    final ja = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Zuweisung entfernen?'),
        content: Text('„${z['titel'] ?? ''}" bei ${z['traeger_name'] ?? ''} wird aus der Akte '
            'des Mitglieds entfernt. Der Träger und das Angebot bleiben im Katalog.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Entfernen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ja != true) return;
    final r = await widget.apiService.massnahmeAction({
      'action': 'delete_user_massnahme', 'id': z['id'], 'user_id': widget.userId,
    });
    if (r['success'] == true) { widget.onChanged?.call(); _laden(); }
    else { _melden(r['message']?.toString() ?? 'Konnte nicht entfernt werden'); }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Der amtliche Wortlaut. Die Reiterbeschriftung ist unsere Kurzform,
      // die Formulierung des Zuweisungsschreibens steht hier.
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: F.h(Colors.indigo, 50),
          border: Border(bottom: BorderSide(color: F.h(Colors.indigo, 200))),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.school_outlined, size: 20, color: F.h(Colors.indigo, 800)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kMassnahmeVollTitel,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold,
                    color: F.h(Colors.indigo, 900))),
            const SizedBox(height: 2),
            Text(kMassnahmeRechtsgrundlage,
                style: TextStyle(fontSize: 11, color: F.h(Colors.indigo, 700))),
          ])),
        ]),
      ),
      TabBar(
        controller: _sub,
        labelColor: F.h(Colors.indigo, 800),
        unselectedLabelColor: F.h(Colors.grey, 600),
        indicatorColor: F.h(Colors.indigo, 700),
        tabs: [
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.assignment_turned_in_outlined, size: 16),
            const SizedBox(width: 6),
            Text('Zuständige Maßnahme${_offen.isNotEmpty ? " (${_offen.length})" : ""}',
                style: const TextStyle(fontSize: 12)),
          ])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.history, size: 16),
            const SizedBox(width: 6),
            Text('Historie${_historie.isNotEmpty ? " (${_historie.length})" : ""}',
                style: const TextStyle(fontSize: 12)),
          ])),
        ],
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(controller: _sub, children: [
                Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: F.h(Colors.indigo, 50).withValues(alpha: 0.5),
                    child: Row(children: [
                      Expanded(child: Text('Aktuelle Zuweisung des Mitglieds',
                          style: TextStyle(fontSize: 11, color: F.h(Colors.indigo, 700)))),
                      ElevatedButton.icon(
                        onPressed: () => _bearbeiten(),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Neue Zuweisung', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: F.h(Colors.indigo, 700),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ]),
                  ),
                  Expanded(child: _liste(_offen, 'Zurzeit ist das Mitglied keiner Maßnahme zugewiesen')),
                ]),
                _liste(_historie, 'Keine früheren Maßnahmen'),
              ]),
      ),
    ]);
  }

  Widget _liste(List<Map<String, dynamic>> zs, String leer) {
    if (zs.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(leer, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 600))),
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: zs.length,
      itemBuilder: (_, i) => _karte(zs[i]),
    );
  }

  Widget _karte(Map<String, dynamic> z) {
    final df = DateFormat('dd.MM.yyyy');
    final status = z['status']?.toString() ?? 'zugewiesen';
    final offen = massnahmeIstOffen(status);
    final beginn = massnahmeDatum(z['beginn']);
    final ende = massnahmeDatum(z['ende']);
    final bekanntgabe = massnahmeDatum(z['bekanntgabe_datum']);
    final tage = massnahmeTageBisFrist(bekanntgabe);
    final lesbar = z['lesbar'] != false;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      // Tippen öffnet die Detailansicht: Details · Bewilligung · Korrespondenz.
      child: InkWell(
        onTap: () => _detailOeffnen(z),
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(z['titel']?.toString() ?? '—',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(z['traeger_name']?.toString() ?? '',
                  style: TextStyle(fontSize: 12, color: F.h(Colors.indigo, 700))),
            ])),
            Chip(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              label: Text(kMassnahmeStatusLabel[status] ?? status,
                  style: const TextStyle(fontSize: 11)),
              backgroundColor: offen ? F.h(Colors.green, 100) : F.h(Colors.grey, 200),
            ),
          ]),
          const Divider(height: 16),

          // ⚠️ „Konnte nicht entschlüsselt werden" ist etwas anderes als
          // „nichts erfasst". Ohne diesen Hinweis sähe beides gleich aus, und
          // das nächste Speichern schriebe das Nichts fest.
          if (!lesbar)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: F.h(Colors.red, 50),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: F.h(Colors.red, 200)),
              ),
              child: Text(
                '⚠ Mindestens ein Textfeld konnte nicht entschlüsselt werden. '
                'Die Angaben sind NICHT leer — bitte nicht überschreiben, sondern melden.',
                style: TextStyle(fontSize: 11, color: F.h(Colors.red, 900)),
              ),
            ),

          if (beginn != null || ende != null)
            _zeile(Icons.date_range, 'Zeitraum',
                '${beginn != null ? df.format(beginn) : "?"} – ${ende != null ? df.format(ende) : "offen"}'),
          if ((z['stunden_woche'] ?? '').toString().isNotEmpty)
            _zeile(Icons.schedule, 'Stunden/Woche', z['stunden_woche'].toString()),
          if ((z['durchfuehrungsort'] ?? '').toString().isNotEmpty)
            _zeile(Icons.place_outlined, 'Durchführungsort', z['durchfuehrungsort'].toString()),
          if ((z['massnahmenummer'] ?? '').toString().isNotEmpty)
            _zeile(Icons.tag, 'Maßnahmenummer', z['massnahmenummer'].toString()),
          if ((z['aktenzeichen'] ?? '').toString().isNotEmpty)
            _zeile(Icons.folder_outlined, 'Aktenzeichen', z['aktenzeichen'].toString()),
          _zeile(Icons.gavel, 'Rechtsgrundlage',
              z['rechtsgrundlage']?.toString() ?? kMassnahmeRechtsgrundlage),

          // Widerspruchsfrist, § 84 Abs. 1 SGG.
          if (tage != null && offen)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tage < 0 ? F.h(Colors.grey, 100)
                    : (tage <= 7 ? F.h(Colors.red, 50) : F.h(Colors.amber, 50)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tage < 0
                    ? 'Widerspruchsfrist (§ 84 Abs. 1 SGG) ist seit ${-tage} Tagen abgelaufen.'
                    : 'Widerspruchsfrist (§ 84 Abs. 1 SGG) läuft in $tage Tagen ab '
                      '(${df.format(massnahmeWiderspruchsfrist(bekanntgabe)!)}).',
                style: const TextStyle(fontSize: 11.5),
              ),
            ),

          // Die Daten des Trägers — der eigentliche Grund für den Katalog.
          const Divider(height: 18),
          Text('Träger', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
              color: F.h(Colors.grey, 700))),
          const SizedBox(height: 4),
          if ((z['rechtstraeger'] ?? '').toString().isNotEmpty)
            _zeile(Icons.business, 'Rechtsträger', z['rechtstraeger'].toString()),
          if ((z['strasse'] ?? '').toString().isNotEmpty)
            _zeile(Icons.location_on_outlined, 'Anschrift',
                '${z['strasse']}, ${z['plz'] ?? ''} ${z['ort'] ?? ''}'.trim()),
          if ((z['telefon'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Icon(Icons.phone, size: 14, color: F.h(Colors.grey, 600)),
                const SizedBox(width: 6),
                SizedBox(width: 110, child: Text('Telefon',
                    style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700)))),
                Expanded(child: PhoneText(z['telefon'].toString(),
                    style: const TextStyle(fontSize: 11.5))),
              ]),
            ),
          if ((z['email'] ?? '').toString().isNotEmpty)
            _zeile(Icons.mail_outline, 'E-Mail', z['email'].toString()),
          if ((z['ansprechpartner'] ?? '').toString().isNotEmpty)
            _zeile(Icons.person_outline, 'Ansprechpartner', z['ansprechpartner'].toString()),

          // ⚠️ NULL heißt „nicht geprüft", nicht „nicht zugelassen". Die
          // AZAV-Zulassung erteilt eine fachkundige Stelle, nicht wir.
          if (z['azav_geprueft'] == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('AZAV-Zulassung: nicht geprüft',
                  style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600),
                      fontStyle: FontStyle.italic)),
            ),

          if ((z['notiz'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(z['notiz'].toString(), style: const TextStyle(fontSize: 11.5)),
          ],

          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.touch_app_outlined, size: 13, color: F.h(Colors.indigo, 400)),
            const SizedBox(width: 4),
            Expanded(child: Text('Tippen für Bewilligung und Korrespondenz',
                style: TextStyle(fontSize: 10.5, color: F.h(Colors.indigo, 400)))),
            TextButton.icon(
              onPressed: () => _bearbeiten(z),
              icon: const Icon(Icons.edit, size: 15),
              label: const Text('Bearbeiten', style: TextStyle(fontSize: 12)),
            ),
            TextButton.icon(
              onPressed: () => _loeschen(z),
              icon: const Icon(Icons.delete_outline, size: 15, color: Colors.red),
              label: const Text('Entfernen',
                  style: TextStyle(fontSize: 12, color: Colors.red)),
            ),
          ]),
        ]),
      ),
      ),
    );
  }

  /// ⚠️ Die Detailansicht kann Korrespondenz und Dokumente ändern; danach neu
  /// laden, sonst zeigt die Karte den Anhangzähler von vorhin.
  Future<void> _detailOeffnen(Map<String, dynamic> z) async {
    final geaendert = await showDialog<bool>(
      context: context,
      builder: (_) => MassnahmeDetailModal(
        apiService: widget.apiService,
        userId: widget.userId,
        zuweisung: z,
      ),
    );
    if (geaendert == true) { widget.onChanged?.call(); _laden(); }
  }

  Widget _zeile(IconData ic, String label, String wert) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ic, size: 14, color: F.h(Colors.grey, 600)),
          const SizedBox(width: 6),
          SizedBox(width: 110, child: Text(label,
              style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700)))),
          Expanded(child: Text(wert, style: const TextStyle(fontSize: 11.5))),
        ]),
      );
}

/// Anlegen und Bearbeiten einer Zuweisung.
///
/// Erst der Träger, dann sein Angebot — dieselbe Reihenfolge wie beim
/// Arbeitsvermittler (erst das Jobcenter, dann die Person). Beides lässt sich
/// hier auch neu anlegen: der Katalog ist ein Startbestand, keine feste Liste.
class _ZuweisungDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int userAvId;
  final Map<String, dynamic>? vorhanden;
  const _ZuweisungDialog({
    required this.apiService,
    required this.userId,
    required this.userAvId,
    this.vorhanden,
  });
  @override
  State<_ZuweisungDialog> createState() => _ZuweisungDialogState();
}

class _ZuweisungDialogState extends State<_ZuweisungDialog> {
  List<Map<String, dynamic>> _traeger = [];
  List<Map<String, dynamic>> _angebote = [];
  int? _traegerId;
  int? _angebotId;
  String _status = 'zugewiesen';
  bool _laden = true, _busy = false;

  final _zuweisung = TextEditingController();
  final _bekanntgabe = TextEditingController();
  final _beginn = TextEditingController();
  final _ende = TextEditingController();
  final _stunden = TextEditingController();
  final _ort = TextEditingController();
  final _az = TextEditingController();
  final _notiz = TextEditingController();

  @override
  void initState() {
    super.initState();
    final v = widget.vorhanden;
    if (v != null) {
      _traegerId = mnZahl(v['traeger_id']);
      _angebotId = mnZahl(v['massnahme_id']);
      _status = v['status']?.toString() ?? 'zugewiesen';
      _zuweisung.text = _iso(v['zuweisung_datum']);
      _bekanntgabe.text = _iso(v['bekanntgabe_datum']);
      _beginn.text = _iso(v['beginn']);
      _ende.text = _iso(v['ende']);
      _stunden.text = (v['stunden_woche'] ?? '').toString();
      _ort.text = (v['durchfuehrungsort'] ?? '').toString();
      _az.text = (v['aktenzeichen'] ?? '').toString();
      _notiz.text = (v['notiz'] ?? '').toString();
    }
    _traegerLaden();
  }

  static String _iso(dynamic v) {
    final d = massnahmeDatum(v);
    return d == null ? '' : d.toIso8601String().substring(0, 10);
  }

  @override
  void dispose() {
    for (final c in [_zuweisung, _bekanntgabe, _beginn, _ende, _stunden, _ort, _az, _notiz]) {
      c.dispose();
    }
    super.dispose();
  }

  void _melden(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _traegerLaden() async {
    final r = await widget.apiService.massnahmeAction({'action': 'list_traeger'});
    if (!mounted) return;
    setState(() {
      _traeger = (r['success'] == true && r['traeger'] is List)
          ? List<Map<String, dynamic>>.from(
              (r['traeger'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
          : [];
      _laden = false;
    });
    if (_traegerId != null) _angeboteLaden(_traegerId!);
  }

  Future<void> _angeboteLaden(int tid) async {
    final r = await widget.apiService.massnahmeAction({
      'action': 'list_angebote', 'traeger_id': tid,
    });
    if (!mounted) return;
    setState(() {
      _angebote = (r['success'] == true && r['angebote'] is List)
          ? List<Map<String, dynamic>>.from(
              (r['angebote'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
          : [];
      // Amtlich belegte Maßnahmen zuerst: die mit einer Maßnahmenummer stammen
      // aus einem Zuweisungsbescheid, die übrigen von der Werbeseite des
      // Trägers. ⚠️ Beide Titel weichen regelmäßig voneinander ab — im Bescheid
      // vom 04.09.2026 heißt dieselbe Sache „Coaching für Menschen mit Flucht-
      // oder Migrationshintergrund", auf der Webseite „Coaching on the Job".
      _angebote.sort((a, b) {
        final an = (a['massnahmenummer'] ?? '').toString().isEmpty;
        final bn = (b['massnahmenummer'] ?? '').toString().isEmpty;
        if (an != bn) return an ? 1 : -1;
        return (a['titel'] ?? '').toString().compareTo((b['titel'] ?? '').toString());
      });
      // Ein Angebot, das nicht zu diesem Träger gehört, darf nicht ausgewählt
      // bleiben — sonst zeigt der Schirm eine Zusammenstellung, die es nicht gibt.
      if (!_angebote.any((a) => mnZahl(a['id']) == _angebotId)) _angebotId = null;
    });
  }

  Future<void> _datumWaehlen(TextEditingController c) async {
    final jetzt = DateTime.now();
    final vor = massnahmeDatum(c.text) ?? jetzt;
    final d = await showDatePicker(
      context: context, initialDate: vor,
      firstDate: DateTime(jetzt.year - 5), lastDate: DateTime(jetzt.year + 5),
    );
    if (d != null) setState(() => c.text = d.toIso8601String().substring(0, 10));
  }

  Future<void> _neuerTraeger() async {
    final name = TextEditingController();
    final strasse = TextEditingController();
    final plz = TextEditingController();
    final ort = TextEditingController();
    final tel = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Neuer Träger', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name *')),
          TextField(controller: strasse, decoration: const InputDecoration(labelText: 'Straße')),
          Row(children: [
            SizedBox(width: 90, child: TextField(controller: plz,
                decoration: const InputDecoration(labelText: 'PLZ'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: ort,
                decoration: const InputDecoration(labelText: 'Ort'))),
          ]),
          TextField(controller: tel, decoration: const InputDecoration(labelText: 'Telefon')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Anlegen')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final r = await widget.apiService.massnahmeAction({
        'action': 'save_traeger', 'name': name.text.trim(),
        'strasse': strasse.text.trim(), 'plz': plz.text.trim(),
        'ort': ort.text.trim(), 'telefon': tel.text.trim(),
        'quelle': 'von Hand erfasst',
      });
      if (r['success'] == true) {
        await _traegerLaden();
        if (mounted) setState(() { _traegerId = mnZahl(r['id']); _angebote = []; _angebotId = null; });
      } else {
        _melden(r['message']?.toString() ?? 'Konnte nicht angelegt werden');
      }
    }
    for (final c in [name, strasse, plz, ort, tel]) { c.dispose(); }
  }

  Future<void> _neuesAngebot() async {
    if (_traegerId == null) { _melden('Erst einen Träger wählen'); return; }
    final titel = TextEditingController();
    final nummer = TextEditingController();
    String art = 'MAT';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c2, setD) => AlertDialog(
        title: const Text('Neues Angebot', style: TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titel, decoration: const InputDecoration(labelText: 'Titel *')),
          TextField(controller: nummer,
              decoration: const InputDecoration(labelText: 'Maßnahmenummer')),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: art,
            decoration: const InputDecoration(labelText: 'Art'),
            items: kMassnahmeArten.map((a) => DropdownMenuItem(
                value: a, child: Text(kMassnahmeArtLabel[a] ?? a,
                    style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) => setD(() => art = v ?? 'MAT'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Anlegen')),
        ],
      )),
    );
    if (ok == true && titel.text.trim().isNotEmpty) {
      final r = await widget.apiService.massnahmeAction({
        'action': 'save_angebot', 'traeger_id': _traegerId,
        'titel': titel.text.trim(), 'massnahmenummer': nummer.text.trim(), 'art': art,
        'quelle': 'von Hand erfasst',
      });
      if (r['success'] == true) {
        await _angeboteLaden(_traegerId!);
        if (mounted) setState(() => _angebotId = mnZahl(r['id']));
      } else {
        _melden(r['message']?.toString() ?? 'Konnte nicht angelegt werden');
      }
    }
    titel.dispose(); nummer.dispose();
  }

  Future<void> _speichern() async {
    if (_angebotId == null) { _melden('Bitte eine Maßnahme wählen'); return; }
    setState(() => _busy = true);
    final r = await widget.apiService.massnahmeAction({
      'action': 'save_user_massnahme',
      if (widget.vorhanden != null) 'id': widget.vorhanden!['id'],
      'user_id': widget.userId,
      'massnahme_id': _angebotId,
      'user_av_id': widget.userAvId,
      'zuweisung_datum': _zuweisung.text,
      'bekanntgabe_datum': _bekanntgabe.text,
      'beginn': _beginn.text,
      'ende': _ende.text,
      'stunden_woche': _stunden.text.trim().replaceAll(',', '.'),
      'durchfuehrungsort': _ort.text.trim(),
      'aktenzeichen': _az.text.trim(),
      'status': _status,
      'notiz': _notiz.text.trim(),
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['success'] == true) {
      Navigator.pop(context, true);
    } else {
      // ⚠️ Der Grund gehört auf den Schirm. Ein stilles Zurücknehmen sieht
      // aus wie „ich habe danebengetippt" — dieselbe Lehre wie bei den
      // Chat-Reaktionen.
      _melden(r['message']?.toString() ?? 'Konnte nicht gespeichert werden');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fenster = MediaQuery.of(context).size;
    final schmal = fenster.width < 600;
    return Dialog(
      insetPadding: EdgeInsets.all(schmal ? 8 : 24),
      child: SizedBox(
        width: schmal ? fenster.width * 0.96 : 560,
        height: fenster.height * (schmal ? 0.92 : 0.85),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: F.h(Colors.indigo, 700),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            child: Row(children: [
              const Icon(Icons.school_outlined, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(
                widget.vorhanden == null ? 'Neue Zuweisung' : 'Zuweisung bearbeiten',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
              IconButton(icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context, false)),
            ]),
          ),
          Expanded(
            child: _laden
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: DropdownButtonFormField<int>(
                          initialValue: _traegerId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Träger *'),
                          items: _traeger.map((t) => DropdownMenuItem(
                            value: mnZahl(t['id']),
                            child: Text('${t['name']}${(t['ort'] ?? '').toString().isNotEmpty ? " — ${t['ort']}" : ""}',
                                style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                          )).toList(),
                          onChanged: (v) {
                            setState(() { _traegerId = v; _angebote = []; _angebotId = null; });
                            if (v != null) _angeboteLaden(v);
                          },
                        )),
                        IconButton(icon: const Icon(Icons.add_business_outlined),
                            tooltip: 'Neuer Träger', onPressed: _neuerTraeger),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(child: DropdownButtonFormField<int>(
                          initialValue: _angebotId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Maßnahme *',
                            helperText: _traegerId == null
                                ? 'Erst einen Träger wählen'
                                : (_angebote.isEmpty ? 'Dieser Träger hat noch kein Angebot' : null),
                          ),
                          items: _angebote.map((a) {
                            final nr = (a['massnahmenummer'] ?? '').toString();
                            return DropdownMenuItem(
                              value: mnZahl(a['id']),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a['titel']?.toString() ?? '',
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis),
                                  // ⚠️ Ohne Maßnahmenummer stammt der Titel von der
                                  // Webseite des Trägers und ist NICHT die Bezeichnung,
                                  // die im Zuweisungsbescheid steht.
                                  Text(nr.isEmpty
                                          ? 'nur Webseite — Bezeichnung im Bescheid prüfen'
                                          : 'Nr. $nr — aus Bescheid',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: nr.isEmpty
                                              ? F.h(Colors.orange, 800)
                                              : F.h(Colors.green, 800))),
                                ],
                              ),
                            );
                          }).toList(),
                          selectedItemBuilder: (_) => _angebote
                              .map((a) => Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(a['titel']?.toString() ?? '',
                                        style: const TextStyle(fontSize: 13),
                                        overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _angebotId = v),
                        )),
                        IconButton(icon: const Icon(Icons.playlist_add),
                            tooltip: 'Neues Angebot', onPressed: _neuesAngebot),
                      ]),
                      const SizedBox(height: 10),
                      _datumFeld('Datum des Zuweisungsschreibens', _zuweisung),
                      _datumFeld('Bekanntgabe (Zugang beim Mitglied)', _bekanntgabe,
                          hilfe: 'Ab hier läuft die Widerspruchsfrist, § 84 Abs. 1 SGG'),
                      Row(children: [
                        Expanded(child: _datumFeld('Beginn', _beginn)),
                        const SizedBox(width: 8),
                        Expanded(child: _datumFeld('Ende', _ende)),
                      ]),
                      TextField(
                        controller: _stunden,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Stunden/Woche'),
                      ),
                      TextField(controller: _ort,
                          decoration: const InputDecoration(labelText: 'Durchführungsort')),
                      TextField(controller: _az,
                          decoration: const InputDecoration(labelText: 'Aktenzeichen')),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: kMassnahmeStatus.map((s) => DropdownMenuItem(
                            value: s, child: Text(kMassnahmeStatusLabel[s] ?? s,
                                style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (v) => setState(() => _status = v ?? 'zugewiesen'),
                      ),
                      TextField(controller: _notiz, maxLines: 3,
                          decoration: const InputDecoration(labelText: 'Notiz')),
                      const SizedBox(height: 10),
                      Text(
                        'Diese Angaben liegen verschlüsselt auf dem Server — die Teilnahme '
                        'an einer Maßnahme ist ein Sozialdatum nach § 35 SGB I.',
                        style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600)),
                      ),
                    ]),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false),
                  child: const Text('Abbrechen')),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _busy ? null : _speichern,
                style: ElevatedButton.styleFrom(
                    backgroundColor: F.h(Colors.indigo, 700), foregroundColor: Colors.white),
                child: _busy
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Speichern'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _datumFeld(String label, TextEditingController c, {String? hilfe}) => TextField(
        controller: c,
        readOnly: true,
        onTap: () => _datumWaehlen(c),
        decoration: InputDecoration(
          labelText: label,
          helperText: hilfe,
          helperMaxLines: 2,
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
      );
}
