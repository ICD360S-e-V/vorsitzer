import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';
import '../widgets/korrespondenz_message_dialog.dart';

/// DMARC ▸ Reporting — was andere Postfächer über unsere Domain melden.
///
/// Unser DNS trägt `rua=mailto:dmarc@icd360s.de`. Jedes grosse Postfach, das
/// Post mit Absender `icd360s.de` bekommt, schickt daraufhin täglich einen
/// Bericht: wie viele Nachrichten kamen, von welcher IP, und ob SPF und DKIM
/// gestimmt haben. In den ersten 37 Berichten waren das Google, WEB.DE, Yahoo,
/// Microsoft, GoDaddy und Komm.ONE.
///
/// Zwei Ansichten, weil es zwei verschiedene Fragen sind:
///
/// **E-Mails** ist das Archiv der Nachrichten selbst, baugleich zu
/// Finanzamt/GitHub/INWX ▸ Korrespondenz. Was an dmarc@icd360s.de eingeht,
/// landet hier von selbst (Cron, jede Minute).
/// ⚠️ Der Eintrag hängt danach nicht mehr an der Mail: Betreff, Absender und
/// Empfänger stehen verschlüsselt in unserer Tabelle, die vollständige
/// Originalnachricht als .eml auf unserer Platte. Wer die Mail im
/// Mailprogramm löscht, löscht hier nichts.
///
/// **Berichte** ist der Inhalt dieser Mails. Das ist der eigentliche Punkt:
/// der Bericht ist XML in einem ZIP, und ein ZIP nützt auf einem Telefon
/// niemandem. Ausgepackt und ausgewertet wird er beim Import; hier stehen nur
/// noch Zahlen.
class DmarcScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;

  const DmarcScreen({super.key, required this.apiService, required this.onBack});

  @override
  State<DmarcScreen> createState() => _DmarcScreenState();
}

/// PHP kennt nur einen Array-Typ: eine lückenlose Liste kodiert als `[]`,
/// dieselbe Struktur mit String-Schlüsseln als Objekt. Ein `as Map` auf einer
/// Liste wirft — genau daran blieb der Speedtest-Bildschirm am 05.08.2026 in
/// der Produktion grau hängen. Deshalb lesen diese Helfer beide Formen und
/// geben im Zweifel Leeres zurück, nie eine Ausnahme.
List<Map<String, dynamic>> dmarcListe(dynamic roh) {
  if (roh is! List) return const [];
  return roh.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

Map<String, dynamic> dmarcMap(dynamic roh) {
  if (roh is Map) return Map<String, dynamic>.from(roh);
  return const {}; // eine Liste (auch die leere) ist hier keine Map
}

class _DmarcScreenState extends State<DmarcScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _melde(String text, {bool fehler = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler ? Colors.red.shade600 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
            tooltip: 'Zurück zu Partner',
          ),
          const SizedBox(width: 8),
          Icon(Icons.verified_user_outlined, size: 30, color: Colors.teal.shade700),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('DMARC Reporting',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text('Berichte an dmarc@icd360s.de',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
        ]),
      ),
      TabBar(
        controller: _tabs,
        labelColor: Colors.teal.shade700,
        indicatorColor: Colors.teal.shade700,
        tabs: const [
          Tab(icon: Icon(Icons.mail_outline, size: 18), text: 'E-Mails'),
          Tab(icon: Icon(Icons.insights_outlined, size: 18), text: 'Berichte'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            _DmarcMailTab(apiService: widget.apiService, melde: _melde),
            _DmarcBerichteTab(apiService: widget.apiService, melde: _melde),
          ],
        ),
      ),
    ]);
  }
}

// ═══════════════════ Tab 1: E-Mails ═══════════════════

