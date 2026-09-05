import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/app_farben.dart';
import '../utils/cloud_picker_helper.dart';
// ⚠️ FileType/FilePickerResult kommen aus DIESEM Helfer, nicht aus
// package:file_picker — ein direkter Import macht die Namen mehrdeutig.
import '../utils/file_picker_helper.dart';
import '../utils/massnahme_konstanten.dart';
import 'file_viewer_dialog.dart';

/// Detailansicht EINER Zuweisung: Details · Bewilligung · Korrespondenz.
///
/// Öffnet sich beim Antippen der Karte im Reiter „Maßnahme (Träger)".
///
/// ⚠️ Die Dateien liegen serverseitig AES-256-GCM-verschlüsselt als BLOB.
/// Angesehen werden sie aus dem Arbeitsspeicher (`showFromBytes`) — sie
/// berühren die Platte des Geräts nie.
class MassnahmeDetailModal extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> zuweisung;
  /// Mitgliedsnummer des Bearbeiters. Ein Schriftwechsel ohne Verfasser ist
  /// kein Verlauf — später ist nicht mehr zu klären, wer was notiert hat.
  final String? bearbeiter;
  const MassnahmeDetailModal({
    super.key,
    required this.apiService,
    required this.userId,
    required this.zuweisung,
    this.bearbeiter,
  });

  @override
  State<MassnahmeDetailModal> createState() => _MassnahmeDetailModalState();
}

class _MassnahmeDetailModalState extends State<MassnahmeDetailModal>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _geaendert = false;

  int get _zid => mnZahl(widget.zuweisung['id']) ?? 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final z = widget.zuweisung;
    final fenster = MediaQuery.of(context).size;
    final schmal = fenster.width < 600;
    return Dialog(
      insetPadding: EdgeInsets.all(schmal ? 6 : 16),
      child: SizedBox(
        width: schmal ? fenster.width * 0.98 : (fenster.width * 0.9).clamp(720.0, 1100.0),
        height: fenster.height * (schmal ? 0.95 : 0.9),
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
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(z['titel']?.toString() ?? '—',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                Text(z['traeger_name']?.toString() ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ])),
              IconButton(icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context, _geaendert)),
            ]),
          ),
          TabBar(controller: _tab, labelColor: F.h(Colors.indigo, 800),
            indicatorColor: F.h(Colors.indigo, 700),
            tabs: const [
              Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
              Tab(icon: Icon(Icons.verified_outlined, size: 18), text: 'Bewilligung'),
              Tab(icon: Icon(Icons.forum_outlined, size: 18), text: 'Korrespondenz'),
            ]),
          Expanded(child: TabBarView(controller: _tab, children: [
            _DetailsTab(zuweisung: z),
            MassnahmeDateiTab(
              apiService: widget.apiService,
              userId: widget.userId,
              zuweisungId: _zid,
              bereich: 'bewilligung',
              hinweis: 'Der Zuweisungs-/Bewilligungsbescheid und weitere Unterlagen '
                  'zu dieser Maßnahme. PDF, JPEG oder PNG, höchstens 20 MB.',
              onChanged: () => _geaendert = true,
            ),
            _KorrespondenzTab(
              apiService: widget.apiService,
              userId: widget.userId,
              zuweisungId: _zid,
              bearbeiter: widget.bearbeiter,
              onChanged: () => _geaendert = true,
            ),
          ])),
        ]),
      ),
    );
  }
}

// ═══════════════════════════ Details ═══════════════════════════

class _DetailsTab extends StatelessWidget {
  final Map<String, dynamic> zuweisung;
  const _DetailsTab({required this.zuweisung});

