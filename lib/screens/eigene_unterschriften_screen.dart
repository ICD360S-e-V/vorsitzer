import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:signature/signature.dart';

import '../services/api_service.dart';
import '../utils/app_farben.dart';

/// Dokumente, die der VORSITZENDE SELBST unterschreiben soll.
///
/// Nicht zu verwechseln mit der Unterschriften-Ansicht in der
/// Mitgliederverwaltung: dort geht es um die Unterschriften der Mitglieder,
/// hier um die eigenen. Gebraucht wird das für die Vollmacht, die zwei Leute
/// unterschreiben — das Mitglied als Vollmachtgeber, der Verein als
/// Vollmachtnehmer.
///
/// Serverseitig war dafür nichts zu bauen: member/signatur_manage.php hängt an
/// der Identität aus dem Token, nicht an einer Rolle, und der Code geht an die
/// Mobilnummer dessen, der unterschreibt. Der Vorsitzende ist dort ein Nutzer
/// wie jeder andere.
class EigeneUnterschriftenScreen extends StatefulWidget {
  final ApiService apiService;

  const EigeneUnterschriftenScreen({super.key, required this.apiService});

  @override
  State<EigeneUnterschriftenScreen> createState() =>
      _EigeneUnterschriftenScreenState();
}

class _EigeneUnterschriftenScreenState
    extends State<EigeneUnterschriftenScreen> {
  List<Map<String, dynamic>> _vorgaenge = [];
  bool _laedt = true;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() {
      _laedt = true;
      _fehler = null;
    });

    final antwort = await widget.apiService.eigeneSignatur('list');
    if (!mounted) return;

    if (antwort['success'] != true) {
      setState(() {
        _laedt = false;
        _fehler = antwort['message']?.toString() ?? 'Laden fehlgeschlagen';
      });
      return;
    }

    final roh = antwort['signaturen'];
    setState(() {
      _laedt = false;
      _vorgaenge = roh is List
          ? roh.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Unterschriften'),
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
          : _fehler != null
              ? _fehlerAnsicht()
              : _vorgaenge.isEmpty
                  ? _leer()
                  : RefreshIndicator(
                      onRefresh: _laden,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _vorgaenge.length,
                        itemBuilder: (_, i) => _kachel(_vorgaenge[i]),
                      ),
                    ),
    );
  }

  Widget _fehlerAnsicht() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 48, color: F.h(Colors.grey, 400)),
              const SizedBox(height: 16),
              Text(_fehler!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _laden, child: const Text('Erneut versuchen')),
            ],
          ),
        ),
      );

  Widget _leer() => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.draw_outlined, size: 56, color: F.h(Colors.grey, 400)),
          const SizedBox(height: 16),
          Text(
            'Zurzeit liegt nichts zu Ihrer Unterschrift vor.',
            textAlign: TextAlign.center,
            style: TextStyle(color: F.h(Colors.grey, 600)),
          ),
        ],
      );

  Widget _kachel(Map<String, dynamic> v) {
    final status = (v['status'] ?? 'offen').toString();
    final offen = status == 'offen';
    // Unterschrieben, aber das Dokument wartet noch auf den zweiten
    // Unterzeichner. Ohne eigenen Zustand sähe das aus wie „fertig" — und der
    // Vorsitzende suchte einen Download, den es noch nicht geben kann.
    final wartet = v['wartet_auf_mitunterzeichner'] == true;

    final (farbe, symbol, text) = switch (status) {
      'signiert' when wartet => (
          Colors.blue.shade700,
          Icons.hourglass_top,
          'Von Ihnen unterschrieben · warten auf die zweite Unterschrift',
        ),
      'signiert' => (Colors.green.shade700, Icons.verified, 'Von Ihnen unterschrieben'),
      'abgelehnt' => (Colors.red.shade700, Icons.cancel, 'Von Ihnen abgelehnt'),
      'widerrufen' => (Colors.grey.shade600, Icons.undo, 'Zurückgezogen'),
      'abgelaufen' => (Colors.grey.shade600, Icons.schedule, 'Frist abgelaufen'),
      _ => (Colors.orange.shade800, Icons.edit_document, 'Wartet auf Ihre Unterschrift'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: farbe.withValues(alpha: 0.15),
          child: Icon(symbol, color: farbe),
        ),
        title: Text((v['dokument_titel'] ?? '').toString(),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(text, style: TextStyle(color: farbe, fontSize: 12)),
        trailing: offen ? const Icon(Icons.chevron_right) : null,
        onTap: offen ? () => _oeffnen(v) : null,
      ),
    );
  }

  Future<void> _oeffnen(Map<String, dynamic> v) async {
    final fertig = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EigeneUnterschriftLeistenScreen(
          apiService: widget.apiService,
          signaturId: (v['id'] as num).toInt(),
          titel: (v['dokument_titel'] ?? '').toString(),
          seiten: (v['pdf_seiten'] as num?)?.toInt(),
        ),
      ),
    );
    if (fertig == true) _laden();
  }
}

