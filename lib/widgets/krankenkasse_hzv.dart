import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../utils/app_farben.dart';
import '../utils/cloud_picker_helper.dart';
import '../utils/file_picker_helper.dart';
import '../utils/hzv_fristen.dart';
import 'arzt_suche_dialog.dart';
import 'file_viewer_dialog.dart';

/// Behörde ▸ Krankenkasse ▸ **Hausarztprogramm (HZV)** — die Teilnahme des
/// Mitglieds an der hausarztzentrierten Versorgung nach § 73b SGB V.
///
/// Ein Eintrag je Teilnahme, nicht einer je Mitglied: nach einem Hausarztwechsel
/// oder einem Kassenwechsel beginnt eine neue Teilnahme, und die alte ist der
/// Beleg dafür, wie lange die Bindung lief. Ein einzelner überschriebener
/// Datensatz hätte genau diesen Nachweis vernichtet.
///
/// ⚠️ Der Hausarzt kommt aus **demselben Katalog** wie Gesundheit ▸ Hausarzt
/// (`aerzte_datenbank` über [ArztSucheDialog]) — keine zweite Arztliste. Name,
/// Praxis, BSNR und LANR werden trotzdem in die Zeile kopiert: verschwindet die
/// Praxis aus dem Katalog, darf die Akte nicht leer werden.
class KrankenkasseHzvTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  /// Name der zuständigen Kasse aus dem ersten Tab — nur als Vorbelegung.
  final String kasseVorschlag;

  /// Meldet die Zahl der **laufenden** Teilnahmen an die Tab-Leiste.
  final ValueChanged<int> onCountChanged;

  const KrankenkasseHzvTab({
    super.key,
    required this.apiService,
    required this.userId,
    required this.onCountChanged,
    this.kasseVorschlag = '',
  });

  @override
  State<KrankenkasseHzvTab> createState() => _KrankenkasseHzvTabState();
}

class _KrankenkasseHzvTabState extends State<KrankenkasseHzvTab> {
  List<Map<String, dynamic>> _items = [];

