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
  final String adminMitgliedernummer;
  const VertragRechtsanwaltTab({super.key, required this.apiService,
      required this.vertragId, this.adminMitgliedernummer = ''});

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
              adminMitgliedernummer: widget.adminMitgliedernummer,
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
    _gewaehlt = int.tryParse(raWert(m['rechtsanwalt_id']));
    _ansprechC = TextEditingController(text: raWert(m['ansprechpartner']));
    _telC = TextEditingController(text: raWert(m['telefon_durchwahl']));
    _emailC = TextEditingController(text: raWert(m['email_ansprechpartner']));
    _azC = TextEditingController(text: raWert(m['ra_aktenzeichen']));
    _gegenstandC = TextEditingController(text: raWert(m['gegenstand']));
    _rsvNameC = TextEditingController(text: raWert(m['rsv_name']));
    _rsvNrC = TextEditingController(text: raWert(m['rsv_schadennummer']));
    _notizC = TextEditingController(text: raWert(m['notizen']));
    _status = raHat(m['status']) ? raWert(m['status']) : 'kein_mandat';
    _rechtsschutz = raHat(m['rechtsschutz']) ? raWert(m['rechtsschutz']) : 'unbekannt';
    _seit = DateTime.tryParse(raWert(m['mandat_seit']));
    _bis = DateTime.tryParse(raWert(m['mandat_bis']));
    _kanzleienLaden();
  }

  @override
  void dispose() {
    for (final c in [_ansprechC, _telC, _emailC, _azC, _gegenstandC, _rsvNameC, _rsvNrC, _notizC]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Kanzlei anlegen oder aendern — und die frisch angelegte gleich
  /// auswaehlen, damit man nach dem Speichern nicht noch einmal suchen muss.
  Future<void> _kanzleiBearbeiten({Map<String, dynamic>? vorhanden}) async {
    final id = await showDialog<int>(
      context: context,
      builder: (ctx) => RaKanzleiDialog(apiService: widget.apiService, vorhanden: vorhanden),
    );
    if (id == null) return;
    await _kanzleienLaden();
    if (mounted) setState(() => _gewaehlt = id);
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
      content: Text(ok ? 'Mandat gespeichert (verschlüsselt)' : raWert(res['message']).isEmpty ? 'Fehler' : raWert(res['message'])),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    final gewaehlteKanzlei = _kanzleien.firstWhere(
      (e) => int.tryParse(raWert(e['id'])) == _gewaehlt,
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
        Row(children: [
          const Expanded(
            child: Text('Zuständiger Rechtsanwalt',
                style: TextStyle(fontWeight: FontWeight.bold, color: kRaFarbe)),
          ),
          TextButton.icon(
            icon: const Icon(Icons.person_add_alt, size: 16),
            label: const Text('Neu', style: TextStyle(fontSize: 12)),
            onPressed: () => _kanzleiBearbeiten(),
          ),
        ]),
        const SizedBox(height: 4),
        // ⚠️ Suchfeld statt Auswahlliste. Ein Aufklappmenü zwingt dazu,
        // erst zu wissen, wie die Kanzlei bei uns heißt — man sucht aber
        // nach dem Namen, den man vom Brief kennt, und das ist meist der
        // des Anwalts, nicht der der Kanzlei. Gesucht wird deshalb in
        // beidem, plus Ort und Fachgebiet.
        Autocomplete<Map<String, dynamic>>(
          key: ValueKey(_kanzleien.length),
          displayStringForOption: (k) => raWert(k['firmenname']),
          optionsBuilder: (eingabe) {
            final suche = eingabe.text.trim().toLowerCase();
            if (suche.isEmpty) return _kanzleien;
            return _kanzleien.where((k) => [
                  raWert(k['firmenname']),
                  raWert(k['anwalt_name']),
                  raWert(k['plz_ort']),
                  raWert(k['fachgebiete']),
                ].any((feld) => feld.toLowerCase().contains(suche)));
          },
          onSelected: (k) => setState(() => _gewaehlt = int.tryParse(raWert(k['id']))),
          fieldViewBuilder: (ctx, controller, focus, onSubmit) => TextField(
            controller: controller,
            focusNode: focus,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              hintText: 'Namen des Anwalts oder der Kanzlei eingeben…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'Auswahl aufheben',
                      onPressed: () {
                        controller.clear();
                        setState(() => _gewaehlt = null);
                      },
                    ),
            ),
          ),
          optionsViewBuilder: (ctx, onSelected, optionen) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 260,
                  maxWidth: MediaQuery.of(ctx).size.width - 64,
                ),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: optionen
                      .map((k) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.balance, size: 18, color: kRaFarbe),
                            title: Text(raWert(k['firmenname']),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              [raWert(k['anwalt_name']), raWert(k['plz_ort'])]
                                  .where((e) => e.isNotEmpty)
                                  .join(' · '),
                              style: const TextStyle(fontSize: 11),
                            ),
                            onTap: () => onSelected(k),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
        ),
        if (gewaehlteKanzlei.isNotEmpty) ...[
          const SizedBox(height: 12),
          _KanzleiKarte(
            kanzlei: gewaehlteKanzlei,
            onBearbeiten: () => _kanzleiBearbeiten(vorhanden: gewaehlteKanzlei),
          ),
        ] else if (_kanzleien.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('${_kanzleien.length} Kanzlei(en) hinterlegt — tippen Sie einen Namen '
              'oder öffnen Sie die Liste mit einem Klick ins Feld.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
        const SizedBox(height: 20),
        // ⚠️ Eingeklappt und hinter den Anwaltsdaten. Der Reiter heisst
        // „Zuständiger Rechtsanwalt" — dort gehoert der Anwalt hin, nicht
        // die Verwaltung des Mandats. In der ersten Fassung stand das
        // Mandat oben und fuellte den Schirm, waehrend die Daten des
        // Anwalts unsichtbar blieben.
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            initiallyExpanded: _status != 'kein_mandat',
            leading: const Icon(Icons.assignment_outlined, size: 20, color: kRaFarbe),
            title: const Text('Mandat und Rechtsschutz',
                style: TextStyle(fontWeight: FontWeight.bold, color: kRaFarbe, fontSize: 14)),
            subtitle: Text('Status, Laufzeit, Ansprechpartner — optional',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            children: [
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
            ],          // children der ExpansionTile
          ),            // ExpansionTile
        ),              // Theme
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _speichert ? null : _speichern,
            icon: _speichert
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 16),
            label: const Text('Zuordnung speichern'),
            style: ElevatedButton.styleFrom(backgroundColor: kRaFarbe, foregroundColor: Colors.white),
          ),
        ),
      ]),
    );
  }
}

