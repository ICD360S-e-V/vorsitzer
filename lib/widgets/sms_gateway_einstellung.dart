import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/anruf_gateway_service.dart';
import '../services/rdp_nur_modus.dart';
import '../services/signatur_gateway_service.dart';
import '../services/sms_service.dart';
import '../services/termin_sms_gateway_service.dart';
import '../utils/app_farben.dart';

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

  /// Läuft der Vordergrunddienst, der die TAN-Warteschlange bewacht?
  bool _dienstLaeuft = false;

  bool _running = false;
  ({bool messaging, bool permission}) _caps = (messaging: false, permission: false);
  DateTime? _lastRun;
  String? _lastResult;

  /// Vorprüfung fürs Nachlesen des SMS-Verlaufs. Null = noch nicht geprüft.
  SmsReadDiagnose? _readDiagnose;

  /// Nimmt dieses Gerät Wählaufträge anderer Geräte entgegen?
  bool _anrufAn = false;
  AnrufFaehigkeiten _anrufCaps = const AnrufFaehigkeiten();

  /// Schickt dieses Gerät Klicks auf Rufnummern ans Vereinstelefon?
  bool _fernwahlAn = false;

  /// Zeigt dieses Gerät ausschließlich den Remote Desktop?
  bool _nurRdpAn = false;

  /// Steht der Wert noch so, wie ihn die Geräteerkennung gesetzt hat?
  bool _nurRdpAuto = false;

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
    final dienst = await SignaturGatewayService.laeuft();
    final lastRun = await TerminSmsGatewayService.lastRun();
    final lastResult = await TerminSmsGatewayService.lastResult();
    final anrufAn = await AnrufGatewayService.isEnabled();
    final anrufCaps = await AnrufGatewayService.faehigkeiten();
    final fernwahlAn = await AnrufFernwahl.istAktiv();
    final nurRdpAn = await RdpNurModus.istAn();
    final nurRdpAuto = await RdpNurModus.istAutomatisch();
    if (!mounted) return;
    setState(() {
      _nurRdpAn = nurRdpAn;
      _nurRdpAuto = nurRdpAuto;
      _anrufAn = anrufAn;
      _anrufCaps = anrufCaps;
      _fernwahlAn = fernwahlAn;
      _enabled = enabled;
      _caps = caps;
      _batteryExempt = exempt;
      _backgroundRestricted = restricted;
      _jobScheduled = scheduled;
      _dienstLaeuft = dienst;
      _lastRun = lastRun;
      _lastResult = lastResult;
      _loading = false;
    });
  }

  /// Bewusst kein automatischer Neustart beim Öffnen der Seite, anders als
  /// beim WorkManager-Job: einen Vordergrunddienst ungefragt zu starten
  /// erzeugt eine Dauerbenachrichtigung, und die soll niemand kommentarlos
  /// vorgesetzt bekommen. Deshalb der Knopf.
  Future<void> _dienstNeuStarten() async {
    final ok = await SignaturGatewayService.starten();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Wachdienst läuft.'
          : 'Start fehlgeschlagen — bitte Benachrichtigungen für die App erlauben.'),
      backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
    ));
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

  /// Liest den Ist-Zustand fürs SMS-Lesen. Zählt nur — es wird kein einziges
  /// SMS-Wort und keine Rufnummer angefasst.
  Future<void> _pruefeLesen() async {
    final d = await SmsService.readDiagnose();
    if (!mounted) return;
    setState(() => _readDiagnose = d);
  }

  Future<void> _requestReadPermission() async {
    final res = await SmsService.requestReadPermission();
    if (!mounted) return;
    // Nach jeder Antwort neu messen: „granted" allein sagt noch nicht, ob der
    // App-Op offen ist — genau daran scheitert der Installationsweg-Fall.
    await _pruefeLesen();
    if (!mounted) return;
    final text = switch (res) {
      'granted' => 'Berechtigung erteilt — Ergebnis der Prüfung siehe oben.',
      'denied' => 'Abgelehnt.',
      'denied_permanently' =>
        'Der Dialog erscheint nicht. Das deutet darauf hin, dass diese '
            'Installation die Berechtigung gar nicht erhalten darf.',
      'no_activity' => 'Nur bei geöffneter App möglich.',
      'not_supported' => 'Auf diesem Gerät nicht verfügbar.',
      _ => 'Keine Antwort.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
            Icon(Icons.sms, size: 22, color: F.h(Colors.teal, 700)),
            const SizedBox(width: 8),
            // 24 dp Überlauf auf dem Pixel 8 — Abschnittsüberschrift bei
            // 18 pt neben dem Symbol.
            Expanded(
              child: Text('SMS-Terminerinnerung',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: F.h(Colors.teal, 800))),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Der Server bereitet täglich um 9:00 Uhr die Erinnerungen für die Termine '
          'von morgen vor. Verschickt werden sie von dem Gerät, das hier als '
          'SMS-Gateway markiert ist — nur dieses hat eine SIM. Empfänger sind '
          'ausschließlich Mobilnummern aus Verifizierung Stufe 1; SMS ins '
          'Festnetz gibt es seit 2023 nicht mehr.',
          style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700), height: 1.4),
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
              side: BorderSide(color: F.h(Colors.grey, 300)),
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
                  color: _enabled ? F.h(Colors.teal, 700) : F.h(Colors.grey, 500)),
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
          // Der Wachdienst ist der einzige Weg, auf dem eine TAN bei
          // geschlossener App noch innerhalb ihrer fünf Minuten rausgeht.
          // Läuft er nicht, sieht am Tablet alles normal aus, und erst ein
          // Mitglied merkt es — deshalb steht sein Zustand hier.
          _statusZeile(
            'Wachdienst (Codes)',
            _dienstLaeuft
                ? 'läuft (prüft alle 20 Sek.)'
                : _enabled
                    ? 'gestoppt — Codes gehen bei geschlossener App nicht raus'
                    : 'aus',
            _dienstLaeuft || !_enabled,
          ),
          if (_enabled && !_dienstLaeuft) ...[
            const SizedBox(height: 8),
            _hinweis(
              Icons.warning_amber,
              'Wachdienst läuft nicht',
              'Bestätigungscodes für die digitale Unterschrift gelten nur fünf '
              'Minuten. Ohne den Wachdienst gehen sie nur raus, solange die App '
              'offen ist. Tippen Sie auf „Neu starten".',
              Colors.orange,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _dienstNeuStarten,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Wachdienst neu starten'),
              ),
            ),
          ],
          if (_lastRun != null)
            _statusZeile(
              'Letzter Durchlauf',
              '${DateFormat('dd.MM.yyyy HH:mm').format(_lastRun!)}'
              '${_lastResult != null ? ' — $_lastResult' : ''}',
              // Älter als 26 Stunden heißt: der Job kommt nicht mehr dran,
              // obwohl er alle 30 Minuten laufen sollte.
              DateTime.now().difference(_lastRun!).inHours < 26,
            ),

          // ── Vorprüfung: lässt sich der SMS-Verlauf überhaupt lesen? ──
          // Steht bewusst hier und nicht im Chat: die Frage betrifft das
          // Gerät, nicht ein einzelnes Mitglied, und beantwortet wird sie
          // einmalig beim Einrichten des Tablets.
          const Divider(height: 28),
          _statusZeile(
            'SMS-Verlauf lesen',
            _readDiagnose?.urteil ?? 'noch nicht geprüft',
            _readDiagnose?.funktioniert ?? false,
            action: _readDiagnose?.lage == SmsReadLage.fragenMoeglich
                ? TextButton(
                    onPressed: _requestReadPermission,
                    child: const Text('Anfragen'))
                : TextButton(
                    onPressed: _pruefeLesen,
                    child: const Text('Prüfen')),
          ),
          if (_readDiagnose?.lage == SmsReadLage.vomInstallerBlockiert)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _hinweis(
                Icons.block,
                'Diese Installation darf keine SMS lesen',
                'Android entscheidet das beim INSTALLIEREN, nicht in den '
                'Einstellungen — an dieser Stelle lässt sich nichts '
                'freischalten. Die App müsste über einen Installationsweg '
                'kommen, der die Berechtigung ausdrücklich zulässt. '
                'Der SMS-VERSAND ist davon nicht betroffen und läuft weiter.',
                Colors.deepOrange,
              ),
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

        const Divider(height: 36),
        ..._anrufAbschnitt(),

        const Divider(height: 36),
        ..._nurRdpAbschnitt(),
      ],
    );
  }

  // ── Nur Remote Desktop ────────────────────────────────────────────────────

  Future<void> _nurRdpToggle(bool wert) async {
    await RdpNurModus.setzen(wert);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(wert
          ? 'Beim nächsten Start zeigt dieses Gerät nur noch den Remote Desktop.'
          : 'Beim nächsten Start zeigt dieses Gerät wieder die vollständige App.'),
      backgroundColor: Colors.indigo.shade700,
    ));
  }

  List<Widget> _nurRdpAbschnitt() {
    return [
      Row(
        children: [
          Icon(Icons.desktop_windows_outlined, size: 22, color: F.h(Colors.indigo, 700)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Nur Remote Desktop',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 800))),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        'Für ein Gerät, das nur zum Aufschalten auf den Bürorechner da ist: '
        'statt des Panels erscheint ein einziger Knopf, der die hinterlegte '
        'RDP-Verbindung öffnet. Kein Menü, keine Module, keine Abfragetakte.',
        style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700), height: 1.4),
      ),
      const SizedBox(height: 8),
      // Die Zeile, die man sonst erst bemerkt, wenn ein Klick am Rechner
      // wortlos verfällt.
      _hinweis(
        Icons.phone_disabled,
        'Auf einem Pixel werden die Gateway-Rollen abgeschaltet',
        'Nur dort, und mit Absicht: das Pixel soll nichts weiter tun. Fernwahl, '
        'SMS-Gateway und die automatische Messung werden umgelegt — nicht bloß '
        'übergangen, denn der Wachdienst käme nach jedem Neustart von allein '
        'zurück und fragte weiter alle fünf Sekunden nach Wählaufträgen. Der '
        'Preis steht ausdrücklich dabei: ein Klick auf eine Rufnummer am '
        'Rechner lässt dieses Telefon dann nicht mehr wählen.',
        Colors.deepOrange,
      ),
      const SizedBox(height: 8),
      _hinweis(
        Icons.tablet_android,
        'Auf jedem anderen Gerät bleiben sie an',
        'Das Tablet mit der SIM ist das SMS-Gateway des Vereins. Ein hier '
        'versehentlich eingeschalteter Kiosk darf ihm nicht lautlos die '
        'Termin-Erinnerungen und die Signatur-TANs abdrehen — dort verhält '
        'sich der Kiosk deshalb wie das Dashboard.',
        Colors.blueGrey,
      ),
      const SizedBox(height: 8),
      _hinweis(
        Icons.touch_app,
        'Der Rückweg liegt auf dem Vereinsnamen',
        'Im Kiosk führt langes Tippen auf „ICD360S e.V" zu Verbindungen, '
        'Abmelden und zurück zur vollständigen App. Ohne diesen Weg könnte ein '
        'Gerät mit unerreichbarem RDP-Ziel sich nicht mehr selbst reparieren.',
        Colors.blueGrey,
      ),
      const SizedBox(height: 12),
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: F.h(Colors.grey, 300)),
        ),
        child: SwitchListTile(
          value: _nurRdpAn,
          onChanged: _nurRdpToggle,
          title: const Text('Dieses Gerät zeigt nur den Remote Desktop',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(
            _nurRdpAn && _nurRdpAuto
                ? 'Automatisch gesetzt, weil dieses Gerät ein Google Pixel ist. '
                    'Ein Umlegen von Hand gilt dauerhaft.'
                : 'Wirkt beim nächsten Start der App.',
            style: const TextStyle(fontSize: 12),
          ),
          secondary: Icon(Icons.desktop_windows_outlined,
              color: _nurRdpAn ? F.h(Colors.indigo, 700) : F.h(Colors.grey, 500)),
        ),
      ),
    ];
  }

  // ── Ferngesteuerter Anruf ─────────────────────────────────────────────────

  /// Holt die Anrufberechtigung nach. Der Dialog geht nur bei offener App auf —
  /// deshalb gehört der Knopf hierher und nicht in den Hintergrunddienst.
  Future<void> _anrufrechtAnfragen() async {
    final res = await AnrufGatewayService.anrufrechtAnfragen();
    await _load();
    if (!mounted) return;
    final text = switch (res) {
      'erteilt' => 'Berechtigung erteilt — das Telefon wählt jetzt selbst.',
      'abgelehnt' => 'Abgelehnt. Ohne sie bleibt es bei der Benachrichtigung, '
          'die am Telefon angetippt werden muss.',
      // Der Dialog kommt nicht wieder; nur die Systemseite hilft noch.
      'dauerhaft_abgelehnt' =>
        'Dauerhaft abgelehnt. In den App-Einstellungen unter '
            '„Berechtigungen → Telefon" freigeben.',
      'kein_dialog' => 'Nur bei geöffneter App möglich.',
      'laeuft_schon' => 'Der Dialog ist bereits offen.',
      _ => 'Auf diesem Gerät nicht verfügbar.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 6),
      backgroundColor: res == 'erteilt' ? Colors.green.shade700 : null,
    ));
    if (res == 'dauerhaft_abgelehnt') {
      await TerminSmsGatewayService.openAppSettings();
    }
  }

  Future<void> _anrufToggle(bool value) async {
    await AnrufGatewayService.setEnabled(value);
    await _load();
    if (!mounted) return;

    // Zuerst die Anrufberechtigung: ohne sie wählt gar nichts, egal wie die
    // übrigen Häkchen stehen. Direkt fragen, statt es den Vorsitzer beim
    // ersten Klick vom Rechner aus herausfinden zu lassen.
    if (value && !_anrufCaps.anrufrecht) {
      await _anrufrechtAnfragen();
      if (!mounted) return;
    }

    // Ohne „Über anderen Apps anzeigen" wählt das Gerät nur bei offener App.
    // Das gleich beim Einschalten sagen, statt es den Vorsitzer beim ersten
    // stillen Fehlschlag herausfinden zu lassen.
    if (value && !_anrufCaps.overlay) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Noch fehlt „Über anderen Apps anzeigen" — '
            'sonst wählt das Gerät nur bei offener App.'),
        duration: Duration(seconds: 6),
      ));
    }
  }

  Future<void> _fernwahlToggle(bool value) async {
    await AnrufFernwahl.setAktiv(value);
    await _load();
  }

  Future<void> _oeffne(Future<bool> Function() aktion, String fehlschlag) async {
    final ok = await aktion();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(fehlschlag)));
      return;
    }
    // Die Systemseite läuft außerhalb der App; beim Zurückkommen neu lesen.
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) _load();
  }

  List<Widget> _anrufAbschnitt() {
    return [
      Row(
        children: [
          Icon(Icons.phone_forwarded, size: 22, color: F.h(Colors.indigo, 700)),
          const SizedBox(width: 8),
          // 42 dp Überlauf auf dem Pixel 8 — gleiche Stelle, gleiche Ursache.
          Expanded(
            child: Text('Anruf vom Rechner aus',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: F.h(Colors.indigo, 800))),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        'Ein Klick auf eine Rufnummer am Linux- oder Windows-Rechner lässt das '
        'Vereinstelefon wählen — die Rechner haben keine SIM. Der Auftrag gilt '
        'zwei Minuten; danach verfällt er, damit das Telefon niemanden anruft, '
        'während längst niemand mehr danebensteht.',
        style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700), height: 1.4),
      ),
      const SizedBox(height: 8),
      // Die wichtigste Zeile auf dieser Seite, und die einzige, die sich nicht
      // programmieren lässt: das Gespräch bleibt am Telefon.
      _hinweis(
        Icons.hearing_disabled,
        'Gesprochen wird am Telefon, nicht am Rechner',
        'Keine App darf den Ton eines Mobilfunkgesprächs anfassen — Android '
        'sperrt die Audioquelle seit Version 10 für alles außer System-Dialern. '
        'Der Klick startet also den Anruf, den Hörer nimmt man trotzdem in die '
        'Hand. Wer vom Rechner aus mitreden will, koppelt ihn per Bluetooth als '
        'Freisprecheinrichtung des Telefons; das ist Sache des Betriebssystems, '
        'nicht dieser App, und geht nur in Reichweite.',
        Colors.blueGrey,
      ),
      const SizedBox(height: 16),

      // ── Absenderseite ─────────────────────────────────────────────────
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: F.h(Colors.grey, 300)),
        ),
        child: SwitchListTile(
          value: _fernwahlAn,
          onChanged: _fernwahlToggle,
          title: const Text('Klicks auf Rufnummern ans Telefon schicken',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(
            Platform.isAndroid
                ? 'Aus: dieses Gerät wählt selbst. Nur einschalten, wenn ein '
                    'anderes Telefon die SIM hat.'
                : 'Statt „tel:" an einen Handler zu reichen, den es hier meist '
                    'gar nicht gibt.',
            style: const TextStyle(fontSize: 12),
          ),
          secondary: Icon(Icons.send_to_mobile,
              color: _fernwahlAn ? F.h(Colors.indigo, 700) : F.h(Colors.grey, 500)),
        ),
      ),
      const SizedBox(height: 12),

      // ── Empfängerseite ────────────────────────────────────────────────
      if (!AnrufGatewayService.istUnterstuetzt)
        _hinweis(
          Icons.info_outline,
          'Dieses Gerät kann keine Aufträge entgegennehmen',
          'Wählen im Auftrag anderer Geräte gibt es nur auf Android.',
          Colors.blueGrey,
        )
      else ...[
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: F.h(Colors.grey, 300)),
          ),
          child: SwitchListTile(
            value: _anrufAn,
            onChanged: _anrufCaps.telefonie ? _anrufToggle : null,
            title: const Text('Dieses Gerät wählt für die anderen',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(
              _anrufCaps.telefonie
                  ? 'Sieht alle ${AnrufGatewayService.takt.inSeconds} Sekunden '
                      'nach offenen Aufträgen.'
                  : 'Kein Mobilfunkmodem gefunden — dieses Gerät kann nicht wählen.',
              style: const TextStyle(fontSize: 12),
            ),
            secondary: Icon(Icons.ring_volume,
                color: _anrufAn ? F.h(Colors.indigo, 700) : F.h(Colors.grey, 500)),
          ),
        ),
        const SizedBox(height: 12),

        _statusZeile('Mobilfunk / SIM',
            _anrufCaps.telefonie ? 'vorhanden' : 'fehlt', _anrufCaps.telefonie),
        // ⚠️ Diese Zeile hatte beim ersten Versuch KEINEN Knopf, und genau
        // daran scheiterte alles: das Telefon holte den Auftrag ab, das Plugin
        // lief, und meldete „Anrufberechtigung fehlt". Gefragt wird sonst nur,
        // wenn jemand AUF DEM TELEFON eine Rufnummer antippt — bei der
        // Fernwahl tippt aber niemand dort.
        _statusZeile(
          'Anrufberechtigung',
          _anrufCaps.anrufrecht ? 'erteilt' : 'fehlt — es wird nichts gewählt',
          _anrufCaps.anrufrecht,
          action: _anrufCaps.anrufrecht
              ? null
              : TextButton(
                  onPressed: _anrufrechtAnfragen,
                  child: const Text('Erlauben'),
                ),
        ),
        // Der Kern der ganzen Sache. Android verwirft einen Anruf aus dem
        // Hintergrund STUMM — ohne diese Freigabe sieht alles richtig aus und
        // das Telefon wählt trotzdem nur, wenn die App gerade offen ist.
        _statusZeile(
          'Über anderen Apps',
          _anrufCaps.overlay
              ? 'erlaubt — wählt auch bei Bildschirm aus'
              : 'aus — wählt nur bei offener App',
          _anrufCaps.overlay,
          action: _anrufCaps.overlay
              ? null
              : TextButton(
                  onPressed: () => _oeffne(
                    AnrufGatewayService.overlayEinstellungOeffnen,
                    'Systemseite ließ sich nicht öffnen.',
                  ),
                  child: const Text('Erlauben'),
                ),
        ),
        _statusZeile(
          'Vollbild-Meldungen',
          _anrufCaps.vollbild ? 'erlaubt' : 'aus — Rückfallweg schwächer',
          _anrufCaps.vollbild,
          action: _anrufCaps.vollbild
              ? null
              : TextButton(
                  onPressed: () => _oeffne(
                    AnrufGatewayService.vollbildEinstellungOeffnen,
                    'Gibt es erst ab Android 14.',
                  ),
                  child: const Text('Erlauben'),
                ),
        ),
        _statusZeile(
          'Wachdienst',
          _dienstLaeuft
              ? 'läuft'
              : _anrufAn
                  ? 'gestoppt — Aufträge kommen bei geschlossener App nicht an'
                  : 'aus',
          _dienstLaeuft || !_anrufAn,
          action: _anrufAn && !_dienstLaeuft
              ? TextButton(onPressed: _dienstNeuStarten, child: const Text('Starten'))
              : null,
        ),

        if (_anrufAn && !_anrufCaps.overlay) ...[
          const SizedBox(height: 10),
          _hinweis(
            Icons.warning_amber,
            'Ohne diese Freigabe wählt das Telefon nicht von allein',
            'Für das Starten von Bildschirmen gilt ein Gerät mit laufendem '
            'Hintergrunddienst laut Android als „im Hintergrund" — der Anruf '
            'wird dann OHNE Fehlermeldung verworfen. „Über anderen Apps '
            'anzeigen" ist die offizielle Ausnahme davon.\n\n'
            'Es geht auch ohne: dann legt das Telefon eine Benachrichtigung, '
            'und ein Tipp darauf wählt. Der Auftrag geht also nie verloren — '
            'er kostet nur einen Handgriff am Telefon, den er nicht kosten '
            'müsste.',
            Colors.orange,
          ),
        ],
        if (_anrufAn && _anrufCaps.waehltVonAllein) ...[
          const SizedBox(height: 10),
          _hinweis(
            Icons.check_circle_outline,
            'Bereit',
            'Ein Klick am Rechner startet hier den Anruf, auch bei '
            'ausgeschaltetem Bildschirm. Notrufe (110, 112) sind '
            'ausgenommen — die löst man nicht in einem Raum aus, in dem '
            'niemand steht.',
            Colors.green,
          ),
        ],
      ],
    ];
  }

  Widget _statusZeile(String label, String wert, bool ok, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline,
              size: 16, color: ok ? F.h(Colors.green, 600) : F.h(Colors.orange, 700)),
          const SizedBox(width: 8),
          SizedBox(width: 150, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: Text(wert,
                style: TextStyle(fontSize: 13, color: F.h(Colors.grey, 700))),
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
        color: F.h(farbe, 50),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: F.h(farbe, 200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: F.h(farbe, 700)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titel,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: F.h(farbe, 900))),
                const SizedBox(height: 6),
                Text(text, style: TextStyle(fontSize: 12, height: 1.45, color: F.h(farbe, 900))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
