import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/app_farben.dart';
import 'bussgeld_vorfall_dialog.dart';
import 'phone_link.dart';

/// Ein Bußgeld-Vorgang mit allem, was daran hängt.
///
/// Vier Reiter, in der Reihenfolge, in der man sie braucht: was drinsteht,
/// was hin- und hergegangen ist, ob Einspruch eingelegt wurde, und womit der
/// Verein überhaupt auftreten darf.
class BussgeldVorfallDetailsDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int vorfallId;

  const BussgeldVorfallDetailsDialog({
    super.key,
    required this.apiService,
    required this.userId,
    required this.vorfallId,
  });

  @override
  State<BussgeldVorfallDetailsDialog> createState() => _BussgeldVorfallDetailsDialogState();
}

/// Wie der Einspruch ausgegangen ist.
///
/// ⚠️ `zurueckgenommen` ist etwas anderes als „nie eingelegt": die Rücknahme
/// lässt den Bescheid rechtskräftig werden und muss im Verlauf sichtbar
/// bleiben.
/// Wege, auf denen die Vollmacht zur Stelle gelangt.
///
/// ⚠️ Deckungsgleich mit dem ENUM `bussgeld_vollmacht_versand.weg`. Ein Wert
/// daneben würde von MariaDB stillschweigend auf '' gekürzt — der Nachweis,
/// WIE sie hinausging, wäre dann weg.
const Map<String, String> kVersandWege = {
  'post': 'Post',
  'fax': 'Fax',
  'email': 'E-Mail',
  'persoenlich': 'Persönlich abgegeben',
  'sonstige': 'Sonstiger Weg',
};

const Map<String, String> kEinspruchErgebnisse = {
  'offen': 'noch offen',
  'abgeholfen': 'Behörde hat abgeholfen',
  'eingestellt': 'Verfahren eingestellt',
  'an_gericht': 'an das Amtsgericht abgegeben',
  'verworfen': 'als unzulässig verworfen',
  'zurueckgenommen': 'zurückgenommen',
};