  /// Zusätzlich in Gesundheit ▸ Hausarzt erfasste Praxen (zweiter, dritter …).
  List<Map<String, dynamic>> _weitereHausaerzte = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    _hausaerzteLesen();
  }

  Future<void> _load() async {
    final res = await widget.apiService.listHzvTeilnahme(widget.userId);
    if (!mounted) return;
    setState(() {
      _items = List<Map<String, dynamic>>.from(res['teilnahmen'] as List? ?? []);
      _loaded = true;
    });
    widget.onCountChanged(_items.where((e) => hzvLaeuft(e['status']?.toString())).length);
  }

  /// Liest die Hausarzt-Instanzen aus der Gesundheitsakte, um einen zweiten
  /// Hausarzt zu bemerken.
  ///
  /// ⚠️ Ein Fehlschlag bleibt **still**: die Liste bleibt leer, also wird nichts
  /// gemeldet. Eine Fehlermeldung an dieser Stelle wäre für den Vorsitz nicht
  /// handhabbar, und eine erfundene Warnung wäre schlimmer als keine. Der Preis
  /// ist, dass ein Netzfehler den Abgleich stumm ausfallen lässt — deshalb steht
  /// die Prüfung ausdrücklich als Hinweis auf dem Schirm und nicht als Zusicherung.
  Future<void> _hausaerzteLesen() async {
    final gefunden = <Map<String, dynamic>>[];
    try {
      final basis = await widget.apiService.getGesundheitData(widget.userId, 'gesundheit_hausarzt');
      final bd = Map<String, dynamic>.from(basis['data'] as Map? ?? {});
      final anzahl = (bd['instance_count'] as num?)?.toInt() ?? 1;
      // Die erste Instanz ist der reguläre Hausarzt; gemeldet werden nur die
      // WEITEREN — die erste mit dem HZV-Eintrag zu vergleichen wäre der
      // Normalfall und würde bei jedem Mitglied anschlagen.
      for (var i = 2; i <= anzahl && i <= 6; i++) {
        final r = await widget.apiService.getGesundheitData(widget.userId, 'gesundheit_hausarzt_$i');
        final d = Map<String, dynamic>.from(r['data'] as Map? ?? {});
        final arzt = Map<String, dynamic>.from(d['selected_arzt'] as Map? ?? {});
        final name = (arzt['arzt_name']?.toString().trim().isNotEmpty == true)
            ? arzt['arzt_name'].toString()
            : (d['behandelnder_arzt']?.toString() ?? '').trim();
        final id = d['arzt_id'] is int ? d['arzt_id'] as int : int.tryParse(d['arzt_id']?.toString() ?? '');
        if (name.isEmpty && id == null) continue;
        gefunden.add({'arzt_id': id, 'name': name});
      }
    } catch (_) {
      return;
    }
    if (mounted) setState(() => _weitereHausaerzte = gefunden);
  }

  Future<void> _addOrEdit({Map<String, dynamic>? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => HzvEditDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        kasseVorschlag: widget.kasseVorschlag,
        existing: existing,
      ),
    );
    if (saved == true) _load();
  }

  /// Legt einen neuen Eintrag als Wechsel an und übernimmt, was gleich bleibt:
  /// Kasse und Programm. Der Hausarzt bleibt bewusst leer — er ist ja das, was
  /// sich ändert.
  ///
  /// ⚠️ Der alte Eintrag wird **nicht** angefasst. Bis die Kasse den Wechsel
  /// bestätigt, bindet er weiter; ihn hier schon auf „Beendet" zu setzen wäre
  /// eine Behauptung über etwas, das noch niemand entschieden hat.
  Future<void> _wechselBeantragen(Map<String, dynamic> alt) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => HzvEditDialog(
        apiService: widget.apiService,
        userId: widget.userId,
        kasseVorschlag: widget.kasseVorschlag,
        vorlage: {
          'ist_wechsel': true,
          'status': 'eingereicht',
          'kasse_name': alt['kasse_name'],
          'programm_name': alt['programm_name'],
          'kuendigungsfrist': alt['kuendigungsfrist'],
          'abgabe_ort': 'praxis',
        },
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Teilnahme löschen?'),
        content: const Text(
            'Der Eintrag und alle angehängten Dokumente (Teilnahmeerklärung, '
            'Kündigung …) werden gelöscht.\n\n'
            'Für eine beendete Teilnahme ist der Status „Beendet" der richtige Weg — '
            'gelöscht ist der Nachweis der Bindungszeit weg.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Löschen', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await widget.apiService.deleteHzvTeilnahme(t['id'] as int);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final laufend = _items.where((e) => hzvLaeuft(e['status']?.toString())).length;

    final konflikte = hzvKonflikte(_items, weitereHausaerzte: _weitereHausaerzte);

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: F.h(Colors.teal, 50),
        child: Row(children: [
          Icon(Icons.medical_services, size: 18, color: F.h(Colors.teal, 700)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Hausarztprogramm / HZV — ${_items.length} Eintrag${_items.length == 1 ? '' : 'e'}'
              '${laufend > 0 ? ', $laufend laufend' : ''}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 800)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => _addOrEdit(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neue Teilnahme', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ]),
      ),
      if (konflikte.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Column(children: [for (final k in konflikte) _konfliktKarte(k)]),
        ),
      Expanded(
        child: _items.isEmpty
            ? _leer()
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _items.length + 1,
                itemBuilder: (_, i) => i == _items.length
                    ? const Padding(padding: EdgeInsets.only(top: 8), child: HzvRechtsHinweis())
                    : _karte(_items[i]),
              ),
      ),
    ]);
  }

  Widget _konfliktKarte(HzvKonflikt k) {
    final farbe = k.art == HzvHinweisArt.warnung ? Colors.orange : Colors.blue;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: F.h(farbe, 50),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: F.h(farbe, 300)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(k.art == HzvHinweisArt.warnung ? Icons.warning_amber : Icons.info_outline,
            size: 18, color: F.h(farbe, 800)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Mehr als ein Hausarzt',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(farbe, 900))),
            const SizedBox(height: 2),
            Text(k.text, style: TextStyle(fontSize: 12, color: F.h(farbe, 900))),
            if (k.handlung != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('→ ${k.handlung}',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: F.h(farbe, 900))),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _leer() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Icon(Icons.medical_services_outlined, size: 64, color: F.h(Colors.grey, 300)),
          const SizedBox(height: 12),
          Text('Keine HZV-Teilnahme erfasst',
              style: TextStyle(color: F.h(Colors.grey, 600), fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'Ein Eintrag hält fest: welcher Hausarzt gewählt wurde, wo und wann die '
            'Teilnahmeerklärung abgegeben wurde und ob die Teilnahme aktiv, gekündigt '
            'oder widerrufen ist.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)),
          ),
          const SizedBox(height: 20),
          const HzvRechtsHinweis(),
        ]),
      );

  Widget _karte(Map<String, dynamic> t) {
    final status = t['status']?.toString() ?? 'eingereicht';
    final farbe = _statusFarbe(status);
    final arzt = (t['arzt_name']?.toString() ?? '').trim();
    final praxis = (t['praxis_name']?.toString() ?? '').trim();
    final ort = (t['praxis_ort']?.toString() ?? '').trim();
    final programm = (t['programm_name']?.toString() ?? '').trim();
    final kasse = (t['kasse_name']?.toString() ?? '').trim();
    final docs = ((t['dok_anzahl'] as num?) ?? 0).toInt();
    final hinweise = hzvHinweise(t, heute: DateTime.now());
    final vertretung = (t['vertretungsarzt']?.toString() ?? '').trim();
    final gruende = (t['wechsel_gruende'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    final grundText = (t['wechsel_grund_text']?.toString() ?? '').trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: F.h(farbe, 50),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: F.h(farbe, 300)),
              ),
              child: Text(hzvStatusLabel[status] ?? status,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: F.h(farbe, 800))),
            ),
            if (t['ist_wechsel'] == true) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: F.h(Colors.indigo, 50),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: F.h(Colors.indigo, 300)),
                ),
                child: Text('Hausarztwechsel',
                    style: TextStyle(fontSize: 11, color: F.h(Colors.indigo, 800))),
              ),
            ],
            const Spacer(),
            if (hzvLaeuft(status))
              IconButton(
                tooltip: 'Hausarztwechsel beantragen',
                icon: const Icon(Icons.swap_horiz, size: 18),
                onPressed: () => _wechselBeantragen(t),
              ),
            IconButton(
              tooltip: 'Bearbeiten',
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _addOrEdit(existing: t),
            ),
            IconButton(
              tooltip: 'Löschen',
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              onPressed: () => _delete(t),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            arzt.isNotEmpty ? arzt : (praxis.isNotEmpty ? praxis : 'Hausarzt nicht eingetragen'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          if (praxis.isNotEmpty && arzt.isNotEmpty)
            Text([praxis, if (ort.isNotEmpty) ort].join(' · '),
                style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)))
          else if (ort.isNotEmpty)
            Text(ort, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
          if (programm.isNotEmpty || kasse.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text([if (programm.isNotEmpty) programm, if (kasse.isNotEmpty) kasse].join(' · '),
                  style: TextStyle(fontSize: 12, color: F.h(Colors.teal, 700))),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 4, children: [
            _feld('Unterschrieben', t['unterschrieben_am']),
            if ((t['belehrung_am']?.toString() ?? '').isNotEmpty)
              _feld('Belehrung erhalten', t['belehrung_am']),
            _feld('Bei der Kasse', t['eingang_kasse_am']),
            _feld('Beginn', t['beginn_am']),
            _feld('Bindung bis', t['bindung_bis'] ?? t['bindung_bis_berechnet'],
                abgeleitet: (t['bindung_bis']?.toString() ?? '').isEmpty),
            if ((t['widerruf_am']?.toString() ?? '').isNotEmpty) _feld('Widerruf', t['widerruf_am']),
            if ((t['kuendigung_am']?.toString() ?? '').isNotEmpty) _feld('Gekündigt am', t['kuendigung_am']),
            if ((t['kuendigung_zum']?.toString() ?? '').isNotEmpty) _feld('Wirksam zum', t['kuendigung_zum']),
            if ((t['ende_am']?.toString() ?? '').isNotEmpty) _feld('Ende', t['ende_am']),
          ]),
          const SizedBox(height: 6),
          Text(
            'Abgegeben: ${hzvAbgabeOrtLabel[t['abgabe_ort']?.toString()] ?? '–'}'
            '${(t['abgabe_detail']?.toString() ?? '').isNotEmpty ? ' (${t['abgabe_detail']})' : ''}',
            style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)),
          ),
          if (vertretung.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Benannter HZV-Vertretungsarzt: $vertretung',
                  style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
            ),
          if (gruende.isNotEmpty || grundText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Grund für den Wechsel',
                style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
            for (final g in gruende)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(
                      hzvHaertefallGruende.contains(g) ? Icons.gavel : Icons.circle,
                      size: hzvHaertefallGruende.contains(g) ? 12 : 6,
                      color: F.h(Colors.indigo, 600)),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(hzvWechselGrundLabel[g] ?? g,
                          style: const TextStyle(fontSize: 12))),
                ]),
              ),
            if (grundText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(grundText, style: const TextStyle(fontSize: 12)),
              ),
            if (gruende.isNotEmpty && !gruende.any(hzvHaertefallGruende.contains))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '⚠️ Kein Härtefallgrund angegeben — ein Wechsel VOR Ablauf der '
                  'zwölf Monate braucht einen (Praxis nimmt nicht mehr teil, Umzug, '
                  'Praxisschließung, gestörtes Vertrauensverhältnis).',
                  style: TextStyle(fontSize: 11, color: F.h(Colors.orange, 900)),
                ),
              ),
          ],
          if ((t['datenweitergabe']?.toString() ?? 'unbekannt') != 'unbekannt')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'Unterlagen an die neue Praxis: '
                  '${hzvDatenweitergabeLabel[t['datenweitergabe']?.toString()] ?? '–'}',
                  style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
            ),
          if ((t['kuendigungsfrist']?.toString() ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Kündigungsfrist laut Kasse: ${t['kuendigungsfrist']}',
                  style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
            ),
          if ((t['notiz']?.toString() ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(t['notiz'].toString(), style: const TextStyle(fontSize: 12)),
            ),
          for (final h in hinweise)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: F.h(h.art == HzvHinweisArt.warnung ? Colors.orange : Colors.blue, 50),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: F.h(h.art == HzvHinweisArt.warnung ? Colors.orange : Colors.blue, 200)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(h.art == HzvHinweisArt.warnung ? Icons.warning_amber : Icons.info_outline,
                      size: 16,
                      color: F.h(h.art == HzvHinweisArt.warnung ? Colors.orange : Colors.blue, 800)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(h.text,
                        style: TextStyle(
                            fontSize: 12,
                            color: F.h(h.art == HzvHinweisArt.warnung ? Colors.orange : Colors.blue, 900))),
                  ),
                ]),
              ),
            ),
          const Divider(height: 20),
          HzvDokumenteSection(
            apiService: widget.apiService,
            userId: widget.userId,
            hzvId: t['id'] as int,
            anzahlVorbelegt: docs,
            onChanged: _load,
          ),
        ]),
      ),
    );
  }

  Widget _feld(String label, dynamic wert, {bool abgeleitet = false}) {
    final s = wert?.toString() ?? '';
    final d = s.isEmpty ? null : DateTime.tryParse(s);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(abgeleitet ? '$label (berechnet)' : label,
          style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
      Text(d == null ? '–' : DateFormat('dd.MM.yyyy').format(d),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }

  MaterialColor _statusFarbe(String s) => switch (s) {
        'aktiv' => Colors.green,
        'eingereicht' => Colors.amber,
        'widerrufen' => Colors.purple,
        'gekuendigt' => Colors.orange,
        'abgelehnt' => Colors.red,
        _ => Colors.grey,
      };
}

/// Was gesetzlich feststeht, steht auf dem Schirm — sonst müsste es jemand
/// jedes Mal nachschlagen, und beim zweiten Mal schlägt es niemand nach.
class HzvRechtsHinweis extends StatelessWidget {
  const HzvRechtsHinweis({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: F.h(Colors.blueGrey, 50),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: F.h(Colors.blueGrey, 200)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.gavel, size: 15, color: F.h(Colors.blueGrey, 700)),
            const SizedBox(width: 6),
            Text('Was für jede Kasse gilt (§ 73b SGB V)',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.blueGrey, 900))),
          ]),
          const SizedBox(height: 6),
          _z('Die Teilnahme ist freiwillig und kostenfrei.'),
          _z('Widerruf innerhalb von zwei Wochen, ohne Angabe von Gründen — schriftlich, '
              'elektronisch oder zur Niederschrift. Zur Fristwahrung genügt das rechtzeitige '
              'ABSCHICKEN; ankommen muss er nicht rechtzeitig.'),
          _z('⚠️ Die zwei Wochen laufen ab dem Erhalt der WIDERRUFSBELEHRUNG, frühestens '
              'aber ab der Unterschrift — der spätere Tag zählt. Steht die Belehrung auf dem '
              'Formular (Regelfall), fallen beide zusammen; kommt sie per Post, beginnt die '
              'Frist erst dann. Das Begrüßungsschreiben ist NICHT die Belehrung.'),
          _z('Danach ist das Mitglied mindestens zwölf Monate an die Teilnahme UND an '
              'den gewählten Hausarzt gebunden.'),
          _z('Die HZV bindet an GENAU EINEN Hausarzt. Andere Ärzte nur nach dessen '
              'Überweisung (Ausnahmen: Notfall, Gynäkologie, Augenarzt, Zahnarzt, '
              'Kinder- und Jugendarzt). Der einzige zulässige zweite Hausarzt ist der von '
              'ihm benannte HZV-Vertretungsarzt für Urlaub und Krankheit; die gleichzeitige '
              'Teilnahme an einem weiteren Hausarztprogramm ist ausgeschlossen.'),
          _z('Bei wiederholtem Verstoß gegen die Teilnahmebedingungen kann die Kasse die '
              'Teilnahme kündigen und Mehrkosten geltend machen.'),
          _z('Ein Hausarztwechsel muss SCHRIFTLICH erklärt werden. Vor Ablauf der zwölf '
              'Monate geht er nur aus wichtigem Grund: die Praxis nimmt nicht mehr teil, '
              'Praxis oder Mitglied ziehen um und die Entfernung ist nicht zumutbar, '
              'Praxisschließung, oder das Vertrauensverhältnis ist nachhaltig gestört.'),
          _z('Die bisherige Praxis gibt ihre Unterlagen an die neue nur weiter, wenn das '
              'Mitglied es ausdrücklich wünscht.'),
          _z('Mit dem Ende der Mitgliedschaft bei der Kasse endet auch die Teilnahme — '
              'bei der neuen Kasse muss neu eingeschrieben werden.'),
          const SizedBox(height: 6),
          Text(
            '⚠️ Kündigungsfrist, Beginn und Vorlauf für einen Wechsel stehen NICHT im Gesetz, '
            'sondern im Vertrag der jeweiligen Kasse — und sie weichen bei jeder ab, die wir '
            'nachgesehen haben: AOK Baden-Württemberg ein Monat zum Ablauf des '
            '12-Monats-Zeitraums (neue Teilnahmeerklärung zwei Monate vorher) · TK vier '
            'Wochen zum Ende des Teilnahmejahres, danach zum Quartalsende · Ersatzkassen '
            'acht Wochen vor Ablauf. Deshalb werden sie hier eingetragen und nicht gerechnet.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.blueGrey, 800)),
          ),
        ]),
      );

  Widget _z(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('· ', style: TextStyle(fontSize: 11)),
          Expanded(child: Text(s, style: const TextStyle(fontSize: 11))),
        ]),
      );
}

