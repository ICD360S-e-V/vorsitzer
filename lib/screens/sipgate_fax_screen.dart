import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'sipgate_kontakte_screen.dart';

/// Fax über sipgate.
///
/// ⚠️ WARUM DAS NICHT AM VOIP-TELEFON HÄNGT
/// Die App telefoniert per SIP-over-WebSocket gegen sip.sipgate.de. Fax kann
/// diesen Weg nicht nehmen — ein Fax ist ein Modem, kein Gespräch, und ein
/// WebRTC-Stack hat weder T.38 noch einen G.711-Passthrough. Fax läuft
/// ausschließlich über die REST-API und braucht deshalb ein eigenes, zweites
/// Zugangsmittel: einen Personal Access Token.
///
/// ⚠️ WARUM DER VERLAUF UNSERER IST UND NICHT DER VON SIPGATE
/// sipgate löscht seinen Verlauf nach 30 Tagen (`historyLifeTime:
/// THIRTY_DAYS`, am Konto nachgesehen). Jedes gesendete und jedes empfangene
/// Dokument liegt deshalb verschlüsselt auf unserem Server. Was dieser
/// Bildschirm zeigt, überlebt die 30 Tage; was bei sipgate steht, nicht.
class SipgateFaxScreen extends StatefulWidget {
  const SipgateFaxScreen({super.key});

  @override
  State<SipgateFaxScreen> createState() => _SipgateFaxScreenState();
}

class _SipgateFaxScreenState extends State<SipgateFaxScreen> {
  final ApiService _api = ApiService();

  final TextEditingController _empfaenger = TextEditingController();
  final TextEditingController _name = TextEditingController();

  bool _lade = true;
  bool _sendet = false;
  Map<String, dynamic> _zugang = const {};
  List<Map<String, dynamic>> _faxe = const [];

  /// Das gewählte Dokument. Bewusst als Bytes im Speicher und nicht als Pfad:
  /// auf Android liefert die Dateiauswahl einen content://-Verweis, der nach
  /// dem Schließen des Dialogs nicht mehr lesbar sein muss.
  List<int>? _dokument;
  String _dokumentName = '';

  @override
  void initState() {
    super.initState();
    _laden(live: true);
  }

  @override
  void dispose() {
    _empfaenger.dispose();
    _name.dispose();
    super.dispose();
  }