  @override
  Widget build(BuildContext context) {
    final z = zuweisung;
    final df = DateFormat('dd.MM.yyyy');
    final beginn = massnahmeDatum(z['beginn']);
    final ende = massnahmeDatum(z['ende']);
    final bekannt = massnahmeDatum(z['bekanntgabe_datum']);
    final tage = massnahmeTageBisFrist(bekannt);
    final status = z['status']?.toString() ?? '';
    // Die Nummer der Zuweisung geht der des Katalogs vor — im Bescheid steht
    // die dieses Durchgangs, und die gilt.
    final nr = (z['nummer_wirksam'] ?? z['massnahmenummer'] ?? '').toString();

    return ListView(padding: const EdgeInsets.all(14), children: [
      if (z['lesbar'] == false)
        _kasten(Colors.red,
            '⚠ Mindestens ein Textfeld konnte nicht entschlüsselt werden. Die '
            'Angaben sind NICHT leer — bitte nicht überschreiben, sondern melden.'),

      // ⚠️ Ohne Maßnahmenummer stammt die Bezeichnung von der Webseite des
      // Trägers und ist nicht die, unter der das Jobcenter die Maßnahme führt.
      if (nr.isEmpty)
        _kasten(Colors.orange,
            'Diese Maßnahme hat keine Maßnahmenummer — die Bezeichnung stammt '
            'von der Webseite des Trägers. Im Bescheid lautet sie oft anders; '
            'für einen Widerspruch zählt die dort genannte.'),

      _abschnitt('Maßnahme'),
      _z('Bezeichnung', z['titel']?.toString() ?? '—'),
      if (nr.isNotEmpty) _z('Nummer der Maßnahme', nr),
      _z('Art', kMassnahmeArtLabel[z['art']?.toString()] ?? (z['art']?.toString() ?? '—')),
      _z('Rechtsgrundlage', z['rechtsgrundlage']?.toString() ?? kMassnahmeRechtsgrundlage),
      _z('Status', kMassnahmeStatusLabel[status] ?? status),
      if ((z['zielgruppe'] ?? '').toString().isNotEmpty)
        _z('Zielgruppe', z['zielgruppe'].toString()),

      _abschnitt('Zeit und Ort'),
      _z('Zeitraum',
          '${beginn != null ? df.format(beginn) : "?"} – ${ende != null ? df.format(ende) : "offen"}'),
      if ((z['stunden_woche'] ?? '').toString().isNotEmpty)
        _z('Stunden/Woche', z['stunden_woche'].toString()),
      if ((z['durchfuehrungsort'] ?? '').toString().isNotEmpty)
        _z('Durchführungsort', z['durchfuehrungsort'].toString()),
      if (massnahmeDatum(z['zuweisung_datum']) != null)
        _z('Zuweisungsschreiben', df.format(massnahmeDatum(z['zuweisung_datum'])!)),
      if (bekannt != null) _z('Bekanntgabe', df.format(bekannt)),
      if ((z['aktenzeichen'] ?? '').toString().isNotEmpty)
        _z('Aktenzeichen (Jobcenter)', z['aktenzeichen'].toString()),
      if ((z['kundennummer'] ?? '').toString().isNotEmpty)
        _z('Kundennummer', z['kundennummer'].toString()),

      if (tage != null && massnahmeIstOffen(status))
        _kasten(tage < 0 ? Colors.grey : (tage <= 7 ? Colors.red : Colors.amber),
            tage < 0
                ? 'Widerspruchsfrist (§ 84 Abs. 1 SGG) ist seit ${-tage} Tagen abgelaufen.'
                : 'Widerspruchsfrist (§ 84 Abs. 1 SGG) läuft in $tage Tagen ab '
                  '(${df.format(massnahmeWiderspruchsfrist(bekannt)!)}).'),

      _abschnitt('Träger'),
      _z('Name', z['traeger_name']?.toString() ?? '—'),
      if ((z['rechtstraeger'] ?? '').toString().isNotEmpty)
        _z('Rechtsträger', z['rechtstraeger'].toString()),
      if ((z['strasse'] ?? '').toString().isNotEmpty)
        _z('Anschrift', '${z['strasse']}, ${z['plz'] ?? ''} ${z['ort'] ?? ''}'.trim()),
      if ((z['telefon'] ?? '').toString().isNotEmpty) _z('Telefon', z['telefon'].toString()),
      if ((z['email'] ?? '').toString().isNotEmpty) _z('E-Mail', z['email'].toString()),
      if ((z['website'] ?? '').toString().isNotEmpty) _z('Web', z['website'].toString()),
      if (z['azav_geprueft'] == null)
        Padding(padding: const EdgeInsets.only(top: 6),
            child: Text('AZAV-Zulassung: nicht geprüft — die erteilt eine fachkundige Stelle, nicht wir.',
                style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600), fontStyle: FontStyle.italic))),

      if ((z['beschreibung'] ?? '').toString().isNotEmpty) ...[
        _abschnitt('Inhalt laut Bescheid'),
        Text(z['beschreibung'].toString(), style: const TextStyle(fontSize: 12)),
      ],
      if ((z['notiz'] ?? '').toString().isNotEmpty) ...[
        _abschnitt('Notiz'),
        Text(z['notiz'].toString(), style: const TextStyle(fontSize: 12)),
      ],
      const SizedBox(height: 20),
    ]);
  }

  Widget _abschnitt(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
            color: F.h(Colors.indigo, 800))),
      );

  Widget _z(String label, String wert) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 140, child: Text(label,
              style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)))),
          Expanded(child: SelectableText(wert, style: const TextStyle(fontSize: 12))),
        ]),
      );

  Widget _kasten(MaterialColor farbe, String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: F.h(farbe, 50),
          border: Border.all(color: F.h(farbe, 200)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: TextStyle(fontSize: 11.5, color: F.h(farbe, 900))),
      );
}

