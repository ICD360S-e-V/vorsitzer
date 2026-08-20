import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'vermieter_dokumente.dart';

/// Widerspruch gegen die Forderung des Inkassobüros.
///
/// ⚠️ NICHT der Widerspruch gegen den Mahnbescheid. Die beiden zu
/// verwechseln kostet den Fall:
///
/// | | gegen das Inkassobüro | gegen den Mahnbescheid |
/// |---|---|---|
/// | wohin | an das Büro | an das Mahngericht |
/// | Frist | **keine** | zwei Wochen ab Zustellung |
/// | Form | formfrei | Vordruck oder Schriftform (§ 690 Abs. 3 ZPO) |
/// | steht in | diesem Reiter | Reiter „Mahnverfahren" |
///
/// Wer hier bestreitet, hat damit NICHT dem Mahnbescheid widersprochen —
/// und umgekehrt.
class VermieterWiderspruch extends StatefulWidget {
  final ApiService apiService;
  final int vorfallId;

  /// Für den Brieftext: wie das Büro heißt und unter welchem Aktenzeichen
  /// es schreibt. Ohne beides ist der Text nur eine Hülle.
  final String? inkassoName;
  final String? aktenzeichen;

  const VermieterWiderspruch({
    super.key,
    required this.apiService,
    required this.vorfallId,
    this.inkassoName,
    this.aktenzeichen,
  });

  @override
  State<VermieterWiderspruch> createState() => _VermieterWiderspruchState();
}

/// Die Gründe, aus denen eine Forderung üblicherweise bestritten wird.
///
/// ⚠️ Das ist eine Merkhilfe, kein Katalog: der freie Text darunter bleibt
/// das Entscheidende. Eine angekreuzte Zeile ohne Begründung überzeugt
/// niemanden — § 13a RDG verlangt vom Büro eine konkrete Darlegung, und
/// dasselbe Maß gilt für die Antwort darauf.
const _kGruende = <String, String>{
  'kein_vertrag': 'Ein Vertrag wurde nie geschlossen',
  'bereits_bezahlt': 'Die Forderung ist bereits bezahlt',
  'widerrufen': 'Der Vertrag wurde fristgerecht widerrufen',
  'leistung_mangelhaft': 'Die Leistung wurde nicht oder mangelhaft erbracht',
  'hoehe_falsch': 'Die Höhe der Hauptforderung stimmt nicht',
  'verjaehrt': 'Die Forderung ist verjährt (§ 195 BGB: drei Jahre)',
  'kosten_ueberhoeht': 'Die Inkassokosten sind überhöht oder nicht geschuldet',
  'kein_verzug': 'Es lag kein Verzug vor — dann sind auch keine Kosten geschuldet',
  'identitaet': 'Ich bin nicht die Person, gegen die sich die Forderung richtet',
  'unklar': 'Die Forderung ist trotz Nachfrage nicht nachvollziehbar dargelegt',
};

const _kVersandweg = <String, String>{
  'einschreiben': 'Einwurfeinschreiben',
  'brief': 'Brief',
  'email': 'E-Mail',
  'fax': 'Fax',
  'persoenlich': 'Persönlich übergeben',
  'online': 'Online-Portal',
};

const _kStatus = <String, String>{
  'entwurf': 'Entwurf',
  'versendet': 'Versendet',
  'reaktion_offen': 'Antwort steht aus',
  'anerkannt': 'Büro hat nachgegeben',
  'abgelehnt': 'Büro bleibt dabei',
  'erledigt': 'Erledigt',
};

class _VermieterWiderspruchState extends State<VermieterWiderspruch> {
  bool _geladen = false;
  bool _speichert = false;
  String? _fehler;
  bool _vorhanden = false;

  String _umfang = 'voll';
  String _status = 'entwurf';
  String? _versandweg;
  bool _kopieGlaeubiger = true;
  bool _auskunftVerlangt = true;
  final Set<String> _gruende = {};

