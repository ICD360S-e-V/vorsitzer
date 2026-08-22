import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/anruf_gateway_service.dart';
import '../services/api_service.dart';
import '../services/app_sperre_service.dart';
import '../services/rdp_nur_modus.dart';
import '../services/rdp_service.dart';
import '../services/signatur_gateway_service.dart';
import '../services/speedtest_service.dart';
import '../services/termin_sms_gateway_service.dart';
import '../services/update_service.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';
import 'rdp_session_screen.dart';
import 'remote_desktop_screen.dart';

/// Die ganze App auf einem Gerät, das nur eines tun soll: auf den Bürorechner
/// schalten. Ein Knopf, eine Verbindung, sonst nichts.
///
/// Steht anstelle des [DashboardScreen], wenn [RdpNurModus.istAn] gilt — siehe
/// dort für das Warum und für die Umkehrbarkeit.
///
/// ⚠️ Dieser Bildschirm baut die RDP-Sitzung NICHT selbst auf. Er benutzt
/// dieselben zwei Bausteine wie [RemoteDesktopScreen]: [RdpService] für die
/// serverseitige Sitzung und [RdpSessionScreen] für die Anzeige. An der
/// Verbindung selbst ändert der Kiosk-Modus damit nichts — er lässt nur alles
/// andere weg.
class RdpOnlyScreen extends StatefulWidget {
  final String userName;
  final String currentMitgliedernummer;
  final String currentEmail;
  final String currentRole;

  const RdpOnlyScreen({
    super.key,
    required this.userName,
    required this.currentMitgliedernummer,
    required this.currentEmail,
    required this.currentRole,
  });

  @override
  State<RdpOnlyScreen> createState() => _RdpOnlyScreenState();
}

class _RdpOnlyScreenState extends State<RdpOnlyScreen> {
  final RdpService _svc = RdpService();
  final ApiService _api = ApiService();

