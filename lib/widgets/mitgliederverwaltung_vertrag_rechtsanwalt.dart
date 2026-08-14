/// Rechtsanwalt-Zweig eines Vertrags — vierter Reiter neben Aktenzeichen
/// im Inkasso-Bereich.
///
/// Eigene Datei, obwohl der Inkasso-Zweig in
/// mitgliederverwaltung_vertraege.dart liegt: jene Datei hat 3.488 Zeilen
/// und wird von mehreren Sitzungen gleichzeitig angefasst. Hier bleibt der
/// Eingriff dort auf einen Import, einen Reiter und eine Zeile in der
/// TabBarView beschraenkt.
///
/// ⚠️ ZWEI DINGE, DIE HIER SCHON FEHLER ERZEUGT HABEN:
///
///  1. Der Server mischt die Nutzdaten in die WURZEL der Antwort
///     (`jsonResponse()` macht `array_merge`). `items`, `id`, `exists`,
///     `fristen` stehen also direkt oben — nicht unter `data`. Nur
///     `get_mandat` und `get_mahnverfahren` setzen zusaetzlich einen
///     echten Schluessel `data`. Deshalb [_liste] und [_karte] statt
///     Zugriffe von Hand.
///  2. Fristen kommen fertig gerechnet vom Server. Hier wird NICHTS
///     nachgerechnet. Eine Notfrist, die auf zwei Wegen entsteht, ist eine
///     Notfrist, die irgendwann zwei Werte hat.
library;

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/ra_antwort.dart';
import 'mitgliederverwaltung_vertrag_ra_akte.dart';
import 'phone_link.dart';

const Color kRaFarbe = Color(0xFF00695C); // teal.shade800

/// Dialoge in Bildschirmgroesse statt fester Punktzahl.
///
/// ⚠️ Der Inkasso-Dialog daneben steht auf `width: 720, height: 600`. Auf
/// dem Pixel, auf dem diese App laeuft, ist das breiter als das Geraet —
/// der Inhalt wird gequetscht, ohne dass ein Ueberlauf gemeldet wird.
Size _dialogGroesse(BuildContext context) {
  final m = MediaQuery.of(context).size;
  return Size(m.width < 760 ? m.width * 0.96 : 760, m.height * 0.88);
}

// ═══════════════════════════════════════════════════════════════════════
// Reiter: Rechtsanwalt  →  Zustaendiger Rechtsanwalt | Aktenzeichen
// ═══════════════════════════════════════════════════════════════════════

class VertragRechtsanwaltTab extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  const VertragRechtsanwaltTab({super.key, required this.apiService, required this.vertragId});

  @override
  State<VertragRechtsanwaltTab> createState() => _VertragRechtsanwaltTabState();
}

