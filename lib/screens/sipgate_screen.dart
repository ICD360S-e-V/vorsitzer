import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/sipgate_service.dart';
import '../widgets/responsive_layout.dart';

/// Telefonieren über sipgate, direkt in der App.
///
/// Drei Teile: die Anmeldung (oben, weil eine verlorene Registrierung sonst
/// unbemerkt bliebe), das laufende Gespräch, und die Wähltastatur mit Verlauf.
/// Die VoIP-Telefone des Kontos liegen darunter zugeklappt — daran fasst man
/// selten und dann bewusst.
class SipgateScreen extends StatefulWidget {
  const SipgateScreen({super.key});

  @override
  State<SipgateScreen> createState() => _SipgateScreenState();
}

class _SipgateScreenState extends State<SipgateScreen> {
  final SipgateService _dienst = SipgateService();
  final TextEditingController _nummer = TextEditingController();

  bool _auto = false;
  String _wahlweg = 'sim';
  bool _ladeVerlauf = true;
  List<Map<String, dynamic>> _verlauf = const [];
  List<Map<String, dynamic>> _geraete = const [];

  @override
  void initState() {
    super.initState();
    _dienst.zustand.addListener(_aufZustand);
    _laden();
  }

  @override
  void dispose() {
    _dienst.zustand.removeListener(_aufZustand);
    _nummer.dispose();
    super.dispose();
  }

  // Ein beendetes Gespräch schreibt eine Zeile in den Verlauf; ohne das hier
  // müsste man den Bildschirm verlassen und neu öffnen, um sie zu sehen.
  SipgateGespraechStand? _letzterStand;
  void _aufZustand() {
    final jetzt = _dienst.zustand.value.gespraech?.stand;
    if (_letzterStand != null && jetzt == null) _verlaufLaden();
    _letzterStand = jetzt;
    if (mounted) setState(() {});
  }

  Future<void> _laden() async {
    _auto = await _dienst.autoAktiv();
    _wahlweg = await SipgateService.wahlwegFuerRechner();
    if (mounted) setState(() {});
    await Future.wait([_verlaufLaden(), _geraeteLaden()]);
  }

