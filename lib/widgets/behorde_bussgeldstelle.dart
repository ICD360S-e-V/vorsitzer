import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../utils/app_farben.dart';
import 'phone_link.dart';
import 'bussgeld_vorgaenge_manager.dart';

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

  bool get _hatStelle => (_zustaendig?['stelle_name']?.toString().isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    if (_laedt) return const Center(child: CircularProgressIndicator());
    // ⚠️ Ein Bild, keine Reiter. Die Karte zeigt die zuständige Stelle;
    // ihre Vorgänge liegen hinter einem Tipp im Vorgangs-Manager. Weder
    // ein zweiter Reiter daneben (dann sieht er aus wie etwas anderes) noch
    // eine Liste darunter (dann wächst sie der Anschrift davon).
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
      // ⚠️ Die Karte der Institution IST der Knopf. Vorher hing darunter eine
      // eigene Zeile „Vorgänge verwalten" — wer die Stelle vor sich hat und
      // sie antippt, will ihre Vorgänge sehen, nicht erst eine zweite Zeile
      // suchen. Die Telefonnummer und der Website-Verweis darin bleiben
      // trotzdem für sich anklickbar: das innere Element gewinnt.
      InkWell(
        key: const Key('bg_vorgaenge_oeffnen'),
        onTap: _vorgaengeOeffnen,
        borderRadius: BorderRadius.circular(8),
        child: Container(
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

          // ⚠️ Was dahinter liegt und was drängt, steht IM Block. Ohne das
          // müsste man ihn öffnen, um zu erfahren, dass man ihn öffnen sollte.
          const Divider(height: 20),
          Row(children: [
            Icon(Icons.folder_shared, size: 18, color: F.h(Colors.deepOrange, 700)),
            const SizedBox(width: 8),
            Expanded(child: Text(
              _vorfaelle.isEmpty
                  ? 'Vorgänge verwalten — noch kein Aktenzeichen'
                  : 'Vorgänge verwalten — ${_vorfaelle.length} erfasst · $_offen offen',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            if (_eilig > 0)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: F.h(Colors.red, 50),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: F.h(Colors.red, 300)),
                ),
                child: Text('$_eilig × Frist',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                        color: F.h(Colors.red, 700))),
              ),
            Icon(Icons.chevron_right, color: F.h(Colors.deepOrange, 700)),
          ]),
        ]),
      ),
      ),
    ]);
  }

  int get _offen => _vorfaelle.where((v) => !_fertig.contains(v['status'])).length;

  int get _eilig => _vorfaelle.where((v) {
        if (_fertig.contains(v['status'])) return false;
        final t = v['tage_bis_frist'];
        return t is int && t <= 3;
      }).length;

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

  /// Zustände, die als abgeschlossen gelten.
  ///
  /// ⚠️ Dieselbe Liste steht im Manager. Laufen sie auseinander, zählt die
  /// Karte etwas anderes als der Bildschirm dahinter — und man traut keiner
  /// von beiden Zahlen mehr.
  static const _fertig = {'bezahlt', 'rechtskraeftig', 'eingestellt', 'abgeschlossen'};

  Future<void> _vorgaengeOeffnen() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => BussgeldVorgaengeManager(
        apiService: widget.apiService,
        userId: widget.userId,
        stelle: _zustaendig,
        vorfaelle: _vorfaelle,
      ),
    );
    if (mounted) _laden();
  }


}
