import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';

import 'api_service.dart';
import 'device_key_service.dart';
import 'logger_service.dart';
import 'platform_service.dart';
import 'secure_store.dart';

final _log = LoggerService();

/// Telefonieren über sipgate, direkt aus der App — SIP over WebSocket gegen
/// `wss://sip.sipgate.de`, Sprache über WebRTC.
///
/// WOFÜR DAS DA IST
/// Der Vorsitzer sitzt am Linux-Rechner. Bisher gab es zwei Wege, und beide
/// haben einen Haken: `tel:` fällt auf einen Handler, den es dort meist nicht
/// gibt, und die Fernwahl ([AnrufFernwahl]) lässt das Vereinstelefon wählen —
/// aber die Sprache bleibt am Telefon und kommt nur über Bluetooth an den
/// Rechner, also über höchstens zehn Meter. Hier landet das Gespräch im
/// Rechner selbst, ohne Entfernungsgrenze.
///
/// WAS AM 11.08.2026 GEGEN DAS ECHTE KONTO NACHGEMESSEN WURDE
///  * `wss://sip.sipgate.de/` antwortet `101` mit `Sec-WebSocket-Protocol: sip`
///  * die Digest-Aufforderung kommt OHNE `qop` (RFC 2069) → **HA1 allein
///    genügt**, ein Klartextpasswort braucht der Client nie
///  * auf ein WebRTC-Angebot antwortet sipgate mit
///    `m=audio … UDP/TLS/RTP/SAVPF`, `a=fingerprint:sha-256`, `a=rtcp-mux`,
///    vollem ICE (trickle, IPv4+IPv6) und **opus/48000/2** an erster Stelle
///
/// ⚠️ NUR IM HAUPT-ISOLAT VERWENDEN. `sip_ua` scheitert in einem
/// Hintergrund-Isolat (PlatformException bei der Activity-Registrierung), und
/// `flutter_foreground_task` fährt grundsätzlich ein *eigenes* Isolat. Der
/// Vordergrunddienst kann diesen Dienst also nicht beherbergen — er kann nur
/// den Prozess am Leben halten, damit das Haupt-Isolat nicht abgeräumt wird.
/// Wer das verwechselt, baut eine Funktion, die auf dem Schreibtisch läuft und
/// nachts still stirbt.
class SipgateService {
  SipgateService._internal();
  static final SipgateService _instance = SipgateService._internal();
  factory SipgateService() => _instance;

  static const String _prefAuto = 'sipgate_auto_registrieren';
  static const String _prefWahlweg = 'anruf_wahlweg_rechner';
  static const String _storeSipId = 'sipgate_sip_id';
  static const String _storeHa1 = 'sipgate_ha1';

