import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// Nur LatLng: latlong2 exportiert ein eigenes `Path<LatLng>`, das sonst das
// `Path` aus dart:ui verdeckt, mit dem der Diagramm-Painter zeichnet.
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:icd_netinfo/icd_netinfo.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';
import '../services/speedtest_service.dart';
import '../services/termin_sms_gateway_service.dart';

/// Speedtest gegen den EIGENEN Server — kein Fremdanbieter ist beteiligt.
///
/// Zweck ist nicht die eine schöne Zahl, sondern die Reihe: wann bricht die
/// Leitung ein, wie oft, und auf welcher Mobilfunkgeneration hing das Gerät in
/// dem Moment. Deshalb misst die App alle 30 Minuten selbstständig weiter und
/// hält bis zu fünf Jahre vor.
/// `as Map?`, aber ohne zu werfen, wenn stattdessen eine Liste ankommt.
///
/// Ein leeres PHP-Array kodiert als `[]`, nicht als `{}` — jede serverseitige
/// Struktur mit Textschlüsseln kann also im Leerfall als Liste eintreffen.
/// Begründung im Detail bei [speedtestNachIndex].
Map<String, dynamic>? speedtestAlsMap(dynamic roh) =>
    roh is Map ? roh.cast<String, dynamic>() : null;

Map<int, double> speedtestNachIndex(dynamic roh) {
  final werte = <int, double>{};
  if (roh is List) {
    for (var i = 0; i < roh.length; i++) {
      final v = roh[i];
      if (v is num) werte[i] = v.toDouble();
    }
  } else if (roh is Map) {
    roh.forEach((k, v) {
      final i = int.tryParse(k.toString());
      if (i != null && v is num) werte[i] = v.toDouble();
    });
  }
  return werte;
}


class SpeedtestScreen extends StatefulWidget {
  const SpeedtestScreen({super.key});

  @override
  State<SpeedtestScreen> createState() => _SpeedtestScreenState();
}

class _SpeedtestScreenState extends State<SpeedtestScreen> {
  static const _accent = Color(0xFF4a90d9);

  static const _zeitraeume = <String, String>{
    '1d': '1 Tag',
    '1w': '1 Woche',
    '2w': '2 Wochen',
    '1m': '1 Monat',
    '6m': '6 Monate',
    '1y': '1 Jahr',
    '2y': '2 Jahre',
    '3y': '3 Jahre',
    '5y': '5 Jahre',
  };

  String _zeitraum = '1d';
  String? _geraetKey;

  /// Kopfzeilen für den Kachel-Proxy. Der Endpunkt ist wie alle anderen
  /// authentifiziert — sonst wäre er ein offener Kachel-Spiegel für Fremde,
  /// genau die Art Fund, die das Hardening vom 25.07. geschlossen hat.
  Map<String, String> get _kachelKopf {
    final t = ApiService().token;
    return t == null ? const {} : {'Authorization': 'Bearer $t'};
  }

  /// Geschätzte maximale Geschwindigkeit des Tarifs (300 bei Business Mobil L).
  double _maximal = kBusinessMobilLDownloadMax;
  SpeedtestDichte _dichte = SpeedtestDichte.mittel;

  /// Ausgewertet wird gegen [_maximal] × Prozentsatz der Haushaltsdichte —
  /// gegen die vollen 300 lägen praktisch alle Messungen darunter, und die
  /// Aussage wäre wertlos.
  double get _bewertung => _maximal * _dichte.anteil;

  bool _auto = false;
  bool _jobLaeuft = false;
  DateTime? _letzteMessung;
  DateTime? _naechsteMessung;

  /// Nicht eingereichte Messungen. Sichtbar, weil der wahrscheinlichste
  /// Dauerfall ein totes Token ist — dann scheitert jedes Einreichen, und ohne
  /// diese Zeile bliebe der Ausfall unbemerkt.
  int _rueckstand = 0;

  /// Heute verbrauchtes Messvolumen und das Tagesbudget aus plan.php.
  ///
  /// Seit die Messung auf ZEIT statt auf Volumen läuft, kostet eine schnelle
  /// Leitung mehr Daten als eine langsame — der Verbrauch wächst also
  /// ausgerechnet dann, wenn alles gut ist. Deshalb sichtbar statt versteckt.
  double _volumenHeute = 0;
  int _volumenBudget = 3000;

  /// Ohne „immer erlauben" bleibt jede Hintergrundmessung ohne frische Position.
  bool _hintergrundOrtung = true;

  /// Ist die App von der Akku-Optimierung ausgenommen?
  ///
  /// ⚠️ Ohne die Ausnahme friert Android den 30-Minuten-Takt im Ruhezustand
  /// ein — und zwar über Nacht, also genau in den Stunden, in denen die
  /// Leitung am wenigsten belastet ist. In der Nacht auf den 08.08.2026 sind
  /// dadurch **neun Stunden** aus der Reihe gefallen (23:44 bis 08:39, größter
  /// Abstand 534 Minuten laut Schweigewächter). Eine Lücke ist in einer
  /// Beweisreihe das Schlimmste, was passieren kann: sie sieht aus wie eine
  /// ausgesuchte Stichprobe.
  bool _akkuAusnahme = true;

  bool _laedt = true;
  bool _misst = false;
  SpeedtestPhase _phase = SpeedtestPhase.latenz;
  double _anteil = 0;