// ═══════════════════════ Dateien (Bewilligung / Anhänge) ═══════════════════

/// Liste + Upload verschlüsselter Dokumente zu einer Zuweisung.
///
/// Wird zweimal benutzt: für die Bewilligung selbst und für die Anhänge eines
/// Korrespondenz-Eintrags. ⚠️ Absichtlich EIN Weg für beides — zwei getrennte
/// Hochladewege bekämen je eigene Grenzen und Fehlermeldungen.
class MassnahmeDateiTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int zuweisungId;
  final String bereich;
  final int? korrespondenzId;
  final String? hinweis;
  final bool kompakt;
  final VoidCallback? onChanged;
  const MassnahmeDateiTab({
    super.key,
    required this.apiService,
    required this.userId,
    required this.zuweisungId,
    required this.bereich,
    this.korrespondenzId,
    this.hinweis,
    this.kompakt = false,
    this.onChanged,
  });

  @override
  State<MassnahmeDateiTab> createState() => _MassnahmeDateiTabState();
}

class _MassnahmeDateiTabState extends State<MassnahmeDateiTab> {
  List<Map<String, dynamic>> _docs = [];
  bool _laden = true, _busy = false;
  static const _erlaubt = ['pdf', 'jpg', 'jpeg', 'png'];
  static const _max = 20;

  @override
  void initState() { super.initState(); _laden1(); }