class _KanzleiKarte extends StatelessWidget {
  final Map<String, dynamic> kanzlei;
  final VoidCallback? onBearbeiten;
  const _KanzleiKarte({required this.kanzlei, this.onBearbeiten});

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
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (raHat(kanzlei['firmenname']))
                Text(raWert(kanzlei['firmenname']),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              if (raHat(kanzlei['anwalt_name']))
                Text(raWert(kanzlei['anwalt_name']),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ]),
          ),
          if (onBearbeiten != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Daten der Kanzlei bearbeiten',
              onPressed: onBearbeiten,
            ),
        ]),
        const SizedBox(height: 6),
        if (raHat(kanzlei['strasse']) || raHat(kanzlei['plz_ort']))
          zeile(Icons.location_on, [raWert(kanzlei['strasse']), raWert(kanzlei['plz_ort'])].where((e) => e.isNotEmpty).join(', ')),
        if (raHat(kanzlei['telefon'])) zeile(Icons.phone, raWert(kanzlei['telefon'])),
        if (raHat(kanzlei['fax'])) zeile(Icons.fax, raWert(kanzlei['fax'])),
        if (raHat(kanzlei['email'])) zeile(Icons.email, raWert(kanzlei['email'])),
        if (raHat(kanzlei['website'])) zeile(Icons.language, raWert(kanzlei['website'])),
        if (raHat(kanzlei['fachgebiete'])) zeile(Icons.workspace_premium, raWert(kanzlei['fachgebiete'])),
        if (raHat(kanzlei['rechtsanwaltskammer'])) zeile(Icons.account_balance, raWert(kanzlei['rechtsanwaltskammer'])),
        // beA: der Weg, auf dem Schriftsaetze bei der Kanzlei ankommen,
        // ohne dass jemand einen Brief einwirft (§ 31a BRAO).
        if (raHat(kanzlei['bea_safe_id'])) zeile(Icons.mark_email_read, 'beA: ${raWert(kanzlei['bea_safe_id'])}'),
        if (raHat(kanzlei['rechtsform'])) zeile(Icons.business_center, raWert(kanzlei['rechtsform'])),
        // ⚠️ Mit Beschriftung: eine nackte Nummer wie „DE 252771644" ist
        // ohne sie nicht einzuordnen — im gerenderten Bild stand sie unter
        // der Anschrift und sah aus wie eine Kundennummer.
        if (raHat(kanzlei['ust_id'])) zeile(Icons.receipt_long, 'USt-IdNr.: ${raWert(kanzlei['ust_id'])}'),
        // ⚠️ Die Bankverbindung steht als eigener Block, abgesetzt und
        // beschriftet. Eine IBAN zwischen Telefon und Fax liest niemand als
        // Zahlungsziel — und genau darauf wird Geld überwiesen.
        if (raHat(kanzlei['iban'])) ...[
          const Divider(height: 14),
          Row(children: [
            Icon(Icons.account_balance_wallet, size: 13, color: Colors.indigo.shade400),
            const SizedBox(width: 6),
            Text('Bankverbindung',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: Colors.indigo.shade700)),
          ]),
          const SizedBox(height: 3),
          if (raHat(kanzlei['bank_inhaber']))
            zeile(Icons.account_box, raWert(kanzlei['bank_inhaber'])),
          // SelectableText über zeile() hinaus: eine IBAN wird abgetippt oder
          // kopiert, nie nur gelesen.
          Padding(
            padding: const EdgeInsets.only(left: 19, top: 1, bottom: 1),
            child: SelectableText('IBAN ${raIbanLesbar(raWert(kanzlei['iban']))}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
          ),
          if (raHat(kanzlei['bic']))
            Padding(
              padding: const EdgeInsets.only(left: 19, bottom: 1),
              child: SelectableText('BIC ${raWert(kanzlei['bic'])}',
                  style: const TextStyle(fontSize: 12, letterSpacing: 0.4)),
            ),
          if (raHat(kanzlei['bank_name'])) zeile(Icons.savings, raWert(kanzlei['bank_name'])),
          if (raHat(kanzlei['zahlungshinweis']))
            zeile(Icons.info_outline, raWert(kanzlei['zahlungshinweis'])),
        ],
        if (raHat(kanzlei['notizen'])) ...[
          const Divider(height: 14),
          Text(raWert(kanzlei['notizen']), style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        ],
      ]),
    );
  }
}

