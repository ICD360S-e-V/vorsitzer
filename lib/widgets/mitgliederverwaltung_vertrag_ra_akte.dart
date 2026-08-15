import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/signatur_service.dart';
import '../utils/ra_antwort.dart';
import '../utils/file_picker_helper.dart';
import 'file_viewer_dialog.dart';
import 'mitgliederverwaltung_vertrag_rechtsanwalt.dart';
import 'phone_link.dart';

/// Der Aktendeckel: Details · Korrespondenz · Mahnverfahren · Vollmacht.
///
/// ⚠️ Fristen und Rechtstexte werden hier NICHT gebildet. Sie kommen fertig
/// vom Server (api/helpers/ra_recht_lib.php) und werden nur dargestellt.
/// Eine zweite Fassung derselben Frist im Client ist eine zweite Wahrheit,
/// und die falsche faellt erst auf, wenn eine Notfrist verstrichen ist.
class RaAktenzeichenDetailDialog extends StatelessWidget {
  final ApiService apiService;
  final int vertragId;
  final Map<String, dynamic> akte;
  final Map<String, dynamic>? mandat;
  final String adminMitgliedernummer;
  final VoidCallback onChanged;

  const RaAktenzeichenDetailDialog({
    super.key,
    required this.apiService,
    required this.vertragId,
    required this.akte,
    required this.mandat,
    required this.onChanged,
    this.adminMitgliedernummer = '',
  });

  @override
  Widget build(BuildContext context) {
    final akzId = int.tryParse(akte['id']?.toString() ?? '') ?? 0;
    return DefaultTabController(
      length: 4,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: kRaFarbe,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            const Icon(Icons.folder_special, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(
                  akte['aktenzeichen']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                if ((akte['bezeichnung']?.toString() ?? '').isNotEmpty)
                  Text(
                    akte['bezeichnung'].toString(),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
              ]),
            ),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        const TabBar(
          isScrollable: true,
          labelColor: kRaFarbe,
          indicatorColor: kRaFarbe,
          tabs: [
            Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
            Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
            Tab(icon: Icon(Icons.gavel, size: 18), text: 'Mahnverfahren'),
            Tab(icon: Icon(Icons.assignment_ind, size: 18), text: 'Vollmacht'),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            _RaDetailsTab(apiService: apiService, akte: akte, mandat: mandat),
            _RaKorrTab(apiService: apiService, aktenzeichenId: akzId),
            _RaMahnverfahrenTab(apiService: apiService, aktenzeichenId: akzId, onChanged: onChanged),
            _RaVollmachtTab(apiService: apiService, akte: akte, mandat: mandat,
                adminMitgliedernummer: adminMitgliedernummer, onChanged: onChanged),
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 1. Details
// ═══════════════════════════════════════════════════════════════════════

class _RaDetailsTab extends StatelessWidget {
  final ApiService apiService;
  final Map<String, dynamic> akte;
  final Map<String, dynamic>? mandat;
  const _RaDetailsTab({required this.apiService, required this.akte, required this.mandat});

  @override
  Widget build(BuildContext context) {
    final akzId = int.tryParse(raWert(akte['id'])) ?? 0;
    final kanzlei = (mandat?['kanzlei'] is Map)
        ? Map<String, dynamic>.from(mandat!['kanzlei'] as Map)
        : const <String, dynamic>{};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _Ueberschrift('Akte'),
        _Zeile(Icons.tag, 'Aktenzeichen', raWert(akte['aktenzeichen'])),
        _Zeile(Icons.label, 'Bezeichnung', raWert(akte['bezeichnung'])),
        _Zeile(Icons.flag, 'Status', raWert(akte['status'])),
        _Zeile(Icons.euro, 'Streitwert / Forderung', raHat(akte['streitwert']) ? '${raWert(akte['streitwert'])} €' : ''),
        _Zeile(Icons.date_range, 'Eröffnet', raDatumDe(akte['eroeffnet_am'])),
        _Zeile(Icons.alarm, 'Nächste Frist', raDatumDe(akte['naechste_frist'])),
        _Zeile(Icons.event_available, 'Geschlossen', raDatumDe(akte['geschlossen_am'])),
        const SizedBox(height: 12),
        const _Ueberschrift('Gegenseite'),
        _Zeile(Icons.groups, 'Gegenseite', raWert(akte['gegenseite'])),
        _Zeile(Icons.balance, 'Anwalt der Gegenseite', raWert(akte['gegner_anwalt'])),
        _Zeile(Icons.numbers, 'Deren Aktenzeichen', raWert(akte['gegner_aktenzeichen'])),
        const SizedBox(height: 12),
        const _Ueberschrift('Gericht'),
        _Zeile(Icons.account_balance, 'Gericht', raWert(akte['gericht'])),
        _Zeile(Icons.numbers, 'Gerichts-Aktenzeichen', raWert(akte['gericht_aktenzeichen'])),
        if (kanzlei.isNotEmpty) ...[
          const SizedBox(height: 12),
          const _Ueberschrift('Bearbeitende Kanzlei'),
          _Zeile(Icons.business, 'Kanzlei', raWert(kanzlei['firmenname'])),
          _Zeile(Icons.person, 'Sachbearbeitung', raWert(kanzlei['anwalt_name'])),
          _Zeile(Icons.phone, 'Telefon', raWert(kanzlei['telefon'])),
          _Zeile(Icons.email, 'E-Mail', raWert(kanzlei['email'])),
        ],
        if (raHat(akte['notizen'])) ...[
          const SizedBox(height: 12),
          const _Ueberschrift('Notizen'),
          Text(raWert(akte['notizen']), style: const TextStyle(fontSize: 13)),
        ],
        const SizedBox(height: 20),
        const _Ueberschrift('Dokumente zur Akte'),
        const SizedBox(height: 4),
        SizedBox(
          height: 260,
          child: RaDokumente(
            apiService: apiService,
            bereich: 'akte',
            parentId: akzId,
            hinweis: 'Alles, was zur Akte gehört und nicht einer einzelnen Korrespondenz '
                'zuzuordnen ist: Verträge, Rechnungen, Bescheide, Abschriften aus der Handakte.',
          ),
        ),
      ]),
    );
  }
}

class _Ueberschrift extends StatelessWidget {
  final String text;
  const _Ueberschrift(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: kRaFarbe, fontSize: 13)),
      );
}

