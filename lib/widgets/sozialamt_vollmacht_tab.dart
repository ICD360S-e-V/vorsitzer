/// Vollmacht gegenüber dem Sozialamt — erzeugen, unterschreiben lassen, lesen.
///
/// ⚠️ SIE GILT FÜR DIE GANZE AKTE des Mitglieds bei diesem Amt, nicht für
/// einen einzelnen Antrag. Festlegung des Vorsitzenden vom 05.09.2026. Deshalb
/// hängt dieser Reiter zwar IN einem Antrag — er steht neben Korrespondenz —,
/// zeigt aber in jedem Antrag desselben Mitglieds dieselbe Vollmacht.
///
/// Juristisch ist das der einfachere Weg: § 13 SGB X verlangt die Bindung an
/// ein bestimmtes Verfahren NICHT. Diese Anforderung steht in § 14 Abs. 1
/// Satz 2 VwVfG — daran hängt das Landratsamt, und nur deshalb ist dessen
/// Vollmacht an einen Vorfall gebunden. Ein Mitglied mit drei Anträgen
/// unterschriebe sonst dreimal dasselbe Blatt.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';
import '../services/signatur_service.dart';
import '../utils/app_farben.dart';
import 'file_viewer_dialog.dart';
import 'vollmacht_link_aktionen.dart';

class SozialamtVollmachtTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  /// Für den Signaturauftrag: unter dieser Nummer stellt der Vorstand.
  final String adminMitgliedernummer;

  /// Das Postfach des Mitglieds — Ziel des Chat-Versands.
  final String memberMitgliedernummer;

  const SozialamtVollmachtTab({
    super.key,
    required this.apiService,
    required this.userId,
    this.adminMitgliedernummer = '',
    this.memberMitgliedernummer = '',
  });

  @override
  State<SozialamtVollmachtTab> createState() => _SozialamtVollmachtTabState();
}

class _SozialamtVollmachtTabState extends State<SozialamtVollmachtTab> {
  static const _akzent = Colors.indigo;

  bool _laedt = true;
  String? _fehler;
  int? _beschaeftigt;
  bool _erzeugt = false;

  Map<String, dynamic> _daten = {};
  List<Map<String, dynamic>> _liste = [];

  /// Schlüssel → Beschriftung, vom Server. ⚠️ NICHT im Client gepflegt: der
  /// Bildschirm darf keine Option anbieten, die im PDF nicht steht — sonst
  /// hätte jemand etwas bevollmächtigt, das er nie gelesen hat.
  Map<String, String> _katalog = {};
  final Set<String> _umfang = {};

  /// Wie viele Zeilen das Versandprotokoll je Vollmacht hat — nur für die
  /// Zahl am Knopf. Ohne sie müsste man den Dialog öffnen, um zu sehen, ob
  /// überhaupt schon etwas hinausgegangen ist.
  Map<int, int> _versandAnzahl = {};

