import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';

import '../services/api_service.dart';
import '../services/signatur_service.dart';
import '../utils/cloud_picker_helper.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';
import '../utils/app_farben.dart';
import 'vollmacht_link_aktionen.dart';

/// Ein Objekt aus der Serverantwort, tolerant gelesen.
Map<String, dynamic> vollmachtFeldAlsMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Ein Katalog (Schlüssel → Text) aus der Serverantwort.
///
/// 🔴 PHP hat nur EINEN Array-Typ. `array_fill_keys([], …)` und jedes leere
/// Array werden von `json_encode` als **Liste** `[]` ausgegeben, gefüllte
/// Kataloge als Objekt `{}`. Ein `as Map` auf einer Liste gibt nicht `null`
/// zurück, sondern **wirft** — und im Release-Build ist das Ergebnis eine
/// graue Fläche ohne jede Meldung. Genau so ist am 05.08.2026 der
/// Speedtest-Bildschirm gestorben, und das war schon der zweite Fall
/// desselben Musters.
///
/// Beim Landratsamt ist der leere Katalog kein Ausnahmefall: `zusatz_katalog`
/// ist für drei der vier Rechtskreise leer. Der Bildschirm sähe also bei
/// Betreuungssachen und Sozialhilfe grau aus — bei Führerschein und Kfz aber
/// nicht. Ein Fehler, der nur die halbe Zeit auftritt, wird der Anzeige
/// zugeschrieben, nicht dem Code.
Map<String, String> vollmachtFeldAlsKatalog(dynamic v) {
  if (v is Map) {
    return v.map((k, w) => MapEntry(k.toString(), w.toString()));
  }
  return const {};
}

