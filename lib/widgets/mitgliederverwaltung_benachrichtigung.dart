import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/sms_service.dart';

/// Tab „Benachrichtigung" im Mitglieder-Dialog.
///
/// Hier steht, ob und wofür ein Mitglied den SMS-Erinnerungen zugestimmt hat.
/// Zwei getrennte Einwilligungen, weil die Medikamenten-Erinnerung den
/// Medikamentennamen in die SMS schreibt und damit Gesundheitsdaten
/// verschickt — die verlangen nach Art. 9 DSGVO eine ausdrückliche, auf genau
/// diese Verarbeitung bezogene Zustimmung. Ein gemeinsames Häkchen für beides
/// wäre unwirksam.
///
/// Mündlich erteilte Zustimmung ist gültig, aber nachweispflichtig (Art. 7
/// Abs. 1) — deshalb hält der Server zu jeder Entscheidung Zeitpunkt, Weg und
/// die Fassung des Einwilligungstextes fest.
class MitgliederBenachrichtigungWidget extends StatefulWidget {
  final ApiService apiService;
  final User user;

  const MitgliederBenachrichtigungWidget({
    super.key,
    required this.apiService,
    required this.user,
  });

  @override
  State<MitgliederBenachrichtigungWidget> createState() =>
      _MitgliederBenachrichtigungWidgetState();
}