class _Zeile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String wert;
  const _Zeile(this.icon, this.label, this.wert);

  @override
  Widget build(BuildContext context) {
    if (wert.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(
          width: 150,
          child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ),
        // ⚠️ phoneAwareText statt Text: hinter Icons.phone stand die Nummer
        // der Kanzlei als toter Text. Gefunden von rufnummern_waehlbar_test —
        // und das ist genau der Fall, fuer den es die Fernwahl gibt.
        // Bei allen anderen Icons verhaelt es sich wie ein gewoehnlicher Text.
        Expanded(child: phoneAwareText(icon, wert, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 2. Korrespondenz
// ═══════════════════════════════════════════════════════════════════════

class _RaKorrTab extends StatefulWidget {
  final ApiService apiService;
  final int aktenzeichenId;
  const _RaKorrTab({required this.apiService, required this.aktenzeichenId});

  @override
  State<_RaKorrTab> createState() => _RaKorrTabState();
}

class _RaKorrTabState extends State<_RaKorrTab> {
  List<Map<String, dynamic>> _eintraege = [];
  bool _geladen = false;

  static const medien = [
    ('brief', 'Brief', Icons.markunread_mailbox),
    ('email', 'E-Mail', Icons.email),
    ('telefon', 'Telefon', Icons.phone),
    ('fax', 'Fax', Icons.fax),
    ('bea', 'beA', Icons.mark_email_read),
    ('persoenlich', 'Persönlich', Icons.people),
    ('sonstiges', 'Sonstiges', Icons.more_horiz),
  ];

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final res = await widget.apiService.listVertragRaKorrespondenz(widget.aktenzeichenId);
    if (!mounted) return;
    setState(() {
      _eintraege = raListe(res);
      _geladen = true;
    });
  }

  Future<void> _bearbeiten({Map<String, dynamic>? vorhanden}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _RaKorrDialog(
        apiService: widget.apiService,
        aktenzeichenId: widget.aktenzeichenId,
        vorhanden: vorhanden,
      ),
    );
    if (ok == true) _laden();
  }

  Future<void> _loeschen(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: const Text('Auch die angehängten Dateien werden entfernt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Löschen', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await widget.apiService.deleteVertragRaKorrespondenz(id);
    _laden();
  }

  void _anhaenge(Map<String, dynamic> eintrag) {
    final breite = MediaQuery.of(context).size.width;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: breite < 620 ? breite * 0.92 : 560,
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: kRaFarbe,
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(children: [
                const Icon(Icons.attach_file, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    raHat(eintrag['betreff']) ? raWert(eintrag['betreff']) : 'Anhänge',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            Expanded(
              child: RaDokumente(
                apiService: widget.apiService,
                bereich: 'korr',
                parentId: int.tryParse(raWert(eintrag['id'])) ?? 0,
                hinweis: 'Schriftstücke zu genau diesem Vorgang.',
              ),
            ),
          ]),
        ),
      ),
    ).then((_) => _laden());
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          const Icon(Icons.mail, size: 18, color: kRaFarbe),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${_eintraege.length} Vorgang/Vorgänge',
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
        child: _eintraege.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.mail_outline, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('Noch keine Korrespondenz', style: TextStyle(color: Colors.grey.shade600)),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _eintraege.length,
                itemBuilder: (ctx, i) {
                  final k = _eintraege[i];
                  final eingehend = raWert(k['richtung']) != 'ausgehend';
                  final medium = medien.firstWhere(
                    (m) => m.$1 == raWert(k['medium']),
                    orElse: () => medien.last,
                  );
                  final anhaenge = int.tryParse(raWert(k['anhaenge'])) ?? 0;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (eingehend ? Colors.blue : Colors.green).withValues(alpha: 0.15),
                        child: Icon(
                          eingehend ? Icons.call_received : Icons.call_made,
                          color: eingehend ? Colors.blue : Colors.green,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        raHat(k['betreff']) ? raWert(k['betreff']) : '(ohne Betreff)',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (raHat(k['text']))
                          Text(raWert(k['text']), maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 2),
                        Wrap(spacing: 8, runSpacing: 2, children: [
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(medium.$3, size: 12, color: Colors.grey.shade600),
                            const SizedBox(width: 3),
                            Text(medium.$2, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                          ]),
                          Text(raDatumDe(k['datum']), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                          if (k['erledigt'] == 1 || k['erledigt'] == true)
                            const Text('erledigt', style: TextStyle(fontSize: 10, color: Colors.green)),
                          if (anhaenge > 0)
                            Text('$anhaenge Anhang/Anhänge',
                                style: const TextStyle(fontSize: 10, color: kRaFarbe)),
                        ]),
                      ]),
                      isThreeLine: true,
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.attach_file, size: 18),
                          tooltip: 'Anhänge',
                          onPressed: () => _anhaenge(k),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Bearbeiten',
                          onPressed: () => _bearbeiten(vorhanden: k),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          tooltip: 'Löschen',
                          onPressed: () => _loeschen(int.tryParse(raWert(k['id'])) ?? 0),
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class _RaKorrDialog extends StatefulWidget {
  final ApiService apiService;
  final int aktenzeichenId;
  final Map<String, dynamic>? vorhanden;
  const _RaKorrDialog({required this.apiService, required this.aktenzeichenId, this.vorhanden});

  @override
  State<_RaKorrDialog> createState() => _RaKorrDialogState();
}

class _RaKorrDialogState extends State<_RaKorrDialog> {
  late final TextEditingController _betreffC;
  late final TextEditingController _textC;
  late final TextEditingController _partnerC;
  late final TextEditingController _notizC;
  String _richtung = 'eingehend';
  String _medium = 'brief';
  bool _erledigt = false;
  DateTime _datum = DateTime.now();
  bool _speichert = false;

  @override
  void initState() {
    super.initState();
    final e = widget.vorhanden ?? const <String, dynamic>{};
    _betreffC = TextEditingController(text: raWert(e['betreff']));
    _textC = TextEditingController(text: raWert(e['text']));
    _partnerC = TextEditingController(text: raWert(e['gespraechspartner']));
    _notizC = TextEditingController(text: raWert(e['notizen']));
    _richtung = raHat(e['richtung']) ? raWert(e['richtung']) : 'eingehend';
    _medium = raHat(e['medium']) ? raWert(e['medium']) : 'brief';
    _erledigt = e['erledigt'] == 1 || e['erledigt'] == true;
    _datum = DateTime.tryParse(raWert(e['datum'])) ?? DateTime.now();
  }

  @override
  void dispose() {
    for (final c in [_betreffC, _textC, _partnerC, _notizC]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _speichern() async {
    setState(() => _speichert = true);
    final res = await widget.apiService.saveVertragRaKorrespondenz(widget.aktenzeichenId, {
      if (widget.vorhanden != null) 'id': widget.vorhanden!['id'],
      'datum': raIso(_datum),
      'richtung': _richtung,
      'medium': _medium,
      'erledigt': _erledigt ? 1 : 0,
      'betreff': _betreffC.text.trim(),
      'text': _textC.text.trim(),
      'gespraechspartner': _partnerC.text.trim(),
      'notizen': _notizC.text.trim(),
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
      title: Text(widget.vorhanden == null ? 'Neuer Vorgang' : 'Vorgang bearbeiten'),
      content: SizedBox(
        width: breite < 560 ? breite * 0.86 : 500,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _datum,
                      firstDate: DateTime(2010),
                      lastDate: DateTime(2060),
                    );
                    if (d != null) setState(() => _datum = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Datum', prefixIcon: Icon(Icons.event), border: OutlineInputBorder(), isDense: true),
                    child: Text(raDatumDe(raIso(_datum))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _richtung,
                  decoration: const InputDecoration(labelText: 'Richtung', border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'eingehend', child: Text('Eingehend')),
                    DropdownMenuItem(value: 'ausgehend', child: Text('Ausgehend')),
                  ],
                  onChanged: (v) => setState(() => _richtung = v ?? 'eingehend'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _medium,
              decoration: const InputDecoration(labelText: 'Medium', border: OutlineInputBorder(), isDense: true),
              items: _RaKorrTabState.medien
                  .map((m) => DropdownMenuItem(
                        value: m.$1,
                        child: Row(children: [
                          Icon(m.$3, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Text(m.$2),
                        ]),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _medium = v ?? 'brief'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _betreffC,
              decoration: const InputDecoration(labelText: 'Betreff', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _partnerC,
              decoration: const InputDecoration(
                  labelText: 'Gesprächspartner', prefixIcon: Icon(Icons.person), border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textC,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Inhalt', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notizC,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notizen', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _erledigt,
              title: const Text('Erledigt', style: TextStyle(fontSize: 13)),
              onChanged: (v) => setState(() => _erledigt = v ?? false),
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
// 3. Mahnverfahren
// ═══════════════════════════════════════════════════════════════════════

class _RaMahnverfahrenTab extends StatefulWidget {
  final ApiService apiService;
  final int aktenzeichenId;
  final VoidCallback onChanged;
  const _RaMahnverfahrenTab({required this.apiService, required this.aktenzeichenId, required this.onChanged});

  @override
  State<_RaMahnverfahrenTab> createState() => _RaMahnverfahrenTabState();
}

class _RaMahnverfahrenTabState extends State<_RaMahnverfahrenTab> {
  Map<String, dynamic> _stufen = {};
  List<Map<String, dynamic>> _fristen = const [];
  String _vorbehalt = '';
  bool _geladen = false;
  bool _speichert = false;

  String _rolle = 'antragsgegner';
  String _stufe = 'kein';
  String _wspUmfang = 'kein';
  bool _ausland = false;
  bool _erledigt = false;
  final Map<String, DateTime?> _datum = {};

  late final TextEditingController _mahngerichtC;
  late final TextEditingController _gzC;
  late final TextEditingController _antragstellerC;
  late final TextEditingController _hauptC;
  late final TextEditingController _zinsenC;
  late final TextEditingController _kostenC;
  late final TextEditingController _wspBegrC;
  late final TextEditingController _notizC;

  /// Die Datumsfelder in der Reihenfolge des Verfahrens.
  static const felder = [
    ('mb_beantragt_am', 'Mahnbescheid beantragt', '§ 690 ZPO'),
    ('mb_erlassen_am', 'Mahnbescheid erlassen', ''),
    ('mb_zugestellt_am', 'Mahnbescheid zugestellt', '§ 693 ZPO — Fristbeginn'),
    ('widerspruch_am', 'Widerspruch eingelegt', '§ 694 ZPO'),
    ('vb_beantragt_am', 'Vollstreckungsbescheid beantragt', '§ 699 ZPO'),
    ('vb_erlassen_am', 'Vollstreckungsbescheid erlassen', ''),
    ('vb_zugestellt_am', 'Vollstreckungsbescheid zugestellt', '§ 700 ZPO — Fristbeginn'),
    ('einspruch_am', 'Einspruch eingelegt', '§ 700 i.V.m. § 338 ZPO'),
    ('abgabe_am', 'Abgabe an das Streitgericht', '§ 696 ZPO'),
    ('vollstreckung_am', 'Zwangsvollstreckung begonnen', '§ 794 Abs. 1 Nr. 4 ZPO'),
  ];

  @override
  void initState() {
    super.initState();
    _mahngerichtC = TextEditingController();
    _gzC = TextEditingController();
    _antragstellerC = TextEditingController();
    _hauptC = TextEditingController();
    _zinsenC = TextEditingController();
    _kostenC = TextEditingController();
    _wspBegrC = TextEditingController();
    _notizC = TextEditingController();
    _laden();
  }

  @override
  void dispose() {
    for (final c in [_mahngerichtC, _gzC, _antragstellerC, _hauptC, _zinsenC, _kostenC, _wspBegrC, _notizC]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _laden() async {
    final res = await widget.apiService.getVertragRaMahnverfahren(widget.aktenzeichenId);
    if (!mounted) return;
    final d = (res['data'] is Map) ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
    setState(() {
      _stufen = (res['stufen'] is Map) ? Map<String, dynamic>.from(res['stufen'] as Map) : {};
      _fristen = raListe(res, 'fristen');
      _vorbehalt = raWert(res['vorbehalt']);
      _rolle = raHat(d['rolle']) ? raWert(d['rolle']) : 'antragsgegner';
      _stufe = raHat(d['stufe']) ? raWert(d['stufe']) : 'kein';
      _wspUmfang = raHat(d['widerspruch_umfang']) ? raWert(d['widerspruch_umfang']) : 'kein';
      _ausland = d['zustellung_ausland'] == 1 || d['zustellung_ausland'] == true;
      _erledigt = d['erledigt'] == 1 || d['erledigt'] == true;
      for (final f in felder) {
        _datum[f.$1] = DateTime.tryParse(raWert(d[f.$1]));
      }
      _mahngerichtC.text = raWert(d['mahngericht']);
      _gzC.text = raWert(d['gz_mahngericht']);
      _antragstellerC.text = raWert(d['antragsteller']);
      _hauptC.text = raWert(d['hauptforderung']);
      _zinsenC.text = raWert(d['zinsen']);
      _kostenC.text = raWert(d['kosten']);
      _wspBegrC.text = raWert(d['widerspruch_begruendung']);
      _notizC.text = raWert(d['notizen']);
      _geladen = true;
    });
  }

  Future<void> _speichern() async {
    setState(() => _speichert = true);
    final res = await widget.apiService.saveVertragRaMahnverfahren(widget.aktenzeichenId, {
      'rolle': _rolle,
      'stufe': _stufe,
      'widerspruch_umfang': _wspUmfang,
      'zustellung_ausland': _ausland ? 1 : 0,
      'erledigt': _erledigt ? 1 : 0,
      for (final f in felder) f.$1: raIso(_datum[f.$1]),
      'mahngericht': _mahngerichtC.text.trim(),
      'gz_mahngericht': _gzC.text.trim(),
      'antragsteller': _antragstellerC.text.trim(),
      'hauptforderung': _hauptC.text.trim(),
      'zinsen': _zinsenC.text.trim(),
      'kosten': _kostenC.text.trim(),
      'widerspruch_begruendung': _wspBegrC.text.trim(),
      'notizen': _notizC.text.trim(),
    });
    if (!mounted) return;
    setState(() => _speichert = false);
    final ok = res['success'] == true;
    if (ok) {
      // Die frisch gerechneten Fristen kommen mit der Antwort zurueck —
      // sie werden uebernommen, nicht selbst abgeleitet.
      setState(() {
        _fristen = raListe(res, 'fristen');
        _vorbehalt = raWert(res['vorbehalt']).isEmpty ? _vorbehalt : raWert(res['vorbehalt']);
      });
      widget.onChanged();
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Mahnverfahren gespeichert' : (raWert(res['message']).isEmpty ? 'Fehler' : raWert(res['message']))),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
  }

  Future<void> _datumWaehlen(String schluessel) async {
    final d = await showDatePicker(
      context: context,
      initialDate: _datum[schluessel] ?? DateTime.now(),
      firstDate: DateTime(2010),
      lastDate: DateTime(2060),
    );
    if (d != null) setState(() => _datum[schluessel] = d);
  }

  static Color _dringlichkeitsFarbe(String d) => switch (d) {
        'abgelaufen' => Colors.red,
        'heute' => Colors.deepOrange,
        'bald' => Colors.orange,
        'erledigt' => Colors.green,
        'offen' => Colors.blue,
        _ => Colors.grey,
      };

  static String _dringlichkeitsText(Map<String, dynamic> f) {
    final tage = int.tryParse(raWert(f['tage']));
    return switch (raWert(f['dringlichkeit'])) {
      'erledigt' => 'erledigt',
      'abgelaufen' => tage == null ? 'abgelaufen' : 'seit ${-tage} Tag(en) abgelaufen',
      'heute' => 'heute',
      'bald' => 'in $tage Tag(en)',
      'offen' => 'in $tage Tag(en)',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Rolle: das Feld, an dem alles haengt ──────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Stellung des Mitglieds im Verfahren',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              ChoiceChip(
                label: const Text('Antragsgegner (Schuldner)', style: TextStyle(fontSize: 11)),
                selected: _rolle == 'antragsgegner',
                onSelected: (_) => setState(() => _rolle = 'antragsgegner'),
              ),
              ChoiceChip(
                label: const Text('Antragsteller (Gläubiger)', style: TextStyle(fontSize: 11)),
                selected: _rolle == 'antragsteller',
                onSelected: (_) => setState(() => _rolle = 'antragsteller'),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              _rolle == 'antragsgegner'
                  ? 'Die Notfristen der §§ 692, 700 ZPO laufen gegen das Mitglied.'
                  : 'Gegen das Mitglied läuft keine Notfrist; maßgeblich ist die Sechsmonatsfrist des § 701 ZPO.',
              style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Fristen ──────────────────────────────────────────────────
        if (_fristen.isNotEmpty) ...[
          const Text('Fristen', style: TextStyle(fontWeight: FontWeight.bold, color: kRaFarbe)),
          const SizedBox(height: 6),
          ..._fristen.map((f) {
            final farbe = _dringlichkeitsFarbe(raWert(f['dringlichkeit']));
            final notfrist = f['notfrist'] == true;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: farbe.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: farbe.withValues(alpha: 0.4)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(notfrist ? Icons.gpp_maybe : Icons.schedule, size: 16, color: farbe),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(raWert(f['titel']),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: farbe)),
                  ),
                  if (notfrist)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: farbe, borderRadius: BorderRadius.circular(3)),
                      child: const Text('NOTFRIST',
                          style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Text(raDatumDe(f['datum']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  Text(_dringlichkeitsText(f), style: TextStyle(fontSize: 12, color: farbe)),
                ]),
                Text('${raWert(f['norm'])} · ab ${raDatumDe(f['ab'])} (${raWert(f['ab_label'])})',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
                if (raHat(f['hinweis'])) ...[
                  const SizedBox(height: 4),
                  Text(raWert(f['hinweis']), style: const TextStyle(fontSize: 11)),
                ],
              ]),
            );
          }),
          if (_vorbehalt.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 13, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(child: Text(_vorbehalt, style: TextStyle(fontSize: 10, color: Colors.grey.shade700))),
              ]),
            ),
        ] else
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Keine Frist berechenbar. Sobald ein Zustellungsdatum erfasst ist, '
                  'erscheinen die Fristen hier.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ),
            ]),
          ),

        // ── Stufe ────────────────────────────────────────────────────
        const Text('Stand des Verfahrens', style: TextStyle(fontWeight: FontWeight.bold, color: kRaFarbe)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _stufen.containsKey(_stufe) ? _stufe : 'kein',
          decoration: const InputDecoration(
              labelText: 'Stufe', prefixIcon: Icon(Icons.stairs), border: OutlineInputBorder(), isDense: true),
          items: _stufen.entries.map((e) {
            final wert = (e.value is Map) ? Map<String, dynamic>.from(e.value as Map) : const <String, dynamic>{};
            final norm = raWert(wert['norm']);
            return DropdownMenuItem(
              value: e.key,
              child: Text(norm.isEmpty ? raWert(wert['label']) : '${raWert(wert['label'])}  ($norm)',
                  overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (v) => setState(() => _stufe = v ?? 'kein'),
        ),
        const SizedBox(height: 16),

        // ── Daten des Verfahrens ─────────────────────────────────────
        const Text('Verfahrensdaten', style: TextStyle(fontWeight: FontWeight.bold, color: kRaFarbe)),
        const SizedBox(height: 6),
        TextField(
          controller: _mahngerichtC,
          decoration: const InputDecoration(
              labelText: 'Mahngericht',
              helperText: 'zentrales Mahngericht des Bundeslandes',
              prefixIcon: Icon(Icons.account_balance),
              border: OutlineInputBorder(),
              isDense: true),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _gzC,
              decoration: const InputDecoration(
                  labelText: 'Geschäftszeichen', prefixIcon: Icon(Icons.tag), border: OutlineInputBorder(), isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _antragstellerC,
              decoration: const InputDecoration(
                  labelText: 'Antragsteller', prefixIcon: Icon(Icons.groups), border: OutlineInputBorder(), isDense: true),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _hauptC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Hauptforderung (€)', border: OutlineInputBorder(), isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _zinsenC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Zinsen (€)', border: OutlineInputBorder(), isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _kostenC,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Kosten (€)', border: OutlineInputBorder(), isDense: true),
            ),
          ),
        ]),
        const SizedBox(height: 16),

        // ── Datumsfelder ─────────────────────────────────────────────
        const Text('Ablauf', style: TextStyle(fontWeight: FontWeight.bold, color: kRaFarbe)),
        const SizedBox(height: 6),
        ...felder.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _datumWaehlen(f.$1),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: f.$2,
                    helperText: f.$3.isEmpty ? null : f.$3,
                    prefixIcon: const Icon(Icons.event, size: 18),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _datum[f.$1] == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            tooltip: 'Datum entfernen',
                            onPressed: () => setState(() => _datum[f.$1] = null),
                          ),
                  ),
                  child: Text(_datum[f.$1] == null ? '—' : raDatumDe(raIso(_datum[f.$1]))),
                ),
              ),
            )),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _wspUmfang,
          decoration: const InputDecoration(
              labelText: 'Umfang des Widerspruchs', border: OutlineInputBorder(), isDense: true),
          items: const [
            DropdownMenuItem(value: 'kein', child: Text('Kein Widerspruch')),
            DropdownMenuItem(value: 'voll', child: Text('Gegen den gesamten Anspruch')),
            DropdownMenuItem(value: 'teil', child: Text('Nur gegen einen Teil')),
          ],
          onChanged: (v) => setState(() => _wspUmfang = v ?? 'kein'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _wspBegrC,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Begründung des Widerspruchs',
            helperText: 'Der Widerspruch selbst braucht keine Begründung (§ 694 ZPO) — '
                'was hier steht, ist die Vorbereitung für die Kanzlei.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _ausland,
          title: const Text('Im Ausland zugestellt', style: TextStyle(fontSize: 13)),
          subtitle: const Text('§ 339 Abs. 2 ZPO: Einspruchsfrist ein Monat statt zwei Wochen',
              style: TextStyle(fontSize: 11)),
          onChanged: (v) => setState(() => _ausland = v ?? false),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _erledigt,
          title: const Text('Verfahren erledigt', style: TextStyle(fontSize: 13)),
          onChanged: (v) => setState(() => _erledigt = v ?? false),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notizC,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Notizen', border: OutlineInputBorder()),
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
        const SizedBox(height: 20),
        const Text('Dokumente zum Mahnverfahren',
            style: TextStyle(fontWeight: FontWeight.bold, color: kRaFarbe, fontSize: 13)),
        const SizedBox(height: 4),
        SizedBox(
          height: 260,
          child: RaDokumente(
            apiService: widget.apiService,
            bereich: 'mahn',
            parentId: widget.aktenzeichenId,
            hinweis: 'Mahnbescheid, Vollstreckungsbescheid, Zustellungsurkunden, '
                'Widerspruchs- und Einspruchsschreiben.',
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 4. Vollmacht
// ═══════════════════════════════════════════════════════════════════════

class _RaVollmachtTab extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> akte;
  final Map<String, dynamic>? mandat;
  final String adminMitgliedernummer;
  final VoidCallback onChanged;
  const _RaVollmachtTab({
    required this.apiService,
    required this.akte,
    required this.mandat,
    required this.onChanged,
    this.adminMitgliedernummer = '',
  });

  @override
  State<_RaVollmachtTab> createState() => _RaVollmachtTabState();
}

class _RaVollmachtTabState extends State<_RaVollmachtTab> {
  List<Map<String, dynamic>> _vollmachten = [];
  bool _geladen = false;
  bool _stelltZu = false;

  int get _akzId => int.tryParse(raWert(widget.akte['id'])) ?? 0;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  /// Signaturvorgänge je Vollmacht-Id — der Stand kommt aus dem
  /// Unterschriften-System, nicht aus einem Feld, das jemand von Hand setzt.
  Map<int, List<Signaturvorgang>> _signaturen = {};

  Future<void> _laden() async {
    final res = await widget.apiService.listVertragRaVollmachten(_akzId);
    if (!mounted) return;
    final liste = raListe(res);

    // ⚠️ Nur laden, wenn wir wissen, wer fragt: der Endpunkt verlangt die
    // Mitgliedsnummer des Anfordernden als Identitätsnachweis. Fehlt sie,
    // bleibt die Liste eben ohne Unterschriftsstand — lieber keine Angabe
    // als eine erfundene.
    final vorgaenge = <int, List<Signaturvorgang>>{};
    final mitgliedId = int.tryParse(raWert(liste.isEmpty ? '' : liste.first['user_id'])) ?? 0;
    if (widget.adminMitgliedernummer.isNotEmpty && mitgliedId > 0) {
      final alle = await SignaturService().liste(
        callerMitgliedernummer: widget.adminMitgliedernummer,
        userId: mitgliedId,
      );
      for (final v in alle) {
        if (v.quelleTabelle != 'vertrag_ra_vollmacht' || v.quelleId == null) continue;
        vorgaenge.putIfAbsent(v.quelleId!, () => []).add(v);
      }
    }

    if (!mounted) return;
    setState(() {
      _vollmachten = liste;
      _signaturen = vorgaenge;
      _geladen = true;
    });
  }

  Future<void> _erzeugen() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _RaVollmachtErzeugenDialog(
        apiService: widget.apiService,
        aktenzeichenId: _akzId,
        akte: widget.akte,
        mandat: widget.mandat,
      ),
    );
    if (ok == true) {
      _laden();
      widget.onChanged();
    }
  }

  Future<void> _oeffnen(Map<String, dynamic> v, {String? typ}) async {
    final id = int.tryParse(raWert(v['id'])) ?? 0;
    try {
      final resp = await widget.apiService.downloadVertragRaVollmachtPdf(id, typ: typ);
      if (!mounted) return;
      if (resp.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF nicht abrufbar (HTTP ${resp.statusCode})'), backgroundColor: Colors.red),
        );
        return;
      }
      final name = typ == 'uebersetzung'
          ? 'vollmacht_${raWert(v['uebersetzung_sprache'])}_$id.pdf'
          : (raWert(v['pdf_filename']).isEmpty ? 'vollmacht_$id.pdf' : raWert(v['pdf_filename']));

      // Nur beim Leseexemplar: das Mitglied soll es in seiner Sprache im
      // Chat haben. Die deutsche Fassung geht an die Kanzlei, nicht an das
      // Mitglied — dafür gibt es hier bewusst keinen Knopf.
      await FileViewerDialog.showFromBytes(
        context, resp.bodyBytes, name,
        zusatzAktion: typ == 'uebersetzung' && raHat(v['mitglied_nummer'])
            ? IconButton(
                icon: const Icon(Icons.forum_outlined),
                tooltip: 'An ${raWert(v['mitglied_nummer'])} in den Chat senden '
                    '(${raSpracheName(raWert(v['uebersetzung_sprache']))})',
                onPressed: () => _inDenChat(v, resp.bodyBytes, name),
              )
            : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _speichern(Map<String, dynamic> v, {String? typ}) async {
    final resp = await widget.apiService
        .downloadVertragRaVollmachtPdf(int.tryParse(raWert(v['id'])) ?? 0, typ: typ);
    if (!mounted || resp.statusCode != 200) return;
    final name = typ == 'uebersetzung'
        ? 'vollmacht_${raWert(v['uebersetzung_sprache'])}.pdf'
        : (raWert(v['pdf_filename']).isEmpty ? 'vollmacht.pdf' : raWert(v['pdf_filename']));
    final ziel = await FilePickerHelper.saveBytes(
      bytes: resp.bodyBytes,
      fileName: name,
      dialogTitle: 'Vollmacht speichern',
    );
    if (ziel == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Gespeichert: $ziel'), backgroundColor: Colors.green),
    );
  }

  /// Stellt die Vollmacht beiden Unterzeichnern zur Unterschrift.
  ///
  /// ⚠️ Das PDF geht als Bytes, nicht über eine temporäre Datei: es liegt auf
  /// dem Server verschlüsselt und kommt entschlüsselt im Speicher an. Es
  /// erst auf die Platte zu schreiben hieße, den Klartext ausgerechnet für
  /// das Dokument abzulegen, dessen Unversehrtheit gleich beglaubigt wird.
  ///
  /// ⚠️ Immer die DEUTSCHE Fassung — sie ist die rechtlich verbindliche.
  /// Das Leseexemplar in der Sprache des Mitglieds wird nicht unterschrieben
  /// und trägt deshalb auch kein Unterschriftsfeld.
  Future<void> _zurUnterschrift(Map<String, dynamic> v) async {
    final mitgliedId = int.tryParse(raWert(v['user_id'])) ?? 0;
    final vorsitzerId = int.tryParse(raWert(v['vorsitzer_id'])) ?? 0;
    if (mitgliedId <= 0 || vorsitzerId <= 0 || widget.adminMitgliedernummer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Unterzeichner nicht ermittelbar — bitte die Liste neu laden'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zur Unterschrift stellen?'),
        content: const Text(
          'Die deutsche Fassung geht an beide Unterzeichner: an das Mitglied als '
          'Vollmachtgeber und an den Vorstand als Bevollmächtigten. Beide '
          'unterschreiben in ihrer eigenen App und bekommen einen Code auf ihre '
          'Mobilnummer.\n\n'
          'Wirksam wird die Vollmacht erst, wenn beide unterschrieben haben.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kRaFarbe, foregroundColor: Colors.white),
            child: const Text('Stellen'),
          ),
        ],
      ),
    );
    if (bestaetigt != true || !mounted) return;

    setState(() => _stelltZu = true);
    try {
      final resp = await widget.apiService
          .downloadVertragRaVollmachtPdf(int.tryParse(raWert(v['id'])) ?? 0);
      if (!mounted) return;
      if (resp.statusCode != 200) {
        _melden('PDF nicht abrufbar (HTTP ${resp.statusCode})', Colors.red);
        return;
      }

      final ergebnis = await SignaturService().anfordernAusBytes(
        callerMitgliedernummer: widget.adminMitgliedernummer,
        userId: mitgliedId,
        dokumentTyp: 'ra_vollmacht',
        dokumentTitel: 'Vollmacht und Schweigepflichtentbindung — '
            '${raWert(widget.akte['aktenzeichen'])}',
        pdfBytes: resp.bodyBytes,
        dateiname: raWert(v['pdf_filename']).isEmpty
            ? 'vollmacht.pdf'
            : raWert(v['pdf_filename']),
        quelleTabelle: 'vertrag_ra_vollmacht',
        quelleId: int.tryParse(raWert(v['id'])) ?? 0,
        unterzeichner: [
          Unterzeichner(userId: mitgliedId, rolle: 'vollmachtgeber'),
          Unterzeichner(userId: vorsitzerId, rolle: 'bevollmaechtigter'),
        ],
      );
      if (!mounted) return;
      _melden(
        ergebnis.ok
            ? 'Zur Unterschrift gestellt — beide Unterzeichner sind benachrichtigt'
            : (ergebnis.fehler ?? 'Fehler'),
        ergebnis.ok ? Colors.green : Colors.red,
      );
      if (ergebnis.ok) {
        _laden();
        widget.onChanged();
      }
    } finally {
      if (mounted) setState(() => _stelltZu = false);
    }
  }

  void _melden(String text, Color farbe) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text), backgroundColor: farbe));

  /// Schickt das Leseexemplar in den Chat DES MITGLIEDS, dem die Vollmacht
  /// gehört.
  ///
  /// ⚠️ Adressiert wird über `mitglied_nummer` aus der Vollmacht-Zeile, nicht
  /// über das gerade geöffnete Mitgliederprofil. Beides ist fast immer
  /// dasselbe — aber „fast immer" ist bei einer Vollmacht zu wenig: ein
  /// Dokument im falschen Postfach ist eine Datenpanne, kein Schönheitsfehler.
  ///
  /// ⚠️ Es geht IMMER das Leseexemplar, nie die deutsche Fassung. Die ist für
  /// die Kanzlei bestimmt; ins Postfach des Mitglieds gehört die, die es
  /// lesen kann.
  Future<void> _inDenChat(Map<String, dynamic> v, List<int> pdf, String name) async {
    final nummer = raWert(v['mitglied_nummer']);
    if (nummer.isEmpty || widget.adminMitgliedernummer.isEmpty) {
      _melden('Empfänger nicht ermittelbar', Colors.red);
      return;
    }
    final sprache = raSpracheName(raWert(v['uebersetzung_sprache']));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('In den Chat senden?'),
        content: Text(
          'Das Leseexemplar auf $sprache geht an $nummer.\n\n'
          'Es ist die Fassung zum Lesen — unterschrieben wird die deutsche, '
          'und die geht an die Kanzlei.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kRaFarbe, foregroundColor: Colors.white),
            child: const Text('Senden'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    File? temp;
    try {
      final gespraech = await widget.apiService
          .adminStartChat(widget.adminMitgliedernummer, nummer);
      final id = int.tryParse(raWert(gespraech['conversation_id'])) ??
          int.tryParse(raWert((gespraech['data'] as Map?)?['conversation_id'])) ?? 0;
      if (id <= 0) {
        if (mounted) _melden('Kein Gespräch mit $nummer gefunden', Colors.red);
        return;
      }

      // ⚠️ Der Chat-Upload will eine Datei auf der Platte. Das PDF liegt hier
      // im Speicher, muss also kurz abgelegt werden — im temporären
      // Verzeichnis der App und mit `finally` wieder weg. Es wandert ohnehin
      // gleich in die Chat-Ablage, ist also keine neue Offenlegung.
      temp = File('${Directory.systemTemp.path}/$name');
      await temp.writeAsBytes(pdf, flush: true);

      final res = await widget.apiService.uploadChatAttachments(
        conversationId: id,
        mitgliedernummer: widget.adminMitgliedernummer,
        files: [temp],
        message: 'Vollmacht ($sprache) — ${raWert(widget.akte['aktenzeichen'])}',
      );
      if (!mounted) return;
      final erfolg = res['success'] == true;

      // ⚠️ Erst jetzt protokollieren, nachdem der Server den Empfang
      // bestätigt hat. Vorher einzutragen hieße, eine Sendung zu behaupten,
      // die vielleicht nie ankam — und genau darauf verlässt sich später
      // jemand, der sieht „ist beim Mitglied".
      if (erfolg) {
        // Die Id des Anhangs mitnehmen, damit ein späterer Download des
        // Mitglieds dieser Vollmacht zugeordnet werden kann — sonst wäre er
        // irgendein Anhang in irgendeinem Gespräch.
        final anhaenge = res['attachments'];
        final anhangId = (anhaenge is List && anhaenge.isNotEmpty && anhaenge.first is Map)
            ? int.tryParse(raWert((anhaenge.first as Map)['id']))
            : int.tryParse(raWert(res['attachment_id']));
        await widget.apiService.vertragRaVollmachtVersandEintragen(
          vollmachtId: int.tryParse(raWert(v['id'])) ?? 0,
          empfaenger: nummer,
          weg: 'chat',
          fassung: 'uebersetzung',
          sprache: raWert(v['uebersetzung_sprache']),
          chatAttachmentId: anhangId,
        );
      }
      if (!mounted) return;
      _melden(
        erfolg ? 'An $nummer gesendet' : (raWert(res['message']).isEmpty ? 'Fehler' : raWert(res['message'])),
        erfolg ? Colors.green : Colors.red,
      );
      if (erfolg) _laden();
    } catch (e) {
      if (mounted) _melden('Fehler: $e', Colors.red);
    } finally {
      if (temp != null && temp.existsSync()) {
        try { temp.deleteSync(); } catch (_) {}
      }
    }
  }

  /// Ist die Gruppe vollstaendig unterschrieben und gesiegelt, gibt es eine
  /// DRITTE Fassung: das Dokument mit beiden Unterschriften.
  ///
  /// ⚠️ Genau die fehlte bisher im Bildschirm. Es sah aus, als sei nichts
  /// passiert, obwohl beide unterschrieben hatten — eine bereits
  /// unterschriebene Vollmacht wurde deshalb widerrufen. Der Siegel-Cron
  /// schreibt `signiert_pdf_pfad` auf ALLE Zeilen der Gruppe, sobald der
  /// letzte unterschrieben hat; es ist ein Dokument mit beiden
  /// Unterschriften, nicht zwei.
  Signaturvorgang? _signiertVerfuegbar(Map<String, dynamic> v) {
    final vorgaenge = _signaturen[int.tryParse(raWert(v['id'])) ?? 0] ?? const <Signaturvorgang>[];
    if (vorgaenge.isEmpty) return null;
    if (!vorgaenge.every((x) => x.istSigniert)) return null;
    return vorgaenge.first;
  }

  Future<void> _signiertOeffnen(Map<String, dynamic> v, {bool speichern = false}) async {
    final vorgang = _signiertVerfuegbar(v);
    if (vorgang == null) return;
    final bytes = await SignaturService().herunterladen(
      callerMitgliedernummer: widget.adminMitgliedernummer,
      signaturId: vorgang.id,
      welche: 'signiert',
    );
    if (!mounted) return;
    if (bytes == null) {
      // Der Cron laeuft alle paar Minuten. „Noch nicht da" ist kein Fehler,
      // aber es muss dastehen — sonst sucht jemand wieder an der falschen
      // Stelle.
      _melden('Die unterschriebene Fassung ist noch nicht gesiegelt — '
              'das geschieht wenige Minuten nach der letzten Unterschrift', Colors.orange);
      return;
    }
    final name = 'vollmacht_unterschrieben_${raWert(v['id'])}.pdf';
    if (speichern) {
      final ziel = await FilePickerHelper.saveBytes(
        bytes: Uint8List.fromList(bytes), fileName: name,
        dialogTitle: 'Unterschriebene Vollmacht speichern');
      if (ziel == null || !mounted) return;
      _melden('Gespeichert: $ziel', Colors.green);
      return;
    }
    await FileViewerDialog.showFromBytes(context, Uint8List.fromList(bytes), name);
  }

  /// Das vollstaendige Versandprotokoll — jede Sendung, nicht nur die letzte.
  Future<void> _versandprotokoll(Map<String, dynamic> v) async {
    final res = await widget.apiService
        .listVertragRaVollmachtVersand(int.tryParse(raWert(v['id'])) ?? 0);
    if (!mounted) return;
    final zeilen = raListe(res);
    final breite = MediaQuery.of(context).size.width;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Versandprotokoll'),
        content: SizedBox(
          width: breite < 560 ? breite * 0.86 : 480,
          child: zeilen.isEmpty
              ? const Text('Noch nicht verschickt.', style: TextStyle(fontSize: 13))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: zeilen.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, i) {
                    final z = zeilen[i];
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        '${raDatumDe(z['gesendet_am'])} · '
                        '${raWert(z['fassung']) == 'original' ? 'deutsche Fassung' : 'Leseexemplar'}'
                        '${raHat(z['sprache']) ? ' (${raSpracheName(raWert(z['sprache']))})' : ''}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text('${raWert(z['weg'])} an ${raWert(z['empfaenger'])}',
                          style: const TextStyle(fontSize: 12)),
                      if (raHat(z['gesendet_von_name']))
                        Text('durch ${raWert(z['gesendet_von_name'])}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      if (raHat(z['notiz']))
                        Text(raWert(z['notiz']),
                            style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                    ]);
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
        ],
      ),
    );
  }

  Future<void> _statusAendern(Map<String, dynamic> v) async {
    final id = int.tryParse(raWert(v['id'])) ?? 0;
    final ergebnis = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _RaVollmachtStatusDialog(vollmacht: v),
    );
    if (ergebnis == null) return;
    final res = await widget.apiService.updateVertragRaVollmacht(
      id: id,
      status: raWert(ergebnis['status']),
      uebermitteltAm: raWert(ergebnis['uebermittelt_am']).isEmpty ? null : raWert(ergebnis['uebermittelt_am']),
      uebermitteltWeg: raWert(ergebnis['uebermittelt_weg']).isEmpty ? null : raWert(ergebnis['uebermittelt_weg']),
      notizen: raWert(ergebnis['notizen']),
    );
    if (!mounted) return;
    if (res['success'] == true) {
      _laden();
      widget.onChanged();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(raWert(res['message']).isEmpty ? 'Fehler' : raWert(res['message'])), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _widerrufen(Map<String, dynamic> v) async {
    final grundC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vollmacht widerrufen?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Das Dokument bleibt erhalten und wird als widerrufen gekennzeichnet — '
            'gelöscht wird nichts. Später muss nachvollziehbar sein, was wann galt.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: grundC,
            decoration: const InputDecoration(labelText: 'Grund (optional)', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 8),
          const Text(
            'Der Widerruf wirkt erst, wenn die Kanzlei ihn kennt — bitte zusätzlich '
            'schriftlich mitteilen.',
            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Widerrufen', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    grundC.dispose();
    if (ok != true) return;
    await widget.apiService.widerrufVertragRaVollmacht(int.tryParse(raWert(v['id'])) ?? 0, grundC.text.trim());
    _laden();
    widget.onChanged();
  }

  Future<void> _loeschen(Map<String, dynamic> v) async {
    final res = await widget.apiService.deleteVertragRaVollmacht(int.tryParse(raWert(v['id'])) ?? 0);
    if (!mounted) return;
    if (res['success'] == true) {
      _laden();
      widget.onChanged();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(raWert(res['message']).isEmpty ? 'Fehler' : raWert(res['message'])), backgroundColor: Colors.orange),
      );
    }
  }

  /// Wie weit die Unterschriften sind — aus dem Unterschriften-System.
  ///
  /// ⚠️ Zeigt „0 von 2", nicht „offen": bei zwei Unterzeichnern ist die
  /// Frage nie ja/nein, sondern wer noch fehlt. Und solange nicht beide
  /// unterschrieben haben, ist die Vollmacht nicht wirksam — das steht
  /// dabei, damit niemand sie zu früh an die Kanzlei gibt.
  List<Widget> _unterschriftsStand(Map<String, dynamic> v) {
    final id = int.tryParse(raWert(v['id'])) ?? 0;
    final vorgaenge = _signaturen[id] ?? const <Signaturvorgang>[];
    if (vorgaenge.isEmpty) return const [];

    final signiert = vorgaenge.where((x) => x.istSigniert).length;
    final abgelehnt = vorgaenge.where((x) => x.status == 'abgelehnt').length;
    final vollstaendig = signiert == vorgaenge.length;
    final farbe = abgelehnt > 0
        ? Colors.red
        : (vollstaendig ? Colors.green : Colors.orange);

    return [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(vollstaendig ? Icons.verified : Icons.draw, size: 12, color: farbe),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              abgelehnt > 0
                  ? 'Unterschrift abgelehnt'
                  : (vollstaendig
                      ? 'Von beiden unterschrieben'
                      : '$signiert von ${vorgaenge.length} unterschrieben — '
                          'wirksam erst, wenn beide unterschrieben haben'),
              style: TextStyle(fontSize: 10, color: farbe),
            ),
          ),
        ]),
      ),
    ];
  }

  /// Dass die Vollmacht beim Mitglied ist — an der Vollmacht selbst.
  ///
  /// ⚠️ Der Chat wäre zwar auch ein Nachweis; die Nachricht samt Anhang
  /// bleibt dort stehen. Aber wer die Vollmacht ansieht, soll nicht erst
  /// ein Gespräch durchsuchen müssen, um zu wissen, ob sie angekommen ist.
  List<Widget> _versandStand(Map<String, dynamic> v) {
    final letzter = v['letzter_versand'];
    if (letzter is! Map) return const [];
    final anzahl = int.tryParse(raWert(v['versand_anzahl'])) ?? 1;
    final weg = switch (raWert(letzter['weg'])) {
      'chat' => 'in den Chat',
      'email' => 'per E-Mail',
      'bea' => 'per beA',
      'fax' => 'per Fax',
      'post' => 'per Post',
      'persoenlich' => 'persönlich',
      _ => '',
    };
    final fassung = raWert(letzter['fassung']) == 'original'
        ? 'deutsche Fassung'
        : 'Leseexemplar${raHat(letzter['sprache']) ? ' auf ${raSpracheName(raWert(letzter['sprache']))}' : ''}';

    // ⚠️ Hier steht „heruntergeladen", und das ist belegbar: der
    // Herunterladen-Knopf im Chat ruft einen eigenen Endpunkt, das Anzeigen
    // geht einen anderen Weg. Beim Unterschriften-PDF wäre dasselbe Wort
    // eine Behauptung — dort holt die App die Datei mit einem Aufruf, zum
    // Lesen wie zum Speichern, und der Server sieht keinen Unterschied.
    final geholt = letzter['heruntergeladen_am'];
    final holAnzahl = int.tryParse(raWert(letzter['heruntergeladen_anzahl'])) ?? 0;

    return [
      if (raHat(geholt))
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.download_done, size: 12, color: Colors.green),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Vom Mitglied heruntergeladen — ${raDatumDe(geholt)}'
                '${holAnzahl > 1 ? ' ($holAnzahl×)' : ''}',
                style: const TextStyle(fontSize: 10, color: Colors.green),
              ),
            ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.outgoing_mail, size: 12, color: Colors.indigo),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '$fassung $weg an ${raWert(letzter['empfaenger'])} '
              '— ${raDatumDe(letzter['gesendet_am'])}'
              // Mehrfach verschickt kommt vor: das Mitglied fragt ein halbes
              // Jahr später noch einmal danach. Dann gehört die Zahl dazu.
              '${anzahl > 1 ? ' ($anzahl Sendungen)' : ''}',
              style: const TextStyle(fontSize: 10, color: Colors.indigo),
            ),
          ),
        ]),
      ),
    ];
  }

  static (String, Color) _statusAnzeige(String s) => switch (s) {
        'draft' => ('Entwurf', Colors.grey),
        'unterzeichnet' => ('Unterzeichnet', Colors.blue),
        'uebermittelt' => ('Übermittelt', Colors.green),
        'widerrufen' => ('Widerrufen', Colors.red),
        'abgelaufen' => ('Abgelaufen', Colors.orange),
        _ => (s, Colors.grey),
      };

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    final kanzlei = (widget.mandat?['kanzlei'] is Map)
        ? Map<String, dynamic>.from(widget.mandat!['kanzlei'] as Map)
        : const <String, dynamic>{};

    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        color: Colors.teal.shade50,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.info_outline, size: 15, color: Colors.teal.shade800),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Vollmacht und Schweigepflichtentbindung gegenüber der Kanzlei',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            'Ohne sie darf die Kanzlei dem Verein gar nichts sagen (§ 43a Abs. 2 BRAO, '
            '§ 203 StGB) — Herr des Geheimnisses ist das Mitglied. Das Dokument ist keine '
            'Prozessvollmacht und überträgt kein Mandat.',
            style: TextStyle(fontSize: 11, color: Colors.teal.shade900),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          const Icon(Icons.assignment_ind, size: 18, color: kRaFarbe),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${_vollmachten.length} Vollmacht(en)',
                style: const TextStyle(fontWeight: FontWeight.bold, color: kRaFarbe)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.picture_as_pdf, size: 16),
            label: const Text('Erzeugen'),
            style: ElevatedButton.styleFrom(backgroundColor: kRaFarbe, foregroundColor: Colors.white),
            onPressed: kanzlei.isEmpty && raWert(widget.mandat?['rechtsanwalt_id']).isEmpty ? null : _erzeugen,
          ),
        ]),
      ),
      if (kanzlei.isEmpty && raWert(widget.mandat?['rechtsanwalt_id']).isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Erst unter „Zuständiger Rechtsanwalt" eine Kanzlei auswählen — '
            'ohne Adressat hat die Vollmacht keinen Empfänger.',
            style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
          ),
        ),
      const Divider(height: 12),
      Expanded(
        child: _vollmachten.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.assignment_late_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('Noch keine Vollmacht', style: TextStyle(color: Colors.grey.shade600)),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _vollmachten.length,
                itemBuilder: (ctx, i) {
                  final v = _vollmachten[i];
                  // `status_effektiv` beruecksichtigt ein abgelaufenes
                  // Gueltigkeitsdatum — gerechnet, nicht gespeichert.
                  final st = raWert(v['status_effektiv']).isEmpty ? raWert(v['status']) : raWert(v['status_effektiv']);
                  final (text, farbe) = _statusAnzeige(st);
                  final entwurf = raWert(v['status']) == 'draft';
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: farbe.withValues(alpha: 0.15),
                        child: Icon(Icons.assignment_ind, color: farbe),
                      ),
                      title: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: farbe.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                          child: Text(text, style: TextStyle(fontSize: 10, color: farbe)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(raWert(v['firmenname']),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          'gültig ${raDatumDe(v['valid_from'])} – '
                          '${raHat(v['valid_until']) ? raDatumDe(v['valid_until']) : 'bis auf Widerruf'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        ..._unterschriftsStand(v),
                        ..._versandStand(v),
                        if (raHat(v['uebersetzung_sprache']))
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.translate, size: 12, color: kRaFarbe),
                              const SizedBox(width: 4),
                              Text('Leseexemplar auf '
                                  '${raSpracheName(raWert(v['uebersetzung_sprache']))} '
                                  '— unterschrieben wird die deutsche Fassung',
                                  style: const TextStyle(fontSize: 10, color: kRaFarbe)),
                            ]),
                          ),
                        if (raHat(v['uebermittelt_am']))
                          Text('übermittelt ${raDatumDe(v['uebermittelt_am'])} '
                              '(${raWert(v['uebermittelt_weg'])})',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                        if (raHat(v['widerrufen_am']))
                          Text('widerrufen ${raDatumDe(v['widerrufen_am'])}'
                              '${raHat(v['widerruf_grund']) ? ' — ${raWert(v['widerruf_grund'])}' : ''}',
                              style: const TextStyle(fontSize: 10, color: Colors.red)),
                      ]),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (wahl) {
                          switch (wahl) {
                            case 'oeffnen':
                              _oeffnen(v);
                            case 'speichern':
                              _speichern(v);
                            case 'oeffnen_sig':
                              _signiertOeffnen(v);
                            case 'speichern_sig':
                              _signiertOeffnen(v, speichern: true);
                            case 'oeffnen_ueb':
                              _oeffnen(v, typ: 'uebersetzung');
                            case 'speichern_ueb':
                              _speichern(v, typ: 'uebersetzung');
                            case 'unterschrift':
                              _zurUnterschrift(v);
                            case 'versand':
                              _versandprotokoll(v);
                            case 'status':
                              _statusAendern(v);
                            case 'widerruf':
                              _widerrufen(v);
                            case 'loeschen':
                              _loeschen(v);
                          }
                        },
                        itemBuilder: (ctx) => [
                          // ⚠️ Die unterschriebene Fassung steht OBEN, sobald
                          // es sie gibt: wer eine Vollmacht sucht, die schon
                          // unterschrieben ist, sucht diese — und fand
                          // bisher nur das leere Original.
                          if (_signiertVerfuegbar(v) != null) ...[
                            const PopupMenuItem(
                                value: 'oeffnen_sig',
                                child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.verified, size: 18, color: Colors.green),
                                    title: Text('Anzeigen (unterschrieben)'))),
                            const PopupMenuItem(
                                value: 'speichern_sig',
                                child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.download_done, size: 18, color: Colors.green),
                                    title: Text('Speichern (unterschrieben)'))),
                            const PopupMenuDivider(),
                          ],
                          const PopupMenuItem(
                              value: 'oeffnen',
                              child: ListTile(dense: true, leading: Icon(Icons.visibility, size: 18), title: Text('Anzeigen (Original, ohne Unterschriften)'))),
                          const PopupMenuItem(
                              value: 'speichern',
                              child: ListTile(dense: true, leading: Icon(Icons.download, size: 18), title: Text('Speichern'))),
                          // Das Leseexemplar erscheint nur, wenn es eines
                          // gibt — ein toter Menüpunkt wäre schlimmer als
                          // keiner.
                          if (raHat(v['uebersetzung_sprache'])) ...[
                            PopupMenuItem(
                                value: 'oeffnen_ueb',
                                child: ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.translate, size: 18),
                                    title: Text('Anzeigen (${raSpracheName(raWert(v['uebersetzung_sprache']))})'))),
                            PopupMenuItem(
                                value: 'speichern_ueb',
                                child: ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.download, size: 18),
                                    title: Text('Speichern (${raSpracheName(raWert(v['uebersetzung_sprache']))})'))),
                          ],
                          // Nur solange sie noch Entwurf ist: was schon zur
                          // Unterschrift steht, ein zweites Mal zu stellen
                          // ergäbe zwei Vorgänge über dasselbe Papier.
                          if (entwurf)
                            PopupMenuItem(
                                value: 'unterschrift',
                                enabled: !_stelltZu,
                                child: const ListTile(
                                    dense: true,
                                    leading: Icon(Icons.draw, size: 18, color: kRaFarbe),
                                    title: Text('Zur Unterschrift stellen'))),
                          if ((int.tryParse(raWert(v['versand_anzahl'])) ?? 0) > 0)
                            const PopupMenuItem(
                                value: 'versand',
                                child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.outgoing_mail, size: 18, color: Colors.indigo),
                                    title: Text('Versandprotokoll'))),
                          const PopupMenuItem(
                              value: 'status',
                              child: ListTile(dense: true, leading: Icon(Icons.flag, size: 18), title: Text('Übermittlung eintragen'))),
                          if (st != 'widerrufen')
                            const PopupMenuItem(
                                value: 'widerruf',
                                child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.block, size: 18, color: Colors.red),
                                    title: Text('Widerrufen'))),
                          // Nur Entwuerfe verschwinden spurlos; alles, was
                          // erteilt war, wird widerrufen statt geloescht.
                          if (entwurf)
                            const PopupMenuItem(
                                value: 'loeschen',
                                child: ListTile(
                                    dense: true,
                                    leading: Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                    title: Text('Entwurf löschen'))),
                        ],
                      ),
                      onTap: () => _oeffnen(v),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