  /// Womit das Vereinstelefon wählen soll, wenn der Auftrag vom Rechner kommt.
  ///
  /// `'sim'` = Systemdialer über die SIM-Karte, wie bisher.
  /// `'sipgate'` = VoIP in der App auf dem Tablet; die Sprache geht dann in das
  /// Bluetooth-Headset, das am Tablet hängt.
  ///
  /// Standard bleibt `'sim'`: das ist der Weg, der nachweislich funktioniert,
  /// und ein stiller Wechsel würde bedeuten, dass Anrufe plötzlich über einen
  /// anderen Anschluss mit einer anderen Absendernummer laufen.
  static Future<String> wahlwegFuerRechner() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_prefWahlweg) == 'sipgate' ? 'sipgate' : 'sim';
  }

  static Future<void> setWahlwegFuerRechner(String weg) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefWahlweg, weg == 'sipgate' ? 'sipgate' : 'sim');
  }

  /// Notrufe. Dieselbe Liste wie in [PhoneCallService], `MainActivity`,
  /// `IcdAnrufPlugin`, `anruf/queue.php` und `sipgate_lib.php` — bewusst ohne
  /// 115 und 116117, die keine Notrufe sind.
  ///
  /// ⚠️ Über sipgate wären 110/112 nicht nur unnötig, sondern gefährlich:
  /// sipgate leitet einen Notruf an die Leitstelle des im Konto hinterlegten,
  /// **verifizierten** Notrufstandorts — und für das VoIP-Telefon des Vereins
  /// steht dort „Nicht eingerichtet". Der Ruf landete also bei der falschen
  /// Stelle oder nirgends. Notrufe gehören auf die SIM.
  static const Set<String> _notrufe = {'110', '112', '911', '999'};

  static bool istNotruf(String nummer) =>
      _notrufe.contains(nummer.replaceAll(RegExp(r'\D'), ''));

  final SIPUAHelper _helper = SIPUAHelper();
  final SecureStore _store = SecureStore();
  _SipgateHorcher? _horcher;

  /// Der aktuelle Zustand — Registrierung und, falls eines läuft, das Gespräch.
  final ValueNotifier<SipgateZustand> zustand =
      ValueNotifier<SipgateZustand>(const SipgateZustand());

  Call? _aktuellerRuf;
  Timer? _dauerTakt;
  int? _anrufId; // Zeile in sipgate_anrufe, wird fortgeschrieben
  String? _sipId;
  bool _startetGerade = false;

  bool get istRegistriert => zustand.value.stand == SipgateStand.registriert;
  bool get hatGespraech => zustand.value.gespraech != null;

  /// Ob dieses Gerät überhaupt in Frage kommt.
  ///
  /// Web fällt weg (dort gibt es weder `SecureStore` noch die nativen
  /// WebRTC-Bindungen dieses Projekts); alles andere kann.
  bool get plattformFaehig => !kIsWeb;

  // ── Schalter ───────────────────────────────────────────────────────────────

  /// Ob beim Start automatisch registriert wird. **Aus als Standard**, wie die
  /// Automatik beim Speedtest: eine dauerhaft offene Verbindung schaltet man
  /// selbst ein, sie schaltet sich nicht selbst ein.
  Future<bool> autoAktiv() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_prefAuto) ?? false;
  }

  Future<void> setAutoAktiv(bool an) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefAuto, an);
    if (an) {
      await starten();
    } else {
      await stoppen();
    }
  }

  /// Beim App-Start aufzurufen: registriert nur, wenn der Schalter an ist.
  Future<void> beimStart() async {
    if (!plattformFaehig) return;
    if (await autoAktiv()) await starten();
  }

  // ── Registrierung ──────────────────────────────────────────────────────────

  /// Holt die Anmeldedaten und registriert sich.
  ///
  /// Vom Server kommt **HA1**, nie das Passwort. HA1 wird im [SecureStore]
  /// zwischengelagert, damit ein Netzausfall beim Start nicht bedeutet, dass
  /// das Telefon stumm bleibt — der Wert allein reicht zum Registrieren.
  Future<bool> starten() async {
    if (!plattformFaehig) return false;
    if (_startetGerade) return istRegistriert;
    _startetGerade = true;
    try {
      _setz(stand: SipgateStand.verbindet, meldung: 'Melde an …');

      final cfg = await _konfigHolen();
      if (cfg == null) {
        _setz(
          stand: SipgateStand.fehler,
          meldung: 'Keine Anmeldedaten — im Bildschirm ein VoIP-Telefon hinterlegen.',
        );
        return false;
      }

      final settings = UaSettings()
        ..webSocketUrl = cfg.wssUrl
        ..uri = 'sip:${cfg.sipId}@${cfg.realm}'
        ..authorizationUser = cfg.sipId
        // ⚠️ HA1 statt `password`. `digest_authentication.dart` verlangt dann,
        // dass `realm` genau dem Realm der Aufforderung entspricht — sonst
        // bricht es mit „stored realm does not match" ab, ohne es zu sagen.
        ..ha1 = cfg.ha1
        ..realm = cfg.realm
        ..displayName = cfg.bezeichnung?.isNotEmpty == true
            ? cfg.bezeichnung
            : 'ICD360S e.V'
        ..transportType = TransportType.WS
        ..register = true
        // sipgate gewährt 300 s (nachgemessen). Höher zu bitten bringt nichts,
        // niedriger nur mehr Funkverkehr.
        ..register_expires = 300
        // ⚠️ sipgate schickt telephone-event/8000 im SDP mit, also RFC 2833.
        // Der Standardwert von sip_ua ist INFO — damit landet eine getippte
        // Ziffer in einem SIP-INFO, das die Gegenstelle stillschweigend
        // verwirft, und ein Sprachmenü reagiert nicht.
        ..dtmfMode = DtmfMode.RFC2833
        ..sessionTimers = true
        ..userAgent = 'ICD360S-Vorsitzer'
        ..iceServers = await _iceServer();

      settings.webSocketSettings.userAgent = 'ICD360S-Vorsitzer';

      _horcher ??= _SipgateHorcher(this);
      _helper.removeSipUaHelperListener(_horcher!);
      _helper.addSipUaHelperListener(_horcher!);

      _sipId = cfg.sipId;
      _setz(
        stand: SipgateStand.verbindet,
        sipId: cfg.sipId,
        bezeichnung: cfg.bezeichnung,
        geteilt: cfg.geteilt,
        meldung: 'Melde an …',
      );

      await _helper.start(settings);
      _log.info('sipgate: Anmeldung gestartet für ${cfg.sipId}', tag: 'SIPGATE');
      return true;
    } catch (e) {
      _log.error('sipgate: Anmeldung fehlgeschlagen: $e', tag: 'SIPGATE');
      _setz(stand: SipgateStand.fehler, meldung: 'Anmeldung fehlgeschlagen: $e');
      return false;
    } finally {
      _startetGerade = false;
    }
  }

  Future<void> stoppen() async {
    _dauerTakt?.cancel();
    _dauerTakt = null;
    _aktuellerRuf = null;
    _anrufId = null;
    try {
      _helper.stop();
    } catch (e) {
      _log.warning('sipgate: Abmelden meldete $e', tag: 'SIPGATE');
    }
    _setz(stand: SipgateStand.aus, meldung: null, gespraech: null, loescheGespraech: true);
  }

  /// ICE-Server aus unserem **eigenen** coturn.
  ///
  /// ⚠️ `UaSettings.iceServers` ist standardmäßig mit
  /// `stun:stun.l.google.com:19302` vorbelegt. Ohne dieses Überschreiben würde
  /// jedes sipgate-Gespräch seine Kandidaten bei Google erfragen — genau das,
  /// was [VoiceCallService] ausdrücklich ausschließt. Schlägt der Abruf fehl,
  /// wird die Liste **leer** gelassen: sipgate liefert im SDP einen
  /// öffentlichen Host-Kandidaten, das Gespräch kommt also meist auch ohne
  /// zustande. Lieber kein STUN als ein fremdes.
  Future<List<Map<String, String>>> _iceServer() async {
    try {
      final creds = await ApiService().getTurnCredentials();
      if (creds == null) return <Map<String, String>>[];
      final uris = (creds['uris'] as List).cast<String>();
      final user = '${creds['username']}';
      final pass = '${creds['password']}';
      return [
        for (final u in uris)
          if (u.startsWith('stun:'))
            {'urls': u}
          else
            {'urls': u, 'username': user, 'credential': pass},
      ];
    } catch (e) {
      _log.warning('sipgate: keine TURN-Zugangsdaten ($e) — ohne STUN weiter',
          tag: 'SIPGATE');
      return <Map<String, String>>[];
    }
  }

  Future<_SipgateKonfig?> _konfigHolen() async {
    try {
      final antwort = await ApiService().sipgateAction({
        'action': 'get_config',
        'plattform': _plattformName(),
        if (DeviceKeyService().deviceId != null)
          'device_id': DeviceKeyService().deviceId,
      });
      final daten = antwort['data'];
      if (antwort['success'] == true && daten is Map && daten['eingerichtet'] == true) {
        final cfg = _SipgateKonfig(
          sipId: '${daten['sip_id']}',
          ha1: '${daten['ha1']}',
          realm: '${daten['realm']}',
          wssUrl: '${daten['wss_url']}',
          bezeichnung: daten['bezeichnung'] as String?,
          geteilt: daten['geteilt'] == true,
        );
        await _store.write(key: _storeSipId, value: cfg.sipId);
        await _store.write(key: _storeHa1, value: cfg.ha1);
        return cfg;
      }
      _log.warning('sipgate: Server meldet „${antwort['message']}"', tag: 'SIPGATE');
    } catch (e) {
      _log.warning('sipgate: Konfiguration nicht abrufbar ($e) — versuche Zwischenspeicher',
          tag: 'SIPGATE');
    }

    // Zwischenspeicher. HA1 hängt am Realm; beides liegt fest im Code, also
    // ist der gespeicherte Wert genau dann noch gültig, wenn das Passwort im
    // Konto unverändert ist.
    final sipId = await _store.read(key: _storeSipId);
    final ha1 = await _store.read(key: _storeHa1);
    if (sipId == null || ha1 == null || sipId.isEmpty || ha1.isEmpty) return null;
    return _SipgateKonfig(
      sipId: sipId,
      ha1: ha1,
      realm: 'sipgate.de',
      wssUrl: 'wss://sip.sipgate.de',
      bezeichnung: null,
      geteilt: false,
    );
  }

  String _plattformName() {
    if (PlatformService.isAndroid) return 'android';
    if (PlatformService.isIOS) return 'ios';
    if (PlatformService.isMacOS) return 'macos';
    if (PlatformService.isWindows) return 'windows';
    if (PlatformService.isLinux) return 'linux';
    return 'alle';
  }

  // ── Wählen ─────────────────────────────────────────────────────────────────

  /// Ruft an. Gibt eine Meldung zurück, wenn es nicht geht — `null` heißt: läuft.
  Future<String?> anrufen(String rohNummer, {String? bezeichnung}) async {
    final nummer = normalisieren(rohNummer);
    if (nummer == null) return 'Keine gültige Rufnummer: $rohNummer';

    if (istNotruf(nummer)) {
      // Kein Fehlerfall im technischen Sinn, sondern eine Weigerung mit Grund.
      return 'Notrufe werden nicht über sipgate gewählt — bitte über das '
          'Telefon mit SIM-Karte. Für 110/112 fehlt im sipgate-Konto ein '
          'verifizierter Notrufstandort.';
    }
    if (hatGespraech) return 'Es läuft schon ein Gespräch.';

    if (!istRegistriert) {
      final ok = await starten();
      if (!ok) return zustand.value.meldung ?? 'Nicht bei sipgate angemeldet.';
      // Nach `start()` steht die Registrierung nicht sofort; kurz warten,
      // sonst antwortet sip_ua mit „Not connected, you will need to register".
      if (!await _wartenAufRegistrierung()) {
        return 'Anmeldung bei sipgate kam nicht zustande.';
      }
    }

    _anrufId = await _anrufProtokoll(
      richtung: 'aus',
      nummer: nummer,
      bezeichnung: bezeichnung,
      status: 'gestartet',
    );

    final ziel = 'sip:$nummer@sipgate.de';
    final ok = await _helper.call(ziel, voiceOnly: true);
    if (!ok) {
      await _anrufProtokoll(
        anrufId: _anrufId,
        status: 'fehler',
        fehler: 'sip_ua: nicht verbunden',
      );
      return 'Anruf konnte nicht gestartet werden — keine Verbindung zu sipgate.';
    }

    _setzGespraech(SipgateGespraech(
      nummer: nummer,
      name: bezeichnung,
      eingehend: false,
      stand: SipgateGespraechStand.waehlt,
    ));
    return null;
  }

  Future<bool> _wartenAufRegistrierung() async {
    for (var i = 0; i < 40; i++) {
      if (istRegistriert) return true;
      if (zustand.value.stand == SipgateStand.fehler) return false;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return istRegistriert;
  }

  void annehmen() {
    final ruf = _aktuellerRuf;
    if (ruf == null) return;
    ruf.answer(_helper.buildCallOptions(true));
  }

  void ablehnen() {
    final ruf = _aktuellerRuf;
    if (ruf == null) return;
    // 603 Decline, nicht 486 Busy: „abgelehnt" ist die Wahrheit, „belegt" wäre
    // eine Ausrede und schickt den Anrufer bei sipgate in die Mailbox-Logik
    // für Besetztfälle.
    ruf.hangup({'status_code': 603});
  }

  void auflegen() {
    final ruf = _aktuellerRuf;
    if (ruf == null) return;
    ruf.hangup();
  }

  void stummSchalten(bool stumm) {
    final ruf = _aktuellerRuf;
    if (ruf == null) return;
    if (stumm) {
      ruf.mute(true, false);
    } else {
      ruf.unmute(true, false);
    }
    final g = zustand.value.gespraech;
    if (g != null) _setzGespraech(g.kopie(stumm: stumm));
  }

  void dtmf(String ton) {
    _aktuellerRuf?.sendDTMF(ton);
  }

  /// Liest aus einem Anzeigetext die wählbare Rufnummer und bringt sie nach
  /// E.164.
  ///
  /// ⚠️ Kurznummern bleiben unangetastet: aus `116117` darf niemals
  /// `+49116117` werden — das ist keine gültige Rufnummer, und der ärztliche
  /// Bereitschaftsdienst ist genau die Nummer, die im Ernstfall gehen muss.
  /// Dieselbe Regel steht in `sipgate_lib.php`; die beiden müssen
  /// übereinstimmen, sonst protokolliert der Server etwas anderes als gewählt
  /// wurde.
  static String? normalisieren(String roh) {
    final sauber = roh.replaceAll(RegExp(r'[^0-9+*#]'), '');
    if (sauber.isEmpty) return null;

    if (sauber.startsWith('*') || sauber.startsWith('#')) return sauber;

    if (sauber.startsWith('+')) {
      final rest = sauber.replaceAll(RegExp(r'\D'), '');
      return rest.isEmpty ? null : '+$rest';
    }
    if (sauber.startsWith('00')) {
      final rest = sauber.substring(2);
      return rest.isEmpty ? null : '+$rest';
    }
    if (sauber.startsWith('0') && sauber.length >= 7) {
      return '+49${sauber.substring(1)}';
    }
    if (sauber.replaceAll(RegExp(r'\D'), '').length < 3) return null;
    return sauber;
  }

  // ── Innenleben ─────────────────────────────────────────────────────────────

  void _setz({
    SipgateStand? stand,
    String? sipId,
    String? bezeichnung,
    bool? geteilt,
    String? meldung,
    SipgateGespraech? gespraech,
    bool loescheGespraech = false,
  }) {
    final alt = zustand.value;
    zustand.value = SipgateZustand(
      stand: stand ?? alt.stand,
      sipId: sipId ?? alt.sipId,
      bezeichnung: bezeichnung ?? alt.bezeichnung,
      geteilt: geteilt ?? alt.geteilt,
      meldung: meldung,
      gespraech: loescheGespraech ? null : (gespraech ?? alt.gespraech),
    );
  }

  void _setzGespraech(SipgateGespraech? g) {
    _setz(gespraech: g, loescheGespraech: g == null);
  }

  void _registrierung(RegistrationState state) {
    switch (state.state) {
      case RegistrationStateEnum.REGISTERED:
        _log.info('sipgate: registriert ($_sipId)', tag: 'SIPGATE');
        _setz(stand: SipgateStand.registriert, meldung: null);
        break;
      case RegistrationStateEnum.REGISTRATION_FAILED:
        final grund = state.cause?.cause ?? state.cause?.status_code?.toString() ?? '';
        _log.error('sipgate: Anmeldung abgelehnt ($grund)', tag: 'SIPGATE');
        _setz(
          stand: SipgateStand.fehler,
          meldung: grund.isEmpty
              ? 'sipgate hat die Anmeldung abgelehnt.'
              : 'sipgate hat die Anmeldung abgelehnt: $grund',
        );
        break;
      case RegistrationStateEnum.UNREGISTERED:
      case RegistrationStateEnum.NONE:
      case null:
        if (zustand.value.stand != SipgateStand.aus) {
          _setz(stand: SipgateStand.aus, meldung: 'Abgemeldet.');
        }
        break;
    }
  }

  void _transport(TransportState state) {
    if (state.state == TransportStateEnum.DISCONNECTED &&
        zustand.value.stand == SipgateStand.registriert) {
      // sip_ua baut selbst wieder auf; das hier ist nur die Anzeige, damit ein
      // Abriss sichtbar ist statt still.
      _setz(stand: SipgateStand.verbindet, meldung: 'Verbindung unterbrochen — baue neu auf …');
    }
  }

  void _gespraech(Call call, CallState state) {
    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
        _aktuellerRuf = call;
        if (call.direction == Direction.incoming) {
          final nummer = call.remote_identity ?? 'unbekannt';
          _anrufProtokoll(
            richtung: 'ein',
            nummer: nummer,
            bezeichnung: call.remote_display_name,
            status: 'klingelt',
          ).then((id) => _anrufId = id);
          _setzGespraech(SipgateGespraech(
            nummer: nummer,
            name: call.remote_display_name,
            eingehend: true,
            stand: SipgateGespraechStand.klingelt,
          ));
        }
        break;

      case CallStateEnum.PROGRESS:
        _anrufProtokoll(anrufId: _anrufId, status: 'klingelt');
        break;

      case CallStateEnum.CONFIRMED:
      case CallStateEnum.ACCEPTED:
        _aktuellerRuf = call;
        _tonWegWaehlen();
        final g = zustand.value.gespraech;
        if (g != null && g.stand != SipgateGespraechStand.verbunden) {
          _setzGespraech(g.kopie(
            stand: SipgateGespraechStand.verbunden,
            verbundenSeit: DateTime.now(),
          ));
          _dauerTakt?.cancel();
          _dauerTakt = Timer.periodic(const Duration(seconds: 1), (_) {
            final akt = zustand.value.gespraech;
            if (akt == null) return;
            // Nur anstoßen, damit die Dauer im Bildschirm weiterläuft.
            _setzGespraech(akt.kopie());
          });
          _anrufProtokoll(anrufId: _anrufId, status: 'verbunden');
        }
        break;

      case CallStateEnum.FAILED:
      case CallStateEnum.ENDED:
        final beendet = zustand.value.gespraech;
        final dauer = beendet?.dauerSekunden ?? 0;
        final grund = state.cause?.cause;
        final warEingehendUnbeantwortet = beendet != null &&
            beendet.eingehend &&
            beendet.stand != SipgateGespraechStand.verbunden;
        _anrufProtokoll(
          anrufId: _anrufId,
          status: state.state == CallStateEnum.FAILED
              ? 'fehler'
              : warEingehendUnbeantwortet
                  ? 'verpasst'
                  : 'beendet',
          dauerS: dauer,
          fehler: state.state == CallStateEnum.FAILED ? (grund ?? 'unbekannt') : null,
        );
        _dauerTakt?.cancel();
        _dauerTakt = null;
        _aktuellerRuf = null;
        _anrufId = null;
        _setzGespraech(null);
        break;

      case CallStateEnum.MUTED:
      case CallStateEnum.UNMUTED:
      case CallStateEnum.CONNECTING:
      case CallStateEnum.STREAM:
      case CallStateEnum.HOLD:
      case CallStateEnum.UNHOLD:
      case CallStateEnum.REFER:
      case CallStateEnum.NONE:
        break;
    }
  }

  /// Schickt die Sprache dorthin, wo das Headset hängt.
  ///
  /// WARUM DAS NICHT VON ALLEIN PASSIERT
  /// Das Tablet ist mit einem Bluetooth-Headset gekoppelt. WebRTC routet die
  /// Sprache aber nach der Vorgabe des Systems, und die ist bei einem
  /// Kommunikationsstrom nicht zwangsläufig das Headset — ohne Zutun landet das
  /// Gespräch im Tablet-Lautsprecher, während der Vorsitzer Kopfhörer trägt.
  /// `setSpeakerphoneOnButPreferBluetooth()` ist der dafür vorgesehene Weg des
  /// Plugins (es bringt `audioswitch` mit, das SCO-Geräte kennt).
  ///
  /// ⚠️ Bekannte Schwäche von flutter_webrtc: eine von Hand gesetzte Route
  /// kann nach wenigen Sekunden auf die Systemvorgabe zurückspringen, und das
  /// Plugin verrät weder die aktuelle Route noch meldet es eine Änderung.
  /// Deshalb wird hier die eingebaute Bevorzugung benutzt statt
  /// `selectAudioOutput` — und deshalb steht hier kein „ist erledigt", sondern
  /// eine Zeile im Protokoll, an der man es auf dem Gerät nachprüfen kann.
  ///
  /// Nur Android/iOS: auf dem Linux-Rechner gibt es diese Umschaltung nicht,
  /// dort entscheidet PipeWire.
  Future<void> _tonWegWaehlen() async {
    if (!PlatformService.isAndroid && !PlatformService.isIOS) return;
    try {
      await Helper.setSpeakerphoneOnButPreferBluetooth();
      _log.info('sipgate: Sprachausgabe auf Bluetooth bevorzugt', tag: 'SIPGATE');
    } catch (e) {
      _log.warning('sipgate: Sprachausgabe nicht umgestellt ($e) — System entscheidet',
          tag: 'SIPGATE');
    }
  }

  /// Schreibt den eigenen Verlauf mit.
  ///
  /// ⚠️ Nicht dasselbe wie sipgates Channel Events: die sagen, was bei sipgate
  /// angekommen ist. Diese Zeilen sagen, was in unserer App passiert ist —
  /// samt der Anrufe, die nie zustande kamen, und des Grundes. Genau die
  /// fehlen im Verlauf des Anbieters.
  ///
  /// Wirft nie: ein Protokolleintrag darf ein laufendes Gespräch nicht stören.
  Future<int?> _anrufProtokoll({
    int? anrufId,
    String? richtung,
    String? nummer,
    String? bezeichnung,
    required String status,
    int? dauerS,
    String? fehler,
  }) async {
    if (anrufId == null && richtung == null) return null;
    try {
      final antwort = await ApiService().sipgateAction({
        'action': 'log_anruf',
        if (anrufId != null) 'anruf_id': anrufId,
        if (richtung != null) 'richtung': richtung,
        if (nummer != null) 'nummer': nummer,
        if (bezeichnung != null && bezeichnung.isNotEmpty) 'bezeichnung': bezeichnung,
        'status': status,
        if (dauerS != null) 'dauer_s': dauerS,
        if (fehler != null) 'fehler': fehler,
        if (_sipId != null) 'sip_id': _sipId,
        if (DeviceKeyService().deviceId != null) 'device_id': DeviceKeyService().deviceId,
      });
      final id = (antwort['data'] as Map?)?['anruf_id'];
      return id is int ? id : anrufId;
    } catch (e) {
      _log.warning('sipgate: Verlauf nicht geschrieben ($e)', tag: 'SIPGATE');
      return anrufId;
    }
  }
}

