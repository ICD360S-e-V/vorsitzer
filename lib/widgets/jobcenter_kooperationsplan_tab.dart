import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';
import '../utils/app_farben.dart';
import '../utils/cloud_picker_helper.dart';
// ⚠️ KEIN `package:file_picker` hier. `FileType`, `PlatformFile` und
// `FilePickerResult` kommen aus diesem Helfer — er reicht sie unter
// eigenem Namen weiter, damit der Rückfall auf `file_selector` (macOS)
// nicht an jeder Aufrufstelle sichtbar wird. Wer die Bibliothek
// zusätzlich direkt importiert, bekommt `ambiguous_import`.
import '../utils/file_picker_helper.dart';
import '../utils/sicherer_dateiname.dart';
import 'file_viewer_dialog.dart';

/// Jobcenter ▸ Arbeitsvermittler ▸ „Kooperationsplan" (§ 15 SGB II).
///
/// Bis heute war das eine Dateiliste. Jetzt ist es ein Vorgang: wann der Plan
/// entstand, wann und wie er beim Mitglied ankam, was besprochen war, ob er das
/// enthält — und was dem Jobcenter geschrieben wird, wenn nicht.
///
/// Aufbau bewusst wie die Termine nebenan: Karten in einer Liste, ein Tippen
/// öffnet den Vorgang mit eigenen Registern. Zwei Sachen, die sich gleich
/// anfühlen, sollen auch gleich aussehen.
///
/// ⚠️ Eigene Datei, obwohl der Reiter im AV-Modal steckt: behorde_jobcenter.dart
/// hat über 13.000 Zeilen.
///
/// ⚠️ HIER STEHT KEIN KRITERIENKATALOG. Er kommt mit der Antwort des Servers
/// (`kriterien` + `gruppen`), samt Titel, Frage, Rechtsgrundlage und Schwere.
/// Eine zweite Liste in Dart wäre eine zweite Wahrheit — und weil der Server
/// entscheidet, welche Punkte für einen Plan und welche für einen
/// Verwaltungsakt gelten, verschwände ein nur einseitig bekannter Schlüssel
/// lautlos.

/// ⚠️ Die drei Schlüssel sind die ENUM-Werte der Spalte `zugang_weg`. Ein
/// vierter hier ohne den passenden auf dem Server würde von MariaDB
/// stillschweigend zu '' gekürzt.
const Map<String, String> kKoopZugangswege = {
  'online': 'Online-Portal',
  'postalisch': 'Per Post',
  'persoenlich': 'Persönlich übergeben',
};

const Map<String, IconData> kKoopZugangIcons = {
  'online': Icons.language,
  'postalisch': Icons.local_post_office,
  'persoenlich': Icons.person,
};

const Map<String, String> kKoopStatusLabel = {
  'offen': 'Noch nicht geprüft',
  'geprueft': 'Geprüft — in Ordnung',
  'beanstandet': 'Beanstandet',
  'erledigt': 'Erledigt',
};

String koopDatumDe(dynamic roh) {
  final s = (roh ?? '').toString();
  if (s.isEmpty) return '';
  final d = DateTime.tryParse(s);
  return d == null ? s : DateFormat('dd.MM.yyyy').format(d);
}

class JobcenterKooperationsplanTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int userAvId;

  const JobcenterKooperationsplanTab({
    super.key,
    required this.apiService,
    required this.userId,
    required this.userAvId,
  });

  @override
  State<JobcenterKooperationsplanTab> createState() => _KoopTabState();
}

class _KoopTabState extends State<JobcenterKooperationsplanTab> {
  List<Map<String, dynamic>> _plaene = [];
  Map<String, dynamic> _kontext = {};
  List<Map<String, dynamic>> _ohnePlan = [];
  bool _laden = true;

  @override
  void initState() {
    super.initState();
    _laden1();
  }

