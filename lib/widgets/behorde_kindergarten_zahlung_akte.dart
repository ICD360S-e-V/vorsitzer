/// Der einzelne Vorgang von Kindergarten ▸ Zahlung.
///
/// Details · Korrespondenz · Akteneinsicht · Ratenzahlung · Ermäßigung ·
/// Vollmacht · Mahnverfahren.
///
/// 🔴 DIE REGEL, DIE DIESE DATEI ZUSAMMENHÄLT: DER EMPFÄNGER WIRD HIER NIE
/// GEWÄHLT.
///
/// Jede Vorlage bringt vom Server ein Feld `empfaenger` mit einer ROLLE mit
/// — `fachstelle`, `kasse`, `jugendamt` oder `datenschutzaufsicht` —, und
/// der Server löst sie in eine Adresse auf. Der Bildschirm zeigt an, wohin
/// es geht; er bestimmt es nicht. Das ist keine Kleinigkeit:
///
///   · Ein Auskunftsersuchen an die Kasse bleibt unbeantwortet — sie hat
///     die Akte nicht.
///   · Ein Härtefallantrag an die Kasse landet bestenfalls in einer
///     Weiterleitung.
///   · Der Antrag nach § 90 Abs. 4 SGB VIII geht an das JUGENDAMT, nicht an
///     die Stadt. Die Stadt betreibt die Einrichtung, das Jugendamt
///     entscheidet über die Übernahme.
///   · Die Beschwerde nach Art. 77 DSGVO geht an die DATENSCHUTZaufsicht,
///     nicht an die Kommunalaufsicht. Zwei Behörden, beide heißen
///     „Aufsicht"; die falsche kostet Wochen.
///
/// ⚠️ ZWEI DINGE, DIE DER BILDSCHIRM NICHT WEGLASSEN DARF:
///
///  1. Der Satz „ohne Anerkennung einer Rechtspflicht" im Ratenschreiben.
///     Der Text ist bearbeitbar; wer den Satz herausnimmt, bekommt vom
///     Server eine Absage mit Begründung. Grund ist § 212 Abs. 1 Nr. 1 BGB:
///     ein Anerkenntnis lässt die dreijährige Verjährung neu beginnen, und
///     schon die erste gezahlte Rate genügt dafür.
///  2. Die Grenzen der Vollmacht. Der Verein ist kein Anwalt und darf nach
///     § 2 Abs. 1 RDG keine rechtliche Prüfung des Einzelfalls vornehmen.
///     Genau dieser Zuschnitt macht die Vollmacht für die Stelle
///     annehmbar — er gehört sichtbar auf den Schirm, nicht ins
///     Kleingedruckte.
library;

import 'dart:convert';
// ⚠️ Nur für die kurze Zwischendatei beim Chat-Versand: der Chat-Upload
// will einen Pfad, das PDF liegt im Speicher. Sie wird im `finally` wieder
// gelöscht.
import 'dart:io';
// Für die unterschriebene Fassung: sie kommt als Bytes aus dem
// Unterschriften-System, nicht als Datei.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/signatur_service.dart';
import '../utils/file_picker_helper.dart';
import '../utils/ra_antwort.dart';
import 'behorde_kindergarten_zahlung.dart';
import 'file_viewer_dialog.dart';
import '../utils/app_farben.dart';

// ═══════════════════════════════════════════════════════════════════════
// Der Dialog
// ═══════════════════════════════════════════════════════════════════════

class KigaBuchungszeichenDetailDialog extends StatelessWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> vorgang;
  final String adminMitgliedernummer;
  final VoidCallback onChanged;
  const KigaBuchungszeichenDetailDialog({
    super.key,
    required this.apiService,
    required this.userId,
    required this.vorgang,
    required this.onChanged,
    this.adminMitgliedernummer = '',
  });

  int get _kzId => int.tryParse(raWert(vorgang['id'])) ?? 0;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: kZahlungFarbe,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            const Icon(Icons.receipt_long, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  raWert(vorgang['buchungszeichen']).isEmpty
                      ? '(ohne Buchungszeichen)'
                      : raWert(vorgang['buchungszeichen']),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                if (raHat(vorgang['kind_name']))
                  Text(raWert(vorgang['kind_name']),
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: kZahlungFarbe,
          indicatorColor: kZahlungFarbe,
          labelStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          tabs: [
            Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
            Tab(icon: Icon(Icons.mail_outline, size: 16), text: 'Korrespondenz'),
            Tab(icon: Icon(Icons.folder_open, size: 16), text: 'Akteneinsicht'),
            Tab(icon: Icon(Icons.payments_outlined, size: 16), text: 'Ratenzahlung'),
            Tab(icon: Icon(Icons.volunteer_activism_outlined, size: 16), text: 'Ermäßigung'),
            Tab(icon: Icon(Icons.assignment_ind_outlined, size: 16), text: 'Vollmacht'),
            Tab(icon: Icon(Icons.gavel, size: 16), text: 'Mahnverfahren'),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            _DetailsTab(vorgang: vorgang),
            _KorrTab(apiService: apiService, buchungszeichenId: _kzId),
            _AkteneinsichtTab(apiService: apiService, buchungszeichenId: _kzId),
            _RatenTab(apiService: apiService, buchungszeichenId: _kzId, vorgang: vorgang),
            _ErmaessigungTab(apiService: apiService, buchungszeichenId: _kzId, onChanged: onChanged),
            _VollmachtTab(apiService: apiService, buchungszeichenId: _kzId,
                userId: userId, adminMitgliedernummer: adminMitgliedernummer,
                vorgang: vorgang),
            _MahnverfahrenTab(apiService: apiService, buchungszeichenId: _kzId),
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 1 · Details
// ═══════════════════════════════════════════════════════════════════════

class _DetailsTab extends StatelessWidget {
  final Map<String, dynamic> vorgang;
  const _DetailsTab({required this.vorgang});

  @override
  Widget build(BuildContext context) {
    final gefahr = vorgang['kuendigungsgefahr'];
    final gefahrMap = gefahr is Map ? Map<String, dynamic>.from(gefahr) : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (gefahrMap != null) ...[
          _Warnkasten(
            stufe: raWert(gefahrMap['stufe']),
            text: raWert(gefahrMap['text']),
          ),
          const SizedBox(height: 14),
        ],
        _Zeile(symbol: Icons.pin, label: 'Buchungszeichen', wert: raWert(vorgang['buchungszeichen'])),
        _Zeile(symbol: Icons.folder_outlined, label: 'Aktenzeichen', wert: raWert(vorgang['aktenzeichen'])),
        _Zeile(symbol: Icons.child_care, label: 'Kind', wert: raWert(vorgang['kind_name'])),
        _Zeile(symbol: Icons.date_range, label: 'Zeitraum', wert: raWert(vorgang['zeitraum'])),
        _Zeile(symbol: Icons.label_outline, label: 'Bezeichnung', wert: raWert(vorgang['bezeichnung'])),
        const Divider(height: 22),
        _Zeile(symbol: Icons.euro, label: 'Forderung',
            wert: raHat(vorgang['betrag']) ? '${raWert(vorgang['betrag'])} €' : ''),
        _Zeile(symbol: Icons.euro_symbol, label: 'davon offen',
            wert: raHat(vorgang['offener_betrag']) ? '${raWert(vorgang['offener_betrag'])} €' : ''),
        const Divider(height: 22),
        // ⚠️ „Festsetzung", nicht „Bescheid" — siehe Kopf von
        // behorde_kindergarten_zahlung.dart.
        _Zeile(symbol: Icons.description_outlined, label: 'Festsetzung am',
            wert: raDatumDe(vorgang['festsetzung_am'])),
        _Zeile(symbol: Icons.event, label: 'Fällig am', wert: raDatumDe(vorgang['faellig_am'])),
        _Zeile(symbol: Icons.alarm, label: 'Nächste Frist', wert: raDatumDe(vorgang['naechste_frist'])),
        if (raHat(vorgang['notizen'])) ...[
          const Divider(height: 22),
          Text('Notizen', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 4),
          Text(raWert(vorgang['notizen']), style: const TextStyle(fontSize: 13)),
        ],
      ]),
    );
  }
}

class _Warnkasten extends StatelessWidget {
  final String stufe;
  final String text;
  const _Warnkasten({required this.stufe, required this.text});

  @override
  Widget build(BuildContext context) {
    final a = kuendigungsAussehen(stufe.isEmpty ? null : stufe);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: a.farbe.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: a.farbe.withValues(alpha: 0.45)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(a.symbol, size: 18, color: a.farbe),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Betreuungsplatz', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: a.farbe)),
            const SizedBox(height: 2),
            Text(text, style: TextStyle(fontSize: 12, color: a.farbe)),
          ]),
        ),
      ]),
    );
  }
}

class _Zeile extends StatelessWidget {
  final IconData symbol;
  final String label;
  final String wert;
  const _Zeile({required this.symbol, required this.label, required this.wert});