  SpeedtestErgebnis? _letztes;
  Map<String, dynamic>? _reihe;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _maximal = await SpeedtestService.maximalGeschwindigkeit();
    _dichte = await SpeedtestService.dichte();
    _auto = await SpeedtestService.autoAktiv();
    _jobLaeuft = await SpeedtestService.jobLaeuft();
    _letzteMessung = await SpeedtestService.letzteMessung();
    _naechsteMessung = await SpeedtestService.naechsteMessung();
    _rueckstand = await SpeedtestService.rueckstand();
    _volumenHeute = await SpeedtestService.tagesvolumenMb();
    _volumenBudget = await SpeedtestService.tagesbudgetMb();
    _hintergrundOrtung = !Platform.isAndroid ||
        await SpeedtestService.hintergrundOrtungErlaubt();
    _akkuAusnahme = await TerminSmsGatewayService.isBatteryExempt();
    await _reiheLaden();
  }

  Future<void> _reiheLaden() async {
    setState(() { _laedt = true; _fehler = null; });
    try {
      final antwort = await ApiService().speedtestListe(
        range: _zeitraum,
        geraetKey: _geraetKey,
        schwelle: _bewertung,
      );
      if (!mounted) return;
      if (antwort['success'] == true) {
        setState(() { _reihe = antwort; _laedt = false; });
        await _mobilesGeraetWaehlen(antwort);
      } else {
        setState(() {
          _fehler = (antwort['message'] ?? 'Abfrage fehlgeschlagen').toString();
          _laedt = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _fehler = e.toString(); _laedt = false; });
    }
  }

  /// Wählt beim ersten Laden das Gerät mit der Mobilfunkleitung vor.
  ///
  /// Die Auswertung ist ohnehin je Gerät gerechnet — der Maßstab der
  /// Verfügung prüft EINEN Zugang, nicht einen Gerätepark. In der Ansicht
  /// „alle Geräte" richtete sich dagegen die Diagrammskala nach dem
  /// schnellsten, und ein Desktop am Festnetz hätte die Einbrüche des Tablets
  /// optisch platt gedrückt. Nur beim ersten Mal: eine spätere Auswahl des
  /// Nutzers darf nicht bei jeder Aktualisierung überschrieben werden.
  bool _geraetVorgewaehlt = false;
  Future<void> _mobilesGeraetWaehlen(Map<String, dynamic> antwort) async {
    if (_geraetVorgewaehlt || _geraetKey != null) return;
    _geraetVorgewaehlt = true;
    final geraete = (antwort['geraete'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (geraete.length < 2) return;
    for (final g in geraete) {
      final bauform = g['bauform']?.toString();
      if (bauform == 'tablet' || bauform == 'handy') {
        if (!mounted) return;
        setState(() => _geraetKey = g['geraet_key']?.toString());
        await _reiheLaden();
        return;
      }
    }
  }

  Future<void> _messen() async {
    if (_misst) return;
    // Ohne die Berechtigung meldet Android bei Telekoms NSA-5G schlicht „LTE".
    // Einmal fragen, wenn wir im Vordergrund sind — im Hintergrundjob ginge es
    // nicht mehr, und die Reihe würde jahrelang das Falsche protokollieren.
    if (Platform.isAndroid && !await hatTelefonBerechtigung()) {
      await telefonBerechtigungAnfragen();
    }

    setState(() { _misst = true; _anteil = 0; _phase = SpeedtestPhase.latenz; });
    final e = await SpeedtestService.messen(
      fortschritt: (phase, anteil) {
        if (mounted) setState(() { _phase = phase; _anteil = anteil; });
      },
    );
    if (!mounted) return;
    final letzte = await SpeedtestService.letzteMessung();
    final naechste = await SpeedtestService.naechsteMessung();
    final offen = await SpeedtestService.rueckstand();
    if (!mounted) return;
    setState(() {
      _letztes = e;
      _misst = false;
      _letzteMessung = letzte;
      _naechsteMessung = naechste;
      _rueckstand = offen;
    });
    _volumenHeute = await SpeedtestService.tagesvolumenMb();
    await _reiheLaden();
  }

  /// Marker der Messreihe verwalten.
  ///
  /// Ein Marker ist der Zeitpunkt eines Ereignisses, das die Leitung verändert
  /// haben könnte: die Mängelanzeige an die Telekom, ein Tarifwechsel, ein
  /// neuer Router. Erst damit lässt sich die Frage beantworten, auf die nach
  /// einer Beschwerde alles hinausläuft — hat sich danach etwas geändert? Ohne
  /// einen festgehaltenen Zeitpunkt gibt es kein „danach", das man vergleichen
  /// könnte, und die Reihe ist ein einziger langer Durchschnitt.
  Future<void> _markerVerwalten() async {
    final bote = ScaffoldMessenger.of(context);
    final antwort = await ApiService().speedtestMarker('list');
    if (!mounted) return;
    if (antwort['success'] != true) {
      bote.showSnackBar(SnackBar(
          content: Text('Marker nicht erreichbar: ${antwort['message'] ?? '?'}')));
      return;
    }
    final liste = (antwort['marker'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Marker'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zeitpunkte, an denen sich etwas geändert haben könnte. Die '
                  'Auswertung zeigt zu jedem Marker Mittelwert und Median '
                  'vorher und nachher.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                if (liste.isEmpty)
                  const Text('Noch kein Marker gesetzt.',
                      style: TextStyle(fontSize: 13))
                else
                  ...liste.map((m) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${m['text']}', style: const TextStyle(fontSize: 13)),
                        subtitle: Text('${m['zeitpunkt']}',
                            style: const TextStyle(fontSize: 11)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () async {
                            final r = await ApiService()
                                .speedtestMarker('delete', id: (m['id'] as num?)?.toInt());
                            if (r['success'] == true) {
                              setDialog(() => liste.remove(m));
                            }
                          },
                        ),
                      )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Schließen'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Neu'),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    await _markerAnlegen();
  }

  Future<void> _markerAnlegen() async {
    final feld = TextEditingController();
    var zeitpunkt = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Marker setzen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: feld,
                autofocus: true,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Was ist passiert?',
                  hintText: 'z. B. Mängelanzeige an Telekom Geschäftskunden',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(
                  '${zeitpunkt.day.toString().padLeft(2, '0')}.'
                  '${zeitpunkt.month.toString().padLeft(2, '0')}.${zeitpunkt.year}',
                ),
                subtitle: const Text('Zeitpunkt des Ereignisses'),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: zeitpunkt,
                    // Vor der ersten Messung gibt es nichts zu vergleichen.
                    firstDate: DateTime(2026, 8, 4),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setDialog(() => zeitpunkt = d);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Setzen')),
          ],
        ),
      ),
    );

    if (ok != true || feld.text.trim().isEmpty) return;
    if (!mounted) return;
    final bote = ScaffoldMessenger.of(context);
    final r = await ApiService()
        .speedtestMarker('add', zeitpunkt: zeitpunkt, text: feld.text.trim());
    if (!mounted) return;
    bote.showSnackBar(SnackBar(
      content: Text(r['success'] == true
          ? 'Marker gesetzt.'
          : 'Nicht gespeichert: ${r['message'] ?? '?'}'),
    ));
    if (r['success'] == true) await _reiheLaden();
  }

  Future<void> _exportieren(String format) async {
    final bote = ScaffoldMessenger.of(context);
    bote.showSnackBar(SnackBar(content: Text('${format.toUpperCase()} wird erstellt …')));
    try {
      final antwort = await ApiService().speedtestExport(
        range: _zeitraum,
        format: format,
        geraetKey: _geraetKey,
        schwelle: _bewertung,
      );
      if (antwort.statusCode >= 400) {
        bote.showSnackBar(SnackBar(content: Text('Export fehlgeschlagen (HTTP ${antwort.statusCode})')));
        return;
      }
      final ordner = await getApplicationDocumentsDirectory();
      // `brief` ist ein PDF, nur mit anderem Inhalt.
      final endung = format == 'brief' ? 'pdf' : format;
      final name = 'speedtest_${format}_${_zeitraum}_'
          '${DateTime.now().millisecondsSinceEpoch}.$endung';
      final datei = File('${ordner.path}/$name');
      await datei.writeAsBytes(antwort.bodyBytes);

      // ⚠️ Der app-private Dokumentenordner ist auf Android von aussen NICHT
      // erreichbar — ohne Öffnen-Aktion lag das Beweisdokument dort und kam nie
      // heraus. Ein kopierter Pfad hilft auf einem Tablet niemandem: es gibt
      // keine Dateiverwaltung, die ihn ansteuern könnte.
      bote.showSnackBar(SnackBar(
        content: Text('Gespeichert: $name'),
        action: SnackBarAction(
          label: 'Öffnen',
          onPressed: () => OpenFilex.open(datei.path),
        ),
        duration: const Duration(seconds: 10),
      ));
      // Direkt anbieten: in aller Regel will man es sofort weiterschicken.
      await OpenFilex.open(datei.path);
    } catch (e) {
      bote.showSnackBar(SnackBar(content: Text('Export fehlgeschlagen: $e')));
    }
  }

  Future<void> _schwelleSetzen() async {
    final regler = TextEditingController(text: _maximal.toStringAsFixed(0));
    var dichte = _dichte;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final max = double.tryParse(regler.text.replaceAll(',', '.')) ?? 0;
          return AlertDialog(
            title: const Text('Bewertungsmaßstab'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Im Mobilfunk gibt es keine zugesagte Mindestgeschwindigkeit — '
                    'anders als im Festnetz nennt der Vertrag nur einen Höchstwert. '
                    'Für Business Mobil L (5. Generation) sind das laut Preisliste '
                    'Geschäftskunden 300 Mbit/s im Download.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: regler,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialog(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Geschätzte maximale Geschwindigkeit (Mbit/s)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Gegen diesen Höchstwert direkt zu messen wäre sinnlos — fast '
                    'jede Messung läge darunter. Maßgeblich ist der Anteil, den die '
                    'Bundesnetzagentur (Vfg 35/2026) je nach Haushaltsdichte am '
                    'Standort noch als vertragsgemäß ansieht. Je dichter besiedelt, '
                    'desto mehr wird verlangt.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  RadioGroup<SpeedtestDichte>(
                    groupValue: dichte,
                    onChanged: (v) => setDialog(() => dichte = v ?? dichte),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final d in SpeedtestDichte.values)
                          RadioListTile<SpeedtestDichte>(
                            value: d,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(d.bezeichnung, style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                              '${d.prozent} → ${(max * d.anteil).toStringAsFixed(0)} Mbit/s',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Welche Kategorie am Standort gilt, zeigt die App '
                    '„Nachweisverfahren Mobilfunk" der Bundesnetzagentur vor jeder '
                    'Messung an.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Speichern')),
            ],
          );
        },
      ),
    );

    if (ok != true) return;
    final max = double.tryParse(regler.text.replaceAll(',', '.')) ?? _maximal;
    await SpeedtestService.setzeMaximalGeschwindigkeit(max);
    await SpeedtestService.setzeDichte(dichte);
    setState(() { _maximal = max; _dichte = dichte; });
    await _reiheLaden();
  }

  Future<void> _autoUmschalten(bool an) async {
    await SpeedtestService.setzeAuto(an);
    final laeuft = await SpeedtestService.jobLaeuft();
    if (mounted) setState(() { _auto = an; _jobLaeuft = laeuft; });
  }

  @override
  Widget build(BuildContext context) {
    final geraete = (_reihe?['geraete'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final statistik = speedtestAlsMap(_reihe?['statistik']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Speedtest'),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.speed),
            tooltip: 'Bewertungsmaßstab',
            onPressed: _schwelleSetzen,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            tooltip: 'Export',
            onSelected: _exportieren,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Als PDF exportieren')),
              PopupMenuItem(value: 'csv', child: Text('Als CSV exportieren')),
              PopupMenuDivider(),
              // Der Schritt von der Messreihe zur Beschwerde fehlte bisher
              // ganz: der Export lieferte Zahlen, aber niemand hätte daraus
              // ein Anschreiben gemacht.
              PopupMenuItem(
                value: 'brief',
                child: Text('Beschwerde-Entwurf (PDF)'),
              ),
            ],
          ),
          // Der Marker war serverseitig fertig und von der App aus überhaupt
          // nicht erreichbar — die einzige Stelle, an der ein „danach"
          // entsteht, hatte keine Oberfläche.
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Marker setzen',
            onPressed: _markerVerwalten,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: _laedt ? null : _reiheLaden,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _messkarte(),
          const SizedBox(height: 16),
          _automatikkarte(),
          const SizedBox(height: 16),
          if (geraete.length > 1) ...[_geraetewahl(geraete), const SizedBox(height: 12)],
          _zeitraumwahl(),
          const SizedBox(height: 16),
          if (_fehler != null)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_fehler!, style: TextStyle(color: Colors.red.shade900)),
              ),
            )
          else if (_laedt)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _diagramm(),
            const SizedBox(height: 16),
            _karte(),
            const SizedBox(height: 16),
            if (statistik != null) ...[
              _statistikkarte(statistik),
              const SizedBox(height: 16),
              _funkkarte(statistik),
              const SizedBox(height: 16),
              _profilkarte(statistik),
            ],
          ],
        ],
      ),
    );
  }

  // ── Bausteine ───────────────────────────────────────────────────────────

  Widget _messkarte() {
    final e = _letztes;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _misst ? _phasenname(_phase) : 'Messung',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _misst ? null : _messen,
                  icon: _misst
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow),
                  label: Text(_misst ? 'läuft …' : 'Jetzt messen'),
                ),
              ],
            ),
            if (_misst) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _anteil == 0 ? null : _anteil),
            ],
            if (e != null) ...[
              const SizedBox(height: 16),
              if (!e.erfolgreich)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Messung fehlgeschlagen: ${e.fehler}',
                      style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
                )
              else ...[
                Row(
                  children: [
                    _wert('Download', e.downloadMbps, 'Mbit/s', Colors.blue.shade700),
                    _wert('Upload', e.uploadMbps, 'Mbit/s', Colors.green.shade700),
                    _wert('Ping', e.pingAvgMs, 'ms', Colors.orange.shade800),
                    _wert('Jitter', e.jitterMs, 'ms', Colors.purple.shade400),
                  ],
                ),
                // Warum eine Zahl fehlt oder weich ist, gehört direkt neben die
                // Zahl — sonst rätselt man beim nächsten Blick, ob gemessen
                // wurde oder etwas kaputt war.
                if (e.nurLatenzGrund != null)
                  _hinweiszeile(
                    Icons.data_saver_off,
                    switch (e.nurLatenzGrund) {
                      'tagesbudget' => 'Nur Latenz gemessen — das Tagesbudget für '
                          'diesen Takt war aufgebraucht.',
                      'roaming' => 'Nur Latenz gemessen — im Roaming wird keine '
                          'Massenübertragung gestartet.',
                      'wlan' => 'Nur Latenz gemessen — im Hintergrund über WLAN. '
                          'Über die Telekom-Leitung sagt so ein Lauf nichts aus.',
                      _ => 'Nur Latenz gemessen (${e.nurLatenzGrund}).',
                    },
                  ),
                if (e.uploadZeitDeckel)
                  _hinweiszeile(Icons.timer_off,
                      'Upload in die Zeitgrenze gelaufen — kein Messwert, aber '
                      'auch kein Ausfall. Die Menge stammte aus einem schnelleren Lauf.'),
                if (e.uploadFehler != null)
                  _hinweiszeile(Icons.upload_file,
                      'Upload gescheitert, Download gilt trotzdem: ${e.uploadFehler}'),
                if (e.downloadSchnittstelleMbps != null)
                  _hinweiszeile(
                    Icons.compare_arrows,
                    'Schnittstelle des Geräts: '
                    '${e.downloadSchnittstelleMbps!.toStringAsFixed(1)} Mbit/s im selben '
                    'Fenster. Immer etwas höher — Protokollköpfe zählen mit. '
                    'Als Obergrenze zu lesen, nicht als besserer Messwert.',
                  ),
                ?_verlaufkarte(e),
                const SizedBox(height: 12),
                _netzzeilen(e),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Der Verlauf INNERHALB des Messfensters.
  ///
  /// Zwei Läufe mit je 61 Mbit/s können drei gleichmäßige Sekunden sein — oder
  /// anderthalb Sekunden mit 150 und anderthalb mit gar nichts. Nur das Zweite
  /// lässt ein Gespräch abreißen, und im Durchschnitt sind die beiden nicht zu
  /// unterscheiden. Die Tripel liegen seit dem ersten Lauf in jedem Datensatz.
  ///
  /// ⚠️ Zusammengefasst auf 250 ms, nicht auf den 50-ms-Rohtakt. Bei
  /// 0,46 Mbit/s über vier Ströme kommen je 50 ms rund 2,9 kB an — weniger als
  /// ein einziger Socket-Read. Die Mehrzahl der Rohtakte ist dann legitim null,
  /// ohne dass die Leitung stand. Ein daraus abgeleiteter „Einbruch" wäre ein
  /// Eigentor.
  ///
  /// ⚠️ Nur Abschnitte, in denen ALLE Ströme liefen (dritte Spalte). Sonst wäre
  /// der normale Abfall am Fensterende — drei von vier Scheiben fertig — von
  /// einem echten Loch nicht zu trennen.
  Widget? _verlaufkarte(SpeedtestErgebnis e) {
    const bucketMs = 250;
    final roh = e.downloadVerlauf;
    if (roh.length < 4) return null;

    final raten = <double>[];
    var letzteMs = 0.0, letzteBytes = 0.0, blockStart = 0.0, blockBytes = 0.0;
    var alleAktiv = true;
    for (final t in roh) {
      if (t.length < 3) continue;
      final ms = t[0].toDouble(), bytes = t[1].toDouble(), stroeme = t[2].toInt();
      if (stroeme < e.streams) alleAktiv = false;
      blockBytes += bytes - letzteBytes;
      letzteMs = ms;
      letzteBytes = bytes;
      if (ms - blockStart >= bucketMs) {
        final s = (ms - blockStart) / 1000;
        if (s > 0 && alleAktiv) raten.add(blockBytes * 8 / s / 1e6);
        blockStart = ms;
        blockBytes = 0;
        alleAktiv = true;
      }
    }
    if (raten.length < 3) return null;
    if (letzteMs <= 0) return null;

    final hoechst = raten.reduce(max);
    final tiefst = raten.reduce(min);
    if (hoechst <= 0) return null;
    // Ein Einbruch ist erst einer, wenn er deutlich unter das Übrige fällt.
    final einbruch = tiefst < hoechst * 0.35;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Verlauf im Messfenster',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              const Spacer(),
              Text('${tiefst.toStringAsFixed(0)}–${hoechst.toStringAsFixed(0)} Mbit/s',
                  style: TextStyle(
                      fontSize: 11,
                      color: einbruch ? Colors.orange.shade800 : Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 34,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final r in raten)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 0.7),
                      child: Container(
                        height: (r / hoechst * 32).clamp(1.5, 32.0),
                        decoration: BoxDecoration(
                          color: r < hoechst * 0.35 ? Colors.orange.shade400 : _accent,
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(1.5)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (einbruch)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Der Durchsatz brach innerhalb des Fensters ein — im Mittelwert '
                'ist das nicht zu sehen, in einem Gespräch schon.',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
              ),
            ),
        ],
      ),
    );
  }

  /// Kurze Erläuterung unter den Messwerten.
  ///
  /// Warum eine Zahl fehlt oder weich ist, gehört neben die Zahl. Ein leeres
  /// Feld ohne Begründung liest sich wie ein Defekt, und in einer Beweisreihe
  /// ist „hier wurde bewusst nicht gemessen" eine ganz andere Aussage als
  /// „hier ist etwas schiefgegangen".
  Widget _hinweiszeile(IconData symbol, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(symbol, size: 15, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            ),
          ],
        ),
      );

  Widget _wert(String titel, double zahl, String einheit, Color farbe) => Expanded(
        child: Column(
          children: [
            Text(zahl.toStringAsFixed(zahl >= 100 ? 0 : 1),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: farbe)),
            Text(einheit, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text(titel, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );

  Widget _netzzeilen(SpeedtestErgebnis e) {
    final netz = e.netz;
    final zeilen = <Widget>[];

    void zeile(String links, String? rechts, {Color? farbe, String? hinweis}) {
      if (rechts == null || rechts.isEmpty) return;
      zeilen.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 150, child: Text(links, style: const TextStyle(fontSize: 12, color: Colors.grey))),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rechts, style: TextStyle(fontSize: 12, color: farbe, fontWeight: farbe != null ? FontWeight.bold : null)),
                  if (hinweis != null)
                    Text(hinweis, style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ],
        ),
      ));
    }

    zeile('Netz', e.generation, farbe: _generationsfarbe(e.generation));

    // Der Ort gehört zur Beweiskraft: die Untergrenze der Bundesnetzagentur
    // hängt an der Haushaltsdichte der Rasterzelle, in der gemessen wurde.
    final ort = e.adresse;
    if (ort != null && ort.isNotEmpty) {
      zeile('Ort', ort,
          hinweis: e.ortFrisch
              ? null
              : 'zuletzt bekannte Position — kein aktuelles GPS-Signal');
    }

    // Das eigentliche Argument: was das Netz selbst zu können behauptet, neben
    // dem, was tatsächlich ankam.
    final gemeldet = e.gemeldetDownMbps;
    if (gemeldet != null && gemeldet > 0) {
      final anteil = e.downloadMbps / gemeldet * 100;
      zeile('Netz meldet', '${gemeldet.toStringAsFixed(0)} Mbit/s',
          hinweis: 'gemessen: ${e.downloadMbps.toStringAsFixed(1)} Mbit/s '
              '(${anteil.toStringAsFixed(0)} %)');
    }

    if (netz != null) {
      zeile('Betreiber', netz['operator'] as String?);
      final rsrp = netz['nr_ss_rsrp'] ?? netz['lte_rsrp'];
      final sinr = netz['nr_ss_sinr'] ?? netz['lte_rssnr'];
      if (rsrp != null) zeile('Signal', '$rsrp dBm${sinr != null ? '  ·  SINR $sinr dB' : ''}');
      zeile('Zelle', netz['zelle_typ'] != null
          ? '${netz['zelle_typ']}  ·  PCI ${netz['zelle_pci'] ?? '?'}  ·  TAC ${netz['zelle_tac'] ?? '?'}'
          : null);
      zeile('WLAN', netz['wlan_ssid'] as String?);
      if (netz['hat_telefon_recht'] == false && Platform.isAndroid) {
        zeile('Hinweis', 'Ohne Telefon-Berechtigung meldet Android bei 5G-NSA nur „LTE".',
            farbe: Colors.orange.shade800);
      }
    }

    // Latenz: Minimum und Maximum gehören dazu. Das Minimum ist der einzige
    // handshake-freie Wert, das Maximum zeigt den Aussetzer, den die mittlere
    // Abweichung wegmittelt.
    if (e.pingMaxMs > 0) {
      zeile('Ping min / Median / max',
          '${e.pingMinMs.toStringAsFixed(0)} · ${e.pingMedianMs.toStringAsFixed(0)}'
          ' · ${e.pingMaxMs.toStringAsFixed(0)} ms');
    }

    // Latenz unter Last: die Zahl, die erklärt, warum Videotelefonie nicht
    // geht, auch wenn der Durchsatz die Untergrenze knapp schafft.
    final lastMax = e.lastlatenzMaxMs;
    if (lastMax != null) {
      final anstieg = e.pingMinMs > 0 ? lastMax / e.pingMinMs : 0;
      zeile('Latenz unter Last', '${lastMax.toStringAsFixed(0)} ms',
          farbe: anstieg >= 10 ? Colors.red.shade700 : (anstieg >= 4 ? Colors.orange.shade800 : null),
          hinweis: e.pingMinMs > 0
              ? '${anstieg.toStringAsFixed(0)}× der Leerlauf-Latenz'
                  ' (${e.pingMinMs.toStringAsFixed(0)} ms)'
              : null);
    }

    // Ausdrücklich NICHT „Paketverlust": über TCP verschwindet echter Verlust
    // in Retransmits, 3 % Verlust ergäben hier zuverlässig 0,0 %. Eine nie
    // gemessene Größe als gemessen auszuweisen ist genau der Punkt, an dem die
    // Gegenseite nicht einen Wert, sondern die Methode angreift.
    if (e.latenzProben > 0 && (e.anfragenTimeout + e.anfragenHttpFehler) > 0) {
      zeile('Fehlgeschlagene Anfragen',
          '${e.anfragenTimeout + e.anfragenHttpFehler} von ${e.latenzProben}',
          farbe: e.anfragenHttpFehler > 0 ? Colors.orange.shade800 : null,
          hinweis: e.anfragenHttpFehler > 0
              ? '${e.anfragenHttpFehler} davon Serverfehler — nicht die Leitung'
              : 'kein Paketverlust — über TCP nicht messbar');
    }

    // Drei Geräte hängen am selben Konto. Hat ein zweites parallel gemessen,
    // ist der Wert womöglich selbstverschuldet niedrig — das muss dastehen,
    // sonst wandert ein hausgemachter Einbruch als Beleg gegen Telekom in die
    // Reihe.
    if (!e.alleine) {
      zeile('Achtung', 'Ein anderes Gerät hat gleichzeitig gemessen',
          farbe: Colors.orange.shade800,
          hinweis: 'Der Wert kann dadurch zu niedrig sein');
    } else if (!e.koordiniert) {
      zeile('Hinweis', 'Abstimmung mit den anderen Geräten nicht erreichbar',
          farbe: Colors.orange.shade800,
          hinweis: 'Ein paralleler Lauf lässt sich nicht ausschließen');
    }
    // Ein sehr kurzes Messfenster heißt: die Übertragung war zu schnell vorbei,
    // um den TCP-Slow-Start hinter sich zu lassen. Der Wert ist dann weich, und
    // das gehört dazugesagt statt kaschiert.
    if (e.erfolgreich && e.downloadFensterSekunden < 0.5) {
      zeile('Messfenster', '${e.downloadFensterSekunden.toStringAsFixed(2)} s',
          farbe: Colors.orange.shade800,
          hinweis: 'sehr kurz — Download-Wert eher zu niedrig');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: zeilen);
  }

  /// Zeigt nicht nur den Schalter, sondern ob der Takt tatsächlich läuft.
  ///
  /// Der Schalter allein sagt nichts: WorkManager-Jobs verschwinden unter
  /// Android still (Force Stop, Akku-Optimierung), und dass seit Tagen nichts
  /// mehr gemessen wurde, sähe man sonst erst an der Lücke im Diagramm.
  Widget _automatikkarte() {
    final abgemeldet = _auto && Platform.isAndroid && !_jobLaeuft;
    final ueberfaellig = _auto &&
        _letzteMessung != null &&
        DateTime.now().difference(_letzteMessung!) > const Duration(hours: 2);

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            value: _auto,
            onChanged: _autoUmschalten,
            title: const Text('Automatisch alle 30 Minuten messen'),
            subtitle: Text(
              !_auto
                  ? 'Aus — es entsteht keine Messreihe.'
                  : abgemeldet
                      ? 'Eingeschaltet, aber beim System nicht angemeldet — '
                          'nach einem Force Stop passiert das. App neu starten.'
                      : 'Läuft. Heute ${_volumenHeute.toStringAsFixed(0)} von '
                          '$_volumenBudget MB verbraucht.',
              style: TextStyle(
                fontSize: 12,
                color: abgemeldet ? Colors.orange.shade800 : null,
              ),
            ),
            secondary: const Icon(Icons.schedule),
          ),
          // ⚠️ Ohne Akku-Ausnahme friert Android den Takt im Ruhezustand ein.
          // In der Nacht auf den 08.08.2026 sind so neun Stunden ausgefallen —
          // und zwar die Nachtstunden, in denen die Leitung am wenigsten
          // belastet ist. Die Lücke steht im Diagramm und sieht aus wie eine
          // ausgesuchte Stichprobe.
          if (_auto && Platform.isAndroid && !_akkuAusnahme)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.battery_alert, size: 16, color: Colors.red.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Akku-Optimierung aktiv. Android streckt den Takt nachts '
                      'auf Stunden — zuletzt fielen neun Stunden am Stück aus.',
                      style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final bote = ScaffoldMessenger.of(context);
                      final r = await TerminSmsGatewayService
                          .requestBatteryExemption();
                      final jetzt = await TerminSmsGatewayService.isBatteryExempt();
                      if (!mounted) return;
                      setState(() => _akkuAusnahme = jetzt);
                      if (!jetzt) {
                        bote.showSnackBar(SnackBar(
                          content: Text(r == 'no_dialog' || r == 'unsupported'
                              ? 'Das Gerät zeigt den Dialog nicht. In den '
                                  'Einstellungen unter Apps → ICD360S → Akku '
                                  'auf „Unbeschränkt" stellen.'
                              : 'Noch nicht erteilt — im Dialog „Zulassen" wählen.'),
                          duration: const Duration(seconds: 8),
                        ));
                      }
                    },
                    child: const Text('Erlauben'),
                  ),
                ],
              ),
            ),
          // ⚠️ Ohne „immer erlauben" liefert Android im Hintergrund GAR KEINE
          // Position — die Anfrage läuft stumm in den Timeout. In den ersten 38
          // Produktionsläufen waren deshalb 36 Rückfälle auf einen Stunden alten
          // Fix, der auf der Karte trotzdem als Messort erschien.
          if (_auto && Platform.isAndroid && !_hintergrundOrtung)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.location_off, size: 16, color: Colors.orange.shade800),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Ortung nur „während der Nutzung" erlaubt. Die '
                      'Hintergrundmessungen tragen dann eine veraltete Position.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final ok = await SpeedtestService.hintergrundOrtungAnfragen();
                      if (!mounted) return;
                      setState(() => _hintergrundOrtung = ok);
                      if (!ok) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Android fragt das getrennt ab: in den '
                              'App-Einstellungen unter Berechtigungen → '
                              'Standort auf „Immer zulassen" stellen.'),
                          duration: Duration(seconds: 8),
                        ));
                      }
                    },
                    child: const Text('Erlauben'),
                  ),
                ],
              ),
            ),
          if (_rueckstand > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, size: 16, color: Colors.orange.shade800),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$_rueckstand Messung${_rueckstand == 1 ? '' : 'en'} noch nicht '
                      'eingereicht — werden beim nächsten erfolgreichen Lauf nachgereicht.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
          if (_auto)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(
                    ueberfaellig ? Icons.warning_amber : Icons.check_circle_outline,
                    size: 16,
                    color: ueberfaellig ? Colors.orange.shade800 : Colors.green.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _letzteMessung == null
                          ? 'Noch keine Messung auf diesem Gerät gelaufen.'
                          : ueberfaellig
                              ? 'Zuletzt ${_vorZeit(_letzteMessung!)} — das ist '
                                  'überfällig. Android streckt den Takt im '
                                  'Ruhezustand; Akku-Optimierung prüfen.'
                              : 'Zuletzt ${_vorZeit(_letzteMessung!)}'
                                  '${_naechsteMessung != null ? ', nächste gegen ${_uhrzeit(_naechsteMessung!)}' : ''}.',
                      style: TextStyle(
                        fontSize: 12,
                        color: ueberfaellig ? Colors.orange.shade800 : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _vorZeit(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'gerade eben';
    if (d.inMinutes < 60) return 'vor ${d.inMinutes} Min.';
    if (d.inHours < 24) return 'vor ${d.inHours} Std.';
    return 'vor ${d.inDays} Tagen';
  }

  String _uhrzeit(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _geraetewahl(List<Map<String, dynamic>> geraete) => SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: const Text('Alle Geräte'),
                selected: _geraetKey == null,
                onSelected: (_) { setState(() => _geraetKey = null); _reiheLaden(); },
              ),
            ),
            for (final g in geraete)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  // Bauform als Symbol: bei drei gleichzeitig angemeldeten
                  // Geräten sagen drei Namen allein nicht, welches an der
                  // Telekom-SIM hängt — und um dessen Leitung geht es.
                  avatar: Icon(_bauformIcon(g['bauform'] as String?), size: 16),
                  label: Text(_geraetLabel(g)),
                  selected: _geraetKey == g['geraet_key'],
                  onSelected: (_) {
                    setState(() => _geraetKey = g['geraet_key'] as String?);
                    _reiheLaden();
                  },
                ),
              ),
          ],
        ),
      );

  Widget _zeitraumwahl() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in _zeitraeume.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: _zeitraum == e.key,
              onSelected: (_) { setState(() => _zeitraum = e.key); _reiheLaden(); },
            ),
        ],
      );

  /// Farben für den Mehrgeräte-Fall. Bewusst gut unterscheidbar auch bei
  /// Rot-Grün-Schwäche (kein Rot/Grün-Paar) — Rot bleibt der Zusage-Linie
  /// vorbehalten.
  static const _geraetefarben = <Color>[
    Color(0xFF1565C0), Color(0xFFEF6C00), Color(0xFF6A1B9A),
    Color(0xFF00838F), Color(0xFF827717), Color(0xFF4E342E),
  ];

  Widget _diagramm() {
    final punkte = (_reihe?['punkte'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (punkte.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: Text('Noch keine Messungen in diesem Zeitraum')),
        ),
      );
    }

    // Bei „Alle Geräte" liefert der Server die Punkte nach Zeit sortiert und
    // damit zwischen den Geräten verschränkt. Als eine Linie gezeichnet würde
    // sie zwischen Tablet und Desktop hin- und herspringen und nichts aussagen
    // — deshalb je Gerät eine eigene Reihe.
    final geraeteImBild = <String>{
      for (final p in punkte) (p['geraet'] ?? '').toString(),
    }.toList();
    final mehrere = geraeteImBild.length > 1;

    final namen = <String, String>{
      for (final g in (_reihe?['geraete'] as List?)?.cast<Map<String, dynamic>>() ?? const [])
        (g['geraet_key'] ?? '').toString():
            (g['name'] ?? g['modell'] ?? 'Gerät').toString(),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: Column(
          children: [
            SizedBox(
              height: 240,
              child: CustomPaint(
                size: Size.infinite,
                painter: _ReihenPainter(
                  punkte: punkte,
                  geraeteReihenfolge: geraeteImBild,
                  farben: _geraetefarben,
                  schwelle: _bewertung,
                  dunkel: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (!mehrere) ...[
                  _legende('Download', Colors.blue.shade700),
                  _legende('Upload', Colors.green.shade700),
                ] else
                  // Bei mehreren Geräten steht die Farbe für das Gerät; Upload
                  // bleibt weg, sonst sind es doppelt so viele Linien wie
                  // ablesbar wären.
                  for (var i = 0; i < geraeteImBild.length; i++)
                    _legende(
                      '${namen[geraeteImBild[i]] ?? 'Gerät ${i + 1}'} (Download)',
                      _geraetefarben[i % _geraetefarben.length],
                    ),
                if (_bewertung > 0)
                  _legende('Untergrenze (${_bewertung.toStringAsFixed(0)})', Colors.red.shade400),
              ],
            ),
            if (_reihe?['verdichtet'] == true)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Punkte zusammengefasst — die Statistik unten rechnet trotzdem '
                  'mit allen Messungen.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Karte der Messorte, eingefärbt nach Download.
  ///
  /// Nur für Zeiträume mit Rohdaten (bis zwei Wochen): ab einem Monat kommen
  /// Rollups, und ein über einen Tag gemittelter Ort wäre ein Punkt, an dem nie
  /// gemessen wurde.
  Widget _karte() {
    final punkte = (_reihe?['punkte'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final mitOrt = punkte
        .where((p) => p['lat'] is num && p['lon'] is num)
        .toList();

    if (mitOrt.isEmpty) {
      final rollup = (_reihe?['quelle'] ?? '').toString().startsWith('rollup');
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.location_off_outlined, size: 18, color: Colors.grey.shade600),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rollup
                      ? 'Keine Karte über einen Monat hinaus: dort liefert der '
                          'Server zusammengefasste Werte, und ein gemittelter Ort '
                          'wäre eine Stelle, an der nie gemessen wurde.'
                      : 'Noch keine Messung mit Standort. Die Ortung wird beim '
                          'nächsten Durchlauf abgefragt.',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final orte = [
      for (final p in mitOrt)
        LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble())
    ];
    final mitte = LatLng(
      orte.map((o) => o.latitude).reduce((a, b) => a + b) / orte.length,
      orte.map((o) => o.longitude).reduce((a, b) => a + b) / orte.length,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 260,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: mitte,
                initialZoom: orte.length == 1 ? 15 : 12,
                interactionOptions: const InteractionOptions(
                  // Ohne das schluckt die Karte jede vertikale Wischgeste und
                  // die Seite darunter lässt sich nicht mehr scrollen.
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                // ⚠️ NICHT direkt von tile.openstreetmap.org.
                //
                // Der gesamte Speedtest verzichtet bewusst auf Fremdanbieter —
                // und ausgerechnet die Karte hätte OpenStreetMap bei jeder
                // Ansicht Zeitpunkt, IP und Ausschnitt geliefert, also genau
                // die Information, wo der Verein misst. Dieselbe Erwägung, aus
                // der die Adressauflösung schon über den eigenen Server läuft.
                // `tiles.php` holt die Kachel serverseitig und hält sie 30 Tage
                // vor; nach außen sieht OSM nur unseren Server.
                TileLayer(
                  urlTemplate: '${ApiService.baseUrl}/speedtest/tiles.php'
                      '?z={z}&x={x}&y={y}',
                  userAgentPackageName: 'de.icd360sev.vorsitzer',
                  tileProvider: NetworkTileProvider(headers: _kachelKopf),
                ),
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < mitOrt.length; i++)
                      Marker(
                        point: orte[i],
                        width: 14,
                        height: 14,
                        child: Tooltip(
                          message: '${(mitOrt[i]['down'] as num?)?.toStringAsFixed(0) ?? '?'}'
                              ' Mbit/s\n${mitOrt[i]['ort'] ?? ''}\n${mitOrt[i]['t']}',
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _punktfarbe((mitOrt[i]['down'] as num?)?.toDouble() ?? 0),
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${mitOrt.length} Messorte · rot = unter '
                    '${_bewertung.toStringAsFixed(0)} Mbit/s',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                // Kartendaten gehören ausgewiesen — die ODbL verlangt das.
                const Text('© OpenStreetMap',
                    style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _punktfarbe(double down) {
    if (_bewertung <= 0) return Colors.blue.shade700;
    if (down < _bewertung) return Colors.red.shade600;
    if (down < _bewertung * 2) return Colors.orange.shade700;
    return Colors.green.shade700;
  }

  Widget _legende(String text, Color farbe) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 3, color: farbe),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11)),
        ],
      );

  /// Liest eine nach Index geordnete Reihe — egal ob als JSON-Objekt oder als
  /// JSON-Liste geliefert.
  ///
  /// ⚠️ Diese Unterscheidung ist keine Kür. PHP kennt nur EINEN Array-Typ:
  /// `array_fill(0, 24, …)` hat die lückenlosen Schlüssel 0..23, und
  /// `json_encode` macht daraus eine **Liste**, nicht ein Objekt. Fehlt auch
  /// nur eine Stunde, wird plötzlich ein Objekt daraus. Ein `as Map?` auf einer
  /// Liste liefert nicht `null`, sondern **wirft** — der Bildschirm blieb
  /// dadurch beim Aufbau hängen und zeigte nur eine graue Fläche. Am 05.08.2026
  /// in der Produktion passiert, unmittelbar nach dem Ausrollen.
  ///
  /// Der Server kodiert inzwischen ausdrücklich als Objekt. Sich darauf allein
  /// zu verlassen wäre trotzdem falsch: die Kodierung ist ein Nebeneffekt der
  /// Schlüssel, kein Vertrag, und der nächste Umbau dort dreht sie lautlos um.
  /// Empfangsgüte gegen Durchsatz.
  ///
  /// Die Funkdaten wurden von Anfang an bei jeder Messung erhoben und von
  /// niemandem ausgewertet. Dabei beantworten sie den Einwand, der garantiert
  /// als Erstes kommt: „Sie hatten eben schlechten Empfang." Erst diese
  /// Gegenüberstellung trennt schwaches Signal von **gutem Signal und trotzdem
  /// langsam** — und nur das Zweite lässt sich nicht mehr auf das Gerät, den
  /// Standort oder die Hülle schieben.
  Widget _funkkarte(Map<String, dynamic> s) {
    final funk = speedtestAlsMap(speedtestAlsMap(s['profil'])?['funk']);
    if (funk == null) return const SizedBox.shrink();

    const namen = {
      'gut': 'gut (ab −85 dBm)',
      'mittel': 'mittel (−85 bis −100)',
      'schwach': 'schwach (unter −100)',
    };
    final zeilen = <Widget>[];
    for (final k in ['gut', 'mittel', 'schwach']) {
      final e = speedtestAlsMap(funk[k]);
      final n = (e?['n'] as num?)?.toInt() ?? 0;
      if (n == 0) continue;
      final down = (e?['down'] as num?)?.toDouble();
      zeilen.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 170, child: Text(namen[k]!, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: LinearProgressIndicator(
              value: down == null ? 0 : (down / max(_maximal, 1)).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              color: k == 'schwach' ? Colors.orange : _accent,
            ),
          ),
          SizedBox(
            width: 96,
            child: Text('${down?.toStringAsFixed(0) ?? '–'} Mbit/s',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 46,
            child: Text('n=$n',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ),
        ]),
      ));
    }
    if (zeilen.isEmpty) return const SizedBox.shrink();

    final gut = speedtestAlsMap(funk['gut'])?['down'] as num?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Empfang und Durchsatz',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Durchschnittlicher Download je Empfangsklasse',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 10),
            ...zeilen,
            if (gut != null && gut < _bewertung) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Auch bei gutem Empfang bleibt der Schnitt mit '
                  '${gut.toStringAsFixed(0)} Mbit/s unter der Untergrenze von '
                  '${_bewertung.toStringAsFixed(0)}. Der Einwand „schlechter '
                  'Empfang" trägt hier also nicht.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Tageszeit, Wochentag und Bruchstelle.
  ///
  /// Ein Mittelwert über Monate kann die eigentliche Frage prinzipiell nicht
  /// beantworten: nicht „wie schnell im Schnitt", sondern **wann bricht es
  /// ein**. Die vorhandene Stundenstatistik zählte bisher nur, wie viele
  /// Messungen je Stunde vorlagen — eine Aussage über die Abdeckung, nicht
  /// über die Leitung.
  Widget _profilkarte(Map<String, dynamic> s) {
    final profil = speedtestAlsMap(s['profil']);
    if (profil == null) return const SizedBox.shrink();

    final werte = speedtestNachIndex(profil['stunde_down']);
    final bruchVorab = speedtestAlsMap(s['bruchstelle']);
    // ⚠️ Nicht abbrechen, nur weil das Stundenprofil fehlt. Ab einem Monat
    // kommt die Reihe aus Rollups, und dort ist das Profil je nach Quelle
    // nicht herleitbar — die BRUCHSTELLE steht aber im selben Karten-Body und
    // verschwand damit gleich mit. Ausgerechnet über lange Zeiträume, wo sie
    // als Einzige überhaupt etwas aussagt.
    if (werte.isEmpty && bruchVorab == null) return const SizedBox.shrink();

    final hoechst = werte.isEmpty ? 0.0 : werte.values.reduce(max);
    final schlechteste = werte.isEmpty
        ? null
        : werte.entries.reduce((a, b) => a.value <= b.value ? a : b);
    final bruch = bruchVorab;
    final luecken = speedtestAlsMap(profil['luecken']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Wann bricht es ein?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Ø Download je Tagesstunde',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            // Fehlt das Profil, sagen warum — statt eine leere Fläche zu
            // zeigen, die wie ein Defekt aussieht.
            if (werte.isEmpty)
              Text(
                'Für diesen Zeitraum liegt kein Stundenprofil vor: die Reihe '
                'kommt hier aus zusammengefassten Werten, und die tragen die '
                'Tagesstunde nicht in jedem Fall mit'
                '${luecken != null && luecken.isNotEmpty ? ' (${luecken.entries.map((e) => '${e.key}: ${e.value}').join(', ')})' : ''}'
                '. Über kürzere Zeiträume ist es vorhanden.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              )
            else
            SizedBox(
              height: 84,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var h = 0; h < 24; h++)
                    Expanded(
                      child: Tooltip(
                        message: werte[h] == null
                            ? '$h Uhr: keine Messung'
                            : '$h Uhr: ${werte[h]!.toStringAsFixed(0)} Mbit/s',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: werte[h] == null || hoechst <= 0
                                    ? 2
                                    : (werte[h]! / hoechst * 64).clamp(2.0, 64.0),
                                decoration: BoxDecoration(
                                  // Unter der Untergrenze auffällig, damit die
                                  // kritischen Stunden nicht erst ausgerechnet
                                  // werden müssen.
                                  color: werte[h] == null
                                      ? Colors.grey.shade300
                                      : (werte[h]! < _bewertung
                                          ? Colors.red.shade400
                                          : _accent),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(2)),
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (h % 6 == 0)
                                Text('$h',
                                    style: TextStyle(
                                        fontSize: 9, color: Colors.grey.shade600))
                              else
                                const SizedBox(height: 11),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (schlechteste != null) ...[
              const SizedBox(height: 10),
              Text(
                'Schlechteste Stunde: ${schlechteste.key} Uhr mit '
                '${schlechteste.value.toStringAsFixed(0)} Mbit/s.',
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if (bruch != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Auffällige Veränderung',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      'In Woche ${bruch['woche']} sprang der Wochenmedian von '
                      '${bruch['vorher']} auf ${bruch['nachher']} Mbit/s '
                      '(${(((bruch['aenderung'] as num?) ?? 0) * 100).toStringAsFixed(0)} %). '
                      'Lohnt den Abgleich mit Tarifwechsel, Netzumbau oder '
                      'Gerätetausch — der Zeitpunkt ist das Argument.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statistikkarte(Map<String, dynamic> s) {
    final unter = speedtestAlsMap(s['unter_schwelle']);
    // ⚠️ NICHT `as Map?`. Ohne bewertbare Läufe ist `generationen` serverseitig
    // ein leeres PHP-Array, und das kodiert json_encode als `[]` — eine LISTE.
    // Ein `as Map?` darauf liefert nicht null, sondern wirft, und der ganze
    // Bildschirm bleibt grau. Siehe [_nachIndex].
    final generationen = speedtestAlsMap(s['generationen']) ?? const {};

    String mb(dynamic v) => v == null ? '–' : '${(v as num).toStringAsFixed(1)} Mbit/s';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_zeitraeume[_zeitraum]} — ${s['n']} Messungen',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            // Ohne Abdeckung wäre „unvollständig, also ausgesucht" der erste
            // Einwand. Mit ihr steht dort „vollständig, mit ausgewiesener
            // Abdeckung".
            if (s['abdeckung'] != null)
              Builder(builder: (_) {
                final a = speedtestAlsMap(s['abdeckung']) ?? const {};
                final anteil = ((a['anteil'] as num?) ?? 0) * 100;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Abdeckung: ${a['vorhanden']} von ${a['erwartet']} erwarteten '
                    'Läufen (${anteil.toStringAsFixed(0)} %)',
                    style: TextStyle(
                      fontSize: 12,
                      color: anteil < 70 ? Colors.orange.shade800 : Colors.grey.shade700,
                    ),
                  ),
                );
              }),
            const SizedBox(height: 12),
            _statzeile('Download Ø', mb(s['down_avg'])),
            _statzeile('Download Median', mb(s['down_p50'])),
            // Der Wert, der eine Beschwerde trägt: so schlecht war es in den
            // schlechtesten 5 % der Messungen.
            _statzeile('Schlechteste 5 %', s['down_p05'] == null
                ? '–'
                : 'unter ${mb(s['down_p05'])}'),
            _statzeile('Download min / max', '${mb(s['down_min'])}  /  ${mb(s['down_max'])}'),
            _statzeile('Upload Ø', mb(s['up_avg'])),
            _statzeile('Ping Ø', s['ping_avg'] == null ? '–' : '${s['ping_avg']} ms'),
            if ((s['fehler'] as num? ?? 0) > 0)
              _statzeile('Fehlgeschlagen',
                  '${s['fehler']} (${((s['fehlerquote'] as num) * 100).toStringAsFixed(1)} %)',
                  farbe: Colors.orange.shade800),
            if (generationen.isNotEmpty)
              _statzeile('Netz',
                  generationen.entries.map((e) => '${e.key}: ${e.value}').join('  ·  ')),
            if (unter != null) ...[
              const Divider(height: 24),
              _massstabkarte(s, unter),
            ] else ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Kein Bewertungsmaßstab hinterlegt — ohne Höchstgeschwindigkeit '
                      'und Haushaltsdichte lässt sich keine Untergrenze berechnen.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  TextButton(onPressed: _schwelleSetzen, child: const Text('Festlegen')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Die Auswertung gegen den Maßstab der Bundesnetzagentur.
  ///
  /// Zwei Zahlen, und die Reihenfolge ist Absicht. Oben steht die
  /// TAGESSICHT — danach fragt die Allgemeinverfügung 35/2026 tatsächlich:
  /// ein Tag gilt schon als in Ordnung, wenn eine einzige Messung die
  /// Untergrenze erreicht. Der Anteil einzelner Messungen darunter steht
  /// bewusst nur als Zusatz, weil er die Lage strenger darstellt, als der
  /// Maßstab es tut, und allein zitiert unredlich wäre.
  Widget _massstabkarte(Map<String, dynamic> s, Map<String, dynamic> unter) {
    final tage = speedtestAlsMap(s['tagesbestwerte']);
    final tageUnter = (tage?['tage_unter'] as num?)?.toInt() ?? 0;
    final tageGesamt = (tage?['tage_gesamt'] as num?)?.toInt() ?? 0;
    final beanstandet = tageUnter > 0;
    final messanteil = ((unter['anteil'] as num?) ?? 0) * 100;

    // Bei mehreren Geräten steht oben das am stärksten betroffene — der
    // Maßstab prüft einen Zugang, nicht einen Gerätepark. Welches gemeint ist,
    // muss dabeistehen, sonst liest man die Zahl der falschen Leitung zu.
    final mehrere = tage?['mehrere_geraete'] == true;
    String? betroffen;
    if (mehrere) {
      final key = tage?['betrifft_geraet'];
      final geraete = (_reihe?['geraete'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      for (final g in geraete) {
        if (g['geraet_key'] == key) {
          betroffen = (g['name'] ?? g['modell'] ?? 'Gerät').toString();
          break;
        }
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: beanstandet ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Untergrenze ${_bewertung.toStringAsFixed(0)} Mbit/s '
            '(${_dichte.prozent} von ${_maximal.toStringAsFixed(0)})',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          Text(
            tageGesamt == 0
                ? 'Noch keine vollständigen Tage'
                : beanstandet
                    ? 'An $tageUnter von $tageGesamt Tagen blieb auch der beste '
                        'Wert des Tages darunter'
                    : 'An allen $tageGesamt Tagen wurde die Untergrenze '
                        'mindestens einmal erreicht',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: beanstandet ? Colors.red.shade900 : Colors.green.shade900,
            ),
          ),
          if (betroffen != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Gerät mit dem höchsten Anteil: $betroffen — je Gerät getrennt '
                'gerechnet, weil der Maßstab einen Zugang prüft und nicht mehrere '
                'zusammen.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'So misst die Bundesnetzagentur: ein Tag zählt bereits als '
            'vertragsgemäß, wenn eine einzige Messung die Untergrenze schafft.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          // ── Der eigentliche Maßstab der Verfügung ────────────────────────
          //
          // Die Norm kennt keinen „Anteil beanstandeter Tage", sondern ein
          // Fenster: drei von fünf aufeinanderfolgenden Messtagen, innerhalb
          // von 14 Kalendertagen. Zwanzig schlechte Tage über ein Jahr verteilt
          // erfüllen sie NIE, dieselben zwanzig am Stück erfüllen sie mehrfach.
          // Ohne diese Zeile hätte der Anteil oben nach mehr ausgesehen, als
          // er rechtlich hergibt — oder nach weniger.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tage?['vfg_erfuellt'] == true
                  ? Colors.red.shade100
                  : Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tage?['vfg_erfuellt'] == true
                      ? 'Maßstab der Vfg 35/2026 erfüllt'
                      : 'Maßstab der Vfg 35/2026 noch nicht erfüllt',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: tage?['vfg_erfuellt'] == true
                        ? Colors.red.shade900
                        : Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tage?['vfg_erfuellt'] == true
                      ? 'Es gibt ${tage?['vfg_anzahl']} Fenster aus fünf Messtagen, '
                          'in denen an mindestens drei Tagen auch der beste Wert '
                          'unter der Untergrenze blieb — erstmals '
                          '${speedtestAlsMap(tage?['vfg_erstes'])?['von']} bis '
                          '${speedtestAlsMap(tage?['vfg_erstes'])?['bis']}. '
                          'Ab jetzt lohnt die amtliche Messung mit der App '
                          '„Nachweisverfahren Mobilfunk".'
                      : 'Verlangt sind drei von fünf aufeinanderfolgenden '
                          'Messtagen unter der Untergrenze, innerhalb von 14 '
                          'Kalendertagen. Solange das nicht zutrifft, würde die '
                          'amtliche Messung nichts ergeben.',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          if (s['nicht_bewertbar'] != null) ...[
            const SizedBox(height: 8),
            Builder(builder: (_) {
              final nb = speedtestAlsMap(s['nicht_bewertbar']) ?? const {};
              final wlan = (nb['wlan'] as num?)?.toInt() ?? 0;
              final nurLatenz = (nb['nur_latenz'] as num?)?.toInt() ?? 0;
              final kurz = (nb['fenster_kurz'] as num?)?.toInt() ?? 0;
              final unbekannt = (nb['netz_unbekannt'] as num?)?.toInt() ?? 0;
              if (wlan + nurLatenz + kurz + unbekannt == 0) {
                return const SizedBox.shrink();
              }
              // Ausdrücklich benennen. Eine still gekürzte Grundgesamtheit ist
              // genau der Vorwurf, den die Gegenseite erheben würde.
              return Text(
                'Nicht in die Bewertung eingeflossen: '
                '${[
                  if (wlan > 0) '$wlan über WLAN',
                  if (nurLatenz > 0) '$nurLatenz ohne Massenübertragung',
                  if (kurz > 0) '$kurz mit zu kurzem Messfenster',
                  // „Keine Netzangabe" ist NICHT dasselbe wie WLAN — sonst
                  // stünde eine Behauptung über etwas, das niemand gemessen hat.
                  if (unbekannt > 0) '$unbekannt ohne Netzangabe',
                ].join(' · ')}.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              );
            }),
          ],
          const SizedBox(height: 8),
          Text(
            'Zum Vergleich: ${messanteil.toStringAsFixed(1)} % aller '
            'Einzelmessungen lagen darunter '
            '(${(unter['unter'] as num?)?.toStringAsFixed(0) ?? '0'} von '
            '${unter['gesamt']}).',
            style: const TextStyle(fontSize: 12),
          ),
          const Divider(height: 20),
          // Muss dastehen, sonst liest jemand aus der roten Fläche einen
          // Anspruch heraus, den der Verein nicht hat — und übersieht
          // gleichzeitig die Wege, die ihm offenstehen.
          Text(
            'Keine Minderung nach TKG: § 57 Abs. 4 gilt nur für Verbraucher, '
            'und § 71 Abs. 3 zählt § 57 nicht auf. Die zugesagten Werte sind '
            'aber trotzdem Vertragsinhalt (§ 54 Abs. 4 i.V.m. § 55 TKG, beide '
            'in der Liste des § 71 Abs. 3). Durchsetzbar über § 314 BGB '
            '(Kündigung aus wichtigem Grund), § 320 BGB (Entgelt einbehalten) '
            'und die Schlichtung nach § 68 TKG, die dem Endnutzer offensteht — '
            'nicht nur dem Verbraucher.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Text(
            'Diese Messreihe ersetzt nicht das Nachweisverfahren der '
            'Bundesnetzagentur. Für BGB-Ansprüche gilt aber freie '
            'Beweiswürdigung (§ 286 ZPO) — dort ist eine lückenlose Reihe '
            'aussagekräftiger als 30 Einzelmessungen. Vor rechtlichen '
            'Schritten anwaltlich prüfen lassen.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _statzeile(String links, String rechts, {Color? farbe}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 170, child: Text(links, style: const TextStyle(fontSize: 13, color: Colors.grey))),
            Expanded(child: Text(rechts, style: TextStyle(fontSize: 13, color: farbe))),
          ],
        ),
      );

  String _phasenname(SpeedtestPhase p) => switch (p) {
        SpeedtestPhase.latenz => 'Latenz wird gemessen …',
        SpeedtestPhase.download => 'Download wird gemessen …',
        SpeedtestPhase.upload => 'Upload wird gemessen …',
      };

  IconData _bauformIcon(String? bauform) => switch (bauform) {
        'tablet' => Icons.tablet_android,
        'handy' => Icons.smartphone,
        'laptop' => Icons.laptop_mac,
        'desktop' => Icons.desktop_windows,
        // Ausdrücklich ein eigenes Symbol für „nicht bestimmbar" statt eines
        // geratenen: unter Windows gibt die Plattform nichts her, und ein
        // falsch beschriftetes Gerät führt beim Auswerten zur falschen Leitung.
        _ => Icons.devices_other,
      };

  /// Name plus das, was ihn unterscheidbar macht — etwa
  /// „Galaxy Tab (Tablet · GrapheneOS)".
  String _geraetLabel(Map<String, dynamic> g) {
    final name = (g['name'] ?? g['modell'] ?? 'Gerät').toString();
    final teile = <String>[];
    final bauform = (g['bauform'] ?? '').toString();
    if (bauform.isNotEmpty && bauform != 'unbekannt') {
      teile.add(switch (bauform) {
        'tablet' => 'Tablet',
        'handy' => 'Handy',
        'laptop' => 'Laptop',
        'desktop' => 'Desktop',
        _ => bauform,
      });
    }
    final variante = (g['os_variante'] ?? '').toString();
    if (variante.isNotEmpty && variante != 'unbestimmt') teile.add(variante);
    return teile.isEmpty ? name : '$name (${teile.join(' · ')})';
  }

  Color? _generationsfarbe(String g) => switch (g) {
        '5G-SA' || '5G+' => Colors.green.shade700,
        '5G-NSA' => Colors.lightGreen.shade800,
        'LTE-CA' || 'LTE+' => Colors.blue.shade700,
        'LTE' => Colors.orange.shade800,
        '3G' || '2G' => Colors.red.shade700,
        _ => null,
      };
}

/// Ordnet die Punkte ihrem Gerät zu und liefert je Gerät die Indizes in
/// [punkte], in unveränderter Zeitreihenfolge.
///
/// Ausgelagert und öffentlich, weil daran ein echter Darstellungsfehler hängt:
/// bei „Alle Geräte" kommen die Punkte nach Zeit sortiert und damit zwischen
/// den Geräten verschränkt an. Wer sie über einen Kamm zeichnet, bekommt eine
/// Linie, die zwischen Mobilfunk- und Festnetzleitung hin- und herspringt.
/// Der Fehler sieht auf den ersten Blick nach einer unruhigen Leitung aus —
/// deshalb ist er getestet.
Map<String, List<int>> gruppiereNachGeraet(List<Map<String, dynamic>> punkte) {
  final proGeraet = <String, List<int>>{};
  for (var i = 0; i < punkte.length; i++) {
    proGeraet.putIfAbsent((punkte[i]['geraet'] ?? '').toString(), () => []).add(i);
  }
  return proGeraet;
}

/// Zeichnet den Verlauf — eine Reihe JE GERÄT.
///
/// Von Hand statt mit einem Diagramm-Paket: das Projekt hat keins, und alle
/// vorhandenen Darstellungen (Wetter, Gesundheitsprofil, eGK) sind ebenso
/// gemalt. Eine Abhängigkeit nur hierfür wäre der Ausreißer.
///
/// Die Trennung nach Gerät ist nicht kosmetisch: der Server liefert bei
/// „Alle Geräte" nach Zeit sortiert, also zwischen den Geräten verschränkt.
/// Über einen Kamm gezeichnet ergäbe das eine Linie, die zwischen der
/// Mobilfunkleitung des Tablets und der Festnetzleitung des Desktops hin- und
/// herspringt — optisch ein Zickzack, inhaltlich nichts.
class _ReihenPainter extends CustomPainter {
  final List<Map<String, dynamic>> punkte;

  /// Gerätereihenfolge bestimmt die Farbzuordnung; muss zur Legende passen.
  final List<String> geraeteReihenfolge;
  final List<Color> farben;
  final double schwelle;
  final bool dunkel;

  _ReihenPainter({
    required this.punkte,
    required this.geraeteReihenfolge,
    required this.farben,
    required this.schwelle,
    required this.dunkel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (punkte.isEmpty) return;

    const links = 44.0, unten = 18.0, oben = 8.0, rechts = 4.0;
    final flaeche = Rect.fromLTRB(links, oben, size.width - rechts, size.height - unten);
    if (flaeche.width <= 0 || flaeche.height <= 0) return;

    double z(Map<String, dynamic> p, String k) => ((p[k] as num?) ?? 0).toDouble();

    // ⚠️ Die Skala richtet sich nach dem SCHNELLSTEN Punkt im Bild. Sind
    // mehrere Geräte zu sehen, drückt ein Desktop am Festnetz die Kurve des
    // Tablets an der Telekom-SIM optisch flach — und genau um deren Einbrüche
    // geht es. Deshalb wird beim Öffnen ein Mobilfunkgerät vorausgewählt
    // (siehe `_mobilesGeraetWaehlen`); die Skala bleibt damit im Regelfall die
    // dieses einen Zugangs.
    var hoechst = 0.0;
    for (final p in punkte) {
      hoechst = max(hoechst, max(z(p, 'down_max'), z(p, 'down')));
      hoechst = max(hoechst, z(p, 'up_max'));
    }
    // Die zugesagte Geschwindigkeit muss ins Bild passen, sonst sieht eine
    // Reihe, die weit darunter liegt, unauffällig aus.
    hoechst = max(hoechst, schwelle);
    if (hoechst <= 0) hoechst = 1;
    hoechst *= 1.1;

    final achsenfarbe = dunkel ? Colors.white24 : Colors.black26;
    final textfarbe = dunkel ? Colors.white54 : Colors.black54;

    // Raster + Beschriftung
    final raster = Paint()..color = achsenfarbe..strokeWidth = 0.5;
    for (var i = 0; i <= 4; i++) {
      final y = flaeche.bottom - flaeche.height * i / 4;
      canvas.drawLine(Offset(flaeche.left, y), Offset(flaeche.right, y), raster);
      final beschriftung = TextPainter(
        text: TextSpan(
          text: (hoechst * i / 4).toStringAsFixed(0),
          style: TextStyle(fontSize: 9, color: textfarbe),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      beschriftung.paint(canvas, Offset(flaeche.left - beschriftung.width - 4, y - 5));
    }

    // Die x-Achse läuft über die ZEIT, nicht über den Index. Bei mehreren
    // Geräten haben die Reihen unterschiedlich viele Punkte; über den Index
    // gezeichnet läge derselbe Zeitpunkt je Gerät woanders, und die Reihen
    // wären nicht mehr vergleichbar — was der einzige Zweck der Ansicht ist.
    final zeiten = <int>[];
    for (final p in punkte) {
      zeiten.add(DateTime.tryParse((p['t'] ?? '').toString())?.millisecondsSinceEpoch ?? 0);
    }
    final tVon = zeiten.reduce(min);
    final tBis = zeiten.reduce(max);
    final spanne = (tBis - tVon).toDouble();

    double x(int index) => spanne <= 0
        ? flaeche.center.dx
        : flaeche.left + flaeche.width * (zeiten[index] - tVon) / spanne;
    double y(double wert) => flaeche.bottom - (wert / hoechst) * flaeche.height;

    final proGeraet = gruppiereNachGeraet(punkte);
    final mehrere = proGeraet.length > 1;

    void linie(List<int> indizes, String schluessel, Color farbe, double breite) {
      if (indizes.isEmpty) return;
      final pfad = Path();
      for (var n = 0; n < indizes.length; n++) {
        final p = Offset(x(indizes[n]), y(z(punkte[indizes[n]], schluessel)));
        n == 0 ? pfad.moveTo(p.dx, p.dy) : pfad.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        pfad,
        Paint()
          ..color = farbe
          ..style = PaintingStyle.stroke
          ..strokeWidth = breite,
      );
    }

    if (!mehrere) {
      final indizes = proGeraet.values.first;

      // Min/Max-Band des Downloads: bei zusammengefassten Punkten zeigt es, wie
      // weit die Werte innerhalb eines Balkens auseinanderlagen. Ohne das würde
      // ein Mittelwert einen Einbruch verstecken.
      final band = Path();
      for (var n = 0; n < indizes.length; n++) {
        final p = Offset(x(indizes[n]), y(z(punkte[indizes[n]], 'down_max')));
        n == 0 ? band.moveTo(p.dx, p.dy) : band.lineTo(p.dx, p.dy);
      }
      for (var n = indizes.length - 1; n >= 0; n--) {
        band.lineTo(x(indizes[n]), y(z(punkte[indizes[n]], 'down_min')));
      }
      band.close();
      canvas.drawPath(band, Paint()..color = Colors.blue.withValues(alpha: 0.12));

      linie(indizes, 'down', Colors.blue.shade700, 1.6);
      linie(indizes, 'up', Colors.green.shade700, 1.6);
    } else {
      // Bei mehreren Geräten steht die Farbe für das Gerät. Kein Band und kein
      // Upload: das wären doppelt so viele Linien, wie sich auf einem
      // Telefondisplay noch auseinanderhalten lassen.
      for (var g = 0; g < geraeteReihenfolge.length; g++) {
        final indizes = proGeraet[geraeteReihenfolge[g]];
        if (indizes == null) continue;
        linie(indizes, 'down', farben[g % farben.length], 1.6);
      }
    }

    // Zugesagte Geschwindigkeit als gestrichelte Marke.
    if (schwelle > 0) {
      final yS = y(schwelle);
      final strich = Paint()
        ..color = Colors.red.shade400
        ..strokeWidth = 1.2;
      for (var xs = flaeche.left; xs < flaeche.right; xs += 8) {
        canvas.drawLine(Offset(xs, yS), Offset(min(xs + 4, flaeche.right), yS), strich);
      }
    }

    // Zeitachse: nur erster und letzter Punkt, mehr wird auf einem Telefon
    // ohnehin zu Matsch.
    void zeit(int index, double xPos, TextAlign ausrichtung) {
      final t = (punkte[index]['t'] ?? '').toString();
      if (t.length < 16) return;
      final tp = TextPainter(
        text: TextSpan(text: t.substring(0, 16), style: TextStyle(fontSize: 9, color: textfarbe)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(
        ausrichtung == TextAlign.left ? xPos : xPos - tp.width,
        size.height - unten + 4,
      ));
    }

    zeit(0, flaeche.left, TextAlign.left);
    if (punkte.length > 1) zeit(punkte.length - 1, flaeche.right, TextAlign.right);
  }

  @override
  bool shouldRepaint(covariant _ReihenPainter alt) =>
      alt.punkte != punkte ||
      alt.geraeteReihenfolge != geraeteReihenfolge ||
      alt.schwelle != schwelle ||
      alt.dunkel != dunkel;
}