// ══════════════════ Bearbeiten ══════════════════════════════════════════

class HzvEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String kasseVorschlag;
  final Map<String, dynamic>? existing;

  /// Vorbelegung für einen NEUEN Eintrag (Hausarztwechsel): übernimmt, was
  /// gleich bleibt. Wird ignoriert, wenn [existing] gesetzt ist.
  final Map<String, dynamic>? vorlage;

  const HzvEditDialog({
    super.key,
    required this.apiService,
    required this.userId,
    this.kasseVorschlag = '',
    this.existing,
    this.vorlage,
  });

  @override
  State<HzvEditDialog> createState() => _HzvEditDialogState();
}

class _HzvEditDialogState extends State<HzvEditDialog> {
  late TextEditingController _kasseC, _programmC, _arztC, _praxisC, _ortC,
      _bsnrC, _lanrC, _teIdC, _abgabeDetailC, _fristC, _endeGrundC, _notizC,
      _vertretungC, _grundTextC;
  late TextEditingController _unterschriebenC, _belehrungC, _eingangC, _beginnC,
      _bindungC, _widerrufC, _kuendAmC, _kuendZumC, _endeC;
  String _status = 'eingereicht';
  String _abgabeOrt = 'praxis';
  String _datenweitergabe = 'unbekannt';
  bool _istWechsel = false;
  final Set<String> _gruende = {};
  int? _arztId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Vorbelegung gilt nur beim Anlegen — beim Bearbeiten zählt allein der Stand.
    final e = widget.existing ?? widget.vorlage ?? <String, dynamic>{};
    String v(String k) => e[k]?.toString() ?? '';
    _kasseC = TextEditingController(
        text: v('kasse_name').isNotEmpty ? v('kasse_name') : widget.kasseVorschlag);
    _programmC = TextEditingController(text: v('programm_name'));
    _arztC = TextEditingController(text: v('arzt_name'));
    _praxisC = TextEditingController(text: v('praxis_name'));
    _ortC = TextEditingController(text: v('praxis_ort'));
    _bsnrC = TextEditingController(text: v('bsnr'));
    _lanrC = TextEditingController(text: v('lanr'));
    _teIdC = TextEditingController(text: v('te_id'));
    _abgabeDetailC = TextEditingController(text: v('abgabe_detail'));
    _fristC = TextEditingController(text: v('kuendigungsfrist'));
    _endeGrundC = TextEditingController(text: v('ende_grund'));
    _notizC = TextEditingController(text: v('notiz'));
    _vertretungC = TextEditingController(text: v('vertretungsarzt'));
    _grundTextC = TextEditingController(text: v('wechsel_grund_text'));
    _unterschriebenC = TextEditingController(text: v('unterschrieben_am'));
    _belehrungC = TextEditingController(text: v('belehrung_am'));
    _eingangC = TextEditingController(text: v('eingang_kasse_am'));
    _beginnC = TextEditingController(text: v('beginn_am'));
    _bindungC = TextEditingController(text: v('bindung_bis'));
    _widerrufC = TextEditingController(text: v('widerruf_am'));
    _kuendAmC = TextEditingController(text: v('kuendigung_am'));
    _kuendZumC = TextEditingController(text: v('kuendigung_zum'));
    _endeC = TextEditingController(text: v('ende_am'));
    _status = v('status').isEmpty ? 'eingereicht' : v('status');
    _abgabeOrt = v('abgabe_ort').isEmpty ? 'praxis' : v('abgabe_ort');
    _istWechsel = e['ist_wechsel'] == true;
    _datenweitergabe = v('datenweitergabe').isEmpty ? 'unbekannt' : v('datenweitergabe');
    _gruende.addAll(((e['wechsel_gruende'] as List?) ?? const [])
        .map((g) => g.toString())
        .where(hzvWechselGrundLabel.containsKey));
    // Nur beim Wechsel wird ein Arzt neu gewählt — bei einer Vorbelegung bleibt
    // das Feld deshalb leer, obwohl Kasse und Programm übernommen werden.
    _arztId = widget.existing == null
        ? null
        : (e['arzt_id'] is int ? e['arzt_id'] as int : int.tryParse(v('arzt_id')));
  }

  @override
  void dispose() {
    for (final c in [
      _kasseC, _programmC, _arztC, _praxisC, _ortC, _bsnrC, _lanrC, _teIdC,
      _abgabeDetailC, _fristC, _endeGrundC, _notizC, _vertretungC, _grundTextC,
      _unterschriebenC, _belehrungC, _eingangC, _beginnC, _bindungC, _widerrufC,
      _kuendAmC, _kuendZumC, _endeC,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(TextEditingController c) async {
    final init = DateTime.tryParse(c.text) ?? DateTime.now();
    final p = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2005),
      lastDate: DateTime(2060),
      locale: const Locale('de'),
    );
    if (p != null) setState(() => c.text = DateFormat('yyyy-MM-dd').format(p));
  }

  /// Hausarzt aus demselben Katalog wie Gesundheit ▸ Hausarzt. BSNR und LANR
  /// stehen dort bereits — genau die zwei Nummern, die auf der
  /// Teilnahmeerklärung stehen; sie bleiben überschreibbar, weil eine
  /// Betriebsstätte mehrere Arztnummern führen kann.
  void _arztWaehlen() {
    ArztSucheDialog.oeffnen(
      context: context,
      fachrichtung: 'Allgemeinmedizin / Innere Medizin',
      katalog: arztKatalog((s) => widget.apiService.searchAerzte(search: s)),
      titel: 'Hausarzt aus Datenbank auswählen',
      onSelect: (a) {
        setState(() {
          _arztId = a['id'] is int ? a['id'] as int : int.tryParse(a['id']?.toString() ?? '');
          _arztC.text = a['arzt_name']?.toString() ?? _arztC.text;
          _praxisC.text = a['praxis_name']?.toString() ?? _praxisC.text;
          _ortC.text = a['plz_ort']?.toString() ?? _ortC.text;
          if ((a['bsnr']?.toString() ?? '').isNotEmpty) _bsnrC.text = a['bsnr'].toString();
          if ((a['lanr']?.toString() ?? '').isNotEmpty) _lanrC.text = a['lanr'].toString();
        });
      },
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    String t(TextEditingController c) => c.text.trim();
    String? d(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final res = await widget.apiService.saveHzvTeilnahme(widget.userId, {
      if (widget.existing != null) 'id': widget.existing!['id'],
      'status': _status,
      'abgabe_ort': _abgabeOrt,
      'ist_wechsel': _istWechsel,
      'arzt_id': _arztId,
      'unterschrieben_am': d(_unterschriebenC),
      'belehrung_am': d(_belehrungC),
      'eingang_kasse_am': d(_eingangC),
      'beginn_am': d(_beginnC),
      'bindung_bis': d(_bindungC),
      'widerruf_am': d(_widerrufC),
      'kuendigung_am': d(_kuendAmC),
      'kuendigung_zum': d(_kuendZumC),
      'ende_am': d(_endeC),
      'kasse_name': t(_kasseC),
      'programm_name': t(_programmC),
      'arzt_name': t(_arztC),
      'praxis_name': t(_praxisC),
      'praxis_ort': t(_ortC),
      'vertretungsarzt': t(_vertretungC),
      'wechsel_gruende': _gruende.toList(),
      'wechsel_grund_text': t(_grundTextC),
      'datenweitergabe': _datenweitergabe,
      'bsnr': t(_bsnrC),
      'lanr': t(_lanrC),
      'te_id': t(_teIdC),
      'abgabe_detail': t(_abgabeDetailC),
      'kuendigungsfrist': t(_fristC),
      'ende_grund': t(_endeGrundC),
      'notiz': t(_notizC),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Fehler'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Vorschau derselben Rechnung, die die Liste anzeigt — damit sichtbar ist,
    // was ein eingetragener Beginn nach sich zieht, bevor gespeichert wird.
    final belehrung = DateTime.tryParse(_belehrungC.text);
    final wBis = hzvWiderrufBis(DateTime.tryParse(_unterschriebenC.text), belehrung);
    final bBis = hzvBindungBis(DateTime.tryParse(_beginnC.text));

    return AlertDialog(
      title: Text(widget.existing == null ? 'Neue HZV-Teilnahme' : 'HZV-Teilnahme bearbeiten'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _ueberschrift('Hausarzt'),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _arztC,
                  decoration: const InputDecoration(
                      labelText: 'Hausarzt (Name)', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Aus Ärzte-Datenbank wählen',
                icon: const Icon(Icons.search),
                onPressed: _arztWaehlen,
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _praxisC,
                      decoration: const InputDecoration(
                          labelText: 'Praxis', isDense: true, border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _ortC,
                      decoration: const InputDecoration(
                          labelText: 'PLZ / Ort', isDense: true, border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _bsnrC,
                      decoration: const InputDecoration(
                          labelText: 'Betriebsstätten-Nr. (BSNR)',
                          isDense: true,
                          border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _lanrC,
                      decoration: const InputDecoration(
                          labelText: 'Arzt-Nr. (LANR)', isDense: true, border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _vertretungC,
              decoration: const InputDecoration(
                labelText: 'Benannter HZV-Vertretungsarzt',
                hintText: 'für Urlaub und Krankheit des gewählten Hausarztes',
                helperText: 'Der einzige zweite Arzt, den die HZV erlaubt.',
                helperMaxLines: 2,
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),

            _ueberschrift('Vertrag'),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _kasseC,
                      decoration: const InputDecoration(
                          labelText: 'Krankenkasse', isDense: true, border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _programmC,
                      decoration: const InputDecoration(
                          labelText: 'Programmname',
                          hintText: 'z. B. AOK-HausarztProgramm',
                          isDense: true,
                          border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _abgabeOrt,
                  decoration: const InputDecoration(
                      labelText: 'Wo abgegeben?', isDense: true, border: OutlineInputBorder()),
                  items: hzvAbgabeOrtLabel.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _abgabeOrt = v ?? 'praxis'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: _abgabeDetailC,
                      decoration: const InputDecoration(
                          labelText: 'Genauer (Geschäftsstelle, Portal …)',
                          isDense: true,
                          border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: _teIdC,
                      decoration: const InputDecoration(
                          labelText: 'TE-ID / Vorgangsnummer',
                          isDense: true,
                          border: OutlineInputBorder()))),
            ]),

            _ueberschrift('Fristen'),
            Row(children: [
              Expanded(child: _datum(_unterschriebenC, 'Unterschrieben am')),
              const SizedBox(width: 8),
              Expanded(child: _datum(_eingangC, 'Bei der Kasse eingegangen')),
            ]),
            const SizedBox(height: 10),
            _datum(_belehrungC, 'Widerrufsbelehrung erhalten am'),
            if (wBis != null)
              _rechnung(
                'Widerruf ohne Begründung möglich bis '
                '${DateFormat('dd.MM.yyyy').format(wBis)}. Die Frist beginnt mit dem '
                'Erhalt der Widerrufsbelehrung, frühestens mit der Abgabe — der '
                'spätere Tag zählt (§ 73b Abs. 3 SGB V). Abschicken genügt.'
                '${belehrung == null ? ' ⚠️ Ohne Belehrungsdatum ab der Unterschrift '
                    'gerechnet; kam die Belehrung erst per Post, ist der letzte Tag '
                    'später. Die Belehrung ist NICHT das Begrüßungsschreiben.' : ''}',
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _datum(_beginnC, 'Teilnahme beginnt am')),
              const SizedBox(width: 8),
              Expanded(child: _datum(_bindungC, 'Mindestbindung bis')),
            ]),
            if (bBis != null && _bindungC.text.trim().isEmpty)
              _rechnung('Zwölf Monate ab Beginn enden am '
                  '${DateFormat('dd.MM.yyyy').format(bBis)}. Steht im Begrüßungsschreiben ein '
                  'anderes Datum, hier eintragen — dann gilt das eingetragene.'),
            const SizedBox(height: 10),
            TextField(
              controller: _fristC,
              decoration: const InputDecoration(
                labelText: 'Kündigungsfrist laut Kasse (Wortlaut)',
                hintText: 'z. B. 4 Wochen zum Ende des Teilnahmejahres',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),

            _ueberschrift('Hausarztwechsel'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _istWechsel,
              onChanged: (v) => setState(() => _istWechsel = v ?? false),
              title: const Text('Dieser Eintrag ist ein Hausarztwechsel',
                  style: TextStyle(fontSize: 13)),
              subtitle: const Text(
                  'Ein Wechsel muss schriftlich erklärt werden. Vor Ablauf der zwölf '
                  'Monate geht er nur mit einem Härtefallgrund (⚖).',
                  style: TextStyle(fontSize: 11)),
            ),
            if (_istWechsel) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Gründe — mehrere möglich',
                    style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                children: [
                  for (final g in hzvWechselGrundReihenfolge)
                    FilterChip(
                      label: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (hzvHaertefallGruende.contains(g)) ...[
                          Icon(Icons.gavel, size: 12, color: F.h(Colors.indigo, 700)),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(hzvWechselGrundLabel[g]!,
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ]),
                      selected: _gruende.contains(g),
                      onSelected: (an) => setState(
                          () => an ? _gruende.add(g) : _gruende.remove(g)),
                    ),
                ],
              ),
              if (_gruende.isNotEmpty && !_gruende.any(hzvHaertefallGruende.contains))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '⚠️ Darunter ist kein Härtefallgrund. Nach Ablauf der zwölf Monate '
                    'ist das in Ordnung; davor trägt der Wechsel nur mit einem der mit '
                    '⚖ gekennzeichneten Gründe.',
                    style: TextStyle(fontSize: 11, color: F.h(Colors.orange, 900)),
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _grundTextC,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Grund in eigenen Worten (für die Erklärung an die Kasse)',
                    isDense: true,
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _datenweitergabe,
                decoration: const InputDecoration(
                  labelText: 'Unterlagen an die neue Praxis?',
                  helperText: 'Der bisherige Hausarzt gibt sie nur weiter, wenn das '
                      'ausdrücklich gewünscht ist.',
                  helperMaxLines: 2,
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: hzvDatenweitergabeLabel.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _datenweitergabe = v ?? 'unbekannt'),
              ),
            ],

            _ueberschrift('Stand'),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _status,
              decoration:
                  const InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder()),
              items: hzvStatusReihenfolge
                  .map((k) => DropdownMenuItem(value: k, child: Text(hzvStatusLabel[k]!)))
                  .toList(),
              onChanged: (v) => setState(() => _status = v ?? 'eingereicht'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _datum(_widerrufC, 'Widerruf abgeschickt am')),
              const SizedBox(width: 8),
              Expanded(child: _datum(_kuendAmC, 'Kündigung abgeschickt am')),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _datum(_kuendZumC, 'Kündigung wirksam zum')),
              const SizedBox(width: 8),
              Expanded(child: _datum(_endeC, 'Teilnahme beendet am')),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _endeGrundC,
              decoration: const InputDecoration(
                  labelText: 'Grund für das Ende',
                  hintText: 'z. B. Kassenwechsel, Praxis nimmt nicht mehr teil',
                  isDense: true,
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notizC,
              maxLines: 2,
              decoration:
                  const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder()),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 16),
          label: const Text('Speichern'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
        ),
      ],
    );
  }

  Widget _ueberschrift(String s) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Row(children: [
          Text(s, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 800))),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: F.h(Colors.teal, 100))),
        ]),
      );

  Widget _datum(TextEditingController c, String label) => TextField(
        controller: c,
        readOnly: true,
        onTap: () => _pick(c),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: c.text.isEmpty
              ? const Icon(Icons.calendar_today, size: 16)
              : IconButton(
                  tooltip: 'Datum leeren',
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () => setState(() => c.clear()),
                ),
        ),
      );

  Widget _rechnung(String s) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.calculate_outlined, size: 14, color: F.h(Colors.blue, 700)),
          const SizedBox(width: 6),
          Expanded(child: Text(s, style: TextStyle(fontSize: 11, color: F.h(Colors.blue, 900)))),
        ]),
      );
}