  void _melde(String text, {bool fehler = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler ? Colors.red.shade700 : null,
      duration: Duration(seconds: fehler ? 6 : 3),
    ));
  }

  Future<void> _laden({bool live = false}) async {
    setState(() => _lade = true);
    // ⚠️ `live` fragt sipgate wirklich. Ohne den Schalter sagt die Antwort nur,
    // was in unserer Tabelle steht — und ein zurückgezogener Token sieht dort
    // genauso aus wie ein gültiger.
    final z = await _api.sipgateFaxAction({'action': 'status', if (live) 'live': true});
    final l = await _api.sipgateFaxAction({'action': 'list'});
    if (!mounted) return;
    setState(() {
      _zugang = z['success'] == true ? Map<String, dynamic>.from(z) : const {};
      _faxe = l['success'] == true
          ? List<Map<String, dynamic>>.from(
              (l['faxe'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e)))
          : const [];
      _lade = false;
    });
  }

  // ---------------------------------------------------------------------------
  //  Zugang
  // ---------------------------------------------------------------------------

  Future<void> _tokenDialog() async {
    final id = TextEditingController(text: (_zugang['token_id'] ?? '').toString());
    final tok = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('sipgate-Zugang für Fax'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'Fax braucht ein eigenes Zugangsmittel — die SIP-Zugangsdaten des '
              'VoIP-Telefons reichen dafür nicht.\n\n'
              'In app.sipgate.com unter „Personal Access Token" einen Token anlegen '
              'mit den Rechten:\n'
              '  • sessions:fax:write\n'
              '  • history:read\n'
              '  • faxlines:read',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: id,
              decoration: const InputDecoration(
                labelText: 'Token-ID', hintText: 'token-XXXXXX', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tok,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Token',
                // sipgate zeigt den Token genau einmal an. Wer ihn nicht
                // kopiert hat, legt einen neuen an — das gehört hier hin,
                // bevor jemand vergeblich sucht.
                helperText: 'Wird von sipgate nur einmal angezeigt',
                border: OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Prüfen & speichern')),
        ],
      ),
    );
    if (ok != true) return;

    // ⚠️ Der Server prüft live gegen sipgate, BEVOR er speichert. Ein
    // vertippter Token ließe sich sonst speichern, der Bildschirm zeigte
    // „eingerichtet", und der Fehler käme erst beim ersten Fax — also genau
    // dann, wenn es eilt.
    final r = await _api.sipgateFaxAction({
      'action': 'token_save',
      'token_id': id.text.trim(),
      'token': tok.text.trim(),
    });
    _melde(r['message']?.toString() ?? (r['success'] == true ? 'Gespeichert' : 'Fehlgeschlagen'),
        fehler: r['success'] != true);
    if (r['success'] == true) await _laden(live: true);
  }

  Future<void> _kennungSetzen() async {
    final r = await _api.sipgateFaxAction({
      'action': 'absenderkennung_setzen',
      'wert': (_zugang['absender'] ?? '').toString(),
    });
    _melde(r['message']?.toString() ?? '', fehler: r['success'] != true);
    if (r['success'] == true) await _laden(live: true);
  }

  // ---------------------------------------------------------------------------
  //  Senden
  // ---------------------------------------------------------------------------

  Future<void> _dokumentWaehlen() async {
    final res = await FilePickerHelper.pickFiles(
      dialogTitle: 'PDF zum Faxen wählen',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    final datei = res?.files.firstOrNull;
    if (datei == null) return;

    final List<int>? gelesen = datei.bytes ??
        (datei.path != null ? await File(datei.path!).readAsBytes() : null);
    if (gelesen == null) { _melde('Datei nicht lesbar', fehler: true); return; }

    // ⚠️ Hier prüfen, nicht erst auf dem Server: sipgate nimmt ausschließlich
    // PDF, und die Endung sagt nichts über den Inhalt. Ein umbenanntes Bild
    // käme erst zurück, nachdem es vollständig hochgeladen wurde — bei einem
    // mehrseitigen Dokument über die Mobilfunkleitung ist das eine Minute
    // Wartezeit für eine Auskunft, die hier sofort zu haben ist.
    const kopf = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-
    final istPdf = gelesen.length > kopf.length &&
        List.generate(kopf.length, (i) => gelesen[i] == kopf[i]).every((b) => b);
    if (!istPdf) { _melde('Das ist kein PDF. sipgate faxt nur PDF.', fehler: true); return; }

    setState(() {
      _dokument = gelesen;
      _dokumentName = datei.name;
    });
  }

  Future<void> _senden() async {
    if (_dokument == null) { _melde('Kein Dokument gewählt', fehler: true); return; }
    if (_empfaenger.text.trim().isEmpty) { _melde('Keine Empfängernummer', fehler: true); return; }

    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Fax jetzt senden?'),
        content: Text(
          'An: ${_empfaenger.text.trim()}\n'
          'Dokument: $_dokumentName\n\n'
          'Ein gesendetes Fax lässt sich nicht zurückholen.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Senden')),
        ],
      ),
    );
    if (bestaetigt != true) return;

    setState(() => _sendet = true);
    final r = await _api.sipgateFaxAction({
      'action': 'senden',
      'empfaenger': _empfaenger.text.trim(),
      'empfaenger_name': _name.text.trim(),
      'dateiname': _dokumentName,
      'inhalt_b64': base64Encode(_dokument!),
      // Ein mehrseitiges PDF geht zweimal über die Leitung: zu uns und von
      // uns zu sipgate. 90 s statt der üblichen 25.
    }, timeout: const Duration(seconds: 90));
    if (!mounted) return;
    setState(() => _sendet = false);

    _melde(r['message']?.toString() ?? '', fehler: r['success'] != true);
    if (r['success'] == true) {
      setState(() { _dokument = null; _dokumentName = ''; });
      _empfaenger.clear();
      _name.clear();
      await _laden();
    }
  }

  // ---------------------------------------------------------------------------
  //  Verlauf
  // ---------------------------------------------------------------------------

  /// Holt das Dokument vom Server. Gibt `null` zurück und meldet selbst,
  /// wenn es nicht geht.
  ///
  /// ⚠️ Die Bytes bleiben im Speicher und werden NICHT auf die Platte
  /// geschrieben. Auf dem Server liegt jedes Fax verschlüsselt; es hier
  /// nebenbei als Klartext-PDF in den Temp-Ordner zu legen, würde diesen
  /// Schutz aufheben — Temp-Dateien überleben die Sitzung, landen in Backups
  /// und sind auf einem geteilten Rechner für jeden lesbar. Ein Faxverlauf
  /// enthält Widersprüche, Atteste und Behördenpost.
  Future<Uint8List?> _dokumentHolen(Map<String, dynamic> f) async {
    final r = await _api.sipgateFaxAction({'action': 'dokument', 'id': f['id']},
        timeout: const Duration(seconds: 60));
    if (r['success'] != true) {
      _melde(r['message']?.toString() ?? 'Dokument nicht abrufbar', fehler: true);
      return null;
    }
    try {
      return base64Decode(r['inhalt_b64'].toString());
    } catch (e) {
      _melde('Dokument ist beschädigt angekommen: $e', fehler: true);
      return null;
    }
  }

  String _dateinameVon(Map<String, dynamic> f) {
    final n = (f['dateiname'] ?? '').toString().trim();
    return n.isEmpty ? 'Fax-${f['id']}.pdf' : n;
  }

  /// Das Auge: Fax ansehen, ohne dass es je die Platte berührt.
  Future<void> _ansehen(Map<String, dynamic> f) async {
    final bytes = await _dokumentHolen(f);
    if (bytes == null || !mounted) return;
    final name = _dateinameVon(f);

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 850,
          height: 750,
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.teal.shade800,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(children: [
                const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                ),
                ElevatedButton.icon(
                  onPressed: () => _herunterladen(f, vorhandene: bytes),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Download'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: Colors.teal.shade800,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                ),
                const SizedBox(width: 6),
                ElevatedButton.icon(
                  onPressed: () => Printing.layoutPdf(onLayout: (_) async => bytes, name: name),
                  icon: const Icon(Icons.print, size: 16),
                  label: const Text('Drucken'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: Colors.teal.shade800,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            Expanded(
              child: PdfPreview(
                // ⚠️ Aus dem Speicher, nicht von einem Pfad — das ist der
                // ganze Punkt dieses Dialogs.
                build: (_) async => bytes,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                // Eigene Knöpfe oben; die eingebauten würden zusätzlich
                // Zwischendateien anlegen.
                allowPrinting: false,
                allowSharing: false,
                pdfFileName: name,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Herunterladen — der Mensch bestimmt, wohin.
  ///
  /// ⚠️ Bewusst mit Auswahldialog statt still in den Temp-Ordner: das Fax
  /// verlässt hier den verschlüsselten Bereich, und das soll eine Entscheidung
  /// sein, keine Nebenwirkung. `vorhandene` spart den zweiten Abruf, wenn die
  /// Bytes aus der Vorschau schon da sind.
  Future<void> _herunterladen(Map<String, dynamic> f, {Uint8List? vorhandene}) async {
    final bytes = vorhandene ?? await _dokumentHolen(f);
    if (bytes == null) return;
    try {
      final ziel = await FilePickerHelper.saveBytes(
        bytes: bytes,
        fileName: _dateinameVon(f),
        dialogTitle: 'Fax speichern',
      );
      if (ziel != null) _melde('Gespeichert: $ziel');
    } catch (e) {
      _melde('Speichern fehlgeschlagen: $e', fehler: true);
    }
  }

  /// Drucken, ebenfalls ohne Zwischendatei.
  Future<void> _drucken(Map<String, dynamic> f) async {
    final bytes = await _dokumentHolen(f);
    if (bytes == null) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: _dateinameVon(f));
  }

  Future<void> _nachsehen(Map<String, dynamic> f) async {
    final r = await _api.sipgateFaxAction({'action': 'stand', 'id': f['id']});
    _melde(r['success'] == true
        ? 'Stand: ${_statusText(r['status']?.toString() ?? '', r['fax_status_type']?.toString())}'
        : (r['message']?.toString() ?? 'Stand nicht abfragbar'), fehler: r['success'] != true);
    await _laden();
  }

  Future<void> _loeschen(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Fax löschen?'),
        // ⚠️ Der Hinweis ist keine Floskel: bei sipgate ist das Dokument nach
        // 30 Tagen ohnehin weg, unsere Kopie ist die einzige, die bleibt.
        content: const Text('Das Dokument wird auch von unserem Server gelöscht. '
            'sipgate hält seinen Verlauf nur 30 Tage — danach gibt es keine zweite Kopie.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.sipgateFaxAction({'action': 'loeschen', 'id': f['id']});
    _melde(r['message']?.toString() ?? '', fehler: r['success'] != true);
    await _laden();
  }

  // ---------------------------------------------------------------------------
  //  Darstellung
  // ---------------------------------------------------------------------------

  /// ⚠️ „gesendet" kommt hier bewusst nicht vor. sipgate bestätigt beim
  /// Absenden nur die Warteschlange; ob das Faxgerät der Gegenseite
  /// abgenommen hat, weiß erst die Nachverfolgung. Ein Wort, das jemand als
  /// Zustellnachweis lesen könnte, darf erst stehen, wenn es einer ist.
  String _statusText(String status, [String? roh]) {
    if (roh == 'UNBEKANNT') return 'Ausgang unbekannt';
    if (roh == 'VERFALLEN') return 'Bei sipgate nicht mehr abfragbar';
    return switch (status) {
      'zugestellt'     => 'Zugestellt',
      'fehlgeschlagen' => 'Fehlgeschlagen',
      'in_zustellung'  => 'In Zustellung …',
      'vorbereitet'    => 'Vorbereitet',
      'storniert'      => 'Storniert',
      'empfangen'      => 'Empfangen',
      _                => status,
    };
  }

  (IconData, Color) _statusZeichen(String status, [String? roh]) {
    if (roh == 'UNBEKANNT' || roh == 'VERFALLEN') return (Icons.help_outline, Colors.orange);
    return switch (status) {
      'zugestellt'     => (Icons.check_circle, Colors.green),
      'fehlgeschlagen' => (Icons.error, Colors.red),
      'in_zustellung'  => (Icons.schedule, Colors.amber),
      'empfangen'      => (Icons.call_received, Colors.blue),
      _                => (Icons.description_outlined, Colors.grey),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fax'),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_received),
            tooltip: 'Eingang von sipgate holen',
            onPressed: () async {
              final r = await _api.sipgateFaxAction({'action': 'eingang'},
                  timeout: const Duration(seconds: 60));
              _melde(r['message']?.toString() ?? '', fehler: r['success'] != true);
              await _laden();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Neu laden',
            onPressed: () => _laden(live: true),
          ),
        ],
      ),
      body: _lade
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _laden(live: true),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _zugangsfeld(),
                  const SizedBox(height: 16),
                  if (_zugang['eingerichtet'] == true) ...[
                    _sendefeld(),
                    const SizedBox(height: 24),
                  ],
                  _verlaufsfeld(),
                ],
              ),
            ),
    );
  }

  Widget _zugangsfeld() {
    final ein = _zugang['eingerichtet'] == true;
    final live = _zugang['live'];
    final anonym = _zugang['kennung_anonym'] == true;

    if (!ein) {
      return Card(
        color: Colors.orange.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.key_off, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(child: Text('Noch kein Fax-Zugang',
                  style: Theme.of(context).textTheme.titleMedium)),
            ]),
            const SizedBox(height: 8),
            Text(
              (_zugang['hinweis'] ?? 'Fax braucht einen eigenen Personal Access Token.').toString(),
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _tokenDialog,
              icon: const Icon(Icons.key),
              label: const Text('Zugang einrichten'),
            ),
          ]),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(live == false ? Icons.cloud_off : Icons.cloud_done,
                color: live == false ? Colors.red : Colors.green),
            const SizedBox(width: 10),
            Expanded(child: Text('Faxleitung ${_zugang['faxline_id'] ?? '—'}',
                style: Theme.of(context).textTheme.titleMedium)),
            IconButton(
              icon: const Icon(Icons.key, size: 20),
              tooltip: 'Zugang ändern',
              onPressed: _tokenDialog,
            ),
          ]),
          const SizedBox(height: 4),
          _zeile('Absender', (_zugang['absender'] ?? '—').toString()),
          _zeile('Token', (_zugang['token_id'] ?? '—').toString()),
          if (_zugang['geprueft_am'] != null)
            _zeile('Zuletzt geprüft', _zugang['geprueft_am'].toString()),
          if (live == false && (_zugang['live_fehler'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_zugang['live_fehler'].toString(),
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
            ),
          // ⚠️ Ein Fax ohne Absenderkennung gilt bei Ämtern, Gerichten und
          // Praxen im Zweifel als nicht zuordenbar. Der Wert lässt sich im
          // sipgate-Kundencenter mit zwei Klicks zurücksetzen, deshalb wird er
          // bei jeder Live-Prüfung neu gelesen und hier gemeldet.
          if (anonym) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Die Faxleitung sendet ohne Absenderkennung.',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text(
                  'Auf dem Sendebericht des Empfängers steht dann keine Rufnummer. '
                  'Ämter und Gerichte behandeln ein Fax ohne Kennung im Zweifel als '
                  'nicht zuordenbar — bei einer Frist ist das der Unterschied '
                  'zwischen zugegangen und nicht zugegangen.',
                  style: TextStyle(fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _kennungSetzen,
                  icon: const Icon(Icons.visibility, size: 18),
                  label: Text('Nummer ${_zugang['absender'] ?? ''} anzeigen'),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _zeile(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
          Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 13))),
        ]),
      );

  Widget _sendefeld() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Fax senden', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _empfaenger,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Faxnummer des Empfängers',
                  // ⚠️ Ohne Vorwahl ist nicht entscheidbar, welches Land
                  // gemeint ist — der Server weist solche Nummern ab.
                  //
                  // ⚠️ Als Beispiel stand hier die Faxnummer des Vereins.
                  // Kein Geheimnis — sie steht im Impressum —, aber im Feld
                  // „Faxnummer des EMPFÄNGERS" liest sie sich wie eine
                  // Vorgabe und lädt dazu ein, sich selbst zu faxen. Die
                  // 0815-Nummer der Bundesnetzagentur-Beispiele tut es
                  // genauso und gehört niemandem.
                  helperText: 'Mit Vorwahl, z. B. 030 12345678',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.contacts),
              tooltip: 'Aus dem Verzeichnis wählen',
              onPressed: () async {
                // ⚠️ `zurueckgeben: true` ausdrücklich, auch wenn es der
                // Vorgabewert ist: der andere Zweig WÄHLT die Nummer, und ein
                // Anruf statt einer übernommenen Faxnummer wäre hier grotesk.
                final n = await Navigator.of(context).push<String>(MaterialPageRoute(
                    builder: (_) => const SipgateKontakteScreen(zurueckgeben: true)));
                if (n != null && n.isNotEmpty) _empfaenger.text = n;
              },
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Empfänger (für den Verlauf)',
              hintText: 'z. B. Amtsgericht Neu-Ulm',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _dokumentWaehlen,
            icon: const Icon(Icons.attach_file),
            label: Text(_dokumentName.isEmpty ? 'PDF wählen' : _dokumentName),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sendet ? null : _senden,
              icon: _sendet
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_sendet ? 'Wird übertragen …' : 'Fax senden'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _verlaufsfeld() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Verlauf', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        Text('${_faxe.length}', style: TextStyle(color: Colors.grey.shade600)),
      ]),
      const SizedBox(height: 4),
      // ⚠️ Der Satz steht da, damit niemand den Verlauf für den von sipgate
      // hält und ihn dort sucht, wenn er nach fünf Wochen leer ist.
      Text('Liegt bei uns — sipgate löscht seinen Verlauf nach 30 Tagen.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
      const SizedBox(height: 8),
      if (_faxe.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: Text('Noch kein Fax')),
        )
      else
        ..._faxe.map(_faxZeile),
    ]);
  }

  Widget _faxZeile(Map<String, dynamic> f) {
    final status = (f['status'] ?? '').toString();
    final roh = f['fax_status_type']?.toString();
    final (ikone, farbe) = _statusZeichen(status, roh);
    final ein = f['richtung'] == 'ein';
    final name = (f['empfaenger_name'] ?? '').toString();
    final nummer = (f['empfaenger'] ?? '').toString();
    final fehler = (f['fehler'] ?? '').toString();
    // Der Server sagt, ob die Datei noch da ist. Ohne das zeigten Auge und
    // Download auf ein Dokument, das es nicht mehr gibt.
    final hatDokument = f['hat_dokument'] == true;
    // ⚠️ Gemessene Breite, nicht Plattform: die App läuft auch auf einem
    // Android-Tablet, wo `isMobile` wahr wäre, obwohl reichlich Platz ist.
    final schmal = MediaQuery.sizeOf(context).width < 420;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(ikone, color: farbe),
        title: Text(name.isNotEmpty ? name : (nummer.isNotEmpty ? nummer : '—')),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${ein ? 'Empfangen von' : 'An'} $nummer'
              '${f['seiten'] != null ? ' · ${f['seiten']} S.' : ''}'),
          Text('${_statusText(status, roh)} · ${(f['gesendet_am'] ?? f['erstellt_am'] ?? '').toString()}',
              style: TextStyle(color: farbe, fontSize: 12)),
          if (fehler.isNotEmpty)
            Text(fehler, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
        ]),
        isThreeLine: true,
        // ⚠️ Das Auge steht IMMER offen, der Download nur, wo Platz ist.
        //
        // Ansehen und Herunterladen sind die beiden Dinge, die man mit einem
        // Fax tatsächlich tut — sie hinter zwei Tipps zu verstecken macht aus
        // dem Verlauf eine Liste, die man nur betrachten kann. Aber drei
        // Knöpfe belegen rund 144 dp; auf einem 360-dp-Telefon bliebe für
        // „Amtsgericht Neu-Ulm" und die Statuszeile zu wenig übrig, und
        // ListTile kürzt dann den Text statt die Knöpfe. Deshalb wandert auf
        // Telefonbreite der Download ins Menü — das Auge bleibt.
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (hatDokument)
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'Ansehen — bleibt im Speicher, wird nicht abgelegt',
              onPressed: () => _ansehen(f),
            ),
          if (hatDokument && !schmal)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Herunterladen',
              onPressed: () => _herunterladen(f),
            ),
          PopupMenuButton<String>(
            onSelected: (w) => switch (w) {
              'laden'    => _herunterladen(f),
              'drucken'  => _drucken(f),
              'stand'    => _nachsehen(f),
              'loeschen' => _loeschen(f),
              _          => null,
            },
            itemBuilder: (c) => [
              if (hatDokument && schmal)
                const PopupMenuItem(value: 'laden',
                    child: ListTile(leading: Icon(Icons.download_outlined), title: Text('Herunterladen'))),
              if (hatDokument)
                const PopupMenuItem(value: 'drucken',
                    child: ListTile(leading: Icon(Icons.print_outlined), title: Text('Drucken'))),
              // Nur solange sipgate überhaupt noch etwas dazu weiß.
              if (!ein && (f['session_id'] != null || status == 'in_zustellung'))
                const PopupMenuItem(value: 'stand',
                    child: ListTile(leading: Icon(Icons.refresh), title: Text('Stand nachsehen'))),
              const PopupMenuItem(value: 'loeschen',
                  child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Löschen'))),
            ],
          ),
        ]),
      ),
    );
  }
}