/// Erzeugen: Umfang ankreuzen, Geltung setzen, PDF bauen lassen.
///
/// ⚠️ Die Punkte kommen vom Server (`vollmacht_optionen`) und werden hier
/// NICHT noch einmal aufgeschrieben. Sonst verspricht der Bildschirm eines
/// und das PDF druckt ein anderes.
class _RaVollmachtErzeugenDialog extends StatefulWidget {
  final ApiService apiService;
  final int aktenzeichenId;
  final Map<String, dynamic> akte;
  final Map<String, dynamic>? mandat;
  const _RaVollmachtErzeugenDialog({
    required this.apiService,
    required this.aktenzeichenId,
    required this.akte,
    required this.mandat,
  });

  @override
  State<_RaVollmachtErzeugenDialog> createState() => _RaVollmachtErzeugenDialogState();
}

class _RaVollmachtErzeugenDialogState extends State<_RaVollmachtErzeugenDialog> {
  Map<String, dynamic> _umfang = {};
  List<String> _grenzen = const [];
  final Map<String, Map<String, bool>> _gewaehlt = {};
  bool _geladen = false;
  bool _laeuft = false;

  DateTime _ab = DateTime.now();
  DateTime? _bis = DateTime.now().add(const Duration(days: 365));
  final _notizC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _optionenLaden();
  }

  @override
  void dispose() {
    _notizC.dispose();
    super.dispose();
  }

  Future<void> _optionenLaden() async {
    final res = await widget.apiService.vertragRaVollmachtOptionen();
    if (!mounted) return;
    final u = (res['umfang'] is Map) ? Map<String, dynamic>.from(res['umfang'] as Map) : <String, dynamic>{};
    setState(() {
      _umfang = u;
      _grenzen = ((res['grenzen'] as List?) ?? const []).map((e) => e.toString()).toList();
      for (final gruppe in u.entries) {
        final punkte = (gruppe.value is Map) ? Map<String, dynamic>.from(gruppe.value as Map) : <String, dynamic>{};
        _gewaehlt[gruppe.key] = {
          // Auskunft ist der Anlass des Dokuments und deshalb vorbelegt.
          // Organisation und Erklaerungen sind AUS: ein vorangekreuztes
          // Kaestchen ist eine Einladung, es stehen zu lassen.
          for (final k in punkte.keys) k: gruppe.key == 'auskunft',
        };
      }
      _geladen = true;
    });
  }

  Future<void> _erzeugen() async {
    setState(() => _laeuft = true);
    final res = await widget.apiService.createVertragRaVollmacht(
      aktenzeichenId: widget.aktenzeichenId,
      validFrom: raIso(_ab),
      validUntil: _bis == null ? null : raIso(_bis),
      options: {
        for (final g in _gewaehlt.entries) g.key: {for (final e in g.value.entries) e.key: e.value},
      },
      notizen: _notizC.text.trim(),
    );
    if (!mounted) return;
    setState(() => _laeuft = false);
    if (res['success'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(raWert(res['message']).isEmpty ? 'Fehler' : raWert(res['message'])), backgroundColor: Colors.red),
      );
    }
  }

  static const gruppenTitel = {
    'auskunft': ('I. Auskunft und Akteneinsicht', 'Der Anlass des Dokuments — ohne Vertretungsbefugnis möglich.'),
    'organisation': (
      'II. Organisatorische Unterstützung',
      'Verwaltungshilfe ohne rechtliche Prüfung — keine Rechtsdienstleistung (§ 2 Abs. 1 RDG).'
    ),
    'erklaerung': (
      'III. Erklärungen im Namen des Mitglieds',
      'Rechtsgeschäftliche Vertretung (§§ 164 ff. BGB). Nur ankreuzen, was wirklich gelten soll.'
    ),
  };

  @override
  Widget build(BuildContext context) {
    final breite = MediaQuery.of(context).size.width;
    return AlertDialog(
      title: const Text('Vollmacht erzeugen'),
      content: SizedBox(
        width: breite < 640 ? breite * 0.88 : 580,
        height: MediaQuery.of(context).size.height * 0.68,
        child: !_geladen
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Angelegenheit: ${raWert(widget.akte['aktenzeichen'])}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      if (raHat(widget.akte['gegenseite']))
                        Text('gegen ${raWert(widget.akte['gegenseite'])}', style: const TextStyle(fontSize: 11)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _ab,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2060),
                          );
                          if (d != null) setState(() => _ab = d);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Gültig ab', border: OutlineInputBorder(), isDense: true),
                          child: Text(raDatumDe(raIso(_ab))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _bis ?? DateTime.now().add(const Duration(days: 365)),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2060),
                          );
                          if (d != null) setState(() => _bis = d);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Gültig bis',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: _bis == null
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    tooltip: 'Ohne Enddatum',
                                    onPressed: () => setState(() => _bis = null),
                                  ),
                          ),
                          child: Text(_bis == null ? 'bis auf Widerruf' : raDatumDe(raIso(_bis))),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  for (final gruppe in _umfang.entries) ...[
                    Text(gruppenTitel[gruppe.key]?.$1 ?? gruppe.key,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: kRaFarbe, fontSize: 13)),
                    if (gruppenTitel[gruppe.key] != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(gruppenTitel[gruppe.key]!.$2,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                      ),
                    ...(gruppe.value is Map ? Map<String, dynamic>.from(gruppe.value as Map) : <String, dynamic>{})
                        .entries
                        .map((p) => CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              // Ohne das steht ein Material-violettes Haekchen
                              // in einem sonst durchgehend tealfarbenen Zweig.
                              activeColor: kRaFarbe,
                              value: _gewaehlt[gruppe.key]?[p.key] ?? false,
                              title: Text(p.value.toString(), style: const TextStyle(fontSize: 12)),
                              onChanged: (v) => setState(() => _gewaehlt[gruppe.key]![p.key] = v ?? false),
                            )),
                    const SizedBox(height: 10),
                  ],
                  if (_grenzen.isNotEmpty) ...[
                    const Text('Was der Verein in keinem Fall tut',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('Steht so im Dokument — nicht abwählbar.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                    const SizedBox(height: 4),
                    ..._grenzen.map((g) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('•  ', style: TextStyle(fontSize: 12)),
                            Expanded(child: Text(g, style: const TextStyle(fontSize: 11))),
                          ]),
                        )),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _notizC,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Interne Notiz (nicht im PDF)', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      'Das PDF wird als Entwurf angelegt. Wirksam wird es erst mit der '
                      'Unterschrift des Mitglieds — danach hier auf „Unterzeichnet" setzen '
                      'und der Kanzlei übermitteln.',
                      style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                    ),
                  ),
                ]),
              ),
      ),
      actions: [
        TextButton(onPressed: _laeuft ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
        ElevatedButton.icon(
          onPressed: _laeuft || !_geladen ? null : _erzeugen,
          icon: _laeuft
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.picture_as_pdf, size: 16),
          label: const Text('PDF erzeugen'),
          style: ElevatedButton.styleFrom(backgroundColor: kRaFarbe, foregroundColor: Colors.white),
        ),
      ],
    );
  }
}