/// Eine Liste von Texten aus der Serverantwort.
List<String> vollmachtFeldAlsTexte(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : const [];

/// Eine Liste von Objekten aus der Serverantwort — etwa die Unterzeichner.
///
/// 🔴 Dieselbe Falle wie bei [vollmachtFeldAlsKatalog], nur andersherum: eine
/// Gruppe ohne Zeilen kommt als `[]` an, eine Serverfassung ohne das Feld gar
/// nicht, und `as List` wirft in beiden Fällen statt `null` zu geben — im
/// Release-Build eine graue Fläche ohne Meldung. Der Fall ist kein Randfall:
/// solange niemand „Zur Unterschrift stellen" gedrückt hat, ist die Liste leer.
///
/// Einträge, die keine Karte sind, fallen heraus statt alles mitzureißen.
List<Map<String, dynamic>> vollmachtFeldAlsZeilen(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

/// Vollmacht gegenüber dem Landratsamt — je Vorfall eine.
///
/// ⚠️ Die Vollmacht hängt an EINEM Vorgang, nicht am Mitglied. § 14 Abs. 1
/// Satz 2 VwVfG bindet die Ermächtigung an „alle das Verwaltungsverfahren
/// betreffenden Verfahrenshandlungen" — also an ein bestimmtes Verfahren. Die
/// echten Muster der Landratsämter halten es genauso: das Formular des
/// Landratsamts Heidenheim benennt Fahrzeug und Vorhaben, bevor unterschrieben
/// wird. Deshalb steht dieser Reiter im Vorfall und nicht neben ihm.
///
/// ⚠️ Die Rechtsgrundlage wechselt INNERHALB derselben Behörde: Sozialhilfe
/// läuft nach § 13 SGB X zum Sozialgericht, Führerschein und Kfz nach § 14
/// VwVfG zum Verwaltungsgericht. Welche gilt, entscheidet AUSSCHLIESSLICH der
/// Server anhand der Vorfall-Art; dieser Bildschirm zeigt sie nur an. Stünde
/// die Zuordnung auch hier, liefen Anzeige und Urkunde irgendwann auseinander.
class LandratsamtVollmachtTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int vorfallId;

  /// Nur für die Überschrift des Signaturauftrags, den das Mitglied sieht.
  final String vorfallBezeichnung;
  final String adminMitgliedernummer;

  /// Das Postfach des Mitglieds — Ziel des Chat-Versands.
  final String memberMitgliedernummer;

  const LandratsamtVollmachtTab({
    super.key,
    required this.apiService,
    required this.userId,
    required this.vorfallId,
    this.vorfallBezeichnung = '',
    this.adminMitgliedernummer = '',
    this.memberMitgliedernummer = '',
  });

  @override
  State<LandratsamtVollmachtTab> createState() => _LandratsamtVollmachtTabState();
}

class _LandratsamtVollmachtTabState extends State<LandratsamtVollmachtTab>
    with SingleTickerProviderStateMixin {
  static const MaterialColor _akzent = Colors.brown;

  late TabController _sub;
  bool _laden = true;
  bool _erzeugt = false;
  int? _beschaeftigt;

  Map<String, dynamic> _user = const {};
  Map<String, dynamic> _vorsitzer = const {};
  Map<String, dynamic> _verein = const {};
  Map<String, dynamic> _vorfall = const {};
  Map<String, dynamic> _amt = const {};
  Map<String, dynamic> _recht = const {};

  /// Schlüssel → Text. Kommt vom SERVER, steht nicht hier. Zwei Kataloge
  /// liefen auseinander, und dann hätte jemand etwas bevollmächtigt, das er
  /// nie gelesen hat.
  Map<String, String> _umfangKatalog = const {};
  Map<String, String> _zusatzKatalog = const {};
  List<String> _grenzen = const [];

  final Map<String, bool> _umfang = {};
  final Map<String, bool> _zusatz = {};
  DateTime _abDatum = DateTime.now();
  DateTime? _bisDatum;

  List<Map<String, dynamic>> _vollmachten = const [];
  int? _gewaehlt;

  /// Ziele und Bereitschaft aus `vorlagen`, plus das Versandprotokoll.
  /// [_zieleFuer] merkt, für WELCHE Vollmacht sie gelten — ohne das zeigte der
  /// Reiter nach dem Umschalten im Auswahlmenü weiter die Ziele der vorigen.
  Map<String, dynamic> _ziele = const {};
  List<Map<String, dynamic>> _zeilen = const [];
  List<Map<String, dynamic>> _links = const [];
  int? _zieleFuer;

  @override
  void initState() {
    super.initState();
    _sub = TabController(length: 3, vsync: this);
    _laden0();
  }

  @override
  void dispose() {
    _sub.dispose();
    super.dispose();
  }

  Future<void> _laden0() async {
    setState(() => _laden = true);
    final d = await widget.apiService.getVollmachtData(
        widget.userId, 'landratsamt', vorfallId: widget.vorfallId);
    final l = await widget.apiService.listVollmachten(
        widget.userId, 'landratsamt', vorfallId: widget.vorfallId);
    if (!mounted) return;
    setState(() {
      _laden = false;
      if (d['success'] == true) {
        _user      = vollmachtFeldAlsMap(d['user']);
        _vorsitzer = vollmachtFeldAlsMap(d['vorsitzer']);
        _verein    = vollmachtFeldAlsMap(d['verein']);
        _vorfall   = vollmachtFeldAlsMap(d['vorfall']);
        _amt       = vollmachtFeldAlsMap(d['amt']);
        _recht     = vollmachtFeldAlsMap(d['recht']);
        _umfangKatalog = vollmachtFeldAlsKatalog(_recht['umfang_katalog']);
        _zusatzKatalog = vollmachtFeldAlsKatalog(_recht['zusatz_katalog']);
        _grenzen       = vollmachtFeldAlsTexte(_recht['grenzen']);
        // Vorbelegt ist alles im Umfang — und NICHTS bei den
        // Zusatzerklärungen: die geben Daten preis (Steuer- und
        // Gebührenrückstände) und gehören ausdrücklich angekreuzt, nicht
        // stillschweigend mitgeliefert.
        for (final k in _umfangKatalog.keys) { _umfang.putIfAbsent(k, () => true); }
        for (final k in _zusatzKatalog.keys) { _zusatz.putIfAbsent(k, () => false); }
      }
      if (l['success'] == true && l['vollmachten'] is List) {
        _vollmachten = (l['vollmachten'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    });
  }

  void _sagen(String text, Color farbe) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text), backgroundColor: farbe));
  }

  List<String> _fehlend() {
    final f = <String>[];
    if ((_user['vorname'] ?? '').toString().isEmpty ||
        (_user['nachname'] ?? '').toString().isEmpty) {
      f.add('Name (Stufe 1)');
    }
    if ((_user['geburtsdatum'] ?? '').toString().isEmpty) f.add('Geburtsdatum');
    if ((_user['strasse'] ?? '').toString().isEmpty ||
        (_user['plz'] ?? '').toString().isEmpty) {
      f.add('Anschrift');
    }
    if ((_vorsitzer['vorname'] ?? '').toString().isEmpty) f.add('Vorsitzender');
    if ((_verein['vereinsname'] ?? '').toString().isEmpty) f.add('Vereinsdaten');
    return f;
  }

  Future<void> _erzeugen() async {
    setState(() => _erzeugt = true);
    final r = await widget.apiService.createVollmacht({
      'user_id': widget.userId,
      'behoerde': 'landratsamt',
      'vorfall_id': widget.vorfallId,
      'valid_from': DateFormat('yyyy-MM-dd').format(_abDatum),
      'valid_until': _bisDatum == null ? null : DateFormat('yyyy-MM-dd').format(_bisDatum!),
      'options': {'umfang': _umfang, 'zusatz': _zusatz},
    });
    if (!mounted) return;
    setState(() => _erzeugt = false);
    final ok = r['success'] == true;
    _sagen(ok ? 'Vollmacht erstellt (ID ${r['id']})' : (r['message'] ?? 'Fehler').toString(),
        ok ? Colors.green : Colors.red);
    if (ok) { await _laden0(); if (mounted) _sub.animateTo(1); }
  }

  Future<void> _widerrufen(int id) async {
    final grund = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Vollmacht widerrufen'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Sie wird als widerrufen markiert und kann danach weder versendet '
            'noch unterschrieben werden.\n\n'
            'Der Widerruf wirkt gegenüber der Behörde erst, wenn er IHR zugeht — '
            'er muss also zusätzlich schriftlich an das Landratsamt gehen.',
            style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(controller: grund, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Grund (optional)',
                border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true), child: const Text('Widerrufen')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await widget.apiService.revokeVollmacht(id, reason: grund.text.trim());
    if (!mounted) return;
    _sagen(r['success'] == true ? 'Widerrufen' : (r['message'] ?? 'Fehler').toString(),
        r['success'] == true ? Colors.orange : Colors.red);
    if (r['success'] == true) await _laden0();
  }

  Future<void> _pdfOeffnen(Map<String, dynamic> vm, {bool uebersetzung = false}) async {
    final id = vm['id'] as int;
    final r = await widget.apiService
        .downloadVollmachtPdf(id, type: uebersetzung ? 'translation' : 'pdf');
    if (!mounted) return;
    if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
      FileViewerDialog.showFromBytes(context, r.bodyBytes,
          ((uebersetzung ? vm['pdf_translation_filename'] : vm['pdf_filename'])
              ?? 'vollmacht_$id.pdf').toString());
    } else {
      _sagen('Fehler (${r.statusCode})', Colors.red);
    }
  }

  Future<void> _hochladen(int id, String signer, {FilePickerResult? ausCloud}) async {
    final auswahl = ausCloud ?? await FilePickerHelper.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'heif'],
      withData: true, allowMultiple: true,
    );
    if (auswahl == null || auswahl.files.isEmpty) return;
    setState(() => _beschaeftigt = id);
    var ok = 0, fehler = 0;
    for (final f in auswahl.files) {
      if (f.bytes == null) { fehler++; continue; }
      final r = await widget.apiService.uploadVollmachtSignature(
          vollmachtId: id, signer: signer, bytes: f.bytes!, filename: f.name);
      r['success'] == true ? ok++ : fehler++;
    }
    if (!mounted) return;
    setState(() => _beschaeftigt = null);
    _sagen('$ok hochgeladen${fehler > 0 ? ', $fehler fehlgeschlagen' : ''}',
        fehler > 0 ? Colors.orange : Colors.green);
    if (ok > 0) await _laden0();
  }

  // ── Anzeige ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_laden) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      TabBar(
        controller: _sub,
        labelColor: F.h(_akzent, 700),
        indicatorColor: F.h(_akzent, 700),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        tabs: [
          const Tab(icon: Icon(Icons.auto_awesome, size: 16), text: 'Generator'),
          Tab(icon: const Icon(Icons.history, size: 16), text: 'Historie (${_vollmachten.length})'),
          const Tab(icon: Icon(Icons.outbox, size: 16), text: 'Versand'),
        ],
      ),
      Expanded(child: TabBarView(controller: _sub, children: [
        _generator(),
        _historie(),
        _versand(),
      ])),
    ]);
  }

  Widget _titel(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Row(children: [
      Icon(icon, size: 16, color: F.h(_akzent, 700)),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
          color: F.h(_akzent, 800))),
    ]),
  );

  Widget _zeile(String k, String? v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 108, child: Text(k,
          style: const TextStyle(fontSize: 11, color: Colors.grey))),
      Expanded(child: Text((v ?? '').isEmpty ? '—' : v!,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _generator() {
    final fehlt = _fehlend();
    // ⚠️ Ohne Katalog gibt es nichts anzukreuzen — und der Grund ist fast
    // immer, dass der Vorfall nicht geladen werden konnte. Das gehört gesagt,
    // nicht als leere Fläche gezeigt.
    if (_umfangKatalog.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24),
        child: Text(
          'Für diesen Vorfall konnte die Rechtslage nicht bestimmt werden.\n'
          'Ist der Vorfall gespeichert und hat er eine Art?',
          style: TextStyle(color: F.h(Colors.grey, 600)), textAlign: TextAlign.center)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Rechtslage — sie steht ganz oben, weil sie alles andere bestimmt.
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: F.h(_akzent, 50),
            border: Border.all(color: F.h(_akzent, 200)),
            borderRadius: BorderRadius.circular(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.balance, size: 16, color: F.h(_akzent, 700)),
              const SizedBox(width: 6),
              Expanded(child: Text((_recht['label'] ?? '').toString(),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold,
                      color: F.h(_akzent, 900)))),
            ]),
            const SizedBox(height: 6),
            _zeile('Grundlage', (_recht['norm'] ?? '').toString()),
            _zeile('Post an uns', (_recht['norm_post'] ?? '').toString()),
            if ((_recht['rechtsweg'] ?? '').toString().isNotEmpty)
              _zeile('Rechtsweg',
                  '${_recht['rechtsweg']} (${_recht['rechtsweg_norm']})'),
            const SizedBox(height: 4),
            Text((_recht['einleitung'] ?? '').toString(),
                style: TextStyle(fontSize: 10.5, color: F.h(_akzent, 900),
                    fontStyle: FontStyle.italic)),
          ]),
        ),

        // ── Der Vorgang
        _titel(Icons.report_problem_outlined, 'Der Vorgang'),
        _zeile('Angelegenheit', (_vorfall['art'] ?? '').toString()),
        _zeile('Aktenzeichen', (_vorfall['aktenzeichen'] ?? '').toString()),
        _zeile('Datum', (_vorfall['datum'] ?? '').toString()),
        _zeile('Sachbearbeiter', (_vorfall['sachbearbeiter'] ?? '').toString()),
        _zeile('Landratsamt', (_amt['name'] ?? '').toString()),

        // ── Beteiligte
        _titel(Icons.people_outline, 'Beteiligte'),
        _zeile('Mitglied',
            '${_user['vorname'] ?? ''} ${_user['nachname'] ?? ''}'
            '${(_user['geburtsdatum'] ?? '').toString().isEmpty ? '' : ' — geb. ${_user['geburtsdatum']}'}'),
        _zeile('Vorstand', '${_vorsitzer['vorname'] ?? ''} ${_vorsitzer['nachname'] ?? ''}'),
        _zeile('Verein', (_verein['vereinsname'] ?? '').toString()),

        if (fehlt.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: F.h(Colors.red, 50),
                border: Border.all(color: F.h(Colors.red, 300))),
            child: Row(children: [
              Icon(Icons.warning, color: F.h(Colors.red, 700), size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('Fehlende Pflichtdaten: ${fehlt.join(", ")}',
                  style: TextStyle(fontSize: 11.5, color: F.h(Colors.red, 900)))),
            ]),
          ),
        ),

        // ── Umfang
        _titel(Icons.checklist, 'Umfang der Vollmacht'),
        ..._umfangKatalog.entries.map((e) => CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _umfang[e.key] ?? false,
          onChanged: (v) => setState(() => _umfang[e.key] = v ?? false),
          title: Text(e.value, style: const TextStyle(fontSize: 11.5)),
        )),

        if (_zusatzKatalog.isNotEmpty) ...[
          _titel(Icons.playlist_add_check, 'Zusätzliche Erklärungen'),
          Text(
            'Nicht vorangekreuzt: diese Erklärungen geben etwas preis und '
            'gehören ausdrücklich gewollt.',
            style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600))),
          ..._zusatzKatalog.entries.map((e) => CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _zusatz[e.key] ?? false,
            onChanged: (v) => setState(() => _zusatz[e.key] = v ?? false),
            title: Text(e.value, style: const TextStyle(fontSize: 11.5)),
          )),
        ],

        // ── Grenzen — was NICHT geht. Sie stehen auch auf dem Blatt; hier
        //    stehen sie, damit niemand etwas verspricht, das die Urkunde
        //    danach ausdrücklich ausschließt.
        if (_grenzen.isNotEmpty) ...[
          _titel(Icons.block, 'Was diese Vollmacht nicht umfasst'),
          ..._grenzen.map((g) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('•  ', style: TextStyle(fontSize: 11)),
              Expanded(child: Text(g, style: TextStyle(
                  fontSize: 10.5, color: F.h(Colors.grey, 800)))),
            ]),
          )),
        ],

        // ── Gültigkeit
        _titel(Icons.event, 'Gültigkeit'),
        Row(children: [
          Expanded(child: ListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            title: const Text('Gültig ab', style: TextStyle(fontSize: 11)),
            subtitle: Text(DateFormat('dd.MM.yyyy').format(_abDatum),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.calendar_today, size: 15),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _abDatum,
                  firstDate: DateTime(2020), lastDate: DateTime(2099));
              if (d != null) setState(() => _abDatum = d);
            },
          )),
          Expanded(child: ListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            title: const Text('Gültig bis', style: TextStyle(fontSize: 11)),
            subtitle: Text(_bisDatum == null
                ? 'auf Widerruf' : DateFormat('dd.MM.yyyy').format(_bisDatum!),
                style: const TextStyle(fontSize: 12.5)),
            trailing: _bisDatum != null
                ? IconButton(icon: const Icon(Icons.clear, size: 15),
                    onPressed: () => setState(() => _bisDatum = null))
                : const Icon(Icons.calendar_today, size: 15),
            onTap: () async {
              final d = await showDatePicker(context: context,
                  initialDate: _bisDatum ?? _abDatum.add(const Duration(days: 365)),
                  firstDate: _abDatum, lastDate: DateTime(2099));
              if (d != null) setState(() => _bisDatum = d);
            },
          )),
        ]),

        const SizedBox(height: 16),
        Center(child: ElevatedButton.icon(
          icon: _erzeugt
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.picture_as_pdf),
          label: Text(_erzeugt ? 'Erzeuge…' : 'PDF erzeugen & speichern'),
          style: ElevatedButton.styleFrom(
              backgroundColor: F.h(_akzent, 700), foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12)),
          onPressed: (_erzeugt || fehlt.isNotEmpty) ? null : _erzeugen,
        )),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _historie() {
    if (_vollmachten.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.assignment_ind_outlined, size: 44, color: F.h(Colors.grey, 300)),
          const SizedBox(height: 8),
          Text('Noch keine Vollmacht für diesen Vorgang.',
              style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 600))),
          const SizedBox(height: 4),
          Text('Im Reiter „Generator" eine erstellen — sie erscheint dann hier.',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 500)),
              textAlign: TextAlign.center),
        ])));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: _vollmachten.map(_karte).toList(),
    );
  }

  Widget _karte(Map<String, dynamic> vm) {
    final id = vm['id'] as int;
    final status = (vm['status'] ?? '').toString();
    final laeuft = _beschaeftigt == id;
    final (Color farbe, String text) = switch (status) {
      'draft'                 => (Colors.blue, 'ENTWURF'),
      'wartet_unterschriften' => (Colors.orange, 'WARTET AUF UNTERSCHRIFTEN'),
      'unterzeichnet'         => (Colors.lightGreen, 'UNTERZEICHNET'),
      'eingereicht'           => (Colors.green, 'EINGEREICHT'),
      'aktiv'                 => (Colors.green, 'AKTIV'),
      'revoked'               => (Colors.red, 'WIDERRUFEN'),
      'expired'               => (Colors.grey, 'ABGELAUFEN'),
      _                       => (Colors.grey, status.toUpperCase()),
    };
    final member   = (vm['signatures_member'] as List?) ?? const [];
    final vorstand = (vm['signatures_vorstand'] as List?) ?? const [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.picture_as_pdf, color: F.h(_akzent, 700), size: 20),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Vollmacht #$id',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('Erstellt: ${vm['generated_at'] ?? ''} · gültig ab '
                   '${vm['valid_from'] ?? ''} bis ${vm['valid_until'] ?? 'auf Widerruf'}',
                  style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600))),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: farbe.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10), border: Border.all(color: farbe)),
              child: Text(text, style: TextStyle(
                  fontSize: 9.5, fontWeight: FontWeight.bold, color: farbe)),
            ),
          ]),
          const Divider(height: 16),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('Öffnen (DE)', style: TextStyle(fontSize: 11)),
              onPressed: () => _pdfOeffnen(vm),
            ),
            // Das Leseexemplar in der Sprache des Mitglieds — es entsteht nur,
            // wenn dessen Sprache eine der sechs übersetzten ist.
            if ((vm['pdf_translation_filename'] ?? '').toString().isNotEmpty)
              OutlinedButton.icon(
                icon: const Icon(Icons.translate, size: 14),
                label: Text(
                  'Leseexemplar (${(vm['translation_language'] ?? '').toString().toUpperCase()})',
                  style: const TextStyle(fontSize: 11)),
                onPressed: () => _pdfOeffnen(vm, uebersetzung: true),
              ),
            if (status != 'revoked')
              TextButton.icon(
                icon: const Icon(Icons.block, size: 14, color: Colors.red),
                label: const Text('Widerrufen',
                    style: TextStyle(fontSize: 11, color: Colors.red)),
                onPressed: () => _widerrufen(id),
              ),
          ]),
          // ⚠️ Der Papierweg bleibt — nicht jede Behörde und nicht jedes
          // Mitglied kommt mit dem digitalen aus. Der digitale steht im
          // Reiter „Versand"; hier liegt das eingescannte Blatt.
          if (status != 'revoked') ...[
            const Divider(height: 16),
            Text('Unterschriebenes Exemplar hochladen',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold,
                    color: F.h(_akzent, 800))),
            const SizedBox(height: 4),
            _uploadZeile(id, 'member', 'Vom Mitglied', member, laeuft),
            _uploadZeile(id, 'vorstand', 'Vom Vorstand', vorstand, laeuft),
          ],
        ]),
      ),
    );
  }

  Widget _uploadZeile(int id, String signer, String label,
                      List<dynamic> dateien, bool laeuft) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(dateien.isEmpty ? Icons.pending_outlined : Icons.check_circle,
            size: 15, color: dateien.isEmpty ? Colors.orange : Colors.green),
        const SizedBox(width: 6),
        Expanded(child: Text('$label (${dateien.length})',
            style: const TextStyle(fontSize: 11))),
        if (laeuft)
          const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2))
        else ...[
          TextButton.icon(
            icon: const Icon(Icons.upload_file, size: 14),
            label: const Text('Upload', style: TextStyle(fontSize: 10.5)),
            onPressed: () => _hochladen(id, signer),
          ),
          CloudPickButton(
            memberId: widget.userId,
            apiService: widget.apiService,
            allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'heif'],
            kompakt: true,
            onPicked: (r) => _hochladen(id, signer, ausCloud: r),
          ),
        ],
      ]),
    );
  }

  // ── Versand ────────────────────────────────────────────────────────────
  //
  // ⚠️ Gebaut auf VollmachtLinkKnoepfe und VollmachtLinkZeile aus
  // vollmacht_link_aktionen.dart — dieselben Knöpfe, dieselbe
  // Reihenfolgeregel und dasselbe Protokoll wie beim Jobcenter, bei der
  // Insolvenzverwaltung und in der Anwaltsakte. Eine eigene Fassung wäre ein
  // zweiter Stand: derselbe Knopf, der an einer Stelle die Reihenfolge
  // erzwingt und an der anderen nicht.

  Future<void> _zurUnterschrift(Map<String, dynamic> vm) async {
    final id = vm['id'] as int;
    final vorsitzerId = int.tryParse('${vm['vorsitzer_id'] ?? ''}') ?? 0;
    if (widget.adminMitgliedernummer.isEmpty || vorsitzerId <= 0) {
      _sagen('Unterzeichner nicht ermittelbar — bitte neu laden', Colors.red);
      return;
    }

    // ⚠️ Ein zweiter Auftrag ersetzt den ersten NICHT — er legt eine zweite
    // Gruppe daneben, und beide leben weiter. Vor der Reparatur vom
    // 29.08.2026 bestimmte dann die ÄLTERE den angezeigten Stand: drei
    // Gruppen, nur die letzte unterschrieben, Anzeige „0 von 2", Versand
    // gesperrt. Der Server nimmt jetzt die richtige — aber ein zweites
    // Bündel Unterschriftsaufforderungen an dieselben zwei Menschen zu
    // schicken bleibt trotzdem falsch, solange das erste noch offen ist.
    final standGilt = _laufendeUnterschriften(id);
    final wieViele   = (_ziele['noetig'] ?? 0) as int;
    final wieWeit    = (_ziele['unterschrieben'] ?? 0) as int;
    final schonFertig = standGilt && wieViele > 0 && wieWeit >= wieViele;
    final schonOffen  = standGilt && wieViele > 0 && !schonFertig;
    if (schonFertig || schonOffen) {
      final weiter = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: Text(schonFertig ? 'Es ist schon unterschrieben' : 'Es läuft schon eine Anforderung',
            style: const TextStyle(fontSize: 15)),
        content: Text(
          schonFertig
              ? 'Zu dieser Vollmacht liegen bereits alle Unterschriften vor.\n\n'
                'Eine neue Anforderung hebt sie nicht auf — sie stellt beiden '
                'dasselbe Blatt ein zweites Mal zu. Nur sinnvoll, wenn die '
                'vorhandene Unterschrift nicht mehr gelten soll; dann die '
                'Vollmacht widerrufen und eine neue erzeugen.'
              : 'Beide sind bereits aufgefordert, es fehlt nur noch eine '
                'Unterschrift.\n\nEine zweite Aufforderung ersetzt die erste '
                'nicht — sie kommt daneben an, mit einem zweiten Code.',
          style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(c, true),
              child: const Text('Trotzdem erneut stellen')),
        ]));
      if (weiter != true || !mounted) return;
    }
    final los = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Zur Unterschrift stellen?'),
      content: const Text(
        'Die deutsche Fassung geht an beide Unterzeichner: an das Mitglied als '
        'Vollmachtgeber und an den Vorstand als Bevollmächtigten. Beide '
        'unterschreiben in ihrer eigenen App und bekommen einen Code auf ihre '
        'Mobilnummer.\n\n'
        'Wirksam wird die Vollmacht erst, wenn beide unterschrieben haben.',
        style: TextStyle(fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: F.h(_akzent, 700), foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(c, true), child: const Text('Stellen')),
      ]));
    if (los != true || !mounted) return;

    setState(() => _beschaeftigt = id);
    try {
      final r = await widget.apiService.downloadVollmachtPdf(id);
      if (!mounted) return;
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        _sagen('PDF konnte nicht geladen werden (${r.statusCode})', Colors.red);
        return;
      }
      final e = await SignaturService().anfordernAusBytes(
        callerMitgliedernummer: widget.adminMitgliedernummer,
        userId: widget.userId,
        dokumentTyp: 'landratsamt_vollmacht',
        dokumentTitel: widget.vorfallBezeichnung.isEmpty
            ? 'Vollmacht — Landratsamt'
            : 'Vollmacht — ${widget.vorfallBezeichnung}',
        pdfBytes: r.bodyBytes,
        dateiname: (vm['pdf_filename'] ?? 'vollmacht_$id.pdf').toString(),
        fristBis: DateTime.now().add(const Duration(days: 14)),
        quelleTabelle: 'member_vollmachten',
        quelleId: id,
        unterzeichner: [
          Unterzeichner(userId: widget.userId, rolle: 'vollmachtgeber'),
          Unterzeichner(userId: vorsitzerId, rolle: 'bevollmaechtigter'),
        ],
      );
      if (!mounted) return;
      _sagen(e.ok ? 'Zur Unterschrift gestellt — beide sind benachrichtigt'
                  : (e.fehler ?? 'Anforderung fehlgeschlagen'),
             e.ok ? Colors.green : Colors.red);
      if (e.ok) await _laden0();
    } finally {
      if (mounted) setState(() => _beschaeftigt = null);
    }
  }

  /// Das Blatt in das Postfach DES MITGLIEDS.
  ///
  /// ⚠️ Es geht das LESEEXEMPLAR in der Sprache des Mitglieds, wenn es eines
  /// gibt — es ist sein Recht zu wissen, was er unterschreibt. Unterschrieben
  /// und beim Landratsamt eingereicht wird weiter allein die deutsche Fassung;
  /// das steht auch auf jeder Seite des Leseexemplars.
  ///
  /// ⚠️ Ohne den Typ `translation` ginge stillschweigend das deutsche Blatt
  /// hinaus, während der Dialog eine Übersetzung angekündigt hat.
  Future<void> _inDenChat(Map<String, dynamic> vm) async {
    final id = vm['id'] as int;
    final nummer = widget.memberMitgliedernummer.trim();
    if (nummer.isEmpty || widget.adminMitgliedernummer.isEmpty) {
      _sagen('Empfänger nicht ermittelbar', Colors.red);
      return;
    }
    final sprache = (vm['translation_language'] ?? '').toString().trim();
    final uebersetzt = sprache.isNotEmpty
        && (vm['pdf_translation_filename'] ?? '').toString().trim().isNotEmpty;
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('In den Chat senden?'),
      content: Text(
        uebersetzt
            ? 'Das Leseexemplar (${sprache.toUpperCase()}) geht an $nummer.\n\n'
              'Unterschrieben und beim Landratsamt eingereicht wird weiter '
              'allein die deutsche Fassung — das steht auch auf jeder Seite '
              'des Leseexemplars.'
            : 'Die deutsche Fassung geht an $nummer.\n\n'
              'Ein Leseexemplar in der Sprache des Mitglieds gibt es für diese '
              'Vollmacht nicht. Der Verein erläutert den Inhalt mündlich.',
        style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: F.h(_akzent, 700), foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(c, true), child: const Text('Senden')),
      ]));
    if (ok != true || !mounted) return;

    File? temp;
    setState(() => _beschaeftigt = id);
    try {
      final r = await widget.apiService
          .downloadVollmachtPdf(id, type: uebersetzt ? 'translation' : 'pdf');
      if (!mounted) return;
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        _sagen('Fehler (${r.statusCode})', Colors.red); return;
      }
      final g = await widget.apiService
          .adminStartChat(widget.adminMitgliedernummer, nummer);
      final cid = int.tryParse('${g['conversation_id'] ?? ''}')
          ?? int.tryParse('${(g['data'] as Map?)?['conversation_id'] ?? ''}') ?? 0;
      if (cid <= 0) { _sagen('Kein Gespräch mit $nummer gefunden', Colors.red); return; }

      temp = File('${(await getTemporaryDirectory()).path}/'
          'vollmacht_$id${uebersetzt ? '_$sprache' : ''}.pdf');
      await temp.writeAsBytes(r.bodyBytes, flush: true);
      final res = await widget.apiService.uploadChatAttachments(
        conversationId: cid, mitgliedernummer: widget.adminMitgliedernummer,
        files: [temp],
        message: uebersetzt
            ? 'Vollmacht (Leseexemplar) — Landratsamt'
            : 'Vollmacht — Landratsamt');
      if (!mounted) return;
      final erfolg = res['success'] == true;
      // ⚠️ Erst NACH bestätigtem Empfang protokollieren. Eine Zeile, die eine
      // Sendung behauptet, die nie ankam, ist genau die, auf die sich später
      // jemand verlässt.
      if (erfolg) {
        await widget.apiService.landratsamtVollmachtVersandEintragen(
          vollmachtId: id, empfaenger: nummer, weg: 'chat',
          fassung: uebersetzt ? 'uebersetzung' : 'original',
          sprache: uebersetzt ? sprache : 'de');
      }
      if (!mounted) return;
      _sagen(erfolg ? 'An $nummer gesendet' : 'Konnte nicht gesendet werden',
             erfolg ? Colors.green : Colors.red);
      if (erfolg) await _laden0();
    } catch (e) {
      if (mounted) _sagen('Fehler: $e', Colors.red);
    } finally {
      if (temp != null && await temp.exists()) { await temp.delete(); }
      if (mounted) setState(() => _beschaeftigt = null);
    }
  }

  Future<void> _anBehoerde(Map<String, dynamic> vm, bool perFax) async {
    final id = vm['id'] as int;
    final ziel = perFax ? (_ziele['fax'] ?? '').toString()
                        : (_ziele['empfaenger'] ?? '').toString();
    final stelle = (_ziele['stelle'] ?? 'die Behörde').toString();
    final ausVorfall = (_ziele['sachbearbeiter'] ?? '').toString().isNotEmpty;
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(perFax ? 'Vollmacht faxen?' : 'Vollmacht mailen?'),
      content: Text('Die unterschriebene Vollmacht geht an:\n\n$stelle\n$ziel'
          '${ausVorfall ? '\n\n(Ziel aus dem Vorgang, nicht aus den Amtsdaten.)' : ''}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Senden')),
      ]));
    if (ok != true) return;
    setState(() => _beschaeftigt = id);
    final r = perFax
        ? await widget.apiService.landratsamtVollmachtFaxSenden(vollmachtId: id)
        : await widget.apiService.landratsamtVollmachtMailSenden(vollmachtId: id);
    if (!mounted) return;
    setState(() => _beschaeftigt = null);
    final gut = r['success'] == true;
    _sagen((r['message'] ?? (gut ? 'Gesendet' : 'Fehler')).toString(),
        gut ? Colors.green : Colors.red);
    if (gut) await _laden0();
  }

  /// Die Unterzeichner der Gruppe, die der Server als massgeblich gewaehlt hat.
  ///
  /// ⚠️ Tolerant gelesen: `unterzeichner` fehlt in der Antwort einer aelteren
  /// Serverfassung ganz, und ein leeres PHP-Array kommt als Liste `[]` an.
  /// Vgl. den Kopf von [vollmachtFeldAlsKatalog] — dasselbe Muster hat schon
  /// einen Bildschirm grau werden lassen.
  List<Map<String, dynamic>> _unterzeichner() =>
      vollmachtFeldAlsZeilen(_ziele['unterzeichner']);

  /// Gehoert der geladene Stand zu genau dieser Vollmacht?
  ///
  /// [_ziele] wird nachgeladen; solange das laeuft, gehoeren die Zahlen darin
  /// noch zur vorigen Auswahl. Eine Warnung „ist schon unterschrieben", die
  /// sich auf eine andere Vollmacht bezieht, waere schlimmer als keine.
  bool _laufendeUnterschriften(int id) => _zieleFuer == id && _ziele.isNotEmpty;

  /// Eine Zeile je Person: Name, in welcher Eigenschaft, wann.
  Widget _unterzeichnerZeile(Map<String, dynamic> u) {
    final status = (u['status'] ?? '').toString();
    final (IconData icon, MaterialColor farbe) = switch (status) {
      'signiert'   => (Icons.check_circle, Colors.green),
      'abgelehnt'  => (Icons.cancel, Colors.red),
      'widerrufen' => (Icons.block, Colors.red),
      'abgelaufen' => (Icons.timer_off, Colors.grey),
      _            => (Icons.pending_outlined, Colors.orange),
    };
    // Die Rolle beschreibt, ALS WAS jemand unterschreibt — nicht seine Rolle
    // im Verein. Der Vorsitzende zeichnet hier als Bevollmächtigter.
    final rolle = switch ((u['rolle'] ?? '').toString()) {
      'vollmachtgeber'    => 'Vollmachtgeber (Mitglied)',
      'bevollmaechtigter' => 'Bevollmächtigter (Vorstand)',
      final r             => r.isEmpty ? '' : r,
    };
    final name = (u['name'] ?? '').toString().trim();
    final wann = (u['signiert_am'] ?? '').toString().trim();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: F.h(farbe, 600)),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Ein geloeschtes Konto laesst den Namen leer — die Zeile bleibt
          // trotzdem stehen, sonst sähe es aus, als fehlte der Unterzeichner.
          Text(name.isEmpty ? '(Name nicht mehr hinterlegt)' : name,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          Text(
            rolle.isEmpty ? status : '$rolle · ${status == 'signiert' ? 'unterschrieben' : status}'
                '${wann.isEmpty ? '' : ' am $wann'}',
            style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600))),
        ])),
      ]),
    );
  }

  /// Oeffnet die Fassung, auf der die Unterschriften stehen.
  ///
  /// ⚠️ „Noch nicht gesiegelt" und „fehlgeschlagen" sind zwei verschiedene
  /// Dinge: gesiegelt wird in einem eigenen Lauf im Minutentakt. Wer beides
  /// als Fehler meldet, sagt „kaputt", wo „einen Moment noch" richtig waere.
  Future<void> _signiertesOeffnen(int signaturId, Map<String, dynamic> vm) async {
    if (widget.adminMitgliedernummer.isEmpty) {
      _sagen('Ohne Anmeldung als Vorstand nicht abrufbar', Colors.red);
      return;
    }
    final name = 'vollmacht_${vm['id']}_unterschrieben.pdf';
    final gesiegelt = await SignaturService().herunterladenMitGrund(
      callerMitgliedernummer: widget.adminMitgliedernummer,
      signaturId: signaturId, welche: 'signiert');
    if (!mounted) return;
    if (gesiegelt.bytes != null) {
      await FileViewerDialog.showFromBytes(
          context, Uint8List.fromList(gesiegelt.bytes!), name);
      return;
    }
    final weiter = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Siegel noch nicht fertig', style: TextStyle(fontSize: 15)),
      content: Text(
        '${gesiegelt.hinweis ?? 'Die gesiegelte Fassung wird noch erstellt.'}\n\n'
        'Solange lässt sich die Fassung öffnen, die den Unterzeichnern vorlag — '
        'ohne Siegel und ohne Zeitstempel.',
        style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Original öffnen')),
      ]));
    if (weiter != true || !mounted) return;
    final orig = await SignaturService().herunterladenMitGrund(
      callerMitgliedernummer: widget.adminMitgliedernummer,
      signaturId: signaturId, welche: 'original');
    if (!mounted) return;
    if (orig.bytes == null) {
      _sagen(orig.hinweis ?? 'Dokument konnte nicht geladen werden', Colors.red);
      return;
    }
    await FileViewerDialog.showFromBytes(
        context, Uint8List.fromList(orig.bytes!), 'vollmacht_${vm['id']}_original.pdf');
  }

  Future<void> _zieleLaden(int id) async {
    final z = await widget.apiService.landratsamtVollmachtVorlagen(id);
    final p = await widget.apiService.landratsamtVollmachtVersandListe(id);
    if (!mounted) return;
    setState(() {
      _ziele = z['success'] == true ? Map<String, dynamic>.from(z) : const {};
      if (p['success'] == true) {
        _zeilen = ((p['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _links = ((p['links'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    });
  }

  Widget _versand() {
    if (_vollmachten.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24),
        child: Text('Erst eine Vollmacht erzeugen — dann führen von hier die Wege hinaus.',
            style: TextStyle(color: F.h(Colors.grey, 600)), textAlign: TextAlign.center)));
    }
    final gewaehlt = _gewaehlt ?? (_vollmachten.first['id'] as int);
    final vm = _vollmachten.firstWhere((v) => v['id'] == gewaehlt,
        orElse: () => _vollmachten.first);
    final id = vm['id'] as int;
    if (_zieleFuer != id) { _zieleFuer = id; scheduleMicrotask(() => _zieleLaden(id)); }

    final status = (vm['status'] ?? '').toString();
    final widerrufen = status == 'revoked';
    final bereit = _ziele['bereit'] == true;
    final noetig = (_ziele['noetig'] ?? 0) as int;
    final fertig = (_ziele['unterschrieben'] ?? 0) as int;
    // ⚠️ Zwei verschiedene Dinge, die vorher eins waren: `vollstaendig` heisst
    // „beide haben unterschrieben", `bereit` heisst „die gesiegelte Fassung
    // liegt auf der Platte". Gesiegelt wird im Minutentakt, also gibt es ein
    // Fenster, in dem das erste stimmt und das zweite noch nicht.
    final vollstaendig = noetig > 0 && fertig >= noetig;
    final signaturId = (_ziele['signatur_id'] ?? 0) as int;
    final laeuft = _beschaeftigt == id;

    return ListView(padding: const EdgeInsets.all(12), children: [
      if (_vollmachten.length > 1)
        Padding(padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: id,
            decoration: const InputDecoration(labelText: 'Welche Vollmacht',
                isDense: true, border: OutlineInputBorder()),
            items: _vollmachten.map((v) => DropdownMenuItem<int>(
              value: v['id'] as int,
              child: Text('#${v['id']} — ${v['valid_from']} — '
                          '${(v['status'] ?? '').toString().toUpperCase()}',
                  style: const TextStyle(fontSize: 12)),
            )).toList(),
            onChanged: (w) => setState(() => _gewaehlt = w),
          )),

      if (widerrufen)
        // 🔴 Der Server lehnt ohnehin ab; hier steht der Grund, statt ihn erst
        // nach dem Klick zu zeigen.
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: F.h(Colors.red, 50), border: Border.all(color: F.h(Colors.red, 300)),
            borderRadius: BorderRadius.circular(6)),
          child: Text(
            'Diese Vollmacht ist widerrufen. Sie bleibt als Spur in der Akte, '
            'darf aber nicht mehr versendet und nicht mehr unterschrieben werden.',
            style: TextStyle(fontSize: 11.5, color: F.h(Colors.red, 900))))
      else ...[
        _titel(Icons.verified_user, 'Unterschrift'),
        Text(
          vollstaendig
              ? (bereit
                  ? 'Beide Unterschriften liegen vor.'
                  : 'Beide haben unterschrieben — die gesiegelte Fassung wird noch erstellt.')
              : (noetig > 0
                  ? '$fertig von $noetig Unterschriften liegen vor.'
                  : 'Noch nicht zur Unterschrift gestellt.'),
          style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700))),
        // Wer unterschrieben hat, mit Namen und Uhrzeit. Eine Zahl allein sagt
        // nicht, auf WEN noch gewartet wird — und beim Nachfragen ist genau
        // das die einzige Auskunft, die gebraucht wird.
        ..._unterzeichner().map(_unterzeichnerZeile),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          ElevatedButton.icon(
            icon: laeuft
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.draw, size: 15),
            label: const Text('Zur Unterschrift stellen', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
                backgroundColor: F.h(Colors.green, 700), foregroundColor: Colors.white),
            onPressed: laeuft ? null : () => _zurUnterschrift(vm),
          ),
          // ⚠️ NICHT dasselbe wie „Öffnen (DE)" im Reiter Historie: der Knopf
          // dort holt das ERZEUGTE Blatt mit den leeren Linien. Hier kommt die
          // Fassung, auf der die beiden Unterschriften stehen.
          if (signaturId > 0 && vollstaendig)
            OutlinedButton.icon(
              icon: const Icon(Icons.verified, size: 15),
              label: const Text('Unterschriebene Fassung', style: TextStyle(fontSize: 11)),
              onPressed: laeuft ? null : () => _signiertesOeffnen(signaturId, vm),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.chat_outlined, size: 15),
            label: const Text('In den Chat', style: TextStyle(fontSize: 11)),
            onPressed: laeuft ? null : () => _inDenChat(vm),
          ),
        ]),

        _titel(Icons.sms_outlined, 'Ohne App: Link per SMS'),
        VollmachtLinkKnoepfe(
          farbe: _akzent,
          widerrufen: widerrufen,
          // ⚠️ Der Signierlink FÜHRT zu einem offenen Vorgang, er legt keinen
          // an. Ohne gestellte Unterschrift lehnt der Server ab — der Knopf
          // bleibt deshalb grau, statt die Auskunft erst nach dem Klick zu geben.
          signierbar: noetig > 0,
          signierHinweis: 'Erst „Zur Unterschrift stellen" — der Link führt zu '
                          'einem offenen Vorgang, er legt keinen an.',
          onGesendet: () => _zieleLaden(id),
          onSenden: (zweck) => widget.apiService
              .landratsamtVollmachtLinkSenden(vollmachtId: id, zweck: zweck),
        ),

        _titel(Icons.outbox, 'An das Landratsamt'),
        if (!bereit)
          Text(
            vollstaendig
                ? 'Beide haben unterschrieben. Die gesiegelte Fassung entsteht '
                  'im Minutentakt — gleich noch einmal öffnen, dann geht der Versand.'
                : 'Erst unterschreiben lassen, dann senden — eine unvollständige '
                  'Vollmacht kostet nur eine Rückfrage.',
            style: TextStyle(fontSize: 11.5, color: F.h(Colors.orange, 800)))
        else ...[
          if ((_ziele['stelle'] ?? '').toString().isNotEmpty)
            Text('Empfänger: ${_ziele['stelle']}'
                 '${(_ziele['sachbearbeiter'] ?? '').toString().isNotEmpty ? '  (aus dem Vorgang)' : ''}',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.mail_outline, size: 15),
              label: Text((_ziele['empfaenger'] ?? '').toString().isEmpty
                  ? 'Keine E-Mail' : 'Per E-Mail', style: const TextStyle(fontSize: 11)),
              onPressed: (laeuft || (_ziele['empfaenger'] ?? '').toString().isEmpty)
                  ? null : () => _anBehoerde(vm, false),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.print_outlined, size: 15),
              label: Text((_ziele['fax'] ?? '').toString().isEmpty
                  ? 'Kein Fax' : 'Per Fax', style: const TextStyle(fontSize: 11)),
              onPressed: (laeuft || (_ziele['fax'] ?? '').toString().isEmpty)
                  ? null : () => _anBehoerde(vm, true),
            ),
          ]),
        ],
      ],

      _titel(Icons.receipt_long, 'Versandprotokoll (${_zeilen.length + _links.length})'),
      if (_zeilen.isEmpty && _links.isEmpty)
        Text('Noch nichts versandt.',
            style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 600))),
      // ⚠️ kVollmachtVersandWege statt des Rohwerts: sonst stünde hier
      // „fax an +49 731 …", kleingeschrieben und ohne Präposition, wie ein
      // Datenbankauszug.
      ..._zeilen.map((z) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          '${z['gesendet_am'] ?? ''} · '
          '${kVollmachtVersandWege[(z['weg'] ?? '').toString()] ?? (z['weg'] ?? '')} '
          'an ${z['empfaenger'] ?? ''}'
          '${(z['gesendet_von_name'] ?? '').toString().isEmpty ? '' : ' · durch ${z['gesendet_von_name']}'}',
          style: const TextStyle(fontSize: 12)))),
      ..._links.map((l) => VollmachtLinkZeile(link: l)),
    ]);
  }
}