  Future<void> _laden1() async {
    if (mounted) setState(() => _laden = true);
    final liste = await widget.apiService.jcKoopListe(widget.userAvId);
    final kontext = await widget.apiService.jcKoopKontext(widget.userAvId);
    // Die Altbestände: Dateien, die vor dieser Funktion an der Zuordnung
    // hingen. Sie werden NICHT automatisch einem Plan zugeschlagen — welchem
    // denn? Sie bleiben sichtbar und lassen sich von Hand zuordnen.
    final alt = await widget.apiService.jcKooperationsplanDocsList(widget.userAvId, planId: 0);
    if (!mounted) return;
    setState(() {
      _plaene = (liste['plaene'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      _kontext = Map<String, dynamic>.from((kontext['kontext'] as Map?) ?? {});
      _ohnePlan = (alt['data'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      _laden = false;
    });
  }

  void _sagen(String m, {bool schlecht = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: schlecht ? Colors.red.shade700 : Colors.green.shade600,
    ));
  }

  Future<void> _neu({Map<String, dynamic>? bestehend}) async {
    final gespeichert = await showDialog<bool>(
      context: context,
      builder: (_) => _KoopPlanDialog(
        apiService: widget.apiService,
        userAvId: widget.userAvId,
        kontext: _kontext,
        bestehend: bestehend,
      ),
    );
    if (gespeichert == true) _laden1();
  }

  Future<void> _oeffnen(Map<String, dynamic> plan) async {
    final geaendert = await showDialog<bool>(
      context: context,
      builder: (_) => _KoopDetailModal(
        apiService: widget.apiService,
        userId: widget.userId,
        userAvId: widget.userAvId,
        planId: plan['id'] as int,
        kontext: _kontext,
      ),
    );
    if (geaendert == true) _laden1();
  }

  Future<void> _zuordnen(Map<String, dynamic> dok) async {
    if (_plaene.isEmpty) {
      _sagen('Erst einen Kooperationsplan anlegen', schlecht: true);
      return;
    }
    final ziel = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Zu welchem Plan gehört die Datei?', style: TextStyle(fontSize: 15)),
        children: _plaene
            .map((p) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, p['id'] as int),
                  child: Text('Plan vom ${koopDatumDe(p['erstellt_am'])}'
                      '${(p['ist_verwaltungsakt'] == true) ? " (Verwaltungsakt)" : ""}'),
                ))
            .toList(),
      ),
    );
    if (ziel == null) return;
    final r = await widget.apiService.jcKooperationsplanDocZuordnen(dok['id'] as int, ziel);
    if (r['success'] == true) {
      _sagen('Zugeordnet');
      _laden1();
    } else {
      _sagen(r['message']?.toString() ?? 'Nicht zugeordnet', schlecht: true);
    }
  }

  // ── Karte ────────────────────────────────────────────────────────────
  Widget _karte(Map<String, dynamic> p) {
    final status = (p['status'] ?? 'offen').toString();
    final maengel = (p['maengel'] as num?)?.toInt() ?? 0;
    final va = p['ist_verwaltungsakt'] == true;
    final weg = (p['zugang_weg'] ?? '').toString();
    final ohneGespraech = p['termin_id'] == null;

    final (Color farbe, IconData zeichen) = switch (status) {
      'beanstandet' => (Colors.red.shade700, Icons.report_problem_outlined),
      'geprueft' => (Colors.green.shade700, Icons.verified_outlined),
      'erledigt' => (Colors.grey.shade600, Icons.task_alt),
      _ => (Colors.orange.shade800, Icons.hourglass_empty),
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () => _oeffnen(p),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(va ? Icons.gavel : Icons.handshake, size: 18, color: F.h(Colors.purple, 700)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  va ? 'Verwaltungsakt vom ${koopDatumDe(p['erstellt_am'])}'
                     : 'Kooperationsplan vom ${koopDatumDe(p['erstellt_am'])}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: farbe.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(zeichen, size: 12, color: farbe),
                  const SizedBox(width: 3),
                  Text(
                    status == 'beanstandet' && maengel > 0
                        ? '$maengel Beanstandung${maengel == 1 ? "" : "en"}'
                        : (kKoopStatusLabel[status] ?? status),
                    style: TextStyle(fontSize: 10.5, color: farbe, fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 12, runSpacing: 4, children: [
              if (weg.isNotEmpty)
                _zeile(kKoopZugangIcons[weg] ?? Icons.help_outline,
                    'Zugang ${koopDatumDe(p['zugang_am'])} · ${kKoopZugangswege[weg] ?? weg}'),
              if ((p['zugang_fingiert_am'] ?? '').toString().isNotEmpty)
                _zeile(Icons.gavel, 'Zugangsfiktion ${koopDatumDe(p['zugang_fingiert_am'])}', farbe: Colors.blue),
              if ((p['fortschreibung_am'] ?? '').toString().isNotEmpty)
                _zeile(Icons.update, 'Fortschreibung ${koopDatumDe(p['fortschreibung_am'])}'),
              _zeile(Icons.attach_file, '${p['dokumente'] ?? 0} Dokument(e)'),
            ]),
            // ⚠️ Der wichtigste Hinweis der ganzen Karte: § 15 Abs. 2 Satz 1
            // SGB II verlangt, dass der Plan GEMEINSAM erstellt wird.
            if (ohneGespraech && !va) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.warning_amber, size: 13, color: F.h(Colors.orange, 800)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Keinem Gespräch zugeordnet — § 15 Abs. 2 Satz 1 SGB II verlangt '
                    'gemeinsame Erstellung.',
                    style: TextStyle(fontSize: 10.5, color: F.h(Colors.orange, 900)),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _zeile(IconData i, String t, {Color? farbe}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 12, color: farbe ?? F.h(Colors.grey, 600)),
        const SizedBox(width: 3),
        Text(t, style: TextStyle(fontSize: 11, color: farbe ?? F.h(Colors.grey, 700))),
      ]);

  @override
  Widget build(BuildContext context) {
    if (_laden) return const Center(child: CircularProgressIndicator());

    return Column(children: [
      Container(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Expanded(
            child: Text(
              _plaene.isEmpty ? 'Noch kein Kooperationsplan erfasst'
                              : '${_plaene.length} Kooperationsplan/-pläne',
              style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => _neu(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Plan erfassen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 34),
            ),
          ),
        ]),
      ),
      Expanded(
        child: ListView(children: [
          if (_plaene.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(children: [
                IconButton(
                  iconSize: 46,
                  color: Colors.purple.shade300,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Ersten Plan erfassen',
                  onPressed: () => _neu(),
                ),
                Text('Wann er entstand, wann er ankam — und ob er das enthält, was besprochen war',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: F.h(Colors.grey, 500), fontSize: 12)),
              ]),
            ),
          ..._plaene.map(_karte),

          // ── Altbestand ───────────────────────────────────────────────
          if (_ohnePlan.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('Dateien ohne Plan (${_ohnePlan.length})',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
              child: Text(
                'Vor dieser Funktion hochgeladen. Sie werden nicht von selbst einem Plan '
                'zugeschlagen — welchem, weiß nur der, der sie hochgeladen hat.',
                style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600)),
              ),
            ),
            ..._ohnePlan.map((d) => Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  color: F.h(Colors.grey, 50),
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.insert_drive_file, size: 18, color: F.h(Colors.grey, 600)),
                    title: Text((d['datei_name'] ?? '').toString(),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    trailing: TextButton(
                      onPressed: () => _zuordnen(d),
                      child: const Text('Zuordnen', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                )),
          ],
          const SizedBox(height: 16),
        ]),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════
//  Das Formular — anlegen und ändern
// ══════════════════════════════════════════════════════════════════════

class _KoopPlanDialog extends StatefulWidget {
  final ApiService apiService;
  final int userAvId;
  final Map<String, dynamic> kontext;
  final Map<String, dynamic>? bestehend;

  const _KoopPlanDialog({
    required this.apiService,
    required this.userAvId,
    required this.kontext,
    this.bestehend,
  });

  @override
  State<_KoopPlanDialog> createState() => _KoopPlanDialogState();
}

class _KoopPlanDialogState extends State<_KoopPlanDialog> {
  int? _terminId;
  DateTime? _erstellt, _zugang, _fortschreibung;
  String _weg = 'persoenlich';
  bool _va = false;
  final List<String> _berufe = [];
  final List<String> _massnahmen = [];
  final _notizC = TextEditingController();
  bool _speichert = false;

  List<Map<String, dynamic>> get _termine =>
      (widget.kontext['termine'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];

  @override
  void initState() {
    super.initState();
    final b = widget.bestehend;
    if (b != null) {
      _terminId = b['termin_id'] as int?;
      _erstellt = DateTime.tryParse((b['erstellt_am'] ?? '').toString());
      _zugang = DateTime.tryParse((b['zugang_am'] ?? '').toString());
      _fortschreibung = DateTime.tryParse((b['fortschreibung_am'] ?? '').toString());
      _weg = kKoopZugangswege.containsKey(b['zugang_weg']) ? b['zugang_weg'].toString() : 'persoenlich';
      _va = b['ist_verwaltungsakt'] == true;
      final v = b['vereinbart'];
      if (v is Map) {
        _berufe.addAll((v['berufe'] as List?)?.map((e) => e.toString()) ?? const []);
        _massnahmen.addAll((v['massnahmen'] as List?)?.map((e) => e.toString()) ?? const []);
      }
      _notizC.text = (b['notiz'] ?? '').toString();
    } else {
      // ⚠️ Der Regelfall, den der Vorsitzende beschrieben hat: der Plan
      // entsteht IM Gespräch und wird dort ausgehändigt. Also den jüngsten
      // Termin vorschlagen — bestätigen ist billiger als tippen.
      final t = _termine.isNotEmpty ? _termine.first : null;
      if (t != null) {
        _terminId = t['id'] as int?;
        _erstellt = DateTime.tryParse((t['datum'] ?? '').toString());
        _zugang = _erstellt;
      }
    }
  }

  @override
  void dispose() {
    _notizC.dispose();
    super.dispose();
  }

  /// Ein Termin gewählt = Datum und Weg folgen mit. Wer sie danach ändert,
  /// behält seine Änderung: die Vorbelegung greift nur auf leere Felder und
  /// beim Wechsel des Termins.
  void _terminGewaehlt(int? id) {
    setState(() {
      _terminId = id;
      final t = _termine.where((x) => x['id'] == id).firstOrNull;
      if (t != null) {
        final d = DateTime.tryParse((t['datum'] ?? '').toString());
        if (d != null) {
          _erstellt = d;
          _zugang = d;
          _weg = 'persoenlich';
        }
      }
    });
  }

  Future<void> _datum(DateTime? jetzt, ValueChanged<DateTime> gesetzt) async {
    final d = await showDatePicker(
      context: context,
      initialDate: jetzt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (d != null) setState(() => gesetzt(d));
  }

  Widget _datumsfeld(String label, DateTime? wert, ValueChanged<DateTime> gesetzt, {VoidCallback? loeschen}) {
    return InkWell(
      onTap: () => _datum(wert, gesetzt),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.calendar_today, size: 16),
          suffixIcon: (wert != null && loeschen != null)
              ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(loeschen))
              : null,
        ),
        child: Text(wert == null ? '—' : DateFormat('dd.MM.yyyy').format(wert),
            style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  Widget _chips(String titel, String hilfe, List<String> werte, List<String> vorschlaege, IconData ikone) {
    final c = TextEditingController();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(ikone, size: 15, color: F.h(Colors.purple, 700)),
        const SizedBox(width: 5),
        Text(titel, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: F.h(Colors.purple, 800))),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: Text(hilfe, style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600))),
      ),
      if (werte.isNotEmpty)
        Wrap(
          spacing: 6,
          runSpacing: 2,
          children: werte
              .map((w) => Chip(
                    label: Text(w, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => setState(() => werte.remove(w)),
                  ))
              .toList(),
        ),
      Row(children: [
        Expanded(
          child: TextField(
            controller: c,
            decoration: const InputDecoration(hintText: 'Hinzufügen …', isDense: true, border: OutlineInputBorder()),
            style: const TextStyle(fontSize: 13),
            onSubmitted: (v) {
              final t = v.trim();
              if (t.isNotEmpty && !werte.contains(t)) setState(() => werte.add(t));
              c.clear();
            },
          ),
        ),
      ]),
      if (vorschlaege.where((v) => !werte.contains(v)).isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 2,
            children: vorschlaege
                .where((v) => !werte.contains(v))
                .map((v) => ActionChip(
                      avatar: const Icon(Icons.add, size: 13),
                      label: Text(v, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => werte.add(v)),
                    ))
                .toList(),
          ),
        ),
    ]);
  }

  Future<void> _speichern() async {
    setState(() => _speichert = true);
    String iso(DateTime? d) => d == null ? '' : DateFormat('yyyy-MM-dd').format(d);
    final r = await widget.apiService.jcKoopSpeichern({
      if (widget.bestehend != null) 'id': widget.bestehend!['id'],
      'user_av_id': widget.userAvId,
      'termin_id': _terminId ?? 0,
      'erstellt_am': iso(_erstellt),
      'zugang_am': iso(_zugang),
      'zugang_weg': _weg,
      'fortschreibung_am': iso(_fortschreibung),
      'ist_verwaltungsakt': _va,
      'vereinbart': {'berufe': _berufe, 'massnahmen': _massnahmen},
      'notiz': _notizC.text.trim(),
    });
    if (!mounted) return;
    setState(() => _speichert = false);
    if (r['success'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r['message']?.toString() ?? 'Nicht gespeichert'),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vorschlaege = Map<String, dynamic>.from((widget.kontext['vorschlaege'] as Map?) ?? {});
    final verlauf = (widget.kontext['verlauf'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    final fenster = MediaQuery.of(context).size;
    final schmal = fenster.width < 600;

    return Dialog(
      insetPadding: EdgeInsets.all(schmal ? 6 : 24),
      child: SizedBox(
        width: schmal ? fenster.width * 0.98 : 620,
        height: fenster.height * 0.88,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.shade700,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            child: Row(children: [
              const Icon(Icons.handshake, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.bestehend == null ? 'Kooperationsplan erfassen' : 'Kooperationsplan ändern',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context, false),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Gespräch ────────────────────────────────────────────
                DropdownButtonFormField<int?>(
                  isExpanded: true,
                  initialValue: _terminId,
                  decoration: const InputDecoration(
                    labelText: 'In welchem Gespräch entstand er?',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.event, size: 18),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Ohne Gespräch — nur übersandt', style: TextStyle(fontSize: 12.5)),
                    ),
                    ..._termine.map((t) => DropdownMenuItem<int?>(
                          value: t['id'] as int?,
                          child: Text(
                            '${koopDatumDe(t['datum'])}${(t['zeit'] ?? '').toString().isNotEmpty ? " · ${t['zeit']}" : ""}'
                            ' · ${t['typ']}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        )),
                  ],
                  onChanged: _terminGewaehlt,
                ),
                if (_terminId == null && !_va)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: F.h(Colors.orange, 50),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: F.h(Colors.orange, 300)),
                      ),
                      child: Row(children: [
                        Icon(Icons.warning_amber, size: 14, color: F.h(Colors.orange, 800)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Ohne Gespräch ist der Plan nicht gemeinsam erstellt — § 15 Abs. 2 Satz 1 '
                            'SGB II. Die Prüfung stellt das später als Mangel fest.',
                            style: TextStyle(fontSize: 10.5, color: F.h(Colors.orange, 900)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                const SizedBox(height: 12),

                // ── Daten ───────────────────────────────────────────────
                Row(children: [
                  Expanded(child: _datumsfeld('Erstellt am', _erstellt, (d) => _erstellt = d)),
                  const SizedBox(width: 8),
                  Expanded(child: _datumsfeld('Zugang beim Klienten', _zugang, (d) => _zugang = d)),
                ]),
                const SizedBox(height: 10),

                Text('Wie kam er an?',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: F.h(Colors.purple, 800))),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: kKoopZugangswege.entries
                      .map((e) => ChoiceChip(
                            avatar: Icon(kKoopZugangIcons[e.key], size: 15),
                            label: Text(e.value, style: const TextStyle(fontSize: 12)),
                            selected: _weg == e.key,
                            onSelected: (_) => setState(() => _weg = e.key),
                          ))
                      .toList(),
                ),
                if (_weg == 'postalisch' && _zugang != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Zugangsfiktion § 37 Abs. 2 SGB X: '
                      '${DateFormat('dd.MM.yyyy').format(_zugang!.add(const Duration(days: 4)))}. '
                      'Kam der Brief nachweislich später, gilt das spätere Datum — Umschlag aufheben.',
                      style: TextStyle(fontSize: 10.5, color: F.h(Colors.blue, 900)),
                    ),
                  ),
                const SizedBox(height: 12),

                Row(children: [
                  Expanded(
                    child: _datumsfeld('Fortschreibung am', _fortschreibung, (d) => _fortschreibung = d,
                        loeschen: () => _fortschreibung = null),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Ist ein Verwaltungsakt', style: TextStyle(fontSize: 12)),
                        value: _va,
                        onChanged: (v) => setState(() => _va = v),
                      ),
                    ]),
                  ),
                ]),
                if (_va)
                  Text(
                    'Seit 01.07.2026 kann das Jobcenter Pflichten per Bescheid festlegen. Dann gelten '
                    'andere Maßstäbe: eine Rechtsfolgenbelehrung gehört hinein, eine '
                    'Rechtsbehelfsbelehrung ist Pflicht.',
                    style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 700)),
                  ),
                const Divider(height: 24),

                // ── Vereinbart ──────────────────────────────────────────
                Text('Was war besprochen?',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: F.h(Colors.purple, 900))),
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 8),
                  child: Text(
                    'Daran misst die Prüfung den Plan. Was hier steht, muss im Plan wörtlich '
                    'vorkommen — sonst wird es beanstandet.',
                    style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
                  ),
                ),
                _chips('Zielberufe', 'Die konkreten Tätigkeiten, nicht der Oberbegriff.', _berufe,
                    (vorschlaege['berufe'] as List?)?.map((e) => e.toString()).toList() ?? const [],
                    Icons.work_outline),
                const SizedBox(height: 12),
                _chips('Maßnahmen und Qualifikationen', 'Scheine, Kurse, Förderungen.', _massnahmen,
                    (vorschlaege['massnahmen'] as List?)?.map((e) => e.toString()).toList() ?? const [],
                    Icons.school_outlined),

                // ── Lesehilfe: was in den Terminen vermerkt ist ─────────
                if (verlauf.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Was in den Terminen vermerkt ist (${verlauf.length})',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      'Nur zum Nachlesen — daraus wird nichts automatisch übernommen.',
                      style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600)),
                    ),
                    children: verlauf
                        .map((v) => ListTile(
                              dense: true,
                              leading: Icon(Icons.forum_outlined, size: 15, color: F.h(Colors.indigo, 500)),
                              title: Text(koopDatumDe(v['datum']), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                              subtitle: Text((v['notiz'] ?? '').toString(), style: const TextStyle(fontSize: 11.5)),
                            ))
                        .toList(),
                  ),
                ],

                const SizedBox(height: 12),
                TextField(
                  controller: _notizC,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notiz',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note_alt, size: 18),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: F.h(Colors.grey, 300)))),
            child: Row(children: [
              const Spacer(),
              TextButton(
                onPressed: _speichert ? null : () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _speichert ? null : _speichern,
                icon: _speichert
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, size: 16),
                label: const Text('Speichern'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  Der Vorgang — Details · Dokument · Prüfung · Schreiben
// ══════════════════════════════════════════════════════════════════════

class _KoopDetailModal extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int userAvId;
  final int planId;
  final Map<String, dynamic> kontext;

  const _KoopDetailModal({
    required this.apiService,
    required this.userId,
    required this.userAvId,
    required this.planId,
    required this.kontext,
  });

  @override
  State<_KoopDetailModal> createState() => _KoopDetailModalState();
}

class _KoopDetailModalState extends State<_KoopDetailModal> with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _geaendert = false;

  Map<String, dynamic> _plan = {};
  List<Map<String, dynamic>> _docs = [];
  bool _laden = true, _arbeitet = false;

  /// Der Kriterienkatalog — kommt vom Server, steht nie in Dart.
  List<Map<String, dynamic>> _kriterien = [];
  Map<String, String> _gruppen = {};

  /// Der Stand je Kriterium. Was hier steht, geht beim Speichern hinaus.
  final Map<String, Map<String, dynamic>> _stand = {};
  String _pruefHinweis = '';
  String _quelle = '';

  List<Map<String, dynamic>> _absaetze = [];
  List<Map<String, dynamic>> _unvollstaendig = [];
  final _freitextC = TextEditingController();
  final _faxC = TextEditingController();
  int _fristTage = 14;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _laden1();
  }

  @override
  void dispose() {
    _tab.dispose();
    _freitextC.dispose();
    _faxC.dispose();
    super.dispose();
  }

  Future<void> _laden1() async {
    if (mounted) setState(() => _laden = true);
    final liste = await widget.apiService.jcKoopListe(widget.userAvId);
    final plaene = (liste['plaene'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    final docs = await widget.apiService.jcKooperationsplanDocsList(widget.userAvId, planId: widget.planId);
    final pruef = await widget.apiService.jcKoopPruefungLesen(widget.planId);
    if (!mounted) return;
    setState(() {
      _plan = plaene.where((p) => p['id'] == widget.planId).firstOrNull ?? {};
      _docs = (docs['data'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      _kriterien = (pruef['kriterien'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      _gruppen = Map<String, String>.from((pruef['gruppen'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {});
      _stand
        ..clear()
        ..addAll(((pruef['stand'] as Map?) ?? {})
            .map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map))));
      _laden = false;
    });
    // Die Faxnummer des Amtes nur VORSCHLAGEN. Wer im Feld eine eigene
    // eingetragen hat, meinte sie so.
    if (_faxC.text.trim().isEmpty) {
      _faxC.text = ((widget.kontext['jobcenter'] as Map?)?['fax'] ?? '').toString();
    }
  }

  void _sagen(String m, {bool schlecht = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: schlecht ? Colors.red.shade700 : Colors.green.shade600,
      duration: const Duration(seconds: 5),
    ));
  }

  // ── PDF und Fax ─────────────────────────────────────────────────────

  Future<void> _briefAnsehen() async {
    setState(() => _arbeitet = true);
    final r = await widget.apiService.jcKoopBriefPdf(widget.planId,
        freitext: _freitextC.text.trim(), fristTage: _fristTage);
    if (!mounted) return;
    setState(() => _arbeitet = false);
    if (r['success'] != true || (r['pdf_base64'] ?? '').toString().isEmpty) {
      _sagen(r['message']?.toString() ?? 'Der Brief konnte nicht erzeugt werden', schlecht: true);
      return;
    }
    final bytes = base64Decode(r['pdf_base64'].toString());
    final ordner = await getTemporaryDirectory();
    final datei = sichereDatei(ordner, r['filename'] ?? 'Brief.pdf');
    await datei.writeAsBytes(bytes);
    if (!mounted) return;
    await FileViewerDialog.show(context, datei.path, (r['filename'] ?? 'Brief.pdf').toString());
  }

  /// ⚠️ Ein Fax an eine Behörde geht sofort hinaus und ist nicht zurückholbar.
  /// Deshalb wird hier gefragt — und die Frage nennt beim Namen, was schiefgehen
  /// kann: eine Vollmacht, die nicht trägt, und eine Widerspruchsfrist, die
  /// von einem Änderungsschreiben NICHT gewahrt wird.
  Future<void> _faxen() async {
    final nummer = _faxC.text.trim();
    if (nummer.isEmpty) {
      _sagen('Keine Faxnummer eingetragen', schlecht: true);
      return;
    }
    final vm = widget.kontext['vollmacht'];
    final deckt = vm is Map && vm['deckt'] == true;
    final va = _plan['ist_verwaltungsakt'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fax jetzt senden?', style: TextStyle(fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Der Brief geht als Fax an $nummer — an eine Behörde, sofort und nicht '
              'zurückholbar.', style: const TextStyle(fontSize: 13)),
          if (!deckt) ...[
            const SizedBox(height: 10),
            Text(
              '⚠️ Keine tragende Vollmacht: der Brief geht in der Person des Mitglieds '
              'hinaus und braucht dessen Unterschrift. Ungezeichnet gefaxt ist er für das '
              'Jobcenter wenig wert.',
              style: TextStyle(fontSize: 12, color: F.h(Colors.orange, 900), fontWeight: FontWeight.w600),
            ),
          ],
          if (va) ...[
            const SizedBox(height: 10),
            Text(
              '⚠️ Das hier ist ein Verwaltungsakt. Dieses Schreiben ist KEIN Widerspruch — '
              'die Widerspruchsfrist läuft weiter. Wer sie wahren will, legt zusätzlich '
              'Widerspruch ein.',
              style: TextStyle(fontSize: 12, color: F.h(Colors.red, 800), fontWeight: FontWeight.w600),
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fax senden'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _arbeitet = true);
    final r = await widget.apiService.jcKoopFaxSenden(widget.planId, nummer,
        freitext: _freitextC.text.trim(), fristTage: _fristTage);
    if (!mounted) return;
    setState(() => _arbeitet = false);
    if (r['success'] == true) {
      _geaendert = true;
      _sagen('Fax beauftragt. Der Sendebericht kommt von sipgate.');
    } else {
      _sagen(r['message']?.toString() ?? 'Das Fax wurde nicht angenommen', schlecht: true);
    }
  }

  // ══════════════════════════════════════════════════════════════════
  //  Register 1 — Details
  // ══════════════════════════════════════════════════════════════════
  Widget _detailsTab() {
    final weg = (_plan['zugang_weg'] ?? '').toString();
    final va = _plan['ist_verwaltungsakt'] == true;
    final vereinbart = Map<String, dynamic>.from((_plan['vereinbart'] as Map?) ?? {});
    final berufe = (vereinbart['berufe'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final massnahmen = (vereinbart['massnahmen'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];

    Widget zeile(IconData i, String label, String wert, {Color? farbe}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, size: 15, color: farbe ?? F.h(Colors.grey, 600)),
            const SizedBox(width: 8),
            SizedBox(width: 150, child: Text(label, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)))),
            Expanded(
              child: Text(wert.isEmpty ? '—' : wert,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: farbe)),
            ),
          ]),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(va ? 'Verwaltungsakt' : 'Kooperationsplan (§ 15 SGB II)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: F.h(Colors.purple, 900))),
          ),
          TextButton.icon(
            icon: const Icon(Icons.edit, size: 15),
            label: const Text('Bearbeiten', style: TextStyle(fontSize: 12)),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => _KoopPlanDialog(
                  apiService: widget.apiService,
                  userAvId: widget.userAvId,
                  kontext: widget.kontext,
                  bestehend: _plan,
                ),
              );
              if (ok == true) {
                _geaendert = true;
                _laden1();
              }
            },
          ),
        ]),
        const Divider(),
        zeile(Icons.event_note, 'Erstellt am', koopDatumDe(_plan['erstellt_am'])),
        zeile(kKoopZugangIcons[weg] ?? Icons.help_outline, 'Zugang beim Klienten',
            '${koopDatumDe(_plan['zugang_am'])}${weg.isEmpty ? "" : " · ${kKoopZugangswege[weg] ?? weg}"}'),
        if ((_plan['zugang_fingiert_am'] ?? '').toString().isNotEmpty)
          zeile(Icons.gavel, 'Zugangsfiktion', '${koopDatumDe(_plan['zugang_fingiert_am'])} (§ 37 Abs. 2 SGB X)',
              farbe: F.h(Colors.blue, 800)),
        zeile(Icons.update, 'Fortschreibung', koopDatumDe(_plan['fortschreibung_am'])),
        _plan['termin_id'] == null
            ? zeile(Icons.warning_amber, 'Gespräch',
                va ? '—' : 'Keinem Gespräch zugeordnet — § 15 Abs. 2 Satz 1 SGB II',
                farbe: va ? null : F.h(Colors.orange, 900))
            : zeile(Icons.event_available, 'Gespräch am', koopDatumDe(_plan['termin_datum']),
                farbe: F.h(Colors.green, 800)),
        const Divider(height: 22),
        Text('Was besprochen war',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.purple, 900))),
        const SizedBox(height: 6),
        if (berufe.isEmpty && massnahmen.isEmpty)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: F.h(Colors.orange, 50),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: F.h(Colors.orange, 300)),
            ),
            child: Text(
              'Nichts eingetragen. Ohne das kann die Prüfung nicht feststellen, ob der Plan '
              'enthält, was besprochen wurde — genau der Punkt, um den es geht.',
              style: TextStyle(fontSize: 11.5, color: F.h(Colors.orange, 900)),
            ),
          ),
        if (berufe.isNotEmpty) ...[
          Text('Zielberufe', style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700))),
          Wrap(spacing: 6, children: berufe.map((b) => Chip(
                label: Text(b, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
              )).toList()),
        ],
        if (massnahmen.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Maßnahmen', style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700))),
          Wrap(spacing: 6, children: massnahmen.map((b) => Chip(
                label: Text(b, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
              )).toList()),
        ],
        if ((_plan['notiz'] ?? '').toString().isNotEmpty) ...[
          const Divider(height: 22),
          Text('Notiz', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
          Text(_plan['notiz'].toString(), style: const TextStyle(fontSize: 12.5)),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  Register 2 — Dokument
  // ══════════════════════════════════════════════════════════════════
  Future<void> _hochladen({FilePickerResult? ausCloud}) async {
    final ergebnis = ausCloud ??
        await FilePickerHelper.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf', 'jpg', 'jpeg'],
          allowMultiple: true,
        );
    if (ergebnis == null || ergebnis.files.isEmpty) return;
    setState(() => _arbeitet = true);
    for (final f in ergebnis.files.where((x) => x.path != null)) {
      final r = await widget.apiService.jcKooperationsplanDocUpload(
        userAvId: widget.userAvId,
        filePath: f.path!,
        fileName: f.name,
        planId: widget.planId,
      );
      if (r['success'] != true) {
        _sagen(r['message']?.toString() ?? 'Upload fehlgeschlagen: ${f.name}', schlecht: true);
      } else if ((r['text_quelle'] ?? '') == 'keiner') {
        // ⚠️ Kein Text heisst: die Prüfung kann zum Inhalt nichts sagen. Das
        // muss dastehen, sonst hält man eine leere Prüfung für ein "alles gut".
        _sagen('${f.name} gespeichert, aber es liess sich kein Text lesen — '
            'inhaltliche Punkte bleiben offen.');
      }
    }
    if (!mounted) return;
    _geaendert = true;
    setState(() => _arbeitet = false);
    _laden1();
  }

  Future<File?> _holen(Map<String, dynamic> d) async {
    final antwort = await widget.apiService.jcKooperationsplanDocDownload(d['id'] as int);
    if (antwort.statusCode != 200) return null;
    final ordner = await getTemporaryDirectory();
    final datei = sichereDatei(ordner, d['datei_name']);
    await datei.writeAsBytes(antwort.bodyBytes);
    return datei;
  }

  Widget _dokumenteTab() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Icon(Icons.lock, size: 14, color: F.h(Colors.green, 700)),
          const SizedBox(width: 4),
          Expanded(
            child: Text('${_docs.length} Dokument(e) · verschlüsselt',
                style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600))),
          ),
          CloudPickButton(
            memberId: widget.userId,
            apiService: widget.apiService,
            allowedExtensions: const ['pdf', 'jpg', 'jpeg'],
            kompakt: true,
            enabled: !_arbeitet,
            onPicked: (r) => _hochladen(ausCloud: r),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _arbeitet ? null : () => _hochladen(),
            icon: _arbeitet
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_file, size: 14),
            label: const Text('Hochladen'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 32),
            ),
          ),
        ]),
      ),
      Expanded(
        child: _docs.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Noch kein Plan hochgeladen. Ohne ihn prüft die Maschine nur die Daten, '
                      'nicht den Inhalt.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: F.h(Colors.grey, 500), fontSize: 12.5)),
                ),
              )
            : ListView.builder(
                itemCount: _docs.length,
                itemBuilder: (_, i) {
                  final d = _docs[i];
                  final quelle = (d['text_quelle'] ?? 'keiner').toString();
                  final zeichen = (d['text_zeichen'] as num?)?.toInt() ?? 0;
                  final (String txt, Color farbe) = switch (quelle) {
                    'pdf' => ('Text aus der Datei gelesen ($zeichen Zeichen) — sicher', Colors.green.shade700),
                    'ocr' => ('Aus dem Bild erkannt ($zeichen Zeichen) — unsicher', Colors.orange.shade800),
                    _ => ('Kein Text gelesen — Inhalt nicht prüfbar', Colors.red.shade700),
                  };
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        (d['datei_name'] ?? '').toString().toLowerCase().endsWith('.pdf')
                            ? Icons.picture_as_pdf
                            : Icons.image,
                        color: F.h(Colors.purple, 700),
                      ),
                      title: Text((d['datei_name'] ?? '').toString(),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(txt, style: TextStyle(fontSize: 11, color: farbe)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (quelle == 'keiner')
                          IconButton(
                            icon: Icon(Icons.find_in_page_outlined, size: 18, color: F.h(Colors.blue, 700)),
                            tooltip: 'Text nachlesen',
                            onPressed: () async {
                              setState(() => _arbeitet = true);
                              final r = await widget.apiService.jcKooperationsplanDocTextNachlesen(d['id'] as int);
                              if (!mounted) return;
                              setState(() => _arbeitet = false);
                              _sagen(r['success'] == true
                                  ? 'Gelesen: ${r['text_zeichen']} Zeichen (${r['text_quelle']})'
                                  : 'Kein Text lesbar', schlecht: r['success'] != true);
                              _laden1();
                            },
                          ),
                        IconButton(
                          icon: Icon(Icons.visibility, size: 18, color: F.h(Colors.indigo, 600)),
                          tooltip: 'Ansehen',
                          onPressed: () async {
                            final f = await _holen(d);
                            if (f != null && mounted) {
                              await FileViewerDialog.show(context, f.path, (d['datei_name'] ?? '').toString());
                            }
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.open_in_new, size: 18, color: F.h(Colors.green, 700)),
                          tooltip: 'Öffnen',
                          onPressed: () async {
                            final f = await _holen(d);
                            if (f != null) await OpenFilex.open(f.path);
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.link_off, size: 18, color: F.h(Colors.grey, 600)),
                          tooltip: 'Vom Plan lösen',
                          onPressed: () async {
                            await widget.apiService.jcKooperationsplanDocZuordnen(d['id'] as int, 0);
                            _geaendert = true;
                            _laden1();
                          },
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════
  //  Register 3 — Prüfung
  // ══════════════════════════════════════════════════════════════════

  /// Holt den Vorschlag der Maschine und trägt ihn ein.
  ///
  /// ⚠️ Eine UNSICHERE Feststellung wird NICHT als Mangel vorgehakt. Sie
  /// landet auf „offen" und der Befund steht daneben. Der Grund ist derselbe
  /// wie bei den Blutwerten: aus einem Bild gelesener Text liefert plausible
  /// falsche Wörter, und ein vorgehakter Mangel wird zur Beanstandung in einem
  /// Brief an eine Behörde, ohne dass ihn jemand gelesen hat.
  Future<void> _vorpruefen() async {
    setState(() => _arbeitet = true);
    final r = await widget.apiService.jcKoopPruefen(widget.planId);
    if (!mounted) return;
    setState(() => _arbeitet = false);
    if (r['success'] != true) {
      _sagen(r['message']?.toString() ?? 'Prüfung fehlgeschlagen', schlecht: true);
      return;
    }
    final vorschlag = ((r['vorschlag'] as Map?) ?? {})
        .map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
    setState(() {
      _kriterien = (r['kriterien'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? _kriterien;
      _gruppen = Map<String, String>.from(
          (r['gruppen'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? _gruppen);
      _pruefHinweis = (r['hinweis'] ?? '').toString();
      _quelle = (r['quelle'] ?? '').toString();
      vorschlag.forEach((id, s) {
        final unsicher = s['sicher'] != true;
        final stand = (s['stand'] ?? 'unklar').toString();
        _stand[id] = {
          'id': id,
          'stand': (unsicher && stand == 'nicht_erfuellt') ? 'unklar' : stand,
          'quelle': 'auto',
          'sicher': s['sicher'] == true,
          'befund': (s['befund'] ?? '').toString(),
          'daten': s['daten'] ?? const {},
          if (unsicher && stand == 'nicht_erfuellt') 'vermutet': 'nicht_erfuellt',
        };
      });
    });
    final maengel = _stand.values.where((s) => s['stand'] == 'nicht_erfuellt').length;
    _sagen(r['gelesen'] == true
        ? '$maengel Beanstandung(en) vorgeschlagen — bitte durchsehen und bestätigen.'
        : 'Kein Text im Dokument — nur die Daten konnten geprüft werden.');
  }

  Future<void> _pruefungSpeichern() async {
    setState(() => _arbeitet = true);
    final r = await widget.apiService.jcKoopPruefungSpeichern(widget.planId, _stand);
    if (!mounted) return;
    setState(() => _arbeitet = false);
    if (r['success'] == true) {
      _geaendert = true;
      _sagen('Prüfung gespeichert — ${r['maengel']} Beanstandung(en)');
      _laden1();
    } else {
      _sagen(r['message']?.toString() ?? 'Nicht gespeichert', schlecht: true);
    }
  }

  Widget _standWahl(String id) {
    const werte = ['erfuellt', 'unklar', 'nicht_erfuellt'];
    const namen = {'erfuellt': 'Erfüllt', 'unklar': 'Offen', 'nicht_erfuellt': 'Mangel'};
    const farben = {'erfuellt': Colors.green, 'unklar': Colors.grey, 'nicht_erfuellt': Colors.red};
    final aktuell = (_stand[id]?['stand'] ?? 'unklar').toString();
    return Wrap(
      spacing: 4,
      children: werte.map((w) {
        final an = aktuell == w;
        return ChoiceChip(
          label: Text(namen[w]!, style: const TextStyle(fontSize: 11)),
          selected: an,
          visualDensity: VisualDensity.compact,
          selectedColor: (farben[w] as MaterialColor).shade100,
          onSelected: (_) => setState(() {
            final alt = _stand[id] ?? {'id': id};
            // ⚠️ Sobald ein Mensch anfasst, ist die Quelle "hand". Genau daran
            // erkennt der Brief später, worauf sich jemand festgelegt hat.
            _stand[id] = {...alt, 'id': id, 'stand': w, 'quelle': 'hand'};
          }),
        );
      }).toList(),
    );
  }

  Widget _pruefungTab() {
    if (_kriterien.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Der Prüfkatalog kommt vom Server.',
                style: TextStyle(color: F.h(Colors.grey, 600), fontSize: 12.5)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _arbeitet ? null : _vorpruefen,
              icon: const Icon(Icons.fact_check, size: 16),
              label: const Text('Automatisch vorprüfen'),
            ),
          ]),
        ),
      );
    }

    final nachGruppe = <String, List<Map<String, dynamic>>>{};
    for (final k in _kriterien) {
      nachGruppe.putIfAbsent((k['gruppe'] ?? 'sonstige').toString(), () => []).add(k);
    }
    final maengel = _stand.values.where((s) => s['stand'] == 'nicht_erfuellt').length;
    final offen = _kriterien.where((k) => (_stand[k['id']]?['stand'] ?? 'unklar') == 'unklar').length;

    return Column(children: [
      Container(
        padding: const EdgeInsets.all(10),
        color: F.h(Colors.grey, 50),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_kriterien.length} Kriterien · $maengel Mangel/Mängel · $offen offen',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              if (_quelle.isNotEmpty)
                Text(
                  _quelle == 'pdf'
                      ? 'Text aus der Datei — Feststellungen zum Wortlaut sind belastbar.'
                      : _quelle == 'ocr'
                          ? 'Text aus einer Bilderkennung — unsichere Punkte bleiben offen.'
                          : 'Kein Text — nur die Daten wurden geprüft.',
                  style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 700)),
                ),
            ]),
          ),
          TextButton.icon(
            onPressed: _arbeitet ? null : _vorpruefen,
            icon: _arbeitet
                ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.fact_check, size: 15),
            label: const Text('Vorprüfen', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _arbeitet ? null : _pruefungSpeichern,
            icon: const Icon(Icons.save, size: 15),
            label: const Text('Speichern', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 32),
            ),
          ),
        ]),
      ),
      if (_pruefHinweis.isNotEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: F.h(Colors.orange, 50),
          child: Text(_pruefHinweis, style: TextStyle(fontSize: 11, color: F.h(Colors.orange, 900))),
        ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 20),
          children: nachGruppe.entries.expand((eintrag) {
            return [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text(_gruppen[eintrag.key] ?? eintrag.key,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: F.h(Colors.purple, 900))),
              ),
              ...eintrag.value.map((k) {
                final id = (k['id'] ?? '').toString();
                final s = _stand[id];
                final befund = (s?['befund'] ?? '').toString();
                final nurMaschine = (s?['quelle'] ?? '') == 'auto';
                final vermutet = (s?['vermutet'] ?? '').toString();
                final schwere = (k['schwere'] ?? 'hinweis').toString();
                final schwereFarbe = switch (schwere) {
                  'hoch' => Colors.red.shade700,
                  'mittel' => Colors.orange.shade800,
                  _ => Colors.grey.shade600,
                };
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text((k['titel'] ?? '').toString(),
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: schwereFarbe.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(schwere, style: TextStyle(fontSize: 9.5, color: schwereFarbe)),
                        ),
                      ]),
                      Text((k['frage'] ?? '').toString(),
                          style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700))),
                      if ((k['grundlage'] ?? '').toString().isNotEmpty)
                        Text((k['grundlage'] ?? '').toString(),
                            style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: F.h(Colors.indigo, 600))),
                      const SizedBox(height: 6),
                      _standWahl(id),
                      if (befund.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(nurMaschine ? Icons.smart_toy_outlined : Icons.person_outline,
                              size: 12, color: F.h(Colors.grey, 600)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(befund, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 800))),
                          ),
                        ]),
                      ],
                      // ⚠️ Der wichtigste Hinweis der Seite: die Maschine hält
                      // das für einen Mangel, traut sich aber nicht.
                      if (vermutet == 'nicht_erfuellt' && (s?['stand'] ?? '') == 'unklar')
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Vermuteter Mangel — aus unsicherem Text gelesen und deshalb nicht '
                            'vorgehakt. Bitte im Dokument nachsehen.',
                            style: TextStyle(fontSize: 10.5, color: F.h(Colors.orange, 900), fontWeight: FontWeight.w600),
                          ),
                        ),
                    ]),
                  ),
                );
              }),
            ];
          }).toList(),
        ),
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════
  //  Register 4 — Schreiben
  // ══════════════════════════════════════════════════════════════════
  Future<void> _beanstandungenHolen() async {
    setState(() => _arbeitet = true);
    final r = await widget.apiService.jcKoopBeanstandungen(widget.planId);
    if (!mounted) return;
    setState(() {
      _arbeitet = false;
      _absaetze = (r['absaetze'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      _unvollstaendig =
          (r['unvollstaendig'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    });
  }

  Widget _schreibenTab() {
    final vm = widget.kontext['vollmacht'];
    final deckt = vm is Map && vm['deckt'] == true;
    final fax = ((widget.kontext['jobcenter'] as Map?)?['fax'] ?? '').toString();

    return ListView(padding: const EdgeInsets.all(12), children: [
      // ── Worauf sich der Brief berufen kann ────────────────────────
      Card(
        color: vm is Map
            ? (deckt ? F.h(Colors.indigo, 50) : F.h(Colors.orange, 50))
            : F.h(Colors.grey, 100),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.assignment_ind, size: 16,
                  color: vm is Map ? (deckt ? F.h(Colors.indigo, 700) : F.h(Colors.orange, 800)) : F.h(Colors.grey, 600)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  vm is Map ? 'Vollmacht #${vm['id']} vom ${koopDatumDe(vm['valid_from'])}' : 'Keine gültige Jobcenter-Vollmacht',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ]),
            const SizedBox(height: 3),
            Text(
              vm is! Map
                  ? 'Das Schreiben geht in der Person des Mitglieds hinaus und braucht dessen Unterschrift.'
                  : switch ((vm['nachweis'] ?? 'status').toString()) {
                      'uebermittelt' =>
                        'Dem Jobcenter am ${koopDatumDe(vm['zugang_am'])} übersandt — sie wird nicht erneut beigefügt.',
                      'unterschrift' =>
                        'Unterschrieben hinterlegt. Der Nachweis wird auf Verlangen angeboten (§ 13 Abs. 1 Satz 3 SGB X).',
                      _ => 'Noch kein Zugangsnachweis. Der Brief behauptet deshalb nicht, sie liege dem Amt vor.',
                    },
              style: const TextStyle(fontSize: 10.5),
            ),
            if (vm is Map && !deckt)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '⚠️ Sie umfasst weder „Eingliederungsvereinbarung ändern" noch „Erklärungen zur '
                  'Mitwirkung" — für DIESES Schreiben trägt sie also nicht.',
                  style: TextStyle(fontSize: 10.5, color: F.h(Colors.orange, 900), fontWeight: FontWeight.w500),
                ),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 10),

      Row(children: [
        Expanded(
          child: Text('Beanstandungen',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: F.h(Colors.purple, 900))),
        ),
        TextButton.icon(
          onPressed: _arbeitet ? null : _beanstandungenHolen,
          icon: const Icon(Icons.refresh, size: 15),
          label: const Text('Zusammenstellen', style: TextStyle(fontSize: 12)),
        ),
      ]),
      Text(
        'Aus den Punkten, die als Mangel bestätigt sind. Was auf „offen" steht, kommt nicht in '
        'den Brief — eine Beanstandung, die niemand gelesen hat, gehört nicht zu einer Behörde.',
        style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
      ),
      const SizedBox(height: 8),

      if (_absaetze.isEmpty && _unvollstaendig.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text('Noch nichts zusammengestellt.',
                style: TextStyle(color: F.h(Colors.grey, 500), fontSize: 12.5)),
          ),
        ),

      ..._absaetze.map((a) => Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text((a['titel'] ?? '').toString(),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  if (a['nur_maschine'] == true)
                    Tooltip(
                      message: 'Nur von der Maschine gesetzt, nicht von Hand bestätigt',
                      child: Icon(Icons.smart_toy_outlined, size: 14, color: F.h(Colors.orange, 800)),
                    ),
                ]),
                if ((a['grundlage'] ?? '').toString().isNotEmpty)
                  Text((a['grundlage'] ?? '').toString(),
                      style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: F.h(Colors.indigo, 600))),
                const SizedBox(height: 5),
                Text((a['text'] ?? '').toString(), style: const TextStyle(fontSize: 12, height: 1.35)),
              ]),
            ),
          )),

      if (_unvollstaendig.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: F.h(Colors.orange, 50),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: F.h(Colors.orange, 300)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_unvollstaendig.length} Punkt(e) brauchen Handarbeit',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.orange, 900))),
            const SizedBox(height: 3),
            Text(
              'Für diese Beanstandungen fehlt eine Angabe, die der Satz nennen müsste. Sie bleiben '
              'draußen — ein Brief mit einer Lücke darin ginge sonst an ein Amt.',
              style: TextStyle(fontSize: 10.5, color: F.h(Colors.orange, 900)),
            ),
            const SizedBox(height: 4),
            ..._unvollstaendig.map((u) => Text('· ${u['titel']}',
                style: TextStyle(fontSize: 11, color: F.h(Colors.orange, 900)))),
          ]),
        ),
      ],

      const Divider(height: 24),

      // ── Was noch in den Brief soll ────────────────────────────────
      TextField(
        controller: _freitextC,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Eigener Zusatz (steht vor der Bitte um Änderung)',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 12.5),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Text('Rückmeldung binnen', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 800))),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: _fristTage,
          isDense: true,
          items: const [7, 14, 21, 30]
              .map((t) => DropdownMenuItem(value: t, child: Text('$t Tagen', style: const TextStyle(fontSize: 12.5))))
              .toList(),
          onChanged: (v) => setState(() => _fristTage = v ?? 14),
        ),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: _faxC,
        decoration: InputDecoration(
          labelText: 'Faxnummer des Jobcenters',
          isDense: true,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.fax, size: 18),
          helperText: fax.isEmpty
              ? 'Für dieses Amt ist keine hinterlegt — mit Vorwahl eintragen, z. B. +4973180159737.'
              : 'Aus den Stammdaten des zuständigen Amtes.',
          helperMaxLines: 2,
        ),
        style: const TextStyle(fontSize: 13),
      ),

      // ⚠️ Der gefährlichste Fall der ganzen Seite: bei einem Verwaltungsakt
      // wahrt ein Änderungsschreiben KEINE Frist. Das muss dastehen, bevor
      // jemand auf „Fax" tippt und sich in Sicherheit wiegt.
      if (_plan['ist_verwaltungsakt'] == true) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: F.h(Colors.red, 50),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: F.h(Colors.red, 300)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.gavel, size: 16, color: F.h(Colors.red, 800)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Dieser Vorgang ist ein Verwaltungsakt. Das Änderungsschreiben ist KEIN '
                'Widerspruch und wahrt keine Frist. Wer die Frist wahren will, legt '
                'zusätzlich Widerspruch ein.',
                style: TextStyle(fontSize: 11.5, color: F.h(Colors.red, 900), fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ],

      const SizedBox(height: 12),
      Row(children: [
        TextButton.icon(
          onPressed: _arbeitet ? null : _briefAnsehen,
          icon: const Icon(Icons.picture_as_pdf, size: 16),
          label: const Text('PDF ansehen', style: TextStyle(fontSize: 12.5)),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _arbeitet ? null : _faxen,
          icon: _arbeitet
              ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.fax, size: 16),
          label: const Text('Fax senden'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple.shade700,
            foregroundColor: Colors.white,
          ),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Vor dem Senden ansehen. Ein Fax an eine Behörde geht sofort hinaus und lässt sich '
          'nicht zurückholen.',
          style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600)),
        ),
      ),
      const SizedBox(height: 20),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final fenster = MediaQuery.of(context).size;
    final schmal = fenster.width < 600;

    return Dialog(
      insetPadding: EdgeInsets.all(schmal ? 6 : 16),
      child: SizedBox(
        width: schmal ? fenster.width * 0.98 : (fenster.width * 0.9).clamp(720.0, 1100.0),
        height: schmal ? fenster.height * 0.95 : (fenster.height * 0.9).clamp(600.0, 900.0),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.shade700,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            child: Row(children: [
              Icon(_plan['ist_verwaltungsakt'] == true ? Icons.gavel : Icons.handshake, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    _plan['ist_verwaltungsakt'] == true ? 'Verwaltungsakt' : 'Kooperationsplan',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text('vom ${koopDatumDe(_plan['erstellt_am'])}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context, _geaendert),
              ),
            ]),
          ),
          TabBar(
            controller: _tab,
            labelColor: Colors.purple,
            isScrollable: true,
            tabs: const [
              Tab(icon: Icon(Icons.info, size: 18), text: 'Details'),
              Tab(icon: Icon(Icons.description, size: 18), text: 'Dokument'),
              Tab(icon: Icon(Icons.fact_check, size: 18), text: 'Prüfung'),
              Tab(icon: Icon(Icons.mail_outline, size: 18), text: 'Schreiben'),
            ],
          ),
          Expanded(
            child: _laden
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tab,
                    children: [_detailsTab(), _dokumenteTab(), _pruefungTab(), _schreibenTab()],
                  ),
          ),
        ]),
      ),
    );
  }
}