  @override
  Widget build(BuildContext context) {
    if (wert.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(symbol, size: 16, color: F.h(Colors.grey, 600)),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: Text(label, style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
        ),
        Expanded(child: Text(wert, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Gemeinsam: ein Schreiben ansehen, bearbeiten und senden
// ═══════════════════════════════════════════════════════════════════════

/// Zeigt Betreff und Text einer Vorlage, lässt beide ändern und sendet.
///
/// ⚠️ ES STEHT IMMER DABEI, AN WEN ES GEHT — und zwar mit Rolle UND
/// Adresse. Ein Absendeknopf ohne sichtbaren Empfänger ist die
/// zuverlässigste Art, einen Härtefallantrag bei der Kasse landen zu
/// lassen.
///
/// ⚠️ Ist die Adresse unbekannt (Datenschutzaufsicht), wird ein Feld
/// eingeblendet statt zu raten.
class _SchreibenSendenDialog extends StatefulWidget {
  final String titel;
  final String hinweis;
  final String rolle;
  final String? adresse;
  final String? adresseBezeichnung;
  final String betreff;
  final String text;
  final int? fristTage;
  final Future<Map<String, dynamic>> Function({
    required String empfaenger,
    required String betreff,
    required String text,
  }) senden;

  const _SchreibenSendenDialog({
    required this.titel,
    required this.hinweis,
    required this.rolle,
    required this.adresse,
    required this.adresseBezeichnung,
    required this.betreff,
    required this.text,
    required this.senden,
    this.fristTage,
  });

  @override
  State<_SchreibenSendenDialog> createState() => _SchreibenSendenDialogState();
}

class _SchreibenSendenDialogState extends State<_SchreibenSendenDialog> {
  late final TextEditingController _betreffC;
  late final TextEditingController _textC;
  late final TextEditingController _adresseC;
  bool _sendet = false;

  @override
  void initState() {
    super.initState();
    _betreffC = TextEditingController(text: widget.betreff);
    _textC = TextEditingController(text: widget.text);
    _adresseC = TextEditingController(text: widget.adresse ?? '');
  }

  @override
  void dispose() {
    _betreffC.dispose();
    _textC.dispose();
    _adresseC.dispose();
    super.dispose();
  }

  Future<void> _senden() async {
    final adresse = _adresseC.text.trim();
    if (adresse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ohne Empfängeradresse kann nichts raus.'),
        backgroundColor: Colors.orange));
      return;
    }
    setState(() => _sendet = true);
    final res = await widget.senden(
      empfaenger: adresse,
      betreff: _betreffC.text.trim(),
      text: _textC.text,
    );
    if (!mounted) return;
    setState(() => _sendet = false);
    final ok = res['success'] == true;
    if (ok) {
      Navigator.pop(context, true);
      return;
    }
    // ⚠️ Die Meldung des Servers wird GEZEIGT. Bei der Ratenzahlung steht
    // dort, dass der Anerkenntnis-Satz fehlt — und das ist das Einzige,
    // was weiterhilft. Lange Anzeigedauer, der Text ist lang.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(raWert(res['message']).isEmpty ? 'Senden fehlgeschlagen' : raWert(res['message'])),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 8),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final groesse = zahlungDialogGroesse(context);
    final unbekannt = (widget.adresse ?? '').isEmpty;
    return AlertDialog(
      title: Text(widget.titel, style: const TextStyle(fontSize: 15)),
      content: SizedBox(
        width: groesse.width,
        height: groesse.height * 0.7,
        child: Column(children: [
          if (widget.hinweis.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: F.h(Colors.blue, 50),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(widget.hinweis, style: const TextStyle(fontSize: 11.5)),
            ),
          const SizedBox(height: 8),
          // Empfänger — Rolle und Adresse, immer sichtbar.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: unbekannt ? F.h(Colors.amber, 50) : kZahlungFarbe.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: unbekannt ? F.h(Colors.amber, 300) : kZahlungFarbe.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(unbekannt ? Icons.help_outline : Icons.send, size: 14,
                    color: unbekannt ? F.h(Colors.amber, 900) : kZahlungFarbe),
                const SizedBox(width: 6),
                Text('Geht an: ${widget.rolle}',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold,
                        color: unbekannt ? F.h(Colors.amber, 900) : kZahlungFarbe)),
              ]),
              if ((widget.adresseBezeichnung ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 2),
                  child: Text(widget.adresseBezeichnung!,
                      style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
                ),
              const SizedBox(height: 6),
              TextField(
                controller: _adresseC,
                decoration: InputDecoration(
                  labelText: 'E-Mail-Adresse',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
                style: const TextStyle(fontSize: 12.5),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _betreffC,
            decoration: InputDecoration(
              labelText: 'Betreff', isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            ),
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _textC,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                labelText: 'Text',
                alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (widget.fristTage != null && widget.fristTage! > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Der Server notiert eine Frist von ${widget.fristTage} Tagen.',
                  style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton.icon(
          onPressed: _sendet ? null : _senden,
          style: FilledButton.styleFrom(backgroundColor: kZahlungFarbe),
          icon: _sendet
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send, size: 16),
          label: Text(_sendet ? 'Sendet…' : 'Senden'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 2 · Korrespondenz
// ═══════════════════════════════════════════════════════════════════════

class _KorrTab extends StatefulWidget {
  final ApiService apiService;
  final int buchungszeichenId;
  const _KorrTab({required this.apiService, required this.buchungszeichenId});

  @override
  State<_KorrTab> createState() => _KorrTabState();
}

class _KorrTabState extends State<_KorrTab> {
  List<Map<String, dynamic>> _items = [];
  bool _geladen = false;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final res = await widget.apiService.listKigaZahlungKorrespondenz(widget.buchungszeichenId);
    if (!mounted) return;
    setState(() {
      _items = raListe(res);
      _geladen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.mail_outline, size: 40, color: F.h(Colors.grey, 300)),
            const SizedBox(height: 8),
            Text('Noch kein Schriftwechsel', style: TextStyle(color: F.h(Colors.grey, 600))),
            const SizedBox(height: 4),
            Text(
              'Was über „Akteneinsicht", „Ratenzahlung" oder „Ermäßigung" gesendet '
              'wird, erscheint hier automatisch.',
              style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 500)),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final k = _items[i];
        final eingehend = raWert(k['richtung']) == 'eingehend';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              eingehend ? Icons.call_received : Icons.call_made,
              color: eingehend ? F.h(Colors.green, 700) : kZahlungFarbe,
              size: 20,
            ),
            title: Text(raWert(k['betreff']),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${raDatumDe(k['datum'])} · ${raWert(k['medium'])}',
                  style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
              // ⚠️ Der Zustellstand kommt MIT der Liste, nicht per zweitem
              // Aufruf. Ohne ihn stünde hier „gesendet" ohne jeden Hinweis
              // darauf, ob die Stelle es je bekommen hat.
              if (raHat(k['mail_status']))
                _Zustellstand(status: raWert(k['mail_status']), antwort: raWert(k['mail_antwort'])),
              // ⚠️ Beim Fax genauso. „an sipgate übergeben" ist NICHT
              // „zugestellt"; ohne den Stand liest jemand den Eintrag als
              // Beleg für etwas, das vielleicht nie ankam.
              if (raHat(k['fax_status']))
                _Faxstand(
                  status: raWert(k['fax_status']),
                  seiten: raWert(k['fax_seiten']),
                  fehler: raWert(k['fax_fehler']),
                ),
            ]),
            trailing: (int.tryParse(raWert(k['anhaenge'])) ?? 0) > 0
                ? Chip(
                    label: Text(raWert(k['anhaenge']), style: const TextStyle(fontSize: 10)),
                    avatar: const Icon(Icons.attach_file, size: 12),
                    visualDensity: VisualDensity.compact,
                  )
                : null,
            onTap: () => showDialog(
              context: context,
              builder: (ctx) => _KorrDetailDialog(
                apiService: widget.apiService,
                eintrag: k,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ein Korrespondenzeintrag im Ganzen: Text, Zustellstand, Anhänge.
///
/// 🔴 Vorher stand hier nur der Brieftext. Ob die Sendung angekommen ist
/// und was ihr beilag, war beim Öffnen nicht zu sehen — dabei ist genau
/// das die Frage, mit der man einen Eintrag aufmacht.
class _KorrDetailDialog extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> eintrag;
  const _KorrDetailDialog({required this.apiService, required this.eintrag});

  @override
  State<_KorrDetailDialog> createState() => _KorrDetailDialogState();
}

class _KorrDetailDialogState extends State<_KorrDetailDialog> {
  List<Map<String, dynamic>> _anhaenge = [];
  bool _laedt = true;
  int? _oeffnet;

  Map<String, dynamic> get k => widget.eintrag;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  /// ⚠️ Die Anhänge werden erst beim Öffnen geholt, nicht mit der Liste.
  /// In der Liste steht nur ihre ANZAHL — ein Aktendeckel mit zwanzig
  /// Einträgen zöge sonst zwanzig Abfragen nach sich, von denen niemand
  /// eine sehen will.
  Future<void> _laden() async {
    final id = int.tryParse(raWert(k['id'])) ?? 0;
    if (id <= 0) { setState(() => _laedt = false); return; }
    final res = await widget.apiService
        .listKigaZahlungDocs(bereich: 'korr', parentId: id);
    if (!mounted) return;
    setState(() {
      _anhaenge = raListe(res);
      _laedt = false;
    });
  }

  /// ⚠️ Im Speicher anzeigen, nicht auf die Platte schreiben. Die Datei
  /// liegt auf dem Server verschlüsselt; sie beim Ansehen abzulegen machte
  /// die Verschlüsselung zunichte. Speichern und Drucken bringt der
  /// Betrachter selbst mit — dann ist es eine bewusste Handlung.
  Future<void> _anhangOeffnen(Map<String, dynamic> a) async {
    final id = int.tryParse(raWert(a['id'])) ?? 0;
    if (id <= 0) return;
    setState(() => _oeffnet = id);
    try {
      final resp = await widget.apiService.downloadKigaZahlungDoc(id);
      if (!mounted) return;
      if (resp.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Datei nicht abrufbar (HTTP ${resp.statusCode})'),
          backgroundColor: Colors.red));
        return;
      }
      final name = raWert(a['datei_name']).isEmpty ? 'anhang_$id.pdf' : raWert(a['datei_name']);
      await FileViewerDialog.showFromBytes(context, resp.bodyBytes, name);
    } finally {
      if (mounted) setState(() => _oeffnet = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final istFax = raHat(k['fax_status']);
    final istMail = raHat(k['mail_status']);

    return AlertDialog(
      title: Text(raWert(k['betreff']), style: const TextStyle(fontSize: 14)),
      content: SizedBox(
        width: zahlungDialogGroesse(context).width,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${raDatumDe(k['datum'])} · ${raWert(k['medium'])} · '
              '${raWert(k['richtung']) == 'eingehend' ? 'eingegangen' : 'ausgegangen'}',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)),
            ),

            // ── Zustellstand, ausführlich ──────────────────────────
            if (istMail || istFax) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: F.h(Colors.grey, 50),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: F.h(Colors.grey, 300)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(istFax ? 'Fax' : 'E-Mail', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
                  const SizedBox(height: 4),
                  if (istMail) ...[
                    _Zustellstand(
                        status: raWert(k['mail_status']), antwort: raWert(k['mail_antwort'])),
                    if (raHat(k['mail_zugestellt_am']))
                      _Kleinzeile('zugestellt', raDatumDe(k['mail_zugestellt_am'])),
                    if (raHat(k['mail_relay'])) _Kleinzeile('Gegenstelle', raWert(k['mail_relay'])),
                    if (raHat(k['mail_message_id']))
                      _Kleinzeile('Message-ID', raWert(k['mail_message_id'])),
                  ],
                  if (istFax) ...[
                    _Faxstand(
                      status: raWert(k['fax_status']),
                      seiten: raWert(k['fax_seiten']),
                      fehler: raWert(k['fax_fehler']),
                    ),
                    if (raHat(k['fax_gesendet_am']))
                      _Kleinzeile('übergeben', raDatumDe(k['fax_gesendet_am'])),
                    if (raHat(k['fax_zugestellt_am']))
                      _Kleinzeile('zugestellt', raDatumDe(k['fax_zugestellt_am'])),
                    if (raHat(k['fax_sitzung']))
                      _Kleinzeile('Sitzung bei sipgate', raWert(k['fax_sitzung'])),
                    // ⚠️ Solange nichts zugestellt ist, wird das gesagt und
                    // nicht verschwiegen: der Cron fasst alle zehn Minuten
                    // nach, und bis dahin IST der Stand offen.
                    if (!raHat(k['fax_zugestellt_am']) && raWert(k['fax_status']) == 'in_zustellung')
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'Die Zustellung wird nachverfolgt; der Stand aktualisiert '
                          'sich alle zehn Minuten.',
                          style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)),
                        ),
                      ),
                  ],
                ]),
              ),
            ],

            const SizedBox(height: 12),
            SelectableText(raWert(k['text']), style: const TextStyle(fontSize: 12.5)),

            // ── Anhänge ────────────────────────────────────────────
            const SizedBox(height: 14),
            Row(children: [
              Icon(Icons.attach_file, size: 14, color: F.h(Colors.grey, 700)),
              const SizedBox(width: 4),
              Text('Anhänge', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
            ]),
            const SizedBox(height: 4),
            if (_laedt)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_anhaenge.isEmpty)
              Text('Kein Anhang.', style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 600)))
            else
              for (final a in _anhaenge)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: _oeffnet == (int.tryParse(raWert(a['id'])) ?? -1)
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.description_outlined, size: 18, color: kZahlungFarbe),
                  title: Text(raWert(a['datei_name']), style: const TextStyle(fontSize: 12)),
                  subtitle: Text(
                    [
                      _groesse(a['file_size']),
                      raWert(a['notiz']),
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600)),
                  ),
                  onTap: _oeffnet != null ? null : () => _anhangOeffnen(a),
                ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen')),
      ],
    );
  }

  static String _groesse(dynamic roh) {
    final b = int.tryParse(raWert(roh)) ?? 0;
    if (b <= 0) return '';
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(0)} kB';
    return '${(b / 1048576).toStringAsFixed(1)} MB';
  }
}

class _Kleinzeile extends StatelessWidget {
  final String was;
  final String wert;
  const _Kleinzeile(this.was, this.wert);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 96,
              child: Text('$was:', style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600)))),
          Expanded(child: SelectableText(wert, style: const TextStyle(fontSize: 10.5))),
        ]),
      );
}

/// Die Stände von `sipgate_faxe.status`, ausgeschrieben.
///
/// ⚠️ Die Aufzählung liegt in der Datenbank, das PHP in keinem Repo — der
/// Test dazu ist die einzige Stelle, an der ein neuer Wert auffallen kann.
///
/// 🔴 `in_zustellung` heißt „an sipgate übergeben", NICHT „zugestellt".
/// Wer beides gleich beschriftet, macht aus einem offenen Vorgang einen
/// Beleg — und genau dafür wird der Stand überhaupt angezeigt.
const Map<String, String> kFaxStaende = {
  'vorbereitet': 'vorbereitet',
  'in_zustellung': 'an sipgate übergeben',
  'zugestellt': 'zugestellt',
  'fehlgeschlagen': 'nicht zugestellt',
  'storniert': 'storniert',
  'empfangen': 'empfangen',
};

/// Der Zustellstand eines Fax.
///
/// ⚠️ Ein unbekannter Wert wird ROH gezeigt statt verschluckt.
class _Faxstand extends StatelessWidget {
  final String status;
  final String seiten;
  final String fehler;
  const _Faxstand({required this.status, required this.seiten, required this.fehler});