/// Die Nachrichten, die an dmarc@icd360s.de eingegangen sind.
///
/// ⚠️ Hier gibt es bewusst kein „Erfassen". In den anderen Korrespondenz-
/// Bereichen ist der Knopf für das, was nicht per Mail kommt — ein Anruf beim
/// Support, ein Brief. DMARC-Berichte erzeugt kein Mensch; ein Eingabeformular
/// wäre hier nur eine Möglichkeit, die Statistik zu verfälschen. Der
/// Endpunkt kann es weiterhin, falls es je gebraucht wird.
class _DmarcMailTab extends StatefulWidget {
  final ApiService apiService;
  final void Function(String, {bool fehler}) melde;

  const _DmarcMailTab({required this.apiService, required this.melde});

  @override
  State<_DmarcMailTab> createState() => _DmarcMailTabState();
}

class _DmarcMailTabState extends State<_DmarcMailTab>
    with AutomaticKeepAliveClientMixin {
  static const String _modul = 'dmarc';

  bool _laeuft = true;
  List<Map<String, dynamic>> _eintraege = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() => _laeuft = true);
    try {
      final r = await widget.apiService.getVereinKorrespondenz(modul: _modul);
      if (!mounted) return;
      if (r['success'] == true) {
        final d = r['data'];
        _eintraege = dmarcListe(
            (d is Map ? d['korrespondenz'] : null) ?? r['korrespondenz']);
      } else {
        widget.melde(r['message']?.toString() ?? 'Korrespondenz nicht abrufbar',
            fehler: true);
      }
    } catch (e) {
      if (mounted) widget.melde('Fehler: $e', fehler: true);
    }
    if (mounted) setState(() => _laeuft = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(children: [
          Expanded(
            child: Text(
              _laeuft
                  ? 'Wird geladen …'
                  : '${_eintraege.length} '
                      '${_eintraege.length == 1 ? "Nachricht" : "Nachrichten"} archiviert',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Neu laden',
            onPressed: _laden,
          ),
        ]),
      ),
      Expanded(
        child: _laeuft
            ? const Center(child: CircularProgressIndicator())
            : _eintraege.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.mail_outline, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 10),
                        Text(
                          'Noch keine Nachricht.\n'
                          'E-Mails an dmarc@icd360s.de werden automatisch übernommen.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ]),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _laden,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: _eintraege.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _karte(_eintraege[i]),
                    ),
                  ),
      ),
    ]);
  }

  Widget _karte(Map<String, dynamic> k) {
    final betreff = (k['betreff'] ?? '').toString();
    final absender = (k['absender'] ?? '').toString();
    final empfaenger = (k['empfaenger'] ?? '').toString();
    final dateien = dmarcListe(k['dateien']);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.south_west, size: 15, color: Colors.indigo.shade600),
            const SizedBox(width: 5),
            Text('EINGANG',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: Colors.indigo.shade700)),
          ]),
          Text(dmarcZeit(k['datum']?.toString() ?? ''),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          if ((k['quelle'] ?? '').toString() == 'mail')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                  color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.bolt, size: 10, color: Colors.blue.shade400),
                const SizedBox(width: 2),
                Text('automatisch',
                    style: TextStyle(fontSize: 9, color: Colors.blue.shade700)),
              ]),
            ),
        ]),
        const SizedBox(height: 7),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (betreff.isNotEmpty)
                Text(betreff,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                [if (absender.isNotEmpty) absender, if (empfaenger.isNotEmpty) '→ $empfaenger']
                    .join(' '),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 17, color: Colors.red.shade400),
            tooltip: 'Löschen',
            visualDensity: VisualDensity.compact,
            onPressed: () => _loeschen(k),
          ),
        ]),
        if (dateien.isNotEmpty) ...[
          const SizedBox(height: 9),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final f in dateien) _dateiChip(f)]),
        ],
      ]),
    );
  }

  Widget _dateiChip(Map<String, dynamic> f) {
    final name = (f['original_name'] ?? 'Datei').toString();
    final eml = (f['rolle'] ?? '').toString() == 'eml';
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _oeffnen(f),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: eml ? Colors.blueGrey.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: eml ? Colors.blueGrey.shade200 : Colors.grey.shade200),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(eml ? Icons.mail_outline : Icons.folder_zip_outlined,
              size: 15, color: eml ? Colors.blueGrey.shade600 : Colors.grey.shade600),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(eml ? 'Originalnachricht öffnen' : name,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );
  }

  /// Eine archivierte Nachricht geht in den Mail-Leser. Eine .eml an den
  /// Dateibetrachter zu geben zeigt nichts — der kennt PDFs und Bilder.
  ///
  /// ⚠️ Der Anhang eines Berichts ist ein ZIP oder ein .xml.gz, das der
  /// Betrachter genauso wenig kennt. Er wird deshalb heruntergeladen und dem
  /// System übergeben; wer den Inhalt lesen will, geht in den Tab „Berichte" —
  /// dort steht er ausgewertet.
  Future<void> _oeffnen(Map<String, dynamic> f) async {
    final id = int.tryParse(f['id']?.toString() ?? '') ?? 0;
    if (id == 0) return;
    if ((f['rolle'] ?? '').toString() == 'eml') {
      await KorrespondenzMessageDialog.show(
        context, widget.apiService, id,
        loader: (fid) => widget.apiService.getKorrespondenzMessage(fid, modul: _modul),
      );
      return;
    }
    final r = await widget.apiService.downloadVereinKorrespondenzFile(id, modul: _modul);
    if (!mounted) return;
    if (r == null) {
      widget.melde('Datei konnte nicht geladen werden', fehler: true);
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final sauber = (f['original_name'] ?? 'bericht')
          .toString()
          .replaceAll(RegExp(r'[^\w.\-]'), '_');
      final datei = File('${dir.path}/$sauber');
      await datei.writeAsBytes(r.bodyBytes);
      final auf = await OpenFilex.open(datei.path);
      if (auf.type != ResultType.done) widget.melde('Gespeichert unter ${datei.path}');
    } catch (e) {
      widget.melde('Öffnen fehlgeschlagen: $e', fehler: true);
    }
  }

  Future<void> _loeschen(Map<String, dynamic> k) async {
    final id = int.tryParse(k['id']?.toString() ?? '') ?? 0;
    if (id == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eintrag löschen?', style: TextStyle(fontSize: 15)),
        content: Text(
          '„${k['betreff'] ?? ''}" wird mitsamt Originalnachricht und Anhang entfernt. '
          'Ist die Mail im Postfach schon gelöscht, ist das die letzte Kopie.\n\n'
          'Die ausgewerteten Zahlen im Tab „Berichte" bleiben erhalten.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await widget.apiService.deleteVereinKorrespondenz(id, modul: _modul);
    if (!mounted) return;
    if (r['success'] == true) {
      widget.melde('Eintrag gelöscht');
      await _laden();
    } else {
      widget.melde(r['message']?.toString() ?? 'Löschen fehlgeschlagen', fehler: true);
    }
  }
}

// ═══════════════════ Tab 2: Berichte ═══════════════════

class _DmarcBerichteTab extends StatefulWidget {
  final ApiService apiService;
  final void Function(String, {bool fehler}) melde;

  const _DmarcBerichteTab({required this.apiService, required this.melde});

  @override
  State<_DmarcBerichteTab> createState() => _DmarcBerichteTabState();
}

class _DmarcBerichteTabState extends State<_DmarcBerichteTab>
    with AutomaticKeepAliveClientMixin {
  bool _laeuft = true;
  int _tage = 30;
  Map<String, dynamic> _uebersicht = const {};
  List<Map<String, dynamic>> _quellen = const [];
  List<Map<String, dynamic>> _berichte = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() => _laeuft = true);
    try {
      final r = await widget.apiService.getDmarcBerichte(tage: _tage);
      if (!mounted) return;
      if (r['success'] == true) {
        final d = r['data'] is Map ? Map<String, dynamic>.from(r['data']) : r;
        _uebersicht = dmarcMap(d['uebersicht'] ?? r['uebersicht']);
        _quellen = dmarcListe(d['quellen'] ?? r['quellen']);
        _berichte = dmarcListe(d['berichte'] ?? r['berichte']);
      } else {
        widget.melde(r['message']?.toString() ?? 'Berichte nicht abrufbar', fehler: true);
      }
    } catch (e) {
      if (mounted) widget.melde('Fehler: $e', fehler: true);
    }
    if (mounted) setState(() => _laeuft = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final t in const [7, 30, 90, 365]) ...[
                  ChoiceChip(
                    label: Text(t == 365 ? '1 Jahr' : '$t Tage',
                        style: const TextStyle(fontSize: 12)),
                    selected: _tage == t,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) {
                      setState(() => _tage = t);
                      _laden();
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ]),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Neu laden',
            onPressed: _laden,
          ),
        ]),
      ),
      Expanded(
        child: _laeuft
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _laden,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    _uebersichtKarte(),
                    const SizedBox(height: 18),
                    _abschnitt('Absendende Server', Icons.dns_outlined),
                    const SizedBox(height: 8),
                    if (_quellen.isEmpty)
                      _leer('Keine Meldung in diesem Zeitraum.')
                    else
                      for (final q in _quellen) ...[
                        _quelleKarte(q),
                        const SizedBox(height: 8),
                      ],
                    const SizedBox(height: 12),
                    _abschnitt('Einzelne Berichte', Icons.description_outlined),
                    const SizedBox(height: 8),
                    if (_berichte.isEmpty)
                      _leer('Kein Bericht in diesem Zeitraum.')
                    else
                      for (final b in _berichte) ...[
                        _berichtKarte(b),
                        const SizedBox(height: 8),
                      ],
                  ],
                ),
              ),
      ),
    ]);
  }

  Widget _abschnitt(String titel, IconData ikone) => Row(children: [
        Icon(ikone, size: 17, color: Colors.grey.shade600),
        const SizedBox(width: 7),
        Text(titel,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
      ]);

  Widget _leer(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      );

  Widget _uebersichtKarte() {
    final nachrichten = (_uebersicht['nachrichten'] as num?)?.toInt() ?? 0;
    final bestanden = (_uebersicht['bestanden'] as num?)?.toInt() ?? 0;
    final durch = (_uebersicht['durchgefallen'] as num?)?.toInt() ?? 0;
    final quote = (_uebersicht['quote'] as num?)?.toDouble();
    final melder = (_uebersicht['melder'] as num?)?.toInt() ?? 0;
    final berichte = (_uebersicht['berichte'] as num?)?.toInt() ?? 0;

    // ⚠️ „keine Daten" ist nicht „0 %". Ohne Bericht steht hier ein Strich,
    // nicht eine Null — eine Null hiesse, alles sei durchgefallen.
    final ok = durch == 0 && nachrichten > 0;
    final ton = nachrichten == 0
        ? Colors.grey
        : (ok ? Colors.green : Colors.orange);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ton.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ton.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(nachrichten == 0
              ? Icons.help_outline
              : (ok ? Icons.verified_user : Icons.warning_amber_rounded),
              size: 22, color: ton.shade700),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              nachrichten == 0
                  ? 'Keine Meldung in diesem Zeitraum'
                  : (ok
                      ? 'Alle gemeldeten Nachrichten haben bestanden'
                      : '$durch von $nachrichten Nachrichten sind durchgefallen'),
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: ton.shade800),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 22, runSpacing: 12, children: [
          _zahl('Nachrichten', '$nachrichten'),
          _zahl('bestanden', '$bestanden'),
          _zahl('durchgefallen', '$durch'),
          _zahl('Quote', quote == null ? '–' : '${quote.toStringAsFixed(1)} %'),
          _zahl('Berichte', '$berichte'),
          _zahl('Melder', '$melder'),
        ]),
        const SizedBox(height: 10),
        Text(
          'Gemeldet wird nur Post, die unsere Domain als Absender angibt. '
          'Durchgefallen heisst: weder SPF noch DKIM haben gepasst — entweder '
          'eine Fälschung oder ein eigener Weg, den wir vergessen haben '
          'einzutragen.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.35),
        ),
      ]),
    );
  }

  Widget _zahl(String titel, String wert) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(wert, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        Text(titel, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ]);

  Widget _quelleKarte(Map<String, dynamic> q) {
    final anzahl = (q['anzahl'] as num?)?.toInt() ?? 0;
    final bestanden = (q['bestanden'] as num?)?.toInt() ?? 0;
    final durch = (q['durchgefallen'] as num?)?.toInt() ?? 0;
    final eigen = q['eigen'] == true;
    final ton = durch > 0 ? Colors.orange : (eigen ? Colors.green : Colors.blueGrey);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: durch > 0 ? Colors.orange.shade200 : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(eigen ? Icons.home_outlined : Icons.public, size: 15, color: ton.shade600),
          const SizedBox(width: 6),
          Expanded(
            child: Text((q['source_ip'] ?? '').toString(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Text('$anzahl', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 4),
        Text(
          [
            // Nur exakt bekannte Adressen tragen einen Namen. Eine unbekannte
            // heisst „unbekannt" und wird nicht geraten — falsch als eigener
            // Server beschriftet zu werden ist genau das, was eine Fälschung
            // bräuchte.
            if (eigen) (q['eigen_name'] ?? 'eigener Server').toString() else 'unbekannter Absender',
            '$bestanden bestanden',
            if (durch > 0) '$durch durchgefallen',
          ].join(' · '),
          style: TextStyle(
              fontSize: 11,
              color: durch > 0 ? Colors.orange.shade800 : Colors.grey.shade700),
        ),
        if ((q['spf_domain'] ?? '').toString().isNotEmpty ||
            (q['dkim_domain'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            [
              if ((q['spf_domain'] ?? '').toString().isNotEmpty) 'SPF ${q['spf_domain']}',
              if ((q['dkim_domain'] ?? '').toString().isNotEmpty)
                'DKIM ${q['dkim_domain']}'
                    '${(q['dkim_selector'] ?? '').toString().isEmpty ? '' : ' (${q['dkim_selector']})'}',
            ].join(' · '),
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ]),
    );
  }

  Widget _berichtKarte(Map<String, dynamic> b) {
    final durch = (b['durchgefallen'] as num?)?.toInt() ?? 0;
    final nachrichten = (b['nachrichten'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Icon(durch > 0 ? Icons.error_outline : Icons.check_circle_outline,
            size: 17, color: durch > 0 ? Colors.orange.shade600 : Colors.green.shade600),
        const SizedBox(width: 9),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((b['org_name'] ?? '').toString(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text(
              '${dmarcZeit((b['zeit_von'] ?? '').toString())}'
              ' – ${dmarcZeit((b['zeit_bis'] ?? '').toString())}'
              ' · Regel: ${(b['policy_p'] ?? '?').toString()}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ]),
        ),
        Text('$nachrichten', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

/// „2026-08-23 12:15:10" → „23.08.2026 12:15".
///
/// Die Zeitangaben aus einem Bericht sind UTC — der Server rechnet sie nicht
/// um, weil ein Berichtszeitraum ohnehin ein ganzer Tag in UTC ist und eine
/// Verschiebung um zwei Stunden nur so aussähe, als sei der Tag krumm.
String dmarcZeit(String roh) {
  if (roh.length < 10) return roh;
  final d = roh.substring(0, 10).split('-');
  if (d.length != 3) return roh;
  final uhr = roh.length >= 16 ? ' ${roh.substring(11, 16)}' : '';
  return '${d[2]}.${d[1]}.${d[0]}$uhr';
}
