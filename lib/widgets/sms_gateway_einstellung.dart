import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/sms_service.dart';
import '../services/termin_sms_gateway_service.dart';

/// Einrichtung des Geräts, das die automatischen Termin-Erinnerungen per SMS
/// verschickt.
///
/// Genau ein Gerät darf das sein — das Vereins-Tablet mit SIM. Wäre der
/// Schalter auf mehreren Vorsitzer-Geräten an, bekäme jedes Mitglied dieselbe
/// Erinnerung mehrfach.
class SmsGatewayEinstellungWidget extends StatefulWidget {
  const SmsGatewayEinstellungWidget({super.key});

  @override
  State<SmsGatewayEinstellungWidget> createState() => _SmsGatewayEinstellungWidgetState();
}

class _SmsGatewayEinstellungWidgetState extends State<SmsGatewayEinstellungWidget> {
  bool _loading = true;
  bool _enabled = false;
  bool _batteryExempt = false;
  bool _backgroundRestricted = false;
  bool _jobScheduled = false;
  bool _running = false;
  ({bool messaging, bool permission}) _caps = (messaging: false, permission: false);
  DateTime? _lastRun;
  String? _lastResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final enabled = await TerminSmsGatewayService.isEnabled();
    final caps = await SmsService.capabilities();
    final exempt = await TerminSmsGatewayService.isBatteryExempt();
    final restricted = await TerminSmsGatewayService.isBackgroundRestricted();
    // Beim Öffnen der Seite gleich reparieren, falls Samsung den Job entsorgt
    // hat — sonst müsste der Nutzer raten, warum nichts passiert.
    final scheduled = enabled
        ? await TerminSmsGatewayService.ensureJobScheduled()
        : await TerminSmsGatewayService.isJobScheduled();
    final lastRun = await TerminSmsGatewayService.lastRun();
    final lastResult = await TerminSmsGatewayService.lastResult();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _caps = caps;
      _batteryExempt = exempt;
      _backgroundRestricted = restricted;
      _jobScheduled = scheduled;
      _lastRun = lastRun;
      _lastResult = lastResult;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    await TerminSmsGatewayService.setEnabled(value);
    await _load();
    if (!mounted) return;
    if (value && !_batteryExempt) {
      // Ohne Ausnahme schläft der Hintergrundjob auf Samsung ein — direkt
      // fragen, statt es den Nutzer später herausfinden zu lassen.
      await _requestBattery();
    }
  }

  Future<void> _requestBattery() async {
    final res = await TerminSmsGatewayService.requestBatteryExemption();
    if (!mounted) return;
    final text = switch (res) {
      'already_ignored' => 'Akku-Optimierung ist bereits deaktiviert.',
      'requested' => 'Bitte im Systemdialog „Zulassen" wählen.',
      'no_dialog' => 'Systemliste geöffnet — App suchen und auf „Nicht optimiert" stellen.',
      _ => 'Auf diesem Gerät nicht verfügbar.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    // Der Dialog läuft außerhalb der App; den Status beim Zurückkommen neu lesen.
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) _load();
  }

  Future<void> _runNow() async {
    setState(() => _running = true);
    final result = await TerminSmsGatewayService.runOnce();
    if (!mounted) return;
    setState(() => _running = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.note ?? 'Warteschlange geprüft — $result'),
        backgroundColor: result.note != null ? Colors.orange : Colors.green,
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Icon(Icons.sms, size: 22, color: Colors.teal.shade700),
            const SizedBox(width: 8),
            Text('SMS-Terminerinnerung',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Der Server bereitet täglich um 9:00 Uhr die Erinnerungen für die Termine '
          'von morgen vor. Verschickt werden sie von dem Gerät, das hier als '
          'SMS-Gateway markiert ist — nur dieses hat eine SIM. Empfänger sind '
          'ausschließlich Mobilnummern aus Verifizierung Stufe 1; SMS ins '
          'Festnetz gibt es seit 2023 nicht mehr.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
        ),
        const SizedBox(height: 20),

        if (!Platform.isAndroid)
          _hinweis(
            Icons.info_outline,
            'Dieses Gerät kann keine SMS verschicken',
            'SMS-Versand gibt es nur auf Android. Am Desktop bleibt es bei der '
            'Chat-Erinnerung.',
            Colors.blueGrey,
          )
        else ...[
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: SwitchListTile(
              value: _enabled,
              onChanged: _caps.messaging ? _toggle : null,
              title: const Text('Dieses Gerät ist das SMS-Gateway',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(
                _caps.messaging
                    ? 'Prüft alle 30 Minuten, ob Erinnerungen offen sind.'
                    : 'Kein Mobilfunkmodem gefunden — dieses Gerät kann nicht senden.',
                style: const TextStyle(fontSize: 12),
              ),
              secondary: Icon(Icons.smartphone,
                  color: _enabled ? Colors.teal.shade700 : Colors.grey.shade500),
            ),
          ),
          const SizedBox(height: 12),

          _statusZeile(
            'Mobilfunk / SIM',
            _caps.messaging ? 'vorhanden' : 'fehlt',
            _caps.messaging,
          ),
          _statusZeile(
            'SMS-Berechtigung',
            _caps.permission ? 'erteilt' : 'noch nicht erteilt',
            _caps.permission,
          ),
          _statusZeile(
            'Akku-Optimierung',
            _batteryExempt ? 'deaktiviert (gut)' : 'aktiv — Job kann einschlafen',
            _batteryExempt,
            action: _batteryExempt
                ? null
                : TextButton(onPressed: _requestBattery, child: const Text('Ändern')),
          ),
          _statusZeile(
            'Hintergrund-Nutzung',
            _backgroundRestricted ? 'eingeschränkt — Job läuft nicht' : 'erlaubt',
            !_backgroundRestricted,
            action: _backgroundRestricted
                ? TextButton(
                    onPressed: TerminSmsGatewayService.openAppSettings,
                    child: const Text('Ändern'))
                : null,
          ),
          _statusZeile(
            'Hintergrund-Job',
            _jobScheduled
                ? 'angemeldet (alle 30 Min.)'
                : _enabled
                    ? 'nicht angemeldet'
                    : 'aus',
            _jobScheduled || !_enabled,
          ),
          if (_lastRun != null)
            _statusZeile(
              'Letzter Durchlauf',
              '${DateFormat('dd.MM.yyyy HH:mm').format(_lastRun!)}'
              '${_lastResult != null ? ' — $_lastResult' : ''}',
              // Älter als 26 Stunden heißt: der Job kommt nicht mehr dran,
              // obwohl er alle 30 Minuten laufen sollte.
              DateTime.now().difference(_lastRun!).inHours < 26,
            ),

          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _running || !_enabled ? null : _runNow,
                icon: _running
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow, size: 18),
                label: const Text('Jetzt prüfen'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Status neu lesen'),
              ),
            ],
          ),

          if (!_caps.permission) ...[
            const SizedBox(height: 20),
            _hinweis(
              Icons.lock_outline,
              'SMS-Berechtigung bei eigener APK freischalten',
              'Weil die App nicht aus dem Play Store kommt, sperrt Android den '
              'SMS-Schalter. Einmalig nötig:\n'
              '1. App-Symbol lange drücken → App-Info\n'
              '2. Menü ⋮ oben rechts → „Eingeschränkte Einstellungen zulassen"\n'
              '3. Berechtigungen → SMS → Zulassen\n\n'
              'Danach fragt die App beim ersten Versand ganz normal nach.',
              Colors.orange,
            ),
          ],

          if (_enabled) ...[
            const SizedBox(height: 20),
            _hinweis(
              Icons.battery_saver,
              'Damit Samsung die App nicht schlafen legt',
              'Die Akku-Ausnahme oben reicht auf Samsung-Geräten nicht — One UI hat '
              'eine zweite, eigene Schlafverwaltung. Einmalig einstellen:\n\n'
              '1. Einstellungen → Akku → Nutzungsbeschränkungen im Hintergrund\n'
              '2. „Apps, die nie in den Ruhezustand versetzt werden" → + → diese App\n'
              '3. Prüfen, dass die App NICHT unter „Apps im Tiefschlaf" steht\n'
              '4. Einstellungen → Apps → diese App → Akku → „Unbeschränkt"\n\n'
              'Die App-Seite offen zu lassen hilft zusätzlich: Android hält zuletzt '
              'benutzte Apps in einem aktiveren Zustand. Wird die App über "Force Stop" '
              'beendet, meldet sich der Job erst beim nächsten Öffnen wieder an.',
              Colors.indigo,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: TerminSmsGatewayService.openBatterySettings,
                  icon: const Icon(Icons.battery_charging_full, size: 18),
                  label: const Text('Akku-Einstellungen öffnen'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: TerminSmsGatewayService.openAppSettings,
                  icon: const Icon(Icons.settings_applications, size: 18),
                  label: const Text('App-Info öffnen'),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _statusZeile(String label, String wert, bool ok, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline,
              size: 16, color: ok ? Colors.green.shade600 : Colors.orange.shade700),
          const SizedBox(width: 8),
          SizedBox(width: 150, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: Text(wert,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _hinweis(IconData icon, String titel, String text, MaterialColor farbe) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: farbe.shade50,
        borderRadius: BorderRadius.circular(10),
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
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: farbe.shade900)),
                const SizedBox(height: 6),
                Text(text, style: TextStyle(fontSize: 12, height: 1.45, color: farbe.shade900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