  @override
  Widget build(BuildContext context) {
    final farbe = switch (status) {
      'zugestellt' || 'empfangen' => Colors.green.shade700,
      'in_zustellung' => Colors.blue.shade700,
      'fehlgeschlagen' => Colors.red.shade700,
      'storniert' => Colors.orange.shade800,
      _ => Colors.grey.shade600,
    };
    final text = kFaxStaende[status] ?? status;
    final n = int.tryParse(seiten) ?? 0;
    final zusatz = [
      if (n > 0) '$n Seite${n == 1 ? '' : 'n'}',
      if (fehler.isNotEmpty) fehler,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(children: [
        Container(width: 7, height: 7,
            decoration: BoxDecoration(color: farbe, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            zusatz.isEmpty ? text : '$text · $zusatz',
            style: TextStyle(fontSize: 10.5, color: farbe),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

class _Zustellstand extends StatelessWidget {
  final String status;
  final String antwort;
  const _Zustellstand({required this.status, required this.antwort});

  @override
  Widget build(BuildContext context) {
    final (farbe, text) = switch (status) {
      'delivered' => (Colors.green.shade700, 'zugestellt'),
      'sent' => (Colors.blue.shade700, 'gesendet'),
      'deferred' => (Colors.amber.shade800, 'verzögert'),
      'bounced' || 'failed' => (Colors.red.shade700, 'nicht zugestellt'),
      _ => (Colors.grey.shade600, status),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(children: [
        Container(width: 7, height: 7,
            decoration: BoxDecoration(color: farbe, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            antwort.isEmpty ? text : '$text · $antwort',
            style: TextStyle(fontSize: 10.5, color: farbe),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 3 · Akteneinsicht — „wofür soll ich eigentlich zahlen?"
// ═══════════════════════════════════════════════════════════════════════

class _AkteneinsichtTab extends StatefulWidget {
  final ApiService apiService;
  final int buchungszeichenId;
  const _AkteneinsichtTab({required this.apiService, required this.buchungszeichenId});

  @override
  State<_AkteneinsichtTab> createState() => _AkteneinsichtTabState();
}

class _AkteneinsichtTabState extends State<_AkteneinsichtTab> {
  List<Map<String, dynamic>> _verlauf = [];
  Map<String, dynamic> _vorlagen = {};
  Map<String, dynamic> _adressen = {};
  bool _geladen = false;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final v = await widget.apiService.listKigaAkteneinsicht(widget.buchungszeichenId);
    final t = await widget.apiService.kigaAkteneinsichtVorlagen(widget.buchungszeichenId);
    if (!mounted) return;
    setState(() {
      _verlauf = raListe(v);
      _vorlagen = raKarte(t, 'vorlagen');
      _adressen = raKarte(t, 'adressen');
      _geladen = true;
    });
  }

  Future<void> _senden(String stufe) async {
    final vorlage = _vorlagen[stufe];
    if (vorlage is! Map) return;
    final m = Map<String, dynamic>.from(vorlage);
    final rolle = raWert(m['empfaenger']);
    final adr = _adressen[rolle];
    final adrMap = adr is Map ? Map<String, dynamic>.from(adr) : const <String, dynamic>{};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _SchreibenSendenDialog(
        titel: raWert(m['titel']),
        hinweis: raWert(m['hinweis']),
        rolle: rolle,
        adresse: raWert(adrMap['adresse']).isEmpty ? null : raWert(adrMap['adresse']),
        adresseBezeichnung: raWert(adrMap['bezeichnung']),
        betreff: raWert(m['betreff']),
        text: raWert(m['text']),
        fristTage: int.tryParse(raWert(m['frist_tage'])),
        senden: ({required empfaenger, required betreff, required text}) =>
            widget.apiService.kigaAkteneinsichtSenden(
              buchungszeichenId: widget.buchungszeichenId,
              stufe: stufe,
              empfaenger: empfaenger,
              betreff: betreff,
              text: text,
            ),
      ),
    );
    if (ok == true) _laden();
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());

    // ⚠️ Die Reihenfolge trennt zwei Dinge, die leicht verwechselt werden:
    // die drei Bitten eskalieren aufeinander, der DSGVO-Weg NICHT — er ist
    // ein eigener Anspruch mit gesetzlicher Monatsfrist und darf sofort
    // gezogen werden.
    const bitten = ['anfrage', 'erinnerung', 'fristsetzung'];
    const gesetzlich = ['dsgvo', 'dsgvo_beschwerde'];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Höfliche Bitten', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
        const SizedBox(height: 6),
        for (final s in bitten)
          if (_vorlagen[s] != null) _VorlagenKachel(
            vorlage: Map<String, dynamic>.from(_vorlagen[s] as Map),
            onSenden: () => _senden(s),
          ),

        const SizedBox(height: 16),
        Row(children: [
          Icon(Icons.gavel, size: 14, color: F.h(Colors.indigo, 700)),
          const SizedBox(width: 6),
          Text('Gesetzlicher Anspruch', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 700))),
        ]),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: F.h(Colors.indigo, 50),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Art. 15 DSGVO ist keine vierte Stufe hinter den drei Bitten, sondern ein '
            'eigener Weg mit gesetzlicher Frist von einem Monat (Art. 12 Abs. 3 DSGVO). '
            'Er kann sofort gegangen werden — wer ihn ans Ende stellt, verschenkt '
            'genau diesen Monat.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.indigo, 900)),
          ),
        ),
        const SizedBox(height: 6),
        for (final s in gesetzlich)
          if (_vorlagen[s] != null) _VorlagenKachel(
            vorlage: Map<String, dynamic>.from(_vorlagen[s] as Map),
            onSenden: () => _senden(s),
          ),

        if (_verlauf.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Divider(),
          Text('Verlauf', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 6),
          for (final e in _verlauf) _VerlaufZeile(
            eintrag: e,
            onStatus: (neu) async {
              await widget.apiService.kigaAkteneinsichtStatus(
                  id: int.tryParse(raWert(e['id'])) ?? 0, status: neu);
              _laden();
            },
          ),
        ],
      ],
    );
  }
}

class _VorlagenKachel extends StatelessWidget {
  final Map<String, dynamic> vorlage;
  final VoidCallback onSenden;
  const _VorlagenKachel({required this.vorlage, required this.onSenden});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text(raWert(vorlage['titel']),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(raWert(vorlage['hinweis']), style: const TextStyle(fontSize: 11)),
        trailing: FilledButton.icon(
          onPressed: onSenden,
          style: FilledButton.styleFrom(
            backgroundColor: kZahlungFarbe,
            visualDensity: VisualDensity.compact,
          ),
          icon: const Icon(Icons.send, size: 14),
          label: const Text('Senden', style: TextStyle(fontSize: 11)),
        ),
      ),
    );
  }
}

class _VerlaufZeile extends StatelessWidget {
  final Map<String, dynamic> eintrag;
  final ValueChanged<String> onStatus;
  const _VerlaufZeile({required this.eintrag, required this.onStatus});

  @override
  Widget build(BuildContext context) {
    final tage = int.tryParse(raWert(eintrag['tage_bis_frist']));
    final status = raWert(eintrag['status']);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text(raWert(eintrag['stufe']), style: const TextStyle(fontSize: 12.5)),
        subtitle: Text(
          'gesendet ${raDatumDe(eintrag['gesendet_am'])}'
          '${raHat(eintrag['frist_bis']) ? ' · Frist ${raDatumDe(eintrag['frist_bis'])}' : ''}'
          // ⚠️ Der Server rechnet die Restfrist, nicht der Client. Zwei
          // Rechenwege über dieselbe Frist ergeben irgendwann zwei Zahlen.
          '${tage != null && status == 'offen' ? (tage < 0 ? ' · ${-tage} Tage überfällig' : ' · noch $tage Tage') : ''}',
          style: TextStyle(
            fontSize: 11,
            color: (tage != null && tage < 0 && status == 'offen')
                ? F.h(Colors.red, 700)
                : F.h(Colors.grey, 600),
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 18),
          tooltip: 'Stand ändern',
          onSelected: onStatus,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'offen', child: Text('offen', style: TextStyle(fontSize: 13))),
            PopupMenuItem(value: 'teilweise', child: Text('teilweise erhalten', style: TextStyle(fontSize: 13))),
            PopupMenuItem(value: 'erhalten', child: Text('erhalten', style: TextStyle(fontSize: 13))),
            PopupMenuItem(value: 'abgelehnt', child: Text('abgelehnt', style: TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 4 · Ratenzahlung
// ═══════════════════════════════════════════════════════════════════════

class _RatenTab extends StatefulWidget {
  final ApiService apiService;
  final int buchungszeichenId;
  final Map<String, dynamic> vorgang;
  const _RatenTab({
    required this.apiService,
    required this.buchungszeichenId,
    required this.vorgang,
  });

  @override
  State<_RatenTab> createState() => _RatenTabState();
}

class _RatenTabState extends State<_RatenTab> {
  List<Map<String, dynamic>> _plaene = [];
  bool _geladen = false;
  late final TextEditingController _gesamtC;
  late final TextEditingController _rateC;
  String _zahlweise = 'ueberweisung';
  Map<String, dynamic>? _vorschau;
  bool _rechnet = false;

  @override
  void initState() {
    super.initState();
    _gesamtC = TextEditingController(text: raWert(widget.vorgang['offener_betrag']));
    _rateC = TextEditingController();
    _laden();
  }

  @override
  void dispose() {
    _gesamtC.dispose();
    _rateC.dispose();
    super.dispose();
  }

  Future<void> _laden() async {
    final res = await widget.apiService.listKigaRatenplan(widget.buchungszeichenId);
    if (!mounted) return;
    setState(() {
      _plaene = raListe(res);
      _geladen = true;
    });
  }

  Future<void> _rechnen() async {
    setState(() => _rechnet = true);
    final res = await widget.apiService.kigaRatenplanRechnen(
      buchungszeichenId: widget.buchungszeichenId,
      gesamt: _gesamtC.text.trim(),
      monatlich: _rateC.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _rechnet = false;
      _vorschau = res['success'] == true ? raKarte(res, 'plan') : null;
    });
    if (res['success'] != true) {
      // ⚠️ Der Server meldet echte Rechenfehler im Rückgabewert — „mehr als
      // 120 Raten", Rundungsfehler. Sie gehören auf den Schirm, nicht in
      // ein leeres Feld.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(raWert(res['message']).isEmpty
            ? 'Der Plan ließ sich nicht berechnen'
            : raWert(res['message'])),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
      ));
    }
  }

  Future<void> _senden() async {
    final res = await widget.apiService.kigaAkteneinsichtVorlagen(widget.buchungszeichenId);
    final adressen = raKarte(res, 'adressen');
    final kasse = adressen['kasse'];
    final kasseMap = kasse is Map ? Map<String, dynamic>.from(kasse) : const <String, dynamic>{};

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _RatenSendenDialog(
        apiService: widget.apiService,
        buchungszeichenId: widget.buchungszeichenId,
        gesamt: _gesamtC.text.trim(),
        monatlich: _rateC.text.trim(),
        zahlweise: _zahlweise,
        adresse: raWert(kasseMap['adresse']).isEmpty ? null : raWert(kasseMap['adresse']),
        adresseBezeichnung: raWert(kasseMap['bezeichnung']),
      ),
    );
    if (ok == true) {
      setState(() => _vorschau = null);
      _laden();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(12), children: [
      // 🔴 Die Warnung steht VOR dem Formular, nicht darunter.
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: F.h(Colors.amber, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(Colors.amber, 300)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded, size: 15, color: F.h(Colors.amber, 900)),
            const SizedBox(width: 6),
            Text('Ohne Anerkennung einer Rechtspflicht',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                    color: F.h(Colors.amber, 900))),
          ]),
          const SizedBox(height: 4),
          Text(
            'Jedes Ratenschreiben trägt diesen Satz. Nach § 212 Abs. 1 Nr. 1 BGB lässt '
            'ein Anerkenntnis die dreijährige Verjährung neu beginnen — und schon eine '
            'gezahlte Rate genügt dafür. Der Satz ist genau das, was den Neubeginn '
            'verhindert. Der Server sendet nicht, wenn er fehlt.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.amber, 900)),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _gesamtC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Offener Gesamtbetrag', suffixText: '€', isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _rateC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Rate je Monat', suffixText: '€', isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      InputDecorator(
        decoration: InputDecoration(
          labelText: 'Zahlungsweise', isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _zahlweise,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'ueberweisung', child: Text('Überweisung', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'dauerauftrag', child: Text('Dauerauftrag', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'lastschrift', child: Text('SEPA-Lastschrift', style: TextStyle(fontSize: 13))),
            ],
            onChanged: (v) => setState(() => _zahlweise = v ?? 'ueberweisung'),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _rechnet ? null : _rechnen,
            icon: const Icon(Icons.calculate_outlined, size: 16),
            label: Text(_rechnet ? 'Rechnet…' : 'Berechnen'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: _vorschau == null ? null : _senden,
            style: FilledButton.styleFrom(backgroundColor: kZahlungFarbe),
            icon: const Icon(Icons.send, size: 16),
            label: const Text('An die Kasse'),
          ),
        ),
      ]),

      if (_vorschau != null) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kZahlungFarbe.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${raWert(_vorschau!['anzahl'])} Raten · '
                'erste ${raDatumDe(_vorschau!['erste_am'])} · '
                'letzte ${raDatumDe(_vorschau!['letzte_am'])}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final r in raListe(_vorschau!, 'raten').take(4))
              Text('Rate ${raWert(r['nr'])}: ${raWert(r['betrag_text'])} '
                  'am ${raDatumDe(r['faellig_am'])}',
                  style: const TextStyle(fontSize: 11.5)),
            if (raListe(_vorschau!, 'raten').length > 4)
              Text('… und ${raListe(_vorschau!, 'raten').length - 4} weitere',
                  style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
          ]),
        ),
      ],

      if (_plaene.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Divider(),
        Text('Bisherige Vorschläge', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
        const SizedBox(height: 6),
        for (final p in _plaene)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text('${raWert(p['gesamt'])} in ${raWert(p['anzahl'])} Raten '
                  'à ${raWert(p['monatlich'])}',
                  style: const TextStyle(fontSize: 12.5)),
              subtitle: Text('Stand: ${raWert(p['status'])}'
                  '${raHat(p['angeboten_am']) ? ' · angeboten ${raDatumDe(p['angeboten_am'])}' : ''}',
                  style: const TextStyle(fontSize: 11)),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (neu) async {
                  await widget.apiService.kigaRatenplanStatus(
                      id: int.tryParse(raWert(p['id'])) ?? 0, status: neu);
                  _laden();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'angeboten', child: Text('angeboten', style: TextStyle(fontSize: 13))),
                  PopupMenuItem(value: 'bewilligt', child: Text('bewilligt', style: TextStyle(fontSize: 13))),
                  PopupMenuItem(value: 'abgelehnt', child: Text('abgelehnt', style: TextStyle(fontSize: 13))),
                  PopupMenuItem(value: 'gestundet', child: Text('gestundet', style: TextStyle(fontSize: 13))),
                  PopupMenuItem(value: 'laeuft', child: Text('läuft', style: TextStyle(fontSize: 13))),
                  PopupMenuItem(value: 'erfuellt', child: Text('erfüllt', style: TextStyle(fontSize: 13))),
                  PopupMenuItem(value: 'gescheitert', child: Text('gescheitert', style: TextStyle(fontSize: 13))),
                ],
              ),
            ),
          ),
      ],
    ]);
  }
}

