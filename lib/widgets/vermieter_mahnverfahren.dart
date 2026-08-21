import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'vermieter_dokumente.dart';
import '../utils/app_farben.dart';

/// Das gerichtliche Mahnverfahren zu einem Vorfall, §§ 688 ff. ZPO.
///
/// ⚠️ Zwei Dinge entscheiden hier über Geld, und beide werden regelmäßig
/// falsch gemacht:
///
/// 1. **Die Frist läuft ab ZUSTELLUNG, nicht ab Erlass.** Der Mahnbescheid
///    trägt oben ein Datum — das ist der Tag, an dem das Gericht ihn
///    erlassen hat. Die zwei Wochen für den Widerspruch beginnen erst mit
///    der Zustellung (§ 692 Abs. 1 Nr. 3 ZPO), und dazwischen liegen oft
///    mehrere Tage. Wer vom Erlassdatum rechnet, liegt zu spät.
///
/// 2. **Eine E-Mail ist kein Widerspruch.** Der Widerspruch braucht die
///    Form des § 690 Abs. 3 ZPO — Vordruck oder Schriftform. Eine Mail an
///    das Mahngericht ist unwirksam, und niemand antwortet darauf, dass
///    sie es ist. Die Frist läuft still weiter ab.
///
/// Deshalb steht beides auf dem Schirm, nicht in einer Hilfe-Seite.
class VermieterMahnverfahren extends StatefulWidget {
  final ApiService apiService;
  final int vorfallId;

  const VermieterMahnverfahren({
    super.key,
    required this.apiService,
    required this.vorfallId,
  });

  @override
  State<VermieterMahnverfahren> createState() => _VermieterMahnverfahrenState();
}

const _kStatus = <String, String>{
  'angekuendigt': 'Angekündigt',
  'mahnbescheid': 'Mahnbescheid zugestellt',
  'widerspruch': 'Widerspruch eingelegt',
  'vollstreckungsbescheid': 'Vollstreckungsbescheid',
  'einspruch': 'Einspruch eingelegt',
  'streitig': 'Streitiges Verfahren',
  'erledigt': 'Erledigt',
  'zurueckgenommen': 'Zurückgenommen',
};

class _VermieterMahnverfahrenState extends State<VermieterMahnverfahren> {
  Map<String, dynamic>? _daten;
  bool _geladen = false;
  bool _speichert = false;
  String? _fehler;

  final _gerichtC = TextEditingController();
  final _zeichenC = TextEditingController();
  final _antragstellerC = TextEditingController();
  final _hauptC = TextEditingController();
  final _nebenC = TextEditingController();
  final _kostenC = TextEditingController();
  final _notizC = TextEditingController();

  final _mbAm = TextEditingController();
  final _mbZugestellt = TextEditingController();
  final _wsFrist = TextEditingController();
  final _wsAm = TextEditingController();
  final _vbAm = TextEditingController();
  final _vbZugestellt = TextEditingController();
  final _esFrist = TextEditingController();
  final _esAm = TextEditingController();

  String _status = 'angekuendigt';