  List<RdpProfile> _profile = [];
  RdpProfile? _gewaehlt;
  bool _laden = true;
  bool _verbinde = false;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _hintergrundrollen();
    _aktualisierungPruefen();
    _laden0();
  }

  /// ⚠️ Einmal beim Aufbau, sonst nie — und trotzdem unverzichtbar.
  ///
  /// Ohne das wäre der Kiosk eine Einbahnstraße: das Gerät zeigt keine
  /// Oberfläche mehr, über die je eine neue Fassung käme, und bliebe für immer
  /// auf dem Stand des Tages, an dem der Schalter umgelegt wurde. Eine einzelne
  /// Anfrage je App-Start fällt gegen die Abfragetakte, die hier gerade
  /// wegfallen, nicht ins Gewicht.
  Future<void> _aktualisierungPruefen() async {
    try {
      final dienst = UpdateService();
      final info = await dienst.checkForUpdate();
      if (info == null || !mounted) return;
      final pfad = await dienst.downloadUpdate(info, (_) {});
      if (pfad != null && mounted) await dienst.launchInstaller(pfad);
    } catch (_) {
      // Ein Gerät, das gerade kein Netz hat, soll trotzdem auf den Rechner
      // schalten können — das ist der ganze Zweck dieses Bildschirms.
    }
  }

  /// Was der Kiosk mit den Dauerdiensten des Geräts macht — und das ist NICHT
  /// auf allen Geräten dasselbe.
  ///
  /// ⚠️ Stillgelegt wird ausschließlich auf einem **Google Pixel**. Das ist das
  /// Gerät, für das der Kiosk gedacht ist: es liegt neben dem Schreibtisch und
  /// soll nur auf den Bürorechner schalten. Auf jedem anderen Gerät — allen
  /// voran dem **Tablet mit der SIM**, das SMS-Gateway des Vereins ist — würde
  /// ein versehentlich eingeschalteter Kiosk sonst die Termin-Erinnerungen und
  /// die Signatur-TANs abschalten, und zwar lautlos: der Schalter stünde weiter
  /// auf „an". Dort bleibt es deshalb beim Verhalten des Dashboards.
  Future<void> _hintergrundrollen() async {
    if (!Platform.isAndroid) return;
    if (await RdpNurModus.istPixel()) {
      await _rollenStillegen();
    } else {
      _rollenStarten();
    }
  }

  /// Genau der Block, den sonst das Dashboard beim Aufbau erledigt.
  ///
  /// [TerminSmsGatewayService.initialize] ist der EINZIGE `Workmanager()
  /// .initialize()`-Aufruf der App und richtet zugleich den Wachdienst ein;
  /// daran hängen SMS-Gateway, Fernwahl und Speedtest. Fehlt er auf einem
  /// Gerät, das eine dieser Rollen trägt, verfallen die Aufträge still.
  void _rollenStarten() {
    TerminSmsGatewayService.initialize().then((_) {
      // Steht bewusst hier und nicht in initialize(): die Methode kehrt auf
      // Nicht-Android sofort zurück — dieselbe Falle wie im Dashboard.
      SpeedtestService.jobNachziehen();
    });

    AnrufGatewayService.isEnabled().then((an) async {
      if (!an) return;
      AnrufGatewayService.starteVordergrundTakt();
      final caps = await AnrufGatewayService.faehigkeiten();
      if (caps.telefonie && !caps.anrufrecht) {
        await AnrufGatewayService.anrufrechtAnfragen();
      }
    });
  }

  /// Legt die Dauerdienste dieses Geräts still. „Nur Remote Desktop" heißt
  /// wörtlich nur das — und nur so wird aus dem Kiosk auch ein Gewinn beim Akku.
  ///
  /// ⚠️ NICHT-STARTEN GENÜGT NICHT. Der Wachdienst ist ein Vordergrunddienst
  /// mit `autoRunOnBoot` und `autoRunOnMyPackageReplaced`: einmal eingeschaltet,
  /// kommt er nach jedem Neustart von allein zurück und fragt weiter im
  /// 5-Sekunden-Takt nach Wählaufträgen — ganz gleich, welcher Bildschirm oben
  /// liegt. Am 14.08.2026 waren das **5.216 Anfragen an `anruf/queue.php` an
  /// einem Tag**. Ein Kiosk, der ihn bloß nicht anwirft, spart also nichts.
  /// Die Schalter müssen umgelegt werden, nicht übergangen.
  ///
  /// ⚠️ WAS DAS KOSTET, AUSDRÜCKLICH: ein Klick auf eine Rufnummer am
  /// Linux-Rechner lässt dieses Telefon nicht mehr wählen, und offene
  /// SMS-Aufträge bleiben liegen. Genau das ist die Entscheidung — das Gerät
  /// soll nur noch auf den Bürorechner schalten. Wer beides will, schaltet den
  /// Kiosk in den Einstellungen ab.
  ///
  /// Wirkt nur auf DIESES Gerät: die Schalter liegen lokal.
  Future<void> _rollenStillegen() async {
    try {
      if (await AnrufGatewayService.isEnabled()) {
        // Stoppt den Vordergrundtakt und — wenn auch das SMS-Gateway aus ist —
        // den Wachdienst samt Dauerbenachrichtigung.
        await AnrufGatewayService.setEnabled(false);
      }
      if (await TerminSmsGatewayService.isEnabled()) {
        await TerminSmsGatewayService.setEnabled(false);
      }
      if (await SpeedtestService.autoAktiv()) {
        await SpeedtestService.setzeAuto(false);
      }
      // Gürtel und Hosenträger: nach einem Force Stop oder einem Neustart kann
      // der Dienst laufen, ohne dass ein Schalter davon weiß.
      if (await SignaturGatewayService.laeuft()) {
        await SignaturGatewayService.stoppen();
      }
    } catch (e) {
      // Ein Gerät, dessen Dienste sich gerade nicht abschalten lassen, soll
      // trotzdem auf den Rechner schalten können.
      debugPrint('[RDP-ONLY] Stilllegen fehlgeschlagen: $e');
    }
  }

  Future<void> _laden0() async {
    setState(() {
      _laden = true;
      _fehler = null;
    });
    try {
      final p = await _svc.loadProfiles(widget.currentMitgliedernummer);
      if (!mounted) return;
      setState(() {
        _profile = p;
        // Eine einzige Verbindung ist der Regelfall — dann gibt es nichts zu
        // wählen, nur zu drücken.
        _gewaehlt = p.length == 1 ? p.first : _gewaehlt;
        _laden = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fehler = '$e';
        _laden = false;
      });
    }
  }

  /// Identisch zu [RemoteDesktopScreen]: Sitzung serverseitig anfordern, dann
  /// die WebView öffnen. Beim Verbindungsabbruch prägt der Sitzungsbildschirm
  /// über [RdpProfile.id] eine frische URL — ein verbrauchtes Token lässt sich
  /// nicht neu laden.
  Future<void> _verbinden(RdpProfile p) async {
    setState(() => _verbinde = true);
    try {
      final url = await _svc.requestSessionUrl(widget.currentMitgliedernummer, p.id);
      if (!mounted) return;
      setState(() => _verbinde = false);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RdpSessionScreen(
          sessionUrl: url,
          title: p.name,
          onNeedNewUrl: () =>
              _svc.requestSessionUrl(widget.currentMitgliedernummer, p.id),
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verbinde = false;
        _fehler = '$e';
      });
    }
  }

  // ── Notausgang ────────────────────────────────────────────────────────────

  /// ⚠️ Ohne diesen Weg wäre ein Gerät, dessen RDP-Ziel nicht mehr erreichbar
  /// ist, ein Gerät, das sich nicht mehr selbst reparieren kann: kein Menü,
  /// keine Einstellungen, kein Abmelden. Deshalb liegt er auf einem langen
  /// Tippen auf den Titel — aus dem Weg, aber vorhanden — und die Zeile am
  /// unteren Rand sagt, dass es ihn gibt.
  Future<void> _notausgang() async {
    final wahl = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Dieses Gerät',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.settings_ethernet),
              title: const Text('Verbindungen verwalten'),
              subtitle: const Text('Ziel, Benutzer, Kennwort und Port ändern'),
              onTap: () => Navigator.pop(ctx, 'profile'),
            ),
            ListTile(
              leading: const Icon(Icons.apps),
              title: const Text('Vollständige App anzeigen'),
              subtitle: const Text('Schaltet „Nur Remote Desktop" ab'),
              onTap: () => Navigator.pop(ctx, 'voll'),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Abmelden', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, 'abmelden'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || wahl == null) return;

    switch (wahl) {
      case 'profile':
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RemoteDesktopScreen(
            mitgliedernummer: widget.currentMitgliedernummer,
          ),
        ));
        if (mounted) await _laden0();
        break;
      case 'voll':
        await RdpNurModus.setzen(false);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => DashboardScreen(
            userName: widget.userName,
            currentMitgliedernummer: widget.currentMitgliedernummer,
            currentEmail: widget.currentEmail,
            currentRole: widget.currentRole,
          ),
        ));
        break;
      case 'abmelden':
        await _abmelden();
        break;
    }
  }

  /// Wortgleich zum Dashboard — ein zweiter, abweichender Abmeldeweg wäre eine
  /// Fehlerquelle, die man erst bemerkt, wenn ein Gerät verloren geht.
  Future<void> _abmelden() async {
    await _api.logout();
    // Beim Abmelden faellt auch das App-Passwort weg: es gehoert zu
    // diesem Konto auf diesem Geraet. Wer sich danach wieder anmeldet,
    // braucht ohnehin einen Aktivierungscode — und uebergibt man das
    // Geraet an einen anderen Vorstand, stuende der sonst vor einer
    // Sperre, die nach dem Passwort des Vorgaengers fragt.
    await AppSperreService().zuruecksetzen();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_login', false);
    const secureStorage = FlutterSecureStorage();
    await secureStorage.delete(key: 'mitgliedernummer');
    await secureStorage.delete(key: 'password');
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  // ── Aufbau ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              GestureDetector(
                onLongPress: _notausgang,
                behavior: HitTestBehavior.opaque,
                child: const Text(
                  'ICD360S e.V',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.userName.isEmpty
                    ? widget.currentMitgliedernummer
                    : '${widget.userName} · ${widget.currentMitgliedernummer}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
              ),
              const SizedBox(height: 40),
              Expanded(child: Center(child: _mitte())),
              const Spacer(),
              // Der Notausgang ist absichtlich leise, aber nicht geheim.
              Text(
                'Lange auf den Namen tippen für Einstellungen',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mitte() {
    if (_laden) {
      return const CircularProgressIndicator(color: Colors.white70);
    }
    if (_fehler != null) {
      return _fehlerAnsicht();
    }
    if (_profile.isEmpty) {
      return _leerAnsicht();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_profile.length > 1) ...[
          _auswahl(),
          const SizedBox(height: 24),
        ],
        _knopf(),
      ],
    );
  }

  Widget _knopf() {
    final ziel = _gewaehlt ?? _profile.first;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'Mit ${ziel.name} verbinden',
          child: InkWell(
            onTap: _verbinde ? null : () => _verbinden(ziel),
            borderRadius: BorderRadius.circular(120),
            child: Container(
              width: 176,
              height: 176,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
              ),
              child: Center(
                child: _verbinde
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Icon(Icons.desktop_windows_outlined,
                        size: 84, color: Colors.white),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _verbinde ? 'Verbinde …' : ziel.name,
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '${ziel.username}@${ziel.host}:${ziel.port}',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
        ),
      ],
    );
  }

  /// Mehrere Verbindungen sind nicht der Regelfall, aber sie dürfen den Kiosk
  /// nicht unbedienbar machen.
  Widget _auswahl() {
    final ziel = _gewaehlt ?? _profile.first;
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: ziel.id,
        dropdownColor: const Color(0xFF23233f),
        style: const TextStyle(color: Colors.white, fontSize: 15),
        iconEnabledColor: Colors.white70,
        items: _profile
            .map((p) => DropdownMenuItem<int>(value: p.id, child: Text(p.name)))
            .toList(),
        onChanged: (id) => setState(
            () => _gewaehlt = _profile.firstWhere((p) => p.id == id)),
      ),
    );
  }

  Widget _fehlerAnsicht() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.desktop_access_disabled, size: 56, color: Colors.white38),
        const SizedBox(height: 14),
        const Text('Verbindung fehlgeschlagen',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        const SizedBox(height: 6),
        Text(_fehler ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _laden0,
          icon: const Icon(Icons.refresh),
          label: const Text('Erneut'),
        ),
      ],
    );
  }

  Widget _leerAnsicht() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.desktop_windows_outlined, size: 56, color: Colors.white38),
        const SizedBox(height: 14),
        const Text('Keine Verbindung hinterlegt',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        const SizedBox(height: 6),
        Text('Ziel, Benutzer und Kennwort eintragen — danach genügt ein Tippen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RemoteDesktopScreen(
                mitgliedernummer: widget.currentMitgliedernummer,
              ),
            ));
            if (mounted) await _laden0();
          },
          icon: const Icon(Icons.add),
          label: const Text('Verbindung anlegen'),
        ),
      ],
    );
  }
}