class _RaVollmachtStatusDialog extends StatefulWidget {
  final Map<String, dynamic> vollmacht;
  const _RaVollmachtStatusDialog({required this.vollmacht});

  @override
  State<_RaVollmachtStatusDialog> createState() => _RaVollmachtStatusDialogState();
}

class _RaVollmachtStatusDialogState extends State<_RaVollmachtStatusDialog> {
  late String _status;
  String? _weg;
  DateTime? _am;
  late final TextEditingController _notizC;

  @override
  void initState() {
    super.initState();
    _status = raWert(widget.vollmacht['status']).isEmpty ? 'draft' : raWert(widget.vollmacht['status']);
    _weg = raHat(widget.vollmacht['uebermittelt_weg']) ? raWert(widget.vollmacht['uebermittelt_weg']) : null;
    _am = DateTime.tryParse(raWert(widget.vollmacht['uebermittelt_am']));
    _notizC = TextEditingController(text: raWert(widget.vollmacht['notizen']));
  }

  @override
  void dispose() {
    _notizC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uebermittelt = _status == 'uebermittelt';
    return AlertDialog(
      title: const Text('Übermittlung an die Kanzlei'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true),
            // ⚠️ „Unterzeichnet" steht hier NICHT mehr zur Auswahl. Ob
            // unterschrieben wurde, sagt seit dem 15.08.2026 das
            // Unterschriften-System — und zwar mit Beweiskette. Eine zweite,
            // von Hand gesetzte Wahrheit daneben wäre genau der Fehler, den
            // wir bei den Fristen vermieden haben.
            //
            // Die Übermittlung an die Kanzlei bleibt von Hand: dass ein
            // Brief angekommen ist, kann diese App nicht wissen.
            items: const [
              DropdownMenuItem(value: 'draft', child: Text('Entwurf')),
              DropdownMenuItem(value: 'uebermittelt', child: Text('An die Kanzlei übermittelt')),
            ],
            onChanged: (v) => setState(() => _status = v ?? 'draft'),
          ),
          if (uebermittelt) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _am ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2060),
                );
                if (d != null) setState(() => _am = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Übermittelt am', border: OutlineInputBorder(), isDense: true),
                child: Text(_am == null ? '—' : raDatumDe(raIso(_am))),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _weg,
              decoration: const InputDecoration(labelText: 'Auf welchem Weg', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'bea', child: Text('beA (§ 31a BRAO)')),
                DropdownMenuItem(value: 'email', child: Text('E-Mail')),
                DropdownMenuItem(value: 'fax', child: Text('Fax')),
                DropdownMenuItem(value: 'post', child: Text('Post')),
                DropdownMenuItem(value: 'persoenlich', child: Text('Persönlich übergeben')),
              ],
              onChanged: (v) => setState(() => _weg = v),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _notizC,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notiz', border: OutlineInputBorder(), isDense: true),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, {
            'status': _status,
            'uebermittelt_am': uebermittelt ? raIso(_am) : '',
            'uebermittelt_weg': uebermittelt ? (_weg ?? '') : '',
            'notizen': _notizC.text.trim(),
          }),
          style: ElevatedButton.styleFrom(backgroundColor: kRaFarbe, foregroundColor: Colors.white),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Gemeinsame Dokumentenliste für alle vier Bereiche
