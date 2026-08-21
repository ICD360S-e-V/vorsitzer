import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import '../utils/app_farben.dart';

/// Briefversand über LetterXpress: ein PDF geht rein, ein echter Brief kommt
/// beim Empfänger an. Gedruckt, kuvertiert und frankiert wird bei der
/// A&O Fischer GmbH & Co. KG, zugestellt von der Deutschen Post.
///
/// ⚠️ Die Empfängeranschrift wird NICHT eingegeben. Die LXP-API v3 hat kein
///    Adressfeld — LetterXpress liest die Anschrift aus dem PDF, aus dem
///    Anschriftenfeld nach DIN 5008. Steht sie dort nicht oder verrutscht,
///    geht der Brief an niemanden, und die API meldet dabei keinen Fehler.
///    Deshalb zeigt dieser Bildschirm nach dem Senden die von LetterXpress
///    *erkannte* Adresse groß an: das ist die einzige Gegenprobe, die es gibt,
///    und dafür bleiben 15 Minuten zum Stornieren.
///
/// ⚠️ Deutsche Post selbst kommt hier bewusst nicht vor. Ihre E-POST BUSINESS
///    API kostet 275 € Anschluss und 59 €/Monat, bevor der erste Brief
///    geschrieben ist; die Internetmarke-API frankiert nur und lässt das
///    Drucken und Einwerfen bei uns. Für einen Verein dieser Größe ist der
///    Hybridpost-Weg der einzige, der sich rechnet.
class PostScreen extends StatefulWidget {
  final ApiService apiService;

  const PostScreen({super.key, required this.apiService});

  @override
  State<PostScreen> createState() => _PostScreenState();
}

/// ⚠️ PHP kennt nur einen Array-Typ. `['a'=>1]` kodiert `json_encode` als
/// Objekt, `[]` dagegen als Liste — und `as Map` auf einer Liste liefert nicht
/// null, sondern WIRFT. Genau daran blieb der Speedtest-Bildschirm am
/// 05.08.2026 in der Produktion als graue Fläche hängen.
///
/// Hier trifft es `zugang` und `pdf`: beide sind Objekte, solange sie Felder
/// haben — ein leerer Block käme als Liste an.
Map<String, dynamic>? postAlsMap(dynamic v) {
  if (v is Map) return v.cast<String, dynamic>();
  return null;
}

/// Listen aus PHP: `sendungen` ist leer `[]` und gefüllt eine Liste von
/// Objekten. Alles andere (null, Objekt) ergibt eine leere Liste statt eines
/// Absturzes.
List<Map<String, dynamic>> postListe(dynamic v) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

/// Einschreiben gibt es nur im Inland — LetterXpress lehnt die Kombination ab,
/// und zwar erst beim Senden. Diese Regel steht deshalb sowohl hier als auch
/// im Server (`letterxpress_manage.php`); wer eine ändert, ändert beide.
String? postEinschreibenBereinigen(String? einschreiben, String versandart) {
  if (versandart == 'international') return null;
  return (einschreiben == 'r1' || einschreiben == 'r2') ? einschreiben : null;
}

class _PostScreenState extends State<PostScreen> {
  bool _laedt = true;
  bool _arbeitet = false;

  // Zugang / Konto
  bool _eingerichtet = false;
  bool _verbunden = false;
  String _benutzername = '';
  String _betriebsart = 'test';
  double? _guthaben;
  String _kontoFehler = '';
  int _stornoMinuten = 15;

  final _benutzerCtrl = TextEditingController();
  final _apikeyCtrl = TextEditingController();
  bool _zugangOffen = false;

  // Ausgewählte Datei
  Uint8List? _pdfBytes;
  String _pdfName = '';
  int? _seiten;
  String _pdfFormat = '';
  String _pdfFehler = '';
  double? _preis;
  String _preisFehler = '';

  // Versandoptionen
  String _farbe = '1';
  bool _duplex = false;
  String _versandart = 'auto';
  String? _einschreiben;
  final _notizCtrl = TextEditingController();

