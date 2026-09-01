import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/app_farben.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';

/// Ein einzelnes Schreiben aus der Korrespondenz.
///
/// Drei Reiter in der Reihenfolge, in der man sie braucht: was drinsteht,
/// was dabei lag, und was wir darauf geantwortet haben.
class BussgeldKorrespondenzDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int vorfallId;

  /// Das Schreiben mit `anhaenge` und `antworten`, wie es
  /// `bussgeld_vorfall_details.php` liefert.
  final Map<String, dynamic> schreiben;

  /// Frist des Vorgangs — nur zur Anzeige im Antwort-Reiter.
  final String? fristBis;

  const BussgeldKorrespondenzDialog({
    super.key,
    required this.apiService,
    required this.userId,
    required this.vorfallId,
    required this.schreiben,
    this.fristBis,
  });

  @override
  State<BussgeldKorrespondenzDialog> createState() => _BussgeldKorrespondenzDialogState();
}

/// Wege, auf denen ein Schreiben kommt oder geht.
///
/// ⚠️ Deckungsgleich mit dem ENUM `bussgeld_vorfall_korrespondenz.weg`.
/// Ein Wert daneben würde von MariaDB stillschweigend auf '' gekürzt — und
/// damit wäre nicht mehr belegbar, WIE geantwortet wurde.
const Map<String, String> kKorrWege = {
  'post': 'Post',
  'fax': 'Fax',
  'email': 'E-Mail',
  'persoenlich': 'Persönlich abgegeben',
  'elektronisch': 'Elektronisch',
  'sonstige': 'Sonstiger Weg',
};