// ══════════════════ Dokumente ═══════════════════════════════════════════

/// Anhänge zu einer Teilnahme: Teilnahmeerklärung, Begrüßungsschreiben,
/// Widerruf, Kündigung. Aufbau wie die Krankengeld-Anhänge (Gerät + Cloud,
/// bis 20 Dateien je Durchgang).
class HzvDokumenteSection extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int hzvId;
  final int anzahlVorbelegt;
  final VoidCallback? onChanged;

  const HzvDokumenteSection({
    super.key,
    required this.apiService,
    required this.userId,
    required this.hzvId,
    this.anzahlVorbelegt = 0,
    this.onChanged,
  });

  @override
  State<HzvDokumenteSection> createState() => _HzvDokumenteSectionState();
}

class _HzvDokumenteSectionState extends State<HzvDokumenteSection> {
  static const _erlaubteTypen = ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'odt', 'txt'];

  List<Map<String, dynamic>> _items = [];
  bool _offen = false;
  bool _loaded = false;
  bool _uploading = false;
  int _done = 0, _total = 0;
  String _dokTyp = 'teilnahmeerklaerung';

  Future<void> _load() async {
    final res = await widget.apiService.listHzvDocs(widget.hzvId);
    if (!mounted) return;
    setState(() {
      _items = List<Map<String, dynamic>>.from(res['items'] as List? ?? []);
      _loaded = true;
    });
  }

  Future<void> _upload({FilePickerResult? ausCloud}) async {
    final r = ausCloud ??
        await FilePickerHelper.pickFiles(
          allowMultiple: true,
          type: FileType.custom,
          allowedExtensions: _erlaubteTypen,
        );
    if (r == null || r.files.isEmpty) return;
    var files = r.files.where((f) => f.path != null).toList();
    if (!mounted) return;
    final scaffold = ScaffoldMessenger.of(context);
    if (files.length > 20) {
      scaffold.showSnackBar(SnackBar(
          content: Text('Max. 20 Dateien — ${files.length - 20} ausgelassen'),
          backgroundColor: Colors.orange));
      files = files.sublist(0, 20);
    }
    setState(() {
      _uploading = true;
      _done = 0;
      _total = files.length;
    });
    final fehler = <String>[];
    for (final f in files) {
      final res = await widget.apiService
          .uploadHzvDoc(hzvId: widget.hzvId, filePath: f.path!, fileName: f.name, dokTyp: _dokTyp);
      if (res['success'] == true) {
        _done++;
      } else {
        fehler.add('${f.name}: ${res['message'] ?? '?'}');
      }
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    scaffold.showSnackBar(SnackBar(
      content: Text(fehler.isEmpty
          ? '$_done/$_total Datei(en) hochgeladen'
          : '$_done OK, ${fehler.length} fehlgeschlagen:\n${fehler.join("\n")}'),
      backgroundColor: fehler.isEmpty ? Colors.green : Colors.orange,
      duration: const Duration(seconds: 4),
    ));
    widget.onChanged?.call();
    _load();
  }

  Future<void> _ausCloud() async {
    final res = await CloudPickerHelper.uebernehmen(
      context,
      apiService: widget.apiService,
      memberId: widget.userId,
      attach: (id) => widget.apiService
          .attachHzvDocFromCloud(hzvId: widget.hzvId, cloudFileId: id, dokTyp: _dokTyp),
      allowedExtensions: _erlaubteTypen,
      maxFiles: 20,
      hochladen: (r) => _upload(ausCloud: r),
    );
    if (res == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${res.ok} von ${res.total} aus Cloud übernommen'
          '${res.grund != null ? ' — ${res.grund}' : ''}'),
      backgroundColor: res.ok == res.total ? Colors.green : Colors.orange,
    ));
    widget.onChanged?.call();
    _load();
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Datei löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Löschen', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await widget.apiService.deleteHzvDoc(id);
    if (res['success'] == true) {
      widget.onChanged?.call();
      _load();
    }
  }

  Future<void> _oeffnen(Map<String, dynamic> d) async {
    try {
      final resp = await widget.apiService.downloadHzvDoc(d['id'] as int);
      if (resp.statusCode != 200 || !mounted) return;
      final name = (d['datei_name']?.toString() ?? 'hzv_${d['id']}.pdf')
          .replaceAll(RegExp(r'[<>:"|?*\\/]'), '_');
      await FileViewerDialog.showFromBytes(context, resp.bodyBytes, name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final anzahl = _loaded ? _items.length : widget.anzahlVorbelegt;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      InkWell(
        onTap: () {
          setState(() => _offen = !_offen);
          if (_offen && !_loaded) _load();
        },
        child: Row(children: [
          Icon(_offen ? Icons.expand_less : Icons.expand_more, size: 18, color: F.h(Colors.teal, 700)),
          const SizedBox(width: 4),
          Icon(Icons.folder_zip, size: 16, color: F.h(Colors.teal, 700)),
          const SizedBox(width: 6),
          Text('Dokumente ($anzahl)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 800))),
        ]),
      ),
      if (_offen) ...[
        const SizedBox(height: 8),
        if (!_loaded)
          const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
        else ...[
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _dokTyp,
                decoration: const InputDecoration(
                    labelText: 'Art der neuen Datei', isDense: true, border: OutlineInputBorder()),
                items: hzvDokTypLabel.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _dokTyp = v ?? 'sonstiges'),
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _ausCloud,
              icon: const Icon(Icons.cloud_download, size: 14),
              label: const Text('Aus Cloud', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: F.h(Colors.blue, 700),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  minimumSize: Size.zero),
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              onPressed: _uploading ? null : () => _upload(),
              icon: _uploading
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_file, size: 14),
              label: Text(_uploading ? '$_done / $_total …' : 'Hochladen',
                  style: const TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  minimumSize: Size.zero),
            ),
          ]),
          const SizedBox(height: 6),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Keine Dateien — die unterschriebene Teilnahmeerklärung gehört hierher.',
                  style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
            )
          else
            ..._items.map((d) {
              final kb = ((d['file_size'] as num?) ?? 0).toInt() ~/ 1024;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Icon(Icons.description, size: 16, color: Colors.teal.shade400),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d['datei_name']?.toString() ?? '?',
                          style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      Text(
                          '${hzvDokTypLabel[d['dok_typ']?.toString()] ?? 'Sonstiges'} · $kb KB',
                          style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
                    ]),
                  ),
                  IconButton(
                      tooltip: 'Öffnen',
                      icon: const Icon(Icons.visibility, size: 16),
                      onPressed: () => _oeffnen(d)),
                  IconButton(
                      tooltip: 'Löschen',
                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      onPressed: () => _delete(d['id'] as int)),
                ]),
              );
            }),
        ],
      ],
    ]);
  }
}