/// Eigener Dialog, weil das Senden hier mehr Felder braucht als das
/// gemeinsame Formular — und weil der Text vom Server kommt, nicht aus
/// einer Vorlagenliste.
class _RatenSendenDialog extends StatefulWidget {
  final ApiService apiService;
  final int buchungszeichenId;
  final String gesamt;
  final String monatlich;
  final String zahlweise;
  final String? adresse;
  final String adresseBezeichnung;
  const _RatenSendenDialog({
    required this.apiService,
    required this.buchungszeichenId,
    required this.gesamt,
    required this.monatlich,
    required this.zahlweise,
    required this.adresse,
    required this.adresseBezeichnung,
  });

  @override
  State<_RatenSendenDialog> createState() => _RatenSendenDialogState();
}

class _RatenSendenDialogState extends State<_RatenSendenDialog> {
  late final TextEditingController _adresseC;
  bool _sendet = false;

  @override
  void initState() {
    super.initState();
    _adresseC = TextEditingController(text: widget.adresse ?? '');
  }

  @override
  void dispose() {
    _adresseC.dispose();
    super.dispose();
  }

  Future<void> _senden() async {
    setState(() => _sendet = true);
    // Ohne `text` nimmt der Server seine eigene Vorlage — mit dem
    // Anerkenntnis-Satz darin. Genau deshalb wird hier NICHTS mitgegeben:
    // der sicherste Weg ist der, bei dem der Mensch nichts entfernen kann.
    final res = await widget.apiService.kigaRatenplanSenden(
      buchungszeichenId: widget.buchungszeichenId,
      gesamt: widget.gesamt,
      monatlich: widget.monatlich,
      zahlweise: widget.zahlweise,
      empfaenger: _adresseC.text.trim(),
    );
    if (!mounted) return;
    setState(() => _sendet = false);
    if (res['success'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(raWert(res['message']).isEmpty ? 'Senden fehlgeschlagen' : raWert(res['message'])),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 8),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ratenvorschlag senden', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: zahlungDialogGroesse(context).width,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kZahlungFarbe.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Geht an: Kasse',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kZahlungFarbe)),
              if (widget.adresseBezeichnung.isNotEmpty)
                Text(widget.adresseBezeichnung,
                    style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
            ]),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _adresseC,
            decoration: InputDecoration(
              labelText: 'E-Mail-Adresse', isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${widget.gesamt} € in Raten à ${widget.monatlich} €. '
            'Den Text schreibt der Server — mit dem Satz „ohne Anerkennung einer '
            'Rechtspflicht" und der Bitte, den Betreuungsplatz während der '
            'Ratenzahlung nicht zu kündigen.',
            style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700)),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton.icon(
          onPressed: _sendet ? null : _senden,
          style: FilledButton.styleFrom(backgroundColor: kZahlungFarbe),
          icon: _sendet
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send, size: 16),
          label: Text(_sendet ? 'Sendet…' : 'Senden'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 5 · Ermäßigung — die zwei Wege, die wirklich helfen
// ═══════════════════════════════════════════════════════════════════════

class _ErmaessigungTab extends StatefulWidget {
  final ApiService apiService;
  final int buchungszeichenId;
  final VoidCallback onChanged;
  const _ErmaessigungTab({
    required this.apiService,
    required this.buchungszeichenId,
    required this.onChanged,
  });

  @override
  State<_ErmaessigungTab> createState() => _ErmaessigungTabState();
}

class _ErmaessigungTabState extends State<_ErmaessigungTab> {
  Map<String, dynamic> _vorlagen = {};
  Map<String, dynamic> _adressen = {};
  String _vorbehalt = '';
  bool _geladen = false;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final res = await widget.apiService.kigaErmaessigungVorlagen(widget.buchungszeichenId);
    if (!mounted) return;
    setState(() {
      _vorlagen = raKarte(res, 'vorlagen');
      _adressen = raKarte(res, 'adressen');
      _vorbehalt = raWert(res['vorbehalt']);
      _geladen = true;
    });
  }

  Future<void> _senden(String art) async {
    final v = _vorlagen[art];
    if (v is! Map) return;
    final m = Map<String, dynamic>.from(v);
    final rolle = raWert(m['empfaenger']);
    final adr = _adressen[rolle];
    final adrMap = adr is Map ? Map<String, dynamic>.from(adr) : const <String, dynamic>{};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _SchreibenSendenDialog(
        titel: raWert(m['titel']),
        hinweis: raWert(m['hinweis']),
        rolle: rolle,
        adresse: raWert(adrMap['adresse']).isEmpty ? null : raWert(adrMap['adresse']),
        adresseBezeichnung: raWert(adrMap['bezeichnung']),
        betreff: raWert(m['betreff']),
        text: raWert(m['text']),
        senden: ({required empfaenger, required betreff, required text}) =>
            widget.apiService.kigaErmaessigungSenden(
              buchungszeichenId: widget.buchungszeichenId,
              art: art,
              empfaenger: empfaenger,
              betreff: betreff,
              text: text,
            ),
      ),
    );
    if (ok == true) {
      widget.onChanged();
      _laden();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(12), children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: F.h(Colors.green, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(Colors.green, 200)),
        ),
        child: Text(
          'Eine Ratenzahlung verteilt den Betrag, sie verkleinert ihn nicht. Wer '
          'dauerhaft zu wenig hat, braucht eine Ermäßigung — und die gibt es auf '
          'zwei Wegen, die nichts miteinander zu tun haben und an verschiedene '
          'Stellen gehen.',
          style: TextStyle(fontSize: 11.5, color: F.h(Colors.green, 900)),
        ),
      ),
      const SizedBox(height: 12),

      if (_vorlagen['haertefall'] != null)
        _ErmaessigungKarte(
          vorlage: Map<String, dynamic>.from(_vorlagen['haertefall'] as Map),
          farbe: Colors.teal,
          fussnote: 'Kann-Vorschrift der Entgeltordnung — die Stelle entscheidet nach '
              'Ermessen. Die Begründung trägt den Antrag.',
          onSenden: () => _senden('haertefall'),
        ),
      if (_vorlagen['jugendamt'] != null)
        _ErmaessigungKarte(
          vorlage: Map<String, dynamic>.from(_vorlagen['jugendamt'] as Map),
          farbe: Colors.indigo,
          // ⚠️ Der Unterschied, auf den es ankommt: „wird … erlassen" statt
          // „kann ermäßigt werden". Kein Ermessen, sondern ein Anspruch bei
          // Vorliegen der Voraussetzungen.
          fussnote: '§ 90 Abs. 4 SGB VIII: „wird auf Antrag erlassen oder … übernommen, '
              'wenn die Belastung … nicht zuzumuten ist." Anspruch, kein Ermessen — '
              'der stärkere der beiden Wege. Geht ans Jugendamt, nicht an die Stadt.',
          onSenden: () => _senden('jugendamt'),
        ),

      if (_vorbehalt.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(_vorbehalt, style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600))),
      ],
    ]);
  }
}