// ═══════════════════════════════════════════════════════════════════════

class RaDokumente extends StatefulWidget {
  final ApiService apiService;
  final String bereich; // 'akte' | 'korr' | 'mahn' | 'vollmacht'
  final int parentId;
  final String hinweis;

  const RaDokumente({
    super.key,
    required this.apiService,
    required this.bereich,
    required this.parentId,
    this.hinweis = '',
  });

  @override
  State<RaDokumente> createState() => _RaDokumenteState();
}

class _RaDokumenteState extends State<RaDokumente> {
  List<Map<String, dynamic>> _dateien = [];
  bool _geladen = false;
  bool _laedtHoch = false;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final res = await widget.apiService.listVertragRaDocs(bereich: widget.bereich, parentId: widget.parentId);
    if (!mounted) return;
    setState(() {
      _dateien = raListe(res);
      _geladen = true;
    });
  }

  Future<void> _hochladen() async {
    final r = await FilePickerHelper.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'odt', 'txt', 'eml'],
    );
    if (r == null || r.files.isEmpty) return;
    var dateien = r.files.where((f) => f.path != null).toList();
    if (!mounted) return;
    if (dateien.length > 20) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Höchstens 20 Dateien auf einmal — ${dateien.length - 20} ausgelassen'),
        backgroundColor: Colors.orange,
      ));
      dateien = dateien.sublist(0, 20);
    }
    setState(() => _laedtHoch = true);
    var fertig = 0;
    final fehler = <String>[];
    for (final f in dateien) {
      final res = await widget.apiService.uploadVertragRaDoc(
        bereich: widget.bereich,
        parentId: widget.parentId,
        filePath: f.path!,
        fileName: f.name,
      );
      if (res['success'] == true) {
        fertig++;
      } else {
        fehler.add('${f.name}: ${raWert(res['message']).isEmpty ? '?' : raWert(res['message'])}');
      }
    }
    if (!mounted) return;
    setState(() => _laedtHoch = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(fehler.isEmpty
          ? '$fertig Datei(en) hochgeladen'
          : '$fertig hochgeladen, ${fehler.length} fehlgeschlagen: ${fehler.first}'),
      backgroundColor: fehler.isEmpty ? Colors.green : Colors.orange,
    ));
    _laden();
  }

  Future<void> _loeschen(int id) async {
    await widget.apiService.deleteVertragRaDoc(id);
    _laden();
  }

  Future<void> _oeffnen(Map<String, dynamic> d) async {
    try {
      final resp = await widget.apiService.downloadVertragRaDoc(int.tryParse(raWert(d['id'])) ?? 0);
      if (resp.statusCode != 200 || !mounted) return;
      final name = raWert(d['datei_name']).isEmpty
          ? 'dokument_${raWert(d['id'])}'
          : raWert(d['datei_name']).replaceAll(RegExp(r'[<>:"|?*\\/]'), '_');
      await FileViewerDialog.showFromBytes(context, resp.bodyBytes, name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
      }
    }
  }

  String _groesse(dynamic bytes) {
    final b = int.tryParse(raWert(bytes)) ?? 0;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1048576).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          Icon(Icons.folder_open, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Expanded(child: Text('${_dateien.length} Datei(en)', style: const TextStyle(fontSize: 12))),
          TextButton.icon(
            icon: _laedtHoch
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file, size: 16),
            label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
            onPressed: _laedtHoch || widget.parentId <= 0 ? null : _hochladen,
          ),
        ]),
      ),
      if (widget.hinweis.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(widget.hinweis, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ),
      const Divider(height: 12),
      Expanded(
        child: _dateien.isEmpty
            ? Center(child: Text('Keine Dateien', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _dateien.length,
                itemBuilder: (ctx, i) {
                  final d = _dateien[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.insert_drive_file, size: 18),
                    title: Text(raWert(d['datei_name']), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                    subtitle: Text('${_groesse(d['file_size'])} · ${raDatumDe(d['created_at'])}',
                        style: const TextStyle(fontSize: 10)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.visibility, size: 16),
                        tooltip: 'Anzeigen',
                        onPressed: () => _oeffnen(d),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        tooltip: 'Löschen',
                        onPressed: () => _loeschen(int.tryParse(raWert(d['id'])) ?? 0),
                      ),
                    ]),
                    onTap: () => _oeffnen(d),
                  );
                },
              ),
      ),
    ]);
  }
}