  List<Map<String, dynamic>> _sendungen = [];

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    _benutzerCtrl.dispose();
    _apikeyCtrl.dispose();
    _notizCtrl.dispose();
    super.dispose();
  }

  bool get _istLive => _betriebsart == 'live';

  // ────────────────────────── Laden ──────────────────────────

  Future<void> _laden() async {
    setState(() => _laedt = true);
    final a = await widget.apiService.letterxpressAction({'action': 'get_all'});
    if (!mounted) return;

    if (a['success'] == true) {
      final z = postAlsMap(a['zugang']) ?? const {};
      setState(() {
        _eingerichtet = z['eingerichtet'] == true;
        _benutzername = (z['benutzername'] ?? '').toString();
        _betriebsart = (z['betriebsart'] ?? 'test').toString();
        _verbunden = a['verbunden'] == true;
        _guthaben = (a['guthaben'] as num?)?.toDouble();
        _kontoFehler = (a['fehler'] ?? '').toString();
        _stornoMinuten = (a['storno_min'] as num?)?.toInt() ?? 15;
        _sendungen = postListe(a['sendungen']);
        _benutzerCtrl.text = _benutzername;
        _zugangOffen = !_eingerichtet;
        _laedt = false;
      });
    } else {
      setState(() {
        _laedt = false;
        _kontoFehler = (a['message'] ?? 'Laden fehlgeschlagen').toString();
      });
    }
  }

  // ────────────────────────── Zugang ──────────────────────────

  Future<void> _zugangSpeichern() async {
    setState(() => _arbeitet = true);
    final a = await widget.apiService.letterxpressAction({
      'action': 'zugang_speichern',
      'benutzername': _benutzerCtrl.text.trim(),
      // Ein leeres Feld heißt „nicht ändern" — der Server wirft den
      // hinterlegten Schlüssel dann nicht weg.
      'apikey': _apikeyCtrl.text.trim(),
      'betriebsart': _betriebsart,
    });
    if (!mounted) return;
    setState(() => _arbeitet = false);

    if (a['success'] == true) {
      _apikeyCtrl.clear();
      _melde(a['verbunden'] == true
          ? 'Zugang gespeichert und geprüft.'
          : 'Gespeichert, aber LetterXpress meldet: ${a['fehler']}');
      await _laden();
    } else {
      _melde('Nicht gespeichert: ${a['message']}', fehler: true);
    }
  }

  // ────────────────────────── Datei ──────────────────────────

  Future<void> _dateiWaehlen() async {
    final res = await FilePickerHelper.pickFiles(
      dialogTitle: 'PDF für den Briefversand',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      _melde('Datei konnte nicht gelesen werden.', fehler: true);
      return;
    }

    setState(() {
      _pdfBytes = bytes;
      _pdfName = f.name;
      _seiten = null;
      _pdfFormat = '';
      _pdfFehler = '';
      _preis = null;
      _preisFehler = '';
    });
    await _pruefen();
  }

  /// Format prüfen, Seiten zählen, Preis holen — alles auf dem Server, weil
  /// nur er das PDF zerlegen kann und weil eine hier gezählte Seitenzahl die
  /// Preisbestätigung beim Senden wertlos machen würde.
  Future<void> _pruefen() async {
    final bytes = _pdfBytes;
    if (bytes == null) return;

    setState(() => _arbeitet = true);
    final a = await widget.apiService.letterxpressAction({
      'action': 'pruefen',
      'base64_pdf': base64Encode(bytes),
      'farbe': _farbe,
      'duplex': _duplex,
      'versandart': _versandart,
      if (_einschreiben != null) 'einschreiben': _einschreiben,
    });
    if (!mounted) return;

    final pdf = postAlsMap(a['pdf']) ?? const {};
    setState(() {
      _arbeitet = false;
      _seiten = (pdf['seiten'] as num?)?.toInt();
      _pdfFormat = (pdf['format'] ?? '').toString();
      _pdfFehler = a['success'] == true ? '' : (a['message'] ?? '').toString();
      _preis = (a['preis'] as num?)?.toDouble();
      _preisFehler = (a['preis_fehler'] ?? '').toString();
    });
  }

  // ────────────────────────── Senden ──────────────────────────

  Future<void> _senden() async {
    final bytes = _pdfBytes;
    if (bytes == null || _pdfFehler.isNotEmpty) return;

    if (!await _versandBestaetigen()) return;

    setState(() => _arbeitet = true);
    final a = await widget.apiService.letterxpressAction({
      'action': 'senden',
      'base64_pdf': base64Encode(bytes),
      'dateiname': _pdfName,
      'farbe': _farbe,
      'duplex': _duplex,
      'versandart': _versandart,
      if (_einschreiben != null) 'einschreiben': _einschreiben,
      if (_notizCtrl.text.trim().isNotEmpty) 'notiz': _notizCtrl.text.trim(),
      // Nur im Livemodus verlangt der Server beides; im Test schadet es nicht.
      'live_bestaetigt': true,
      if (_preis != null) 'preis_bestaetigt': _preis,
    });
    if (!mounted) return;
    setState(() => _arbeitet = false);

    if (a['success'] == true) {
      await _erfolgZeigen(a);
      setState(() {
        _pdfBytes = null;
        _pdfName = '';
        _seiten = null;
        _preis = null;
        _notizCtrl.clear();
      });
      await _laden();
      return;
    }

    // Der Server hat den Preis neu gerechnet und er weicht ab — die Zahl, die
    // hier stand, war nicht mehr die Zahl, die gezahlt worden wäre.
    if (a['preis_neu'] != null) {
      setState(() => _preis = (a['preis_neu'] as num?)?.toDouble());
      _melde('Der Preis hat sich geändert — bitte erneut bestätigen.', fehler: true);
      return;
    }
    final d = postAlsMap(a['dublette']);
    if (d != null) {
      _melde('Diese Datei wurde vor Kurzem schon scharf verschickt '
          '(Auftrag ${d['auftrag_id']}). Nichts gesendet.', fehler: true);
      return;
    }
    _melde('Nicht gesendet: ${a['message']}', fehler: true);
  }

  Future<bool> _versandBestaetigen() async {
    final preisText = _preis != null
        ? '${_preis!.toStringAsFixed(2)} €'
        : 'unbekannt';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_istLive ? 'Brief wirklich verschicken?' : 'Testauftrag übertragen?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_istLive)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: F.h(Colors.red, 50),
                  border: Border.all(color: F.h(Colors.red, 300)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Scharfer Versand. Der Brief wird gedruckt und zugestellt. '
                  'Stornieren ist nur noch $_stornoMinuten Minuten lang möglich.',
                  style: TextStyle(color: F.h(Colors.red, 900), fontWeight: FontWeight.w600),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: F.h(Colors.blue, 50),
                  border: Border.all(color: F.h(Colors.blue, 200)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Testmodus: der Auftrag landet in der Postbox bei LetterXpress, '
                  'geht nicht in Verarbeitung und löscht sich nach 7 Tagen.',
                ),
              ),
            _zeile('Datei', _pdfName),
            _zeile('Seiten', '${_seiten ?? "?"}'),
            _zeile('Druck', '${_farbe == "4" ? "Farbe" : "Schwarz/Weiß"}, '
                '${_duplex ? "beidseitig" : "einseitig"}'),
            if (_einschreiben != null)
              _zeile('Einschreiben', _einschreiben == 'r1' ? 'Einwurf' : 'Übergabe'),
            _zeile('Preis', preisText),
            const SizedBox(height: 12),
            const Text(
              '⚠️ Die Anschrift liest LetterXpress aus dem PDF. Nach dem Senden '
              'wird die erkannte Adresse angezeigt — bitte prüfen.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: _istLive
                ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_istLive ? 'Verschicken' : 'In die Postbox'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _erfolgZeigen(Map<String, dynamic> a) async {
    final adresse = (a['empfaenger'] ?? '').toString();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Übertragen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _zeile('Auftrag', '${a['auftrag_id'] ?? "-"}'),
            _zeile('Status', '${a['status'] ?? "-"}'),
            _zeile('Seiten', '${a['seiten'] ?? "-"}'),
            if (a['preis'] != null)
              _zeile('Preis', '${(a['preis'] as num).toDouble().toStringAsFixed(2)} €'),
            const SizedBox(height: 12),
            const Text('Von LetterXpress im PDF erkannte Anschrift:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: adresse.isEmpty ? F.h(Colors.red, 50) : F.h(Colors.green, 50),
                border: Border.all(
                    color: adresse.isEmpty ? F.h(Colors.red, 300) : F.h(Colors.green, 300)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                adresse.isEmpty
                    ? 'Keine Anschrift erkannt! Der Brief kann unzustellbar sein — '
                        'bitte sofort stornieren und das PDF prüfen.'
                    : adresse,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: adresse.isEmpty ? F.h(Colors.red, 900) : F.h(Colors.green, 900),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // ⚠️ Ein Archivproblem ändert NICHTS am Versand — der Brief ist
            // unterwegs. Es hier trotzdem zu sagen ist wichtig: sonst sucht
            // später jemand einen Nachweis, den es nie gab.
            //
            // ⚠️ Der Fehlertext hat Vorrang vor `archiviert`. Es gibt den Fall
            // "abgelegt, aber der Webnutzer kommt nicht heran" — da ist
            // `archiviert` wahr UND etwas im Argen. Wer nur auf das Flag
            // schaut, zeigt eine grüne Zeile über einem unlesbaren Archiv.
            if ((a['archiv_fehler'] ?? '').toString().isNotEmpty)
              Text(
                'Der Brief ist verschickt, aber mit dem Archiv stimmt etwas '
                'nicht: ${a['archiv_fehler']}',
                style: TextStyle(fontSize: 12, color: F.h(Colors.red, 900)),
              )
            else if (a['archiviert'] == true)
              const Text('Der Brief liegt verschlüsselt in unserem Archiv.',
                  style: TextStyle(fontSize: 12))
            else
              Text(
                'ACHTUNG: Der Brief ist verschickt, konnte aber NICHT archiviert '
                'werden. Es gibt bei uns keinen Nachweis, was genau versendet wurde.',
                style: TextStyle(fontSize: 12, color: F.h(Colors.red, 900)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
        ],
      ),
    );
  }

  /// Holt den archivierten Brief zurück und legt ihn dort ab, wo der Mensch
  /// ihn wiederfindet.
  ///
  /// Der Weg führt zwingend durch den Server: die Datei liegt verschlüsselt
  /// und außerhalb des Webroots, nginx könnte sie gar nicht ausliefern.
  Future<void> _dokumentHolen(Map<String, dynamic> s) async {
    setState(() => _arbeitet = true);
    final a = await widget.apiService.letterxpressAction({
      'action': 'dokument',
      'protokoll_id': s['id'],
    });
    if (!mounted) return;
    setState(() => _arbeitet = false);

    if (a['success'] != true) {
      _melde('Brief nicht abrufbar: ${a['message']}', fehler: true);
      return;
    }

    final b64 = (a['base64_pdf'] ?? '').toString();
    if (b64.isEmpty) {
      _melde('Der Server hat keine Datei geliefert.', fehler: true);
      return;
    }

    final ziel = await FilePickerHelper.saveBytes(
      bytes: base64Decode(b64),
      fileName: (a['dateiname'] ?? 'Brief.pdf').toString(),
      dialogTitle: 'Verschickten Brief speichern',
    );
    if (!mounted) return;
    _melde(ziel == null ? 'Nicht gespeichert.' : 'Gespeichert: $ziel');
  }

  Future<void> _dokumentLoeschen(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Brief aus dem Archiv löschen?'),
        content: const Text(
          'Die verschickte PDF wird unwiderruflich gelöscht. Der Eintrag im '
          'Versandprotokoll bleibt bestehen — nur der Inhalt ist dann weg.\n\n'
          'Der Brief selbst ist damit nicht zurückgeholt; er ist bereits unterwegs.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Behalten')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _arbeitet = true);
    final a = await widget.apiService.letterxpressAction({
      'action': 'dokument_loeschen',
      'protokoll_id': s['id'],
    });
    if (!mounted) return;
    setState(() => _arbeitet = false);
    _melde(a['success'] == true ? 'Aus dem Archiv gelöscht.' : 'Nicht gelöscht: ${a['message']}',
        fehler: a['success'] != true);
    if (a['success'] == true) await _laden();
  }

  Future<void> _stornieren(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auftrag stornieren?'),
        content: Text('Auftrag ${s['auftrag_id']} wird bei LetterXpress gelöscht. '
            'Das geht nur innerhalb von $_stornoMinuten Minuten nach der Übertragung.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nein')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stornieren')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _arbeitet = true);
    final a = await widget.apiService.letterxpressAction({
      'action': 'stornieren',
      'auftrag_id': s['auftrag_id'],
    });
    if (!mounted) return;
    setState(() => _arbeitet = false);
    _melde(a['success'] == true ? 'Storniert.' : 'Nicht storniert: ${a['message']}',
        fehler: a['success'] != true);
    if (a['success'] == true) await _laden();
  }

  // ────────────────────────── Aufbau ──────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Briefversand'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Neu laden',
            onPressed: _laedt ? null : _laden,
          ),
        ],
      ),
      body: _laedt
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _kontoBand(),
                    const SizedBox(height: 16),
                    _zugangKarte(),
                    const SizedBox(height: 16),
                    if (_eingerichtet) ...[
                      _briefKarte(),
                      const SizedBox(height: 16),
                    ],
                    _verlaufKarte(),
                  ],
                ),
                if (_arbeitet)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x33000000),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _kontoBand() {
    // ⚠️ Die Fehlermeldung hat Vorrang vor „nicht eingerichtet".
    //
    // Vorher gewann `!_eingerichtet`, und damit wurde ein Serverfehler — etwa
    // „Zugangsdaten nicht entschluesselbar", der auf einen falschen
    // ENC_MASTER_KEY oder einen manipulierten Datensatz hindeutet — als
    // harmloses „noch nichts hinterlegt" angezeigt. Wer das liest, tippt die
    // Zugangsdaten neu ein und überschreibt genau den Zustand, der die
    // Ursache verraten hätte.
    final stoerung = _kontoFehler.isNotEmpty;

    final farbe = stoerung
        ? Colors.orange
        : (!_eingerichtet
            ? Colors.grey
            : (_verbunden ? (_istLive ? Colors.red : Colors.blue) : Colors.orange));
    final text = stoerung
        ? (_eingerichtet ? 'Nicht verbunden: $_kontoFehler' : _kontoFehler)
        : (!_eingerichtet
            ? 'Noch kein LetterXpress-Zugang hinterlegt'
            : (_istLive
                ? 'SCHARF — Briefe gehen wirklich raus'
                : 'Testmodus — Aufträge landen nur in der Postbox'));

    return Card(
      color: farbe.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              stoerung
                  ? Icons.error_outline
                  : (!_eingerichtet
                      ? Icons.markunread_mailbox_outlined
                      : (_istLive ? Icons.warning_amber : Icons.science_outlined)),
              color: farbe,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text,
                      style: TextStyle(fontWeight: FontWeight.bold, color: F.h(farbe, 800))),
                  if (_guthaben != null)
                    Text('Guthaben: ${_guthaben!.toStringAsFixed(2)} €',
                        style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zugangKarte() {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: _zugangOffen,
        leading: const Icon(Icons.key),
        title: const Text('Zugang & Betriebsart'),
        subtitle: Text(_eingerichtet
            ? '$_benutzername · ${_istLive ? "live" : "test"}'
            : 'noch nicht eingerichtet'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextField(
            controller: _benutzerCtrl,
            decoration: const InputDecoration(
              labelText: 'Benutzername',
              helperText: 'Aus dem LXP-Kundenbereich: Mein Konto ▸ Zugangsdaten ▸ LXP API',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _apikeyCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'API-Key',
              helperText: _eingerichtet
                  ? 'Hinterlegt. Leer lassen heißt: unverändert übernehmen.'
                  : 'Wird verschlüsselt gespeichert und nie wieder ausgegeben.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'test', label: Text('Test'), icon: Icon(Icons.science_outlined)),
              ButtonSegment(value: 'live', label: Text('Live'), icon: Icon(Icons.local_post_office)),
            ],
            selected: {_betriebsart},
            onSelectionChanged: (s) => setState(() => _betriebsart = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            'Im Testmodus wird nichts gedruckt und nichts berechnet. Aufträge liegen '
            '7 Tage in der Postbox bei LetterXpress und löschen sich dann selbst.',
            style: TextStyle(fontSize: 12, color: F.hd(Colors.black54, F.textSchwach)),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _arbeitet ? null : _zugangSpeichern,
              icon: const Icon(Icons.save),
              label: const Text('Speichern & prüfen'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _briefKarte() {
    final bereit = _pdfBytes != null && _pdfFehler.isEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mail_outline),
                const SizedBox(width: 8),
                Text('Neuer Brief',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _arbeitet ? null : _dateiWaehlen,
              icon: const Icon(Icons.attach_file),
              label: Text(_pdfName.isEmpty ? 'PDF auswählen' : _pdfName),
            ),
            if (_pdfBytes != null) ...[
              const SizedBox(height: 8),
              if (_pdfFehler.isNotEmpty)
                _hinweis(_pdfFehler, Colors.red)
              else
                _hinweis(
                  '$_seiten Seite${_seiten == 1 ? "" : "n"} · $_pdfFormat · A4 hoch, in Ordnung',
                  Colors.green,
                ),
            ],
            const Divider(height: 28),
            // ⚠️ Wrap statt Row: auf dem Pixel stehen sonst drei Auswahlfelder
            // nebeneinander und werden unlesbar gequetscht.
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _auswahl<String>(
                  'Druck',
                  _farbe,
                  const {'1': 'Schwarz/Weiß', '4': 'Farbe'},
                  (v) => setState(() => _farbe = v),
                ),
                _auswahl<String>(
                  'Versand',
                  _versandart,
                  const {
                    'auto': 'automatisch',
                    'national': 'Inland',
                    'international': 'Ausland',
                  },
                  (v) => setState(() {
                    _versandart = v;
                    _einschreiben = postEinschreibenBereinigen(_einschreiben, v);
                  }),
                ),
                _auswahl<String>(
                  'Einschreiben',
                  _einschreiben ?? '-',
                  _versandart == 'international'
                      ? const {'-': 'nur im Inland möglich'}
                      : const {'-': 'ohne', 'r1': 'Einwurf', 'r2': 'Übergabe'},
                  (v) => setState(() => _einschreiben = v == '-' ? null : v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _duplex,
              onChanged: (v) => setState(() => _duplex = v),
              title: const Text('Beidseitig drucken'),
              subtitle: const Text('Spart Blätter und damit Porto ab mehreren Seiten'),
            ),
            TextField(
              controller: _notizCtrl,
              maxLength: 255,
              decoration: const InputDecoration(
                labelText: 'Notiz (nur für uns)',
                helperText: 'Erscheint nicht im Brief, nur in der Auftragsliste',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _preis != null
                      ? Text('Preis: ${_preis!.toStringAsFixed(2)} €',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold))
                      : Text(
                          _preisFehler.isEmpty
                              ? 'Preis wird nach Dateiauswahl ermittelt'
                              : 'Preis nicht ermittelbar: $_preisFehler',
                          style: TextStyle(color: F.hd(Colors.black54, F.textSchwach))),
                ),
                if (bereit)
                  TextButton.icon(
                    onPressed: _arbeitet ? null : _pruefen,
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('Neu berechnen'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: _istLive
                    ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700)
                    : null,
                onPressed: (!bereit || _arbeitet) ? null : _senden,
                icon: Icon(_istLive ? Icons.local_post_office : Icons.science_outlined),
                label: Text(_istLive ? 'Scharf verschicken' : 'Testauftrag übertragen'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verlaufKarte() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history),
                const SizedBox(width: 8),
                Text('Versandprotokoll',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${_sendungen.length}',
                    style: TextStyle(color: F.hd(Colors.black54, F.textSchwach))),
              ],
            ),
            const SizedBox(height: 8),
            if (_sendungen.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Noch nichts verschickt.',
                    style: TextStyle(color: F.hd(Colors.black54, F.textSchwach))),
              )
            else
              ..._sendungen.map(_sendungZeile),
          ],
        ),
      ),
    );
  }

  Widget _sendungZeile(Map<String, dynamic> s) {
    final live = s['betriebsart'] == 'live';
    final status = (s['status'] ?? '').toString();
    final empf = (s['empfaenger'] ?? '').toString();
    final preis = (s['preis'] as num?)?.toDouble();

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        status == 'fehler'
            ? Icons.error_outline
            : status == 'canceled'
                ? Icons.cancel_outlined
                : (live ? Icons.local_post_office : Icons.science_outlined),
        color: status == 'fehler'
            ? Colors.red
            : status == 'canceled'
                ? F.h(Colors.grey, 500)
                : (live ? F.h(Colors.red, 700) : Colors.blue),
      ),
      title: Text(
        empf.isNotEmpty ? empf : ((s['dateiname'] ?? 'ohne Namen').toString()),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text([
        (s['erstellt_am'] ?? '').toString(),
        live ? 'live' : 'test',
        status,
        if (s['seiten'] != null) '${s['seiten']} S.',
        if (preis != null) '${preis.toStringAsFixed(2)} €',
        if (s['einschreiben'] != null)
          s['einschreiben'] == 'r1' ? 'Einschreiben Einwurf' : 'Einschreiben',
        if ((s['fehler_text'] ?? '').toString().isNotEmpty) s['fehler_text'].toString(),
        // Ohne diesen Hinweis sähe eine Zeile ohne Archiv genauso aus wie eine
        // mit — und man merkte erst beim Suchen, dass der Brief weg ist.
        if (s['hat_dokument'] == true) 'Brief archiviert' else 'ohne Archiv',
      ].join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Storno bleibt ein eigener Knopf: es ist die einzige zeitkritische
          // Handlung hier, und in einem Menü zu versteckt.
          if (s['stornierbar'] == true)
            TextButton(
              onPressed: _arbeitet ? null : () => _stornieren(s),
              child: const Text('Storno'),
            ),
          if (s['hat_dokument'] == true)
            PopupMenuButton<String>(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Verschickter Brief',
              enabled: !_arbeitet,
              onSelected: (w) =>
                  w == 'holen' ? _dokumentHolen(s) : _dokumentLoeschen(s),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'holen', child: Text('Brief speichern')),
                PopupMenuItem(value: 'loeschen', child: Text('Aus dem Archiv löschen')),
              ],
            ),
        ],
      ),
      isThreeLine: true,
    );
  }

  // ────────────────────────── Kleinteile ──────────────────────────

  Widget _auswahl<T>(String titel, T wert, Map<T, String> optionen,
      ValueChanged<T> beiWahl) {
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<T>(
        initialValue: wert,
        isExpanded: true,
        decoration: InputDecoration(labelText: titel, isDense: true),
        items: optionen.entries
            .map((e) => DropdownMenuItem<T>(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null) beiWahl(v);
        },
      ),
    );
  }

  Widget _hinweis(String text, MaterialColor farbe) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: F.h(farbe, 50),
        border: Border.all(color: F.h(farbe, 200)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(color: F.h(farbe, 900))),
    );
  }

  Widget _zeile(String links, String rechts) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(links, style: TextStyle(color: F.hd(Colors.black54, F.textSchwach))),
          ),
          Expanded(child: Text(rechts)),
        ],
      ),
    );
  }

  void _melde(String text, {bool fehler = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler ? Colors.red.shade700 : null,
      duration: Duration(seconds: fehler ? 6 : 3),
    ));
  }
}