class _BussgeldVorfallDetailsDialogState extends State<BussgeldVorfallDetailsDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  Map<String, dynamic>? _vorfall;
  List<Map<String, dynamic>> _korrespondenz = [];
  List<Map<String, dynamic>> _dokumente = [];
  Map<String, dynamic>? _einspruch;
  List<Map<String, dynamic>> _vollmachten = [];
  Map<String, dynamic>? _vmOptionen;

  bool _laedt = true;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _laden();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _laden() async {
    setState(() { _laedt = true; _fehler = null; });
    final r = await widget.apiService.getBussgeldVorfallDetails(widget.userId, widget.vorfallId);
    if (!mounted) return;
    if (r['success'] != true) {
      setState(() { _laedt = false; _fehler = (r['message'] ?? 'Laden fehlgeschlagen').toString(); });
      return;
    }
    // Die Optionen ändern sich nicht — einmal holen reicht.
    _vmOptionen ??= await () async {
      final o = await widget.apiService.bussgeldVollmachtOptionen();
      return o['success'] == true ? o : null;
    }();
    if (!mounted) return;
    setState(() {
      _vorfall = _map(r['vorfall']);
      _korrespondenz = _liste(r['korrespondenz']);
      _dokumente = _liste(r['dokumente']);
      _einspruch = _map(r['einspruch']);
      _vollmachten = _liste(r['vollmachten']);
      _laedt = false;
    });
  }

  static Map<String, dynamic>? _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  static List<Map<String, dynamic>> _liste(dynamic v) => v is List
      ? List<Map<String, dynamic>>.from(v.map((e) => Map<String, dynamic>.from(e as Map)))
      : <Map<String, dynamic>>[];

  void _sagen(String text, {bool fehler = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler ? F.h(Colors.red, 700) : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final az = _vorfall?['aktenzeichen']?.toString();
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 820,
        height: 680,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            color: F.h(Colors.deepOrange, 700),
            child: Row(children: [
              const Icon(Icons.gavel, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(az == null || az.isEmpty ? 'Bußgeld-Vorgang' : az,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
                if (_vorfall?['stelle_db_name'] != null || _vorfall?['stelle_name'] != null)
                  Text('${_vorfall?['stelle_db_name'] ?? _vorfall?['stelle_name']}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
              ])),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context, true),
              ),
            ]),
          ),
          Container(
            color: F.h(Colors.deepOrange, 50),
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: F.h(Colors.deepOrange, 800),
              unselectedLabelColor: F.h(Colors.grey, 600),
              indicatorColor: F.h(Colors.deepOrange, 700),
              tabs: [
                const Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
                Tab(icon: const Icon(Icons.mail_outline, size: 18),
                    text: 'Korrespondenz${_korrespondenz.isEmpty ? '' : ' (${_korrespondenz.length})'}'),
                Tab(icon: Icon(_einspruch == null ? Icons.gavel_outlined : Icons.check_circle_outline, size: 18),
                    text: 'Widerspruch'),
                Tab(icon: const Icon(Icons.assignment_ind_outlined, size: 18),
                    text: 'Vollmacht${_vollmachten.isEmpty ? '' : ' (${_vollmachten.length})'}'),
              ],
            ),
          ),
          Expanded(child: _laedt
              ? const Center(child: CircularProgressIndicator())
              : _fehler != null
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.error_outline, size: 40, color: F.h(Colors.red, 400)),
                        const SizedBox(height: 10),
                        Text(_fehler!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _laden, child: const Text('Nochmal versuchen')),
                      ])))
                  : TabBarView(controller: _tabs, children: [
                      _details(), _korrespondenzTab(), _widerspruchTab(), _vollmachtTab(),
                    ])),
        ]),
      ),
    );
  }

  // ===================================================== Details ==========
  Widget _details() {
    final v = _vorfall!;
    final tage = v['tage_bis_frist'];
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (v['frist_bis'] != null) _fristBanner(v['frist_bis'].toString(), tage is int ? tage : null),
      _block('Schreiben', [
        _kv('Art', kBussgeldArten[v['art']] ?? v['art']?.toString()),
        _kv('Aktenzeichen', v['aktenzeichen']?.toString()),
        _kv('Datum des Schreibens', _datum(v['bescheid_datum'])),
        _kv('Zugegangen am', _datum(v['zugang_datum'])),
        _kv('Status', kBussgeldStatus[v['status']] ?? v['status']?.toString()),
      ]),
      _block('Vorwurf und Tat', [
        _kv('Vorwurf', v['vorwurf']?.toString()),
        _kv('Tatbestandsnummer', v['tbnr']?.toString()),
        _kv('Kennzeichen', v['kennzeichen']?.toString()),
        _kv('Tatzeit', _tatzeit(v)),
        _kv('Tatort', _tatort(v)),
        _kv('Selbst gefahren', switch (v['fahrer_war_mitglied']) {
          'ja' => 'ja', 'nein' => 'nein', _ => 'unbekannt / offen',
        }),
      ]),
      _block('Beträge und Folgen', [
        _kv('Geldbuße', _euro(v['betrag_geldbusse'])),
        _kv('Gebühren', _euro(v['betrag_gebuehren'])),
        _kv('Auslagen', _euro(v['betrag_auslagen'])),
        _kv('Gesamt', _euro(v['betrag_gesamt']), fett: true),
        _kv('Punkte in Flensburg', v['punkte']?.toString()),
        _kv('Fahrverbot', v['fahrverbot_monate'] == null || v['fahrverbot_monate'] == 0
            ? null : '${v['fahrverbot_monate']} Monat(e)'),
        _kv('Bezahlt am', _datum(v['bezahlt_am'])),
      ]),
      _block('Zuständige Stelle', [
        _kv('Name', (v['stelle_db_name'] ?? v['stelle_name'])?.toString()),
        // ⚠️ Post- und Besuchsanschrift getrennt: die Zentrale Bußgeldstelle
        // BW hat als Postanschrift nur „76073 Karlsruhe" ohne Straße —
        // dorthin geht der fristgebundene Einspruch, das Haus steht in 76131.
        _kv('Postanschrift', _anschrift(v['strasse'], v['plz'], v['ort'])),
        _kv('Besuchsanschrift', _anschrift(v['besuch_strasse'], v['besuch_plz'], v['besuch_ort'])),
        _kvTelefon('Telefon', v['telefon']?.toString()),
        _kvTelefon('Fax', v['fax']?.toString()),
        _kv('E-Mail', v['email']?.toString()),
        _kv('Zuständigkeit', v['zustaendigkeit']?.toString()),
      ]),
      if ((v['sachbearbeiter_name']?.toString().isNotEmpty ?? false) ||
          (v['beschreibung']?.toString().isNotEmpty ?? false))
        _block('Sachbearbeitung und Notizen', [
          _kv('Sachbearbeiter/in', v['sachbearbeiter_name']?.toString()),
          _kvTelefon('Telefon', v['sachbearbeiter_telefon']?.toString()),
          _kv('Notizen', v['beschreibung']?.toString()),
        ]),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.edit, size: 18),
        label: const Text('Angaben bearbeiten'),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => BussgeldVorfallDialog(
              apiService: widget.apiService,
              userId: widget.userId,
              stelleId: _vorfall?['stelle_id'] is int ? _vorfall!['stelle_id'] as int : null,
              stelleName: (_vorfall?['stelle_db_name'] ?? _vorfall?['stelle_name'])?.toString(),
              vorfall: _vorfall,
            ),
          );
          if (ok == true) _laden();
        },
      ),
      if (_dokumente.isNotEmpty) ...[
        const SizedBox(height: 12),
        _block('Dokumente', [
          for (final d in _dokumente)
            _kv(_datum(d['created_at']) ?? '', d['original_name']?.toString()),
        ]),
      ],
    ]);
  }

  Widget _fristBanner(String frist, int? tage) {
    final abgelaufen = tage != null && tage < 0;
    final knapp = tage != null && tage >= 0 && tage <= 3;
    final erledigt = _einspruch != null && (_einspruch!['eingelegt_am'] != null);
    final farbe = erledigt
        ? Colors.green
        : abgelaufen
            ? Colors.red
            : knapp
                ? Colors.orange
                : Colors.blueGrey;
    final text = erledigt
        ? 'Einspruch am ${_datum(_einspruch!['eingelegt_am'])} eingelegt.'
        : abgelaufen
            ? 'Die Frist ist am ${_datum(frist)} abgelaufen (vor ${-tage} Tagen).'
            : tage == 0
                ? 'Die Frist endet HEUTE, ${_datum(frist)}.'
                : 'Noch $tage Tage — die Frist endet am ${_datum(frist)}.';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: F.h(farbe, 50),
        border: Border.all(color: F.h(farbe, 200)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(erledigt ? Icons.check_circle : abgelaufen ? Icons.error_outline : Icons.schedule,
            color: F.h(farbe, 700)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: F.h(farbe, 800))),
          const SizedBox(height: 2),
          Text('Zwei Wochen ab Zustellung (§ 67 Abs. 1 OWiG). Feiertage sind nicht berücksichtigt.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
        ])),
      ]),
    );
  }

  // ================================================ Korrespondenz =========
  Widget _korrespondenzTab() {
    final eingang = _korrespondenz.where((k) => k['richtung'] == 'eingang').toList();
    final ausgang = _korrespondenz.where((k) => k['richtung'] == 'ausgang').toList();
    return Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Korrespondenz (${_korrespondenz.length})',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
          ElevatedButton.icon(
            key: const Key('bg_korr_add'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Eintrag'),
            style: ElevatedButton.styleFrom(
                backgroundColor: F.h(Colors.deepOrange, 700), foregroundColor: Colors.white),
            onPressed: _korrespondenzAnlegen,
          ),
        ]),
        const Divider(height: 20),
        Expanded(child: _korrespondenz.isEmpty
            ? _leer(Icons.mail_outline, 'Noch kein Schriftverkehr erfasst',
                'Jedes Schreiben der Stelle und jede Antwort gehört hier hinein — '
                'das ist später der Nachweis, wann was gelaufen ist.')
            : ListView(children: [
                if (eingang.isNotEmpty) ...[
                  _abschnitt('Eingang', Icons.inbox, Colors.green),
                  ...eingang.map(_korrZeile),
                ],
                if (ausgang.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _abschnitt('Ausgang', Icons.outbox, Colors.orange),
                  ...ausgang.map(_korrZeile),
                ],
              ])),
      ]));
  }

  Widget _korrZeile(Map<String, dynamic> k) => Card(
        margin: const EdgeInsets.only(bottom: 6),
        child: ListTile(
          dense: true,
          title: Text(k['betreff']?.toString() ?? '(ohne Betreff)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (k['inhalt'] != null) Text(k['inhalt'].toString(), style: const TextStyle(fontSize: 12)),
            Wrap(spacing: 12, children: [
              if (k['datum'] != null) Text(_datum(k['datum'])!, style: const TextStyle(fontSize: 11)),
              if (k['absender'] != null) Text('von ${k['absender']}', style: const TextStyle(fontSize: 11)),
              if (k['empfaenger'] != null) Text('an ${k['empfaenger']}', style: const TextStyle(fontSize: 11)),
            ]),
          ]),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: F.h(Colors.red, 600),
            onPressed: () => _korrespondenzLoeschen(k),
          ),
        ),
      );

  Future<void> _korrespondenzAnlegen() async {
    final betreff = TextEditingController();
    final inhalt = TextEditingController();
    final wer = TextEditingController();
    DateTime? datum = DateTime.now();
    String richtung = 'eingang';

    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) => AlertDialog(
        title: const Text('Schriftverkehr erfassen'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'eingang', label: Text('Eingang'), icon: Icon(Icons.inbox, size: 16)),
              ButtonSegment(value: 'ausgang', label: Text('Ausgang'), icon: Icon(Icons.outbox, size: 16)),
            ],
            selected: {richtung},
            onSelectionChanged: (v) => ss(() => richtung = v.first),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(context: ctx, initialDate: datum ?? DateTime.now(),
                  firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
              if (d != null) ss(() => datum = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Datum', border: OutlineInputBorder(), isDense: true),
              child: Text(datum == null ? '—' : _datum(_iso(datum!))!),
            ),
          ),
          const SizedBox(height: 10),
          TextField(controller: betreff, decoration: const InputDecoration(
              labelText: 'Betreff', border: OutlineInputBorder(), isDense: true)),
          const SizedBox(height: 10),
          TextField(controller: wer, decoration: InputDecoration(
              labelText: richtung == 'eingang' ? 'Absender' : 'Empfänger',
              border: const OutlineInputBorder(), isDense: true)),
          const SizedBox(height: 10),
          TextField(controller: inhalt, maxLines: 3, decoration: const InputDecoration(
              labelText: 'Inhalt / Notiz', border: OutlineInputBorder(), isDense: true)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Speichern')),
        ],
      ),
    ));
    if (ok != true) return;

    final r = await widget.apiService.bussgeldVorfallAktion({
      'action': 'add_korrespondenz',
      'user_id': widget.userId,
      'vorfall_id': widget.vorfallId,
      'richtung': richtung,
      'datum': datum == null ? null : _iso(datum!),
      'betreff': betreff.text.trim(),
      'inhalt': inhalt.text.trim(),
      if (richtung == 'eingang') 'absender': wer.text.trim() else 'empfaenger': wer.text.trim(),
    });
    if (r['success'] == true) {
      _laden();
    } else {
      _sagen('Nicht gespeichert: ${r['message'] ?? 'unbekannter Fehler'}', fehler: true);
    }
  }

  Future<void> _korrespondenzLoeschen(Map<String, dynamic> k) async {
    final r = await widget.apiService.bussgeldVorfallAktion({
      'action': 'delete_korrespondenz',
      'user_id': widget.userId,
      'vorfall_id': widget.vorfallId,
      'id': k['id'],
    });
    if (r['success'] == true) {
      _laden();
    } else {
      _sagen('Nicht gelöscht: ${r['message'] ?? 'unbekannter Fehler'}', fehler: true);
    }
  }

  // =================================================== Widerspruch ========
  Widget _widerspruchTab() {
    final e = _einspruch;
    final frist = _vorfall?['frist_bis']?.toString();
    return ListView(padding: const EdgeInsets.all(16), children: [
      // ⚠️ Der Reiter heißt „Widerspruch", das Schreiben heißt Einspruch.
      // Das ist keine Wortklauberei: gegen einen Bußgeldbescheid gibt es nach
      // § 67 OWiG den Einspruch zur Behörde, von dort geht die Sache ans
      // Amtsgericht. Der Widerspruch nach § 68 VwGO ist ein anderer Weg mit
      // anderer Frist. Auf dem Schreiben muss das richtige Wort stehen.
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: F.h(Colors.blue, 50),
          border: Border.all(color: F.h(Colors.blue, 200)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 18, color: F.h(Colors.blue, 700)),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Der Rechtsbehelf gegen einen Bußgeldbescheid heißt EINSPRUCH (§ 67 OWiG), nicht Widerspruch. '
            'Er geht schriftlich oder zur Niederschrift an die Behörde, die den Bescheid erlassen hat — '
            'nicht an das Gericht.',
            style: TextStyle(fontSize: 12, color: F.h(Colors.blue, 900)),
          )),
        ]),
      ),
      const SizedBox(height: 14),
      if (e == null)
        _leer(Icons.gavel_outlined, 'Kein Einspruch erfasst',
            frist == null
                ? 'Sobald ein Einspruch eingelegt wurde, hier eintragen.'
                : 'Die Frist endet am ${_datum(frist)}.')
      else ...[
        if (e['innerhalb_frist'] == false)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: F.h(Colors.red, 50),
              border: Border.all(color: F.h(Colors.red, 300)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(Icons.error_outline, color: F.h(Colors.red, 700)),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'Eingelegt am ${_datum(e['eingelegt_am'])}, die Frist endete am ${_datum(frist)}. '
                'Möglicher Weg: Wiedereinsetzung in den vorigen Stand (§ 52 OWiG) — dafür zählt, '
                'warum die Frist versäumt wurde.',
                style: TextStyle(fontSize: 12, color: F.h(Colors.red, 900)),
              )),
            ]),
          ),
        _block('Einspruch', [
          _kv('Eingelegt am', _datum(e['eingelegt_am'])),
          _kv('Weg', kEinspruchWege[e['weg']] ?? e['weg']?.toString()),
          _kv('Beschränkt auf', e['beschraenkt_auf']?.toString()),
          _kv('Begründung', e['begruendung']?.toString()),
          _kv('Eingang bestätigt', e['eingang_bestaetigt'] == 1 ? 'ja, am ${_datum(e['bestaetigt_am']) ?? '—'}' : null),
          _kv('Zurückgenommen am', _datum(e['zurueckgenommen_am'])),
          _kv('Ergebnis', kEinspruchErgebnisse[e['ergebnis']] ?? e['ergebnis']?.toString()),
          _kv('Ergebnis am', _datum(e['ergebnis_am'])),
          _kv('Aktenzeichen Gericht', e['gericht_aktenzeichen']?.toString()),
          _kv('Notizen', e['notizen']?.toString()),
        ]),
      ],
      const SizedBox(height: 8),
      Row(children: [
        ElevatedButton.icon(
          key: const Key('bg_einspruch_bearbeiten'),
          icon: Icon(e == null ? Icons.add : Icons.edit, size: 18),
          label: Text(e == null ? 'Einspruch erfassen' : 'Bearbeiten'),
          style: ElevatedButton.styleFrom(
              backgroundColor: F.h(Colors.deepOrange, 700), foregroundColor: Colors.white),
          onPressed: _einspruchBearbeiten,
        ),
        if (e != null) ...[
          const SizedBox(width: 8),
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Entfernen'),
            style: TextButton.styleFrom(foregroundColor: F.h(Colors.red, 600)),
            onPressed: () async {
              final r = await widget.apiService.bussgeldVorfallAktion({
                'action': 'delete_einspruch',
                'user_id': widget.userId,
                'vorfall_id': widget.vorfallId,
              });
              if (r['success'] == true) {
                _laden();
              } else {
                _sagen('Nicht entfernt: ${r['message'] ?? 'unbekannter Fehler'}', fehler: true);
              }
            },
          ),
        ],
      ]),
    ]);
  }

  Future<void> _einspruchBearbeiten() async {
    final e = _einspruch;
    final begruendung = TextEditingController(text: e?['begruendung']?.toString() ?? '');
    final beschraenkt = TextEditingController(text: e?['beschraenkt_auf']?.toString() ?? '');
    final gerichtAz = TextEditingController(text: e?['gericht_aktenzeichen']?.toString() ?? '');
    final notizen = TextEditingController(text: e?['notizen']?.toString() ?? '');
    DateTime? eingelegt = DateTime.tryParse(e?['eingelegt_am']?.toString() ?? '') ?? DateTime.now();
    DateTime? bestaetigt = DateTime.tryParse(e?['bestaetigt_am']?.toString() ?? '');
    DateTime? ergebnisAm = DateTime.tryParse(e?['ergebnis_am']?.toString() ?? '');
    DateTime? zurueck = DateTime.tryParse(e?['zurueckgenommen_am']?.toString() ?? '');
    String? weg = kEinspruchWege.containsKey(e?['weg']) ? e!['weg'] as String : 'post';
    String ergebnis = kEinspruchErgebnisse.containsKey(e?['ergebnis']) ? e!['ergebnis'] as String : 'offen';
    bool bestaetigtJa = e?['eingang_bestaetigt'] == 1;

    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) {
        Widget dat(String label, DateTime? wert, ValueChanged<DateTime?> setzen) => InkWell(
              onTap: () async {
                final d = await showDatePicker(context: ctx, initialDate: wert ?? DateTime.now(),
                    firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365 * 3)));
                if (d != null) ss(() => setzen(d));
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder(), isDense: true,
                  suffixIcon: wert == null ? const Icon(Icons.calendar_today, size: 16)
                      : IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => ss(() => setzen(null))),
                ),
                child: Text(wert == null ? '—' : _datum(_iso(wert))!),
              ),
            );
        return AlertDialog(
          title: const Text('Einspruch'),
          content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(child: dat('Eingelegt am', eingelegt, (d) => eingelegt = d)),
                const SizedBox(width: 10),
                Expanded(child: DropdownButtonFormField<String>(
                  initialValue: weg,
                  decoration: const InputDecoration(labelText: 'Weg', border: OutlineInputBorder(), isDense: true),
                  items: [for (final x in kEinspruchWege.entries)
                    DropdownMenuItem(value: x.key, child: Text(x.value))],
                  onChanged: (v) => ss(() => weg = v),
                )),
              ]),
              const SizedBox(height: 10),
              TextField(controller: beschraenkt, decoration: const InputDecoration(
                labelText: 'Beschränkt auf (§ 67 Abs. 2 OWiG)', border: OutlineInputBorder(), isDense: true,
                hintText: 'z.B. nur auf den Rechtsfolgenausspruch')),
              const SizedBox(height: 10),
              TextField(controller: begruendung, maxLines: 3, decoration: const InputDecoration(
                labelText: 'Begründung', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: bestaetigtJa,
                title: const Text('Eingang von der Behörde bestätigt'),
                onChanged: (v) => ss(() => bestaetigtJa = v ?? false),
              ),
              if (bestaetigtJa) dat('Bestätigt am', bestaetigt, (d) => bestaetigt = d),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: ergebnis,
                decoration: const InputDecoration(labelText: 'Ergebnis', border: OutlineInputBorder(), isDense: true),
                items: [for (final x in kEinspruchErgebnisse.entries)
                  DropdownMenuItem(value: x.key, child: Text(x.value))],
                onChanged: (v) => ss(() => ergebnis = v ?? ergebnis),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: dat('Ergebnis am', ergebnisAm, (d) => ergebnisAm = d)),
                const SizedBox(width: 10),
                Expanded(child: dat('Zurückgenommen am', zurueck, (d) => zurueck = d)),
              ]),
              const SizedBox(height: 10),
              TextField(controller: gerichtAz, decoration: const InputDecoration(
                labelText: 'Aktenzeichen des Amtsgerichts', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 10),
              TextField(controller: notizen, maxLines: 2, decoration: const InputDecoration(
                labelText: 'Notizen', border: OutlineInputBorder(), isDense: true)),
            ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Speichern')),
          ],
        );
      },
    ));
    if (ok != true) return;

    final r = await widget.apiService.bussgeldVorfallAktion({
      'action': 'save_einspruch',
      'user_id': widget.userId,
      'vorfall_id': widget.vorfallId,
      'eingelegt_am': eingelegt == null ? null : _iso(eingelegt!),
      'weg': weg,
      'beschraenkt_auf': beschraenkt.text.trim(),
      'begruendung': begruendung.text.trim(),
      'eingang_bestaetigt': bestaetigtJa ? 1 : 0,
      'bestaetigt_am': bestaetigt == null ? null : _iso(bestaetigt!),
      'zurueckgenommen_am': zurueck == null ? null : _iso(zurueck!),
      'ergebnis': ergebnis,
      'ergebnis_am': ergebnisAm == null ? null : _iso(ergebnisAm!),
      'gericht_aktenzeichen': gerichtAz.text.trim(),
      'notizen': notizen.text.trim(),
    });
    if (r['success'] == true) {
      if (r['innerhalb_frist'] == false) {
        _sagen('Gespeichert — aber nach Ablauf der Frist am ${_datum(r['frist_bis'])}.');
      }
      _laden();
    } else {
      _sagen('Nicht gespeichert: ${r['message'] ?? 'unbekannter Fehler'}', fehler: true);
    }
  }

  // ===================================================== Vollmacht ========
  Widget _vollmachtTab() {
    final grenzen = (_vmOptionen?['grenzen'] as List?)?.cast<dynamic>() ?? const [];
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (grenzen.isNotEmpty) Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: F.h(Colors.amber, 50),
          border: Border.all(color: F.h(Colors.amber, 300)),
          borderRadius: BorderRadius.circular(8),
        ),
        // ⚠️ Dieser Block ist kein Kleingedrucktes, sondern der Grund, warum
        // die Stelle die Vollmacht annehmen kann: er sagt, dass der Verein
        // keine Rechtsdienstleistung erbringt (§ 2 Abs. 1, § 3 RDG).
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.balance, size: 18, color: F.h(Colors.amber, 900)),
            const SizedBox(width: 8),
            Text('Was diese Vollmacht nicht umfasst',
                style: TextStyle(fontWeight: FontWeight.bold, color: F.h(Colors.amber, 900))),
          ]),
          const SizedBox(height: 6),
          for (final g in grenzen)
            Padding(padding: const EdgeInsets.only(bottom: 3),
                child: Text('– $g', style: const TextStyle(fontSize: 11.5))),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: Text('Vollmachten (${_vollmachten.length})',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
        ElevatedButton.icon(
          key: const Key('bg_vollmacht_neu'),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Neue Vollmacht'),
          style: ElevatedButton.styleFrom(
              backgroundColor: F.h(Colors.deepOrange, 700), foregroundColor: Colors.white),
          onPressed: _vmOptionen == null ? null : _vollmachtAnlegen,
        ),
      ]),
      const Divider(height: 20),
      if (_vollmachten.isEmpty)
        _leer(Icons.assignment_ind_outlined, 'Noch keine Vollmacht',
            'Ohne sie darf der Verein bei dieser Stelle nichts erfragen und nichts entgegennehmen.')
      else
        ..._vollmachten.map(_vollmachtZeile),
    ]);
  }

  Widget _vollmachtZeile(Map<String, dynamic> vm) {
    final widerrufen = vm['status'] == 'revoked';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(widerrufen ? Icons.cancel_outlined : Icons.assignment_ind,
                color: widerrufen ? F.h(Colors.grey, 500) : F.h(Colors.deepOrange, 700)),
            const SizedBox(width: 8),
            Expanded(child: Text('Vollmacht #${vm['id']}',
                style: TextStyle(fontWeight: FontWeight.bold,
                    decoration: widerrufen ? TextDecoration.lineThrough : null))),
            Chip(
              label: Text(switch (vm['status']) {
                'draft' => 'Entwurf',
                'wartet_unterschrift' => 'wartet auf Unterschrift',
                'aktiv' => 'aktiv',
                'revoked' => 'widerrufen',
                'expired' => 'abgelaufen',
                _ => vm['status'].toString(),
              }, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 4),
          Text('Erteilt ${_datum(vm['erteilt_am']) ?? '—'} · gültig '
              '${vm['gueltig_bis'] == null ? 'bis auf Widerruf' : 'bis ${_datum(vm['gueltig_bis'])}'}',
              style: const TextStyle(fontSize: 11.5)),
          if (widerrufen && vm['revoked_reason'] != null)
            Text('Widerrufen: ${vm['revoked_reason']}',
                style: TextStyle(fontSize: 11.5, color: F.h(Colors.red, 700))),
          // Wann sie WIRKLICH bei der Stelle war. Eine Vollmacht, die im
          // Ordner liegt, wirkt nicht; die Behörde muss sie haben.
          for (final vs in _liste(vm['versand']))
            Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [
              Icon(Icons.check, size: 14, color: F.h(Colors.green, 700)),
              const SizedBox(width: 4),
              Expanded(child: Text(
                '${kVersandWege[vs['weg']] ?? vs['weg']}'
                '${vs['versendet_am'] == null ? '' : ' am ${_datum(vs['versendet_am'])}'}'
                '${vs['empfaenger'] == null ? '' : ' an ${vs['empfaenger']}'}',
                style: const TextStyle(fontSize: 11))),
            ])),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('PDF'),
              onPressed: () => _vollmachtPdf(vm['id'] as int),
            ),
            if (!widerrufen) OutlinedButton.icon(
              icon: const Icon(Icons.send_outlined, size: 16),
              label: const Text('Versand vermerken'),
              onPressed: () => _versandVermerken(vm['id'] as int),
            ),
            if (!widerrufen) TextButton.icon(
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: const Text('Widerrufen'),
              style: TextButton.styleFrom(foregroundColor: F.h(Colors.red, 600)),
              onPressed: () => _vollmachtWiderrufen(vm['id'] as int),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _vollmachtAnlegen() async {
    final matrix = Map<String, dynamic>.from(_vmOptionen!['umfang'] as Map);
    // Vorbelegung wie der Server sie auslegt: `auskunft` gilt, solange nicht
    // abgewählt; `organisation` nur, was angekreuzt ist.
    final gewaehlt = <String, Map<String, bool>>{
      for (final g in matrix.entries)
        g.key: {
          for (final p in (g.value['punkte'] as Map).keys)
            p.toString(): g.value['standard_an'] == true,
        },
    };
    DateTime? bis;

    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) => AlertDialog(
        title: const Text('Neue Vollmacht'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final g in matrix.entries) ...[
              Text((g.value['titel'] ?? g.key).toString().toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      letterSpacing: .6, color: F.h(Colors.grey, 700))),
              if (g.value['hinweis'] != null)
                Text(g.value['hinweis'].toString(),
                    style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
              for (final p in (g.value['punkte'] as Map).entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  value: gewaehlt[g.key]![p.key.toString()] ?? false,
                  title: Text(p.value.toString(), style: const TextStyle(fontSize: 12.5)),
                  onChanged: (v) => ss(() => gewaehlt[g.key]![p.key.toString()] = v ?? false),
                ),
              const SizedBox(height: 8),
            ],
            InkWell(
              onTap: () async {
                final d = await showDatePicker(context: ctx, initialDate: bis ?? DateTime.now(),
                    firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365 * 5)));
                if (d != null) ss(() => bis = d);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Gültig bis', border: const OutlineInputBorder(), isDense: true,
                  helperText: 'leer = bis auf Widerruf',
                  suffixIcon: bis == null ? const Icon(Icons.calendar_today, size: 16)
                      : IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => ss(() => bis = null)),
                ),
                child: Text(bis == null ? 'bis auf Widerruf' : _datum(_iso(bis!))!),
              ),
            ),
          ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Anlegen')),
        ],
      ),
    ));
    if (ok != true) return;

    final r = await widget.apiService.bussgeldVollmachtAktion({
      'action': 'create',
      'user_id': widget.userId,
      'vorfall_id': widget.vorfallId,
      'umfang': gewaehlt,
      if (bis != null) 'gueltig_bis': _iso(bis!),
    });
    if (r['success'] == true) {
      _laden();
    } else {
      // ⚠️ Grund zeigen: „keinen einzigen Punkt ausgewählt" ist eine
      // Rückmeldung, aus der man etwas machen kann.
      _sagen('Nicht angelegt: ${r['message'] ?? 'unbekannter Fehler'}', fehler: true);
    }
  }

  Future<void> _vollmachtPdf(int id) async {
    final r = await widget.apiService.downloadBussgeldVollmachtPdf(widget.userId, id);
    if (!mounted) return;
    // ⚠️ Auf die Magic Number prüfen, nicht auf den Statuscode: ein
    // JSON-Fehler kommt ebenfalls mit HTTP 200 und würde als „PDF" gespeichert.
    final istPdf = r.statusCode == 200 && r.bodyBytes.length > 4 &&
        String.fromCharCodes(r.bodyBytes.take(4)) == '%PDF';
    if (!istPdf) {
      _sagen('PDF konnte nicht erzeugt werden.', fehler: true);
      return;
    }
    _sagen('PDF erzeugt (${(r.bodyBytes.length / 1024).round()} kB) — im Vorgang abgelegt.');
    _laden();
  }

  Future<void> _versandVermerken(int vollmachtId) async {
    final empfaenger = TextEditingController();
    final notiz = TextEditingController();
    DateTime? am = DateTime.now();
    String weg = 'post';

    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) => AlertDialog(
        title: const Text('Versand vermerken'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Align(alignment: Alignment.centerLeft, child: Text(
            'Eine Vollmacht wirkt gegenüber der Behörde erst, wenn sie dort ist. '
            'Hier wird festgehalten, wann sie hinausgegangen ist.',
            style: TextStyle(fontSize: 12))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: weg,
            decoration: const InputDecoration(labelText: 'Weg', border: OutlineInputBorder(), isDense: true),
            items: [for (final e in kVersandWege.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => ss(() => weg = v ?? weg),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(context: ctx, initialDate: am ?? DateTime.now(),
                  firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 30)));
              if (d != null) ss(() => am = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Versendet am', border: OutlineInputBorder(), isDense: true),
              child: Text(am == null ? '\u2014' : _datum(_iso(am!))!),
            ),
          ),
          const SizedBox(height: 10),
          TextField(controller: empfaenger, decoration: const InputDecoration(
              labelText: 'Empfänger', border: OutlineInputBorder(), isDense: true)),
          const SizedBox(height: 10),
          TextField(controller: notiz, decoration: const InputDecoration(
              labelText: 'Notiz (z.B. Einwurf-Einschreiben Nr.)', border: OutlineInputBorder(), isDense: true)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Vermerken')),
        ],
      ),
    ));
    if (ok != true) return;
    final r = await widget.apiService.bussgeldVollmachtAktion({
      'action': 'add_versand',
      'user_id': widget.userId,
      'vollmacht_id': vollmachtId,
      'weg': weg,
      'versendet_am': am == null ? null : _iso(am!),
      'empfaenger': empfaenger.text.trim(),
      'notiz': notiz.text.trim(),
    });
    if (r['success'] == true) {
      _laden();
    } else {
      _sagen('Nicht vermerkt: ${r['message'] ?? 'unbekannter Fehler'}', fehler: true);
    }
  }

  Future<void> _vollmachtWiderrufen(int id) async {
    final grund = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Vollmacht widerrufen'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Der Widerruf wirkt gegenüber der Behörde erst mit Zugang. '
            'Die Stelle muss also zusätzlich benachrichtigt werden.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 10),
        TextField(controller: grund, decoration: const InputDecoration(
            labelText: 'Grund', border: OutlineInputBorder(), isDense: true)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Widerrufen'),
        ),
      ],
    ));
    if (ok != true) return;
    final r = await widget.apiService.bussgeldVollmachtAktion({
      'action': 'revoke', 'user_id': widget.userId, 'id': id, 'grund': grund.text.trim(),
    });
    if (r['success'] == true) {
      _laden();
    } else {
      _sagen('Nicht widerrufen: ${r['message'] ?? 'unbekannter Fehler'}', fehler: true);
    }
  }

  // ======================================================== Bausteine =====
  Widget _block(String titel, List<Widget> zeilen) {
    final sichtbar = zeilen.where((w) => w is! SizedBox).toList();
    if (sichtbar.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titel.toUpperCase(), style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: .6,
              color: F.h(Colors.grey, 600))),
          const SizedBox(height: 8),
          ...sichtbar,
        ])),
    );
  }

  /// Leere Werte fallen weg, statt als „—" Platz zu belegen.
  Widget _kv(String label, String? wert, {bool fett = false}) {
    if (wert == null || wert.trim().isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 150, child: Text(label, style: TextStyle(
            fontSize: 12, color: F.h(Colors.grey, 700)))),
        Expanded(child: Text(wert, style: TextStyle(
            fontSize: 12.5, fontWeight: fett ? FontWeight.bold : null))),
      ]));
  }

  /// ⚠️ Rufnummern durch [phoneAwareText], sonst steht die Nummer nur da.
  /// `test/rufnummern_waehlbar_test.dart` hält das projektweit fest.
  Widget _kvTelefon(String label, String? wert) {
    if (wert == null || wert.trim().isEmpty) return const SizedBox.shrink();
    final ikon = label.toLowerCase().contains('fax') ? Icons.fax : Icons.phone;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 150, child: Text(label, style: TextStyle(
            fontSize: 12, color: F.h(Colors.grey, 700)))),
        Expanded(child: phoneAwareText(ikon, wert, style: const TextStyle(fontSize: 12.5))),
      ]));
  }

  Widget _abschnitt(String text, IconData ikon, MaterialColor farbe) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(ikon, size: 15, color: F.h(farbe, 700)),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(farbe, 700))),
        ]),
      );

  Widget _leer(IconData ikon, String titel, String hinweis) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(child: Column(children: [
          Icon(ikon, size: 40, color: F.h(Colors.grey, 400)),
          const SizedBox(height: 8),
          Text(titel, style: TextStyle(color: F.h(Colors.grey, 700))),
          const SizedBox(height: 4),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(hinweis, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 500)))),
        ])),
      );

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String? _datum(dynamic iso) {
    final s = iso?.toString();
    if (s == null || s.isEmpty) return null;
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  static String? _euro(dynamic v) {
    final d = double.tryParse(v?.toString() ?? '');
    return d == null ? null : '${d.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  static String? _anschrift(dynamic strasse, dynamic plz, dynamic ort) {
    final s = strasse?.toString().trim() ?? '';
    final po = '${plz?.toString().trim() ?? ''} ${ort?.toString().trim() ?? ''}'.trim();
    final teile = [if (s.isNotEmpty) s, if (po.isNotEmpty) po];
    return teile.isEmpty ? null : teile.join(', ');
  }

  static String? _tatzeit(Map<String, dynamic> v) {
    final d = _datum(v['tatzeit_datum']);
    final st = v['tatzeit_stunde'];
    if (d == null && st == null) return null;
    if (st == null) return d;
    final zeit = '${st.toString().padLeft(2, '0')}:'
        '${(v['tatzeit_minute'] ?? 0).toString().padLeft(2, '0')}';
    return d == null ? zeit : '$d, $zeit Uhr';
  }

  static String? _tatort(Map<String, dynamic> v) {
    final teile = [
      if ((v['tatort_strasse']?.toString().trim() ?? '').isNotEmpty) v['tatort_strasse'].toString().trim(),
      if ('${v['tatort_plz'] ?? ''} ${v['tatort_ort'] ?? ''}'.trim().isNotEmpty)
        '${v['tatort_plz'] ?? ''} ${v['tatort_ort'] ?? ''}'.trim(),
      if ((v['tatort_bemerkung']?.toString().trim() ?? '').isNotEmpty) v['tatort_bemerkung'].toString().trim(),
    ];
    return teile.isEmpty ? null : teile.join(', ');
  }
}
