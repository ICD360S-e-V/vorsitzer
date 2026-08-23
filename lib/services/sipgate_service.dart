import 'dart:async';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:icd_anruf/icd_anruf.dart' show icdAnrufChannel;
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show AndroidAudioConfiguration, Helper;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';

import 'api_service.dart';
import 'device_key_service.dart';
import 'logger_service.dart';
import 'notification_service.dart';
import 'platform_service.dart';
import 'secure_store.dart';
import 'voice_call_service.dart' show iceServerEintraege;

final _log = LoggerService();

// ── Wiederanmeldung nach einer abgelehnten Anmeldung ────────────────────────
//
// ⚠️ `sip_ua` WIEDERHOLT VON SICH AUS NICHT. Nachgesehen in `sip_ua-1.1.0`
// und gegen `main` von `flutter-webrtc/dart-sip-ua` gegengeprüft:
// `registrator.dart` → `_registrationFailure()` setzt `_registering = false`,
// meldet den Fehlschlag und hört auf. Kein Timer, kein Rückfall. Die einzige
// selbsttätige Neuanmeldung hängt in `ua.dart` → `onTransportConnect()`, also
// am **Wiederaufbau des WebSockets**.
//
// Daraus folgt genau die Lücke, die das hier schließt: reißt die Verbindung,
// heilt es von selbst (der Socket versucht es mit 2–30 s Abstand erneut).
// Wird aber ein REGISTER abgelehnt, während der Socket steht — eine
// Zeitüberschreitung bei der Erneuerung nach 295 s, weil Android den Prozess
// eingefroren hatte, oder ein `503` der Gegenstelle —, dann bleibt es dabei.
// Für immer. Auf einem Tablet, das dauerhaft auf dem Tisch liegt, heißt das:
// es klingelt nichts mehr, und das einzige Zeichen ist ein rotes Symbol, das
// jemandem auffallen muss.

/// Vorgabewert der RFC für den Fall, dass gar keine Verbindung mehr steht —
/// genau unsere Lage, wir haben nur eine.
const Duration sipgateWartebasis = Duration(seconds: 30);

/// ⚠️ 300 s statt der 1800 s aus RFC 5626, und das ist nachgerechnet, nicht
/// geschätzt: am Deckel liegen zwischen zwei REGISTER 150–300 s, die gesunde
/// Erneuerung läuft alle 295 s (`register_expires = 300`, und
/// `registrator.dart:227` erneuert fünf Sekunden vorher). Der Wiederholversuch
/// erzeugt also **nie mehr Verkehr als eine funktionierende Anmeldung** —
/// während eine halbe Stunde Stille genau der Fehler ist, den wir beheben.
/// Dieselbe Größenordnung benutzt PJSIP als Vorgabe (`reg_retry_interval`,
/// 300 s).
const Duration sipgateWartedeckel = Duration(seconds: 300);

/// Wie lange nach dem `fehlversuche`-ten vergeblichen Anlauf gewartet wird.
///
/// Form nach RFC 5626 § 4.5 („Flow Recovery"):
///
///     W = min(max-time, base-time × 2^consecutive-failures)
///
/// und die tatsächliche Wartezeit ist „a uniform random time between 50 and
/// 100% of the upper-bound wait time". Mit [sipgateWartebasis] ergibt der
/// erste Anlauf damit 30–60 s — dieselbe Spanne, die die RFC im Fließtext
/// ausdrücklich nennt.
///
/// ⚠️ Der Zufall ist kein Schmuck. Ohne ihn klopfen nach einem Ausfall der
/// Gegenseite alle Geräte in derselben Sekunde wieder an, und der zweite
/// Versuch scheitert aus demselben Grund wie der erste.
///
/// [zufall] wird hereingereicht statt hier gezogen, damit der Test die Spanne
/// an ihren Rändern festnageln kann statt sie zu würfeln.
Duration sipgateWartezeit(int fehlversuche, double zufall) {
  final n = fehlversuche < 1 ? 1 : fehlversuche;
  // Ab dem vierten Fehlversuch greift ohnehin der Deckel; die Begrenzung auf
  // 30 Verdopplungen hält `1 << n` aus dem Überlauf, falls ein Gerät wochenlang
  // vergeblich anklopft.
  final roh = n > 30
      ? sipgateWartedeckel.inSeconds
      : sipgateWartebasis.inSeconds * (1 << n);
  final obergrenze =
      roh < sipgateWartedeckel.inSeconds ? roh : sipgateWartedeckel.inSeconds;
  final anteil = zufall.isNaN ? 0.0 : zufall.clamp(0.0, 1.0);
  return Duration(seconds: (obergrenze * (0.5 + 0.5 * anteil)).round());
}

/// Was mit einem abgelehnten REGISTER zu tun ist.
enum SipgateAnmeldeFolge {
  /// Netz oder Gegenstelle — später noch einmal, mit wachsendem Abstand.
  wiederholen,

  /// Die Zugangsdaten passen nicht. Einmal frisch vom **eigenen** Server holen,
  /// bevor weiter geklopft wird: dort liegt der HA1, und wurde das
  /// sipgate-Passwort gewechselt, ist der zwischengespeicherte Wert veraltet.
  /// Bloßes Wiederholen bekäme dann bis in alle Ewigkeit denselben Korb.
  datenErneuern,

  /// Auch mit frisch geholten Daten abgelehnt. Weiterprobieren hilft nicht
  /// mehr, es muss jemand die Zugangsdaten richten.
  aufgeben,
}

/// Ordnet einen abgelehnten Anmeldeversuch ein.
///
/// ⚠️ Die Einteilung ist absichtlich schmal: **alles außer der
/// Anmelde-Familie gilt als vorübergehend.** Ein `408` entsteht bei
/// `registrator.dart:150`, wenn gar keine Antwort kam, ein `500` bei
/// `:155` für einen Transportfehler — beides sind genau die Fälle, für die
/// wiederholt werden muss. Wer hier eine lange Liste „endgültiger" Codes
/// pflegt, schaltet die Wiederholung irgendwann für einen Fall ab, der sich
/// von selbst erholt hätte. PJSIP wiederholt aus demselben Grund
/// **jeden** Fehlschlag.
///
/// `401`/`407` erreichen uns nur, wenn die Antwort auf die Aufforderung
/// ebenfalls abgelehnt wurde — die Aufforderung selbst beantwortet `sip_ua`
/// intern. `403` und `404` heißen: dieses Konto oder dieses Telefon gibt es so
/// nicht (mehr).
SipgateAnmeldeFolge sipgateAnmeldeFolge(
  int? code, {
  required bool datenSchonErneuert,
}) {
  const zugangsdaten = {401, 403, 404, 407};
  if (code == null || !zugangsdaten.contains(code)) {
    return SipgateAnmeldeFolge.wiederholen;
  }
  return datenSchonErneuert
      ? SipgateAnmeldeFolge.aufgeben
      : SipgateAnmeldeFolge.datenErneuern;
}