  Future<void> _laden1() async {
    final r = await widget.apiService.massnahmeDokListe(
      zuweisungId: widget.zuweisungId,
      userId: widget.userId,
      bereich: widget.bereich,
      korrespondenzId: widget.korrespondenzId,
    );
    if (!mounted) return;
    setState(() {
      _docs = (r['success'] == true && r['dokumente'] is List)
          ? List<Map<String, dynamic>>.from(
              (r['dokumente'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
          : [];
      _laden = false;
    });
  }

  void _melden(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _hochladen({FilePickerResult? ausCloud}) async {
    if (_docs.length >= _max) { _melden('Höchstens $_max Dokumente'); return; }
    final ergebnis = ausCloud ??
        await FilePickerHelper.pickFiles(
            type: FileType.custom, allowedExtensions: _erlaubt, allowMultiple: true);
    if (ergebnis == null || ergebnis.files.isEmpty) return;

    setState(() => _busy = true);
    var frei = _max - _docs.length;
    for (final f in ergebnis.files) {
      final pfad = f.path;
      if (pfad == null) continue;
      if (frei <= 0) { _melden('Höchstens $_max Dokumente — nicht alle hochgeladen'); break; }
      try {
        final r = await widget.apiService.massnahmeDokUpload(
          zuweisungId: widget.zuweisungId,
          userId: widget.userId,
          bereich: widget.bereich,
          korrespondenzId: widget.korrespondenzId,
          filePath: pfad,
          fileName: f.name,
        );
        // Der Grund gehört auf den Schirm — ein stiller Fehlschlag sieht aus
        // wie „ich habe danebengetippt".
        if (r['success'] != true) {
          _melden(r['message']?.toString() ?? 'Upload fehlgeschlagen: ${f.name}');
        }
      } finally {
        // ⚠️ Die Zwischendatei aus dem Cloud liegt ENTSCHLÜSSELT im temporären
        // Verzeichnis. Sie wird gelöscht, ob der Upload geklappt hat oder
        // nicht — ein Fehlschlag ist kein Grund, den Klartext liegen zu lassen.
        if (ausCloud != null) {
          try { final d = File(pfad); if (d.existsSync()) d.deleteSync(); } catch (_) {}
        }
      }
      frei--;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onChanged?.call();
    _laden1();
  }

  Future<void> _ansehen(Map<String, dynamic> d) async {
    setState(() => _busy = true);
    final resp = await widget.apiService
        .massnahmeDokDownload(mnZahl(d['id']) ?? 0, widget.userId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (resp.statusCode == 410) {
      _melden('Prüfsumme stimmt nicht — die Datei wurde verändert.');
      return;
    }
    if (resp.statusCode != 200) { _melden('Konnte nicht geladen werden (${resp.statusCode})'); return; }
    // Aus dem Arbeitsspeicher — die Datei berührt die Platte des Geräts nicht.
    await FileViewerDialog.showFromBytes(
        context, Uint8List.fromList(resp.bodyBytes), (d['datei_name'] ?? 'dokument').toString());
  }

  Future<void> _loeschen(Map<String, dynamic> d) async {
    final ja = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Dokument löschen?'),
        content: Text('„${d['datei_name']}" wird endgültig gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(c, true),
              child: const Text('Löschen', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ja != true) return;
    final r = await widget.apiService
        .massnahmeDokLoeschen(mnZahl(d['id']) ?? 0, widget.userId);
    if (r['success'] == true) { widget.onChanged?.call(); _laden1(); }
    else { _melden(r['message']?.toString() ?? 'Konnte nicht gelöscht werden'); }
  }

  String _groesse(dynamic b) {
    final n = mnZahl(b) ?? 0;
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} kB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: F.h(Colors.indigo, 50).withValues(alpha: 0.5),
        child: Row(children: [
          Expanded(child: Text(
            widget.hinweis ?? 'PDF, JPEG oder PNG, höchstens 20 MB.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.indigo, 700)))),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Vom Gerät',
            onPressed: _busy ? null : () => _hochladen(),
            icon: const Icon(Icons.upload_file, size: 20),
          ),
          CloudPickButton(
            memberId: widget.userId,
            apiService: widget.apiService,
            allowedExtensions: _erlaubt,
            enabled: !_busy,
            kompakt: true,
            onPicked: (r) => _hochladen(ausCloud: r),
          ),
        ]),
      ),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: _laden
            ? const Center(child: CircularProgressIndicator())
            : _docs.isEmpty
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Noch kein Dokument hinterlegt',
                        style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 600))),
                  ))
                : ListView.builder(
                    padding: EdgeInsets.all(widget.kompakt ? 4 : 10),
                    itemCount: _docs.length,
                    itemBuilder: (_, i) {
                      final d = _docs[i];
                      final name = (d['datei_name'] ?? '').toString();
                      final pdf = name.toLowerCase().endsWith('.pdf');
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: widget.kompakt,
                          leading: Icon(pdf ? Icons.picture_as_pdf : Icons.image_outlined,
                              color: F.h(Colors.indigo, 700)),
                          title: Text(name, style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                              '${_groesse(d['datei_groesse'])} · verschlüsselt gespeichert',
                              style: const TextStyle(fontSize: 11)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.visibility, size: 19),
                                tooltip: 'Ansehen', onPressed: _busy ? null : () => _ansehen(d)),
                            IconButton(
                                icon: const Icon(Icons.delete_outline, size: 19, color: Colors.red),
                                tooltip: 'Löschen', onPressed: _busy ? null : () => _loeschen(d)),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}

// ═══════════════════════════ Korrespondenz ═══════════════════════════

/// Schriftwechsel zu DIESER Zuweisung — getrennt von der Korrespondenz des
/// Arbeitsvermittlers, die am Vermittler hängt und nicht am Bescheid.
/// Betreff und Text liegen serverseitig verschlüsselt.
class _KorrespondenzTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int zuweisungId;
  final String? bearbeiter;
  final VoidCallback? onChanged;
  const _KorrespondenzTab({
    required this.apiService,
    required this.userId,
    required this.zuweisungId,
    this.bearbeiter,
    this.onChanged,
  });
  @override
  State<_KorrespondenzTab> createState() => _KorrespondenzTabState();
}

const _kRichtung = ['eingang', 'ausgang'];
const _kKontaktart = ['post', 'email', 'fax', 'telefon', 'persoenlich', 'online'];
const _kRichtungLabel = {'eingang': 'Eingang', 'ausgang': 'Ausgang'};
const _kKontaktLabel = {
  'post': 'Post', 'email': 'E-Mail', 'fax': 'Fax', 'telefon': 'Telefon',
  'persoenlich': 'Persönlich', 'online': 'Online',
};

class _KorrespondenzTabState extends State<_KorrespondenzTab> {
  List<Map<String, dynamic>> _eintraege = [];
  bool _laden = true;

  @override
  void initState() { super.initState(); _laden1(); }

  Future<void> _laden1() async {
    final r = await widget.apiService.massnahmeAction({
      'action': 'list_korrespondenz',
      'zuweisung_id': widget.zuweisungId,
      'user_id': widget.userId,
    });
    if (!mounted) return;
    setState(() {
      _eintraege = (r['success'] == true && r['korrespondenz'] is List)
          ? List<Map<String, dynamic>>.from(
              (r['korrespondenz'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
          : [];
      _laden = false;
    });
  }

  void _melden(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _bearbeiten([Map<String, dynamic>? vorhanden]) async {
    final betreff = TextEditingController(text: (vorhanden?['betreff'] ?? '').toString());
    final text = TextEditingController(text: (vorhanden?['text'] ?? '').toString());
    final datum = TextEditingController(
        text: massnahmeDatum(vorhanden?['datum'])?.toIso8601String().substring(0, 10) ??
            DateTime.now().toIso8601String().substring(0, 10));
    String richtung = vorhanden?['richtung']?.toString() ?? 'eingang';
    String kontakt = vorhanden?['kontaktart']?.toString() ?? 'post';

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c2, setD) => AlertDialog(
        title: Text(vorhanden == null ? 'Neuer Eintrag' : 'Eintrag bearbeiten',
            style: const TextStyle(fontSize: 16)),
        content: SizedBox(width: 420, child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: richtung,
                decoration: const InputDecoration(labelText: 'Richtung'),
                items: _kRichtung.map((r) => DropdownMenuItem(value: r,
                    child: Text(_kRichtungLabel[r]!, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) => setD(() => richtung = v ?? 'eingang'),
              )),
              const SizedBox(width: 8),
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: kontakt,
                decoration: const InputDecoration(labelText: 'Weg'),
                items: _kKontaktart.map((k) => DropdownMenuItem(value: k,
                    child: Text(_kKontaktLabel[k]!, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) => setD(() => kontakt = v ?? 'post'),
              )),
            ]),
            TextField(
              controller: datum, readOnly: true,
              decoration: const InputDecoration(
                  labelText: 'Datum', suffixIcon: Icon(Icons.calendar_today, size: 18)),
              onTap: () async {
                final jetzt = DateTime.now();
                final d = await showDatePicker(
                  context: c2,
                  initialDate: massnahmeDatum(datum.text) ?? jetzt,
                  firstDate: DateTime(jetzt.year - 5), lastDate: DateTime(jetzt.year + 5),
                );
                if (d != null) setD(() => datum.text = d.toIso8601String().substring(0, 10));
              },
            ),
            TextField(controller: betreff,
                decoration: const InputDecoration(labelText: 'Betreff')),
            TextField(controller: text, maxLines: 5,
                decoration: const InputDecoration(labelText: 'Text')),
          ]),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
        ],
      )),
    );