// ─── Unterreiter 2: Aktenzeichen ──────────────────────────────────────

class _RaAktenzeichenSubTab extends StatefulWidget {
  final ApiService apiService;
  final int vertragId;
  final Map<String, dynamic>? mandat;
  final String adminMitgliedernummer;
  const _RaAktenzeichenSubTab({required this.apiService, required this.vertragId,
      required this.mandat, this.adminMitgliedernummer = ''});

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
            adminMitgliedernummer: widget.adminMitgliedernummer,
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
                  final status = raWert(a['status']);
                  final farbe = statusFarbe(status);
                  final offeneFristen = int.tryParse(raWert(a['fristen_offen'])) ?? 0;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: farbe.withValues(alpha: 0.15),
                        child: Icon(Icons.folder_special, color: farbe),
                      ),
                      title: Text(
                        raHat(a['aktenzeichen']) ? raWert(a['aktenzeichen']) : '(ohne Aktenzeichen)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (raHat(a['bezeichnung'])) Text(raWert(a['bezeichnung'])),
                        if (raHat(a['gegenseite']))
                          Text('gegen ${raWert(a['gegenseite'])}',
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
                          onPressed: () => _loeschen(int.tryParse(raWert(a['id'])) ?? 0),
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
    _azC = TextEditingController(text: raWert(e['aktenzeichen']));
    _bezC = TextEditingController(text: raWert(e['bezeichnung']));
    _gegenseiteC = TextEditingController(text: raWert(e['gegenseite']));
    _gegnerAnwaltC = TextEditingController(text: raWert(e['gegner_anwalt']));
    _gegnerAzC = TextEditingController(text: raWert(e['gegner_aktenzeichen']));
    _gerichtC = TextEditingController(text: raWert(e['gericht']));
    _gerichtAzC = TextEditingController(text: raWert(e['gericht_aktenzeichen']));
    _streitwertC = TextEditingController(text: raWert(e['streitwert']));
    _notizC = TextEditingController(text: raWert(e['notizen']));
    _status = raHat(e['status']) ? raWert(e['status']) : 'offen';
    _eroeffnet = DateTime.tryParse(raWert(e['eroeffnet_am']));
    _geschlossen = DateTime.tryParse(raWert(e['geschlossen_am']));
    _frist = DateTime.tryParse(raWert(e['naechste_frist']));
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
        SnackBar(content: Text(raWert(res['message']).isEmpty ? 'Fehler' : raWert(res['message'])), backgroundColor: Colors.red),
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

// ═══════════════════════════════════════════════════════════════════════
// Kanzlei anlegen und pflegen — das Nachschlagewerk selbst
// ═══════════════════════════════════════════════════════════════════════

/// Die Daten des Anwalts, eingebbar aus der Anwendung.
///
/// ⚠️ Diese Angaben stehen im KLARTEXT in `rechtsanwalt_datenbank`, wie in
/// den 20 anderen Nachschlagewerken des Projekts. Das ist kein Versehen:
/// es sind öffentliche Berufsdaten — Name, Kanzleianschrift, Kammer — die
/// auf jedem Briefkopf und in jedem Impressum stehen. Verschlüsselt gehört,
/// was zum MITGLIED gehört: Aktenzeichen, Gegenseite, Forderungshöhe,
/// Korrespondenz. Die stehen in den anderen Tabellen und sind es auch.
class RaKanzleiDialog extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic>? vorhanden;
  const RaKanzleiDialog({super.key, required this.apiService, this.vorhanden});

  @override
  State<RaKanzleiDialog> createState() => _RaKanzleiDialogState();
}

class _RaKanzleiDialogState extends State<RaKanzleiDialog> {
  /// Feldschlüssel → (Beschriftung, Symbol, Hilfetext, Zeilen)
  static const felder = <(String, String, IconData, String, int)>[
    ('firmenname', 'Name der Kanzlei *', Icons.balance, 'z. B. Anwaltskanzlei Mumm', 1),
    ('anwalt_name', 'Rechtsanwältin / Rechtsanwalt', Icons.person,
        'Name samt Berufsbezeichnung, wie im Briefkopf', 1),
    ('strasse', 'Straße und Hausnummer', Icons.location_on, '', 1),
    ('plz_ort', 'PLZ und Ort', Icons.map, 'z. B. 50354 Hürth-Efferen', 1),
    ('telefon', 'Telefon', Icons.phone, '', 1),
    ('fax', 'Fax', Icons.fax, '', 1),
    ('email', 'E-Mail', Icons.email, '', 1),
    ('website', 'Website', Icons.language, '', 1),
    ('rechtsform', 'Rechtsform', Icons.business_center,
        'Einzelkanzlei, PartG mbB, Rechtsanwalts-GmbH …', 1),
    ('rechtsanwaltskammer', 'Rechtsanwaltskammer', Icons.account_balance,
        'zuständige Aufsicht (§ 73 BRAO)', 1),
    ('bea_safe_id', 'beA-SAFE-ID', Icons.mark_email_read,
        'besonderes elektronisches Anwaltspostfach (§ 31a BRAO)', 1),
    ('fachgebiete', 'Fachgebiete', Icons.workspace_premium,
        'Fachanwaltstitel oder Schwerpunkte', 2),
    ('ust_id', 'USt-IdNr.', Icons.receipt_long, '', 1),
    // ⚠️ Die Bankverbindung gehört NUR aus einem echten Schreiben hierher,
    // nie aus einer Websuche. Zwei im Netz gefundene IBANs für dieselbe
    // Stelle waren beide falsch — eine bei einer anderen Bank, eine in einer
    // anderen Stadt als die Quelle behauptete.
    ('bank_inhaber', 'Kontoinhaber', Icons.account_box,
        'wie im Schreiben — die IBAN allein sagt nicht, wem sie gehört', 1),
    ('iban', 'IBAN', Icons.account_balance_wallet,
        'wird beim Speichern auf die Prüfziffer geprüft', 1),
    ('bic', 'BIC', Icons.qr_code_2, '8 oder 11 Zeichen', 1),
    ('bank_name', 'Bank', Icons.savings, 'z. B. Postbank Essen', 1),
    ('zahlungshinweis', 'Zahlungshinweis', Icons.info_outline,
        'abweichender Verwendungszweck o. Ä.', 2),
    ('notizen', 'Notizen', Icons.note, 'Haftpflicht, Quelle der Daten, Besonderheiten', 3),
  ];

  final Map<String, TextEditingController> _c = {};
  bool _aktiv = true;
  bool _speichert = false;

  @override
  void initState() {
    super.initState();
    final v = widget.vorhanden ?? const <String, dynamic>{};
    for (final f in felder) {
      _c[f.$1] = TextEditingController(text: raWert(v[f.$1]));
    }
    _aktiv = v['aktiv'] == null || v['aktiv'] == 1 || v['aktiv'] == true;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _speichern() async {
    if (_c['firmenname']!.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Der Name der Kanzlei darf nicht leer sein')),
      );
      return;
    }
    setState(() => _speichert = true);
    final res = await widget.apiService.saveRechtsanwaltDatenbank({
      if (widget.vorhanden != null) 'id': widget.vorhanden!['id'],
      for (final f in felder) f.$1: _c[f.$1]!.text.trim(),
      'aktiv': _aktiv ? 1 : 0,
    });
    if (!mounted) return;
    setState(() => _speichert = false);
    if (res['success'] == true) {
      Navigator.pop(context, int.tryParse(raWert(res['id'])) ?? widget.vorhanden?['id'] as int?);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(raWert(res['message']).isEmpty ? 'Fehler' : raWert(res['message'])),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _loeschen() async {
    final id = int.tryParse(raWert(widget.vorhanden?['id'])) ?? 0;
    if (id <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kanzlei entfernen?'),
        content: const Text(
          'Wird die Kanzlei noch in einem Mandat geführt, wird sie nicht gelöscht, '
          'sondern nur auf inaktiv gesetzt — sonst verschwände die Zuordnung aus '
          'laufenden Akten, ohne dass es jemand sieht.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Entfernen', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await widget.apiService.deleteRechtsanwaltDatenbank(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(raWert(res['message']).isEmpty ? 'Entfernt' : raWert(res['message'])),
      backgroundColor: res['stillgelegt'] == true ? Colors.orange : Colors.green,
    ));
    Navigator.pop(context, null);
  }

  @override
  Widget build(BuildContext context) {
    final breite = MediaQuery.of(context).size.width;
    return AlertDialog(
      title: Text(widget.vorhanden == null ? 'Rechtsanwalt aufnehmen' : 'Daten des Rechtsanwalts'),
      content: SizedBox(
        width: breite < 600 ? breite * 0.88 : 540,
        height: MediaQuery.of(context).size.height * 0.66,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final f in felder) ...[
              TextField(
                controller: _c[f.$1],
                maxLines: f.$5,
                autofocus: f.$1 == 'firmenname' && widget.vorhanden == null,
                decoration: InputDecoration(
                  labelText: f.$2,
                  helperText: f.$4.isEmpty ? null : f.$4,
                  prefixIcon: Icon(f.$3, size: 18),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _aktiv,
              activeThumbColor: kRaFarbe,
              title: const Text('Aktiv', style: TextStyle(fontSize: 13)),
              subtitle: const Text('Nur aktive Kanzleien erscheinen in der Suche',
                  style: TextStyle(fontSize: 11)),
              onChanged: (v) => setState(() => _aktiv = v),
            ),
          ]),
        ),
      ),
      actions: [
        if (widget.vorhanden != null)
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
            label: const Text('Entfernen', style: TextStyle(color: Colors.red)),
            onPressed: _speichert ? null : _loeschen,
          ),
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