  final _begruendungC = TextEditingController();
  final _einschreibenC = TextEditingController();
  final _reaktionC = TextEditingController();
  final _notizC = TextEditingController();
  final _versendetAm = TextEditingController();
  final _reaktionAm = TextEditingController();

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    for (final c in [
      _begruendungC, _einschreibenC, _reaktionC, _notizC, _versendetAm, _reaktionAm
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _laden() async {
    try {
      final res = await widget.apiService.getVermieterWiderspruch(widget.vorfallId);
      if (!mounted) return;
      final d = res['exists'] == true ? (res['data'] as Map<String, dynamic>?) : null;
      setState(() {
        _fehler = null;
        _geladen = true;
        _vorhanden = d != null;
        if (d != null) {
          _umfang = d['umfang']?.toString() ?? 'voll';
          _status = d['status']?.toString() ?? 'entwurf';
          _versandweg = (d['versandweg']?.toString() ?? '').isEmpty
              ? null
              : d['versandweg'].toString();
          _kopieGlaeubiger = (int.tryParse(d['kopie_an_glaeubiger']?.toString() ?? '0') ?? 0) == 1;
          _auskunftVerlangt = (int.tryParse(d['auskunft_verlangt']?.toString() ?? '0') ?? 0) == 1;
          _versendetAm.text = d['versendet_am']?.toString() ?? '';
          _reaktionAm.text = d['reaktion_am']?.toString() ?? '';
          _begruendungC.text = d['begruendung']?.toString() ?? '';
          _einschreibenC.text = d['einschreiben_nr']?.toString() ?? '';
          _reaktionC.text = d['reaktion_text']?.toString() ?? '';
          _notizC.text = d['notizen']?.toString() ?? '';
          _gruende
            ..clear()
            ..addAll(((d['gruende'] as List?) ?? const []).map((e) => e.toString()));
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fehler = e.toString();
        _geladen = true;
      });
    }
  }

  Future<void> _speichern() async {
    setState(() => _speichert = true);
    final res = await widget.apiService.saveVermieterWiderspruch(widget.vorfallId, {
      'umfang': _umfang,
      'status': _status,
      'versandweg': _versandweg,
      'versendet_am': _versendetAm.text,
      'reaktion_am': _reaktionAm.text,
      'kopie_an_glaeubiger': _kopieGlaeubiger ? 1 : 0,
      'auskunft_verlangt': _auskunftVerlangt ? 1 : 0,
      'gruende': _gruende.toList(),
      'begruendung': _begruendungC.text.trim(),
      'einschreiben_nr': _einschreibenC.text.trim(),
      'reaktion_text': _reaktionC.text.trim(),
      'notizen': _notizC.text.trim(),
    });
    if (!mounted) return;
    setState(() => _speichert = false);
    final ok = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Gespeichert' : 'Nicht gespeichert: ${res['message'] ?? 'unbekannter Grund'}'),
      backgroundColor: ok ? Colors.green.shade600 : Colors.red,
    ));
    if (ok) _laden();
  }

  /// Der Brieftext, aus den angekreuzten Gründen gebaut.
  ///
  /// ⚠️ Eigene Formulierung, absichtlich keine Abschrift eines fremden
  /// Musterbriefs. Sie sagt dasselbe: bestreiten, Nachweis verlangen,
  /// nichts anerkennen.
  String _brieftext() {
    final buero = (widget.inkassoName ?? '').trim();
    final az = (widget.aktenzeichen ?? '').trim();
    final p = StringBuffer();
    p.writeln('Betreff: Widerspruch${az.isEmpty ? '' : ' — Ihr Aktenzeichen $az'}');
    p.writeln();
    p.writeln('Sehr geehrte Damen und Herren,');
    p.writeln();
    p.write('der von Ihnen${buero.isEmpty ? '' : ' ($buero)'} geltend gemachten Forderung ');
    switch (_umfang) {
      case 'teilweise':
        p.writeln('widerspreche ich teilweise.');
      case 'nur_kosten':
        p.writeln('widerspreche ich hinsichtlich der Inkassokosten.');
      default:
        p.writeln('widerspreche ich in vollem Umfang.');
    }
    p.writeln('Eine Zahlung leiste ich nicht.');
    if (_gruende.isNotEmpty) {
      p.writeln();
      p.writeln('Begründung:');
      for (final g in _gruende) {
        p.writeln('- ${_kGruende[g] ?? g}');
      }
    }
    final frei = _begruendungC.text.trim();
    if (frei.isNotEmpty) {
      p.writeln();
      p.writeln(frei);
    }
    if (_auskunftVerlangt) {
      p.writeln();
      p.writeln('Zugleich fordere ich Sie auf, die Forderung nach § 13a des '
          'Rechtsdienstleistungsgesetzes darzulegen: Name und Anschrift Ihres '
          'Auftraggebers, der Grund der Forderung mit Gegenstand und Datum des '
          'Vertragsschlusses, die Berechnung etwaiger Zinsen sowie Art, Höhe und '
          'Entstehungsgrund der geltend gemachten Inkassokosten. Bis dahin ist '
          'die Forderung für mich nicht überprüfbar.');
    }
    p.writeln();
    p.writeln('Ich weise darauf hin, dass eine bestrittene Forderung nicht die '
        'Voraussetzungen des § 31 Absatz 2 Nummer 4 und 5 des '
        'Bundesdatenschutzgesetzes erfüllt. Eine Übermittlung an eine '
        'Auskunftei wäre danach unzulässig.');
    p.writeln();
    p.writeln('Dieses Schreiben ist kein Anerkenntnis der Forderung, auch nicht '
        'dem Grunde nach.');
    p.writeln();
    p.writeln('Mit freundlichen Grüßen');
    return p.toString();
  }

  Widget _hinweis(MaterialColor farbe, IconData symbol, String titel, String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: farbe.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: farbe.shade200),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(symbol, size: 18, color: farbe.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titel,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.bold, color: farbe.shade900)),
              const SizedBox(height: 3),
              Text(text,
                  style: TextStyle(fontSize: 11.5, color: farbe.shade900, height: 1.45)),
            ]),
          ),
        ]),
      );

  Widget _abschnitt(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
      );

  Widget _datum(String label, TextEditingController c, {String? hinweis}) => TextField(
        controller: c,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: hinweis,
          helperMaxLines: 3,
          isDense: true,
          prefixIcon: const Icon(Icons.calendar_today, size: 16),
          suffixIcon: c.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () => setState(c.clear),
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: DateTime.tryParse(c.text) ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2040),
            locale: const Locale('de'),
          );
          if (d != null) setState(() => c.text = d.toIso8601String().substring(0, 10));
        },
      );

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    if (_fehler != null) return LadeFehler(meldung: _fehler!, onErneut: _laden);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ⚠️ Ganz oben, weil die Verwechslung den Fall kostet.
        _hinweis(Colors.blue, Icons.compare_arrows, 'Nicht der Widerspruch gegen den Mahnbescheid',
            'Dieser Widerspruch geht an das Inkassobüro: formfrei, ohne gesetzliche Frist. '
            'Der Widerspruch gegen einen Mahnbescheid geht an das GERICHT, hat zwei Wochen '
            'Frist und braucht Vordruck oder Schriftform — er steht im Reiter „Mahnverfahren". '
            'Das eine ersetzt das andere nicht.'),
        _hinweis(Colors.green, Icons.shield_outlined, 'Bestreiten schützt vor dem SCHUFA-Eintrag',
            'Solange die Forderung bestritten ist, fehlt die Voraussetzung des § 31 Abs. 2 '
            'Nr. 4 und 5 BDSG — eine Meldung an eine Auskunftei ist dann unzulässig. '
            '⚠️ Das gilt NICHT mehr, sobald ein Titel vorliegt (etwa ein '
            'Vollstreckungsbescheid) oder die Forderung anerkannt wurde.'),
        _hinweis(Colors.red, Icons.dangerous_outlined, 'Nichts unterschreiben, nichts anzahlen',
            'Eine Ratenzahlungsvereinbarung oder eine Teilzahlung ist ein Anerkenntnis: '
            'die Verjährung beginnt danach von vorn (§ 212 Abs. 1 Nr. 1 BGB), und das '
            'Bestreiten ist verbraucht. Wer bestreitet, zahlt nichts — auch nicht „erst mal '
            'einen Teil, um Ruhe zu haben".'),

        _abschnitt('Umfang'),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final e in const {
            'voll': 'Vollständig (100 %)',
            'teilweise': 'Teilweise',
            'nur_kosten': 'Nur die Inkassokosten',
          }.entries)
            ChoiceChip(
              label: Text(e.value, style: const TextStyle(fontSize: 11.5)),
              selected: _umfang == e.key,
              onSelected: (_) => setState(() => _umfang = e.key),
            ),
        ]),

        _abschnitt('Gründe'),
        for (final e in _kGruende.entries)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _gruende.contains(e.key),
            onChanged: (v) => setState(() {
              if (v == true) {
                _gruende.add(e.key);
              } else {
                _gruende.remove(e.key);
              }
            }),
            title: Text(e.value, style: const TextStyle(fontSize: 12.5)),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _begruendungC,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: 'Eigene Begründung',
            helperText: 'Je genauer, desto besser — ein Kreuz allein überzeugt niemanden.',
            helperMaxLines: 2,
            alignLabelWithHint: true,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 10),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _auskunftVerlangt,
          onChanged: (v) => setState(() => _auskunftVerlangt = v ?? false),
          title: const Text('Darlegung nach § 13a RDG verlangen',
              style: TextStyle(fontSize: 12.5)),
          subtitle: Text(
              'Auftraggeber, Vertragsgegenstand und -datum, Zinsberechnung, Art und Höhe '
              'der Inkassokosten. Kommt nichts, ist die Forderung nicht überprüfbar — '
              'und das ist selbst ein Grund.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _kopieGlaeubiger,
          onChanged: (v) => setState(() => _kopieGlaeubiger = v ?? false),
          title: const Text('Kopie an den ursprünglichen Gläubiger',
              style: TextStyle(fontSize: 12.5)),
          subtitle: Text(
              'Über die Forderung entscheidet er, nicht das Büro. Oft zieht er den '
              'Auftrag zurück, sobald er vom Streit erfährt.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ),

        _abschnitt('Musterschreiben'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: SelectableText(_brieftext(),
              style: const TextStyle(fontSize: 12, height: 1.5, fontFamily: 'monospace')),
        ),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _brieftext()));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Text kopiert'),
                duration: Duration(seconds: 2),
              ));
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Text kopieren', style: TextStyle(fontSize: 12)),
          ),
        ]),

        _abschnitt('Versand'),
        _hinweis(Colors.orange, Icons.local_post_office_outlined, 'Einwurfeinschreiben',
            'Der einzige Weg mit Zugangsnachweis, der wenig kostet. Wer per E-Mail '
            'bestreitet, hat im Streitfall nichts in der Hand — und genau darauf kommt '
            'es an, wenn das Büro später behauptet, es sei nie etwas gekommen.'),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _versandweg,
          decoration: InputDecoration(
            labelText: 'Versandweg',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: _kVersandweg.entries
              .map((e) => DropdownMenuItem(
                  value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12))))
              .toList(),
          onChanged: (v) => setState(() => _versandweg = v),
        ),
        const SizedBox(height: 10),
        _datum('Versendet am', _versendetAm),
        const SizedBox(height: 10),
        TextField(
          controller: _einschreibenC,
          decoration: InputDecoration(
            labelText: 'Sendungsnummer',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),

        _abschnitt('Stand und Antwort'),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _status,
          decoration: InputDecoration(
            labelText: 'Status',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: _kStatus.entries
              .map((e) => DropdownMenuItem(
                  value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12))))
              .toList(),
          onChanged: (v) => setState(() => _status = v ?? _status),
        ),
        const SizedBox(height: 10),
        _datum('Antwort erhalten am', _reaktionAm),
        const SizedBox(height: 10),
        TextField(
          controller: _reaktionC,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Was geantwortet wurde',
            alignLabelWithHint: true,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notizC,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Notizen',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),

        const SizedBox(height: 18),
        Row(children: [
          ElevatedButton.icon(
            onPressed: _speichert ? null : _speichern,
            icon: _speichert
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 16),
            label: const Text('Speichern'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple, foregroundColor: Colors.white),
          ),
          const Spacer(),
          if (_vorhanden)
            TextButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Widerspruch löschen?'),
                    content: const Text(
                        'Gründe, Text und Versanddaten werden entfernt. Der Vorfall bleibt.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Abbrechen')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Löschen', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                await widget.apiService.deleteVermieterWiderspruch(widget.vorfallId);
                if (!mounted) return;
                setState(() {
                  _gruende.clear();
                  _umfang = 'voll';
                  _status = 'entwurf';
                  _versandweg = null;
                });
                _laden();
              },
              icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
              label: Text('Löschen', style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
            ),
        ]),
      ]),
    );
  }
}
