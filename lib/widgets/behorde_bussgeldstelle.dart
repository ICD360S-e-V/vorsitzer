import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../utils/app_farben.dart';
import 'phone_link.dart';
import 'bussgeld_vorfall_dialog.dart';
import 'bussgeld_vorfall_details_dialog.dart';

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

class _BehordeBussgeldstelleContentState extends State<BehordeBussgeldstelleContent> {
  Map<String, dynamic>? _zustaendig;
  List<Map<String, dynamic>> _vorfaelle = [];
  bool _laedt = true;

  /// Treffer der letzten Katalogsuche. Wird serverseitig gesucht, deshalb
  /// steht hier immer nur ein Ausschnitt, nie der ganze Katalog.
  List<Map<String, dynamic>> _treffer = [];
  final _sucheCtrl = TextEditingController();
  Timer? _tippPause;
  bool _sucht = false;
  bool _speichert = false;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    _tippPause?.cancel();
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

  /// Übernimmt eine Stelle als zuständig — und speichert dabei sofort.
  ///
  /// [stelle] `null` heißt: den freien Text aus dem Suchfeld übernehmen.
  Future<void> _stelleUebernehmen(Map<String, dynamic>? stelle) async {
    final name = stelle?['name']?.toString().trim() ?? _sucheCtrl.text.trim();
    if (name.isEmpty) return;
    final roh = stelle?['id'];
    final id = roh is int ? roh : int.tryParse(roh?.toString() ?? '');

    setState(() => _speichert = true);
    final r = await widget.apiService.saveUserBussgeldstelle(widget.userId, id, name);
    if (!mounted) return;
    setState(() => _speichert = false);

    if (r['success'] != true) {
      // ⚠️ Beim automatischen Speichern MUSS der Fehlschlag sichtbar sein.
      // Ohne Knopf gibt es keinen zweiten Versuch, den jemand von sich aus
      // unternähme — ein stiller Fehler bliebe für immer stumm.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nicht gespeichert: ${r['message'] ?? 'unbekannter Fehler'}'),
        backgroundColor: F.h(Colors.red, 700),
      ));
      return;
    }
    setState(() { _treffer = []; _sucheCtrl.clear(); });
    await _laden();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$name als zuständig gespeichert'),
      duration: const Duration(seconds: 2),
    ));
  }

  /// Nimmt die Zuständigkeit zurück.
  ///
  /// ⚠️ Die Vorgänge bleiben. Sie hängen am Mitglied, nicht an der Auswahl —
  /// wer die Stelle wechselt, verliert sonst seine Aktenzeichen.
  Future<void> _stelleEntfernen() async {
    final sicher = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Zuständigkeit entfernen?'),
      content: Text(_vorfaelle.isEmpty
          ? 'Die hinterlegte Bußgeldstelle wird entfernt.'
          : 'Die hinterlegte Bußgeldstelle wird entfernt. '
            'Die ${_vorfaelle.length} erfassten Vorgänge bleiben bestehen.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Entfernen'),
        ),
      ],
    ));
    if (sicher != true) return;
    setState(() => _speichert = true);
    final r = await widget.apiService.saveUserBussgeldstelle(widget.userId, null, null);
    if (!mounted) return;
    setState(() => _speichert = false);
    if (r['success'] == true) {
      _sucheCtrl.clear();
      _laden();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nicht entfernt: ${r['message'] ?? 'unbekannter Fehler'}'),
        backgroundColor: F.h(Colors.red, 700),
      ));
    }
  }

  Future<void> _vorfallSchnellAnlegen() async {
    final az = TextEditingController();
    String art = 'bussgeldbescheid';
    DateTime? zugang = DateTime.now();
    DateTime? bescheid;

    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) {
        Widget dat(String label, DateTime? wert, ValueChanged<DateTime?> setzen, {String? hilfe}) => InkWell(
              onTap: () async {
                final d = await showDatePicker(context: ctx, initialDate: wert ?? DateTime.now(),
                    firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) ss(() => setzen(d));
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder(), isDense: true, helperText: hilfe,
                  suffixIcon: wert == null ? const Icon(Icons.calendar_today, size: 16)
                      : IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => ss(() => setzen(null))),
                ),
                child: Text(wert == null ? '\u2014'
                    : '${wert.day.toString().padLeft(2, '0')}.${wert.month.toString().padLeft(2, '0')}.${wert.year}'),
              ),
            );
        return AlertDialog(
          title: Row(children: [
            Icon(Icons.gavel, color: F.h(Colors.deepOrange, 700)),
            const SizedBox(width: 8),
            const Expanded(child: Text('Aktenzeichen erfassen')),
          ]),
          content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_zustaendig?['stelle_name'] != null)
              Padding(padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Icon(Icons.account_balance, size: 15, color: F.h(Colors.grey, 600)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_zustaendig!['stelle_name'].toString(),
                        style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)))),
                  ])),
            TextField(
              key: const Key('bg_schnell_az'),
              controller: az,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Aktenzeichen *', border: OutlineInputBorder(), isDense: true,
                hintText: 'genau wie auf dem Schreiben'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: art,
              decoration: const InputDecoration(labelText: 'Art des Schreibens', border: OutlineInputBorder(), isDense: true),
              items: [for (final e in kBussgeldArten.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => ss(() => art = v ?? art),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: dat('Datum des Schreibens', bescheid, (d) => bescheid = d)),
              const SizedBox(width: 10),
              Expanded(child: dat('Zugegangen am', zugang, (d) => zugang = d, hilfe: 'Fristbeginn')),
            ]),
            const SizedBox(height: 6),
            Text('Alles Weitere \u2014 Vorwurf, Betr\u00E4ge, Tatort \u2014 l\u00E4sst sich danach im Vorgang erg\u00E4nzen.',
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: F.h(Colors.deepOrange, 700), foregroundColor: Colors.white),
              child: const Text('Anlegen und \u00F6ffnen'),
            ),
          ],
        );
      },
    ));
    if (ok != true) return;
    if (az.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ohne Aktenzeichen findet die Beh\u00F6rde den Vorgang nicht \u2014 bitte eintragen.')));
      }
      return;
    }

    final id = _zustaendig?['stelle_id'];
    final r = await widget.apiService.saveBussgeldVorfall(widget.userId, {
      'stelle_id': id is int ? id : int.tryParse(id?.toString() ?? ''),
      'stelle_name': _zustaendig?['stelle_name'],
      'art': art,
      'aktenzeichen': az.text.trim(),
      'bescheid_datum': bescheid == null ? null : _iso(bescheid!),
      'zugang_datum': zugang == null ? null : _iso(zugang!),
    });
    if (!mounted) return;
    if (r['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Nicht angelegt: ${r['message'] ?? 'unbekannter Fehler'}')));
      return;
    }
    await _laden();
    if (!mounted) return;
    // Direkt in den Vorgang: dort stehen Details, Korrespondenz,
    // Widerspruch und Vollmacht.
    await _detailsOeffnen(r['id'] as int);
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _detailsOeffnen(int vorfallId) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => BussgeldVorfallDetailsDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        vorfallId: vorfallId,
      ),
    );
    if (mounted) _laden();
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
    // ⚠️ KEINE zwei Reiter mehr. Die Vorgänge stehen IN der Karte der
    // zuständigen Stelle, nicht daneben: ein Aktenzeichen gehört zu genau
    // einer Behörde, und wer die Stelle vor sich hat, sucht ihre Vorgänge
    // dort — nicht in einem zweiten Reiter, der aussieht, als wäre er etwas
    // anderes.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _stelleKarte(),
    );
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
            if (_speichert) const Padding(padding: EdgeInsets.only(left: 8),
                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
          ]),
          const Divider(height: 24),

          // ⚠️ Das Feld ist NUR Suche. Vorher war es beides — Suchschlitz und
          // zugleich der gespeicherte Name — und genau daher rührte der
          // Speichern-Knopf: irgendwer musste ja entscheiden, wann aus einem
          // Suchbegriff eine Zuständigkeit wird. Wer eine Stelle antippt, hat
          // das entschieden; ein Knopf danach fragt nur noch einmal dasselbe.
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
                  : (_sucheCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Suche leeren',
                          onPressed: () => setState(() {
                            _sucheCtrl.clear();
                            _treffer = [];
                          }),
                        )),
            ),
            // ⚠️ setState beim Tippen, nicht erst wenn die Suche antwortet.
            // Der Leeren-Knopf und der Freitext-Knopf hängen am Inhalt des
            // Feldes; ohne Neuaufbau erschienen sie erst 350 ms später mit
            // dem Suchergebnis — und bei einem Begriff ohne Treffer, für den
            // der Freitext-Knopf ja gerade gedacht ist, wirkte das wie ein
            // Aussetzer.
            onChanged: (v) {
              setState(() {});
              _sucheAngestossen(v);
            },
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
                    final schonGesetzt = _zustaendig != null &&
                        '${_zustaendig!['stelle_id']}' == '${s['id']}';
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        s['typ'] == 'zentrale_bussgeldstelle' ? Icons.account_balance : Icons.location_city,
                        size: 18, color: F.h(Colors.deepOrange, 600)),
                      title: Text(s['name']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                      subtitle: Text(_anschriftKurz(s), style: const TextStyle(fontSize: 11)),
                      trailing: schonGesetzt
                          ? Icon(Icons.check, size: 18, color: F.h(Colors.green, 700))
                          : null,
                      // Antippen IST das Speichern.
                      onTap: schonGesetzt ? null : () => _stelleUebernehmen(s),
                    );
                  },
                ),
              ),
            ),
          ],

          // ⚠️ Freitext bleibt möglich, aber nur mit einem eigenen Tipper.
          // Der Katalog hat erst drei Einträge; die Bußgeldstelle des
          // Landkreises steht noch nicht darin. Ohne diesen Weg wäre sie gar
          // nicht einzutragen — und ein automatisches Speichern beim
          // Tippen würde jeden halben Suchbegriff zur Zuständigkeit machen.
          if (_treffer.isEmpty && !_sucht && _sucheCtrl.text.trim().length >= 3 &&
              _sucheCtrl.text.trim() != (_zustaendig?['stelle_name']?.toString() ?? ''))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                key: const Key('bg_stelle_freitext'),
                icon: const Icon(Icons.add, size: 16),
                label: Text('„${_sucheCtrl.text.trim()}" übernehmen (nicht im Katalog)',
                    style: const TextStyle(fontSize: 12)),
                onPressed: () => _stelleUebernehmen(null),
              ),
            ),

          if (_hatStelle) _stelleInfo(_zustaendig!),

          if (_hatStelle) ...[
            const Divider(height: 28),
            _vorgaengeImKarten(),
          ],
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 2),
        child: Row(children: [
          Icon(Icons.check_circle, size: 16, color: F.h(Colors.green, 700)),
          const SizedBox(width: 6),
          Expanded(child: Text(d['stelle_name']?.toString() ?? '',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
          // Ohne Speichern-Knopf braucht es einen Weg zurück: sonst ließe
          // sich eine einmal gesetzte Zuständigkeit nur noch überschreiben,
          // nie aufheben.
          IconButton(
            key: const Key('bg_stelle_entfernen'),
            icon: const Icon(Icons.link_off, size: 18),
            tooltip: 'Zuständigkeit entfernen',
            color: F.h(Colors.grey, 600),
            onPressed: _speichert ? null : _stelleEntfernen,
          ),
        ]),
      ),
      Container(
        width: double.infinity,
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
      ),
    ]);
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

  /// Die Vorgänge dieser Stelle — innerhalb ihrer Karte.
  ///
  /// Das Plus sitzt in derselben Überschrift: wer die Stelle ausgewählt hat,
  /// legt von hier aus das Aktenzeichen an und landet danach im Vorgang.
  Widget _vorgaengeImKarten() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.gavel, size: 18, color: F.h(Colors.deepOrange, 700)),
        const SizedBox(width: 8),
        Expanded(child: Text(
          _vorfaelle.isEmpty ? 'Vorgänge' : 'Vorgänge (${_vorfaelle.length})',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
        IconButton(
          key: const Key('bg_neuer_vorfall'),
          icon: const Icon(Icons.add_circle),
          color: F.h(Colors.deepOrange, 700),
          tooltip: 'Aktenzeichen hinzufügen',
          onPressed: _vorfallSchnellAnlegen,
        ),
      ]),
      const SizedBox(height: 4),
      if (_vorfaelle.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(child: Column(children: [
            Icon(Icons.inbox, size: 34, color: F.h(Colors.grey, 400)),
            const SizedBox(height: 6),
            Text('Noch kein Aktenzeichen erfasst',
                style: TextStyle(color: F.h(Colors.grey, 600), fontSize: 13)),
            const SizedBox(height: 4),
            Text('Über das Plus oben ein Schreiben dieser Stelle eintragen — '
                 'die Frist wird dann aus dem Zugangsdatum mitgerechnet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500))),
          ])),
        )
      else
        ..._vorfaelle.map(_vorfallZeile),
    ]);
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
        // Tippen auf die Zeile fuehrt in den VORGANG (Details, Korrespondenz,
        // Widerspruch, Vollmacht); der Stift daneben oeffnet weiterhin direkt
        // das Formular.
        onTap: () => _detailsOeffnen(v['id'] as int),
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