class _ErmaessigungKarte extends StatelessWidget {
  final Map<String, dynamic> vorlage;
  final Color farbe;
  final String fussnote;
  final VoidCallback onSenden;
  const _ErmaessigungKarte({
    required this.vorlage,
    required this.farbe,
    required this.fussnote,
    required this.onSenden,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(raWert(vorlage['titel']),
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: farbe)),
          const SizedBox(height: 4),
          Text(fussnote, style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onSenden,
              style: FilledButton.styleFrom(backgroundColor: farbe),
              icon: const Icon(Icons.send, size: 15),
              label: const Text('Antrag senden', style: TextStyle(fontSize: 12)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 6 · Vollmacht
// ═══════════════════════════════════════════════════════════════════════

class _VollmachtTab extends StatefulWidget {
  final ApiService apiService;
  final int buchungszeichenId;
  /// Kontoinhaber des Vorgangs. ⚠️ NICHT zwangsläufig der Unterzeichner —
  /// der Vorgang kann auf einem Kinderkonto liegen.
  final int userId;
  final String adminMitgliedernummer;
  /// Der Vorgang selbst — gebraucht wird daraus das Buchungszeichen, damit
  /// die Chat-Nachricht und die Versandzeile sagen, um welchen es geht.
  final Map<String, dynamic> vorgang;
  const _VollmachtTab({
    required this.apiService,
    required this.buchungszeichenId,
    required this.userId,
    required this.vorgang,
    this.adminMitgliedernummer = '',
  });

  @override
  State<_VollmachtTab> createState() => _VollmachtTabState();
}

class _VollmachtTabState extends State<_VollmachtTab> {
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _umfang = {};
  List<String> _grenzen = [];
  bool _geladen = false;
  bool _arbeitet = false;

  /// Signaturvorgänge je Vollmacht-Id.
  ///
  /// ⚠️ Der Stand kommt aus dem Unterschriften-System, nicht aus einem Feld,
  /// das jemand von Hand setzt. Zwei Wahrheiten über dieselbe Unterschrift
  /// wären genau die Art Fehler, die man erst bemerkt, wenn ein Dokument
  /// als unterschrieben gilt, das niemand unterschrieben hat.
  Map<int, List<Signaturvorgang>> _signaturen = {};

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final v = await widget.apiService.listKigaVollmachten(widget.buchungszeichenId);
    final o = await widget.apiService.kigaVollmachtOptionen();
    if (!mounted) return;
    final liste = raListe(v);

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
      for (final s in alle) {
        if (s.quelleTabelle != 'kiga_zahlung_vollmacht' || s.quelleId == null) continue;
        vorgaenge.putIfAbsent(s.quelleId!, () => []).add(s);
      }
    }

    if (!mounted) return;
    setState(() {
      _items = liste;
      _umfang = raKarte(o, 'umfang');
      final g = o['grenzen'];
      _grenzen = g is List ? g.map((e) => e.toString()).toList() : const [];
      _signaturen = vorgaenge;
      _geladen = true;
    });
  }

  Future<void> _erzeugen() async {
    // 🔴 ERST KLÄREN, WER UNTERSCHREIBT.
    //
    // Der Kontoinhaber ist nicht automatisch der Vollmachtgeber: liegt der
    // Vorgang auf einem Kinderkonto, ist er der Betroffene. Ein Fünfjähriger
    // ist geschäftsunfähig (§ 104 Nr. 1 BGB) — eine so erzeugte Urkunde wäre
    // nichtig. Genau das ist einmal passiert, bevor es diese Abfrage gab.
    final geberId = await showDialog<int>(
      context: context,
      builder: (ctx) => _VollmachtgeberDialog(
        apiService: widget.apiService,
        userId: widget.userId,
      ),
    );
    if (geberId == null || !mounted) return;

    final options = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _VollmachtErzeugenDialog(umfang: _umfang, grenzen: _grenzen),
    );
    if (options == null) return;

    setState(() => _arbeitet = true);
    final res = await widget.apiService.createKigaVollmacht(
      buchungszeichenId: widget.buchungszeichenId,
      vollmachtgeberId: geberId,
      options: options,
    );
    if (!mounted) return;
    setState(() => _arbeitet = false);

    if (res['success'] != true) {
      _melden(raWert(res['message']).isEmpty ? 'Erzeugen fehlgeschlagen' : raWert(res['message']),
          Colors.red);
      return;
    }
    // ⚠️ Ehrlich benennen, warum kein Leseexemplar da ist. „keine
    // Übersetzung" und „für diese Sprache gibt es keine" sind zwei
    // verschiedene Aussagen, und nur die zweite stimmt hier meistens.
    final sprache = raWert(res['mitglied_sprache']);
    final ueb = raWert(res['uebersetzung_sprache']);
    _melden(
      ueb.isNotEmpty
          ? 'Vollmacht erzeugt — mit Leseexemplar auf ${raSpracheName(ueb)}'
          : (res['uebersetzung_moeglich'] == true
              ? 'Vollmacht erzeugt — das Leseexemplar konnte nicht gebaut werden'
              : 'Vollmacht erzeugt — für ${sprache.isEmpty ? "diese Sprache" : raSpracheName(sprache)} '
                'ist noch kein Leseexemplar freigegeben, es bleibt bei der deutschen Fassung'),
      Colors.green,
    );
    _laden();
  }

  Future<void> _oeffnen(Map<String, dynamic> v, {String? typ}) async {
    final id = int.tryParse(raWert(v['id'])) ?? 0;
    final resp = await widget.apiService.downloadKigaVollmachtPdf(id, typ: typ);
    if (!mounted) return;
    if (resp.statusCode != 200) {
      // Der Server begründet 404 unterschiedlich — „gibt es nicht" gegen
      // „für diese Sprache gibt es keins". Die Begründung gehört auf den
      // Schirm, nicht der Statuscode.
      String grund = 'HTTP ${resp.statusCode}';
      try {
        final j = jsonDecode(resp.body);
        if (j is Map && raWert(j['message']).isNotEmpty) grund = raWert(j['message']);
      } catch (_) {}
      _melden('PDF nicht abrufbar: $grund', Colors.red);
      return;
    }
    // 🔴 IM ARBEITSSPEICHER ANZEIGEN, NICHT AUF DIE PLATTE SCHREIBEN.
    //
    // Das PDF liegt auf dem Server mit AES-256-GCM verschlüsselt; hier
    // kommt es entschlüsselt an. Es zum Herunterladen anzubieten, macht
    // die Verschlüsselung zunichte: eine unterschriebene Vollmacht mit
    // Name, Geburtsdatum, Anschrift und dem Namen des Kindes läge danach
    // im Download-Ordner, unverschlüsselt, und bliebe dort.
    //
    // FileViewerDialog.showFromBytes ist genau dafür gebaut — der
    // Kommentar an der Methode sagt es wörtlich: „for encrypted/decrypted
    // docs". Der Dialog bringt Speichern und Drucken selbst mit, für den
    // Fall, dass jemand die Datei doch braucht; dann ist es aber eine
    // bewusste Handlung und kein Nebeneffekt des Ansehens.
    final name = typ == 'uebersetzung'
        ? 'vollmacht_${raWert(v['uebersetzung_sprache'])}_$id.pdf'
        : (raWert(v['pdf_filename']).isEmpty ? 'vollmacht_$id.pdf' : raWert(v['pdf_filename']));

    // Nur beim Leseexemplar: das Mitglied soll es in seiner Sprache im
    // Chat haben. Die deutsche Fassung geht an die Stadt, nicht an das
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
  }

  /// Schickt das Leseexemplar in den Chat DES MITGLIEDS.
  ///
  /// 🔴 Es geht IMMER das Leseexemplar, nie die deutsche Fassung
  /// (Entscheidung des Vorsitzenden, 18.08.2026). Die deutsche ist für die
  /// Stadt bestimmt; ins Postfach des Mitglieds gehört die, die es lesen
  /// kann. Deshalb hängt der Knopf am Übersetzungs-Betrachter und nicht an
  /// der Karte.
  ///
  /// ⚠️ Adressiert wird über `mitglied_nummer` aus der Vollmacht-Zeile,
  /// nicht über das geöffnete Profil. Beides ist fast immer dasselbe — aber
  /// „fast immer" ist hier zu wenig: der Vorgang kann auf einem Kinderkonto
  /// liegen, während die Vollmacht der Mutter gehört. Ein Dokument im
  /// falschen Postfach ist eine Datenpanne, kein Schönheitsfehler.
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
        title: const Text('In den Chat senden?', style: TextStyle(fontSize: 15)),
        content: Text(
          'Das Leseexemplar auf $sprache geht an $nummer.\n\n'
          'Es ist die Fassung zum Lesen — unterschrieben wird die deutsche, '
          'und die geht an die Stadt.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: kZahlungFarbe),
            child: const Text('Senden'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    File? temp;
    try {
      final gespraech =
          await widget.apiService.adminStartChat(widget.adminMitgliedernummer, nummer);
      final id = int.tryParse(raWert(gespraech['conversation_id'])) ??
          int.tryParse(raWert((gespraech['data'] as Map?)?['conversation_id'])) ??
          0;
      if (id <= 0) {
        if (mounted) _melden('Kein Gespräch mit $nummer gefunden', Colors.red);
        return;
      }

      // ⚠️ Der Chat-Upload will eine Datei auf der Platte. Das PDF liegt
      // hier im Speicher, muss also kurz abgelegt werden — im temporären
      // Verzeichnis und mit `finally` wieder weg. Es wandert ohnehin gleich
      // in die Chat-Ablage, ist also keine neue Offenlegung.
      temp = File('${Directory.systemTemp.path}/$name');
      await temp.writeAsBytes(pdf, flush: true);

      final res = await widget.apiService.uploadChatAttachments(
        conversationId: id,
        mitgliedernummer: widget.adminMitgliedernummer,
        files: [temp],
        message: 'Vollmacht ($sprache) — '
            '${raWert(widget.vorgang['buchungszeichen'])}',
      );
      if (!mounted) return;
      final erfolg = res['success'] == true;

      // ⚠️ Erst jetzt protokollieren, nachdem der Server den Empfang
      // bestätigt hat. Vorher einzutragen hieße, eine Sendung zu behaupten,
      // die vielleicht nie ankam — und darauf verlässt sich später jemand,
      // der sieht „ist beim Mitglied".
      if (erfolg) {
        await widget.apiService.kigaVollmachtVersandEintragen(
          vollmachtId: int.tryParse(raWert(v['id'])) ?? 0,
          empfaenger: nummer,
          weg: 'chat',
          fassung: 'uebersetzung',
          sprache: raWert(v['uebersetzung_sprache']),
        );
      }
      if (!mounted) return;
      _melden(
        erfolg
            ? 'An $nummer gesendet'
            : (raWert(res['message']).isEmpty ? 'Fehler' : raWert(res['message'])),
        erfolg ? Colors.green : Colors.red,
      );
      if (erfolg) _laden();
    } catch (e) {
      if (mounted) _melden('Fehler: $e', Colors.red);
    } finally {
      if (temp != null && temp.existsSync()) {
        try {
          temp.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Ist die Gruppe vollständig unterschrieben und gesiegelt, gibt es eine
  /// DRITTE Fassung: das Dokument mit BEIDEN Unterschriften.
  ///
  /// 🔴 Genau die fehlte im Bildschirm. Es sah aus, als sei nichts passiert,
  /// obwohl beide unterschrieben hatten — und am 18.08.2026 wurde deshalb
  /// eine bereits unterschriebene Vollmacht widerrufen. Im Anwaltszweig ist
  /// dasselbe schon einmal passiert; der Kommentar dort sagt es wörtlich.
  ///
  /// ⚠️ Über die GRUPPE geprüft, nicht über die gelieferten Zeilen. `every()`
  /// darüber wäre wahr, sobald das MITGLIED unterschrieben hat — die Zeile
  /// des Vorstands ist hier gar nicht dabei. Der Knopf böte dann eine
  /// Fassung an, die der Siegel-Cron noch nicht erzeugt hat.
  Signaturvorgang? _signiertVerfuegbar(Map<String, dynamic> v) {
    final vorgaenge = _signaturen[int.tryParse(raWert(v['id'])) ?? -1] ?? const <Signaturvorgang>[];
    if (vorgaenge.isEmpty) return null;
    if (!vorgaenge.first.gruppeVollstaendig) return null;
    return vorgaenge.firstWhere((x) => x.istSigniert, orElse: () => vorgaenge.first);
  }

  Future<void> _signiertOeffnen(Map<String, dynamic> v, {bool speichern = false}) async {
    final vorgang = _signiertVerfuegbar(v);
    if (vorgang == null || widget.adminMitgliedernummer.isEmpty) return;

    final bytes = await SignaturService().herunterladen(
      callerMitgliedernummer: widget.adminMitgliedernummer,
      signaturId: vorgang.id,
      welche: 'signiert',
    );
    if (!mounted) return;
    if (bytes == null) {
      // ⚠️ „Noch nicht da" ist kein Fehler. Der Siegel-Cron läuft im
      // Minutentakt; unmittelbar nach der letzten Unterschrift ist die
      // Fassung regulär noch nicht erzeugt. „Fehler" zu melden schickt
      // jemanden auf die Suche nach einem Defekt, den es nicht gibt.
      _melden(
        'Die unterschriebene Fassung wird gerade gesiegelt — das geschieht '
        'wenige Minuten nach der letzten Unterschrift.',
        Colors.orange,
      );
      return;
    }

    final name = 'vollmacht_unterschrieben_${raWert(v['id'])}.pdf';
    if (speichern) {
      final ziel = await FilePickerHelper.saveBytes(
        bytes: Uint8List.fromList(bytes),
        fileName: name,
        dialogTitle: 'Unterschriebene Vollmacht speichern',
      );
      if (ziel == null || !mounted) return;
      _melden('Gespeichert: $ziel', Colors.green);
      return;
    }
    await FileViewerDialog.showFromBytes(context, Uint8List.fromList(bytes), name);
  }

  /// Die unterschriebene Vollmacht per E-Mail an die Stadt.
  ///
  /// 🔴 Nur die von BEIDEN unterschriebene Fassung, nie ein Entwurf und nie
  /// das Leseexemplar. Durchgesetzt wird das im Endpunkt; hier steht nur,
  /// warum der Weg gerade nicht geht — grau allein sagt es nicht.
  Future<void> _perMail(Map<String, dynamic> v) async {
    final id = int.tryParse(raWert(v['id'])) ?? 0;
    if (id <= 0) return;

    final res = await widget.apiService.kigaVollmachtMailVorlagen(id);
    if (!mounted) return;
    if (res['success'] != true) {
      _melden(raWert(res['message']).isEmpty
          ? 'Die Anschreiben konnten nicht geladen werden'
          : raWert(res['message']), Colors.red);
      return;
    }

    final gesendet = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _KigaVollmachtMailDialog(
        apiService: widget.apiService,
        vollmachtId: id,
        daten: res,
      ),
    );
    if (gesendet == null || !mounted) return;
    _laden();
  }

  /// Dieselbe Fassung per Fax.
  ///
  /// ⚠️ Kein Entwurfsdialog wie bei der Mail: ein Fax hat keinen Fließtext,
  /// es überträgt das Blatt. Zu entscheiden bleibt nur die Nummer — und die
  /// steht im Datensatz der Stelle.
  ///
  /// ⚠️ KEINE Wahl zwischen Kasse und Fachstelle, anders als bei der Mail.
  /// Die Stadt hat EINE Faxnummer für das ganze Rathaus (am 18.08.2026
  /// geprüft: Impressum und Ortsdienst nennen dieselbe). Eine Auswahl
  /// anzubieten, die an der Zustellung nichts ändert, wäre eine erfundene
  /// Genauigkeit. Dass das Blatt trotzdem bei der richtigen Stelle landet,
  /// leistet die erste Seite der Vollmacht — sie trägt „Abteilung:", und
  /// zwar die aus dem Datensatz.
  Future<void> _perFax(Map<String, dynamic> v) async {
    final id = int.tryParse(raWert(v['id'])) ?? 0;
    if (id <= 0) return;

    final res = await widget.apiService.kigaVollmachtMailVorlagen(id);
    if (!mounted) return;
    if (res['success'] != true) {
      _melden(raWert(res['message']), Colors.red);
      return;
    }
    final nummer = raWert(res['fax']);
    // ⚠️ NICHT `stelle`. Die Faxnummer hängt an der Stelle, nicht an der
    // Rolle — im Datensatz gibt es genau ein Faxfeld. Sie mit „Stadtkasse"
    // zu beschriften behauptete eine Genauigkeit, die die Daten nicht
    // hergeben.
    final stelle = raWert(res['fax_name']).isEmpty
        ? raWert(res['stelle'])
        : raWert(res['fax_name']);
    if (nummer.isEmpty) {
      _melden('Für $stelle ist keine Faxnummer hinterlegt.', Colors.orange);
      return;
    }
    if (res['bereit'] != true) {
      // Der Grund, nicht nur die Ablehnung: „warum nicht" ist hier die
      // eigentliche Information.
      _melden(
        'Noch keine von beiden Seiten unterschriebene Fassung '
        '(${raWert(res['unterschrieben'])} von ${raWert(res['noetig'])}).',
        Colors.orange,
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Per Fax senden?', style: TextStyle(fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Die unterschriebene Vollmacht geht an\n$stelle\n$nummer',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          Text(
            'Es ist die Faxnummer des ganzen Rathauses. Zur richtigen Stelle '
            'führt die erste Seite der Vollmacht — sie nennt die Abteilung.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
          ),
          const SizedBox(height: 6),
          Text(
            '⚠️ Ein Fax ist übergeben, nicht zugestellt. Die Zustellung wird '
            'nachverfolgt und steht danach im Versandprotokoll.',
            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: kZahlungFarbe),
            icon: const Icon(Icons.fax, size: 16),
            label: const Text('Senden'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _arbeitet = true);
    final r = await widget.apiService.kigaVollmachtFaxSenden(vollmachtId: id);
    if (!mounted) return;
    setState(() => _arbeitet = false);
    _melden(
      raWert(r['message']).isEmpty
          ? (r['success'] == true ? 'Fax übergeben' : 'Fehlgeschlagen')
          : raWert(r['message']),
      r['success'] == true ? Colors.green : Colors.red,
    );
    if (r['success'] == true) _laden();
  }

  /// Das vollständige Versandprotokoll — jede Sendung, nicht nur die letzte.
  Future<void> _versandprotokoll(Map<String, dynamic> v) async {
    final res = await widget.apiService
        .listKigaVollmachtVersand(int.tryParse(raWert(v['id'])) ?? 0);
    if (!mounted) return;
    final zeilen = raListe(res);
    final breite = MediaQuery.of(context).size.width;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Versandprotokoll', style: TextStyle(fontSize: 15)),
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
                      Text('${kVersandWege[raWert(z['weg'])] ?? raWert(z['weg'])} '
                          'an ${raWert(z['empfaenger'])}',
                          style: const TextStyle(fontSize: 12)),
                      if (raHat(z['gesendet_von_name']))
                        Text('durch ${raWert(z['gesendet_von_name'])}',
                            style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
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

  /// Stellt die Vollmacht beiden Unterzeichnern zur Unterschrift.
  ///
  /// ⚠️ Das PDF geht als BYTES, nicht über eine temporäre Datei: es liegt
  /// auf dem Server verschlüsselt und kommt entschlüsselt im Speicher an.
  /// Es erst auf die Platte zu schreiben hieße, den Klartext ausgerechnet
  /// für das Dokument abzulegen, dessen Unversehrtheit gleich beglaubigt
  /// wird.
  ///
  /// ⚠️ Immer die DEUTSCHE Fassung — sie ist die rechtlich verbindliche.
  /// Das Leseexemplar trägt kein Unterschriftsfeld und dürfte gar nicht
  /// unterschrieben werden.
  Future<void> _zurUnterschrift(Map<String, dynamic> v) async {
    final mitgliedId = int.tryParse(raWert(v['user_id'])) ?? 0;
    final vorsitzerId = int.tryParse(raWert(v['vorsitzer_id'])) ?? 0;
    if (mitgliedId <= 0 || vorsitzerId <= 0 || widget.adminMitgliedernummer.isEmpty) {
      _melden('Unterzeichner nicht ermittelbar — bitte die Liste neu laden', Colors.red);
      return;
    }

    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zur Unterschrift stellen?', style: TextStyle(fontSize: 15)),
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
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: kZahlungFarbe),
            child: const Text('Stellen'),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;

    setState(() => _arbeitet = true);
    try {
      final id = int.tryParse(raWert(v['id'])) ?? 0;
      final resp = await widget.apiService.downloadKigaVollmachtPdf(id);
      if (!mounted) return;
      if (resp.statusCode != 200) {
        _melden('PDF nicht abrufbar (HTTP ${resp.statusCode})', Colors.red);
        return;
      }
      final ergebnis = await SignaturService().anfordernAusBytes(
        callerMitgliedernummer: widget.adminMitgliedernummer,
        userId: mitgliedId,
        dokumentTyp: 'kiga_zahlung_vollmacht',
        dokumentTitel: 'Vollmacht Elternbeitrag — ${raWert(v['empfaenger_name'])}',
        pdfBytes: resp.bodyBytes,
        dateiname: raWert(v['pdf_filename']).isEmpty ? 'vollmacht.pdf' : raWert(v['pdf_filename']),
        // ⚠️ Tabellenname und Rollen sind gekoppelt: der Server sucht die
        // Unterschriftskoordinaten unter genau diesem Tabellennamen
        // (unterschriftFelder() in vorstand/signatur_manage.php), und das
        // Siegelprogramm sucht sie unter genau diesen Rollenschlüsseln.
        // Ein eigener Name wäre ein stiller Fehlschlag: unterschrieben
        // würde, nur säße die Unterschrift nicht auf der Linie.
        quelleTabelle: 'kiga_zahlung_vollmacht',
        quelleId: id,
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
      if (ergebnis.ok) _laden();
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  Future<void> _widerrufen(Map<String, dynamic> v) async {
    final grundC = TextEditingController();
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vollmacht widerrufen?', style: TextStyle(fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Der Widerruf löscht nichts. Das Dokument bleibt nachweisbar — sonst '
            'ließe sich hinterher nicht zeigen, was wann galt.\n\n'
            'Offene Unterschriftsanforderungen werden zurückgezogen.',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: grundC,
            decoration: InputDecoration(
              labelText: 'Grund (optional)', isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Widerrufen'),
          ),
        ],
      ),
    );
    if (ja != true) return;
    final res = await widget.apiService
        .widerrufKigaVollmacht(int.tryParse(raWert(v['id'])) ?? 0, grundC.text.trim());
    if (!mounted) return;
    _melden(raWert(res['message']).isEmpty ? 'Widerrufen' : raWert(res['message']),
        res['success'] == true ? Colors.green : Colors.red);
    if (res['success'] == true) _laden();
  }

  void _melden(String text, Color farbe) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: farbe, duration: const Duration(seconds: 5)));

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    return Stack(children: [
      ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          const Expanded(
            child: Text('Vollmachten',
                style: TextStyle(fontWeight: FontWeight.bold, color: kZahlungFarbe)),
          ),
          FilledButton.icon(
            onPressed: _arbeitet ? null : _erzeugen,
            style: FilledButton.styleFrom(backgroundColor: kZahlungFarbe),
            icon: const Icon(Icons.note_add, size: 16),
            label: const Text('Erzeugen', style: TextStyle(fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Das Dokument wird auf dem Server gebaut. Wenn für die Sprache des '
          'Mitglieds ein Leseexemplar freigegeben ist, entsteht es gleich mit — '
          'unterschrieben wird immer die deutsche Fassung.',
          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
        ),
        const SizedBox(height: 12),

        if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [
              Icon(Icons.assignment_ind_outlined, size: 40, color: F.h(Colors.grey, 300)),
              const SizedBox(height: 8),
              Text('Noch keine Vollmacht', style: TextStyle(color: F.h(Colors.grey, 600))),
            ]),
          )
        else
          for (final v in _items)
            _VollmachtKarte(
              vollmacht: v,
              signaturen: _signaturen[int.tryParse(raWert(v['id'])) ?? -1] ?? const [],
              onOeffnen: () => _oeffnen(v),
              onUebersetzung: raHat(v['uebersetzung_sprache'])
                  ? () => _oeffnen(v, typ: 'uebersetzung')
                  : null,
              onUnterschrift: _arbeitet ? null : () => _zurUnterschrift(v),
              onWiderruf: () => _widerrufen(v),
              onMail: _arbeitet ? null : () => _perMail(v),
              onFax: _arbeitet ? null : () => _perFax(v),
              onProtokoll: () => _versandprotokoll(v),
              // Der Knopf erscheint erst, wenn BEIDE unterschrieben haben —
              // vorher gibt es die Fassung nicht.
              onSigniert: _signiertVerfuegbar(v) == null ? null : () => _signiertOeffnen(v),
              onSigniertSpeichern:
                  _signiertVerfuegbar(v) == null ? null : () => _signiertOeffnen(v, speichern: true),
            ),

        const SizedBox(height: 18),
        const Divider(),

        // 🔴 Die Grenzen stehen SICHTBAR, nicht im Kleingedruckten. Sie sind
        // der Grund, warum die Stelle die Vollmacht annehmen kann: der
        // Verein ist kein Anwalt (§ 2 Abs. 1 RDG).
        Text('Was der Verein NICHT tut', style: TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.bold, color: F.h(Colors.red, 800))),
        const SizedBox(height: 4),
        Text(
          'Der Verein ist ein gemeinnütziger Verein, kein Rechtsanwalt. Er wird '
          'unentgeltlich und im Rahmen seines Satzungszwecks tätig (§§ 6, 7 RDG) und '
          'nimmt keine rechtliche Prüfung des Einzelfalls vor (§ 2 Abs. 1 RDG). '
          'Genau dieser Zuschnitt macht die Vollmacht annehmbar.',
          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700)),
        ),
        const SizedBox(height: 8),
        for (final g in _grenzen)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.block, size: 13, color: Colors.red.shade400),
              const SizedBox(width: 6),
              Expanded(child: Text(g, style: const TextStyle(fontSize: 11.5))),
            ]),
          ),
      ]),
      if (_arbeitet)
        const Positioned.fill(
          child: ColoredBox(
            color: Color(0x33000000),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
    ]);
  }
}