  DateTime _abDatum = DateTime.now();
  DateTime? _bisDatum;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() { _laedt = true; _fehler = null; });
    final d = await widget.apiService.getVollmachtData(widget.userId, 'sozialamt');
    final l = await widget.apiService.listVollmachten(widget.userId, 'sozialamt');
    if (!mounted) return;
    setState(() {
      _laedt = false;
      if (d['success'] == true) {
        _daten = Map<String, dynamic>.from(d);
        final k = (d['recht'] is Map) ? (d['recht']['umfang_katalog']) : null;
        if (k is Map) {
          _katalog = k.map((a, b) => MapEntry(a.toString(), b.toString()));
          // Beim ersten Laden ist alles angehakt: das ist der Regelfall, und
          // wer weniger will, nimmt Haken weg. Umgekehrt übersieht man leicht,
          // dass gar nichts gilt.
          if (_umfang.isEmpty) _umfang.addAll(_katalog.keys);
        }
      } else {
        _fehler = (d['message'] ?? 'Daten nicht abrufbar').toString();
      }
      // 🔴 `vollmachten`, NICHT `data`. vollmacht_list.php antwortet mit
      // `jsonResponse(true, ['vollmachten' => $rows])`; die Antrags-Endpunkte
      // dieses Bildschirms nebenan benutzen `data`, und genau von dort war der
      // Schlüssel übernommen. Folge: die Vollmacht wurde jedes Mal erzeugt und
      // erschien nie — kein Fehler, keine Meldung, nur eine leere Liste. Wer
      // daraufhin noch einmal drückt, legt eine zweite an.
      if (l['success'] == true && l['vollmachten'] is List) {
        _liste = (l['vollmachten'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    });
    await _versandStaendeLaden();
  }

  /// ⚠️ Ein Aufruf JE Vollmacht — es gibt keinen Sammelendpunkt. Bei zwei,
  /// drei Vollmachten je Mitglied ist das in Ordnung; wenn daraus je zwanzig
  /// werden, gehört die Zahl in die Liste selbst.
  Future<void> _versandStaendeLaden() async {
    final neu = <int, int>{};
    for (final vm in _liste) {
      final id = (vm['id'] as num?)?.toInt();
      if (id == null) continue;
      final p = await widget.apiService.sozialamtVollmachtVersandListe(id);
      if (p['success'] != true) continue;
      neu[id] = ((p['items'] as List?)?.length ?? 0) + ((p['links'] as List?)?.length ?? 0);
    }
    if (!mounted) return;
    setState(() => _versandAnzahl = neu);
  }

  void _sagen(String t, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), backgroundColor: c));
  }

  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  // ── Erzeugen ───────────────────────────────────────────────────────────

  Future<void> _erzeugen() async {
    if (_umfang.isEmpty) {
      _sagen('Ohne einen einzigen Umfangspunkt wäre die Vollmacht leer.', Colors.orange);
      return;
    }
    setState(() => _erzeugt = true);
    final r = await widget.apiService.createVollmacht({
      'user_id': widget.userId,
      'behoerde': 'sozialamt',
      'valid_from': _iso(_abDatum),
      'valid_until': _bisDatum == null ? null : _iso(_bisDatum!),
      'options': {'umfang': {for (final k in _umfang) k: 1}},
    });
    if (!mounted) return;
    setState(() => _erzeugt = false);
    final ok = r['success'] == true;
    _sagen(ok ? 'Vollmacht erstellt (ID ${r['id']})' : (r['message'] ?? 'Fehler').toString(),
        ok ? Colors.green : Colors.red);
    if (ok) await _laden();
  }

  // ── Unterschrift, Links, PDF ───────────────────────────────────────────

  Future<void> _zurUnterschrift(Map<String, dynamic> vm) async {
    final id = vm['id'] as int;
    final vorsitzerId = (_daten['vorsitzer'] is Map)
        ? ((_daten['vorsitzer']['id'] as num?)?.toInt() ?? 0) : 0;
    if (vorsitzerId <= 0) {
      _sagen('Kein Vorsitzender hinterlegt — ohne ihn fehlt der zweite Unterzeichner.', Colors.red);
      return;
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
      // ⚠️ `anfordernAusBytes`, nicht `anfordern`: das Blatt liegt auf dem
      // Server verschlüsselt. Eine Zwischendatei schriebe den Klartext genau
      // des Dokuments auf die Platte, dessen Unversehrtheit gleich bezeugt wird.
      final e = await SignaturService().anfordernAusBytes(
        callerMitgliedernummer: widget.adminMitgliedernummer,
        userId: widget.userId,
        dokumentTyp: 'sozialamt_vollmacht',
        dokumentTitel: 'Vollmacht — Sozialamt',
        pdfBytes: r.bodyBytes,
        dateiname: (vm['pdf_filename'] ?? 'vollmacht_$id.pdf').toString(),
        fristBis: DateTime.now().add(const Duration(days: 14)),
        // ⚠️ Über quelle_tabelle/quelle_id, NIE über den Titel: der ist bei
        // jeder Vollmacht derselbe, und der Stand landete auf der falschen Zeile.
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
      if (e.ok) await _laden();
    } finally {
      if (mounted) setState(() => _beschaeftigt = null);
    }
  }

  Future<void> _pdfOeffnen(Map<String, dynamic> vm, {bool uebersetzung = false}) async {
    final id = vm['id'] as int;
    final r = await widget.apiService
        .downloadVollmachtPdf(id, type: uebersetzung ? 'translation' : 'pdf');
    if (!mounted) return;
    if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
      // Aus dem Speicher, nicht über eine Datei — siehe oben.
      FileViewerDialog.showFromBytes(context, r.bodyBytes,
          ((uebersetzung ? vm['pdf_translation_filename'] : vm['pdf_filename'])
              ?? 'vollmacht_$id.pdf').toString());
    } else {
      _sagen('Fehler (${r.statusCode})', Colors.red);
    }
  }

  Future<void> _widerrufen(int id) async {
    final grund = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Vollmacht widerrufen'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text(
          'Sie wird als widerrufen markiert und kann danach weder versendet '
          'noch unterschrieben werden.\n\n'
          'Der Widerruf wirkt gegenüber der Behörde erst, wenn er IHR zugeht '
          '(§ 13 Abs. 1 Satz 4 SGB X) — er muss also zusätzlich schriftlich an '
          'das Sozialamt gehen.',
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
      ]));
    if (ok != true) return;
    final r = await widget.apiService.revokeVollmacht(id, reason: grund.text.trim());
    if (!mounted) return;
    _sagen(r['success'] == true ? 'Widerrufen'
                                : (r['message'] ?? 'Fehler').toString(),
        r['success'] == true ? Colors.orange : Colors.red);
    if (r['success'] == true) await _laden();
  }

  /// Das Blatt in das Postfach DES MITGLIEDS.
  ///
  /// ⚠️ Es geht das LESEEXEMPLAR in der Sprache des Mitglieds, wenn es eines
  /// gibt — es ist sein Recht zu wissen, was es unterschreibt. Unterschrieben
  /// und beim Sozialamt eingereicht wird weiter allein die deutsche Fassung;
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
              'Unterschrieben und beim Sozialamt eingereicht wird weiter allein '
              'die deutsche Fassung — das steht auch auf jeder Seite des '
              'Leseexemplars.'
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
        _sagen('Fehler (${r.statusCode})', Colors.red);
        return;
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
            ? 'Vollmacht (Leseexemplar) — Sozialamt'
            : 'Vollmacht — Sozialamt');
      if (!mounted) return;
      final erfolg = res['success'] == true;
      // ⚠️ Erst NACH bestätigtem Empfang protokollieren. Eine Zeile, die eine
      // Sendung behauptet, die nie ankam, ist genau die, auf die sich später
      // jemand verlässt.
      if (erfolg) {
        await widget.apiService.sozialamtVollmachtVersandEintragen(
          vollmachtId: id, empfaenger: nummer, weg: 'chat',
          fassung: uebersetzt ? 'uebersetzung' : 'original',
          sprache: uebersetzt ? sprache : 'de');
      }
      if (!mounted) return;
      _sagen(erfolg ? 'An $nummer gesendet' : 'Konnte nicht gesendet werden',
             erfolg ? Colors.green : Colors.red);
      if (erfolg) await _laden();
    } catch (e) {
      if (mounted) _sagen('Fehler: $e', Colors.red);
    } finally {
      if (temp != null && await temp.exists()) { await temp.delete(); }
      if (mounted) setState(() => _beschaeftigt = null);
    }
  }

  Future<void> _protokoll(int id) async {
    final p = await widget.apiService.sozialamtVollmachtVersandListe(id);
    if (!mounted) return;
    final zeilen = ((p['items'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    // ⚠️ Die Linkzeilen stehen ABGESETZT von den Sendungen. Eine Chatzeile
    // beantwortet „wann ging was an wen"; eine Linkzeile beantwortet
    // zusätzlich, was das Mitglied damit getan hat. In eine Tabelle gepresst,
    // deren Zeitspalte „gesendet" heißt, läse sich das eine als das andere.
    final links = ((p['links'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (p['success'] == true) {
      setState(() => _versandAnzahl = {..._versandAnzahl, id: zeilen.length + links.length});
    }
    final breite = MediaQuery.of(context).size.width;
    await showDialog<void>(context: context, builder: (c) => AlertDialog(
      title: Text('Versandprotokoll — Vollmacht #$id', style: const TextStyle(fontSize: 15)),
      content: SizedBox(
        width: breite < 560 ? breite * 0.86 : 480,
        child: (zeilen.isEmpty && links.isEmpty)
            ? const Text('Noch nichts versandt.', style: TextStyle(fontSize: 13))
            : SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ⚠️ kVollmachtVersandWege statt des Rohwerts: sonst stünde
                  // hier „chat an M12345", kleingeschrieben und ohne
                  // Präposition, wie ein Datenbankauszug.
                  ...zeilen.map((z) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${z['gesendet_am'] ?? ''}',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      Text('${kVollmachtVersandWege[(z['weg'] ?? '').toString()]
                              ?? (z['weg'] ?? '')} an ${z['empfaenger'] ?? ''}'
                           '${(z['fassung'] ?? '') == 'uebersetzung'
                              ? ' · Leseexemplar ${(z['sprache'] ?? '').toString().toUpperCase()}'
                              : ''}',
                          style: const TextStyle(fontSize: 12)),
                      if ((z['gesendet_von_name'] ?? '').toString().trim().isNotEmpty)
                        Text('durch ${z['gesendet_von_name']}',
                            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                    ]))),
                  ...links.map((l) => VollmachtLinkZeile(link: l)),
                ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Schließen')),
      ],
    ));
  }

  // ── Oberfläche ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_laedt) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_fehler != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: F.h(Colors.red, 50),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: F.h(Colors.red, 200))),
            child: Text(_fehler!, style: TextStyle(fontSize: 12, color: F.h(Colors.red, 900))),
          ),
        _geltungsbereich(),
        const SizedBox(height: 12),
        _neueVollmacht(),
        const SizedBox(height: 16),
        Text('Vollmachten (${_liste.length})',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(_akzent, 700))),
        const SizedBox(height: 8),
        if (_liste.isEmpty)
          Text('Noch keine Vollmacht erstellt.',
              style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)))
        else
          ..._liste.map(_karte),
      ]),
    );
  }

  /// ⚠️ Steht GANZ OBEN, vor dem Erzeugen-Knopf. Wer die Vollmacht ausstellt,
  /// muss vorher wissen, dass sie die ganze Akte deckt und nicht nur den
  /// Antrag, in dem er gerade steht.
  Widget _geltungsbereich() {
    final amt = (_daten['amt'] is Map) ? Map<String, dynamic>.from(_daten['amt']) : {};
    final name = (amt['name'] ?? '').toString();
    final recht = (_daten['recht'] is Map) ? Map<String, dynamic>.from(_daten['recht']) : {};
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: F.h(_akzent, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(_akzent, 200))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.folder_shared_outlined, size: 16, color: F.h(_akzent, 700)),
          const SizedBox(width: 6),
          Expanded(child: Text(
            name.isEmpty ? 'Kein Sozialamt im Reiter Behörde ausgewählt' : name,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold,
                color: F.h(name.isEmpty ? Colors.orange : _akzent, 800)))),
        ]),
        const SizedBox(height: 4),
        Text('Gilt für die gesamte Akte des Mitglieds bei diesem Amt — alle '
             'laufenden und künftigen Anträge, nicht nur den hier geöffneten.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
        if ((recht['norm'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('${recht['norm']} · Rechtsweg: ${recht['rechtsweg'] ?? ''} '
                        '(${recht['rechtsweg_norm'] ?? ''})',
                style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600))),
          ),
        if (name.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Ohne ausgewähltes Amt steht auf dem Blatt „(nicht angegeben)". '
                        'Das Amt wird im Reiter Behörde gesetzt.',
                style: TextStyle(fontSize: 10.5, color: F.h(Colors.orange, 800))),
          ),
      ]),
    );
  }

  Widget _neueVollmacht() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Neue Vollmacht',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(_akzent, 700))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _datumFeld('Gültig ab', _abDatum, (d) => setState(() => _abDatum = d))),
            const SizedBox(width: 8),
            Expanded(child: _datumFeld('Gültig bis', _bisDatum,
                (d) => setState(() => _bisDatum = d), leerText: 'auf Widerruf')),
          ]),
          const SizedBox(height: 10),
          Text('Umfang', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
              color: F.h(Colors.grey, 700))),
          Text('Nur was angehakt ist, steht später als [X] auf dem Blatt.',
              style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600))),
          const SizedBox(height: 4),
          if (_katalog.isEmpty)
            Text('Kein Umfangskatalog vom Server — ohne ihn lässt sich nichts erzeugen.',
                style: TextStyle(fontSize: 11.5, color: F.h(Colors.orange, 800)))
          else
            ..._katalog.entries.map((e) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _umfang.contains(e.key),
                  activeColor: F.h(_akzent, 700),
                  title: Text(e.value, style: const TextStyle(fontSize: 12)),
                  onChanged: (v) => setState(() {
                    if (v == true) { _umfang.add(e.key); } else { _umfang.remove(e.key); }
                  }),
                )),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              icon: _erzeugt
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('Vollmacht erzeugen'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: F.h(_akzent, 700), foregroundColor: Colors.white),
              onPressed: (_erzeugt || _katalog.isEmpty) ? null : _erzeugen,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _datumFeld(String label, DateTime? wert, ValueChanged<DateTime> gesetzt,
      {String leerText = ''}) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: wert ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2040),
          locale: const Locale('de'),
        );
        if (d != null) gesetzt(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          prefixIcon: const Icon(Icons.calendar_today, size: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          wert == null ? leerText
              : '${wert.day.toString().padLeft(2, '0')}.'
                '${wert.month.toString().padLeft(2, '0')}.${wert.year}',
          style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  Widget _karte(Map<String, dynamic> vm) {
    final id = vm['id'] as int;
    final status = (vm['status'] ?? '').toString();
    final laeuft = _beschaeftigt == id;
    final widerrufen = status == 'revoked';
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
            TextButton.icon(
              icon: const Icon(Icons.receipt_long, size: 14),
              label: Text('Versandprotokoll${(_versandAnzahl[id] ?? 0) > 0
                  ? ' (${_versandAnzahl[id]})' : ''}',
                  style: const TextStyle(fontSize: 11)),
              onPressed: () => _protokoll(id),
            ),
            if (!widerrufen)
              TextButton.icon(
                icon: const Icon(Icons.block, size: 14, color: Colors.red),
                label: const Text('Widerrufen',
                    style: TextStyle(fontSize: 11, color: Colors.red)),
                onPressed: () => _widerrufen(id),
              ),
          ]),
          if (!widerrufen) ...[
            const Divider(height: 16),
            Row(children: [
              Icon(Icons.draw_outlined, size: 15, color: F.h(_akzent, 700)),
              const SizedBox(width: 5),
              Text('Mit App: in der eigenen App unterschreiben',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold,
                      color: F.h(_akzent, 800))),
            ]),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              icon: laeuft
                  ? const SizedBox(width: 13, height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.how_to_reg, size: 15),
              label: const Text('Zur Unterschrift stellen', style: TextStyle(fontSize: 11)),
              onPressed: laeuft ? null : () => _zurUnterschrift(vm),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.chat_outlined, size: 15, color: F.h(_akzent, 700)),
              const SizedBox(width: 5),
              Text('Mit App: in das Postfach des Mitglieds',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold,
                      color: F.h(_akzent, 800))),
            ]),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              icon: const Icon(Icons.chat_outlined, size: 15),
              // ⚠️ Der Text nennt die Fassung, die WIRKLICH hinausgeht. „In den
              // Chat" allein liesse offen, ob das Mitglied das deutsche Blatt
              // oder seine eigene Sprache bekommt.
              label: Text(
                (vm['pdf_translation_filename'] ?? '').toString().isNotEmpty
                    ? 'Leseexemplar (${(vm['translation_language'] ?? '').toString().toUpperCase()}) in den Chat'
                    : 'In den Chat (DE)',
                style: const TextStyle(fontSize: 11)),
              onPressed: laeuft ? null : () => _inDenChat(vm),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.sms_outlined, size: 15, color: F.h(_akzent, 700)),
              const SizedBox(width: 5),
              Text('Ohne App: Link per SMS',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold,
                      color: F.h(_akzent, 800))),
            ]),
            const SizedBox(height: 4),
            VollmachtLinkKnoepfe(
              farbe: _akzent,
              widerrufen: widerrufen,
              // ⚠️ Der Signierlink FÜHRT zu einem offenen Vorgang, er legt
              // keinen an. Ohne gestellte Unterschrift lehnt der Server ab —
              // der Knopf bleibt grau, statt die Auskunft erst nach dem Klick
              // zu geben.
              signierbar: status == 'wartet_unterschriften',
              signierHinweis: 'Erst „Zur Unterschrift stellen" — der Link führt zu '
                              'einem offenen Vorgang, er legt keinen an.',
              onGesendet: _laden,
              onSenden: (zweck) => widget.apiService
                  .sozialamtVollmachtLinkSenden(vollmachtId: id, zweck: zweck),
            ),
          ],
        ]),
      ),
    );
  }
}