/// Getrennte Klasse, damit [SipgateService] nicht sechs Rückrufe des
/// `sip_ua`-Vertrags in seiner öffentlichen Oberfläche tragen muss.
class _SipgateHorcher implements SipUaHelperListener {
  _SipgateHorcher(this._dienst);
  final SipgateService _dienst;

  @override
  void registrationStateChanged(RegistrationState state) => _dienst._registrierung(state);

  @override
  void transportStateChanged(TransportState state) => _dienst._transport(state);

  @override
  void callStateChanged(Call call, CallState state) => _dienst._gespraech(call, state);

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}
}

class _SipgateKonfig {
  const _SipgateKonfig({
    required this.sipId,
    required this.ha1,
    required this.realm,
    required this.wssUrl,
    required this.bezeichnung,
    required this.geteilt,
  });
  final String sipId;
  final String ha1;
  final String realm;
  final String wssUrl;
  final String? bezeichnung;
  final bool geteilt;
}

enum SipgateStand { aus, verbindet, registriert, fehler }

enum SipgateGespraechStand { waehlt, klingelt, verbunden }

@immutable
class SipgateZustand {
  const SipgateZustand({
    this.stand = SipgateStand.aus,
    this.sipId,
    this.bezeichnung,
    this.geteilt = false,
    this.meldung,
    this.gespraech,
  });