class _MitgliederBenachrichtigungWidgetState
    extends State<MitgliederBenachrichtigungWidget> {
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic> _e = {};
  List<Map<String, dynamic>> _log = [];
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _fehler = null;
    });
    try {
      final res = await widget.apiService.getBenachrichtigung(widget.user.id);
      final logRes = await widget.apiService.getBenachrichtigungLog(widget.user.id);
      if (!mounted) return;
      setState(() {
        if (res['success'] == true && res['einstellungen'] is Map) {
          _e = Map<String, dynamic>.from(res['einstellungen'] as Map);
        } else {
          _fehler = res['message']?.toString() ?? 'Einstellungen nicht lesbar';
        }
        if (logRes['success'] == true && logRes['log'] is List) {
          _log = (logRes['log'] as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fehler = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _speichern(Map<String, String?> felder) async {
    setState(() => _saving = true);
    try {
      final res = await widget.apiService.saveBenachrichtigung(
        userId: widget.user.id,
        smsTermine: felder['sms_termine'],
        smsTermineQuelle: felder['sms_termine_quelle'],
        smsMedikamente: felder['sms_medikamente'],
        smsMedikamenteQuelle: felder['sms_medikamente_quelle'],
        zeitMorgens: felder['zeit_morgens'],
        zeitMittags: felder['zeit_mittags'],
        zeitAbends: felder['zeit_abends'],
        zeitNachts: felder['zeit_nachts'],
      );
      if (!mounted) return;
      if (res['success'] == true && res['einstellungen'] is Map) {
        setState(() => _e = Map<String, dynamic>.from(res['einstellungen'] as Map));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message']?.toString() ?? 'Speichern fehlgeschlagen'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final nummer = SmsService.check(widget.user.telefonMobil);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_fehler != null) ...[
          _hinweis(Icons.error_outline, 'Nicht geladen', _fehler!, Colors.red),
          const SizedBox(height: 16),
        ],

        // ── Rufnummer ────────────────────────────────────────────────────
        _abschnitt('Mobilnummer', Icons.smartphone),
        Row(
          children: [
            Icon(
              nummer.canSend ? Icons.check_circle : Icons.error_outline,
              size: 18,
              color: nummer.canSend ? Colors.green.shade600 : Colors.orange.shade700,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(nummer.label, style: const TextStyle(fontSize: 13))),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 26, top: 2),
          child: Text(
            'Wird in Verifizierung Stufe 1 gepflegt. Ohne Mobilnummer geht keine SMS raus.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 24),

        // ── Einwilligungen ───────────────────────────────────────────────
        _abschnitt('Einwilligungen', Icons.verified_user),
        _einwilligung(
          titel: 'Termin-Erinnerungen per SMS',
          erklaerung: 'Datum, Uhrzeit, Ort und Betreff des Termins.',
          feld: 'sms_termine',
        ),
        const SizedBox(height: 14),
        _einwilligung(
          titel: 'Medikamenten-Erinnerungen per SMS',
          erklaerung: 'Enthält den Namen des Medikaments — das sind '
              'Gesundheitsdaten (Art. 9 DSGVO). Hier genügt kein stillschweigendes '
              'Einverständnis: das Mitglied muss ausdrücklich zustimmen, am besten '
              'nachweisbar per Chat oder schriftlich.',
          feld: 'sms_medikamente',
        ),
        const SizedBox(height: 24),

        // ── Sendezeiten ──────────────────────────────────────────────────
        _abschnitt('Sendezeiten für Medikamente', Icons.schedule),
        Text(
          'Passend zu den Angaben morgens / mittags / abends / nachts am '
          'jeweiligen Medikament.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _zeitFeld('morgens', 'zeit_morgens'),
            _zeitFeld('mittags', 'zeit_mittags'),
            _zeitFeld('abends', 'zeit_abends'),
            _zeitFeld('nachts', 'zeit_nachts'),
          ],
        ),
        const SizedBox(height: 24),

        // ── Sendeprotokoll ───────────────────────────────────────────────
        _abschnitt('Gesendete Erinnerungen', Icons.history),
        if (_log.isEmpty)
          Text('Noch nichts verschickt.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
        else
          ..._log.map(_logZeile),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _saving ? null : _load,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Aktualisieren'),
          ),
        ),
      ],
    );
  }

  // ── Bausteine ────────────────────────────────────────────────────────

  Widget _abschnitt(String titel, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.blueGrey.shade700),
            const SizedBox(width: 8),
            Text(titel,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey.shade800)),
          ],
        ),
      );

  Widget _einwilligung({
    required String titel,
    required String erklaerung,
    required String feld,
  }) {
    final status = _e[feld]?.toString() ?? 'offen';
    final am = _e['${feld}_am']?.toString();
    final quelle = _e['${feld}_quelle']?.toString();
    final version = _e['${feld}_version']?.toString();

    final farbe = switch (status) {
      'ja' => Colors.green,
      'nein' => Colors.red,
      _ => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(titel,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: farbe.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: farbe.shade200),
                ),
                child: Text(
                  switch (status) {
                    'ja' => 'zugestimmt',
                    'nein' => 'abgelehnt',
                    _ => 'noch nicht gefragt',
                  },
                  style: TextStyle(fontSize: 11, color: farbe.shade800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(erklaerung,
              style: TextStyle(fontSize: 11, height: 1.4, color: Colors.grey.shade700)),
          if (am != null && am.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Erfasst am ${_datum(am)}'
              '${quelle != null ? ' · ${_quelle(quelle)}' : ''}'
              '${version != null ? ' · Textfassung $version' : ''}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              _statusKnopf(feld, 'ja', 'muendlich', 'Ja (mündlich)', Colors.green),
              _statusKnopf(feld, 'ja', 'schriftlich', 'Ja (schriftlich)', Colors.green),
              _statusKnopf(feld, 'nein', 'muendlich', 'Nein', Colors.red),
              if (status != 'offen')
                _statusKnopf(feld, 'offen', 'muendlich', 'zurücksetzen', Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusKnopf(
      String feld, String status, String quelle, String text, MaterialColor farbe) {
    final aktiv = (_e[feld]?.toString() ?? 'offen') == status &&
        (status == 'offen' || (_e['${feld}_quelle']?.toString() ?? '') == quelle);
    return OutlinedButton(
      onPressed: _saving
          ? null
          : () => _speichern({feld: status, '${feld}_quelle': quelle}),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: aktiv ? Colors.white : farbe.shade700,
        backgroundColor: aktiv ? farbe.shade600 : null,
        side: BorderSide(color: farbe.shade300),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _zeitFeld(String label, String feld) {
    final wert = (_e[feld]?.toString() ?? '').padRight(5).substring(0, 5);
    return SizedBox(
      width: 130,
      child: OutlinedButton.icon(
        onPressed: _saving ? null : () => _zeitWaehlen(label, feld, wert),
        icon: const Icon(Icons.access_time, size: 16),
        label: Text('$label  $wert', style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Future<void> _zeitWaehlen(String label, String feld, String aktuell) async {
    final teile = aktuell.split(':');
    final gewaehlt = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(teile.first) ?? 8,
        minute: int.tryParse(teile.length > 1 ? teile[1] : '0') ?? 0,
      ),
      helpText: 'Sendezeit $label',
    );
    if (gewaehlt == null) return;
    final wert = '${gewaehlt.hour.toString().padLeft(2, '0')}:'
        '${gewaehlt.minute.toString().padLeft(2, '0')}';
    await _speichern({feld: wert});
  }

  Widget _logZeile(Map<String, dynamic> r) {
    final status = r['status']?.toString() ?? '';
    final (IconData icon, Color farbe) = switch (status) {
      'sent' => (Icons.check_circle, Colors.green.shade600),
      'failed' => (Icons.error_outline, Colors.red.shade600),
      'skipped' => (Icons.remove_circle_outline, Colors.orange.shade700),
      _ => (Icons.schedule, Colors.grey.shade600),
    };
    final wann = r['sent_at']?.toString();
    final titel = r['title']?.toString() ?? 'Termin ${r['termin_id']}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: farbe),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titel, style: const TextStyle(fontSize: 13)),
                Text(
                  [
                    if (wann != null && wann.isNotEmpty) _datum(wann),
                    r['trigger_source'] == 'manual' ? 'von Hand' : 'automatisch',
                    if (r['last_error'] != null &&
                        r['last_error'].toString().isNotEmpty)
                      r['last_error'].toString(),
                  ].join(' · '),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hinweis(IconData icon, String titel, String text, MaterialColor farbe) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: farbe.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: farbe.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: farbe.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titel,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: farbe.shade900)),
                  Text(text, style: TextStyle(fontSize: 12, color: farbe.shade900)),
                ],
              ),
            ),
          ],
        ),
      );

  String _datum(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat('dd.MM.yyyy HH:mm').format(d.toLocal());
  }

  String _quelle(String q) => switch (q) {
        'app' => 'in der App bestätigt',
        'schriftlich' => 'schriftlich',
        _ => 'mündlich, hier erfasst',
      };
}