/// Die Vollmacht per E-Mail an die Stadt — Anschreiben wählen, ändern,
/// senden.
///
/// ⚠️ Der Text ist ÄNDERBAR. Die Bausteine sind ein Vorschlag; wer eine
/// Behörde anschreibt, kennt den Fall besser als eine Vorlage.
///
/// ⚠️ Zwei Stellen bei derselben Stadt, und sie sind nicht austauschbar:
/// die Kasse führt das Buchungszeichen, mahnt und vollstreckt; die
/// Fachstelle entscheidet über Ermäßigung und Härtefall. Ein Ratenvorschlag
/// an die Fachstelle wartet auf eine Antwort von jemandem, der sie nicht
/// geben kann — deshalb steht die Wahl oben und nicht im Kleingedruckten.
class _KigaVollmachtMailDialog extends StatefulWidget {
  final ApiService apiService;
  final int vollmachtId;
  final Map<String, dynamic> daten;
  const _KigaVollmachtMailDialog({
    required this.apiService,
    required this.vollmachtId,
    required this.daten,
  });

  @override
  State<_KigaVollmachtMailDialog> createState() => _KigaVollmachtMailDialogState();
}

class _KigaVollmachtMailDialogState extends State<_KigaVollmachtMailDialog> {
  late Map<String, dynamic> _daten;
  late String _rolle;
  String _vorlage = '';
  bool _sendet = false;
  final _empfaengerC = TextEditingController();
  final _betreffC = TextEditingController();
  final _textC = TextEditingController();

  Map<String, dynamic> get _vorlagen => raKarte(_daten, 'vorlagen');

  @override
  void initState() {
    super.initState();
    _daten = widget.daten;
    _rolle = raWert(_daten['rolle']).isEmpty ? 'kasse' : raWert(_daten['rolle']);
    _vorlage = _vorlagen.keys.isEmpty ? '' : _vorlagen.keys.first;
    _empfaengerC.text = raWert(_daten['empfaenger']);
    _uebernehmen();
  }

  @override
  void dispose() {
    for (final c in [_empfaengerC, _betreffC, _textC]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Setzt Betreff und Text aus der gewählten Vorlage.
  void _uebernehmen() {
    final v = raKarte(_vorlagen, _vorlage);
    _betreffC.text = raWert(v['betreff']);
    _textC.text = raWert(v['text']);
  }

  /// Die Stelle wechseln — Adresse und Anrede kommen neu vom Server.
  ///
  /// ⚠️ Neu geladen, nicht lokal umgeschrieben: die Anrede hängt daran, ob
  /// im Datensatz eine Person mit „Frau"/„Herr" steht. Das weiß nur der
  /// Server, und geraten wird sie nicht.
  Future<void> _stelleWechseln(String rolle) async {
    if (rolle == _rolle) return;
    setState(() => _sendet = true);
    final res = await widget.apiService
        .kigaVollmachtMailVorlagen(widget.vollmachtId, rolle: rolle);
    if (!mounted) return;
    setState(() {
      _sendet = false;
      if (res['success'] == true) {
        _daten = Map<String, dynamic>.from(res);
        _rolle = rolle;
        _empfaengerC.text = raWert(_daten['empfaenger']);
        _uebernehmen();
      }
    });
  }

  Future<void> _senden() async {
    setState(() => _sendet = true);
    final res = await widget.apiService.kigaVollmachtMailSenden(
      vollmachtId: widget.vollmachtId,
      vorlage: _vorlage,
      rolle: _rolle,
      empfaenger: _empfaengerC.text.trim(),
      betreff: _betreffC.text.trim(),
      text: _textC.text,
    );
    if (!mounted) return;
    setState(() => _sendet = false);
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(raWert(res['message']).isEmpty
          ? (ok ? 'Gesendet' : 'Fehlgeschlagen')
          : raWert(res['message'])),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
    if (ok) Navigator.pop(context, Map<String, dynamic>.from(res));
  }

  @override
  Widget build(BuildContext context) {
    final breite = MediaQuery.of(context).size.width;
    final bereit = _daten['bereit'] == true;

    return AlertDialog(
      title: const Text('Vollmacht per E-Mail', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: breite < 620 ? breite * 0.9 : 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!bereit)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: F.h(Colors.orange, 50),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: F.h(Colors.orange, 200)),
                ),
                child: Text(
                  'Es liegt noch keine von beiden Seiten unterschriebene Fassung vor '
                  '(${raWert(_daten['unterschrieben'])} von ${raWert(_daten['noetig'])}). '
                  'Zur Stadt geht ausschließlich die unterschriebene — erst '
                  'unterschreiben lassen, dann senden.',
                  style: TextStyle(fontSize: 11.5, color: F.h(Colors.orange, 900)),
                ),
              ),

            // ── An welche Stelle ─────────────────────────────────────
            Text('An welche Stelle', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [
              ChoiceChip(
                selected: _rolle == 'kasse',
                onSelected: _sendet ? null : (_) => _stelleWechseln('kasse'),
                label: const Text('Stadtkasse', style: TextStyle(fontSize: 11)),
              ),
              ChoiceChip(
                selected: _rolle == 'fachstelle',
                onSelected: _sendet ? null : (_) => _stelleWechseln('fachstelle'),
                label: const Text('Fachstelle', style: TextStyle(fontSize: 11)),
              ),
            ]),
            const SizedBox(height: 3),
            Text(
              _rolle == 'kasse'
                  ? 'Buchungszeichen, Mahnung, Vollstreckung, Ratenvereinbarung.'
                  : 'Ermäßigung und Härtefall (§ 3 Abs. 8 der Entgeltordnung).',
              style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600)),
            ),
            const SizedBox(height: 10),

            // ── Anschreiben ──────────────────────────────────────────
            Text('Anschreiben', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
            const SizedBox(height: 4),
            // ⚠️ RadioGroup, nicht groupValue/onChanged je Kachel: die beiden
            // sind seit Flutter 3.32 abgekündigt, und der Analyzer läuft hier
            // ohne geduldete Meldungen.
            RadioGroup<String>(
              groupValue: _vorlage,
              onChanged: (v) {
                if (_sendet || v == null) return;
                setState(() {
                  _vorlage = v;
                  _uebernehmen();
                });
              },
              child: Column(children: _vorlagen.keys.map((k) {
                final v = raKarte(_vorlagen, k);
                return RadioListTile<String>(
                  value: k,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: kZahlungFarbe,
                  title: Text(raWert(v['titel']),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(raWert(v['hinweis']),
                      style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 500))),
                );
              }).toList()),
            ),
            const SizedBox(height: 6),

            TextField(
              controller: _empfaengerC,
              decoration: const InputDecoration(
                labelText: 'An', isDense: true, border: OutlineInputBorder()),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _betreffC,
              decoration: const InputDecoration(
                labelText: 'Betreff', isDense: true, border: OutlineInputBorder()),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _textC,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'Text', isDense: true, border: OutlineInputBorder()),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              'Anhang: ${raWert(_daten['anhang'])}\n'
              'Absender: ${raWert(_daten['absender'])} — die Antwort kommt ins '
              'Vereinspostfach, nicht ins persönliche.\n'
              'Die Signatur hängt der Server an.',
              style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600)),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sendet ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: (_sendet || !bereit) ? null : _senden,
          style: FilledButton.styleFrom(backgroundColor: kZahlungFarbe),
          icon: _sendet
              ? const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send, size: 16),
          label: const Text('Senden'),
        ),
      ],
    );
  }
}