  final SipgateStand stand;
  final String? sipId;
  final String? bezeichnung;

  /// Zwei Geräte hängen an derselben SIP-ID. Bei sipgate klingeln dann beide
  /// (Parallelruf) — kein Fehler, aber der Bildschirm soll es sagen können.
  final bool geteilt;
  final String? meldung;
  final SipgateGespraech? gespraech;
}

@immutable
class SipgateGespraech {
  const SipgateGespraech({
    required this.nummer,
    required this.eingehend,
    required this.stand,
    this.name,
    this.verbundenSeit,
    this.stumm = false,
  });

  final String nummer;
  final String? name;
  final bool eingehend;
  final SipgateGespraechStand stand;
  final DateTime? verbundenSeit;
  final bool stumm;

  int get dauerSekunden => verbundenSeit == null
      ? 0
      : DateTime.now().difference(verbundenSeit!).inSeconds;

  SipgateGespraech kopie({
    SipgateGespraechStand? stand,
    DateTime? verbundenSeit,
    bool? stumm,
  }) =>
      SipgateGespraech(
        nummer: nummer,
        name: name,
        eingehend: eingehend,
        stand: stand ?? this.stand,
        verbundenSeit: verbundenSeit ?? this.verbundenSeit,
        stumm: stumm ?? this.stumm,
      );
}