class _VertragRechtsanwaltTabState extends State<VertragRechtsanwaltTab> {
  Map<String, dynamic>? _mandat;
  bool _geladen = false;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final res = await widget.apiService.getVertragRaMandat(widget.vertragId);
    if (!mounted) return;
    setState(() {
      // `exists` steht in der Wurzel, `data` ist hier ein echter
      // Schluessel — genau die Verwechslung, die im Inkasso-Zweig dazu
      // gefuehrt hat, dass gespeicherte Daten als "nicht da" erschienen.
      _mandat = res['exists'] == true ? raKarte(res, 'data') : null;
      _geladen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Container(
          color: kRaFarbe.withValues(alpha: 0.08),
          child: const TabBar(
            isScrollable: true,
            labelColor: kRaFarbe,
            indicatorColor: kRaFarbe,
            tabs: [
              Tab(icon: Icon(Icons.balance, size: 16), text: 'Zuständiger Rechtsanwalt'),
              Tab(icon: Icon(Icons.folder_special, size: 16), text: 'Aktenzeichen'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(children: [
            _ZustaendigerAnwaltSubTab(
              apiService: widget.apiService,
              vertragId: widget.vertragId,
              mandat: _mandat,
              onSaved: _laden,
            ),
            _RaAktenzeichenSubTab(
              apiService: widget.apiService,
              vertragId: widget.vertragId,
              mandat: _mandat,
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Unterreiter 1: Zustaendiger Rechtsanwalt ─────────────────────────

class _ZustaendigerAnwaltSubTab extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  final Map<String, dynamic>? mandat;
  final VoidCallback onSaved;
  const _ZustaendigerAnwaltSubTab({
    required this.apiService,
    required this.vertragId,
    required this.mandat,
    required this.onSaved,
  });

  @override
  State<_ZustaendigerAnwaltSubTab> createState() => _ZustaendigerAnwaltSubTabState();
}

class _ZustaendigerAnwaltSubTabState extends State<_ZustaendigerAnwaltSubTab> {
  static const statusOptionen = [
    ('kein_mandat', 'Kein Mandat', Colors.grey),
    ('mandat_erteilt', 'Mandat erteilt', Colors.blue),
    ('in_bearbeitung', 'In Bearbeitung', Colors.indigo),
    ('aussergerichtlich', 'Außergerichtlich', Colors.teal),
    ('mahnverfahren', 'Mahnverfahren', Colors.orange),
    ('klageverfahren', 'Klageverfahren', Colors.red),
    ('vergleich', 'Vergleich', Colors.cyan),
    ('ruht', 'Ruht', Colors.blueGrey),
    ('beendet', 'Beendet', Colors.green),
    ('mandat_niedergelegt', 'Mandat niedergelegt', Colors.deepOrange),
  ];

  List<Map<String, dynamic>> _kanzleien = [];
  int? _gewaehlt;
  bool _geladen = false;
  bool _speichert = false;

  late final TextEditingController _ansprechC;
  late final TextEditingController _telC;
  late final TextEditingController _emailC;
  late final TextEditingController _azC;
  late final TextEditingController _gegenstandC;
  late final TextEditingController _rsvNameC;
  late final TextEditingController _rsvNrC;
  late final TextEditingController _notizC;
  String _status = 'kein_mandat';
  String _rechtsschutz = 'unbekannt';
  DateTime? _seit;
  DateTime? _bis;

  @override
  void initState() {
    super.initState();
    final m = widget.mandat ?? const <String, dynamic>{};
    _gewaehlt = int.tryParse(raText(m['rechtsanwalt_id']));
    _ansprechC = TextEditingController(text: raText(m['ansprechpartner']));
    _telC = TextEditingController(text: raText(m['telefon_durchwahl']));
    _emailC = TextEditingController(text: raText(m['email_ansprechpartner']));
    _azC = TextEditingController(text: raText(m['ra_aktenzeichen']));
    _gegenstandC = TextEditingController(text: raText(m['gegenstand']));
    _rsvNameC = TextEditingController(text: raText(m['rsv_name']));
    _rsvNrC = TextEditingController(text: raText(m['rsv_schadennummer']));
    _notizC = TextEditingController(text: raText(m['notizen']));
    _status = raHat(m['status']) ? raText(m['status']) : 'kein_mandat';
    _rechtsschutz = raHat(m['rechtsschutz']) ? raText(m['rechtsschutz']) : 'unbekannt';
    _seit = DateTime.tryParse(raText(m['mandat_seit']));
    _bis = DateTime.tryParse(raText(m['mandat_bis']));
    _kanzleienLaden();
  }

  @override
  void dispose() {
    for (final c in [_ansprechC, _telC, _emailC, _azC, _gegenstandC, _rsvNameC, _rsvNrC, _notizC]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _kanzleienLaden() async {
    final res = await widget.apiService.listRechtsanwaltDatenbank();
    if (!mounted) return;
    setState(() {
      _kanzleien = raListe(res);
      _geladen = true;
    });
  }

  Future<void> _datumWaehlen(DateTime? start, ValueChanged<DateTime?> gewaehlt) async {
    final d = await showDatePicker(
      context: context,
      initialDate: start ?? DateTime.now(),
      firstDate: DateTime(2010),
      lastDate: DateTime(2060),
    );
    if (d != null) gewaehlt(d);
  }

  Future<void> _speichern() async {
    setState(() => _speichert = true);
    final res = await widget.apiService.saveVertragRaMandat(widget.vertragId, {
      'rechtsanwalt_id': _gewaehlt ?? 0,
      'status': _status,
      'mandat_seit': raIso(_seit),
      'mandat_bis': raIso(_bis),
      'ansprechpartner': _ansprechC.text.trim(),
      'telefon_durchwahl': _telC.text.trim(),
      'email_ansprechpartner': _emailC.text.trim(),
      'ra_aktenzeichen': _azC.text.trim(),
      'gegenstand': _gegenstandC.text.trim(),
      'rechtsschutz': _rechtsschutz,
      'rsv_name': _rsvNameC.text.trim(),
      'rsv_schadennummer': _rsvNrC.text.trim(),
      'notizen': _notizC.text.trim(),
    });
    if (!mounted) return;
    setState(() => _speichert = false);
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Mandat gespeichert (verschlüsselt)' : raText(res['message']).isEmpty ? 'Fehler' : raText(res['message'])),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    final gewaehlteKanzlei = _kanzleien.firstWhere(
      (e) => int.tryParse(raText(e['id'])) == _gewaehlt,
      orElse: () => const <String, dynamic>{},
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_kanzleien.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              border: Border.all(color: Colors.amber.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Die Kanzlei-Datenbank ist noch leer. Bis Einträge vorhanden sind, '
                  'lassen sich Mandatsdaten erfassen, aber keine Vollmacht erzeugen — '
                  'ihr fehlte der Adressat.',
                  style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                ),
              ),
            ]),
          ),
        const Text('Zuständige Kanzlei', style: TextStyle(fontWeight: FontWeight.bold, color: kRaFarbe)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(
          initialValue: _gewaehlt,
          isExpanded: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            hintText: 'Kanzlei auswählen…',
            prefixIcon: const Icon(Icons.balance),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('— keine —')),
            ..._kanzleien.map((e) => DropdownMenuItem<int?>(
                  value: int.tryParse(raText(e['id'])),
                  child: Text(
                    raHat(e['anwalt_name'])
                        ? '${raText(e['firmenname'])} · ${raText(e['anwalt_name'])}'
                        : raText(e['firmenname']),
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
          ],
          onChanged: (v) => setState(() => _gewaehlt = v),
        ),
        if (gewaehlteKanzlei.isNotEmpty) ...[
          const SizedBox(height: 12),
          _KanzleiKarte(kanzlei: gewaehlteKanzlei),
        ],
        const SizedBox(height: 20),
        const Text('Mandat', style: TextStyle(fontWeight: FontWeight.bold, color: kRaFarbe)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _status,
              decoration: const InputDecoration(
                  labelText: 'Status', prefixIcon: Icon(Icons.flag), border: OutlineInputBorder(), isDense: true),
              items: statusOptionen
                  .map((s) => DropdownMenuItem(
                        value: s.$1,
                        child: Row(children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Flexible(child: Text(s.$2, overflow: TextOverflow.ellipsis)),
                        ]),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _status = v ?? 'kein_mandat'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: () => _datumWaehlen(_seit, (d) => setState(() => _seit = d)),
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Mandat seit', prefixIcon: Icon(Icons.event), border: OutlineInputBorder(), isDense: true),
                child: Text(_seit == null ? '—' : raDatumDe(raIso(_seit))),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => _datumWaehlen(_bis, (d) => setState(() => _bis = d)),
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Mandat bis', prefixIcon: Icon(Icons.event_available), border: OutlineInputBorder(), isDense: true),
                child: Text(_bis == null ? '—' : raDatumDe(raIso(_bis))),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _azC,
          decoration: const InputDecoration(
              labelText: 'Aktenzeichen der Kanzlei', prefixIcon: Icon(Icons.tag), border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _gegenstandC,
          decoration: const InputDecoration(
              labelText: 'Gegenstand des Mandats', prefixIcon: Icon(Icons.subject), border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ansprechC,
          decoration: const InputDecoration(
              labelText: 'Ansprechpartner', prefixIcon: Icon(Icons.person), border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _telC,
              decoration: const InputDecoration(
                  labelText: 'Telefon / Durchwahl', prefixIcon: Icon(Icons.phone), border: OutlineInputBorder(), isDense: true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _emailC,
              decoration: const InputDecoration(
                  labelText: 'E-Mail', prefixIcon: Icon(Icons.email), border: OutlineInputBorder(), isDense: true),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        const Text('Rechtsschutzversicherung', style: TextStyle(fontWeight: FontWeight.bold, color: kRaFarbe)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final r in const [
            ('unbekannt', 'Unbekannt'),
            ('ja', 'Vorhanden'),
            ('deckung_zugesagt', 'Deckung zugesagt'),
            ('deckung_abgelehnt', 'Deckung abgelehnt'),
            ('nein', 'Keine'),
          ])
            ChoiceChip(
              label: Text(r.$2, style: const TextStyle(fontSize: 11)),
              selected: _rechtsschutz == r.$1,
              onSelected: (_) => setState(() => _rechtsschutz = r.$1),
            ),
        ]),
        if (_rechtsschutz == 'ja' || _rechtsschutz == 'deckung_zugesagt' || _rechtsschutz == 'deckung_abgelehnt') ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _rsvNameC,
                decoration: const InputDecoration(
                    labelText: 'Versicherer', prefixIcon: Icon(Icons.shield), border: OutlineInputBorder(), isDense: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _rsvNrC,
                decoration: const InputDecoration(
                    labelText: 'Schadennummer', prefixIcon: Icon(Icons.numbers), border: OutlineInputBorder(), isDense: true),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _notizC,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Notizen', prefixIcon: Icon(Icons.note), border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _speichert ? null : _speichern,
            icon: _speichert
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 16),
            label: const Text('Speichern (verschlüsselt)'),
            style: ElevatedButton.styleFrom(backgroundColor: kRaFarbe, foregroundColor: Colors.white),
          ),
        ),
      ]),
    );
  }
}

class _KanzleiKarte extends StatelessWidget {
  final Map<String, dynamic> kanzlei;
  const _KanzleiKarte({required this.kanzlei});

  @override
  Widget build(BuildContext context) {
    Widget zeile(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(child: phoneAwareText(icon, text, style: const TextStyle(fontSize: 12))),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (raHat(kanzlei['firmenname']))
          Text(raText(kanzlei['firmenname']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        if (raHat(kanzlei['anwalt_name']))
          Text(raText(kanzlei['anwalt_name']), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        if (raHat(kanzlei['strasse']) || raHat(kanzlei['plz_ort']))
          zeile(Icons.location_on, [raText(kanzlei['strasse']), raText(kanzlei['plz_ort'])].where((e) => e.isNotEmpty).join(', ')),
        if (raHat(kanzlei['telefon'])) zeile(Icons.phone, raText(kanzlei['telefon'])),
        if (raHat(kanzlei['fax'])) zeile(Icons.fax, raText(kanzlei['fax'])),
        if (raHat(kanzlei['email'])) zeile(Icons.email, raText(kanzlei['email'])),
        if (raHat(kanzlei['website'])) zeile(Icons.language, raText(kanzlei['website'])),
        if (raHat(kanzlei['fachgebiete'])) zeile(Icons.workspace_premium, raText(kanzlei['fachgebiete'])),
        if (raHat(kanzlei['rechtsanwaltskammer'])) zeile(Icons.account_balance, raText(kanzlei['rechtsanwaltskammer'])),
        // beA: der Weg, auf dem Schriftsaetze bei der Kanzlei ankommen,
        // ohne dass jemand einen Brief einwirft (§ 31a BRAO).
        if (raHat(kanzlei['bea_safe_id'])) zeile(Icons.mark_email_read, 'beA: ${raText(kanzlei['bea_safe_id'])}'),
      ]),
    );
  }
}

// ─── Unterreiter 2: Aktenzeichen ──────────────────────────────────────

class _RaAktenzeichenSubTab extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  final Map<String, dynamic>? mandat;
  const _RaAktenzeichenSubTab({required this.apiService, required this.vertragId, required this.mandat});

  @override
  State<_RaAktenzeichenSubTab> createState() => _RaAktenzeichenSubTabState();
}

class _RaAktenzeichenSubTabState extends State<_RaAktenzeichenSubTab> {
  List<Map<String, dynamic>> _akten = [];
  bool _geladen = false;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final res = await widget.apiService.listVertragRaAktenzeichen(widget.vertragId);
    if (!mounted) return;
    setState(() {
      _akten = raListe(res);
      _geladen = true;
    });
  }

  Future<void> _bearbeiten({Map<String, dynamic>? vorhanden}) async {
    final gespeichert = await showDialog<bool>(
      context: context,
      builder: (ctx) => _RaAktenzeichenDialog(
        apiService: widget.apiService,
        vertragId: widget.vertragId,
        vorhanden: vorhanden,
      ),
    );
    if (gespeichert == true) _laden();
  }

  Future<void> _loeschen(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aktenzeichen löschen?'),
        content: const Text(
          'Korrespondenz, Mahnverfahren, hochgeladene Dokumente und Vollmacht-Entwürfe '
          'zu dieser Akte werden mit entfernt.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Löschen', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await widget.apiService.deleteVertragRaAktenzeichen(id);
    _laden();
  }

  void _oeffnen(Map<String, dynamic> akte) {
    final groesse = _dialogGroesse(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: SizedBox(
          width: groesse.width,
          height: groesse.height,
          child: RaAktenzeichenDetailDialog(
            apiService: widget.apiService,
            vertragId: widget.vertragId,
            akte: akte,
            mandat: widget.mandat,
            onChanged: _laden,
          ),
        ),
      ),
    );
  }

  /// ⚠️ Die Plakette zeigt die Bezeichnung, NICHT den ENUM-Wert.
  ///
  /// Beim Ansehen der gerenderten Liste stand da `mahnverfahren` klein
  /// geschrieben neben der Plakette `Mahnverfahren` — es sah aus wie ein
  /// doppelter Eintrag, war aber der Rohwert aus der Datenbank.
  /// `zurueckgewiesen` haette obendrein niemand als „zurückgewiesen"
  /// gelesen.
  static String statusText(String? s) => switch (s) {
        'offen' => 'Offen',
        'in_bearbeitung' => 'In Bearbeitung',
        'aussergerichtlich' => 'Außergerichtlich',
        'mahnverfahren' => 'Mahnverfahren',
        'klageverfahren' => 'Klageverfahren',
        'vergleich' => 'Vergleich',
        'ruht' => 'Ruht',
        'abgeschlossen' => 'Abgeschlossen',
        'zurueckgewiesen' => 'Zurückgewiesen',
        _ => 'Offen',
      };

  static Color statusFarbe(String? s) => switch (s) {
        'offen' => Colors.orange,
        'in_bearbeitung' => Colors.blue,
        'aussergerichtlich' => Colors.teal,
        'mahnverfahren' => Colors.deepOrange,
        'klageverfahren' => Colors.red,
        'vergleich' => Colors.cyan,
        'ruht' => Colors.blueGrey,
        'abgeschlossen' => Colors.green,
        'zurueckgewiesen' => Colors.grey,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          const Icon(Icons.folder_special, size: 18, color: kRaFarbe),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${_akten.length} Aktenzeichen',
                style: const TextStyle(fontWeight: FontWeight.bold, color: kRaFarbe)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neu'),
            style: ElevatedButton.styleFrom(backgroundColor: kRaFarbe, foregroundColor: Colors.white),
            onPressed: () => _bearbeiten(),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _akten.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.folder_special, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('Noch kein Aktenzeichen', style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text('Tippen Sie auf „Neu", um die Aktennummer der Kanzlei zu erfassen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _akten.length,
                itemBuilder: (ctx, i) {
                  final a = _akten[i];
                  final status = raText(a['status']);
                  final farbe = statusFarbe(status);
                  final offeneFristen = int.tryParse(raText(a['fristen_offen'])) ?? 0;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: farbe.withValues(alpha: 0.15),
                        child: Icon(Icons.folder_special, color: farbe),
                      ),
                      title: Text(
                        raHat(a['aktenzeichen']) ? raText(a['aktenzeichen']) : '(ohne Aktenzeichen)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (raHat(a['bezeichnung'])) Text(raText(a['bezeichnung'])),
                        if (raHat(a['gegenseite']))
                          Text('gegen ${raText(a['gegenseite'])}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        const SizedBox(height: 2),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          _chip(statusText(status), farbe),
                          // Sagt der Status schon „Mahnverfahren", waere die
                          // zweite Plakette dasselbe Wort ein zweites Mal.
                          if (a['hat_mahnverfahren'] == true && status != 'mahnverfahren')
                            _chip('Mahnverfahren', Colors.deepOrange),
                          // Nur die dringenden zaehlen — eine Zahl, die auch
                          // ferne Termine mitzaehlt, wird nach einer Woche
                          // ignoriert.
                          if (offeneFristen > 0)
                            _chip('$offeneFristen Frist${offeneFristen == 1 ? '' : 'en'}', Colors.red),
                          if (a['vollmacht_aktiv'] == true) _chip('Vollmacht', Colors.green),
                          if (raHat(a['naechste_frist']))
                            _chip('bis ${raDatumDe(a['naechste_frist'])}', Colors.blueGrey),
                        ]),
                      ]),
                      isThreeLine: true,
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Bearbeiten',
                          onPressed: () => _bearbeiten(vorhanden: a),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          tooltip: 'Löschen',
                          onPressed: () => _loeschen(int.tryParse(raText(a['id'])) ?? 0),
                        ),
                      ]),
                      onTap: () => _oeffnen(a),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  static Widget _chip(String text, Color farbe) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: farbe.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: TextStyle(fontSize: 10, color: farbe)),
      );
}

// ─── Anlegen / Bearbeiten eines Aktenzeichens ─────────────────────────

class _RaAktenzeichenDialog extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  final Map<String, dynamic>? vorhanden;
  const _RaAktenzeichenDialog({required this.apiService, required this.vertragId, this.vorhanden});

  @override
  State<_RaAktenzeichenDialog> createState() => _RaAktenzeichenDialogState();
}

class _RaAktenzeichenDialogState extends State<_RaAktenzeichenDialog> {
  static const statusOptionen = [
    ('offen', 'Offen'),
    ('in_bearbeitung', 'In Bearbeitung'),
    ('aussergerichtlich', 'Außergerichtlich'),
    ('mahnverfahren', 'Mahnverfahren'),
    ('klageverfahren', 'Klageverfahren'),
    ('vergleich', 'Vergleich'),
    ('ruht', 'Ruht'),
    ('abgeschlossen', 'Abgeschlossen'),
    ('zurueckgewiesen', 'Zurückgewiesen'),
  ];

  late final TextEditingController _azC;
  late final TextEditingController _bezC;
  late final TextEditingController _gegenseiteC;
  late final TextEditingController _gegnerAnwaltC;
  late final TextEditingController _gegnerAzC;
  late final TextEditingController _gerichtC;
  late final TextEditingController _gerichtAzC;
  late final TextEditingController _streitwertC;
  late final TextEditingController _notizC;
  String _status = 'offen';
  DateTime? _eroeffnet;
  DateTime? _geschlossen;
  DateTime? _frist;
  bool _speichert = false;

  @override
  void initState() {
    super.initState();
    final e = widget.vorhanden ?? const <String, dynamic>{};
    _azC = TextEditingController(text: raText(e['aktenzeichen']));
    _bezC = TextEditingController(text: raText(e['bezeichnung']));
    _gegenseiteC = TextEditingController(text: raText(e['gegenseite']));
    _gegnerAnwaltC = TextEditingController(text: raText(e['gegner_anwalt']));
    _gegnerAzC = TextEditingController(text: raText(e['gegner_aktenzeichen']));
    _gerichtC = TextEditingController(text: raText(e['gericht']));
    _gerichtAzC = TextEditingController(text: raText(e['gericht_aktenzeichen']));
    _streitwertC = TextEditingController(text: raText(e['streitwert']));
    _notizC = TextEditingController(text: raText(e['notizen']));
    _status = raHat(e['status']) ? raText(e['status']) : 'offen';
    _eroeffnet = DateTime.tryParse(raText(e['eroeffnet_am']));
    _geschlossen = DateTime.tryParse(raText(e['geschlossen_am']));
    _frist = DateTime.tryParse(raText(e['naechste_frist']));
  }

  @override
  void dispose() {
    for (final c in [
      _azC, _bezC, _gegenseiteC, _gegnerAnwaltC, _gegnerAzC,
      _gerichtC, _gerichtAzC, _streitwertC, _notizC,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _datumWaehlen(DateTime? start, ValueChanged<DateTime?> gewaehlt) async {
    final d = await showDatePicker(
      context: context,
      initialDate: start ?? DateTime.now(),
      firstDate: DateTime(2010),
      lastDate: DateTime(2060),
    );
    if (d != null) gewaehlt(d);
  }

  Future<void> _speichern() async {
    if (_azC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Das Aktenzeichen darf nicht leer sein')),
      );
      return;
    }
    setState(() => _speichert = true);
    final res = await widget.apiService.saveVertragRaAktenzeichen(widget.vertragId, {
      if (widget.vorhanden != null) 'id': widget.vorhanden!['id'],
      'aktenzeichen': _azC.text.trim(),
      'bezeichnung': _bezC.text.trim(),
      'gegenseite': _gegenseiteC.text.trim(),
      'gegner_anwalt': _gegnerAnwaltC.text.trim(),
      'gegner_aktenzeichen': _gegnerAzC.text.trim(),
      'gericht': _gerichtC.text.trim(),
      'gericht_aktenzeichen': _gerichtAzC.text.trim(),
      'streitwert': _streitwertC.text.trim(),
      'notizen': _notizC.text.trim(),
      'status': _status,
      'eroeffnet_am': raIso(_eroeffnet),
      'geschlossen_am': raIso(_geschlossen),
      'naechste_frist': raIso(_frist),
    });
    if (!mounted) return;
    setState(() => _speichert = false);
    if (res['success'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(raText(res['message']).isEmpty ? 'Fehler' : raText(res['message'])), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final breite = MediaQuery.of(context).size.width;
    return AlertDialog(
      title: Text(widget.vorhanden == null ? 'Neues Aktenzeichen' : 'Aktenzeichen bearbeiten'),
      content: SizedBox(
        width: breite < 560 ? breite * 0.86 : 500,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _azC,
              autofocus: widget.vorhanden == null,
              decoration: const InputDecoration(
                  labelText: 'Aktenzeichen der Kanzlei *',
                  helperText: 'z. B. 142/26 MU',
                  prefixIcon: Icon(Icons.tag),
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bezC,
              decoration: const InputDecoration(
                  labelText: 'Bezeichnung', prefixIcon: Icon(Icons.label), border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _status,
              decoration: const InputDecoration(
                  labelText: 'Status', prefixIcon: Icon(Icons.flag), border: OutlineInputBorder()),
              items: statusOptionen.map((s) => DropdownMenuItem(value: s.$1, child: Text(s.$2))).toList(),
              onChanged: (v) => setState(() => _status = v ?? 'offen'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gegenseiteC,
              decoration: const InputDecoration(
                  labelText: 'Gegenseite', prefixIcon: Icon(Icons.groups), border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gegnerAnwaltC,
              decoration: const InputDecoration(
                  labelText: 'Anwalt der Gegenseite', prefixIcon: Icon(Icons.balance), border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gegnerAzC,
              decoration: const InputDecoration(
                  labelText: 'Aktenzeichen der Gegenseite', prefixIcon: Icon(Icons.numbers), border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _gerichtC,
                  decoration: const InputDecoration(
                      labelText: 'Gericht', prefixIcon: Icon(Icons.account_balance), border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _gerichtAzC,
                  decoration: const InputDecoration(labelText: 'Gerichts-Az.', border: OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _streitwertC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Streitwert / Forderung (€)', prefixIcon: Icon(Icons.euro), border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () => _datumWaehlen(_eroeffnet, (d) => setState(() => _eroeffnet = d)),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Eröffnet', prefixIcon: Icon(Icons.date_range), border: OutlineInputBorder()),
                    child: Text(_eroeffnet == null ? '—' : raDatumDe(raIso(_eroeffnet))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => _datumWaehlen(_frist, (d) => setState(() => _frist = d)),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Nächste Frist', prefixIcon: Icon(Icons.alarm), border: OutlineInputBorder()),
                    child: Text(_frist == null ? '—' : raDatumDe(raIso(_frist))),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _datumWaehlen(_geschlossen, (d) => setState(() => _geschlossen = d)),
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Geschlossen am', prefixIcon: Icon(Icons.event_available), border: OutlineInputBorder()),
                child: Text(_geschlossen == null ? '—' : raDatumDe(raIso(_geschlossen))),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notizC,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notizen', border: OutlineInputBorder()),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _speichert ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
        ElevatedButton.icon(
          onPressed: _speichert ? null : _speichern,
          icon: _speichert
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 16),
          label: const Text('Speichern'),
          style: ElevatedButton.styleFrom(backgroundColor: kRaFarbe, foregroundColor: Colors.white),
        ),
      ],
    );
  }
}
