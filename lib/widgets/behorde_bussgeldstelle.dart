import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../utils/app_farben.dart';
import 'phone_link.dart';
import 'bussgeld_vorfall_dialog.dart';

/// Behörden-Reiter „Bußgeldstelle" — Zwilling des Polizei-Reiters daneben.
///
/// Links die zuständige Stelle, rechts die Vorfälle. Beides getrennt, weil
/// die Zuständigkeit einmal im Leben eingetragen wird und die Vorfälle
/// laufend dazukommen.
class BehordeBussgeldstelleContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final User? user;

  const BehordeBussgeldstelleContent({
    super.key,
    required this.apiService,
    required this.userId,
    this.user,
  });

  @override
  State<BehordeBussgeldstelleContent> createState() => _BehordeBussgeldstelleContentState();
}

class _BehordeBussgeldstelleContentState extends State<BehordeBussgeldstelleContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  Map<String, dynamic>? _zustaendig;
  List<Map<String, dynamic>> _vorfaelle = [];
  bool _laedt = true;

  /// Treffer der letzten Katalogsuche. Wird serverseitig gesucht, deshalb
  /// steht hier immer nur ein Ausschnitt, nie der ganze Katalog.
  List<Map<String, dynamic>> _treffer = [];
  Map<String, dynamic>? _gewaehlt;
  final _sucheCtrl = TextEditingController();
  Timer? _tippPause;
  bool _sucht = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _laden();
  }

  @override
  void dispose() {
    _tippPause?.cancel();
    _tabCtrl.dispose();
    _sucheCtrl.dispose();
    super.dispose();
  }

  Future<void> _laden() async {
    setState(() => _laedt = true);
    final r = await widget.apiService.getUserBussgeldstelle(widget.userId);
    if (!mounted) return;
    setState(() {
      _zustaendig = r['zustaendig'] is Map ? Map<String, dynamic>.from(r['zustaendig'] as Map) : null;
      _vorfaelle = r['vorfaelle'] is List
          ? List<Map<String, dynamic>>.from((r['vorfaelle'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
          : [];
      if (_zustaendig != null) {
        _sucheCtrl.text = _zustaendig!['stelle_name']?.toString() ?? '';
        _gewaehlt = _zustaendig;
      }
      _laedt = false;
    });
  }

  /// ⚠️ Mit Tipppause: ohne sie stellt jeder Tastendruck eine eigene Anfrage,
  /// und bei „Karlsruhe" wären das neun — auf genau der Mobilfunkleitung,
  /// deren Langsamkeit an anderer Stelle beim Anbieter gerügt wird.
  void _sucheAngestossen(String text) {
    _tippPause?.cancel();
    _tippPause = Timer(const Duration(milliseconds: 350), () => _suchen(text));
  }

  Future<void> _suchen(String text) async {
    if (!mounted) return;
    setState(() => _sucht = true);
    final r = await widget.apiService.sucheBussgeldstellen(q: text.trim(), limit: 25);
    if (!mounted) return;
    setState(() {
      _treffer = List<Map<String, dynamic>>.from(r['stellen'] as List);
      _sucht = false;
    });
  }

  Future<void> _stelleSpeichern() async {
    final id = _gewaehlt?['id'] ?? _gewaehlt?['stelle_id'];
    final r = await widget.apiService.saveUserBussgeldstelle(
      widget.userId,
      id is int ? id : int.tryParse(id?.toString() ?? ''),
      _sucheCtrl.text.trim().isEmpty ? null : _sucheCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r['success'] == true
          ? 'Zuständige Bußgeldstelle gespeichert'
          : 'Nicht gespeichert: ${r['message'] ?? 'unbekannter Fehler'}'),
    ));
    if (r['success'] == true) _laden();
  }

  Future<void> _vorfallDialog({Map<String, dynamic>? vorfall}) async {
    final id = _zustaendig?['stelle_id'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => BussgeldVorfallDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        stelleId: id is int ? id : int.tryParse(id?.toString() ?? ''),
        stelleName: _zustaendig?['stelle_name']?.toString(),
        vorfall: vorfall,
      ),
    );
    if (ok == true) _laden();
  }

  Future<void> _vorfallLoeschen(Map<String, dynamic> v) async {
    final sicher = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vorfall löschen?'),
        content: Text('„${v['aktenzeichen'] ?? 'ohne Aktenzeichen'}" wird endgültig entfernt. '
            'Hochgeladene Dokumente dazu ebenfalls.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (sicher != true) return;
    final r = await widget.apiService.deleteBussgeldVorfall(widget.userId, v['id'] as int);
    if (!mounted) return;
    if (r['success'] == true) {
      _laden();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nicht gelöscht: ${r['message'] ?? 'unbekannter Fehler'}')));
    }
  }

  bool get _hatStelle => (_zustaendig?['stelle_name']?.toString().isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    if (_laedt) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      TabBar(
        controller: _tabCtrl,
        labelColor: F.h(Colors.deepOrange, 800),
        unselectedLabelColor: F.h(Colors.grey, 500),
        indicatorColor: F.h(Colors.deepOrange, 700),
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: _hatStelle ? Colors.green : Colors.red),
            const SizedBox(width: 5),
            const Icon(Icons.account_balance, size: 16),
            const SizedBox(width: 5),
            const Text('Zuständige Bußgeldstelle'),
          ])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: _vorfaelle.isNotEmpty ? Colors.green : Colors.red),
            const SizedBox(width: 5),
            const Icon(Icons.gavel, size: 16),
            const SizedBox(width: 5),
            Text('Vorfälle${_vorfaelle.isNotEmpty ? ' (${_vorfaelle.length})' : ''}'),
          ])),
        ],
      ),
      Expanded(child: TabBarView(controller: _tabCtrl, children: [
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: _stelleKarte()),
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: _vorfaelleKarte()),
      ])),
    ]);
  }

  Widget _stelleKarte() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.account_balance, color: F.h(Colors.deepOrange, 700), size: 24),
            const SizedBox(width: 8),
            const Flexible(child: Text('Zuständige Bußgeldstelle',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          ]),
          const Divider(height: 24),
          TextField(
            key: const Key('bg_stelle_suche'),
            controller: _sucheCtrl,
            decoration: InputDecoration(
              labelText: 'Bußgeldstelle suchen',
              hintText: 'Name, Ort oder PLZ — z.B. Karlsruhe oder 76073',
              border: const OutlineInputBorder(),
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _sucht
                  ? const Padding(padding: EdgeInsets.all(12),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
                  : null,
            ),
            onChanged: (v) { _gewaehlt = null; _sucheAngestossen(v); },
          ),
          if (_treffer.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _treffer.length,
                  itemBuilder: (_, i) {
                    final s = _treffer[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        s['typ'] == 'zentrale_bussgeldstelle' ? Icons.account_balance : Icons.location_city,
                        size: 18, color: F.h(Colors.deepOrange, 600)),
                      title: Text(s['name']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                      subtitle: Text(_anschriftKurz(s), style: const TextStyle(fontSize: 11)),
                      onTap: () => setState(() {
                        _gewaehlt = s;
                        _sucheCtrl.text = s['name']?.toString() ?? '';
                        _treffer = [];
                      }),
                    );
                  },
                ),
              ),
            ),
          ],
          if (_gewaehlt != null || _hatStelle) _stelleInfo(_gewaehlt ?? _zustaendig!),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            key: const Key('bg_stelle_speichern'),
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Speichern'),
            style: ElevatedButton.styleFrom(
              backgroundColor: F.h(Colors.deepOrange, 700), foregroundColor: Colors.white),
            onPressed: _stelleSpeichern,
          )),
        ]),
      ),
    );
  }

  String _anschriftKurz(Map<String, dynamic> s) {
    final plz = s['plz'] ?? s['besuch_plz'];
    final ort = s['ort'] ?? s['besuch_ort'];
    final teile = [if (s['traeger'] != null) s['traeger'], if (plz != null || ort != null) '$plz $ort'.trim()];
    return teile.where((t) => t.toString().trim().isNotEmpty).join(' · ');
  }

  Widget _stelleInfo(Map<String, dynamic> d) {
    final post = _zeile(d['strasse'], d['plz'], d['ort']);
    final besuch = _zeile(d['besuch_strasse'], d['besuch_plz'], d['besuch_ort']);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: F.h(Colors.deepOrange, 50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: F.h(Colors.deepOrange, 200)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ⚠️ Post- und Besuchsanschrift getrennt zeigen. Die Zentrale
        // Bußgeldstelle BW hat als Postanschrift nur „76073 Karlsruhe" ohne
        // Straße; dorthin geht der fristgebundene Einspruch. Die
        // Kapellenstraße ist das Haus.
        if (post.isNotEmpty) _feld(Icons.markunread_mailbox, 'Postanschrift', post),
        if (besuch.isNotEmpty && besuch != post) _feld(Icons.location_on, 'Besuchsanschrift', besuch),
        if (d['telefon'] != null) _feld(Icons.phone, 'Telefon', d['telefon'].toString()),
        if (d['fax'] != null) _feld(Icons.fax, 'Fax', d['fax'].toString()),
        if (d['email'] != null) _feld(Icons.email, 'E-Mail', d['email'].toString()),
        if (d['oeffnungszeiten'] != null) _feld(Icons.access_time, 'Erreichbarkeit', d['oeffnungszeiten'].toString()),
        if (d['zustaendigkeit'] != null) _feld(Icons.info_outline, 'Zuständigkeit', d['zustaendigkeit'].toString()),
        if (d['website'] != null) InkWell(
          onTap: () => launchUrl(Uri.parse(d['website'].toString()), mode: LaunchMode.externalApplication),
          child: _feld(Icons.open_in_new, 'Website', 'öffnen'),
        ),
      ]),
    );
  }

  String _zeile(dynamic strasse, dynamic plz, dynamic ort) {
    final s = strasse?.toString().trim() ?? '';
    final po = '${plz?.toString().trim() ?? ''} ${ort?.toString().trim() ?? ''}'.trim();
    return [if (s.isNotEmpty) s, if (po.isNotEmpty) po].join(', ');
  }

  /// ⚠️ Der Wert laeuft durch [phoneAwareText], damit eine Rufnummer hinter
  /// einem Telefon-Icon auch waehlbar ist. Eine Nummer, die nur dasteht,
  /// sieht auf dem Schirm aus wie eine lebende - und der Vorsitzende tippt
  /// sie dann von Hand ab. `test/rufnummern_waehlbar_test.dart` haelt das
  /// projektweit fest und hat diese Stelle beim ersten Lauf gefunden.
  Widget _feld(IconData ikon, String label, String wert) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ikon, size: 15, color: F.h(Colors.grey, 700)),
          const SizedBox(width: 8),
          SizedBox(width: 110, child: Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: F.h(Colors.grey, 700)))),
          Expanded(child: phoneAwareText(ikon, wert, style: const TextStyle(fontSize: 12))),
        ]),
      );

  Widget _vorfaelleKarte() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.gavel, color: F.h(Colors.deepOrange, 700), size: 22),
            const SizedBox(width: 8),
            const Expanded(child: Text('Bußgeld-Vorfälle',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ElevatedButton.icon(
              key: const Key('bg_neuer_vorfall'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Neuer Vorfall'),
              style: ElevatedButton.styleFrom(
                backgroundColor: F.h(Colors.deepOrange, 700), foregroundColor: Colors.white),
              onPressed: () => _vorfallDialog(),
            ),
          ]),
          const Divider(height: 24),
          if (_vorfaelle.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Column(children: [
                Icon(Icons.inbox, size: 40, color: F.h(Colors.grey, 400)),
                const SizedBox(height: 8),
                Text('Noch kein Vorfall erfasst',
                    style: TextStyle(color: F.h(Colors.grey, 600))),
                const SizedBox(height: 4),
                Text('Anhörungsbogen, Bußgeldbescheid oder Mahnung hier eintragen — '
                     'die Frist wird dann aus dem Zugangsdatum mitgerechnet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
              ])),
            )
          else
            ..._vorfaelle.map(_vorfallZeile),
        ]),
      ),
    );
  }

  Widget _vorfallZeile(Map<String, dynamic> v) {
    final tage = v['tage_bis_frist'];
    final abgelaufen = tage is int && tage < 0;
    final knapp = tage is int && tage >= 0 && tage <= 3;
    final offen = v['status'] != 'abgeschlossen' && v['status'] != 'bezahlt' &&
                  v['status'] != 'rechtskraeftig' && v['status'] != 'eingestellt';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          abgelaufen && offen ? Icons.error_outline : Icons.description_outlined,
          color: abgelaufen && offen
              ? F.h(Colors.red, 700)
              : knapp && offen
                  ? F.h(Colors.orange, 800)
                  : F.h(Colors.grey, 600),
        ),
        title: Text(
          '${kBussgeldArten[v['art']] ?? v['art']} · ${v['aktenzeichen'] ?? 'ohne Aktenzeichen'}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (v['vorwurf'] != null) Text(v['vorwurf'].toString(), style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 2),
          Wrap(spacing: 12, runSpacing: 2, children: [
            if (v['zugang_datum'] != null)
              Text('zugegangen ${_kurzDatum(v['zugang_datum'])}', style: const TextStyle(fontSize: 11)),
            if (v['frist_bis'] != null)
              Text(
                abgelaufen && offen
                    ? 'Frist abgelaufen ${_kurzDatum(v['frist_bis'])}'
                    : 'Frist ${_kurzDatum(v['frist_bis'])}${tage is int && offen ? ' (noch $tage T.)' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  color: abgelaufen && offen ? F.h(Colors.red, 700) : knapp && offen ? F.h(Colors.orange, 800) : null,
                  fontWeight: (abgelaufen || knapp) && offen ? FontWeight.bold : null,
                ),
              ),
            if (v['betrag_gesamt'] != null)
              Text('${_euro(v['betrag_gesamt'])} €', style: const TextStyle(fontSize: 11)),
            if (v['punkte'] != null && v['punkte'] != 0)
              Text('${v['punkte']} Punkt(e)', style: const TextStyle(fontSize: 11)),
            Text(kBussgeldStatus[v['status']] ?? v['status'].toString(),
                style: TextStyle(fontSize: 11, color: F.h(Colors.blue, 700))),
          ]),
        ]),
        isThreeLine: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.edit, size: 18), tooltip: 'Bearbeiten',
              onPressed: () => _vorfallDialog(vorfall: v)),
          IconButton(icon: const Icon(Icons.delete_outline, size: 18), tooltip: 'Löschen',
              color: F.h(Colors.red, 600), onPressed: () => _vorfallLoeschen(v)),
        ]),
        onTap: () => _vorfallDialog(vorfall: v),
      ),
    );
  }

  static String _kurzDatum(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '');
    if (d == null) return iso?.toString() ?? '';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  static String _euro(dynamic v) {
    final d = double.tryParse(v?.toString() ?? '');
    return d == null ? (v?.toString() ?? '') : d.toStringAsFixed(2).replaceAll('.', ',');
  }
}