    if (ok == true) {
      final r = await widget.apiService.massnahmeAction({
        'action': 'save_korrespondenz',
        if (vorhanden != null) 'id': vorhanden['id'],
        'zuweisung_id': widget.zuweisungId,
        'user_id': widget.userId,
        'richtung': richtung,
        'kontaktart': kontakt,
        'datum': datum.text,
        'betreff': betreff.text.trim(),
        'text': text.text.trim(),
        if (widget.bearbeiter != null) 'erstellt_von': widget.bearbeiter,
      });
      if (r['success'] == true) { widget.onChanged?.call(); _laden1(); }
      else { _melden(r['message']?.toString() ?? 'Konnte nicht gespeichert werden'); }
    }
    for (final c in [betreff, text, datum]) { c.dispose(); }
  }

  Future<void> _loeschen(Map<String, dynamic> e) async {
    final ja = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: Text('Der Eintrag wird gelöscht'
            '${(mnZahl(e['anhaenge']) ?? 0) > 0 ? " — samt ${e['anhaenge']} Anhang/Anhängen" : ""}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(c, true),
              child: const Text('Löschen', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ja != true) return;
    final r = await widget.apiService.massnahmeAction({
      'action': 'delete_korrespondenz', 'id': e['id'], 'user_id': widget.userId,
    });
    if (r['success'] == true) { widget.onChanged?.call(); _laden1(); }
    else { _melden(r['message']?.toString() ?? 'Konnte nicht gelöscht werden'); }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy');
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: F.h(Colors.indigo, 50).withValues(alpha: 0.5),
        child: Row(children: [
          Expanded(child: Text('Schriftwechsel zu dieser Maßnahme',
              style: TextStyle(fontSize: 11, color: F.h(Colors.indigo, 700)))),
          ElevatedButton.icon(
            onPressed: () => _bearbeiten(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neuer Eintrag', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
                backgroundColor: F.h(Colors.indigo, 700), foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          ),
        ]),
      ),
      Expanded(
        child: _laden
            ? const Center(child: CircularProgressIndicator())
            : _eintraege.isEmpty
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Noch kein Schriftwechsel erfasst',
                        style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 600))),
                  ))
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _eintraege.length,
                    itemBuilder: (_, i) {
                      final e = _eintraege[i];
                      final eingang = e['richtung']?.toString() == 'eingang';
                      final d = massnahmeDatum(e['datum']);
                      final anh = mnZahl(e['anhaenge']) ?? 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ExpansionTile(
                          leading: Icon(eingang ? Icons.call_received : Icons.call_made,
                              size: 20, color: eingang ? F.h(Colors.green, 700) : F.h(Colors.blue, 700)),
                          title: Text(
                              (e['betreff'] ?? '').toString().isEmpty
                                  ? '(ohne Betreff)' : e['betreff'].toString(),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${d != null ? df.format(d) : "ohne Datum"} · '
                              '${_kRichtungLabel[e['richtung']?.toString()] ?? ""} · '
                              '${_kKontaktLabel[e['kontaktart']?.toString()] ?? ""}'
                              '${anh > 0 ? " · $anh Anhang" : ""}'
                              // Wer den Eintrag gemacht hat — ohne Verfasser
                              // ist ein Verlauf später nicht mehr zuzuordnen.
                              '${(e['erstellt_von'] ?? '').toString().isNotEmpty ? " · ${e['erstellt_von']}" : ""}',
                              style: const TextStyle(fontSize: 11)),
                          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                          children: [
                            if (e['lesbar'] == false)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: F.h(Colors.red, 50),
                                  border: Border.all(color: F.h(Colors.red, 200)),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                    '⚠ Text konnte nicht entschlüsselt werden — NICHT leer, '
                                    'bitte nicht überschreiben.',
                                    style: TextStyle(fontSize: 11, color: F.h(Colors.red, 900))),
                              ),
                            if ((e['text'] ?? '').toString().isNotEmpty)
                              Align(alignment: Alignment.centerLeft,
                                  child: SelectableText(e['text'].toString(),
                                      style: const TextStyle(fontSize: 12))),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 210,
                              child: MassnahmeDateiTab(
                                apiService: widget.apiService,
                                userId: widget.userId,
                                zuweisungId: widget.zuweisungId,
                                bereich: 'korrespondenz',
                                korrespondenzId: mnZahl(e['id']),
                                hinweis: 'Anhänge zu diesem Eintrag',
                                kompakt: true,
                                onChanged: () { widget.onChanged?.call(); _laden1(); },
                              ),
                            ),
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              TextButton.icon(
                                onPressed: () => _bearbeiten(e),
                                icon: const Icon(Icons.edit, size: 15),
                                label: const Text('Bearbeiten', style: TextStyle(fontSize: 12)),
                              ),
                              TextButton.icon(
                                onPressed: () => _loeschen(e),
                                icon: const Icon(Icons.delete_outline, size: 15, color: Colors.red),
                                label: const Text('Löschen',
                                    style: TextStyle(fontSize: 12, color: Colors.red)),
                              ),
                            ]),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}
