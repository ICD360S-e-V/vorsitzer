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

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/ra_antwort.dart';
import 'behorde_kindergarten_zahlung.dart';

// ═══════════════════════════════════════════════════════════════════════
// Der Dialog
// ═══════════════════════════════════════════════════════════════════════

class KigaKassenzeichenDetailDialog extends StatelessWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> vorgang;
  final String adminMitgliedernummer;
  final VoidCallback onChanged;
  const KigaKassenzeichenDetailDialog({
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
                  raWert(vorgang['kassenzeichen']).isEmpty
                      ? '(ohne Kassenzeichen)'
                      : raWert(vorgang['kassenzeichen']),
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
            _KorrTab(apiService: apiService, kassenzeichenId: _kzId),
            _AkteneinsichtTab(apiService: apiService, kassenzeichenId: _kzId),
            _RatenTab(apiService: apiService, kassenzeichenId: _kzId, vorgang: vorgang),
            _ErmaessigungTab(apiService: apiService, kassenzeichenId: _kzId, onChanged: onChanged),
            _VollmachtTab(apiService: apiService, kassenzeichenId: _kzId),
            _MahnverfahrenTab(apiService: apiService, kassenzeichenId: _kzId),
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
        _Zeile(symbol: Icons.pin, label: 'Kassenzeichen', wert: raWert(vorgang['kassenzeichen'])),
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
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
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
        Icon(symbol, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
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
                color: Colors.blue.shade50,
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
              color: unbekannt ? Colors.amber.shade50 : kZahlungFarbe.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: unbekannt ? Colors.amber.shade300 : kZahlungFarbe.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(unbekannt ? Icons.help_outline : Icons.send, size: 14,
                    color: unbekannt ? Colors.amber.shade900 : kZahlungFarbe),
                const SizedBox(width: 6),
                Text('Geht an: ${widget.rolle}',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold,
                        color: unbekannt ? Colors.amber.shade900 : kZahlungFarbe)),
              ]),
              if ((widget.adresseBezeichnung ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 2),
                  child: Text(widget.adresseBezeichnung!,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
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
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
  final int kassenzeichenId;
  const _KorrTab({required this.apiService, required this.kassenzeichenId});

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
    final res = await widget.apiService.listKigaZahlungKorrespondenz(widget.kassenzeichenId);
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
            Icon(Icons.mail_outline, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Noch kein Schriftwechsel', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(
              'Was über „Akteneinsicht", „Ratenzahlung" oder „Ermäßigung" gesendet '
              'wird, erscheint hier automatisch.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
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
              color: eingehend ? Colors.green.shade700 : kZahlungFarbe,
              size: 20,
            ),
            title: Text(raWert(k['betreff']),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${raDatumDe(k['datum'])} · ${raWert(k['medium'])}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              // ⚠️ Der Zustellstand kommt MIT der Liste, nicht per zweitem
              // Aufruf. Ohne ihn stünde hier „gesendet" ohne jeden Hinweis
              // darauf, ob die Stelle es je bekommen hat.
              if (raHat(k['mail_status']))
                _Zustellstand(status: raWert(k['mail_status']), antwort: raWert(k['mail_antwort'])),
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
              builder: (ctx) => AlertDialog(
                title: Text(raWert(k['betreff']), style: const TextStyle(fontSize: 14)),
                content: SizedBox(
                  width: zahlungDialogGroesse(context).width,
                  child: SingleChildScrollView(
                    child: SelectableText(raWert(k['text']), style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
                ],
              ),
            ),
          ),
        );
      },
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
  final int kassenzeichenId;
  const _AkteneinsichtTab({required this.apiService, required this.kassenzeichenId});

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
    final v = await widget.apiService.listKigaAkteneinsicht(widget.kassenzeichenId);
    final t = await widget.apiService.kigaAkteneinsichtVorlagen(widget.kassenzeichenId);
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
              kassenzeichenId: widget.kassenzeichenId,
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
            fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        for (final s in bitten)
          if (_vorlagen[s] != null) _VorlagenKachel(
            vorlage: Map<String, dynamic>.from(_vorlagen[s] as Map),
            onSenden: () => _senden(s),
          ),

        const SizedBox(height: 16),
        Row(children: [
          Icon(Icons.gavel, size: 14, color: Colors.indigo.shade700),
          const SizedBox(width: 6),
          Text('Gesetzlicher Anspruch', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        ]),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Art. 15 DSGVO ist keine vierte Stufe hinter den drei Bitten, sondern ein '
            'eigener Weg mit gesetzlicher Frist von einem Monat (Art. 12 Abs. 3 DSGVO). '
            'Er kann sofort gegangen werden — wer ihn ans Ende stellt, verschenkt '
            'genau diesen Monat.',
            style: TextStyle(fontSize: 11, color: Colors.indigo.shade900),
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
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
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
                ? Colors.red.shade700
                : Colors.grey.shade600,
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
  final int kassenzeichenId;
  final Map<String, dynamic> vorgang;
  const _RatenTab({
    required this.apiService,
    required this.kassenzeichenId,
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
    final res = await widget.apiService.listKigaRatenplan(widget.kassenzeichenId);
    if (!mounted) return;
    setState(() {
      _plaene = raListe(res);
      _geladen = true;
    });
  }

  Future<void> _rechnen() async {
    setState(() => _rechnet = true);
    final res = await widget.apiService.kigaRatenplanRechnen(
      kassenzeichenId: widget.kassenzeichenId,
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
    final res = await widget.apiService.kigaAkteneinsichtVorlagen(widget.kassenzeichenId);
    final adressen = raKarte(res, 'adressen');
    final kasse = adressen['kasse'];
    final kasseMap = kasse is Map ? Map<String, dynamic>.from(kasse) : const <String, dynamic>{};

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _RatenSendenDialog(
        apiService: widget.apiService,
        kassenzeichenId: widget.kassenzeichenId,
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
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded, size: 15, color: Colors.amber.shade900),
            const SizedBox(width: 6),
            Text('Ohne Anerkennung einer Rechtspflicht',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900)),
          ]),
          const SizedBox(height: 4),
          Text(
            'Jedes Ratenschreiben trägt diesen Satz. Nach § 212 Abs. 1 Nr. 1 BGB lässt '
            'ein Anerkenntnis die dreijährige Verjährung neu beginnen — und schon eine '
            'gezahlte Rate genügt dafür. Der Satz ist genau das, was den Neubeginn '
            'verhindert. Der Server sendet nicht, wenn er fehlt.',
            style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
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
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ]),
        ),
      ],

      if (_plaene.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Divider(),
        Text('Bisherige Vorschläge', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
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
  final int kassenzeichenId;
  final String gesamt;
  final String monatlich;
  final String zahlweise;
  final String? adresse;
  final String adresseBezeichnung;
  const _RatenSendenDialog({
    required this.apiService,
    required this.kassenzeichenId,
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
      kassenzeichenId: widget.kassenzeichenId,
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
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
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
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
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
  final int kassenzeichenId;
  final VoidCallback onChanged;
  const _ErmaessigungTab({
    required this.apiService,
    required this.kassenzeichenId,
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
    final res = await widget.apiService.kigaErmaessigungVorlagen(widget.kassenzeichenId);
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
              kassenzeichenId: widget.kassenzeichenId,
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
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Text(
          'Eine Ratenzahlung verteilt den Betrag, sie verkleinert ihn nicht. Wer '
          'dauerhaft zu wenig hat, braucht eine Ermäßigung — und die gibt es auf '
          'zwei Wegen, die nichts miteinander zu tun haben und an verschiedene '
          'Stellen gehen.',
          style: TextStyle(fontSize: 11.5, color: Colors.green.shade900),
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
        Text(_vorbehalt, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
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
          Text(fussnote, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
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
  final int kassenzeichenId;
  const _VollmachtTab({required this.apiService, required this.kassenzeichenId});

  @override
  State<_VollmachtTab> createState() => _VollmachtTabState();
}

class _VollmachtTabState extends State<_VollmachtTab> {
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _optionen = {};
  List<String> _grenzen = [];
  bool _geladen = false;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final v = await widget.apiService.listKigaVollmachten(widget.kassenzeichenId);
    final o = await widget.apiService.kigaVollmachtOptionen();
    if (!mounted) return;
    setState(() {
      _items = raListe(v);
      _optionen = raKarte(o, 'umfang');
      final g = o['grenzen'];
      _grenzen = g is List ? g.map((e) => e.toString()).toList() : const [];
      _geladen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(12), children: [
      // ⚠️ EHRLICH BENANNT. Das Erzeugen des PDFs ist noch nicht gebaut;
      // ein grauer Knopf ohne Grund sieht aus wie ein Fehler. Was heute
      // schon geht — drucken, unterschreiben, Scan hochladen — steht
      // daneben, damit der Zweig benutzbar ist.
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.info_outline, size: 15, color: Colors.blue.shade900),
            const SizedBox(width: 6),
            Text('Erzeugen folgt', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
          ]),
          const SizedBox(height: 4),
          Text(
            'Das Vollmacht-PDF wird serverseitig gebaut; dieser Teil ist noch nicht '
            'ausgeliefert. Bis dahin: Vollmacht ausdrucken, unterschreiben lassen und '
            'den Scan unter „Korrespondenz" hochladen — der Versand lässt sich hier '
            'trotzdem protokollieren.',
            style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
          ),
        ]),
      ),
      const SizedBox(height: 14),

      // 🔴 Die Grenzen stehen SICHTBAR, nicht im Kleingedruckten. Sie sind
      // der Grund, warum die Stelle die Vollmacht annehmen kann: der Verein
      // ist kein Anwalt (§ 2 Abs. 1 RDG).
      Text('Was der Verein NICHT tut',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
      const SizedBox(height: 4),
      Text(
        'Der Verein ist ein gemeinnütziger Verein, kein Rechtsanwalt. Er wird '
        'unentgeltlich und im Rahmen seines Satzungszwecks tätig (§§ 6, 7 RDG) und '
        'nimmt keine rechtliche Prüfung des Einzelfalls vor (§ 2 Abs. 1 RDG). '
        'Genau dieser Zuschnitt macht die Vollmacht annehmbar.',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
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

      if (_optionen.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('Was der Verein tun darf', style: TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
        const SizedBox(height: 6),
        for (final gruppe in _optionen.entries)
          if (gruppe.value is Map)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(gruppe.key, style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                for (final e in Map<String, dynamic>.from(gruppe.value as Map).entries)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.check, size: 12, color: Colors.green.shade600),
                      const SizedBox(width: 5),
                      Expanded(child: Text(e.value.toString(),
                          style: const TextStyle(fontSize: 11))),
                    ]),
                  ),
              ]),
            ),
      ],

      if (_items.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Divider(),
        Text('Erteilte Vollmachten', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        for (final v in _items)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text('gültig ab ${raDatumDe(v['valid_from'])}',
                  style: const TextStyle(fontSize: 12.5)),
              subtitle: Text('Stand: ${raWert(v['status_effektiv'])}'
                  '${(int.tryParse(raWert(v['versand_anzahl'])) ?? 0) > 0 ? ' · ${raWert(v['versand_anzahl'])}× versandt' : ''}',
                  style: const TextStyle(fontSize: 11)),
            ),
          ),
      ],
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 7 · Mahnverfahren
// ═══════════════════════════════════════════════════════════════════════

class _MahnverfahrenTab extends StatefulWidget {
  final ApiService apiService;
  final int kassenzeichenId;
  const _MahnverfahrenTab({required this.apiService, required this.kassenzeichenId});

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
    final res = await widget.apiService.getKigaMahnverfahren(widget.kassenzeichenId);
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
          color: Colors.deepOrange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.deepOrange.shade200),
        ),
        child: Text(
          'Das Entgelt ist privatrechtlich. Die Stelle hat keinen Vollstreckungstitel '
          'und muss den Zivilweg gehen: Mahnbescheid nach §§ 688 ff. ZPO. '
          '⚠️ Gegen einen Mahnbescheid läuft die Widerspruchsfrist von ZWEI WOCHEN ab '
          'Zustellung (§ 692 Abs. 1 Nr. 3 ZPO). Der Widerspruch ist vom Mitglied selbst '
          'oder durch eine Kanzlei einzulegen — nicht durch den Verein.',
          style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade900),
        ),
      ),
      const SizedBox(height: 12),

      if (!_vorhanden)
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Icon(Icons.gavel, size: 36, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text('Kein Mahnverfahren erfasst', style: TextStyle(color: Colors.grey.shade600)),
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
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
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
        Text(_vorbehalt, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
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