  Future<void> _verlaufLaden() async {
    try {
      final a = await ApiService().sipgateAction({'action': 'list_anrufe', 'limit': 40});
      final liste = (a['data'] as Map?)?['anrufe'];
      if (mounted) {
        setState(() {
          _verlauf = liste is List ? liste.cast<Map<String, dynamic>>() : const [];
          _ladeVerlauf = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ladeVerlauf = false);
    }
  }

  Future<void> _geraeteLaden() async {
    try {
      final a = await ApiService().sipgateAction({'action': 'list_geraete'});
      final liste = (a['data'] as Map?)?['geraete'];
      if (mounted && liste is List) {
        setState(() => _geraete = liste.cast<Map<String, dynamic>>());
      }
    } catch (_) {/* Der Bildschirm bleibt ohne Geräteliste benutzbar. */}
  }

  void _melde(String text, {bool fehler = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: fehler ? Colors.red.shade700 : null,
      duration: Duration(seconds: fehler ? 7 : 4),
    ));
  }

  // ── Aktionen ───────────────────────────────────────────────────────────────

  Future<void> _anrufen() async {
    final roh = _nummer.text.trim();
    if (roh.isEmpty) return;
    final meldung = await _dienst.anrufen(roh);
    if (meldung != null) {
      _melde(meldung, fehler: true);
    } else {
      _nummer.clear();
    }
  }

  Future<void> _autoUmschalten(bool an) async {
    setState(() => _auto = an);
    await _dienst.setAutoAktiv(an);
  }

  Future<void> _selbsttest() async {
    final a = await ApiService().sipgateAction({'action': 'selbsttest'});
    final d = (a['data'] as Map?) ?? const {};
    final fehler = (d['fehler'] as List?) ?? const [];
    _melde(
      fehler.isEmpty
          ? 'Selbsttest bestanden — Realm ${d['realm']}, ${d['wss_url']}'
          : 'Selbsttest: ${fehler.join(' · ')}',
      fehler: fehler.isNotEmpty,
    );
  }

  // ── Aufbau ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final z = _dienst.zustand.value;
    final schmal = ResponsiveLayout.istTelefon(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('sipgate — Telefonie'),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'Selbsttest (HA1, Notrufsperre, Rufnummern)',
            onPressed: _selbsttest,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Neu laden',
            onPressed: _laden,
          ),
        ],
      ),
      // Auf allem außer Android ist dieser Bildschirm ein Bedienpult: hier wird
      // eingestellt, WOMIT das Tablet wählt, und nachgesehen, was gelaufen ist.
      // Telefoniert wird auf dem Tablet.
      body: ListView(
        padding: EdgeInsets.all(schmal ? 10 : 16),
        children: [
          if (!_dienst.plattformFaehig) _hinweisBedienpult() else _anmeldung(z),
          if (_dienst.plattformFaehig && z.gespraech != null) ...[
            const SizedBox(height: 12),
            _gespraechsfeld(z.gespraech!),
          ],
          const SizedBox(height: 12),
          _fernwahlweg(),
          if (_dienst.plattformFaehig) ...[
            const SizedBox(height: 12),
            _waehlfeld(schmal),
          ],
          const SizedBox(height: 12),
          _hinweisNotruf(),
          const SizedBox(height: 12),
          _verlaufsfeld(),
          const SizedBox(height: 12),
          _geraetefeld(),
        ],
      ),
    );
  }

  Widget _anmeldung(SipgateZustand z) {
    final (farbe, symbol, text) = switch (z.stand) {
      SipgateStand.registriert => (Colors.green.shade600, Icons.cloud_done, 'Angemeldet'),
      SipgateStand.verbindet => (Colors.orange.shade700, Icons.cloud_sync, 'Melde an …'),
      SipgateStand.fehler => (Colors.red.shade700, Icons.cloud_off, 'Nicht angemeldet'),
      SipgateStand.aus => (Colors.grey.shade600, Icons.cloud_off, 'Aus'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(symbol, color: farbe, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: farbe)),
                      if (z.sipId != null)
                        Text(
                          z.bezeichnung?.isNotEmpty == true
                              ? '${z.bezeichnung} · ${z.sipId}'
                              : '${z.sipId}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                    ],
                  ),
                ),
                if (z.stand == SipgateStand.registriert)
                  TextButton.icon(
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Abmelden'),
                    onPressed: _dienst.stoppen,
                  )
                else
                  FilledButton.icon(
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('Anmelden'),
                    onPressed: () async {
                      final ok = await _dienst.starten();
                      if (!ok) {
                        _melde(_dienst.zustand.value.meldung ?? 'Anmeldung fehlgeschlagen',
                            fehler: true);
                      }
                    },
                  ),
              ],
            ),
            if (z.sipId != null) ...[
              const SizedBox(height: 10),
              // ⚠️ Steht im Bildschirm, weil es sonst niemand weiss: mit
              // unterdrückter Nummer nehmen viele Ämter und Praxen gar nicht ab
              // und können auf keinen Fall zurückrufen. Wer das nicht sieht,
              // sucht den Fehler bei der Verbindung.
              Row(
                children: [
                  Icon(
                    z.absendernummer == null ? Icons.visibility_off : Icons.badge_outlined,
                    size: 16,
                    color: z.absendernummer == null
                        ? Colors.orange.shade700
                        : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      z.absendernummer == null
                          ? 'Angerufene sehen: unterdrückt — viele Ämter nehmen '
                              'dann nicht ab und können nicht zurückrufen'
                          : 'Angerufene sehen: ${_nummerLesbar(z.absendernummer!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: z.absendernummer == null
                            ? Colors.orange.shade900
                            : Colors.grey.shade800,
                        fontWeight: z.absendernummer == null
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.emergency_outlined, size: 16, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      switch (z.notrufstandort) {
                        'gesetzt' => 'Notrufstandort im Konto gesetzt — 110/112 '
                            'gehen hier trotzdem nicht, sondern über die SIM.',
                        'nicht_gesetzt' => 'Notrufstandort NICHT gesetzt — 110/112 '
                            'können über sipgate nicht funktionieren.',
                        _ => 'Notrufstandort unbekannt — 110/112 gehen über die SIM.',
                      },
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                    ),
                  ),
                ],
              ),
            ],
            if (_btNoetig(z)) ...[
              const SizedBox(height: 8),
              // ⚠️ Der wahrscheinlichste Grund für „ich höre nichts im
              // Kopfhörer": ohne BLUETOOTH_CONNECT findet Android das
              // gekoppelte Headset nicht und der Ton geht in den
              // Tablet-Lautsprecher — ohne jede Fehlermeldung. Deshalb steht es
              // hier und nicht nur im Protokoll.
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.bluetooth_disabled, size: 18, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        z.bluetoothRecht == 'dauerhaft_abgelehnt'
                            ? 'Bluetooth-Berechtigung dauerhaft abgelehnt — ohne sie '
                                'findet die App das Headset nicht und der Ton geht in '
                                'den Tablet-Lautsprecher. Nur noch über die '
                                'App-Einstellungen zu erlauben.'
                            : 'Bluetooth-Berechtigung fehlt. Ohne sie findet die App '
                                'das gekoppelte Headset nicht und der Ton geht in den '
                                'Tablet-Lautsprecher.',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                      ),
                    ),
                    if (z.bluetoothRecht != 'dauerhaft_abgelehnt')
                      TextButton(
                        onPressed: () async {
                          final stand = await _dienst.bluetoothRechtSichern();
                          if (stand != 'erteilt' && stand != 'nicht_noetig') {
                            _melde('Bluetooth-Berechtigung: $stand', fehler: true);
                          }
                        },
                        child: const Text('Erlauben'),
                      ),
                  ],
                ),
              ),
            ],
            if (z.meldung != null) ...[
              const SizedBox(height: 8),
              Text(z.meldung!, style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
            ],
            if (z.geteilt) ...[
              const SizedBox(height: 8),
              _warnzeile(
                'Dieses VoIP-Telefon wird mit einem anderen Gerät geteilt — '
                'eingehende Anrufe klingeln dann auf beiden.',
                Colors.orange,
              ),
            ],
            const Divider(height: 22),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _auto,
              onChanged: _autoUmschalten,
              title: const Text('Beim App-Start automatisch anmelden'),
              subtitle: const Text(
                'Nötig, um Anrufe in der App zu empfangen. Hält eine Verbindung '
                'zu sipgate offen, solange die App läuft.',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Erklärt, warum es hier keine Wähltastatur gibt.
  ///
  /// Ohne diese Karte sähe der Bildschirm am Rechner nach einer halben Funktion
  /// aus — und jemand würde suchen, warum „Anmelden" fehlt.
  Widget _hinweisBedienpult() => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.desktop_windows_outlined, size: 24, color: Colors.indigo.shade400),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bedienpult — telefoniert wird auf dem Tablet',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      'Die In-App-Telefonie läuft nur auf dem Samsung-Tablet: dort '
                      'hängt das Bluetooth-Headset, und die App läuft dort dauerhaft. '
                      'Von hier aus wird gewählt, indem der Auftrag ans Tablet geht — '
                      'ein Klick auf eine Rufnummer in einer Behörden- oder Arztkarte '
                      'genügt.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  /// Womit das Vereinstelefon wählt, wenn der Auftrag von hier kommt.
  ///
  /// Der Klick auf eine Rufnummer in einer Behörden- oder Arztkarte bleibt
  /// derselbe; nur der Weg dahinter ändert sich. Über sipgate landet die
  /// Sprache im Bluetooth-Headset am Tablet, über die SIM im Systemdialer.
  Widget _fernwahlweg() {
    final ueberSipgate = _wahlweg == 'sipgate';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings_phone, size: 20, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Anruf vom Rechner: womit wählt das Tablet?',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'sim',
                  icon: Icon(Icons.sim_card, size: 18),
                  label: Text('SIM'),
                ),
                ButtonSegment(
                  value: 'sipgate',
                  icon: Icon(Icons.headset_mic, size: 18),
                  label: Text('sipgate'),
                ),
              ],
              selected: {_wahlweg},
              onSelectionChanged: (s) async {
                final neu = s.first;
                setState(() => _wahlweg = neu);
                await SipgateService.setWahlwegFuerRechner(neu);
              },
            ),
            const SizedBox(height: 8),
            Text(
              ueberSipgate
                  ? 'Das Tablet wählt über VoIP; die Sprache geht in das '
                      'Bluetooth-Headset am Tablet. Setzt voraus, dass dort '
                      '„Beim App-Start automatisch anmelden" an ist.'
                  : 'Das Tablet wählt über die SIM-Karte mit dem Systemdialer '
                      '— der bisherige Weg.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            if (ueberSipgate) ...[
              const SizedBox(height: 8),
              // ⚠️ Steht hier, weil es genau der Fall ist, der sonst als
              // „Anruf geht nicht" ankommt: kein Rückfall auf die SIM, sondern
              // eine Fehlermeldung. Ein stiller Umweg über einen anderen
              // Anschluss mit anderer Absendernummer wäre schlimmer.
              _warnzeile(
                'Ist das Tablet nicht bei sipgate angemeldet, meldet der Auftrag '
                'einen Fehler — es wird NICHT still auf die SIM ausgewichen.',
                Colors.orange,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _gespraechsfeld(SipgateGespraech g) {
    final verbunden = g.stand == SipgateGespraechStand.verbunden;
    final klingelt = g.stand == SipgateGespraechStand.klingelt;

    return Card(
      color: verbunden ? Colors.green.shade50 : Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  g.eingehend ? Icons.phone_callback : Icons.phone_forwarded,
                  color: verbunden ? Colors.green.shade700 : Colors.blue.shade700,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.name?.isNotEmpty == true ? g.name! : g.nummer,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        klingelt
                            ? 'Eingehender Anruf · ${g.nummer}'
                            : verbunden
                                ? 'Verbunden · ${_dauer(g.dauerSekunden)}'
                                : 'Wählt · ${g.nummer}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (klingelt) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                    icon: const Icon(Icons.call),
                    label: const Text('Annehmen'),
                    onPressed: () => _dienst.annehmen(),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                    icon: const Icon(Icons.call_end),
                    label: const Text('Ablehnen'),
                    onPressed: _dienst.ablehnen,
                  ),
                ] else ...[
                  if (verbunden)
                    OutlinedButton.icon(
                      icon: Icon(g.stumm ? Icons.mic_off : Icons.mic),
                      label: Text(g.stumm ? 'Stumm' : 'Mikrofon an'),
                      onPressed: () => _dienst.stummSchalten(!g.stumm),
                    ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                    icon: const Icon(Icons.call_end),
                    label: const Text('Auflegen'),
                    onPressed: _dienst.auflegen,
                  ),
                ],
              ],
            ),
            if (verbunden) ...[
              const Divider(height: 20),
              Text('Tastentöne (DTMF)',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final t in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'])
                    SizedBox(
                      width: 42,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () => _dienst.dtmf(t),
                        child: Text(t),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _waehlfeld(bool schmal) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: _nummer,
              keyboardType: TextInputType.phone,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, letterSpacing: 1.5),
              decoration: InputDecoration(
                hintText: '0711 123456',
                border: const OutlineInputBorder(),
                suffixIcon: _nummer.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.backspace_outlined),
                        onPressed: () => setState(() {
                          final t = _nummer.text;
                          if (t.isNotEmpty) _nummer.text = t.substring(0, t.length - 1);
                        }),
                      ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _anrufen(),
            ),
            const SizedBox(height: 12),
            // Die Tastatur ist kein Zierrat: am Rechner tippt man mit der
            // Tastatur, am Tablet steht das Gerät und man tippt mit dem Finger.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final t in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'])
                  SizedBox(
                    width: schmal ? 62 : 74,
                    height: schmal ? 46 : 52,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => setState(() => _nummer.text += t),
                      child: Text(t, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                SizedBox(
                  width: schmal ? 62 : 74,
                  height: schmal ? 46 : 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => setState(() => _nummer.text += '+'),
                    child: const Text('+', style: TextStyle(fontSize: 20)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.call),
                label: Text(_nummer.text.isEmpty
                    ? 'Anrufen'
                    : 'Anrufen: ${SipgateService.normalisieren(_nummer.text) ?? _nummer.text}'),
                onPressed: _dienst.hatGespraech || _nummer.text.isEmpty ? null : _anrufen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ⚠️ Steht bewusst im Bildschirm, nicht nur im Code: wer hier telefoniert,
  /// muss wissen, dass 110/112 diesen Weg nicht nehmen.
  Widget _hinweisNotruf() => _warnzeile(
        'Notrufe (110, 112) gehen NICHT über sipgate — dafür fehlt im Konto ein '
        'verifizierter Notrufstandort. Im Notfall das Telefon mit SIM-Karte '
        'benutzen. 115 und 116117 sind keine Notrufe und funktionieren hier.',
        Colors.red,
      );

  Widget _warnzeile(String text, MaterialColor farbe) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: farbe.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: farbe.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: farbe.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 12, color: farbe.shade900)),
            ),
          ],
        ),
      );

  Widget _verlaufsfeld() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 20, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                const Text('Verlauf', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Eigenes Protokoll — enthält auch die Anrufe, die nicht zustande '
              'kamen, und warum. Die fehlen im Verlauf von sipgate.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            if (_ladeVerlauf)
              const Center(child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              ))
            else if (_verlauf.isEmpty)
              Text('Noch kein Gespräch.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
            else
              for (final a in _verlauf) _verlaufszeile(a),
          ],
        ),
      ),
    );
  }

  Widget _verlaufszeile(Map<String, dynamic> a) {
    final ein = a['richtung'] == 'ein';
    final status = '${a['status']}';
    final (farbe, symbol) = switch (status) {
      'beendet' => (Colors.green.shade600, ein ? Icons.call_received : Icons.call_made),
      'verbunden' => (Colors.green.shade600, Icons.call),
      'verpasst' => (Colors.orange.shade700, Icons.call_missed),
      'abgelehnt' => (Colors.grey.shade600, Icons.call_end),
      'fehler' => (Colors.red.shade700, Icons.error_outline),
      _ => (Colors.blue.shade600, Icons.call_made),
    };
    final dauer = (a['dauer_s'] as int?) ?? 0;
    final fehler = '${a['fehler'] ?? ''}';
    final name = '${a['bezeichnung'] ?? ''}';
    final nummer = '${a['nummer'] ?? ''}';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(symbol, size: 20, color: farbe),
      title: Text(name.isNotEmpty ? '$name · $nummer' : nummer,
          style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        [
          '${a['begonnen_am'] ?? ''}',
          status,
          if (dauer > 0) _dauer(dauer),
          if (fehler.isNotEmpty) fehler,
        ].join(' · '),
        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.call, size: 18),
        tooltip: 'Zurückrufen',
        onPressed: nummer.isEmpty
            ? null
            : () {
                _nummer.text = nummer;
                setState(() {});
              },
      ),
    );
  }

  Widget _geraetefeld() {
    return Card(
      child: ExpansionTile(
        leading: Icon(Icons.sim_card_outlined, color: Colors.grey.shade700),
        title: const Text('VoIP-Telefone des Kontos',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text('${_geraete.length} hinterlegt',
            style: const TextStyle(fontSize: 11)),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Das SIP-Passwort bleibt auf dem Server. Die App bekommt nur HA1 '
              '— damit kann man telefonieren, aber nicht ins sipgate-Konto.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(height: 10),
          for (final g in _geraete) _geraetezeile(g),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('VoIP-Telefon hinzufügen'),
              onPressed: () => _geraetDialog(null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _geraetezeile(Map<String, dynamic> g) {
    final aktiv = g['aktiv'] == true;
    final hatPass = g['pass_gesetzt'] == true;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        hatPass && aktiv ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 18,
        color: hatPass && aktiv ? Colors.green.shade600 : Colors.grey.shade400,
      ),
      title: Text(
        '${g['bezeichnung']?.toString().isNotEmpty == true ? g['bezeichnung'] : g['sip_id']}',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        [
          '${g['sip_id']}',
          '${g['plattform']}',
          if (!hatPass) 'kein Passwort',
          if (!aktiv) 'inaktiv',
          if (g['belegt'] == true) 'einem Gerät zugeordnet',
        ].join(' · '),
        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (wahl) async {
          switch (wahl) {
            case 'edit':
              _geraetDialog(g);
              break;
            case 'pass':
              await _passZeigen(g);
              break;
            case 'loesen':
              await ApiService().sipgateAction(
                  {'action': 'geraet_loesen', 'id': g['id']});
              await _geraeteLaden();
              _melde('Zuordnung gelöst — ein anderes Gerät kann sie nun belegen.');
              break;
            case 'del':
              await ApiService().sipgateAction(
                  {'action': 'delete_geraet', 'id': g['id']});
              await _geraeteLaden();
              break;
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
          const PopupMenuItem(value: 'pass', child: Text('SIP-Passwort zeigen')),
          if (g['belegt'] == true)
            const PopupMenuItem(value: 'loesen', child: Text('Gerätezuordnung lösen')),
          const PopupMenuItem(value: 'del', child: Text('Löschen')),
        ],
      ),
    );
  }

  /// Das Klartextpasswort — gebraucht, um ein Tischtelefon oder ein fremdes
  /// Softphone von Hand einzurichten. Ausdrücklich abgefragt, nicht beiläufig
  /// mitgeladen.
  Future<void> _passZeigen(Map<String, dynamic> g) async {
    final a = await ApiService().sipgateAction({'action': 'reveal_pass', 'id': g['id']});
    if (!mounted) return;
    final d = (a['data'] as Map?) ?? const {};
    if (a['success'] != true) {
      _melde('${a['message'] ?? 'Nicht abrufbar'}', fehler: true);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${d['sip_id']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _feldZeile(ctx, 'SIP-ID', '${d['sip_id']}'),
            _feldZeile(ctx, 'Passwort', '${d['passwort']}'),
            _feldZeile(ctx, 'Domain / Realm', '${d['realm']}'),
            _feldZeile(ctx, 'Proxy (TLS)', '${d['proxy_tls']}'),
            _feldZeile(ctx, 'Proxy (WSS)', '${d['proxy_wss']}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
        ],
      ),
    );
  }

  Widget _feldZeile(BuildContext ctx, String name, String wert) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 118,
              child: Text(name, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            Expanded(
              child: SelectableText(wert, style: const TextStyle(fontSize: 13)),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: 'Kopieren',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: wert));
                ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('$name kopiert')));
              },
            ),
          ],
        ),
      );

  Future<void> _geraetDialog(Map<String, dynamic>? vorhanden) async {
    final sipId = TextEditingController(text: '${vorhanden?['sip_id'] ?? ''}');
    final name = TextEditingController(text: '${vorhanden?['bezeichnung'] ?? ''}');
    final pass = TextEditingController();
    final absender = TextEditingController(text: '${vorhanden?['absendernummer'] ?? ''}');
    final notiz = TextEditingController(text: '${vorhanden?['notiz'] ?? ''}');
    var plattform = '${vorhanden?['plattform'] ?? 'alle'}';
    var notrufstandort = '${vorhanden?['notrufstandort'] ?? 'unbekannt'}';
    var aktiv = vorhanden == null ? true : vorhanden['aktiv'] == true;

    // ⚠️ Keine feste Dialogbreite: auf Telefonbreite (411–448 dp) quetscht sich
    // ein 600-dp-Dialog stillschweigend zusammen statt überzulaufen.
    final maxBreite = ResponsiveLayout.istTelefon(context)
        ? MediaQuery.of(context).size.width - 32
        : 520.0;

    final gespeichert = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setzen) => AlertDialog(
          title: Text(vorhanden == null ? 'VoIP-Telefon hinzufügen' : 'VoIP-Telefon bearbeiten'),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBreite),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: sipId,
                    decoration: const InputDecoration(
                      labelText: 'SIP-ID',
                      hintText: '4023714e0',
                      helperText: 'Steht im sipgate-Konto beim VoIP-Telefon',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Bezeichnung'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: pass,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'SIP-Passwort',
                      helperText: vorhanden == null
                          ? 'Wird verschlüsselt gespeichert und verlässt den Server nicht'
                          : 'Leer lassen = unverändert',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: absender,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Absendernummer (was der Angerufene sieht)',
                      hintText: '0731 80159736',
                      helperText: 'Leer = unterdrückt. Wird bei sipgate im Channel '
                          'gesetzt; hier nur mitgeschrieben, damit man es beim '
                          'Wählen sieht.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: notrufstandort,
                    decoration: const InputDecoration(labelText: 'Notrufstandort im sipgate-Konto'),
                    items: const [
                      DropdownMenuItem(value: 'unbekannt', child: Text('unbekannt')),
                      DropdownMenuItem(value: 'gesetzt', child: Text('gesetzt')),
                      DropdownMenuItem(value: 'nicht_gesetzt', child: Text('nicht gesetzt')),
                    ],
                    onChanged: (v) => setzen(() => notrufstandort = v ?? 'unbekannt'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: plattform,
                    decoration: const InputDecoration(labelText: 'Für welches Gerät'),
                    items: const [
                      DropdownMenuItem(value: 'alle', child: Text('Beliebig (Pool)')),
                      DropdownMenuItem(value: 'linux', child: Text('Linux')),
                      DropdownMenuItem(value: 'android', child: Text('Android')),
                      DropdownMenuItem(value: 'macos', child: Text('macOS')),
                      DropdownMenuItem(value: 'windows', child: Text('Windows')),
                      DropdownMenuItem(value: 'ios', child: Text('iOS')),
                    ],
                    onChanged: (v) => setzen(() => plattform = v ?? 'alle'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notiz,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notiz'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: aktiv,
                    onChanged: (v) => setzen(() => aktiv = v),
                    title: const Text('Aktiv'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );

    if (gespeichert != true) return;
    final a = await ApiService().sipgateAction({
      'action': 'save_geraet',
      if (vorhanden != null) 'id': vorhanden['id'],
      'sip_id': sipId.text.trim(),
      'bezeichnung': name.text.trim(),
      'absendernummer': absender.text.trim(),
      'notrufstandort': notrufstandort,
      'passwort': pass.text,
      'plattform': plattform,
      'notiz': notiz.text.trim(),
      'aktiv': aktiv,
    });
    _melde('${a['message'] ?? (a['success'] == true ? 'Gespeichert' : 'Fehler')}',
        fehler: a['success'] != true);
    await _geraeteLaden();
  }

  /// Ob die Bluetooth-Warnung gezeigt werden muss.
  ///
  /// `unbekannt` zählt NICHT als fehlend: das ist der Zustand vor der ersten
  /// Abfrage und auf Nicht-Android. Eine Warnung, die immer da steht, wird
  /// nicht gelesen.
  static bool _btNoetig(SipgateZustand z) =>
      z.bluetoothRecht == 'abgelehnt' ||
      z.bluetoothRecht == 'dauerhaft_abgelehnt' ||
      z.bluetoothRecht == 'kein_dialog';

  /// `073180159736` -> `0731 80159736`.
  ///
  /// Nur eine Lesehilfe, keine Rufnummernlogik: gewählt wird immer der
  /// unformatierte Wert, damit hier nie ein Leerzeichen in eine Nummer gerät.
  static String _nummerLesbar(String roh) {
    final n = roh.trim();
    if (n.startsWith('+')) return n;
    // Ortsvorwahlen in Deutschland sind 3–5 Stellen inkl. der führenden Null.
    // 0731 (Ulm) ist vierstellig; bei allem, was nicht passt, bleibt die Nummer
    // wie sie ist — falsch zu trennen ist schlimmer als nicht zu trennen.
    if (n.length >= 8 && n.startsWith('0')) {
      return '${n.substring(0, 4)} ${n.substring(4)}';
    }
    return n;
  }

  static String _dauer(int sekunden) {
    final m = (sekunden ~/ 60).toString().padLeft(2, '0');
    final s = (sekunden % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
