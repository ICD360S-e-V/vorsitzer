import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:icd_netinfo/icd_netinfo.dart';
import 'package:path_provider/path_provider.dart';

import '../services/api_service.dart';
import '../services/speedtest_service.dart';

/// Speedtest gegen den EIGENEN Server — kein Fremdanbieter ist beteiligt.
///
/// Zweck ist nicht die eine schöne Zahl, sondern die Reihe: wann bricht die
/// Leitung ein, wie oft, und auf welcher Mobilfunkgeneration hing das Gerät in
/// dem Moment. Deshalb misst die App alle 30 Minuten selbstständig weiter und
/// hält bis zu fünf Jahre vor.
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

  /// Geschätzte maximale Geschwindigkeit des Tarifs (300 bei Business Mobil L).
  double _maximal = kBusinessMobilLDownloadMax;
  SpeedtestDichte _dichte = SpeedtestDichte.mittel;

  /// Ausgewertet wird gegen [_maximal] × Prozentsatz der Haushaltsdichte —
  /// gegen die vollen 300 lägen praktisch alle Messungen darunter, und die
  /// Aussage wäre wertlos.
  double get _bewertung => _maximal * _dichte.anteil;

  bool _auto = false;
  bool _jobLaeuft = false;

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
    setState(() { _letztes = e; _misst = false; });
    await _reiheLaden();
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
      final name = 'speedtest_${_zeitraum}_${DateTime.now().millisecondsSinceEpoch}.$format';
      final datei = File('${ordner.path}/$name');
      await datei.writeAsBytes(antwort.bodyBytes);
      bote.showSnackBar(SnackBar(
        content: Text('Gespeichert: ${datei.path}'),
        action: SnackBarAction(
          label: 'Pfad kopieren',
          onPressed: () => Clipboard.setData(ClipboardData(text: datei.path)),
        ),
        duration: const Duration(seconds: 8),
      ));
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
    final statistik = (_reihe?['statistik'] as Map?)?.cast<String, dynamic>();

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
            ],
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
            if (statistik != null) _statistikkarte(statistik),
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
                const SizedBox(height: 12),
                _netzzeilen(e),
              ],
            ],
          ],
        ),
      ),
    );
  }

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

    zeile('Paketverlust', '${e.paketverlustProzent.toStringAsFixed(1)} %');

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

  Widget _automatikkarte() => Card(
        child: SwitchListTile(
          value: _auto,
          onChanged: _autoUmschalten,
          title: const Text('Automatisch alle 30 Minuten messen'),
          subtitle: Text(
            !_auto
                ? 'Aus — es entsteht keine Messreihe.'
                : _jobLaeuft || !Platform.isAndroid
                    ? 'Läuft. Rund 35 MB je Messung.'
                    : 'Eingeschaltet, aber beim System nicht angemeldet — '
                        'nach einem Force Stop passiert das. App neu starten.',
            style: TextStyle(
              fontSize: 12,
              color: _auto && Platform.isAndroid && !_jobLaeuft ? Colors.orange.shade800 : null,
            ),
          ),
          secondary: const Icon(Icons.schedule),
        ),
      );

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

  Widget _legende(String text, Color farbe) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 3, color: farbe),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11)),
        ],
      );

  Widget _statistikkarte(Map<String, dynamic> s) {
    final unter = (s['unter_schwelle'] as Map?)?.cast<String, dynamic>();
    final generationen = (s['generationen'] as Map?)?.cast<String, dynamic>() ?? const {};

    String mb(dynamic v) => v == null ? '–' : '${(v as num).toStringAsFixed(1)} Mbit/s';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_zeitraeume[_zeitraum]} — ${s['n']} Messungen',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
    final tage = (s['tagesbestwerte'] as Map?)?.cast<String, dynamic>();
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