/// Wie viele Unterschriften liegen vor, und wie viele werden gebraucht.
///
/// 🔴 AUS DER GRUPPE, NICHT AUS DER LISTE.
/// `SignaturService().liste(userId:)` steht unter EINEM Mitglied und
/// liefert nur dessen Zeilen. Bei einer Vollmacht ist das genau eine von
/// zweien — die zweite gehört dem Vorstand und trägt eine andere
/// `user_id`. Wer die gelieferten Zeilen zählt, schreibt „0 von 1" statt
/// „0 von 2" und hält die Sache für fertig, sobald das Mitglied
/// unterschrieben hat.
///
/// ⚠️ Als eigene Funktion, damit ein Test sie festhalten kann: der Fehler
/// ist an der Oberfläche unauffällig — eine Zahl, die plausibel aussieht.
({int vorhanden, int noetig}) kigaUnterschriftStand(List<Signaturvorgang> signaturen) {
  if (signaturen.isEmpty) return (vorhanden: 0, noetig: 0);
  final s = signaturen.first;
  // ⚠️ Der Rückfall auf die Listenlänge gilt nur, wenn der Server gar
  // keine Gruppe kennt (`gruppe_id` NULL → gruppe_gesamt 1). Dann IST die
  // Liste die Wahrheit.
  final noetig = s.gruppeGesamt > 0 ? s.gruppeGesamt : signaturen.length;
  return (vorhanden: s.gruppeSigniert, noetig: noetig);
}

/// Die Versandwege, ausgeschrieben.
///
/// ⚠️ Spiegelt `kiga_zahlung_vollmacht_versand.weg` — die Aufzählung liegt
/// auf dem Server, das PHP in keinem Repo. Ein unbekannter Wert wird roh
/// gezeigt statt verschluckt.
const Map<String, String> kVersandWege = {
  'chat': 'in den Chat',
  'email': 'per E-Mail',
  'de_mail': 'per De-Mail',
  'fax': 'per Fax',
  'post': 'per Post',
  'persoenlich': 'persönlich übergeben',
};

class _VollmachtKarte extends StatelessWidget {
  final Map<String, dynamic> vollmacht;
  final List<Signaturvorgang> signaturen;
  final VoidCallback onOeffnen;
  final VoidCallback? onUebersetzung;
  final VoidCallback? onUnterschrift;
  final VoidCallback onWiderruf;
  final VoidCallback? onMail;
  final VoidCallback? onFax;
  final VoidCallback onProtokoll;
  /// Die Fassung mit BEIDEN Unterschriften. `null`, solange sie nicht
  /// existiert — dann gibt es auch keinen Knopf.
  final VoidCallback? onSigniert;
  final VoidCallback? onSigniertSpeichern;
  const _VollmachtKarte({
    required this.vollmacht,
    required this.signaturen,
    required this.onOeffnen,
    required this.onUebersetzung,
    required this.onUnterschrift,
    required this.onWiderruf,
    required this.onMail,
    required this.onFax,
    required this.onProtokoll,
    required this.onSigniert,
    required this.onSigniertSpeichern,
  });

  /// Was zuletzt hinausging.
  ///
  /// ⚠️ Steht hier nichts, heißt das „noch nicht verschickt" — und genau
  /// das wird geschrieben. Eine leere Zeile sähe aus wie ein Feld, das
  /// nicht geladen hat.
  Widget? _letzterVersand() {
    final letzter = vollmacht['letzter_versand'];
    if (letzter is! Map) return null;
    final weg = raWert(letzter['weg']);
    final fassung = raWert(letzter['fassung']) == 'original'
        ? 'deutsche Fassung'
        : 'Leseexemplar'
            '${raHat(letzter['sprache']) ? ' auf ${raSpracheName(raWert(letzter['sprache']))}' : ''}';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        const Icon(Icons.outgoing_mail, size: 12, color: kZahlungFarbe),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '${raDatumDe(letzter['gesendet_am'])} · $fassung '
            '${kVersandWege[weg] ?? weg} an ${raWert(letzter['empfaenger'])}',
            style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 700)),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = raWert(vollmacht['status_effektiv']);
    final widerrufen = status == 'widerrufen';
    // 🔴 Aus der GRUPPE — siehe kigaUnterschriftStand(). Die gelieferte
    // Liste enthält nur die Zeile des Mitglieds, nicht die des Vorstands.
    final stand = kigaUnterschriftStand(signaturen);
    final unterschrieben = stand.vorhanden;
    final noetig = stand.noetig;
    // ⚠️ Über die GRUPPE, nicht über die gelieferten Zeilen: die Zeile des
    // Vorstands ist hier nicht dabei. `signaturen.every()` wäre schon wahr,
    // sobald das Mitglied unterschrieben hat — und dann böte der Knopf einen
    // Versand an, den der Server richtigerweise ablehnt.
    final fertig = signaturen.isNotEmpty && signaturen.first.gruppeVollstaendig;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('gültig ab ${raDatumDe(vollmacht['valid_from'])}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            _Marke2(text: status, farbe: switch (status) {
              'unterzeichnet' || 'uebermittelt' => Colors.green.shade700,
              'widerrufen' => Colors.red.shade700,
              'abgelaufen' => Colors.orange.shade800,
              _ => Colors.blueGrey,
            }),
          ]),
          if (raHat(vollmacht['empfaenger_name']))
            Text(raWert(vollmacht['empfaenger_name']),
                style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700))),

          // ⚠️ Der Stand kommt aus dem Unterschriften-System. Steht dort
          // nichts, wird das gesagt — nicht „0 von 2" behauptet, was so
          // aussähe, als sei schon gefragt worden.
          const SizedBox(height: 6),
          Text(
            signaturen.isEmpty
                ? 'Noch nicht zur Unterschrift gestellt.'
                : '$unterschrieben von $noetig Unterschriften liegen vor.',
            style: TextStyle(fontSize: 11.5, color: F.h(Colors.grey, 700)),
          ),
          _letzterVersand() ?? const SizedBox.shrink(),

          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            // 🔴 ZUERST die unterschriebene Fassung, wenn es sie gibt. Sie ist
            // das Ergebnis — der Entwurf daneben interessiert dann kaum noch.
            // Stand sie nicht auf dem Schirm, sah es aus, als sei nichts
            // passiert, obwohl beide unterschrieben hatten.
            if (onSigniert != null)
              FilledButton.icon(
                onPressed: onSigniert,
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.verified, size: 14),
                label: const Text('Unterschrieben', style: TextStyle(fontSize: 11)),
              ),
            if (onSigniertSpeichern != null)
              IconButton(
                onPressed: onSigniertSpeichern,
                icon: const Icon(Icons.download, size: 16),
                tooltip: 'Unterschriebene Fassung speichern',
                visualDensity: VisualDensity.compact,
                color: Colors.green.shade700,
              ),
            OutlinedButton.icon(
              onPressed: onOeffnen,
              icon: const Icon(Icons.picture_as_pdf, size: 14),
              label: Text(onSigniert != null ? 'Entwurf' : 'Deutsch',
                  style: const TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            if (onUebersetzung != null)
              OutlinedButton.icon(
                onPressed: onUebersetzung,
                icon: const Icon(Icons.translate, size: 14),
                label: Text(raSpracheName(raWert(vollmacht['uebersetzung_sprache'])),
                    style: const TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            if (!widerrufen && signaturen.isEmpty)
              FilledButton.icon(
                onPressed: onUnterschrift,
                style: FilledButton.styleFrom(
                    backgroundColor: kZahlungFarbe, visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.draw, size: 14),
                label: const Text('Zur Unterschrift', style: TextStyle(fontSize: 11)),
              ),
            // 🔴 Mail und Fax erst, wenn BEIDE unterschrieben haben. Zur
            // Stadt geht ausschließlich die unterschriebene Fassung — der
            // Server lehnt alles andere ab, und ein Knopf, der ins Leere
            // führt, erzieht zum Ignorieren von Fehlermeldungen.
            if (!widerrufen && fertig) ...[
              OutlinedButton.icon(
                onPressed: onMail,
                icon: const Icon(Icons.alternate_email, size: 14),
                label: const Text('Per E-Mail', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                    foregroundColor: kZahlungFarbe, visualDensity: VisualDensity.compact),
              ),
              OutlinedButton.icon(
                onPressed: onFax,
                icon: const Icon(Icons.fax, size: 14),
                label: const Text('Per Fax', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                    foregroundColor: kZahlungFarbe, visualDensity: VisualDensity.compact),
              ),
            ],
            TextButton.icon(
              onPressed: onProtokoll,
              icon: const Icon(Icons.history, size: 14),
              label: const Text('Versand', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            if (!widerrufen)
              TextButton.icon(
                onPressed: onWiderruf,
                icon: const Icon(Icons.gpp_bad, size: 14),
                label: const Text('Widerrufen', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.red, visualDensity: VisualDensity.compact),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _Marke2 extends StatelessWidget {
  final String text;
  final Color farbe;
  const _Marke2({required this.text, required this.farbe});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration:
            BoxDecoration(color: farbe.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
        child: Text(text,
            style: TextStyle(fontSize: 10.5, color: farbe, fontWeight: FontWeight.w600)),
      );
}

/// Die Ankreuzmatrix vor dem Erzeugen.
///
/// ⚠️ Die Gruppe „auskunft" ist umgekehrt gebaut als die beiden anderen:
/// dort gilt ein Punkt, SOLANGE er nicht abgewählt wurde — Auskunft ist der
/// Anlass des Dokuments. Bei „organisation" und „zahlung" gilt nur, was
/// angekreuzt ist. Der Server rechnet genauso; wer das hier umdreht,
/// erzeugt ein PDF, das etwas anderes sagt als der Bildschirm.
class _VollmachtErzeugenDialog extends StatefulWidget {
  final Map<String, dynamic> umfang;
  final List<String> grenzen;
  const _VollmachtErzeugenDialog({required this.umfang, required this.grenzen});

  @override
  State<_VollmachtErzeugenDialog> createState() => _VollmachtErzeugenDialogState();
}

class _VollmachtErzeugenDialogState extends State<_VollmachtErzeugenDialog> {
  final Map<String, Map<String, bool>> _gewaehlt = {};

  @override
  void initState() {
    super.initState();
    for (final gruppe in widget.umfang.entries) {
      if (gruppe.value is! Map) continue;
      final an = gruppe.key == 'auskunft';   // siehe Klassenkommentar
      _gewaehlt[gruppe.key] = {
        for (final e in Map<String, dynamic>.from(gruppe.value as Map).keys) e: an,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = zahlungDialogGroesse(context);
    return AlertDialog(
      title: const Text('Vollmacht erzeugen', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: g.width,
        height: g.height * 0.7,
        child: ListView(children: [
          for (final gruppe in widget.umfang.entries)
            if (gruppe.value is Map) ...[
              Text(
                switch (gruppe.key) {
                  'auskunft' => 'I. Auskunft und Unterlagen',
                  'organisation' => 'II. Organisatorische Unterstützung',
                  'zahlung' => 'III. Zahlung, Ermäßigung und Anträge',
                  _ => gruppe.key,
                },
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.bold, color: kZahlungFarbe),
              ),
              for (final e in Map<String, dynamic>.from(gruppe.value as Map).entries)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _gewaehlt[gruppe.key]?[e.key] ?? false,
                  title: Text(e.value.toString(), style: const TextStyle(fontSize: 11.5)),
                  onChanged: (v) =>
                      setState(() => _gewaehlt[gruppe.key]![e.key] = v ?? false),
                ),
              const SizedBox(height: 10),
            ],
          const Divider(),
          Text('Diese Punkte stehen im PDF immer, unabhängig von der Auswahl:',
              style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 4),
          for (final gr in widget.grenzen)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.block, size: 12, color: Colors.red.shade300),
                const SizedBox(width: 5),
                Expanded(child: Text(gr, style: const TextStyle(fontSize: 10.5))),
              ]),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            for (final e in _gewaehlt.entries)
              e.key: {for (final k in e.value.entries) k.key: k.value ? 1 : 0},
          }),
          style: FilledButton.styleFrom(backgroundColor: kZahlungFarbe),
          child: const Text('Erzeugen'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 7 · Mahnverfahren
// ═══════════════════════════════════════════════════════════════════════

class _MahnverfahrenTab extends StatefulWidget {
  final ApiService apiService;
  final int buchungszeichenId;
  const _MahnverfahrenTab({required this.apiService, required this.buchungszeichenId});

  @override
  State<_MahnverfahrenTab> createState() => _MahnverfahrenTabState();
}

class _MahnverfahrenTabState extends State<_MahnverfahrenTab> {
  List<Map<String, dynamic>> _fristen = [];
  Map<String, dynamic> _daten = {};
  bool _vorhanden = false;
  bool _geladen = false;
  String _vorbehalt = '';

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final res = await widget.apiService.getKigaMahnverfahren(widget.buchungszeichenId);
    if (!mounted) return;
    setState(() {
      _vorhanden = res['exists'] == true;
      _daten = _vorhanden ? raKarte(res, 'data') : {};
      _fristen = raListe(res, 'fristen');
      _vorbehalt = raWert(res['vorbehalt']);
      _geladen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(12), children: [
      // ⚠️ Die Erklärung steht oben, weil sie beim Klonen fast weggefallen
      // wäre: bei einer öffentlich-rechtlichen Gebühr vollstreckt die Stadt
      // selbst. Hier ist das Entgelt privatrechtlich — die Stadt hat KEINEN
      // Titel und muss den Zivilweg gehen.
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: F.h(Colors.deepOrange, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(Colors.deepOrange, 200)),
        ),
        child: Text(
          'Das Entgelt ist privatrechtlich. Die Stelle hat keinen Vollstreckungstitel '
          'und muss den Zivilweg gehen: Mahnbescheid nach §§ 688 ff. ZPO. '
          '⚠️ Gegen einen Mahnbescheid läuft die Widerspruchsfrist von ZWEI WOCHEN ab '
          'Zustellung (§ 692 Abs. 1 Nr. 3 ZPO). Der Widerspruch ist vom Mitglied selbst '
          'oder durch eine Kanzlei einzulegen — nicht durch den Verein.',
          style: TextStyle(fontSize: 11, color: F.h(Colors.deepOrange, 900)),
        ),
      ),
      const SizedBox(height: 12),

      if (!_vorhanden)
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Icon(Icons.gavel, size: 36, color: F.h(Colors.grey, 300)),
              const SizedBox(height: 8),
              Text('Kein Mahnverfahren erfasst', style: TextStyle(color: F.h(Colors.grey, 600))),
            ]),
          ),
        )
      else ...[
        _Zeile(symbol: Icons.stairs, label: 'Stufe', wert: raWert(_daten['stufe'])),
        _Zeile(symbol: Icons.person_outline, label: 'Rolle', wert: raWert(_daten['rolle'])),
        _Zeile(symbol: Icons.account_balance, label: 'Mahngericht', wert: raWert(_daten['mahngericht'])),
        _Zeile(symbol: Icons.tag, label: 'Geschäftszeichen', wert: raWert(_daten['gz_mahngericht'])),
        _Zeile(symbol: Icons.event, label: 'MB zugestellt',
            wert: raDatumDe(_daten['mb_zugestellt_am'])),
        if (_fristen.isNotEmpty) ...[
          const Divider(height: 20),
          Text('Fristen', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: F.h(Colors.grey, 700))),
          const SizedBox(height: 6),
          // ⚠️ Fertig gerechnet vom Server. Der Client rechnet NICHTS nach —
          // eine Notfrist, die auf zwei Wegen entsteht, hat irgendwann zwei
          // Werte.
          for (final f in _fristen)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(raWert(f['bezeichnung']), style: const TextStyle(fontSize: 12.5)),
                subtitle: Text(
                  '${raDatumDe(f['ende'])}'
                  '${raHat(f['grundlage']) ? ' · ${raWert(f['grundlage'])}' : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: _FristMarke(dringlichkeit: raWert(f['dringlichkeit'])),
              ),
            ),
        ],
      ],

      if (_vorbehalt.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(_vorbehalt, style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600))),
      ],
    ]);
  }
}