  List<TextEditingController> get _alle => [
        _gerichtC, _zeichenC, _antragstellerC, _hauptC, _nebenC, _kostenC, _notizC,
        _mbAm, _mbZugestellt, _wsFrist, _wsAm, _vbAm, _vbZugestellt, _esFrist, _esAm,
      ];

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    for (final c in _alle) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _laden() async {
    try {
      final res = await widget.apiService.getVermieterMahnverfahren(widget.vorfallId);
      if (!mounted) return;
      final d = res['exists'] == true ? (res['data'] as Map<String, dynamic>?) : null;
      setState(() {
        _daten = d;
        _fehler = null;
        _geladen = true;
        if (d != null) {
          _gerichtC.text = d['mahngericht']?.toString() ?? '';
          _zeichenC.text = d['geschaeftszeichen']?.toString() ?? '';
          _antragstellerC.text = d['antragsteller']?.toString() ?? '';
          _hauptC.text = d['hauptforderung']?.toString() ?? '';
          _nebenC.text = d['nebenforderung']?.toString() ?? '';
          _kostenC.text = d['kosten']?.toString() ?? '';
          _notizC.text = d['notizen']?.toString() ?? '';
          _mbAm.text = d['mahnbescheid_am']?.toString() ?? '';
          _mbZugestellt.text = d['mahnbescheid_zugestellt_am']?.toString() ?? '';
          _wsFrist.text = d['widerspruch_frist']?.toString() ?? '';
          _wsAm.text = d['widerspruch_am']?.toString() ?? '';
          _vbAm.text = d['vollstreckungsbescheid_am']?.toString() ?? '';
          _vbZugestellt.text = d['vollstreckungsbescheid_zugestellt_am']?.toString() ?? '';
          _esFrist.text = d['einspruch_frist']?.toString() ?? '';
          _esAm.text = d['einspruch_am']?.toString() ?? '';
          _status = d['status']?.toString() ?? 'angekuendigt';
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
    final res = await widget.apiService.saveVermieterMahnverfahren(widget.vorfallId, {
      'status': _status,
      'mahngericht': _gerichtC.text.trim(),
      'geschaeftszeichen': _zeichenC.text.trim(),
      'antragsteller': _antragstellerC.text.trim(),
      'hauptforderung': _hauptC.text.trim(),
      'nebenforderung': _nebenC.text.trim(),
      'kosten': _kostenC.text.trim(),
      'notizen': _notizC.text.trim(),
      'mahnbescheid_am': _mbAm.text,
      'mahnbescheid_zugestellt_am': _mbZugestellt.text,
      'widerspruch_frist': _wsFrist.text,
      'widerspruch_am': _wsAm.text,
      'vollstreckungsbescheid_am': _vbAm.text,
      'vollstreckungsbescheid_zugestellt_am': _vbZugestellt.text,
      'einspruch_frist': _esFrist.text,
      'einspruch_am': _esAm.text,
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

  /// Zwei Wochen ab Zustellung. Wird beim Speichern auch serverseitig
  /// gerechnet — hier vorab, damit die Zahl schon beim Eintippen dasteht
  /// und nicht erst nach dem Speichern.
  void _fristRechnen(TextEditingController zustellung, TextEditingController frist) {
    final z = DateTime.tryParse(zustellung.text);
    if (z == null) return;
    frist.text = z.add(const Duration(days: 14)).toIso8601String().substring(0, 10);
  }

  Widget _datum(String label, TextEditingController c,
      {VoidCallback? danach, String? hinweis}) {
    return TextField(
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
                onPressed: () => setState(() {
                  c.clear();
                  danach?.call();
                }),
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
        if (d != null) {
          setState(() {
            c.text = d.toIso8601String().substring(0, 10);
            danach?.call();
          });
        }
      },
    );
  }

  Widget _text(String label, TextEditingController c, {String? hinweis, int zeilen = 1}) {
    return TextField(
      controller: c,
      maxLines: zeilen,
      decoration: InputDecoration(
        labelText: label,
        helperText: hinweis,
        helperMaxLines: 3,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Die Zeile, die den Unterschied macht: wie viele Tage bleiben.
  Widget? _fristMelder(TextEditingController frist, TextEditingController erledigt,
      String was) {
    final f = DateTime.tryParse(frist.text);
    if (f == null) return null;
    if (erledigt.text.isNotEmpty) {
      return _band(Colors.green, Icons.check_circle,
          '$was am ${_deutsch(erledigt.text)} eingelegt — die Frist spielt keine Rolle mehr.');
    }
    final heute = DateTime.now();
    final tage = DateTime(f.year, f.month, f.day)
        .difference(DateTime(heute.year, heute.month, heute.day))
        .inDays;
    if (tage < 0) {
      return _band(Colors.red, Icons.error,
          'Frist am ${_deutsch(frist.text)} abgelaufen — seit ${-tage} Tag(en). '
          'Ein verspäteter $was hilft nicht mehr; jetzt zählt der Weg über das '
          'streitige Verfahren.');
    }
    if (tage <= 5) {
      return _band(Colors.red, Icons.warning_amber,
          'Nur noch $tage Tag(e) bis zum ${_deutsch(frist.text)}. '
          'Der $was muss beim Gericht EINGEHEN, nicht abgeschickt sein.');
    }
    return _band(Colors.orange, Icons.schedule,
        'Noch $tage Tage bis zum ${_deutsch(frist.text)}.');
  }

  Widget _band(MaterialColor farbe, IconData symbol, String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: F.h(farbe, 50),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: F.h(farbe, 200)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(symbol, size: 17, color: F.h(farbe, 700)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: F.h(farbe, 900), height: 1.4)),
          ),
        ]),
      );

  String _deutsch(String iso) {
    if (iso.length < 10) return iso;
    return '${iso.substring(8, 10)}.${iso.substring(5, 7)}.${iso.substring(0, 4)}';
  }

  Widget _abschnitt(String titel) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(titel,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: F.h(Colors.purple, 800))),
      );

  @override
  Widget build(BuildContext context) {
    if (!_geladen) return const Center(child: CircularProgressIndicator());
    if (_fehler != null) return LadeFehler(meldung: _fehler!, onErneut: _laden);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ⚠️ Steht ganz oben, nicht am Ende: wer hier landet, hat meist
        // gerade einen Mahnbescheid in der Hand und wenig Zeit.
        _band(Colors.blue, Icons.info_outline,
            'Die Widerspruchsfrist beginnt mit der ZUSTELLUNG, nicht mit dem Datum, '
            'das oben auf dem Mahnbescheid steht (§ 692 Abs. 1 Nr. 3 ZPO). Zwischen '
            'beiden liegen oft mehrere Tage.'),
        _band(Colors.red, Icons.mark_email_unread_outlined,
            'Eine E-Mail an das Mahngericht ist KEIN wirksamer Widerspruch. Es braucht '
            'den beiliegenden Vordruck oder Schriftform (§ 690 Abs. 3 ZPO) — und niemand '
            'teilt mit, dass die Mail unwirksam war. Die Frist läuft still weiter.'),

        _abschnitt('Stand des Verfahrens'),
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

        _abschnitt('Gericht und Forderung'),
        _text('Mahngericht', _gerichtC,
            hinweis: 'Zentrales Mahngericht des Landes — steht im Kopf des Bescheids.'),
        const SizedBox(height: 10),
        _text('Geschäftszeichen des Gerichts', _zeichenC,
            hinweis: 'Nicht das Aktenzeichen des Inkassobüros.'),
        const SizedBox(height: 10),
        _text('Antragsteller', _antragstellerC,
            hinweis: 'Wer den Bescheid beantragt hat — oft das Büro, nicht der Vermieter.'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _text('Hauptforderung €', _hauptC)),
          const SizedBox(width: 8),
          Expanded(child: _text('Nebenforderung €', _nebenC)),
        ]),
        const SizedBox(height: 10),
        _text('Kosten €', _kostenC),

        _abschnitt('Mahnbescheid'),
        _datum('Erlassen am', _mbAm,
            hinweis: 'Das Datum auf dem Bescheid. Von hier läuft KEINE Frist.'),
        const SizedBox(height: 10),
        _datum('Zugestellt am', _mbZugestellt,
            hinweis: 'Der Tag im gelben Umschlag. Ab hier laufen die zwei Wochen.',
            danach: () => _fristRechnen(_mbZugestellt, _wsFrist)),
        const SizedBox(height: 10),
        _datum('Widerspruchsfrist', _wsFrist,
            hinweis: 'Wird aus der Zustellung gerechnet, lässt sich aber überschreiben.'),
        const SizedBox(height: 10),
        _datum('Widerspruch eingelegt am', _wsAm),
        if (_fristMelder(_wsFrist, _wsAm, 'Widerspruch') != null)
          _fristMelder(_wsFrist, _wsAm, 'Widerspruch')!,

        _abschnitt('Vollstreckungsbescheid'),
        _datum('Erlassen am', _vbAm),
        const SizedBox(height: 10),
        _datum('Zugestellt am', _vbZugestellt,
            hinweis: 'Ab hier laufen zwei Wochen für den Einspruch (§ 700 ZPO).',
            danach: () => _fristRechnen(_vbZugestellt, _esFrist)),
        const SizedBox(height: 10),
        _datum('Einspruchsfrist', _esFrist),
        const SizedBox(height: 10),
        _datum('Einspruch eingelegt am', _esAm),
        if (_fristMelder(_esFrist, _esAm, 'Einspruch') != null)
          _fristMelder(_esFrist, _esAm, 'Einspruch')!,

        _abschnitt('Notizen'),
        _text('Notizen', _notizC, zeilen: 4),

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
          if (_daten != null)
            TextButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Mahnverfahren löschen?'),
                    content: const Text(
                        'Alle Daten und Fristen dieses Mahnverfahrens werden entfernt. '
                        'Der Vorfall selbst bleibt.'),
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
                await widget.apiService.deleteVermieterMahnverfahren(widget.vorfallId);
                if (!mounted) return;
                for (final c in _alle) {
                  c.clear();
                }
                setState(() => _status = 'angekuendigt');
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