class _BussgeldKorrespondenzDialogState extends State<BussgeldKorrespondenzDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late Map<String, dynamic> _s;
  bool _arbeitet = false;

  bool get _istEingang => _s['richtung'] == 'eingang';
  List<Map<String, dynamic>> get _anhaenge => _liste(_s['anhaenge']);
  List<Map<String, dynamic>> get _antworten => _liste(_s['antworten']);

  static List<Map<String, dynamic>> _liste(dynamic v) => v is List
      ? List<Map<String, dynamic>>.from(v.map((e) => Map<String, dynamic>.from(e as Map)))
      : <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _s = Map<String, dynamic>.from(widget.schreiben);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Lädt den Vorgang neu und zieht sich das eigene Schreiben heraus.
  ///
  /// ⚠️ Kein eigener Endpunkt für ein einzelnes Schreiben: die Anhänge und
  /// Antworten werden serverseitig an die Zeile gehängt, und eine zweite
  /// Quelle dafür liefe früher oder später auseinander.
  Future<void> _neuLaden() async {
    final r = await widget.apiService.getBussgeldVorfallDetails(widget.userId, widget.vorfallId);
    if (!mounted || r['success'] != true) return;
    for (final k in _liste(r['korrespondenz'])) {
      if (k['id'] == _s['id']) {
        setState(() => _s = k);
        return;
      }
    }
    // Das Schreiben gibt es nicht mehr — dann hat dieser Dialog keinen
    // Gegenstand mehr und schließt sich, statt Altes zu zeigen.
    if (mounted) Navigator.pop(context, true);
  }

  void _sagen(String text, {bool fehler = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler ? F.h(Colors.red, 700) : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final farbe = _istEingang ? Colors.green : Colors.orange;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 720,
        height: 620,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            color: F.h(farbe, 700),
            child: Row(children: [
              Icon(_istEingang ? Icons.inbox : Icons.outbox, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_s['betreff']?.toString() ?? '(ohne Betreff)',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
                Text('${_istEingang ? 'Eingang' : 'Ausgang'}'
                     '${_s['datum'] == null ? '' : ' · ${_datum(_s['datum'])}'}'
                     '${_s['weg'] == null ? '' : ' · ${kKorrWege[_s['weg']] ?? _s['weg']}'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ])),
              if (_arbeitet) const Padding(padding: EdgeInsets.only(right: 8),
                  child: SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
              IconButton(icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context, true)),
            ]),
          ),
          Container(
            color: F.h(farbe, 50),
            child: TabBar(
              controller: _tabs,
              labelColor: F.h(farbe, 800),
              unselectedLabelColor: F.h(Colors.grey, 600),
              indicatorColor: F.h(farbe, 700),
              tabs: [
                const Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
                Tab(icon: const Icon(Icons.attach_file, size: 18),
                    text: 'Unterlagen${_anhaenge.isEmpty ? '' : ' (${_anhaenge.length})'}'),
                Tab(icon: Icon(_antworten.isEmpty ? Icons.reply_outlined : Icons.check_circle_outline, size: 18),
                    text: 'Antwort${_antworten.isEmpty ? '' : ' (${_antworten.length})'}'),
              ],
            ),
          ),
          Expanded(child: TabBarView(controller: _tabs, children: [
            _details(), _unterlagen(), _antwort(),
          ])),
        ]),
      ),
    );
  }

  // ======================================================= Details ========
  Widget _details() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _kv('Richtung', _istEingang ? 'Eingang' : 'Ausgang'),
      _kv('Datum', _datum(_s['datum'])),
      _kv('Weg', kKorrWege[_s['weg']] ?? _s['weg']?.toString()),
      _kv(_istEingang ? 'Absender' : 'Empfänger',
          (_istEingang ? _s['absender'] : _s['empfaenger'])?.toString()),
      _kv('Betreff', _s['betreff']?.toString()),
      if ((_s['inhalt']?.toString().trim().isNotEmpty ?? false)) ...[
        const SizedBox(height: 10),
        Text('INHALT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
            letterSpacing: .6, color: F.h(Colors.grey, 600))),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: F.h(Colors.grey, 100),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(_s['inhalt'].toString(), style: const TextStyle(fontSize: 13)),
        ),
      ],
      if (_s['antwort_auf_id'] != null) Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          Icon(Icons.subdirectory_arrow_right, size: 16, color: F.h(Colors.grey, 600)),
          const SizedBox(width: 6),
          Expanded(child: Text('Dies ist eine Antwort auf ein früheres Schreiben.',
              style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)))),
        ]),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        key: const Key('bg_korr_bearbeiten'),
        icon: const Icon(Icons.edit, size: 18),
        label: const Text('Angaben bearbeiten'),
        onPressed: _arbeitet ? null : _bearbeiten,
      ),
    ]);
  }

  Future<void> _bearbeiten() async {
    final betreff = TextEditingController(text: _s['betreff']?.toString() ?? '');
    final inhalt = TextEditingController(text: _s['inhalt']?.toString() ?? '');
    final wer = TextEditingController(
        text: (_istEingang ? _s['absender'] : _s['empfaenger'])?.toString() ?? '');
    DateTime? datum = DateTime.tryParse(_s['datum']?.toString() ?? '');
    String richtung = _istEingang ? 'eingang' : 'ausgang';
    String? weg = kKorrWege.containsKey(_s['weg']) ? _s['weg'] as String : null;
    bool erledigt = _s['erledigt'] == 1 || _s['erledigt'] == true;

    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) => AlertDialog(
        title: const Text('Schreiben bearbeiten'),
        content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'eingang', label: Text('Eingang'), icon: Icon(Icons.inbox, size: 16)),
                ButtonSegment(value: 'ausgang', label: Text('Ausgang'), icon: Icon(Icons.outbox, size: 16)),
              ],
              selected: {richtung},
              onSelectionChanged: (v) => ss(() => richtung = v.first),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: datum ?? DateTime.now(),
                      firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d != null) ss(() => datum = d);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Datum', border: OutlineInputBorder(), isDense: true),
                  child: Text(datum == null ? '—' : _datum(_iso(datum!))!),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: weg,
                decoration: const InputDecoration(labelText: 'Weg', border: OutlineInputBorder(), isDense: true),
                items: [for (final e in kKorrWege.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => ss(() => weg = v),
              )),
            ]),
            const SizedBox(height: 10),
            TextField(controller: betreff, decoration: const InputDecoration(
                labelText: 'Betreff', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 10),
            TextField(controller: wer, decoration: InputDecoration(
                labelText: richtung == 'eingang' ? 'Absender' : 'Empfänger',
                border: const OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 10),
            TextField(controller: inhalt, maxLines: 4, decoration: const InputDecoration(
                labelText: 'Inhalt', border: OutlineInputBorder(), isDense: true)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: erledigt,
              title: const Text('Erledigt'),
              onChanged: (v) => ss(() => erledigt = v ?? false),
            ),
          ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Speichern')),
        ],
      ),
    ));
    if (ok != true) return;

    setState(() => _arbeitet = true);
    final r = await widget.apiService.bussgeldVorfallAktion({
      'action': 'update_korrespondenz',
      'user_id': widget.userId,
      'vorfall_id': widget.vorfallId,
      'id': _s['id'],
      'richtung': richtung,
      'datum': datum == null ? null : _iso(datum!),
      'weg': weg,
      'erledigt': erledigt ? 1 : 0,
      'betreff': betreff.text.trim(),
      'inhalt': inhalt.text.trim(),
      if (richtung == 'eingang') 'absender': wer.text.trim() else 'empfaenger': wer.text.trim(),
    });
    if (!mounted) return;
    setState(() => _arbeitet = false);
    if (r['success'] == true) {
      await _neuLaden();
    } else {
      _sagen('Nicht gespeichert: ${r['message'] ?? 'unbekannter Fehler'}', fehler: true);
    }
  }

  // ==================================================== Unterlagen ========
  Widget _unterlagen() {
    return Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Unterlagen zu diesem Schreiben (${_anhaenge.length})',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
          ElevatedButton.icon(
            key: const Key('bg_korr_anhang'),
            icon: const Icon(Icons.attach_file, size: 18),
            label: const Text('Hinzufügen'),
            style: ElevatedButton.styleFrom(
                backgroundColor: F.h(Colors.deepOrange, 700), foregroundColor: Colors.white),
            onPressed: _arbeitet ? null : () => _hochladen(_s['id'] as int),
          ),
        ]),
        const Divider(height: 20),
        Expanded(child: _anhaenge.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.folder_open, size: 40, color: F.h(Colors.grey, 400)),
                const SizedBox(height: 8),
                Text('Noch nichts angehängt', style: TextStyle(color: F.h(Colors.grey, 700))),
                const SizedBox(height: 4),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text('Der Bescheid selbst, das Messprotokoll, das Lichtbild — '
                        'alles, was mit diesem Schreiben kam.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 500)))),
              ]))
            : ListView(children: [for (final a in _anhaenge) _anhangZeile(a)])),
      ]));
  }

  Widget _anhangZeile(Map<String, dynamic> a) {
    final istPdf = (a['mime']?.toString() ?? '').contains('pdf');
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(istPdf ? Icons.picture_as_pdf : Icons.image_outlined,
            color: F.h(istPdf ? Colors.red : Colors.blue, 600)),
        title: Text(a['original_name']?.toString() ?? 'Anhang',
            style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
        subtitle: Text('${((int.tryParse(a['groesse']?.toString() ?? '0') ?? 0) / 1024).round()} kB'
            '${a['created_at'] == null ? '' : ' · ${_datum(a['created_at'])}'}',
            style: const TextStyle(fontSize: 11)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          color: F.h(Colors.red, 600),
          tooltip: 'Anhang löschen',
          onPressed: () => _anhangLoeschen(a),
        ),
        // Öffnen zeigt IM PROGRAMM, aus dem Arbeitsspeicher.
        onTap: () => _anhangOeffnen(a),
      ),
    );
  }

  Future<void> _hochladen(int korrespondenzId) async {
    final auswahl = await FilePickerHelper.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'tif', 'tiff'],
    );
    final pfade = (auswahl?.files ?? []).map((f) => f.path).whereType<String>().toList();
    if (pfade.isEmpty) return;

    setState(() => _arbeitet = true);
    final r = await widget.apiService.uploadBussgeldAnhaenge(
      userId: widget.userId,
      vorfallId: widget.vorfallId,
      korrespondenzId: korrespondenzId,
      pfade: pfade,
    );
    if (!mounted) return;
    setState(() => _arbeitet = false);
    final fehler = (r['fehler'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    if (r['success'] == true) {
      final n = (r['hochgeladen'] as List?)?.length ?? 0;
      _sagen(fehler.isEmpty ? '$n Datei(en) angehängt'
                            : '$n angehängt, nicht übernommen: ${fehler.join('; ')}');
      await _neuLaden();
    } else {
      _sagen(fehler.isEmpty
          ? 'Nicht hochgeladen: ${r['message'] ?? 'unbekannter Fehler'}'
          : 'Nicht hochgeladen: ${fehler.join('; ')}', fehler: true);
    }
  }

  /// 🔴 IM PROGRAMM anzeigen, aus dem Arbeitsspeicher — nicht auf die Platte
  /// schreiben und an ein fremdes Programm übergeben. Ein Bußgeldbescheid
  /// trägt Name, Anschrift, Kennzeichen und Tatvorwurf; ein fremder Betrachter
  /// behält ihn in seinem Verlauf, seinem Zwischenspeicher und womöglich
  /// seiner Wolkensicherung. Drucken und „Speichern unter" bietet
  /// [FileViewerDialog] selbst an — dann aber, weil jemand es ausdrücklich will.
  Future<void> _anhangOeffnen(Map<String, dynamic> a) async {
    setState(() => _arbeitet = true);
    final r = await widget.apiService.downloadBussgeldAnhang(widget.userId, a['id'] as int);
    if (!mounted) return;
    setState(() => _arbeitet = false);
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
      _sagen('Anhang nicht abrufbar (HTTP ${r.statusCode}).', fehler: true);
      return;
    }
    final name = a['original_name']?.toString() ?? 'anhang.pdf';
    final gezeigt = await FileViewerDialog.showFromBytes(context, r.bodyBytes, name);
    if (!gezeigt && mounted) {
      _sagen('Dieser Dateityp lässt sich hier nicht anzeigen: $name', fehler: true);
    }
  }

  Future<void> _anhangLoeschen(Map<String, dynamic> a) async {
    final sicher = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Anhang löschen?'),
      content: Text('„${a['original_name'] ?? 'Anhang'}" wird endgültig entfernt.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Löschen')),
      ],
    ));
    if (sicher != true) return;
    final r = await widget.apiService.deleteBussgeldAnhang(widget.userId, a['id'] as int);
    if (r['success'] == true) {
      await _neuLaden();
    } else {
      _sagen('Nicht gelöscht: ${r['message'] ?? 'unbekannter Fehler'}', fehler: true);
    }
  }

  // ======================================================= Antwort ========
  Widget _antwort() {
    if (!_istEingang) {
      return Center(child: Padding(padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.outbox, size: 40, color: F.h(Colors.grey, 400)),
          const SizedBox(height: 10),
          Text('Dies ist ein Ausgang', style: TextStyle(color: F.h(Colors.grey, 700))),
          const SizedBox(height: 4),
          Text('Auf ein eigenes Schreiben wird nicht geantwortet. '
               'Kommt eine Reaktion der Behörde, wird sie als neuer Eingang erfasst.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 500))),
        ])));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      // ⚠️ Der wichtigste Satz auf diesem Reiter. Eine formlose Antwort auf
      // einen Bußgeldbescheid wahrt KEINE Frist — der Rechtsbehelf ist der
      // Einspruch nach § 67 OWiG, und der steht im Vorgang unter
      // „Widerspruch". Wer das hier nicht liest, hält ein freundliches
      // Schreiben für einen Einspruch.
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
            'Eine Antwort hier ist Schriftverkehr, kein Rechtsbehelf. '
            'Gegen einen Bußgeldbescheid wahrt nur der Einspruch nach § 67 OWiG die Frist — '
            'er wird im Vorgang unter „Widerspruch" erfasst'
            '${widget.fristBis == null ? '' : ' (Frist ${_datum(widget.fristBis)})'}.',
            style: TextStyle(fontSize: 12, color: F.h(Colors.blue, 900)),
          )),
        ]),
      ),
      const SizedBox(height: 14),
      if (_antworten.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(child: Column(children: [
            Icon(Icons.reply_outlined, size: 40, color: F.h(Colors.grey, 400)),
            const SizedBox(height: 8),
            Text('Noch nicht geantwortet', style: TextStyle(color: F.h(Colors.grey, 700))),
          ])))
      else
        ..._antworten.map(_antwortZeile),
      const SizedBox(height: 8),
      // ⚠️ Sobald geantwortet ist, verschwindet der Knopf. Es ist beantwortet;
      // ein weiterhin sichtbares „Antworten" lädt dazu ein, dieselbe Sache
      // zweimal zu schreiben — und in einer Behördenakte ist eine doppelte
      // Antwort schlimmer als gar keine.
      //
      // ⚠️ Anlagen an eine bestehende Antwort bleiben trotzdem möglich: das
      // ist kein zweites Antworten, sondern das Nachreichen des Schreibens,
      // das man gerade eingescannt hat. Der Knopf dafür sitzt an der Antwort.
      if (_antworten.isEmpty)
        ElevatedButton.icon(
          key: const Key('bg_korr_antworten'),
          icon: const Icon(Icons.reply, size: 18),
          label: const Text('Antwort erfassen'),
          style: ElevatedButton.styleFrom(
              backgroundColor: F.h(Colors.orange, 800), foregroundColor: Colors.white),
          onPressed: _arbeitet ? null : _antwortErfassen,
        )
      else
        Row(children: [
          Icon(Icons.check_circle, size: 16, color: F.h(Colors.green, 700)),
          const SizedBox(width: 6),
          Expanded(child: Text(
            'Auf dieses Schreiben wurde geantwortet. Kommt eine Reaktion der '
            'Behörde, wird sie als neuer Eingang erfasst.',
            style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700)))),
        ]),
    ]);
  }

  Widget _antwortZeile(Map<String, dynamic> a) {
    final anlagen = _liste(a['anhaenge']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(
          leading: Icon(Icons.outbox, color: F.h(Colors.orange, 700)),
          title: Text(a['betreff']?.toString() ?? '(ohne Betreff)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (a['inhalt'] != null) Text(a['inhalt'].toString(), style: const TextStyle(fontSize: 12)),
            Wrap(spacing: 12, children: [
              if (a['datum'] != null) Text(_datum(a['datum'])!, style: const TextStyle(fontSize: 11)),
              if (a['weg'] != null) Text(kKorrWege[a['weg']] ?? a['weg'].toString(),
                  style: const TextStyle(fontSize: 11)),
              if (a['empfaenger'] != null) Text('an ${a['empfaenger']}', style: const TextStyle(fontSize: 11)),
              if (anlagen.isNotEmpty) Text('${anlagen.length} Anlage(n)',
                  style: TextStyle(fontSize: 11, color: F.h(Colors.deepOrange, 700))),
            ]),
          ]),
          isThreeLine: true,
          // Nachreichen ist kein zweites Antworten.
          trailing: IconButton(
            key: const Key('bg_antwort_anlage'),
            icon: const Icon(Icons.attach_file, size: 18),
            tooltip: 'Schreiben anhängen (PDF oder Foto)',
            color: F.h(Colors.deepOrange, 700),
            onPressed: _arbeitet ? null : () => _hochladen(a['id'] as int),
          ),
        ),
        if (anlagen.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Column(children: [for (final x in anlagen) _anhangZeile(x)]),
          ),
      ]),
    );
  }

  Future<void> _antwortErfassen() async {
    final betreff = TextEditingController(
        text: 'Ihr Schreiben vom ${_datum(_s['datum']) ?? ''}'.trim());
    final inhalt = TextEditingController();
    final empfaenger = TextEditingController(text: _s['absender']?.toString() ?? '');
    DateTime? datum = DateTime.now();
    String weg = 'post';
    // Das Schreiben selbst gehört zur Antwort, nicht in einen zweiten
    // Arbeitsgang. Wer gerade scannt, hängt es hier gleich an.
    final anlagen = <String>[];

    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, ss) => AlertDialog(
        title: const Text('Antwort erfassen'),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: datum ?? DateTime.now(),
                      firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 30)));
                  if (d != null) ss(() => datum = d);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Abgesendet am',
                      border: OutlineInputBorder(), isDense: true),
                  child: Text(datum == null ? '—' : _datum(_iso(datum!))!),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: weg,
                decoration: const InputDecoration(labelText: 'Auf welchem Weg',
                    border: OutlineInputBorder(), isDense: true),
                items: [for (final e in kKorrWege.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => ss(() => weg = v ?? weg),
              )),
            ]),
            const SizedBox(height: 10),
            TextField(controller: empfaenger, decoration: const InputDecoration(
                labelText: 'Empfänger', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 10),
            TextField(controller: betreff, decoration: const InputDecoration(
                labelText: 'Betreff', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 10),
            TextField(
              key: const Key('bg_antwort_text'),
              controller: inhalt, maxLines: 5,
              decoration: const InputDecoration(labelText: 'Was wurde geantwortet',
                  border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: Row(children: [
              OutlinedButton.icon(
                key: const Key('bg_antwort_datei'),
                icon: const Icon(Icons.attach_file, size: 16),
                label: const Text('PDF oder Foto anhängen', style: TextStyle(fontSize: 12.5)),
                onPressed: () async {
                  // ⚠️ Über FilePickerHelper, nicht über FilePicker direkt:
                  // auf macOS nimmt der Helfer einen eigenen Weg.
                  final w = await FilePickerHelper.pickFiles(
                    allowMultiple: true,
                    type: FileType.custom,
                    allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'tif', 'tiff'],
                  );
                  final neu = (w?.files ?? [])
                      .map((f) => f.path).whereType<String>()
                      .where((x) => !anlagen.contains(x));   // kein Doppel
                  if (neu.isNotEmpty) ss(() => anlagen.addAll(neu));
                },
              ),
              const SizedBox(width: 10),
              if (anlagen.isNotEmpty)
                Text('${anlagen.length} Datei(en)',
                    style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
            ])),
            // Die Auswahl sichtbar machen, samt Weg zurück — sonst weiß
            // niemand, was gleich mitgeschickt wird.
            for (final pfad in anlagen)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  Icon(Icons.insert_drive_file, size: 14, color: F.h(Colors.grey, 600)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(pfad.split(Platform.pathSeparator).last,
                      style: const TextStyle(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                  IconButton(
                    icon: const Icon(Icons.clear, size: 14),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => ss(() => anlagen.remove(pfad)),
                  ),
                ]),
              ),
          ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Speichern')),
        ],
      ),
    ));
    if (ok != true) return;

    setState(() => _arbeitet = true);
    final r = await widget.apiService.bussgeldVorfallAktion({
      'action': 'add_korrespondenz',
      'user_id': widget.userId,
      'vorfall_id': widget.vorfallId,
      'richtung': 'ausgang',
      'antwort_auf_id': _s['id'],
      'datum': datum == null ? null : _iso(datum!),
      'weg': weg,
      'betreff': betreff.text.trim(),
      'inhalt': inhalt.text.trim(),
      'empfaenger': empfaenger.text.trim(),
    });
    if (!mounted) return;
    setState(() => _arbeitet = false);
    if (r['success'] != true) {
      _sagen('Nicht gespeichert: ${r['message'] ?? 'unbekannter Fehler'}', fehler: true);
      return;
    }

    // ⚠️ Die Antwort steht bereits. Scheitert das Hochladen, darf das NICHT
    // wie ein Fehlschlag des Ganzen aussehen — sonst legt jemand die Antwort
    // ein zweites Mal an. Deshalb getrennte Meldungen.
    if (anlagen.isNotEmpty) {
      final u = await widget.apiService.uploadBussgeldAnhaenge(
        userId: widget.userId,
        vorfallId: widget.vorfallId,
        korrespondenzId: r['id'] as int?,
        pfade: anlagen,
      );
      if (!mounted) return;
      final fehler = (u['fehler'] as List?)?.map((e) => e.toString()).toList() ?? const [];
      if (u['success'] != true || fehler.isNotEmpty) {
        _sagen('Antwort gespeichert, aber Anlagen nicht vollständig: '
               '${fehler.isEmpty ? (u['message'] ?? 'unbekannter Fehler') : fehler.join('; ')}',
               fehler: true);
        await _neuLaden();
        return;
      }
    }
    await _neuLaden();
    _sagen('Antwort gespeichert${anlagen.isEmpty ? '' : ' mit ${anlagen.length} Anlage(n)'}'
           ' — das Schreiben gilt jetzt als erledigt.');
  }

  // ====================================================== Bausteine =======
  Widget _kv(String label, String? wert) {
    if (wert == null || wert.trim().isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(label,
            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)))),
        Expanded(child: Text(wert, style: const TextStyle(fontSize: 13))),
      ]));
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String? _datum(dynamic iso) {
    final s = iso?.toString();
    if (s == null || s.isEmpty) return null;
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }
}