class _FristMarke extends StatelessWidget {
  final String dringlichkeit;
  const _FristMarke({required this.dringlichkeit});

  @override
  Widget build(BuildContext context) {
    final (farbe, text) = switch (dringlichkeit) {
      'abgelaufen' => (Colors.red.shade700, 'abgelaufen'),
      'heute' => (Colors.red.shade600, 'heute'),
      'bald' => (Colors.deepOrange.shade700, 'bald'),
      _ => (Colors.grey.shade600, dringlichkeit),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text, style: TextStyle(fontSize: 10.5, color: farbe, fontWeight: FontWeight.w600)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Wer unterschreibt
// ═══════════════════════════════════════════════════════════════════════

/// Wahl des Vollmachtgebers.
///
/// 🔴 DER GRUND, WARUM ES DIESEN DIALOG GIBT
///
/// Ein Buchungszeichen kann auf dem Konto eines KINDES liegen. Der
/// Kontoinhaber ist dann der Betroffene, nicht der Schuldner:
/// zahlungspflichtig sind nach § 4 Abs. 1 der Entgeltordnung die
/// gesetzlichen Vertreter. Ein Fünfjähriger ist geschäftsunfähig
/// (§ 104 Nr. 1 BGB); eine auf ihn ausgestellte Vollmacht ist nichtig.
///
/// Vor diesem Dialog wurde stillschweigend der Kontoinhaber genommen — und
/// für ein fünfjähriges Kind eine Urkunde erzeugt, ohne eine einzige
/// Warnung.
///
/// ⚠️ DREI ZUSTÄNDE, nicht zwei: volljährig, minderjährig, Alter
/// unbekannt. Ein fehlendes Geburtsdatum heißt „unbekannt", nicht
/// „volljährig" — und gerade bei Kinderkonten sind die Daten dünn.
class _VollmachtgeberDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const _VollmachtgeberDialog({required this.apiService, required this.userId});

  @override
  State<_VollmachtgeberDialog> createState() => _VollmachtgeberDialogState();
}

class _VollmachtgeberDialogState extends State<_VollmachtgeberDialog> {
  Map<String, dynamic> _inhaber = {};
  List<Map<String, dynamic>> _vorschlaege = [];
  List<Map<String, dynamic>> _treffer = [];
  bool _geladen = false;
  bool _sucht = false;
  int? _gewaehlt;
  final _sucheC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    _sucheC.dispose();
    super.dispose();
  }

  Future<void> _laden({String? suche}) async {
    if (suche != null) setState(() => _sucht = true);
    final res = await widget.apiService
        .listKigaVollmachtgeber(widget.userId, suche: suche);
    if (!mounted) return;
    setState(() {
      _inhaber = raKarte(res, 'inhaber');
      _vorschlaege = raListe(res, 'vorschlaege');
      _treffer = raListe(res, 'treffer');
      // Wenn der Inhaber selbst darf, ist er die naheliegende Wahl.
      _gewaehlt ??= _inhaber['darf_selbst'] == true
          ? int.tryParse(raWert(_inhaber['user_id']))
          : (_vorschlaege.isEmpty ? null : int.tryParse(raWert(_vorschlaege.first['user_id'])));
      _geladen = true;
      _sucht = false;
    });
  }

  // ⚠️ Hier wird nichts gemerkt. Die Verknüpfung Kind → Vormund wird im
  // Mitgliederbereich gepflegt, mitsamt Typ und Nachweis, wer sie wann
  // eingetragen hat; von hier aus geschrieben stünde sie ohne beides da.
  // Der Server nimmt sie als Vorschlag — wer sie ändern will, ändert sie
  // dort, wo sie herkommt.
  void _uebernehmen() {
    if (_gewaehlt == null) return;
    Navigator.pop(context, _gewaehlt);
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) {
      return const AlertDialog(
        content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
      );
    }
    final darfSelbst = _inhaber['darf_selbst'] == true;
    final unbekannt = _inhaber['alter_unbekannt'] == true;
    final inhaberId = int.tryParse(raWert(_inhaber['user_id'])) ?? 0;

    return AlertDialog(
      title: const Text('Wer erteilt die Vollmacht?', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: zahlungDialogGroesse(context).width,
        height: zahlungDialogGroesse(context).height * 0.62,
        child: Column(children: [
          // ── Der Kontoinhaber, mit Begründung ──────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: darfSelbst ? F.h(Colors.green, 50) : F.h(Colors.deepOrange, 50),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: darfSelbst ? F.h(Colors.green, 200) : F.h(Colors.deepOrange, 200)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Der Vorgang liegt auf dem Konto von '
                '${raWert(_inhaber['name'])} (${raWert(_inhaber['mitgliedernummer'])}).',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                darfSelbst
                    ? 'Volljährig — kann selbst unterschreiben.'
                    : unbekannt
                        ? 'Beim Konto ist kein Geburtsdatum hinterlegt. Ohne das lässt '
                          'sich nicht prüfen, ob unterschrieben werden darf — bitte den '
                          'zahlenden Elternteil wählen oder das Datum ergänzen.'
                        : '${raWert(_inhaber['alter'])} Jahre alt und damit nicht '
                          'geschäftsfähig (§ 104 Nr. 1, §§ 106 ff. BGB). Zahlungspflichtig '
                          'sind nach § 4 Abs. 1 der Entgeltordnung die gesetzlichen '
                          'Vertreter — bitte den zahlenden Elternteil wählen.',
                style: TextStyle(
                    fontSize: 11.5,
                    color: darfSelbst ? F.h(Colors.green, 900) : F.h(Colors.deepOrange, 900)),
              ),
            ]),
          ),
          const SizedBox(height: 10),

          TextField(
            controller: _sucheC,
            decoration: InputDecoration(
              labelText: 'Elternteil suchen',
              hintText: 'Name oder Mitgliedsnummer…',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              suffixIcon: _sucht
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (v) => _laden(suche: v),
            onChanged: (v) {
              if (v.trim().length >= 2) _laden(suche: v);
            },
          ),
          const SizedBox(height: 8),

          Expanded(
            child: ListView(children: [
              for (final v in _vorschlaege)
                _GeberZeile(
                  eintrag: v,
                  gewaehlt: _gewaehlt == int.tryParse(raWert(v['user_id'])),
                  onTap: () => setState(() => _gewaehlt = int.tryParse(raWert(v['user_id']))),
                ),
              if (_treffer.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text('Suchergebnisse',
                      style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
                ),
                for (final v in _treffer)
                  _GeberZeile(
                    eintrag: v,
                    gewaehlt: _gewaehlt == int.tryParse(raWert(v['user_id'])),
                    onTap: () => setState(() => _gewaehlt = int.tryParse(raWert(v['user_id']))),
                  ),
              ],
              if (_vorschlaege.isEmpty && _treffer.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _sucheC.text.trim().length >= 2
                        ? 'Keine volljährige Person gefunden.'
                        : 'Namen eingeben, um zu suchen.',
                    style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 600)),
                    textAlign: TextAlign.center,
                  ),
                ),
            ]),
          ),

          if (_gewaehlt != null && _gewaehlt != inhaberId)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Die Zuordnung Kind → Vormund wird im Mitgliedsdatensatz '
                'gepflegt, nicht hier.',
                style: TextStyle(fontSize: 10.5, color: F.h(Colors.grey, 600)),
              ),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: _gewaehlt == null ? null : _uebernehmen,
          style: FilledButton.styleFrom(backgroundColor: kZahlungFarbe),
          child: const Text('Weiter'),
        ),
      ],
    );
  }
}

/// Die sechs Werte von `users.vormund_typ`, ausgeschrieben.
///
/// ⚠️ Sie wiegen NICHT gleich schwer, und genau darum steht der Typ auf
/// dem Schirm. `sorgeberechtigter` ist die elterliche Sorge selbst
/// (§ 1629 BGB) und trägt die Vollmacht ohne Weiteres.
/// `familienangehoeriger` sagt nur „gehört zur Familie" — eine Großmutter
/// ist Familie und trotzdem nicht sorgeberechtigt. Wer unterschreibt,
/// erklärt mit der Unterschrift, dass er vertreten darf; die Auswahl soll
/// mit dem Wissen getroffen werden, das der Datensatz wirklich hergibt.
const Map<String, String> kVormundTypen = {
  'sorgeberechtigter': 'sorgeberechtigt',
  'familienangehoeriger': 'Familienangehörige(r)',
  'ehrenamtlich': 'ehrenamtlich bestellt',
  'vorlaeufig': 'vorläufig bestellt',
  'vorsorgevollmacht': 'Vorsorgevollmacht',
  'berufsbetreuer': 'Berufsbetreuer(in)',
};

class _GeberZeile extends StatelessWidget {
  final Map<String, dynamic> eintrag;
  final bool gewaehlt;
  final VoidCallback onTap;
  const _GeberZeile({required this.eintrag, required this.gewaehlt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final typRoh = raWert(eintrag['vormund_typ']);
    // ⚠️ Ein unbekannter Wert wird ROH gezeigt, nicht verschluckt. Kommt
    // je ein siebter Typ in die Aufzählung, soll er auffallen und nicht
    // als leere Stelle durchgehen.
    final typ = typRoh.isEmpty ? '' : (kVormundTypen[typRoh] ?? typRoh);

    return ListTile(
      dense: true,
      leading: Icon(gewaehlt ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: 18, color: gewaehlt ? kZahlungFarbe : F.h(Colors.grey, 500)),
      title: Text(raWert(eintrag['name']),
          style: TextStyle(
              fontSize: 13, fontWeight: gewaehlt ? FontWeight.bold : FontWeight.w600)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          [raWert(eintrag['mitgliedernummer']),
           raHat(eintrag['alter']) ? '${raWert(eintrag['alter'])} Jahre' : '',
           raWert(eintrag['grund'])]
              .where((s) => s.isNotEmpty)
              .join(' · '),
          style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600)),
        ),
        if (typ.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                typRoh == 'sorgeberechtigter'
                    ? Icons.verified_user_outlined
                    : Icons.help_outline,
                size: 12,
                color: typRoh == 'sorgeberechtigter'
                    ? F.h(Colors.green, 700)
                    : F.h(Colors.orange, 800),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  typRoh == 'sorgeberechtigter'
                      ? typ
                      : '$typ — Vertretungsbefugnis nicht aus dem Datensatz belegt',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: typRoh == 'sorgeberechtigter'
                        ? F.h(Colors.green, 800)
                        : F.h(Colors.orange, 900),
                  ),
                ),
              ),
            ]),
          ),
      ]),
      onTap: onTap,
    );
  }
}