/// Ob ein eintreffendes `UNREGISTERED` den Zustand auf [SipgateStand.aus]
/// setzen darf.
///
/// ⚠️ DIESE REGEL SIEHT ÜBERFLÜSSIG AUS UND IST ES NICHT.
/// Scheitert die **Erneuerung** einer bereits stehenden Anmeldung, feuert
/// `sip_ua` zwei Ereignisse direkt hintereinander:
/// `registrator.dart` → `_registrationFailure()` ruft erst
/// `_ua.registrationFailed(...)`, und weil `_registered` noch wahr war, gleich
/// danach `_ua.unregistered(...)`. In `sip_ua_helper.dart` werden daraus
/// `REGISTRATION_FAILED` und unmittelbar darauf `UNREGISTERED`.
///
/// Ohne diese Regel überschriebe das zweite Ereignis den gerade gesetzten
/// Fehlerzustand mit „Abgemeldet." — das Symbol in der Kopfleiste wäre dann
/// nicht einmal rot, sondern sähe aus, als hätte jemand die Telefonie
/// absichtlich ausgeschaltet. Das ist die schlimmere der beiden Anzeigen: rot
/// lädt zum Nachsehen ein, „aus" nicht.
bool sipgateAbmeldungUebernehmen({
  required bool anlaufGeplant,
  required SipgateStand aktuell,
}) {
  if (anlaufGeplant) return false;
  return aktuell != SipgateStand.aus;
}

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

  /// Die beiden Gesprächsbeine. `A` ist das erste, `B` das hinzugewählte.
  Call? _rufA;
  Call? _rufB;

  /// Welches Bein der Vorsitzer gerade spricht. Bei einer Konferenz zählt `A`
  /// als das Bein, an das die Steuercodes gehen.
  String _aktiv = 'A';

  Timer? _dauerTakt;
  int? _anrufIdA; // Zeilen in sipgate_anrufe, werden fortgeschrieben
  int? _anrufIdB;
  String? _sipId;
  bool _startetGerade = false;

  /// Läuft die Wiederanmeldung. Siehe die Begründung bei [sipgateWartezeit].
  Timer? _erneutTakt;

  /// Vergebliche Anläufe in Folge — der Exponent aus RFC 5626 § 4.5.
  /// Wird bei jeder erfolgreichen Anmeldung auf null gesetzt.
  int _fehlversuche = 0;

  /// Ob wegen abgelehnter Zugangsdaten schon einmal frisch beim eigenen Server
  /// nachgefragt wurde. Genau **einmal** — sonst würde ein dauerhaft falsches
  /// Passwort unseren eigenen Server im Minutentakt befragen.
  bool _datenErneuert = false;

  /// Ob **der nächste** Anlauf die Zugangsdaten neu holen soll.
  ///
  /// ⚠️ Getrennt von [_datenErneuert], und das ist kein Doppel: jenes merkt
  /// sich dauerhaft, dass es schon einmal versucht wurde (damit die Einordnung
  /// beim nächsten `403` auf „aufgeben" springt), dieses gilt nur für den
  /// einen eingeplanten Anlauf. Mit nur einem Merker liefe jeder spätere
  /// Anlauf — auch der nach einem simplen `503` — durch das volle
  /// [starten], also durch Neuaufbau der Verbindung und die
  /// Berechtigungsdialoge.
  bool _anlaufHoltDaten = false;

  /// Ob `_helper.start()` überhaupt schon einmal durchgelaufen ist.
  ///
  /// ⚠️ Ohne das drehte sich die Wiederholung im Kreis: scheitert der allererste
  /// Anlauf schon am Holen der Zugangsdaten, gibt es noch gar keinen UA — und
  /// `SIPUAHelper.register()` läuft dann (`sip_ua_helper.dart:81`) in ein
  /// `assert(_ua != null)` bzw. im Release in einen Null-Zugriff. Die
  /// Wiederholung müsste also ewig `register()` rufen, während das, was
  /// wirklich fehlt, nur [starten] beschaffen kann.
  bool _uaGebaut = false;

  /// Ob die Anmeldung überhaupt gewollt ist, also zwischen [starten] und
  /// [stoppen].
  ///
  /// ⚠️ Ohne das würde ein bereits eingeplanter Wiederholversuch die
  /// Anmeldung wieder hochziehen, nachdem der Nutzer sie gerade abgeschaltet
  /// hat — ein Schalter, der von selbst zurückspringt.
  bool _gewollt = false;

  /// Wann der nächste Anlauf ansteht. `null` heißt: keiner geplant.
  /// Der Bildschirm zeigt daraus die verbleibende Zeit.
  DateTime? _naechsterVersuch;
  DateTime? get naechsterVersuch => _naechsterVersuch;

  /// Nummer des laufenden Anlaufs, für die Anzeige („3. Versuch").
  int get fehlversuche => _fehlversuche;

  /// Die Streuung aus RFC 5626 § 4.5. Kein `Random.secure()` — das hier
  /// verteilt Anläufe, es schützt nichts.
  final Random _zufall = Random();

  /// Grund der letzten Absage, im Klartext mit SIP-Code. Der Bildschirm zeigt
  /// ihn, damit „Fehler" nicht das Letzte ist, was man sieht.
  String? _letzteAbsage;
  String? get letzteAbsage => _letzteAbsage;

  bool get istRegistriert => zustand.value.stand == SipgateStand.registriert;
  bool get hatGespraech => zustand.value.gespraech != null;

  /// Ob noch ein zweites Bein dazupasst — die Anlage kann drei Teilnehmer.
  bool get kannHinzuwaehlen =>
      zustand.value.gespraech?.stand == SipgateGespraechStand.verbunden &&
      zustand.value.zweites == null;

  /// Ob `*5` jetzt Sinn hätte: zwei Beine, beide verbunden, noch keine
  /// Konferenz.
  bool get kannKonferenz =>
      !zustand.value.konferenz && zustand.value.verbundeneBeine == 2;

  /// Ob auf DIESEM Gerät in der App telefoniert wird.
  ///
  /// **Nur Android**, und das ist eine Festlegung, keine technische Grenze:
  /// `sip_ua` und `flutter_webrtc` laufen auch auf Linux, und die Probe am
  /// 11.08.2026 lief von einem Linux-Rechner aus. Gewollt ist es trotzdem
  /// nicht.
  ///
  /// WARUM NUR DAS TABLET
  /// Das Samsung Tab A11 ist das Gerät mit dem Bluetooth-Headset, es liegt auf
  /// dem Tisch und die App läuft dort ohnehin dauerhaft. Der Linux-Rechner
  /// **schickt** den Auftrag (`wahlweg: sipgate`) und bleibt Bedienpult —
  /// registrieren soll er sich nicht:
  ///
  ///  * zwei Registrierungen auf derselben SIP-ID heissen Parallelruf, also
  ///    klingelt es an zwei Stellen und wer zuerst abnimmt, gewinnt. Auf einem
  ///    Rechner ohne Headset ist das nur störend.
  ///  * PipeWire müsste am Rechner erst als Headset-Rolle eingerichtet werden;
  ///    das ist Bastelei an einem Gerät, das den Ton gar nicht braucht.
  ///  * eine Registrierung weniger ist ein Weg weniger, auf dem ein Anruf
  ///    unbemerkt im falschen Lautsprecher landet.
  ///
  /// Der Rest des Bildschirms (Wahlweg, Verlauf, VoIP-Telefone) bleibt überall
  /// erreichbar — konfiguriert und nachgesehen wird am grossen Bildschirm.
  bool get plattformFaehig => !kIsWeb && PlatformService.isAndroid;

  // ── Schalter ───────────────────────────────────────────────────────────────

  /// Ob beim Start automatisch registriert wird.
  ///
  /// **Auf Android an, sonst aus** — und zwar als Vorgabe, nicht als Zwang: der
  /// Schalter im Bildschirm überschreibt beides und bleibt gespeichert.
  ///
  /// WARUM DIE VORGABE HIER ANDERS IST ALS BEIM SPEEDTEST
  /// Beim Speedtest ist die Automatik aus, weil sie Datenvolumen verbraucht und
  /// niemand sie braucht, der nicht danach fragt. Hier ist es umgekehrt: die
  /// Registrierung IST die Funktion. Ohne sie klingelt kein eingehender Anruf,
  /// und ein Auftrag vom Rechner mit `wahlweg: sipgate` scheitert — beides sähe
  /// auf dem Tablet nach „kaputt" aus, während nur ein Schalter aus war.
  ///
  /// Und weil [plattformFaehig] auf Android beschränkt ist, kann diese Vorgabe
  /// kein anderes Gerät zum Mitklingeln bringen.
  Future<bool> autoAktiv() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_prefAuto) ?? PlatformService.isAndroid;
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
    _knoepfeHorchen();
    if (await autoAktiv()) await starten();
  }

  /// Läuft bewusst die ganze Prozesslebensdauer: [SipgateService] ist ein
  /// Singleton ohne Ende, und der Horcher muss auch dann noch da sein, wenn die
  /// Registrierung zwischendurch aus und wieder an war. Ein `cancel()` in
  /// `stoppen()` würde die Knöpfe nach dem ersten Abmelden tot machen.
  // ignore: cancel_subscriptions
  StreamSubscription<String>? _knopfHorcher;

  /// Hört auf die Knöpfe aus der Anruf-Benachrichtigung.
  ///
  /// Der Umweg über den Klick-Strom des [NotificationService] statt eines
  /// direkten Aufrufs: sonst müsste der Benachrichtigungsdienst den
  /// SIP-Dienst kennen, und er kennt sonst keinen einzigen Fachdienst.
  void _knoepfeHorchen() {
    _knopfHorcher ??= NotificationService().onNotificationClicked.listen((e) {
      if (e == 'sipgate-aktion:${NotificationService.aktionAnnehmen}') {
        annehmen();
      } else if (e == 'sipgate-aktion:${NotificationService.aktionAblehnen}') {
        ablehnen();
      }
    });
  }

  // ── Registrierung ──────────────────────────────────────────────────────────

  /// Holt die Anmeldedaten und registriert sich.
  ///
  /// Vom Server kommt **HA1**, nie das Passwort. HA1 wird im [SecureStore]
  /// zwischengelagert, damit ein Netzausfall beim Start nicht bedeutet, dass
  /// das Telefon stumm bleibt — der Wert allein reicht zum Registrieren.
  ///
  /// [istWiederholung] setzt den Fehlversuchszähler **nicht** zurück — sonst
  /// bliebe der Abstand zwischen zwei Anläufen ewig bei 30–60 s, statt zu
  /// wachsen. Ein Druck auf „Anmelden" ist dagegen eine neue Absicht und fängt
  /// von vorn an.
  Future<bool> starten({bool istWiederholung = false}) async {
    if (!plattformFaehig) {
      // Kein stilles `false`: wer am Rechner auf „Anmelden" drückt, muss den
      // Grund sehen, sonst hält er es für einen Fehler.
      _setz(
        stand: SipgateStand.aus,
        meldung: 'In-App-Telefonie läuft nur auf dem Tablet. Von hier aus wird '
            'gewählt, indem der Auftrag ans Tablet geht — siehe „Anruf vom '
            'Rechner" weiter unten.',
      );
      return false;
    }
    if (_startetGerade) return istRegistriert;
    _startetGerade = true;
    _gewollt = true;
    // Ein von Hand ausgelöster Anlauf räumt einen eingeplanten weg: sonst
    // liefe später ein zweites REGISTER auf eine Anmeldung, die längst steht.
    _erneutTakt?.cancel();
    _erneutTakt = null;
    _naechsterVersuch = null;
    if (!istWiederholung) {
      _fehlversuche = 0;
      _datenErneuert = false;
      _anlaufHoltDaten = false;
    }
    try {
      _setz(stand: SipgateStand.verbindet, meldung: 'Melde an …');

      final cfg = await _konfigHolen();
      if (cfg == null) {
        // ⚠️ Auch das darf nicht dauerhaft still bleiben. Ist unser eigener
        // Server beim Start des Tablets kurz nicht erreichbar UND liegt noch
        // nichts im Zwischenspeicher, wäre das Telefon sonst bis zum nächsten
        // Neustart tot. Und wird das VoIP-Telefon erst später auf dem Server
        // hinterlegt, holt der nächste Anlauf es von selbst ab.
        _fehlversuche++;
        _wiederholungPlanen(
          'Keine Anmeldedaten — im Bildschirm ein VoIP-Telefon hinterlegen.',
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
        //
        // Nachgesehen, weil davon abhängt, ob eingehende Anrufe still
        // ausfallen: `registrator.dart:227` erneuert bei
        // `(expires * 1000) - 5000`, also nach 295 s — fünf Sekunden vor
        // Ablauf. Kein Loch.
        //
        // Und sipgate schickt nach der Anmeldung ein `OPTIONS` an unseren
        // Kontakt. Das beantwortet `ua.dart:637` selbst mit 200, aber NUR
        // solange niemand auf `EventNewOptions` hört. `SIPUAHelper` tut das
        // nicht (geprüft: kein `handlers.on(EventNewOptions…)`), wir auch
        // nicht — wer hier je einen solchen Horcher einhängt, muss selbst
        // antworten, sonst hält sipgate die Registrierung für tot.
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

      // Hier, nicht erst beim ersten Anruf: der Systemdialog gehört an eine
      // bewusste Handlung („Anmelden" gedrückt), nicht in die Sekunde, in der
      // es klingelt.
      await bluetoothRechtSichern();
      // Nur nachfragen, nichts öffnen: für das Vollbildrecht gibt es keinen
      // Dialog, nur eine Systemseite — und die schiebt man niemandem
      // unaufgefordert vor die Nase.
      await vollbildPruefen();
      await benachrichtigungPruefen();

      _horcher ??= _SipgateHorcher(this);
      _helper.removeSipUaHelperListener(_horcher!);
      _helper.addSipUaHelperListener(_horcher!);

      _sipId = cfg.sipId;
      _setz(
        stand: SipgateStand.verbindet,
        sipId: cfg.sipId,
        bezeichnung: cfg.bezeichnung,
        absendernummer: cfg.absendernummer?.isEmpty == true ? null : cfg.absendernummer,
        notrufstandort: cfg.notrufstandort,
        geteilt: cfg.geteilt,
        meldung: 'Melde an …',
      );

      await _helper.start(settings);
      _uaGebaut = true;
      _log.info('sipgate: Anmeldung gestartet für ${cfg.sipId}', tag: 'SIPGATE');
      return true;
    } catch (e) {
      _log.error('sipgate: Anmeldung fehlgeschlagen: $e', tag: 'SIPGATE');
      // ⚠️ Auch hier einen Anlauf einplanen. Oben ist der eingeplante Anlauf
      // schon abbestellt worden, also wäre dies sonst die dritte Stelle, an
      // der dieselbe Stille entsteht — diesmal durch eine Ausnahme statt durch
      // eine Ablehnung.
      _fehlversuche++;
      _wiederholungPlanen('Anmeldung fehlgeschlagen: $e');
      return false;
    } finally {
      _startetGerade = false;
    }
  }

  Future<void> stoppen() async {
    // Zuerst, nicht zuletzt: was hier noch eingeplant ist, würde die gerade
    // abgeschaltete Anmeldung wieder hochziehen.
    _gewollt = false;
    _wiederholungAbbrechen();
    _klingelnBeenden();
    _dauerTakt?.cancel();
    _dauerTakt = null;
    _rufA = null;
    _rufB = null;
    _aktiv = 'A';
    _anrufIdA = null;
    _anrufIdB = null;
    try {
      _helper.stop();
    } catch (e) {
      _log.warning('sipgate: Abmelden meldete $e', tag: 'SIPGATE');
    }
    _setz(stand: SipgateStand.aus, meldung: null, gespraech: null, loescheGespraech: true);
  }

  /// ICE-Server aus unserem **eigenen** coturn.
  ///
  /// ⚠️ Der Standardwert von `UaSettings.iceServers` in `sip_ua` ist ein
  /// öffentlicher STUN-Server von Google (nachgesehen: `sip_ua-1.1.0`,
  /// `sip_ua_helper.dart:928`, und gelesen wird das Feld an genau einer Stelle,
  /// Zeile 376). Ohne dieses Überschreiben würde jedes sipgate-Gespräch seine
  /// Kandidaten bei einem Fremden erfragen — also bei jedem Anruf verraten,
  /// wann von welcher Adresse telefoniert wird. Genau das schließt
  /// [VoiceCallService] ausdrücklich aus, und hier gilt es genauso.
  ///
  /// Deshalb wird das Feld **ersetzt**, nicht ergänzt: der Standard ist damit
  /// weg, nicht überstimmt.
  ///
  /// Schlägt der Abruf der eigenen Zugangsdaten fehl, bleibt die Liste
  /// **leer**. sipgate liefert im SDP einen öffentlichen Host-Kandidaten
  /// (nachgemessen: `212.9.44.163` plus IPv6), das Gespräch kommt also meist
  /// auch ohne STUN zustande. Lieber kein STUN als ein fremdes.
  Future<List<Map<String, String>>> _iceServer() async {
    try {
      return iceListeBauen(await ApiService().getTurnCredentials());
    } catch (e) {
      _log.warning('sipgate: keine TURN-Zugangsdaten ($e) — ohne STUN weiter',
          tag: 'SIPGATE');
      return const <Map<String, String>>[];
    }
  }

  /// Baut die ICE-Liste aus der Antwort von `api/auth/turn_credentials.php`.
  ///
  /// ⚠️ DIE FORM IST NICHT KOSMETIK, UND SIE GEHÖRT NICHT HIERHER.
  /// [iceServerEintraege] in `voice_call_service.dart` ist die eine Stelle, an
  /// der sie festliegt — mit `test/ice_server_form_test.dart` darüber. Der Grund
  /// ist eine echte Panne vom 11.08.2026: ein Anruf zeigte auf beiden Seiten
  /// „verbunden" mit laufender Dauer und übertrug **null Byte**, weil die
  /// Desktop-Brücke von flutter_webrtc `urls` in einen EINZELNEN String liest
  /// und bei jedem Listenelement überschreibt. Aus vier URIs überlebte die
  /// letzte — ausgerechnet `turns:`, der Transport, dessen TLS-Handshake
  /// libwebrtc nicht abschließen kann.
  ///
  /// sipgate benutzt dieselbe flutter_webrtc-Brücke, also gilt hier dasselbe
  /// — samt der Obergrenze von acht Servern, die die native Seite ohne
  /// Bereichsprüfung schreibt. Deshalb wird delegiert und nicht nachgebaut: die
  /// gruppierte Form sieht im Review vernünftig aus, und eine zweite Kopie
  /// dieser Regel würde beim nächsten Aufräumen still zurückfallen.
  ///
  /// Bleibt hier nur die Umformung: `UaSettings.iceServers` verlangt
  /// `List<Map<String, String>>`, [iceServerEintraege] liefert `dynamic`.
  static List<Map<String, String>> iceListeBauen(Map<String, dynamic>? creds) {
    if (creds == null) return const <Map<String, String>>[];
    final uris = (creds['uris'] as List?)?.cast<String>() ?? const <String>[];
    if (uris.isEmpty) return const <Map<String, String>>[];
    return iceServerEintraege(
      uris,
      '${creds['username'] ?? ''}',
      '${creds['password'] ?? ''}',
    ).map((e) => e.map((k, v) => MapEntry(k, '$v'))).toList();
  }

  /// Liest die Antwort von `get_config`.
  ///
  /// ⚠️ DIE NUTZLAST LIEGT FLACH, ES GIBT KEIN `data`-OBJEKT.
  /// `jsonResponse()` in `api/config.php` macht
  /// `array_merge(['success' => …], $data)` — die Felder landen also direkt
  /// neben `success`. Genau das habe ich beim ersten Bau angenommen statt
  /// nachgesehen: der Client las `antwort['data']`, bekam `null`, fiel auf den
  /// leeren Zwischenspeicher zurück und meldete „Keine Anmeldedaten", während
  /// der Server die Daten sauber lieferte. Nichts war rot, nichts stand im
  /// Protokoll des Servers — nur der Bildschirm war leer.
  ///
  /// Deshalb steht die Form jetzt unter Test, mit der echten, ungekürzten
  /// Antwort als Vorlage (`test/sipgate_antwort_test.dart`). Dasselbe Muster
  /// wie bei `speedtest_antwort_test.dart`.
  static SipgateKonfig? konfigAusAntwort(Map<String, dynamic> antwort) {
    if (antwort['success'] != true || antwort['eingerichtet'] != true) return null;
    final sipId = '${antwort['sip_id'] ?? ''}';
    final ha1 = '${antwort['ha1'] ?? ''}';
    // Ohne diese zwei ist der Rest wertlos — dann lieber `null` als eine
    // Anmeldung, die mit leeren Feldern in einen 401 läuft.
    if (sipId.isEmpty || ha1.isEmpty) return null;
    final absender = '${antwort['absendernummer'] ?? ''}'.trim();
    return SipgateKonfig(
      sipId: sipId,
      ha1: ha1,
      realm: '${antwort['realm'] ?? 'sipgate.de'}',
      wssUrl: '${antwort['wss_url'] ?? 'wss://sip.sipgate.de'}',
      bezeichnung: antwort['bezeichnung'] as String?,
      geteilt: antwort['geteilt'] == true,
      absendernummer: absender.isEmpty ? null : absender,
      notrufstandort: '${antwort['notrufstandort'] ?? 'unbekannt'}',
    );
  }

  Future<SipgateKonfig?> _konfigHolen() async {
    try {
      final antwort = await ApiService().sipgateAction({
        'action': 'get_config',
        'plattform': _plattformName(),
        if (DeviceKeyService().deviceId != null)
          'device_id': DeviceKeyService().deviceId,
      });
      final cfg = konfigAusAntwort(antwort);
      if (cfg != null) {
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
    return SipgateKonfig(
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
    // Zweites Bein für die Dreierkonferenz. Der Reihe nach, und jeder Schritt
    // hat einen Grund:
    //   * es muss ein erstes Bein geben, und es muss verbunden sein — eine
    //     zweite Nummer zu einem klingelnden Anruf zu wählen ergibt nichts
    //   * das erste wird gehalten (`*3`), sonst hört die erste Person zu,
    //     während man die zweite wählt
    //   * drei Beine kann die Anlage nicht; das wird gesagt, nicht versucht
    if (hatGespraech) {
      if (zustand.value.zweites != null) {
        return 'Es laufen schon zwei Gespräche — mehr kann die Konferenz nicht.';
      }
      if (zustand.value.gespraech!.stand != SipgateGespraechStand.verbunden) {
        return 'Erst muss das laufende Gespräch verbunden sein.';
      }
      return _zweitesWaehlen(nummer, bezeichnung);
    }

    if (!istRegistriert) {
      final ok = await starten();
      if (!ok) return zustand.value.meldung ?? 'Nicht bei sipgate angemeldet.';
      // Nach `start()` steht die Registrierung nicht sofort; kurz warten,
      // sonst antwortet sip_ua mit „Not connected, you will need to register".
      if (!await _wartenAufRegistrierung()) {
        return 'Anmeldung bei sipgate kam nicht zustande.';
      }
    }

    _anrufIdA = await _anrufProtokoll(
      richtung: 'aus',
      nummer: nummer,
      bezeichnung: bezeichnung,
      status: 'gestartet',
    );

    // ⚠️ VOR dem Anruf, nicht danach: der AudioSwitchManager des Plugins
    // startet in `getUserMedia`, das `_helper.call()` intern auslöst, und liest
    // die Konfiguration, die dann gilt. Hinterher umzustellen heißt, dass die
    // ersten Sekunden über das falsche Bluetooth-Profil laufen.
    await _tonWegVorbereiten();

    final ziel = 'sip:$nummer@sipgate.de';
    final ok = await _helper.call(ziel, voiceOnly: true);
    if (!ok) {
      await _anrufProtokoll(
        anrufId: _anrufIdA,
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
    // Auch abgehend: wer eine Nummer aus einer Behördenkarte antippt, sieht
    // dann „Jobcenter Ulm" statt der Ziffern — und merkt, wenn er sich vertippt
    // hat, bevor jemand abnimmt.
    if (bezeichnung == null || bezeichnung.isEmpty) {
      unawaited(_namenNachreichen('A', nummer));
    }
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

  /// Wählt die zweite Nummer dazu, mit dem ersten Bein in der Warteschleife.
  Future<String?> _zweitesWaehlen(String nummer, String? bezeichnung) async {
    // Halten zuerst. Ohne das hört die erste Person mit, während man wählt —
    // bei einem Amt und einem Mitglied im selben Gespräch ist das genau das,
    // was nicht passieren darf.
    await halten(true);

    _anrufIdB = await _anrufProtokoll(
      richtung: 'aus',
      nummer: nummer,
      bezeichnung: bezeichnung,
      status: 'gestartet',
    );

    final ok = await _helper.call('sip:$nummer@sipgate.de', voiceOnly: true);
    if (!ok) {
      await _anrufProtokoll(
          anrufId: _anrufIdB, status: 'fehler', fehler: 'sip_ua: nicht verbunden');
      await halten(false);
      return 'Zweiter Anruf konnte nicht gestartet werden.';
    }
    _aktiv = 'B';
    _setz(
      zweites: SipgateGespraech(
        nummer: nummer,
        name: bezeichnung,
        eingehend: false,
        stand: SipgateGespraechStand.waehlt,
      ),
    );
    return null;
  }

  /// Hält das aktive Bein (`*3`) oder holt es zurück (`#`).
  ///
  /// ⚠️ Das sind Tastenkürzel der sipgate-Anlage, keine SIP-Signale: sie gehen
  /// als DTMF (RFC 2833) durch das laufende Gespräch. Deshalb hängt die
  /// Konferenz daran, dass `dtmfMode` auf RFC 2833 steht — mit dem Standardwert
  /// `INFO` von `sip_ua` würde die Anlage nichts davon hören.
  Future<void> halten(bool an) async {
    final ruf = _aktiverRuf;
    if (ruf == null) return;
    // ⚠️ Über denselben gefangenen Weg wie die Tastentöne: ein `*3` auf eine
    // Sitzung, die gerade endet, würde sonst als Ausnahme durchschlagen.
    if (!_steuercode(ruf, an ? '*3' : '#')) return;
    _setzBein(_aktiv, (g) => g.kopie(gehalten: an));
  }

  /// Wechselt zwischen den beiden Beinen (`*4`).
  Future<void> makeln() async {
    if (zustand.value.zweites == null) return;
    final ruf = _aktiverRuf;
    if (ruf == null) return;
    if (!_steuercode(ruf, '*4')) return;
    _aktiv = _aktiv == 'A' ? 'B' : 'A';
    // Die Anlage tauscht, wer gehalten wird; die Anzeige zieht mit.
    _setzBein('A', (g) => g.kopie(gehalten: _aktiv != 'A'));
    _setzBein('B', (g) => g.kopie(gehalten: _aktiv != 'B'));
    _log.info('sipgate: gemakelt, aktiv ist jetzt Bein $_aktiv', tag: 'SIPGATE');
  }

  /// Schaltet beide Beine und uns zur Dreierkonferenz zusammen (`*5`).
  ///
  /// ⚠️ Gemischt wird bei **sipgate**, nicht hier. Zwei entfernte Tonspuren
  /// ineinander zu mischen kann `flutter_webrtc` nicht — jede Seite würde nur
  /// uns hören, nicht die andere. Im Tarif business L ist die Dreierkonferenz
  /// enthalten (Preisliste Stand Mai 2026: `3er-Konferenz — ja`).
  ///
  /// ⚠️ NICHT AUF DEM GERÄT ERPROBT. Nachgewiesen ist, dass zwei gleichzeitige
  /// Gespräche erlaubt sind und dass DTMF ankommt. Ob `*5` zwei Beine
  /// zusammenschaltet, die als getrennte SIP-Dialoge von unserem Softphone
  /// kommen, steht in keiner Dokumentation, die ich gefunden habe — es braucht
  /// zwei abgehobene Anrufe, also zwei Telefone und zwei Menschen. Deshalb
  /// meldet die Oberfläche danach nicht „Konferenz läuft", sondern
  /// „zusammengeschaltet — bitte prüfen, ob sich alle hören".
  Future<String?> konferenzSchalten() async {
    if (zustand.value.konferenz) return 'Die Konferenz läuft schon.';
    if (zustand.value.verbundeneBeine < 2) {
      return 'Für eine Konferenz müssen beide Gespräche verbunden sein.';
    }
    final ruf = _rufA ?? _rufB;
    if (ruf == null) return 'Kein Gespräch.';
    if (!_steuercode(ruf, '*5')) {
      return 'Der Code ging nicht durch — steht das Gespräch noch?';
    }
    _setz(konferenz: true);
    _setzBein('A', (g) => g.kopie(gehalten: false));
    _setzBein('B', (g) => g.kopie(gehalten: false));
    _log.info('sipgate: *5 geschickt — Konferenz angefordert', tag: 'SIPGATE');
    return null;
  }

  /// Schickt einen Steuercode der sipgate-Anlage (`*3`, `*4`, `*5`, `#`) und
  /// meldet, ob er hinausging.
  bool _steuercode(Call ruf, String code) {
    try {
      ruf.sendDTMF(code);
      return true;
    } catch (e) {
      _log.warning('sipgate: Steuercode „$code" nicht gesendet: $e', tag: 'SIPGATE');
      return false;
    }
  }

  /// Der Ruf, an den Tastentöne und Steuercodes gehen.
  Call? get _aktiverRuf => _aktiv == 'B' ? (_rufB ?? _rufA) : (_rufA ?? _rufB);

  /// Ändert ein Bein im Zustand, ohne das andere anzufassen.
  void _setzBein(String seite, SipgateGespraech Function(SipgateGespraech) wandeln) {
    final z = zustand.value;
    final g = seite == 'A' ? z.gespraech : z.zweites;
    if (g == null) return;
    if (seite == 'A') {
      _setz(gespraech: wandeln(g));
    } else {
      _setz(zweites: wandeln(g));
    }
  }

  /// Nimmt einen eingehenden Anruf an.
  ///
  /// ⚠️ Erst die Audio-Sitzung, dann `answer()`. `answer()` holt sich intern
  /// die Medien; wer die Sitzung danach umstellt, telefoniert die ersten
  /// Sekunden über das Musikprofil des Kopfhörers — also ohne Mikrofon.
  Future<void> annehmen() async {
    _klingelnBeenden();
    final ruf = _klingelnderRuf ?? _aktiverRuf;
    if (ruf == null) return;
    await _tonWegVorbereiten();
    ruf.answer(_helper.buildCallOptions(true));
  }

  void ablehnen() {
    _klingelnBeenden();
    final ruf = _klingelnderRuf ?? _aktiverRuf;
    if (ruf == null) return;
    // 603 Decline, nicht 486 Busy: „abgelehnt" ist die Wahrheit, „belegt" wäre
    // eine Ausrede und schickt den Anrufer bei sipgate in die Mailbox-Logik
    // für Besetztfälle.
    ruf.hangup({'status_code': 603});
  }

  /// Legt auf. Ohne Angabe das aktive Bein; mit `zweites: true` gezielt das
  /// hinzugewählte — sonst könnte man das falsche verlieren, sobald zwei laufen.
  void auflegen({bool? zweites}) {
    final ruf = switch (zweites) {
      true => _rufB,
      false => _rufA,
      null => _aktiverRuf,
    };
    ruf?.hangup();
  }

  /// Das Bein, das gerade klingelt — bei zwei Gesprächen kann das das zweite
  /// sein, und dann wäre „nimm das aktive an" falsch.
  Call? get _klingelnderRuf {
    final z = zustand.value;
    if (z.gespraech?.stand == SipgateGespraechStand.klingelt) return _rufA;
    if (z.zweites?.stand == SipgateGespraechStand.klingelt) return _rufB;
    return null;
  }

  void stummSchalten(bool stumm) {
    final ruf = _aktiverRuf;
    if (ruf == null) return;
    if (stumm) {
      ruf.mute(true, false);
    } else {
      ruf.unmute(true, false);
    }
    _setzBein(_aktiv, (g) => g.kopie(stumm: stumm));
  }

  /// Zeichen, die `sip_ua` als Tastenton durchlässt.
  ///
  /// ⚠️ Nachgelesen in `sip_ua-1.1.0/lib/src/rtc_session/dtmf.dart`, nicht
  /// geraten: alles andere lässt `sendDTMF` mit `TypeError` auffliegen. Das
  /// „+" von der langen Null gehört ausdrücklich NICHT dazu — es ist ein
  /// Wählzeichen, kein Ton.
  static final RegExp _tastentoene = RegExp(r'^[0-9A-DR#*]$');

  /// Ist das ein Zeichen, das als Tastenton gehen kann?
  static bool istTastenton(String zeichen) =>
      _tastentoene.hasMatch(zeichen.toUpperCase());

  /// Schickt einen Tastenton ins laufende Gespräch.
  ///
  /// Gibt den Grund zurück, wenn es nicht ging — `null` heißt: abgeschickt.
  ///
  /// ⚠️ `sendDTMF` wirft, wenn die Sitzung nicht `confirmed` ist. Das ist keine
  /// Randlage: zwischen dem Auflegen der Gegenseite und dem Nachziehen der
  /// Anzeige liegen Millisekunden, in denen eine Taste noch gedrückt werden
  /// kann. Ungefangen wäre das im Debug ein roter Bildschirm und im Release
  /// eine Taste, die einfach nichts tut.
  String? dtmf(String ton) {
    final ruf = _aktiverRuf;
    if (ruf == null) return 'Kein Gespräch, in das ein Ton gehen könnte.';
    if (!istTastenton(ton)) return '„$ton" ist kein Tastenton.';
    try {
      ruf.sendDTMF(ton.toUpperCase());
    } catch (e) {
      _log.warning('sipgate: Tastenton „$ton" nicht gesendet: $e', tag: 'SIPGATE');
      return 'Der Ton ging nicht durch — das Gespräch steht gerade nicht.';
    }
    return null;
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
    String? absendernummer,
    String? notrufstandort,
    String? bluetoothRecht,
    bool? vollbildErlaubt,
    bool? benachrichtigungenErlaubt,
    bool? geteilt,
    String? meldung,
    DateTime? naechsterVersuch,
    SipgateGespraech? gespraech,
    bool loescheGespraech = false,
    SipgateGespraech? zweites,
    bool loescheZweites = false,
    bool? konferenz,
  }) {
    final alt = zustand.value;
    zustand.value = SipgateZustand(
      stand: stand ?? alt.stand,
      sipId: sipId ?? alt.sipId,
      bezeichnung: bezeichnung ?? alt.bezeichnung,
      absendernummer: absendernummer ?? alt.absendernummer,
      notrufstandort: notrufstandort ?? alt.notrufstandort,
      bluetoothRecht: bluetoothRecht ?? alt.bluetoothRecht,
      vollbildErlaubt: vollbildErlaubt ?? alt.vollbildErlaubt,
      benachrichtigungenErlaubt:
          benachrichtigungenErlaubt ?? alt.benachrichtigungenErlaubt,
      geteilt: geteilt ?? alt.geteilt,
      meldung: meldung,
      // Wie `meldung`: NICHT `?? alt`. Ein Zustandswechsel ohne Zeitpunkt
      // bedeutet, dass gerade keiner geplant ist — ein durchgereichter alter
      // Wert würde in der Kopfleiste ewig „nächster Versuch" behaupten.
      naechsterVersuch: naechsterVersuch,
      gespraech: loescheGespraech ? null : (gespraech ?? alt.gespraech),
      zweites: loescheZweites ? null : (zweites ?? alt.zweites),
      konferenz:
          konferenz ?? (loescheGespraech || loescheZweites ? false : alt.konferenz),
    );
  }

  void _setzGespraech(SipgateGespraech? g) {
    _setz(gespraech: g, loescheGespraech: g == null);
  }

  void _registrierung(RegistrationState state) {
    switch (state.state) {
      case RegistrationStateEnum.REGISTERED:
        _log.info('sipgate: registriert ($_sipId)', tag: 'SIPGATE');
        _fehlversuche = 0;
        _datenErneuert = false;
        _anlaufHoltDaten = false;
        _wiederholungAbbrechen();
        _setz(stand: SipgateStand.registriert, meldung: null);
        break;
      case RegistrationStateEnum.REGISTRATION_FAILED:
        _anmeldungAbgelehnt(state);
        break;
      case RegistrationStateEnum.UNREGISTERED:
      case RegistrationStateEnum.NONE:
      case null:
        // ⚠️ Nicht auf `aus` fallen, solange ein Anlauf geplant ist —
        // die Begründung steht bei [sipgateAbmeldungUebernehmen].
        if (sipgateAbmeldungUebernehmen(
          anlaufGeplant: _erneutTakt != null,
          aktuell: zustand.value.stand,
        )) {
          _setz(stand: SipgateStand.aus, meldung: 'Abgemeldet.');
        }
        break;
    }
  }

  /// Ein REGISTER wurde abgelehnt: einordnen, ansagen, neu einplanen.
  void _anmeldungAbgelehnt(RegistrationState state) {
    final code = state.cause?.status_code;
    final grund = state.cause?.cause ?? code?.toString() ?? '';
    final klartext =
        grund.isEmpty ? 'sipgate hat die Anmeldung abgelehnt.' : 'sipgate hat die Anmeldung abgelehnt: $grund';
    _log.error('sipgate: Anmeldung abgelehnt ($grund, Code $code)', tag: 'SIPGATE');

    if (!_gewollt) {
      // Abgemeldet worden, während noch ein REGISTER unterwegs war. Weder
      // wiederholen noch rot färben: der Nutzer hat die Telefonie gerade
      // ausgeschaltet, und ein Fehlersymbol dafür wäre schlicht falsch.
      _log.info('sipgate: späte Ablehnung nach dem Abmelden — ignoriert', tag: 'SIPGATE');
      return;
    }

    _fehlversuche++;
    final folge = sipgateAnmeldeFolge(code, datenSchonErneuert: _datenErneuert);

    switch (folge) {
      case SipgateAnmeldeFolge.aufgeben:
        _wiederholungAbbrechen();
        _setz(
          stand: SipgateStand.fehler,
          meldung: '$klartext\n'
              'Auch mit frisch geholten Zugangsdaten abgelehnt — bitte das '
              'VoIP-Telefon im Bildschirm prüfen.',
        );
        break;

      case SipgateAnmeldeFolge.datenErneuern:
        _datenErneuert = true;
        _anlaufHoltDaten = true;
        _wiederholungPlanen(
          klartext,
          zusatz: 'Zugangsdaten werden neu geholt',
        );
        break;

      case SipgateAnmeldeFolge.wiederholen:
        _wiederholungPlanen(klartext);
        break;
    }
  }

  /// Plant den nächsten Anlauf und sagt im Zustand, wann er kommt.
  ///
  /// Die Wartezeit steht **in der Meldung**, nicht nur im Protokoll: sonst
  /// bliebe in der Oberfläche dasselbe „nicht angemeldet" stehen wie vorher,
  /// und niemand könnte unterscheiden, ob es gleich wieder versucht wird oder
  /// ob endgültig Schluss ist.
  void _wiederholungPlanen(String klartext, {String? zusatz}) {
    final warten = sipgateWartezeit(_fehlversuche, _zufall.nextDouble());
    _erneutTakt?.cancel();
    _naechsterVersuch = DateTime.now().add(warten);
    _log.warning(
      'sipgate: Anmeldung fehlgeschlagen ($_fehlversuche. Anlauf) — '
      'neuer Versuch in ${warten.inSeconds} s',
      tag: 'SIPGATE',
    );
    _erneutTakt = Timer(warten, _wiederholungAusfuehren);
    final wann = warten.inSeconds < 90
        ? '${warten.inSeconds} Sekunden'
        : '${(warten.inSeconds / 60).round()} Minuten';
    _setz(
      stand: SipgateStand.fehler,
      naechsterVersuch: _naechsterVersuch,
      meldung: '$klartext\n'
          '${zusatz == null ? '' : '$zusatz — '}'
          'neuer Versuch in $wann ($_fehlversuche. Anlauf).',
    );
  }

  void _wiederholungAbbrechen() {
    _erneutTakt?.cancel();
    _erneutTakt = null;
    _naechsterVersuch = null;
  }

  Future<void> _wiederholungAusfuehren() async {
    _erneutTakt = null;
    _naechsterVersuch = null;
    if (!_gewollt || !plattformFaehig) return;
    if (istRegistriert) return; // dazwischen doch noch durchgekommen

    if (_anlaufHoltDaten || !_uaGebaut) {
      _anlaufHoltDaten = false;
      // Den ganzen Weg noch einmal: HA1 und SIP-ID stecken in den
      // `UaSettings`, die nur `starten()` baut — und gibt es noch gar keinen
      // UA, ist `starten()` ohnehin der einzige Weg dorthin.
      _log.info('sipgate: melde vollständig neu an (Daten holen: $_anlaufHoltDaten, '
          'UA vorhanden: $_uaGebaut)', tag: 'SIPGATE');
      await starten(istWiederholung: true);
      return;
    }
    // Sonst reicht ein neues REGISTER auf der stehenden Verbindung — das ist
    // billiger als ein kompletter Neuaufbau und fasst die Berechtigungsdialoge
    // aus `starten()` nicht an.
    _setz(stand: SipgateStand.verbindet, meldung: 'Melde erneut an …');
    try {
      _helper.register();
    } catch (e) {
      _log.warning('sipgate: erneutes REGISTER meldete $e', tag: 'SIPGATE');
      // Kein stiller Halt: als Fehlschlag zählen und den nächsten Anlauf
      // planen, sonst endet die Kette hier.
      _fehlversuche++;
      _wiederholungPlanen('Erneute Anmeldung nicht möglich: $e');
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

  /// Ordnet einen Ruf einem der beiden Beine zu.
  ///
  /// Nach der Id, nicht nach der Reihenfolge der Ereignisse: `sip_ua` meldet
  /// beide Beine über denselben Rückruf, und wer sie an der Reihenfolge
  /// festmacht, vertauscht sie beim ersten Mal, wo B schneller antwortet als A.
  String _seiteFuer(Call call) {
    if (_rufA == null || _rufA!.id == call.id) {
      _rufA = call;
      return 'A';
    }
    if (_rufB == null || _rufB!.id == call.id) {
      _rufB = call;
      return 'B';
    }
    // Ein drittes Bein kann es nicht geben; dann lieber A als gar nichts.
    return 'A';
  }

  SipgateGespraech? _bein(String seite) =>
      seite == 'A' ? zustand.value.gespraech : zustand.value.zweites;

  void _setzeBein(String seite, SipgateGespraech? g) {
    if (seite == 'A') {
      _setz(gespraech: g, loescheGespraech: g == null);
    } else {
      _setz(zweites: g, loescheZweites: g == null);
    }
  }

  int? _protokollId(String seite) => seite == 'A' ? _anrufIdA : _anrufIdB;

  void _gespraech(Call call, CallState state) {
    final seite = _seiteFuer(call);

    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
        if (call.direction == Direction.incoming) {
          final roh = call.remote_identity;
          final nummer = anruferAnonym(roh) ? 'anonym' : (roh ?? 'anonym');
          // ⚠️ OHNE DAS SIEHT UND HÖRT MAN EINEN ANRUF NICHT.
          // Die schwebende Karte hilft nur, wenn die App im Vordergrund ist —
          // liegt das Tablet mit dunklem Bildschirm auf dem Tisch, gab es
          // vorher weder Ton noch Benachrichtigung, und der Anruf lief ins
          // Leere, ohne dass irgendwo etwas stand.
          _klingelnStarten(anruferAnzeige(roh));
          // Nicht abgewartet: es soll sofort klingeln, der Name kommt nach.
          unawaited(_eingehendAufnehmen(seite, nummer, call.remote_display_name));
          _setzeBein(
            seite,
            SipgateGespraech(
              nummer: nummer,
              name: istEchterName(call.remote_display_name, nummer)
                  ? call.remote_display_name
                  : null,
              eingehend: true,
              stand: SipgateGespraechStand.klingelt,
            ),
          );
        }
        break;

      case CallStateEnum.PROGRESS:
        _anrufProtokoll(anrufId: _protokollId(seite), status: 'klingelt');
        break;

      case CallStateEnum.CONFIRMED:
      case CallStateEnum.ACCEPTED:
        _klingelnBeenden();
        _tonWegWaehlen();
        // ⚠️ Fehlt der Zustand hier, wird er AUS DEM RUF gebaut statt
        // übersprungen. Sonst wäre der schlimmste Fall möglich: das Gespräch
        // läuft, der Angerufene redet — und der Bildschirm ist leer, ohne
        // Dauer und ohne Auflegen-Knopf. Erreichbar wird das, wenn `CONFIRMED`
        // schneller da ist als die Zeile nach `_helper.call()` (ein
        // Anrufbeantworter nimmt sofort ab) oder wenn ein eingehender Ruf ohne
        // vorheriges `CALL_INITIATION` durchkommt.
        final g = _bein(seite) ??
            SipgateGespraech(
              nummer: call.remote_identity ?? 'unbekannt',
              name: call.remote_display_name,
              eingehend: call.direction == Direction.incoming,
              stand: SipgateGespraechStand.waehlt,
            );
        if (g.stand != SipgateGespraechStand.verbunden) {
          _setzeBein(
            seite,
            g.kopie(
              stand: SipgateGespraechStand.verbunden,
              verbundenSeit: DateTime.now(),
            ),
          );
          _dauerTaktStarten();
          _anrufProtokoll(anrufId: _protokollId(seite), status: 'verbunden');
        }
        break;

      case CallStateEnum.FAILED:
      case CallStateEnum.ENDED:
        _klingelnBeenden();
        final beendet = _bein(seite);
        final dauer = beendet?.dauerSekunden ?? 0;
        final warEingehendUnbeantwortet = beendet != null &&
            beendet.eingehend &&
            beendet.stand != SipgateGespraechStand.verbunden;

        String status;
        String? fehlertext;
        if (state.state == CallStateEnum.FAILED) {
          // Code UND Klartext, nicht nur das Wort. `state.cause` trägt
          // status_code und reason_phrase; die habe ich beim ersten Bau
          // weggeworfen und danach eine Runde gebraucht, um sie von Hand
          // nachzumessen.
          final aus = sipAusgang(
            state.cause?.status_code,
            state.cause?.reason_phrase ?? state.cause?.cause,
          );
          status = aus.status;
          fehlertext = aus.text;
        } else {
          status = warEingehendUnbeantwortet ? 'verpasst' : 'beendet';
        }

        _anrufProtokoll(
          anrufId: _protokollId(seite),
          status: status,
          dauerS: dauer,
          fehler: fehlertext,
        );

        final wen = beendet == null ? '' : ' (${beendet.anzeige})';
        if (fehlertext != null) {
          _log.info('sipgate: Bein $seite endete — $fehlertext', tag: 'SIPGATE');
          _letzteAbsage = '$fehlertext$wen';
        } else if (dauer > 0) {
          // Wie lange gesprochen wurde, sofort und in Worten. Das ist die
          // Auskunft, die man nach dem Auflegen tatsächlich will.
          _letzteAbsage = 'Gespräch beendet — ${dauerLesbar(dauer)}$wen';
        } else {
          _letzteAbsage = null;
        }

        // Nur DIESES Bein abräumen. Legt in einer Konferenz einer der beiden
        // auf, läuft das andere Gespräch weiter — es zu beenden, weil ein
        // Ereignis für das andere Bein kam, wäre der schlimmste Fehler hier.
        if (seite == 'A') {
          _rufA = null;
          _anrufIdA = null;
        } else {
          _rufB = null;
          _anrufIdB = null;
        }
        _setzeBein(seite, null);

        // Bleibt genau ein Bein übrig, ist es das aktive und keine Konferenz
        // mehr. Bleibt keines, hört die Uhr auf.
        final restA = zustand.value.gespraech;
        final restB = zustand.value.zweites;
        if (restA == null && restB == null) {
          _dauerTakt?.cancel();
          _dauerTakt = null;
          _aktiv = 'A';
        } else {
          _aktiv = restA != null ? 'A' : 'B';
          if (zustand.value.konferenz) _setz(konferenz: false);
          // Wer allein übrig bleibt, wird nicht gehalten — sonst stünde die
          // Anzeige auf „in der Warteschleife", während man miteinander redet.
          _setzBein(_aktiv, (g) => g.kopie(gehalten: false));
        }
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

  /// Lässt die Dauer im Bildschirm weiterlaufen — für BEIDE Beine.
  void _dauerTaktStarten() {
    if (_dauerTakt != null) return;
    _dauerTakt = Timer.periodic(const Duration(seconds: 1), (_) {
      final z = zustand.value;
      if (z.gespraech == null && z.zweites == null) return;
      // Nur anstoßen; die Dauer rechnet [SipgateGespraech.dauerSekunden] selbst.
      _setz(
        gespraech: z.gespraech?.kopie(),
        zweites: z.zweites?.kopie(),
      );
    });
  }

  /// Fragt beim Plugin nach, ob der Vollbild-Anrufbildschirm erlaubt ist.
  ///
  /// ⚠️ DEKLARIERT IST NICHT ERTEILT — dieselbe Falle wie bei
  /// BLUETOOTH_CONNECT. `USE_FULL_SCREEN_INTENT` steht seit der Fernwahl im
  /// Manifest, aber seit Android 14 bekommt sie automatisch nur, wer als
  /// Telefonie- oder Weckerapp gilt, und der Play Store zieht sie anderen ab.
  /// Das Tablet hat Play Services, also ist das hier kein theoretischer Fall.
  ///
  /// Ohne die Berechtigung klingelt es und eine Benachrichtigung erscheint —
  /// aber kein Anrufbildschirm. Bei einem Tablet, das mit dunklem Display auf
  /// dem Tisch liegt, ist das der Unterschied zwischen „Anruf gesehen" und
  /// „Anruf verpasst".
  ///
  /// Der Wert kommt aus `faehigkeiten()` des `icd_anruf`-Plugins, das
  /// `NotificationManager.canUseFullScreenIntent()` fragt — also die echte
  /// Auskunft des Systems, nicht das Manifest.
  Future<bool?> vollbildPruefen() async {
    if (!PlatformService.isAndroid) return null;
    try {
      final f = await icdAnrufChannel
          .invokeMapMethod<String, dynamic>('faehigkeiten');
      final erlaubt = f?['vollbild'] == true;
      _setz(vollbildErlaubt: erlaubt);
      if (!erlaubt) {
        _log.warning(
          'sipgate: Vollbild-Anrufbildschirm NICHT erlaubt — ein eingehender '
          'Anruf zeigt nur eine Benachrichtigung, keinen Anrufbildschirm',
          tag: 'SIPGATE',
        );
      }
      return erlaubt;
    } on MissingPluginException {
      return null; // ältere Installation ohne den Kanal
    } catch (e) {
      _log.warning('sipgate: Vollbildrecht nicht abfragbar ($e)', tag: 'SIPGATE');
      return null;
    }
  }

  /// Holt die Benachrichtigungsfreigabe und merkt sich das Ergebnis.
  ///
  /// ⚠️ `POST_NOTIFICATIONS` ist seit Android 13 eine Laufzeitberechtigung und
  /// wurde in diesem Projekt nie abgefragt — die App hat `targetSdk = 34`, also
  /// zeigt Android den Dialog auch nicht mehr von selbst. Ohne die Freigabe
  /// erscheint bei einem Anruf gar nichts, geräuschlos: eine verworfene
  /// Benachrichtigung wirft nicht. Es klingelt dann, aber wer anruft steht
  /// nirgends — und genau das war die Beschwerde.
  Future<bool?> benachrichtigungPruefen() async {
    if (!PlatformService.isAndroid) return null;
    final n = NotificationService();
    var erlaubt = await n.androidErlaubt();
    if (erlaubt == false) {
      // Einmal fragen ist erlaubt und der ganze Sinn; wer ablehnt, sieht danach
      // den Hinweis im Bildschirm und entscheidet selbst.
      await n.requestAndroidPermission();
      erlaubt = await n.androidErlaubt();
    }
    _setz(benachrichtigungenErlaubt: erlaubt);
    if (erlaubt == false) {
      _log.warning(
        'sipgate: Benachrichtigungen sind gesperrt — ein eingehender Anruf '
        'klingelt, zeigt aber nicht, wer anruft',
        tag: 'SIPGATE',
      );
    }
    return erlaubt;
  }

  /// Öffnet die Systemseite, auf der der Vollbild-Anrufbildschirm erlaubt wird.
  Future<void> vollbildEinstellungOeffnen() async {
    if (!PlatformService.isAndroid) return;
    try {
      await icdAnrufChannel.invokeMethod<bool>('vollbildEinstellungOeffnen');
    } catch (e) {
      _log.warning('sipgate: Vollbild-Einstellung nicht öffenbar ($e)', tag: 'SIPGATE');
    }
  }

  /// Holt BLUETOOTH_CONNECT, damit das Headset überhaupt gefunden wird.
  ///
  /// ⚠️ DAS IST DER WAHRSCHEINLICHSTE GRUND FÜR „ICH HÖRE NICHTS IM KOPFHÖRER".
  /// Ab Android 12 ist `BLUETOOTH_CONNECT` eine Laufzeitberechtigung. Ohne sie
  /// wirft der Headset-Dienst bei `getConnectedDevices()` eine
  /// `SecurityException`, `audioswitch` findet das gekoppelte Headset nicht —
  /// und `enableSpeakerButPreferBluetooth()` nimmt folgerichtig den
  /// Lautsprecher. Kein Fehler, keine Meldung, nur der falsche Lautsprecher.
  ///
  /// Die Berechtigung stand seit der Fernwahl im Manifest, wurde aber **nie
  /// abgefragt**: deklariert ist nicht erteilt. Der Dialog erscheint hier, beim
  /// Einschalten und vor dem ersten Gespräch — ist sie schon da, antwortet das
  /// Plugin sofort `erteilt` und es erscheint nichts.
  Future<String> bluetoothRechtSichern() async {
    if (!PlatformService.isAndroid) return 'nicht_noetig';
    try {
      final stand = await icdAnrufChannel
              .invokeMethod<String>('bluetoothRechtAnfragen') ??
          'unbekannt';
      _setz(bluetoothRecht: stand);
      if (stand != 'erteilt' && stand != 'nicht_noetig') {
        _log.warning(
          'sipgate: BLUETOOTH_CONNECT ist „$stand" — das Headset wird '
          'voraussichtlich NICHT gefunden, der Ton geht in den Lautsprecher',
          tag: 'SIPGATE',
        );
      }
      return stand;
    } on MissingPluginException {
      // Ältere Installation ohne die neue Kanalmethode. Kein Grund, das
      // Telefonieren zu verweigern — nur die Gewissheit über den Tonweg fehlt.
      _setz(bluetoothRecht: 'unbekannt');
      return 'unbekannt';
    } catch (e) {
      _log.warning('sipgate: BLUETOOTH_CONNECT nicht abfragbar ($e)', tag: 'SIPGATE');
      _setz(bluetoothRecht: 'unbekannt');
      return 'unbekannt';
    }
  }

  bool _klingelt = false;

  /// Schlägt nach, wer die Nummer gehört — im eigenen Verzeichnis.
  ///
  /// Praxen, Kliniken, Apotheken, Ämter, Gerichte, Kassen und Mitglieder stehen
  /// längst in der Datenbank; sie lagen nur in fünfzig Tabellen und in jeder
  /// denkbaren Schreibweise. Der Server hält dafür ein Rückwärtsverzeichnis mit
  /// `sha256(E.164)` als Schlüssel — ein Indexzugriff, nachgemessen 0,1 ms.
  ///
  /// ⚠️ WIRD NICHT ABGEWARTET, BEVOR ES KLINGELT. Ein Anruf darf nicht auf eine
  /// Netzabfrage warten; bei schlechter Verbindung klingelte es sonst später
  /// als beim Anrufer der Rufton aufhört. Also erst klingeln mit der Nummer,
  /// dann den Namen nachreichen.
  ///
  /// ⚠️ MEHRDEUTIGKEIT WIRD ANGEZEIGT, NICHT AUFGELÖST. Zwei Mitglieder teilen
  /// sich eine Mobilnummer, und eine Gerichtszentrale gehört zu fünf Kammern —
  /// beides nachgemessen im echten Bestand. Einen davon auszuwählen hiesse
  /// raten, und bei einem Anruf über Gesundheitsdaten ist ein falscher Name mit
  /// Zuversicht schlimmer als gar keiner. Deshalb „… (+4 weitere)".
  Future<String?> _anruferNachschlagen(String nummer) async {
    try {
      final a = await ApiService().sipgateAction(
          {'action': 'anrufer', 'nummer': nummer});
      if (a['success'] != true || a['gefunden'] != true) return null;
      final anzeige = a['anzeige'] as String?;
      return anzeige == null || anzeige.isEmpty ? null : anzeige;
    } catch (e) {
      // Ein unbekannter Anrufer ist kein Fehler — die Nummer steht ja da.
      _log.warning('sipgate: Anrufer nicht nachschlagbar ($e)', tag: 'SIPGATE');
      return null;
    }
  }

  /// Nimmt einen eingehenden Anruf in den Verlauf auf und trägt den Namen nach.
  ///
  /// ⚠️ WARUM DAS EINE METHODE IST UND NICHT ZWEI NEBENEINANDER
  /// Vorher lief das Nachschlagen los, BEVOR die Verlaufszeile angelegt war —
  /// und die Zeilennummer kam erst mit deren Antwort zurück. Wenn der Name
  /// eintraf, war sie meistens noch `null`, `_anrufProtokoll` fiel in seine
  /// Wächterzeile und tat nichts. Der Bildschirm zeigte den Namen, der Verlauf
  /// behielt für immer die nackte Nummer. Nichts wurde rot dabei.
  ///
  /// Jetzt laufen beide Netzwege **gleichzeitig** los und werden beide
  /// abgewartet — kein Zeitverlust, keine Reihenfolge zum Verwechseln.
  Future<void> _eingehendAufnehmen(String seite, String nummer, String? rohName) async {
    final zeile = _anrufProtokoll(
      richtung: 'ein',
      nummer: nummer,
      bezeichnung: istEchterName(rohName, nummer) ? rohName : null,
      status: 'klingelt',
    );
    final suche = _anruferNachschlagen(nummer);

    final id = await zeile;
    if (seite == 'A') {
      _anrufIdA = id;
    } else {
      _anrufIdB = id;
    }
    await _namenNachreichen(seite, nummer, name: await suche);
  }

  /// Trägt den gefundenen Namen nach: in den Zustand, den Verlauf und die
  /// Benachrichtigung, die vorher nur die Nummer trug.
  Future<void> _namenNachreichen(String seite, String nummer, {String? name}) async {
    name ??= await _anruferNachschlagen(nummer);
    if (name == null) return;
    final g = _bein(seite);
    // Nur, wenn das Gespräch noch läuft — sonst schriebe man einen Namen in
    // einen Zustand, den gerade jemand aufgelegt hat.
    if (g == null || g.nummer != nummer) return;
    _setzeBein(
      seite,
      SipgateGespraech(
        nummer: g.nummer,
        name: name,
        eingehend: g.eingehend,
        stand: g.stand,
        verbundenSeit: g.verbundenSeit,
        stumm: g.stumm,
        gehalten: g.gehalten,
      ),
    );
    _anrufProtokoll(anrufId: _protokollId(seite), status: g.stand == SipgateGespraechStand.klingelt ? 'klingelt' : 'verbunden', bezeichnung: name);
    if (_klingelt && g.stand == SipgateGespraechStand.klingelt) {
      // Die Benachrichtigung trug bisher nur die Nummer. Neu setzen mit
      // derselben Kennung ersetzt sie, statt eine zweite danebenzustellen.
      unawaited(NotificationService().showIncomingCall(
        callerName: name,
        vollbild: zustand.value.vollbildErlaubt == true,
        mitKnoepfen: true,
      ));
    }
  }

  /// Klingeln und Benachrichtigung mit dem Anrufer.
  ///
  /// Beides, und aus zwei verschiedenen Gründen: der Ton, damit man den Anruf
  /// überhaupt merkt, und die Benachrichtigung, damit man SIEHT wer es ist —
  /// ein Klingeln allein sagt nur, dass jemand anruft, nicht wer.
  ///
  /// Systemklingelton, kein mitgeliefertes Tonstück: derselbe Weg wie bei den
  /// WebRTC-Gesprächen ([VoiceCallService]), also derselbe Ton, den der
  /// Vorsitzer schon als „das Tablet klingelt" kennt.
  void _klingelnStarten(String anrufer) {
    if (_klingelt) return;
    _klingelt = true;
    try {
      FlutterRingtonePlayer().playRingtone(looping: true, asAlarm: false);
    } catch (e) {
      _log.warning('sipgate: Klingelton nicht abspielbar ($e)', tag: 'SIPGATE');
    }
    // Wirft nie in den Gesprächsablauf zurück: eine fehlende Benachrichtigung
    // darf keinen Anruf verhindern.
    NotificationService()
        .showIncomingCall(
          callerName: anrufer,
          // Nur wenn erlaubt. Ein `fullScreenIntent` ohne Berechtigung wird von
          // Android verworfen — samt der Benachrichtigung, in manchen
          // Fassungen. Dann wäre die Vorsicht schlimmer als der Verzicht.
          vollbild: zustand.value.vollbildErlaubt == true,
          // Zwei Knöpfe direkt in der Benachrichtigung: annehmen, ohne erst
          // die App zu suchen. Genau das fehlte.
          mitKnoepfen: true,
        )
        .catchError((Object e) =>
            _log.warning('sipgate: Anruf-Benachrichtigung fehlgeschlagen ($e)',
                tag: 'SIPGATE'));
    _log.info('sipgate: eingehender Anruf von $anrufer', tag: 'SIPGATE');
  }

  void _klingelnBeenden() {
    if (!_klingelt) return;
    _klingelt = false;
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {/* nichts zu retten, und kein Grund, hier zu werfen */}
  }

  /// Stellt die Audio-Sitzung auf **Gespräch** um, BEVOR Medien anfangen.
  ///
  /// ⚠️ DAS IST DER SCHRITT, DER ÜBER DAS BLUETOOTH-HEADSET ENTSCHEIDET, UND
  /// ER MUSS VORHER PASSIEREN.
  /// Ein Bluetooth-Kopfhörer hat zwei getrennte Profile: A2DP spielt Musik in
  /// hoher Qualität und hat **kein Mikrofon**, SCO/HFP ist der Sprachkanal mit
  /// Mikrofon. Welches Android benutzt, hängt am Audio-Modus. Steht der auf
  /// `normal` (die Vorgabe für Wiedergabe), bekommt man A2DP — der Vorsitzer
  /// hört das Gespräch im Kopfhörer und spricht ins Tablet, oder umgekehrt.
  /// Erst `MODE_IN_COMMUNICATION` mit `STREAM_VOICE_CALL` und
  /// `USAGE_VOICE_COMMUNICATION` öffnet SCO. Genau das ist
  /// [AndroidAudioConfiguration.communication].
  ///
  /// Und es muss VOR `getUserMedia` gesetzt sein: der `AudioSwitchManager` des
  /// Plugins startet dort (`GetUserMediaImpl:383`) und liest die Konfiguration,
  /// die zu diesem Zeitpunkt gilt.
  Future<void> _tonWegVorbereiten() async {
    if (!PlatformService.isAndroid) return;
    // Zuerst die Berechtigung: ohne sie ist die schönste Audio-Konfiguration
    // wirkungslos, weil das Headset gar nicht in der Geräteliste auftaucht.
    await bluetoothRechtSichern();
    try {
      await Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.communication);
      _log.info('sipgate: Audio-Sitzung auf Gespräch gestellt (SCO möglich)', tag: 'SIPGATE');
    } catch (e) {
      _log.warning('sipgate: Audio-Sitzung nicht umgestellt ($e)', tag: 'SIPGATE');
    }
  }

  /// Schickt die Sprache dorthin, wo das Headset hängt.
  ///
  /// Nachgesehen in `flutter_webrtc-1.6.0`, nicht vermutet:
  ///  * `AudioSwitchManager.preferredDeviceList` steht ab Werk auf
  ///    **BluetoothHeadset → WiredHeadset → Speakerphone → Earpiece**
  ///    (`AudioSwitchManager.java:136`) — Bluetooth ist von Haus aus zuerst.
  ///  * `setSpeakerphoneOnButPreferBluetooth()` landet in
  ///    `enableSpeakerButPreferBluetooth()`: es sucht in den verfügbaren
  ///    Geräten zuerst das Bluetooth-, dann das Kabel-Headset und nimmt den
  ///    Lautsprecher **nur**, wenn keines von beiden da ist.
  ///  * `audioSessionManagementEnabled` ist `true` (Zeile 63) — der Aufruf ist
  ///    also kein stiller Leerlauf.
  ///  * `audioswitch` ist auf `039a35ae` gepinnt, den Stand, den 1.5.1 wegen
  ///    „Communication Device API support, wired headset and Bluetooth fixes"
  ///    hereingeholt hat.
  ///
  /// ⚠️ Die bekannte Klage „die Route springt nach Sekunden zurück" betrifft
  /// den umgekehrten Fall: `setSpeakerphoneOn(true)` erzwingen, WÄHREND ein
  /// Headset hängt. Das Plugin bevorzugt dann absichtlich das Headset. Für uns
  /// arbeitet dieses Verhalten also mit, nicht gegen uns — deshalb wird hier
  /// bewusst die eingebaute Bevorzugung benutzt und NICHT
  /// `selectAudioOutput`, das genau diesen Kampf anfangen würde.
  ///
  /// Bleibt der Ton trotzdem im Tablet, ist der nächste Knopf
  /// `forceHandleAudioRouting: true` in [AndroidAudioConfiguration] — nicht
  /// vorsorglich gesetzt, weil dafür kein Beleg vorliegt und ein Abweichen von
  /// der Vorgabe ohne Grund neue Fehler baut.
  ///
  /// Nur Android/iOS: auf dem Linux-Rechner entscheidet PipeWire.
  Future<void> _tonWegWaehlen() async {
    if (!PlatformService.isAndroid && !PlatformService.isIOS) return;
    try {
      await Helper.setSpeakerphoneOnButPreferBluetooth();
      final geraete = await Helper.audiooutputs;
      // Ins Protokoll, weil es auf dem Gerät nachprüfbar sein muss: das Plugin
      // verrät die tatsächlich aktive Route nicht (offener Punkt im Projekt,
      // Issue 1987), also ist die Liste der erkannten Ausgänge das Beste, was
      // sich von hier aus feststellen lässt.
      _log.info(
        'sipgate: Bluetooth bevorzugt; erkannte Ausgänge: '
        '${geraete.map((d) => d.label).join(', ')}',
        tag: 'SIPGATE',
      );
    } catch (e) {
      _log.warning('sipgate: Sprachausgabe nicht umgestellt ($e) — System entscheidet',
          tag: 'SIPGATE');
    }
  }

  /// Wie sipgate einen Anrufer bezeichnet, dessen Nummer unterdrückt ist.
  ///
  /// ⚠️ Nachgemessen im echten INVITE: der Anrufer steht in `From`, als
  /// Anzeigename UND als Benutzerteil der URI —
  /// `From: "073180159736" <sip:073180159736@sipgate.de>`. Bei unterdrückter
  /// Nummer trägt die URI `anonymous`; das ungefiltert anzuzeigen hiesse, dem
  /// Vorsitzer „anonymous" als Namen zu präsentieren.
  static const Set<String> _anonym = {
    'anonymous', 'unknown', 'restricted', 'unavailable', 'privat', '',
  };

  /// Ist das ein Name — oder nur die Nummer noch einmal?
  ///
  /// ⚠️ sipgate setzt bei Anrufen aus dem Telefonnetz den Anzeigenamen GLEICH
  /// der Nummer: `From: "073180159736" <sip:073180159736@sipgate.de>`. Wer den
  /// blind übernimmt, schreibt im Verlauf „073180159736 · 073180159736" — und
  /// verdeckt damit den echten Namen, sobald das Verzeichnis ihn nachreicht.
  static bool istEchterName(String? name, String nummer) {
    final n = (name ?? '').trim();
    if (n.isEmpty || anruferAnonym(n)) return false;

    // Steht auch nur ein Buchstabe darin, ist es ein Name — „Praxis Dr. Meier 2"
    // darf nicht daran scheitern, dass eine Zahl vorkommt.
    if (!RegExp(r'^[0-9+()/\s.·-]+$').hasMatch(n)) return true;

    // Sonst ist der „Name" selbst eine Rufnummer. Verglichen wird dann in
    // derselben Form, in der auch gewählt wird — ein roher Ziffernvergleich
    // hielte `+4973180159736` und `073180159736` für verschieden, obwohl es
    // derselbe Anschluss ist. Genau daran ist die erste Fassung gescheitert.
    final a = normalisieren(n);
    final b = normalisieren(nummer);
    return a == null || b == null || a != b;
  }

  /// Macht aus dem, was im `From` steht, etwas Anzeigbares.
  ///
  /// `073180159736` → `0731 80159736` · `+4971112345` bleibt · `anonymous` →
  /// `Unbekannter Anrufer`. Nur zum Ansehen — zurückgerufen wird mit dem
  /// unveränderten Wert, damit hier nie ein Leerzeichen in eine Rufnummer gerät.
  static String anruferAnzeige(String? roh) {
    final r = (roh ?? '').trim();
    if (_anonym.contains(r.toLowerCase())) return 'Unbekannter Anrufer';
    if (r.startsWith('+')) return r;
    // Ortsvorwahlen in Deutschland sind 3–5 Stellen inkl. der führenden Null.
    // Passt es nicht, bleibt die Nummer wie sie ist: falsch zu trennen ist
    // schlimmer als nicht zu trennen.
    if (r.length >= 8 && r.startsWith('0')) {
      return '${r.substring(0, 4)} ${r.substring(4)}';
    }
    return r;
  }

  /// Ob die Nummer des Anrufers unterdrückt ist.
  static bool anruferAnonym(String? roh) =>
      _anonym.contains((roh ?? '').trim().toLowerCase());

  /// Liest die Antwort auf `action: kontakte`.
  ///
  /// ⚠️ FLACH, KEIN `data`. `jsonResponse()` macht `array_merge` — die Felder
  /// liegen direkt in der Antwort. Ein `antwort['data']['kontakte']` wäre
  /// immer `null`, ohne Fehler, und der Bildschirm bliebe leer.
  ///
  /// ⚠️ `kategorien` ist ein PHP-Array. Ist es gefüllt, hat es Zeichenketten
  /// als Schlüssel und wird zu einem JSON-**Objekt**; ist es leer, wird daraus
  /// eine **Liste** `[]`. Genau dieser Unterschied hat beim Speedtest einen
  /// grauen Bildschirm erzeugt: `as Map?` auf eine Liste gibt nicht `null`
  /// zurück, sondern wirft — im Release-Build ohne jede Meldung.
  static ({int gesamt, List<Map<String, dynamic>> kontakte, Map<String, int> kategorien})
      kontakteAusAntwort(Map<String, dynamic> antwort) {
    final rohListe = antwort['kontakte'];
    final kontakte = rohListe is List
        ? rohListe.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    final rohKat = antwort['kategorien'];
    final kategorien = <String, int>{};
    if (rohKat is Map) {
      rohKat.forEach((k, v) {
        final zahl = v is num ? v.toInt() : int.tryParse('$v');
        if (zahl != null) kategorien['$k'] = zahl;
      });
    }

    final gesamt = antwort['gesamt'];
    return (
      gesamt: gesamt is num ? gesamt.toInt() : kontakte.length,
      kontakte: kontakte,
      kategorien: kategorien,
    );
  }

  /// Kategorie eines Kontakts als lesbares Wort.
  ///
  /// Der Server schickt die Kennung (`behoerde`, `arzt`, …), weil danach
  /// gefiltert wird; angezeigt wird das Wort. ⚠️ Was hier nicht steht, wird
  /// **nicht** verschluckt, sondern durchgereicht: eine neue Tabelle auf dem
  /// Server soll in der Liste auftauchen, auch wenn niemand daran gedacht hat,
  /// sie hier einzutragen — sonst verschwindet sie stillschweigend.
  static String kategorieName(String? kennung) {
    return switch ((kennung ?? '').trim()) {
      'eigen' => 'Eigene Kontakte',
      'mitglied' => 'Mitglieder',
      'arzt' => 'Ärzte',
      'klinik' => 'Kliniken',
      'apotheke' => 'Apotheken',
      'sanitaetshaus' => 'Sanitätshäuser',
      'pflege' => 'Pflege',
      'kasse' => 'Kassen',
      'behoerde' => 'Behörden',
      'gericht' => 'Gerichte',
      'polizei' => 'Polizei',
      'rettung' => 'Rettungsdienst',
      'bank' => 'Banken',
      'versicherung' => 'Versicherungen',
      'vermieter' => 'Vermieter',
      'arbeitgeber' => 'Arbeitgeber',
      'bildung' => 'Bildung',
      'dienstleister' => 'Dienstleister',
      'verein' => 'Verein',
      'sonstige' => 'Sonstige',
      '' => 'Sonstige',
      final andere => andere,
    };
  }

  /// Laufende Dauer als Uhr: `03:07`, ab einer Stunde `1:02:15`.
  ///
  /// Für die Anzeige WÄHREND des Gesprächs. Zwei Stellen bei den Minuten,
  /// damit die Zahl nicht bei jedem Wechsel von 9 auf 10 springt und die
  /// Knöpfe daneben verrutschen.
  static String dauerUhr(int sekunden) {
    final s = sekunden < 0 ? 0 : sekunden;
    final std = s ~/ 3600;
    final min = (s % 3600) ~/ 60;
    final sek = s % 60;
    final mm = min.toString().padLeft(2, '0');
    final ss = sek.toString().padLeft(2, '0');
    return std > 0 ? '$std:$mm:$ss' : '$mm:$ss';
  }

  /// Dauer zum Lesen: `42 Sek.`, `3 Min. 7 Sek.`, `1 Std. 2 Min.`
  ///
  /// Für den Verlauf und die Meldung nach dem Auflegen. `03:07` muss man
  /// entschlüsseln, „3 Min. 7 Sek." liest man.
  ///
  /// Ab einer Stunde fallen die Sekunden weg — bei einem Gespräch dieser Länge
  /// interessiert niemand die Sekunde, und die Zeile bleibt kurz.
  static String dauerLesbar(int sekunden) {
    final s = sekunden < 0 ? 0 : sekunden;
    if (s < 60) return '$s Sek.';
    final std = s ~/ 3600;
    final min = (s % 3600) ~/ 60;
    final sek = s % 60;
    if (std > 0) return min == 0 ? '$std Std.' : '$std Std. $min Min.';
    return sek == 0 ? '$min Min.' : '$min Min. $sek Sek.';
  }

  /// Übersetzt eine SIP-Absage in das, was wirklich passiert ist.
  ///
  /// ⚠️ WARUM DAS NICHT „Fehler" HEISSEN DARF
  /// Am 12.08.2026 um 19:07 wurde eine Nummer gewählt und der Bildschirm sagte
  /// „Fehler", im Verlauf stand `Unavailable`. Die echte Antwort war
  /// `480 Temporarily Unavailable, Reason: Q.850;cause=19` — also **niemand hat
  /// abgenommen**. Das ist kein Fehler, das ist ein Telefonat. Der Unterschied
  /// entscheidet, ob man den Fehler bei sich sucht oder es später nochmal
  /// versucht, und er hat einen halben Abend gekostet.
  ///
  /// Der Code steht deshalb ab jetzt IM Verlauf. `Unavailable` allein sagt
  /// nichts; `480 (Q.850 19)` sagt alles.
  static ({String status, String text}) sipAusgang(int? code, String? grund) {
    final zusatz = grund == null || grund.isEmpty ? '' : ' — $grund';
    return switch (code) {
      // Niemand am anderen Ende. 408 ist der Zeitablauf, 487 unser eigenes
      // Abbrechen, 480 die Absage der Gegenstelle.
      480 || 408 || 487 => (status: 'verpasst', text: 'Niemand hat abgenommen ($code)$zusatz'),
      486 || 600 => (status: 'abgelehnt', text: 'Besetzt ($code)$zusatz'),
      603 => (status: 'abgelehnt', text: 'Gespräch abgelehnt ($code)$zusatz'),
      404 || 484 || 485 => (status: 'fehler', text: 'Rufnummer nicht vergeben ($code)$zusatz'),
      401 || 402 || 403 || 407 =>
        (status: 'fehler', text: 'sipgate erlaubt den Anruf nicht ($code)$zusatz — '
            'Guthaben oder Absendernummer prüfen'),
      null => (status: 'fehler', text: grund?.isNotEmpty == true ? grund! : 'Unbekannter Fehler'),
      _ => (status: 'fehler', text: 'SIP $code$zusatz'),
    };
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
      // Flach, kein `data` — siehe [konfigAusAntwort]. Vorher kam hier immer
      // `null` zurück, also bekam jede Fortschreibung eine NEUE Zeile statt die
      // bestehende zu ändern: der Verlauf hätte sich mit Dubletten gefüllt.
      final id = antwort['anruf_id'];
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

class SipgateKonfig {
  const SipgateKonfig({
    required this.sipId,
    required this.ha1,
    required this.realm,
    required this.wssUrl,
    required this.bezeichnung,
    required this.geteilt,
    this.absendernummer,
    this.notrufstandort = 'unbekannt',
  });
  final String sipId;
  final String ha1;
  final String realm;
  final String wssUrl;
  final String? bezeichnung;
  final bool geteilt;

  /// Was der Angerufene sieht. Leer/`null` heisst unterdrueckt.
  final String? absendernummer;

  /// `gesetzt` | `nicht_gesetzt` | `unbekannt` — nur der Zustand, nicht die
  /// Adresse. Ist er nicht `gesetzt`, waere ein Notruf ueber sipgate falsch
  /// geroutet; die Sperre im Client gilt aber ohnehin immer.
  final String notrufstandort;
}

enum SipgateStand { aus, verbindet, registriert, fehler }

enum SipgateGespraechStand { waehlt, klingelt, verbunden }

@immutable
class SipgateZustand {
  const SipgateZustand({
    this.stand = SipgateStand.aus,
    this.sipId,
    this.bezeichnung,
    this.absendernummer,
    this.notrufstandort = 'unbekannt',
    this.bluetoothRecht = 'unbekannt',
    this.vollbildErlaubt,
    this.benachrichtigungenErlaubt,
    this.geteilt = false,
    this.meldung,
    this.naechsterVersuch,
    this.gespraech,
    this.zweites,
    this.konferenz = false,
  });

  final SipgateStand stand;
  final String? sipId;
  final String? bezeichnung;

  /// Was der Angerufene sieht — `null` heisst unterdrueckt.
  ///
  /// Steht im Bildschirm, weil es sonst niemand weiss: ruft man mit
  /// unterdrueckter Nummer bei einem Amt oder einer Praxis an, nehmen viele
  /// gar nicht ab und koennen auf keinen Fall zurueckrufen. Wer das nicht
  /// sieht, sucht den Fehler bei der Verbindung.
  final String? absendernummer;

  /// `gesetzt` | `nicht_gesetzt` | `unbekannt`.
  final String notrufstandort;

  /// Ob Benachrichtigungen für die App überhaupt erlaubt sind
  /// (`POST_NOTIFICATIONS`, Laufzeitberechtigung seit Android 13).
  /// `null` = nicht abgefragt oder nicht Android.
  ///
  /// ⚠️ Ohne sie erscheint bei einem eingehenden Anruf **nichts** — und zwar
  /// geräuschlos, denn eine verworfene Benachrichtigung wirft nicht. Es klingelt
  /// dann zwar, aber wer anruft steht nirgends.
  final bool? benachrichtigungenErlaubt;

  /// Ob `USE_FULL_SCREEN_INTENT` **erteilt** ist — nicht ob sie im Manifest
  /// steht. `null` = noch nicht abgefragt oder nicht Android.
  ///
  /// ⚠️ Seit Android 14 wird die Berechtigung nur Telefonie- und
  /// Weckerapps automatisch gegeben, und der Play Store zieht sie anderen ab.
  /// Ohne sie zeigt Android bei einem Anruf nur einen Streifen — hinter dem
  /// Sperrbildschirm eines Tablets, das auf dem Tisch liegt, sieht das niemand.
  final bool? vollbildErlaubt;

  /// Zustand von BLUETOOTH_CONNECT auf diesem Gerät: `erteilt`,
  /// `nicht_noetig` (Android < 12), `abgelehnt`, `dauerhaft_abgelehnt`,
  /// `kein_dialog`, `unbekannt`.
  ///
  /// ⚠️ Steht im Bildschirm, weil ohne diese Berechtigung `audioswitch` das
  /// gekoppelte Headset nicht findet und das Gespräch im Tablet-Lautsprecher
  /// landet — ohne Fehlermeldung. Das ist der wahrscheinlichste Grund, wenn
  /// „ich höre nichts im Kopfhörer" gemeldet wird.
  final String bluetoothRecht;

  /// Zwei Geräte hängen an derselben SIP-ID. Bei sipgate klingeln dann beide
  /// (Parallelruf) — kein Fehler, aber der Bildschirm soll es sagen können.
  final bool geteilt;
  final String? meldung;

  /// Wann der nächste Anmeldeversuch ansteht, oder `null`.
  ///
  /// ⚠️ Der Unterschied, den die Oberfläche daraus zieht, ist der wichtigste
  /// an diesem Zustand: `fehler` **mit** Zeitpunkt heißt „arbeitet daran",
  /// `fehler` **ohne** heißt „hier hilft nur noch ein Mensch". Beides rot zu
  /// malen würde die Wiederholung wieder unsichtbar machen.
  final DateTime? naechsterVersuch;

  /// Das erste Gesprächsbein.
  final SipgateGespraech? gespraech;

  /// Das zweite Bein, für die Dreierkonferenz. `null`, solange nur eines läuft.
  ///
  /// ⚠️ Zwei gleichzeitige Gespräche auf einer SIP-ID sind erlaubt —
  /// nachgemessen am 12.08.2026: während Bein A klingelte, hat sipgate Bein B
  /// angenommen und geroutet (`100 trying` → `407` → `100 trying` → Antwort der
  /// Gegenstelle). Die Sorge, ein User dürfe nur ein Gespräch führen, trifft
  /// auf abgehende Anrufe nicht zu.
  final SipgateGespraech? zweites;

  /// Ob `*5` geschickt wurde, die beiden Beine also zusammengeschaltet sind.
  ///
  /// Das Mischen macht **sipgate**, nicht wir. Zwei entfernte Tonspuren
  /// ineinander zu mischen kann `flutter_webrtc` nicht — jede Seite würde nur
  /// uns hören, nicht die andere. Die Anlage ist der richtige Ort dafür, und
  /// die Dreierkonferenz ist im Tarif business L enthalten (Preisliste
  /// Stand Mai 2026: `3er-Konferenz — ja`).
  final bool konferenz;

  /// Beide Beine, in der Reihenfolge, in der sie entstanden sind.
  List<SipgateGespraech> get beine =>
      [if (gespraech != null) gespraech!, if (zweites != null) zweites!];

  /// Wie viele Beine gerade verbunden sind — entscheidet, ob `*5` überhaupt
  /// etwas zusammenschalten könnte.
  int get verbundeneBeine =>
      beine.where((g) => g.stand == SipgateGespraechStand.verbunden).length;
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
    this.gehalten = false,
  });

  final String nummer;
  final String? name;
  final bool eingehend;
  final SipgateGespraechStand stand;
  final DateTime? verbundenSeit;
  final bool stumm;

  /// In der Warteschleife der sipgate-Anlage (`*3`).
  final bool gehalten;

  int get dauerSekunden => verbundenSeit == null
      ? 0
      : DateTime.now().difference(verbundenSeit!).inSeconds;

  SipgateGespraech kopie({
    SipgateGespraechStand? stand,
    DateTime? verbundenSeit,
    bool? stumm,
    bool? gehalten,
  }) =>
      SipgateGespraech(
        nummer: nummer,
        name: name,
        eingehend: eingehend,
        stand: stand ?? this.stand,
        verbundenSeit: verbundenSeit ?? this.verbundenSeit,
        stumm: stumm ?? this.stumm,
        gehalten: gehalten ?? this.gehalten,
      );

  /// Das, was auf dem Bildschirm steht.
  ///
  /// ⚠️ Ein echter Name hat Vorrang — aber sipgate setzt bei Anrufen aus dem
  /// Telefonnetz den Anzeigenamen GLEICH der Nummer. Nachgemessen:
  /// `From: "073180156736" <sip:073180159736@sipgate.de>`. Wer den Namen blind
  /// bevorzugt, zeigt dann `073180159736` statt `0731 80159736` — und bei
  /// unterdrückter Nummer das Wort `anonymous`.
  ///
  /// Deshalb: nur ein Name, der sich von der Nummer unterscheidet, ist ein
  /// Name. Alles andere geht durch [SipgateService.anruferAnzeige].
  String get anzeige {
    final n = (name ?? '').trim();
    final nurZiffern = RegExp(r'\D');
    final nameZiffern = n.replaceAll(nurZiffern, '');
    final nummerZiffern = nummer.replaceAll(nurZiffern, '');
    final istEchterName = n.isNotEmpty &&
        !(nameZiffern.isNotEmpty && nameZiffern == nummerZiffern) &&
        !SipgateService.anruferAnonym(n);
    return istEchterName ? n : SipgateService.anruferAnzeige(nummer);
  }
}