// ═══════════════════════════════════════════════════════════════════════════

/// Der eigentliche Vorgang: lesen, unterschreiben, mit Code bestätigen.
class EigeneUnterschriftLeistenScreen extends StatefulWidget {
  final ApiService apiService;
  final int signaturId;
  final String titel;
  final int? seiten;

  const EigeneUnterschriftLeistenScreen({
    super.key,
    required this.apiService,
    required this.signaturId,
    required this.titel,
    this.seiten,
  });

  @override
  State<EigeneUnterschriftLeistenScreen> createState() =>
      _EigeneUnterschriftLeistenScreenState();
}

class _EigeneUnterschriftLeistenScreenState
    extends State<EigeneUnterschriftLeistenScreen> {
  final _unterschrift = SignatureController(
    penStrokeWidth: 2.5,
    penColor: Colors.black,
  );
  final _tanFeld = TextEditingController();

  int _schritt = 0;
  bool _sendet = false;
  String? _fehler;
  String? _codeGesendetAn;
  int _letzteGeseheneSeite = 1;

  /// Erst weiterblättern lassen, wenn das Dokument bis zum Ende gesehen wurde.
  /// Wer unterschreibt, soll gelesen haben können — das ist der Sinn der
  /// ganzen Übung, nicht Förmelei.
  bool get _durchgeblaettert =>
      widget.seiten == null || _letzteGeseheneSeite >= widget.seiten!;

  @override
  void dispose() {
    _unterschrift.dispose();
    _tanFeld.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titel, style: const TextStyle(fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_schritt + 1) / 3),
        ),
      ),
      body: switch (_schritt) {
        0 => _lesen(),
        1 => _malen(),
        _ => _bestaetigen(),
      },
    );
  }

  // ── Schritt 1: lesen ──

  Widget _lesen() => Column(
        children: [
          Expanded(
            child: _EigenesPdf(
              apiService: widget.apiService,
              signaturId: widget.signaturId,
              onSeite: (s) {
                if (s > _letzteGeseheneSeite) {
                  setState(() => _letzteGeseheneSeite = s);
                }
              },
            ),
          ),
          _fussleiste(
            hinweis: _durchgeblaettert
                ? null
                : 'Bitte lesen Sie das Dokument bis zur letzten Seite '
                    '($_letzteGeseheneSeite von ${widget.seiten}).',
            weiter: _durchgeblaettert ? () => setState(() => _schritt = 1) : null,
            weiterText: 'Weiter zur Unterschrift',
          ),
        ],
      );

  // ── Schritt 2: unterschreiben ──

  Widget _malen() => Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'Bitte unterschreiben Sie im weißen Feld.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: F.flaeche,
                        border: Border.all(color: F.h(Colors.grey, 400)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Signature(
                        controller: _unterschrift,
                        backgroundColor: F.flaeche,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _unterschrift.clear(),
                      icon: const Icon(Icons.clear, size: 18),
                      label: const Text('Löschen'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _fussleiste(
            zurueck: () => setState(() => _schritt = 0),
            weiter: () {
              if (_unterschrift.isEmpty) {
                _meldung('Bitte unterschreiben Sie zuerst.', fehler: true);
                return;
              }
              setState(() => _schritt = 2);
            },
            weiterText: 'Weiter zum Code',
          ),
        ],
      );

  // ── Schritt 3: Code ──

  Widget _bestaetigen() => Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Zur Bestätigung schicken wir Ihnen einen Code per SMS an '
                    'Ihre hinterlegte Mobilnummer.',
                  ),
                  const SizedBox(height: 16),
                  if (_codeGesendetAn == null)
                    FilledButton.icon(
                      onPressed: _sendet ? null : _tanAnfordern,
                      icon: const Icon(Icons.sms),
                      label: const Text('Code anfordern'),
                    )
                  else ...[
                    Text('Code gesendet an $_codeGesendetAn',
                        style: TextStyle(color: F.h(Colors.green, 700))),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _tanFeld,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Code aus der SMS',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        // Der Knopf hängt am Inhalt, also muss der Aufbau
                        // laufen, wenn sich der Inhalt ändert. Genau das fehlte
                        // in der Mitglieder-App und der Knopf blieb tot.
                        setState(() {});
                      },
                    ),
                    TextButton(
                      onPressed: _sendet ? null : _tanAnfordern,
                      child: const Text('Neuen Code anfordern'),
                    ),
                  ],
                  if (_fehler != null) ...[
                    const SizedBox(height: 12),
                    Text(_fehler!, style: TextStyle(color: F.h(Colors.red, 700))),
                  ],
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: _sendet ? null : _ablehnen,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Unterschrift ablehnen'),
                    style: TextButton.styleFrom(foregroundColor: F.h(Colors.red, 700)),
                  ),
                ],
              ),
            ),
          ),
          _fussleiste(
            zurueck: () => setState(() => _schritt = 1),
            weiter: (_codeGesendetAn != null && _tanFeld.text.trim().length >= 4 && !_sendet)
                ? _signieren
                : null,
            weiterText: 'Rechtsverbindlich unterschreiben',
          ),
        ],
      );

  // ── Fußleiste ──

  Widget _fussleiste({
    String? hinweis,
    VoidCallback? zurueck,
    VoidCallback? weiter,
    required String weiterText,
  }) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: F.h(Colors.grey, 300))),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              if (hinweis != null) ...[
                Text(hinweis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700))),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  if (zurueck != null)
                    TextButton(onPressed: zurueck, child: const Text('Zurück')),
                  const Spacer(),
                  FilledButton(
                    onPressed: weiter,
                    child: _sendet
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(weiterText),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  // ── Aktionen ──

  Future<void> _tanAnfordern() async {
    setState(() {
      _sendet = true;
      _fehler = null;
    });

    final antwort = await widget.apiService
        .eigeneSignatur('tan_anfordern', {'signatur_id': widget.signaturId});

    if (!mounted) return;
    setState(() => _sendet = false);

    if (antwort['success'] == true) {
      setState(() => _codeGesendetAn = antwort['gesendet_an']?.toString());
      return;
    }

    // 'keine_rufnummer' ausdrücklich benennen: ein Knopf, der nichts tut, sieht
    // aus wie ein Fehler in der App, obwohl schlicht keine Nummer hinterlegt ist.
    setState(() {
      _fehler = antwort['grund'] == 'keine_rufnummer'
          ? 'Für Ihr Konto ist keine Mobilnummer hinterlegt. '
              'Ohne Nummer kann kein Code verschickt werden.'
          : (antwort['message']?.toString() ?? 'Code konnte nicht gesendet werden.');
    });
  }

  Future<void> _signieren() async {
    final svg = _unterschrift.toRawSVG();
    if (svg == null || svg.isEmpty) {
      setState(() => _schritt = 1);
      _meldung('Die Unterschrift ist leer.', fehler: true);
      return;
    }

    setState(() {
      _sendet = true;
      _fehler = null;
    });

    final antwort = await widget.apiService.eigeneSignatur('signieren', {
      'signatur_id': widget.signaturId,
      'signature_svg': svg,
      'tan': _tanFeld.text.trim(),
      'signed_at_local': DateTime.now().toIso8601String(),
      'device_hostname': await _geraetename(),
    });

    if (!mounted) return;
    setState(() => _sendet = false);

    if (antwort['success'] == true) {
      _meldung('Unterschrift gespeichert.', erfolg: true);
      if (mounted) Navigator.pop(context, true);
      return;
    }

    setState(() {
      _fehler = switch (antwort['grund']?.toString()) {
        'tan_falsch' => 'Der Code stimmt nicht.',
        'tan_abgelaufen' => 'Der Code ist abgelaufen. Bitte fordern Sie einen neuen an.',
        'zu_viele_versuche' =>
          'Zu viele Fehlversuche. Bitte fordern Sie einen neuen Code an.',
        _ => antwort['message']?.toString() ?? 'Unterschrift fehlgeschlagen.',
      };
    });
  }

  Future<void> _ablehnen() async {
    final grundFeld = TextEditingController();

    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unterschrift ablehnen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Das Dokument wird dann nicht unterschrieben. Bei einer Vollmacht '
              'gilt die Ablehnung für das ganze Dokument — auch wenn die andere '
              'Person schon unterschrieben hat.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: grundFeld,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Begründung (freiwillig)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ablehnen'),
          ),
        ],
      ),
    );

    if (bestaetigt != true || !mounted) return;

    final antwort = await widget.apiService.eigeneSignatur('ablehnen', {
      'signatur_id': widget.signaturId,
      'grund': grundFeld.text.trim(),
    });
    if (!mounted) return;

    if (antwort['success'] == true) {
      _meldung('Abgelehnt.', erfolg: true);
      Navigator.pop(context, true);
    } else {
      _meldung(antwort['message']?.toString() ?? 'Ablehnen fehlgeschlagen.',
          fehler: true);
    }
  }

  /// Gerätename fürs Beweisbündel. Fehlt er, bleibt das Feld leer — daran darf
  /// eine gültige Unterschrift nicht scheitern.
  Future<String?> _geraetename() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return _zusammen([a.manufacturer, a.model, 'Android ${a.version.release}']);
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        return _zusammen([i.name, i.model, '${i.systemName} ${i.systemVersion}']);
      }
      if (Platform.isMacOS) {
        final m = await info.macOsInfo;
        return _zusammen([m.computerName, m.model, 'macOS ${m.osRelease}']);
      }
      if (Platform.isWindows) {
        final w = await info.windowsInfo;
        return _zusammen([w.computerName, w.productName]);
      }
      if (Platform.isLinux) {
        final l = await info.linuxInfo;
        return _zusammen([Platform.localHostname, l.prettyName]);
      }
    } catch (_) {
      // bewusst still
    }
    return null;
  }

  static String? _zusammen(List<String?> teile) {
    final gefiltert = teile
        .map((t) => (t ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (gefiltert.isEmpty) return null;
    final text = gefiltert.join(' · ');
    return text.length > 120 ? text.substring(0, 120) : text;
  }

  void _meldung(String text, {bool fehler = false, bool erfolg = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: fehler
            ? Colors.red.shade700
            : erfolg
                ? Colors.green.shade700
                : null,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

/// Lädt das PDF über den eigenen Client und zeigt es aus dem Speicher.
///
/// Nicht über `PdfViewer.uri`: der Betrachter lädt dann selbst, mit eigener
/// Zertifikatsprüfung — unter Windows scheitert das an der neuen Wurzel und
/// sieht nur wie „Failed to open PDF" aus.
class _EigenesPdf extends StatefulWidget {
  final ApiService apiService;
  final int signaturId;
  final void Function(int seite) onSeite;

  const _EigenesPdf({
    required this.apiService,
    required this.signaturId,
    required this.onSeite,
  });

  @override
  State<_EigenesPdf> createState() => _EigenesPdfState();
}

class _EigenesPdfState extends State<_EigenesPdf> {
  Uint8List? _daten;
  bool _laedt = true;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    final bytes = await widget.apiService.eigeneSignaturPdf(widget.signaturId);
    if (!mounted) return;
    setState(() {
      _daten = bytes;
      _laedt = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_laedt) return const Center(child: CircularProgressIndicator());
    if (_daten == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 48, color: F.h(Colors.grey, 400)),
              const SizedBox(height: 16),
              const Text('Das Dokument konnte nicht geladen werden.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() => _laedt = true);
                  _laden();
                },
                child: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
    }

    return PdfViewer.data(
      _daten!,
      sourceName: 'unterschrift_${widget.signaturId}.pdf',
      params: PdfViewerParams(
        onPageChanged: (seite) {
          if (seite != null) widget.onSeite(seite);
        },
      ),
    );
  }
}
