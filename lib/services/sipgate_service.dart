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
import 'qualitaets_sonde.dart';
import 'secure_store.dart';
import 'signatur_gateway_service.dart';
import 'untertitel_modell.dart';
import 'untertitel_service.dart';
import 'voice_call_service.dart' show iceServerEintraege;
import '../utils/mitschrift_sprachen.dart';

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
/// Darf sich DIESES Geraet bei sipgate anmelden?
///
/// ⚠️ Der Server verweigert nie. `sipgateGeraetWaehlen()` in `sipgate_lib.php`
/// sucht der Reihe nach ein Telefon fuer genau dieses Geraet, dann ein freies,
/// und faellt zuletzt auf „irgendeines, das aktiv ist" zurueck — ausdruecklich
/// unter dem Kommentar „Nichts frei — teilen statt verweigern". Ein
/// `geteilt = true` in der Antwort heisst also nicht „hier ist dein Telefon",
/// sondern „ich habe nichts Eigenes fuer dich, nimm solange das von jemand
/// anderem".
///
/// Das anzunehmen war die Falle: sipgate laesst bei zwei Anmeldungen auf einer
/// SIP-ID beide klingeln (Parallelruf), und wer zuerst abnimmt, gewinnt. Ein
/// Anruf eines Klienten koennte in einer Hosentasche landen statt am Tablet,
/// an dem das Bluetooth-Headset haengt — und weil `autoAktiv()` auf Android
/// voreingestellt AN ist, brauchte es dafuer niemanden, der etwas einschaltet.
///
/// Entscheidung des Users (23.08.2026): nur das Geraet mit eigenem Telefon
/// meldet sich an. Geprueft am Besitz, nicht am Geraetenamen — ein
/// Tabletwechsel soll kein Release brauchen.
bool sipgateDarfAnmelden({required bool geteilt}) => !geteilt;

/// Die Kennung, mit der sich diese App bei sipgate anmeldet.
///
/// ⚠️ Muss zeichengleich zu `SIPGATE_EIGENER_USER_AGENT` in
/// `api/sipgate/sipgate_lib.php` bleiben. Weicht sie ab, haelt der Bildschirm
/// die eigene Anmeldung fuer ein fremdes Softphone und warnt vor etwas, das in
/// Ordnung ist. Der Server schickt seinen Wert deshalb mit, statt dass hier
/// jemand raet — siehe [sipgateTelefonLage].
const String sipgateEigenerUserAgent = 'ICD360S-Vorsitzer';

/// Was ueber ein VoIP-Telefon gerade zu sagen ist.
enum SipgateTelefonLage {
  /// Angemeldet, und zwar mit unserer App. Alles in Ordnung.
  bereit,

  /// Angemeldet — aber die Anmeldung haelt ein fremdes Softphone. Unsere App
  /// ist es nicht, ein Auftrag mit `wahlweg: sipgate` scheitert also.
  fremdesGeraet,

  /// Angemeldet, steht aber bei sipgate auf „nicht stoeren". Es klingelt
  /// nichts.
  ///
  /// ⚠️ Dafuer gab es in der App bisher KEIN Zeichen. Ein eingehender Anruf
  /// waere schlicht nie angekommen, und niemand haette gewusst warum.
  nichtStoeren,

  /// Nicht angemeldet. Ein Anruf ueber sipgate wuerde scheitern.
  abgemeldet,

  /// Wir wissen es nicht — der Zustand wurde noch nie geholt, oder sipgate war
  /// nicht erreichbar. **Nicht** dasselbe wie „abgemeldet".
  unbekannt,
}

/// Ordnet die drei Angaben von sipgate zu einer Aussage.
///
/// ⚠️ DIE REIHENFOLGE IST DIE AUSSAGE.
/// Ist ueberhaupt nichts bekannt, wird nichts behauptet. Danach entscheidet,
/// was den Anruf tatsaechlich verhindert: erst „gar nicht angemeldet", dann
/// „angemeldet, aber nicht unsere App" (dann kann unser Auftrag nicht wirken),
/// erst danach „nicht stoeren". Ein `dnd` auf einer fremden Anmeldung zu
/// melden hiesse, den zweiten Grund zu nennen und den ersten zu verschweigen.
SipgateTelefonLage sipgateTelefonLage({
  required bool? online,
  required bool? dnd,
  required String? userAgent,
  String eigenerUserAgent = sipgateEigenerUserAgent,
}) {
  if (online == null) return SipgateTelefonLage.unbekannt;
  if (!online) return SipgateTelefonLage.abgemeldet;
  // Leer heisst: angemeldet, aber sipgate nennt keine Kennung. Das ist kein
  // Grund, ein fremdes Geraet zu behaupten.
  final ua = userAgent?.trim() ?? '';
  if (ua.isNotEmpty && ua != eigenerUserAgent) {
    return SipgateTelefonLage.fremdesGeraet;
  }
  if (dnd == true) return SipgateTelefonLage.nichtStoeren;
  return SipgateTelefonLage.bereit;
}

/// Ist diese Verlaufszeile ein verpasster Anruf, um den sich noch niemand
/// gekuemmert hat?
///
/// Entscheidet zweierlei im Verlauf: ob die Zeile hervorgehoben wird und ob
/// das Zurueckrufen den Anruf aus dem Abzeichen nimmt. Beide Male dieselbe
/// Regel — als Funktion, weil sie sonst an zwei Stellen steht und beim
/// naechsten Anfassen auseinanderlaeuft.
///
/// ⚠️ `abgelehnt` gehoert NICHT dazu: einen Anruf wegzudruecken ist eine
/// Entscheidung, kein Versaeumnis. `klingelt` dagegen schon — drei Zeilen
/// stehen dauerhaft darauf, weil die App mitten im Laeuten abgeraeumt wurde.
///
/// ⚠️ DIE ANTWORT KOMMT VOM SERVER, WENN ER SIE MITSCHICKT — und das ist keine
/// Bequemlichkeit. Dieselbe Frage beantwortet `sipgateVerpasstZaehlen()` in SQL,
/// und dort gilt zusaetzlich eine Altersgrenze: `klingelt` zaehlt erst nach
/// fuenf Minuten, sonst spraenge das Abzeichen an, waehrend das Telefon noch
/// laeutet. Hier stand diese Grenze nicht — die beiden gaben also fuer eine
/// Zeile, die GERADE klingelt, verschiedene Antworten.
///
/// Nachrechnen kann der Client sie auch nicht: `begonnen_am` schreibt MySQL,
/// und MySQL laeuft auf diesem Server in Europe/Berlin, waehrend PHP auf UTC
/// steht (nachgemessen am 30.08.2026: `NOW()` = 10:04 CEST, `date()` = 08:04
/// UTC). Eine zweite Rechnung gegen die Geraeteuhr waere nicht bloss doppelt,
/// sondern in einer anderen Zeitrechnung — und faellt niemandem auf, weil sie
/// auf einem Berliner Geraet zufaellig stimmt.
///
/// Der Rueckfall bleibt trotzdem stehen: eine aeltere Serverfassung kennt
/// `verpasst_offen` nicht, und dann ist die alte Regel besser als gar keine
/// Hervorhebung.
bool sipgateVerpasstOffen(Map<String, dynamic> zeile) {
  final vomServer = zeile['verpasst_offen'];
  // ⚠️ `num` mitnehmen, nicht nur `bool`: ob PHP `true` oder `1` schickt, haengt
  // daran, wie der Wert entstanden ist — hier kommt er aus einem SQL-Ausdruck.
  if (vomServer is bool) return vomServer;
  if (vomServer is num) return vomServer != 0;

  if (zeile['richtung'] != 'ein') return false;
  if (zeile['gesehen'] == true) return false;
  final status = '${zeile['status']}';
  return status == 'verpasst' || status == 'klingelt';
}

/// Der Text am Telefonsymbol in der Kopfleiste.
///
/// ⚠️ HIER DARF NICHTS UEBER EIN GESPRAECH STEHEN, UND DAS IST DER ZWECK
/// DIESER FUNKTION. Bis zum 23.08.2026 hiess es bei einer stehenden Anmeldung
/// `Gespräch läuft — <Nummer>`, sobald [SipgateZustand.gespraech] gesetzt war.
/// Gesetzt wird es aber schon bei `CALL_INITIATION`, also mit `klingelt`
/// (eingehend) oder `waehlt` (abgehend) — in zwei von drei Faellen war die
/// Aussage falsch, und bei einem abgehenden Anruf widersprach sie der
/// schwebenden Karte, die korrekt „Wählt …" zeigt.
///
/// Das Gespraech gehoert der Karte ([SipgateAnrufOverlay]): sie ist die Form,
/// die beide Systeme fuer eine laufende Taetigkeit vorsehen — Text, Farbe,
/// Dauer, antippbar —, und sie liegt ueber demselben Bildschirm wie dieser
/// Knopf. Zwei Aussagen ueber dieselbe Sache, von denen eine falsch ist, sind
/// schlimmer als eine.
///
/// Als Funktion und nicht als `switch` im Widget, damit der Test festhalten
/// kann, dass der Text sich NICHT aendert, wenn ein Gespraech anliegt.
String sipgateKopfText(SipgateZustand z) => switch (z.stand) {
      SipgateStand.registriert =>
        'sipgate — angemeldet${z.sipId == null ? '' : ' (${z.sipId})'}',
      SipgateStand.verbindet => 'sipgate — melde an …',
      // Der Grund UND der naechste Anlauf, nicht bloss das Wort. `meldung`
      // traegt beides; ohne sie stuende hier weiter „nicht angemeldet", also
      // genau die Auskunft, die nichts sagt.
      SipgateStand.fehler => z.meldung ?? 'sipgate — nicht angemeldet',
      SipgateStand.aus => 'sipgate — Telefonie',
      SipgateStand.fremdesTelefon =>
        z.meldung ?? 'sipgate — anderes Gerät telefoniert',
    };

/// Welche der drei Aussagen ueber die Absendernummer zutrifft.
enum SipgateAbsenderAnzeige {
  /// Wir kennen die Nummer und koennen sie hinschreiben.
  nummer,

  /// Der Server hat ausdruecklich „leer" gesagt: der Angerufene sieht nichts.
  unterdrueckt,

  /// Wir wissen es nicht. **Das ist eine eigene Aussage**, keine Abart von
  /// „unterdrueckt".
  unbekannt,
}

/// Entscheidet, welcher Satz im Bildschirm steht.
///
/// ⚠️ Als Funktion und nicht als drei Bedingungen im Widget, weil genau hier
/// die falsche Aussage entstand: `nummer == null` hiess „unterdrueckt", und
/// „unterdrueckt" zieht im Bildschirm den Satz nach sich, dass viele Aemter
/// dann nicht abnehmen und nicht zurueckrufen koennen. Wer das liest, waehlt
/// anders oder sucht einen Fehler, den es nicht gibt.
SipgateAbsenderAnzeige sipgateAbsenderAnzeige({
  required bool bekannt,
  required String? nummer,
}) {
  if (!bekannt) return SipgateAbsenderAnzeige.unbekannt;
  final sauber = nummer?.trim() ?? '';
  return sauber.isEmpty
      ? SipgateAbsenderAnzeige.unterdrueckt
      : SipgateAbsenderAnzeige.nummer;
}

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

  // Die weichen Angaben werden mitgelegt, damit die Rueckfalloption nicht nur
  // anmelden, sondern auch Auskunft geben kann.
  //
  // ⚠️ Der leere String ist hier ein ECHTER Wert: er heisst „unterdrueckt".
  // Ein fehlender Schluessel heisst „nie gespeichert". Genau diese beiden
  // auseinanderzuhalten ist der Zweck der Uebung — `read()` liefert `null` nur
  // im zweiten Fall.
  static const String _storeAbsender = 'sipgate_absendernummer';
  static const String _storeGeteilt = 'sipgate_geteilt';
  static const String _storeNotruf = 'sipgate_notrufstandort';
  static const String _storeBezeichnung = 'sipgate_bezeichnung';

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

  /// Die zuletzt gemessene Güte des laufenden Gesprächs, oder `null`.
  ///
  /// ⚠️ Eigener Melder statt eines Feldes in [zustand]: die Güte kommt im
  /// eigenen Takt und geht nur ein einziges Fähnchen an; hinge sie am
  /// Gesamtzustand, würde alle drei Sekunden der ganze Gesprächsschirm neu
  /// gebaut — genau die Last, wegen der der Sekundentakt weiter unten
  /// abgeschafft wurde.
  final ValueNotifier<QualitaetsProbe?> guete =
      ValueNotifier<QualitaetsProbe?>(null);

  /// Die Bilanz des laufenden Gesprächs. Wird am Ende ins Protokoll geschrieben.
  final QualitaetsBilanz gueteBilanz = QualitaetsBilanz();

  final QualitaetsSonde _sonde = QualitaetsSonde();
  Timer? _gueteTakt;
  bool _gueteGemeldet = false;

  /// Die beiden Gesprächsbeine. `A` ist das erste, `B` das hinzugewählte.
  Call? _rufA;
  Call? _rufB;

  /// Welches Bein der Vorsitzer gerade spricht. Bei einer Konferenz zählt `A`
  /// als das Bein, an das die Steuercodes gehen.
  String _aktiv = 'A';

  // ⚠️ HIER STAND EIN SEKUNDENTAKT, UND ER WAR EIN FEHLER.
  //
  // Ein `Timer.periodic` schob jede Sekunde einen kompletten neuen Zustand in
  // [zustand], damit die Gesprächsdauer weiterläuft. Zwei Folgen:
  //
  //  1. Jeder Zuhörer wurde im Sekundentakt neu gebaut — auch die Kopfleiste
  //     des Dashboards, die von der Dauer kein Wort zeigt.
  //
  //  2. Schwerer: [_setz] führt `meldung` und `naechsterVersuch` bewusst NICHT
  //     fort, und der Takt rief es ohne beide. Scheiterte die Anmeldung
  //     während eines Gesprächs, waren Grund und geplanter Anlauf nach
  //     höchstens einer Sekunde gelöscht — die Kopfleiste sprang von
  //     Bernstein („arbeitet daran") auf Rot („hier hilft nur ein Mensch"),
  //     obwohl die Wiederholung lief. Die Unterscheidung, für die beide Farben
  //     eingeführt wurden, hob sich damit selbst auf.
  //
  // Die Dauer rechnet [SipgateGespraech.dauerSekunden] ohnehin selbst aus
  // `verbundenSeit`. Es muss also nur jemand neu bauen — und das tut jetzt
  // `SekundenTakt` genau dort, wo die Zahl steht.
  int? _anrufIdA; // Zeilen in sipgate_anrufe, werden fortgeschrieben
  int? _anrufIdB;
  String? _sipId;
  bool _startetGerade = false;

  /// Die Tonspur der GEGENSTELLE, für die Live-Untertitel.
  ///
  /// ⚠️ Kommt aus `CallStateEnum.STREAM` mit `originator == remote` — der
  /// einzigen Stelle, an der `sip_ua` den entfernten Strom herausgibt. Ohne
  /// diese Kennung findet die native Seite die Spur nicht: sie fragt damit
  /// `FlutterWebRTCPlugin.getRemoteTrack(id)`.
  ///
  /// ⚠️ Nur die des ERSTEN Beins. Bei zwei Gesprächen ist nicht entscheidbar,
  /// wen der Vorsitzende gerade mitlesen will — und zwei Untertitelspuren
  /// übereinander wären unlesbar.
  String? gegenstelleSpurId;

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

  /// Ob `*5` jetzt Sinn hätte: ein zweiter Teilnehmer ist dazugewählt und es
  /// läuft noch keine Konferenz.
  ///
  /// 🔴 NICHT MEHR `verbundeneBeine == 2`, und das war der zweite Grund, warum
  /// der Knopf nie erschien. Seit der zweite Teilnehmer über die Anlage
  /// (`*3<nr>#`) und nicht als eigener SIP-Dialog dazukommt, gibt es für ihn
  /// gar kein `verbunden`-Signal — die Bedingung konnte nie wahr werden, und
  /// der Knopf blieb unsichtbar, ohne dass irgendwo etwas fehlschlug.
  ///
  /// ⚠️ „Kann" heisst hier: es ist sinnvoll, es zu VERSUCHEN. Ob der zweite
  /// Teilnehmer schon abgehoben hat, weiss nur der Mensch am Hörer.
  bool get kannKonferenz =>
      !zustand.value.konferenz && zustand.value.zweites != null;

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
      } else if (e == 'sipgate-aktion:${NotificationService.aktionAuflegen}') {
        auflegen();
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

      // ⚠️ NUR MIT EIGENEM TELEFON ANMELDEN.
      //
      // Der Server verweigert nie: `sipgateGeraetWaehlen()` in
      // `sipgate_lib.php` sucht der Reihe nach ein Telefon fuer genau dieses
      // Geraet, dann ein freies, und faellt zuletzt auf „irgendeines, das
      // aktiv ist" zurueck — ausdruecklich unter dem Kommentar „Nichts frei —
      // teilen statt verweigern". Es gibt derzeit genau ein VoIP-Telefon, und
      // das gehoert dem Tablet. Jedes andere Android-Geraet bekaeme also
      // dessen SIP-ID mit `geteilt = true`.
      //
      // Was daraus folgte, ist kein Schoenheitsfehler: sipgate laesst bei zwei
      // Anmeldungen auf einer SIP-ID beide klingeln (Parallelruf), und wer
      // zuerst abnimmt, gewinnt. Ein Anruf eines Klienten koennte also in
      // einer Hosentasche landen statt am Tablet, an dem das Bluetooth-Headset
      // haengt. Und weil `autoAktiv()` auf Android voreingestellt AN ist,
      // brauchte es dafuer niemanden, der etwas einschaltet.
      //
      // Entscheidung des Users (23.08.2026): **nur das Tablet telefoniert.**
      // Geprueft wird das aber an „hat ein eigenes Telefon", nicht am
      // Geraetenamen — sonst braeuchte ein Tabletwechsel ein Release. Zurueck
      // gibt es den Weg ueber „Geraetezuordnung loesen" im Bildschirm.
      if (!sipgateDarfAnmelden(geteilt: cfg.geteilt)) {
        _log.info('sipgate: kein eigenes VoIP-Telefon (${cfg.sipId} gehoert einem '
            'anderen Geraet) — es wird nicht angemeldet', tag: 'SIPGATE');
        _wiederholungAbbrechen();
        // Kein eigenes Telefon heisst: hier wird nie eine Anmeldung gehalten.
        // Also darf dieses Geraet auch keinen Vordergrunddienst dafuer
        // hochziehen — sonst traegt ausgerechnet der RDP-Kiosk eine
        // Dauerbenachrichtigung fuer eine Registrierung, die er nie eingeht.
        SignaturGatewayService.sipgateHaeltRegistrierung = false;
        unawaited(SignaturGatewayService.stoppenWennUnnoetig());
        _setz(
          stand: SipgateStand.fremdesTelefon,
          sipId: cfg.sipId,
          bezeichnung: cfg.bezeichnung,
          geteilt: true,
          meldung: 'Dieses Gerät hat kein eigenes VoIP-Telefon — ${cfg.sipId} '
              'gehört einem anderen Gerät.\n'
              'Telefoniert wird dort. Soll es hier laufen, im Abschnitt '
              '„VoIP-Telefone" ein eigenes anlegen oder die Gerätezuordnung '
              'lösen.',
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
        absendernummer: cfg.absendernummer,
        // Der Server hat gesprochen: sagt er „unterdrueckt", muss eine frueher
        // angezeigte Nummer verschwinden.
        loescheAbsendernummer: cfg.absendernummerBekannt && cfg.absendernummer == null,
        absendernummerBekannt: cfg.absendernummerBekannt,
        notrufstandort: cfg.notrufstandort,
        geteilt: cfg.geteilt,
        meldung: 'Melde an …',
      );

      // ⚠️ DER VORDERGRUNDDIENST IST DIE LEBENSVERSICHERUNG DIESER ANMELDUNG.
      //
      // `sip_ua` laeuft im Haupt-Isolat, und ein Haupt-Isolat ohne
      // Vordergrunddienst darf Android einfrieren oder abraeumen. Dann
      // scheitert die Erneuerung nach 295 s, es klingelt nichts mehr, und das
      // einzige Zeichen ist ein rotes Symbol, das jemandem auffallen muss.
      //
      // Bis zum 30.08.2026 hat diesen Dienst NIEMAND fuer die Telefonie
      // gestartet: er haengt an `TerminSmsGatewayService` und
      // `AnrufGatewayService`. Dass es trotzdem lief, war Zufall — dasselbe
      // Tablet traegt auch das SMS-Gateway. Wer diesen Schalter umlegte, haette
      // ohne es zu merken die Telefonie mit abgeschaltet.
      //
      // ⚠️ HIER und nicht schon bei `_gewollt = true`: erst ab dieser Zeile
      // steht fest, dass dieses Geraet ein EIGENES VoIP-Telefon hat. Die
      // Grenze, die das offen laesst, sei genannt: scheitert schon das Holen
      // der Zugangsdaten (frisches Geraet, kein Netz, kein Zwischenspeicher),
      // haelt niemand den Prozess, und der eingeplante Anlauf koennte
      // eingefroren werden. Das heilt beim naechsten Oeffnen der App von
      // selbst — im Vordergrund friert nichts ein. Die haeufige
      // Wiederholung (abgelehntes REGISTER auf stehender Verbindung) laeuft
      // ohnehin erst, nachdem diese Zeile einmal durch war.
      SignaturGatewayService.sipgateHaeltRegistrierung = true;
      await SignaturGatewayService.starten();

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
    // Wir halten ab jetzt keine Anmeldung mehr — der Dienst faellt weg, sofern
    // ihn nicht SMS-Gateway oder Fernwahl weiter brauchen.
    SignaturGatewayService.sipgateHaeltRegistrierung = false;
    gegenstelleSpurId = null;
    unawaited(UntertitelService().beenden());
    unawaited(NotificationService().cancelOngoingCall().catchError((Object e) =>
        _log.warning('sipgate: Gesprächsmeldung nicht entfernt ($e)',
            tag: 'SIPGATE')));
    // ⚠️ ERST die offenen Beine abschliessen, DANN die Merker leeren.
    //
    // Bis zum 30.08.2026 stand hier nur das Leeren. Wer die Telefonie waehrend
    // eines Gespraechs abschaltete, liess damit eine Verlaufszeile auf
    // `verbunden` stehen — fuer immer: `_helper.stop()` beendet zwar die
    // Sitzung, aber das darauf folgende `ENDED` findet `_anrufIdA` bereits auf
    // `null` und `_anrufProtokoll()` steigt in seiner Waechterzeile aus. Am
    // 30.08.2026 lagen 13 solcher Zeilen in der Datenbank, die aelteste vom
    // 13.08.; im Verlauf lasen sie sich als Gespraeche, die seit Wochen laufen.
    //
    // Der Prozesstod bleibt unheilbar — wer abgeraeumt wird, schreibt nichts
    // mehr; dafuer raeumt der Server nach zwoelf Stunden auf
    // (`sipgateVerwaisteSchliessen`). Aber DIESER Fall ist kein Prozesstod,
    // sondern ein Knopfdruck, und der kann sauber aufraeumen.
    await _offeneBeineSchliessen();
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
    await SignaturGatewayService.stoppenWennUnnoetig();
  }

  /// Legt auf und schreibt zu Ende, was beim Abschalten noch laeuft.
  ///
  /// ⚠️ Der Status ist nicht immer `beendet`. Ein eingehender Anruf, der noch
  /// klingelte, wurde nicht gefuehrt — er ist `verpasst`, dieselbe Regel wie im
  /// `ENDED`-Zweig von [_gespraech]. Ihn als `beendet` zu buchen hiesse, ihn aus
  /// dem Abzeichen zu nehmen, ohne dass jemand rangegangen ist.
  ///
  /// ⚠️ Die Dauer wird VOR dem Auflegen genommen. Danach ist `verbundenSeit`
  /// zwar noch da, aber die Zeile koennte schon vom `ENDED`-Ereignis
  /// ueberschrieben sein — und dann stuende dort die Dauer von jetzt statt die
  /// des Gespraechs.
  ///
  /// Wirft nie: ein Protokolleintrag darf das Abschalten nicht aufhalten.
  Future<void> _offeneBeineSchliessen() async {
    for (final seite in const ['A', 'B']) {
      final ruf = seite == 'A' ? _rufA : _rufB;
      final g = _bein(seite);
      final id = _protokollId(seite);
      if (ruf == null && id == null) continue;

      if (id != null) {
        final verpasst = g != null &&
            g.eingehend &&
            g.stand != SipgateGespraechStand.verbunden;
        await _anrufProtokoll(
          anrufId: id,
          status: verpasst ? 'verpasst' : 'beendet',
          dauerS: g?.dauerSekunden ?? 0,
          // Steht als Notiz in der Zeile, nicht als Fehler: der Anruf ist nicht
          // gescheitert, er wurde von uns beendet. Ohne den Satz saehe ein
          // Gespraech von drei Sekunden aus wie ein Verbindungsabbruch.
          fehler: 'Telefonie wurde während des Gesprächs abgeschaltet',
        );
      }
      try {
        ruf?.hangup();
      } catch (e) {
        // Die Sitzung kann in derselben Sekunde schon weg sein — kein Grund,
        // das Abschalten daran scheitern zu lassen.
        _log.warning('sipgate: Bein $seite liess sich nicht auflegen: $e',
            tag: 'SIPGATE');
      }
    }
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
    // ⚠️ FEHLENDER SCHLUESSEL IST NICHT DASSELBE WIE LEERER WERT.
    // Ein aelterer Server schickt `absendernummer` gar nicht mit — der Test
    // „ein aelterer Server ohne absendernummer darf die Anmeldung nicht
    // verhindern" haelt genau diesen Fall fest. Vorher wurde daraus ebenfalls
    // `null` und damit im Bildschirm „Angerufene sehen: unterdrueckt". Leer
    // heisst unterdrueckt, fehlend heisst unbekannt.
    return SipgateKonfig(
      sipId: sipId,
      ha1: ha1,
      realm: '${antwort['realm'] ?? 'sipgate.de'}',
      wssUrl: '${antwort['wss_url'] ?? 'wss://sip.sipgate.de'}',
      bezeichnung: antwort['bezeichnung'] as String?,
      geteilt: antwort['geteilt'] == true,
      absendernummer: absender.isEmpty ? null : absender,
      absendernummerBekannt: antwort.containsKey('absendernummer'),
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
        // ⚠️ NUR schreiben, wenn der Server das Feld wirklich geschickt hat.
        // Sonst legten wir eine Unbekannte als leeren String ab — und beim
        // naechsten Start laese der Rueckfall daraus „bekannt, unterdrueckt".
        // Der Zwischenspeicher wuerde die Falschaussage also erst erzeugen,
        // die er verhindern soll. Loeschen statt leer schreiben.
        if (cfg.absendernummerBekannt) {
          await _store.write(key: _storeAbsender, value: cfg.absendernummer ?? '');
        } else {
          await _store.delete(key: _storeAbsender);
        }
        await _store.write(key: _storeGeteilt, value: cfg.geteilt ? '1' : '0');
        await _store.write(key: _storeNotruf, value: cfg.notrufstandort);
        await _store.write(key: _storeBezeichnung, value: cfg.bezeichnung ?? '');
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

    // ⚠️ Die weichen Angaben kommen mit, wenn sie je gespeichert wurden — und
    // NUR dann gelten sie als bekannt. Vorher stand hier `bezeichnung: null,
    // geteilt: false` und implizit `absendernummer: null`; der Bildschirm hat
    // daraus „Angerufene sehen: unterdrueckt" gemacht, obwohl das Konto die
    // Nummer sehr wohl mitschickt. Ein fehlender Schluessel (ganz frisches
    // Geraet, geleerter Speicher, Aufstieg von einer aelteren App) sagt jetzt
    // „unbekannt" statt eine Aussenwirkung zu behaupten.
    final absender = await _store.read(key: _storeAbsender);
    final geteilt = await _store.read(key: _storeGeteilt);
    final notruf = await _store.read(key: _storeNotruf);
    final bezeichnung = await _store.read(key: _storeBezeichnung);
    final bekannt = absender != null; // Schluessel vorhanden, Wert darf leer sein

    return SipgateKonfig(
      sipId: sipId,
      ha1: ha1,
      realm: 'sipgate.de',
      wssUrl: 'wss://sip.sipgate.de',
      bezeichnung: (bezeichnung == null || bezeichnung.isEmpty) ? null : bezeichnung,
      geteilt: geteilt == '1',
      absendernummer: (absender == null || absender.isEmpty) ? null : absender,
      notrufstandort: (notruf == null || notruf.isEmpty) ? 'unbekannt' : notruf,
      absendernummerBekannt: bekannt,
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
  ///
  /// 🔴 ÜBER DIE ANLAGE, NICHT ALS ZWEITER SIP-RUF — und genau daran ist die
  /// Konferenz vorher gescheitert.
  ///
  /// Die alte Fassung hielt das erste Gespräch mit `*3` und öffnete dann mit
  /// `_helper.call(...)` einen ZWEITEN, eigenständigen SIP-Dialog. Für die
  /// Anlage sind das zwei Anrufe, die nichts miteinander zu tun haben; ein
  /// späteres `*5` hat dann nichts zusammenzuschalten. Es sah aus wie eine
  /// Kleinigkeit im Zustand und war der ganze Fehler.
  ///
  /// sipgate schreibt die Folge selbst vor (help.sipgate.de, „Tastenkürzel"):
  ///
  ///     Halten          *3
  ///     Transfer        *3<Rufnummer>#
  ///     Konferenz       *5   — „nach dem Transfer eines weiteren
  ///                            Teilnehmers … alle zusammenschalten"
  ///
  /// Also: `*3`, Nummer, `#` auf DEMSELBEN Gespräch. Danach kennt die Anlage
  /// beide Teilnehmer auf einer Leitung, und `*5` hat etwas zu tun.
  Future<String?> _zweitesWaehlen(String nummer, String? bezeichnung) async {
    final ruf = _rufA ?? _rufB;
    if (ruf == null) return 'Kein Gespräch.';

    _anrufIdB = await _anrufProtokoll(
      richtung: 'aus',
      nummer: nummer,
      bezeichnung: bezeichnung,
      status: 'gestartet',
    );

    if (!await _steuerfolge(ruf, ['*3', nummer, '#'])) {
      await _anrufProtokoll(
          anrufId: _anrufIdB, status: 'fehler', fehler: 'DTMF nicht gesendet');
      return 'Die Anlage hat die Nummer nicht angenommen — steht das '
          'Gespräch noch?';
    }
    _aktiv = 'B';
    // ⚠️ `waehlt` und NICHT `verbunden`, obwohl die Anlage jetzt wählt: für
    // diesen zweiten Teilnehmer gibt es KEINEN eigenen SIP-Dialog, also auch
    // kein Signal, wenn er abhebt. Zu behaupten, er sei verbunden, wäre eine
    // Angabe, die niemand geprüft hat. Der Bildschirm sagt deshalb „angewählt"
    // und überlässt den nächsten Schritt dem Menschen, der hört, ob jemand
    // dran ist.
    _setz(
      zweites: SipgateGespraech(
        nummer: nummer,
        name: bezeichnung,
        eingehend: false,
        stand: SipgateGespraechStand.waehlt,
      ),
    );
    _setzBein('A', (g) => g.kopie(gehalten: true));
    _log.info('sipgate: *3$nummer# geschickt — zweiter Teilnehmer über die '
        'Anlage angewählt', tag: 'SIPGATE');
    if (bezeichnung == null || bezeichnung.isEmpty) {
      unawaited(_namenNachreichen('B', nummer));
    }
    return null;
  }

  /// Schickt mehrere Steuercodes hintereinander, mit Luft dazwischen.
  ///
  /// ⚠️ MIT PAUSEN, und die sind nicht kosmetisch. Eine Anlage erkennt eine
  /// Ziffernfolge über die Lücken zwischen den Tönen; kommt alles in einem
  /// Block, verschmelzen Wiederholungen („077" wird zu „07") oder die Folge
  /// wird gar nicht erst als Wahl erkannt. Deshalb Ziffer für Ziffer.
  Future<bool> _steuerfolge(Call ruf, List<String> teile) async {
    for (final teil in teile) {
      for (final zeichen in teil.split('')) {
        // Was keine Taste ist, gehört nicht auf die Leitung: ein „+" oder ein
        // Leerzeichen aus einer Rufnummer würde die Folge zerreissen.
        if (!'0123456789*#'.contains(zeichen)) continue;
        if (!_steuercode(ruf, zeichen)) return false;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    return true;
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
    _laufendesGespraechMelden();
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
    if (zustand.value.zweites == null) {
      return 'Erst die zweite Nummer dazuwählen — dann zusammenschalten.';
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
    /// ⚠️ Ohne diese Flagge kann [absendernummer] nie wieder auf „unterdrueckt"
    /// zurueck: `_setz` fuehrt fehlende Werte mit `?? alt` fort, also haelt ein
    /// `null` den alten Wert fest. Wer die Nummer im sipgate-Konto auf
    /// unterdrueckt stellt, saehe hier weiter die alte Nummer — wieder als
    /// Tatsache ausgeschrieben, wieder ueber die Aussenwirkung jedes Anrufs.
    bool loescheAbsendernummer = false,
    bool? absendernummerBekannt,
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
      absendernummer:
          loescheAbsendernummer ? null : (absendernummer ?? alt.absendernummer),
      absendernummerBekannt: absendernummerBekannt ?? alt.absendernummerBekannt,
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
          _anrufProtokoll(anrufId: _protokollId(seite), status: 'verbunden');
        }
        _laufendesGespraechMelden();
        _gueteStarten();
        break;

      case CallStateEnum.FAILED:
      case CallStateEnum.ENDED:
        _klingelnBeenden();
        // ⚠️ NUR WENN DAS LETZTE BEIN GEHT. Legt in einer Konferenz einer der
        // beiden auf, läuft das andere Gespräch weiter — die Messung dort
        // mitzubeenden wäre derselbe Fehler, vor dem die Zeilen weiter unten
        // beim Abräumen warnen, nur stiller: der Bildschirm zeigte für den
        // Rest des Gesprächs „wird gemessen …", und im Protokoll stünde nichts.
        //
        // ⚠️ Und die Bilanz gehört zur VERBINDUNG, nicht zum Bein. Bleibt eines
        // übrig, wird frisch begonnen statt weitergezählt — sonst trüge das
        // verbleibende Gespräch die Aussetzer eines anderen, und zwar
        // unauffällig.
        final letztesBein = (seite == 'A' ? _rufB : _rufA) == null;
        final gueteKarte = letztesBein ? gueteBilanz.alsKarte() : null;
        _gueteTakt?.cancel();
        _gueteTakt = null;
        if (letztesBein) {
          _gueteStoppen();
        } else {
          _gueteStarten();
        }
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
          guete: gueteKarte,
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
        if (seite == 'A') {
          gegenstelleSpurId = null;
          // ⚠️ Und damit ist der Text weg. Gespeichert wird nichts.
          unawaited(UntertitelService().beenden());
        }

        // Bleibt genau ein Bein übrig, ist es das aktive und keine Konferenz
        // mehr. Bleibt keines, hört die Uhr auf.
        final restA = zustand.value.gespraech;
        final restB = zustand.value.zweites;
        if (restA == null && restB == null) {
          _aktiv = 'A';
        } else {
          _aktiv = restA != null ? 'A' : 'B';
          if (zustand.value.konferenz) _setz(konferenz: false);
          // Wer allein übrig bleibt, wird nicht gehalten — sonst stünde die
          // Anzeige auf „in der Warteschleife", während man miteinander redet.
          _setzBein(_aktiv, (g) => g.kopie(gehalten: false));
        }
        _laufendesGespraechMelden();
        break;

      // ⚠️ NUR die Gegenseite. Halten wir selbst, geht das über den
      // Steuercode `*3` an die sipgate-Anlage und [halten] hat das Feld schon
      // gesetzt — hier käme dieselbe Aussage ein zweites Mal an und würde die
      // beiden Richtungen vermischen.
      case CallStateEnum.HOLD:
      case CallStateEnum.UNHOLD:
        if (state.originator == Originator.remote) {
          final gehalten = state.state == CallStateEnum.HOLD;
          _setzBein(seite, (g) => g.kopie(vonGegenseiteGehalten: gehalten));
          _log.info(
              'sipgate: Gegenseite hat Bein $seite '
              '${gehalten ? 'in die Warteschleife gestellt' : 'zurückgeholt'}',
              tag: 'SIPGATE');
          _laufendesGespraechMelden();
        }
        break;

      // Die Tonspur der Gegenstelle merken — mehr passiert hier nicht. Ob
      // mitgeschrieben wird, entscheidet der Vorsitzende im Bildschirm.
      case CallStateEnum.STREAM:
        if (state.originator == Originator.remote && seite == 'A') {
          final spuren = state.stream?.getAudioTracks() ?? const [];
          if (spuren.isNotEmpty) {
            gegenstelleSpurId = spuren.first.id;
            _log.info('sipgate: Tonspur der Gegenstelle steht', tag: 'SIPGATE');
            // ⚠️ HIER und nicht bei `CONFIRMED`: vorher gibt es die Spur noch
            // nicht, und ohne sie meldet die native Seite nur „Tonspur der
            // Gegenstelle nicht gefunden".
            //
            // ⚠️ Und bei JEDEM solchen Ereignis, nicht nur beim ersten: eine
            // Neuverhandlung ersetzt die Spur, und eine laufende Mitschrift
            // hinge danach an einer, die niemand mehr füttert — sie würde
            // einfach still, ohne Fehler und ohne Hinweis.
            unawaited(_mitschriftAufNeueSpur());
          }
        }
        break;

      case CallStateEnum.MUTED:
      case CallStateEnum.UNMUTED:
      case CallStateEnum.CONNECTING:
      case CallStateEnum.REFER:
      case CallStateEnum.NONE:
        break;
    }
  }

  /// Lässt die Dauer im Bildschirm weiterlaufen — für BEIDE Beine.

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
  /// wurde in diesem Projekt nie abgefragt — die App zielt auf `targetSdk = 37`
  /// (`android/app/build.gradle.kts`), also zeigt Android den Dialog nicht von
  /// selbst; das tat es nur bei Apps unter Ziel-33. Ohne die Freigabe
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
        vonGegenseiteGehalten: g.vonGegenseiteGehalten,
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

  /// Zeigt oder entfernt die Dauerbenachrichtigung fürs laufende Gespräch.
  ///
  /// ⚠️ WOFÜR — DIE SCHWEBENDE KARTE HÖRT AN DER APP AUF.
  /// [SipgateAnrufOverlay] hängt im Navigator-Overlay: wer während des
  /// Gesprächs in einen Browser wechselt oder den Bildschirm sperrt, hat weder
  /// Dauer noch Auflegen-Knopf mehr vor sich. Auf Android ist die
  /// Dauerbenachrichtigung mit `category: call` die eingeführte Form dafür.
  ///
  /// ⚠️ Nur bei **verbunden**. Beim Klingeln steht schon die Anruf-
  /// Benachrichtigung mit Annehmen/Ablehnen da; zwei Einträge nebeneinander,
  /// von denen einer „Auflegen" anbietet, bevor überhaupt jemand dran ist,
  /// wären eine Falle. Beim Wählen ebenso: da ist noch nichts zu beenden
  /// ausser dem eigenen Versuch, und dafür steht die Karte auf dem Schirm.
  ///
  /// Wirft nie: eine Benachrichtigung darf kein Gespräch stören.
  void _laufendesGespraechMelden() {
    if (!PlatformService.isAndroid) return;
    final z = zustand.value;
    final beine = z.beine
        .where((g) => g.stand == SipgateGespraechStand.verbunden)
        .toList();

    if (beine.isEmpty) {
      unawaited(NotificationService().cancelOngoingCall().catchError((Object e) =>
          _log.warning('sipgate: Gesprächsmeldung nicht entfernt ($e)',
              tag: 'SIPGATE')));
      return;
    }

    final wer = beine.map((g) => g.anzeige).join(' + ');
    // Was gerade gilt, in der Reihenfolge, in der es den Nutzer betrifft: dass
    // die Gegenseite uns parkt, erklärt die Stille — das gehört zuerst hin.
    final zustandstext = z.konferenz
        ? 'Konferenz läuft'
        : beine.any((g) => g.vonGegenseiteGehalten)
            ? 'In der Warteschleife der Gegenseite'
            : beine.any((g) => g.gehalten)
                ? 'Gespräch gehalten'
                : 'Gespräch läuft';

    unawaited(NotificationService()
        .showOngoingCall(wer: wer, zustand: zustandstext)
        .catchError((Object e) => _log.warning(
            'sipgate: Gesprächsmeldung fehlgeschlagen ($e)', tag: 'SIPGATE')));
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
    // ⚠️ Auch die Benachrichtigung, nicht nur der Ton. Bis zum 30.08.2026 stand
    // hier nur `stop()`, und „<Name> ruft an..." blieb danach in der Leiste
    // stehen — während des Gesprächs und lange danach, bis jemand sie
    // wegwischte. Beim nächsten Anruf wurde derselbe Eintrag nur überschrieben,
    // also fiel nie auf, dass ihn niemand zurücknimmt.
    //
    // Diese Methode läuft an allen drei richtigen Stellen: beim Annehmen, beim
    // Ablehnen und wenn das Gespräch endet.
    unawaited(NotificationService().cancelIncomingCall().catchError((Object e) =>
        _log.warning('sipgate: Anruf-Benachrichtigung nicht zurückgenommen ($e)',
            tag: 'SIPGATE')));
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

  /// Die Nummer für die schwebende Gesprächskarte — grösstenteils verdeckt.
  ///
  /// 🔴 WOZU. Die Karte schwebt über allem, was der Vorsitzende gerade tut,
  /// und sie ist von einem Meter Abstand zu lesen. Wer im Wartezimmer, im Amt
  /// oder im Bus daneben steht, hat sonst die vollständige Rufnummer des
  /// Anrufers — eines Mitglieds, eines Arztes, einer Behörde. Im Vollbild
  /// steht sie weiterhin ganz da: dorthin geht man absichtlich.
  ///
  /// Es bleiben die ersten zwei und die letzten drei Ziffern: genug, um einen
  /// bekannten Anrufer wiederzuerkennen, zu wenig, um ihn anzurufen.
  ///
  /// ⚠️ KURZE NUMMERN BLEIBEN GANZ STEHEN. `110`, `112`, `116117`, `115` —
  /// verdeckt ergäben sie Unsinn, sie sind niemandes Privatsache, und
  /// ausgerechnet dort muss man sofort sehen, worum es geht.
  ///
  /// ⚠️ Gezählt werden ZIFFERN, nicht Zeichen: sonst verbrauchte ein `+49 `
  /// die sichtbaren Stellen und man sähe von der eigentlichen Nummer nichts.
  static String anruferVerdeckt(String? roh) {
    final r = (roh ?? '').trim();
    if (_anonym.contains(r.toLowerCase())) return 'Unbekannter Anrufer';
    final ziffern = r.replaceAll(RegExp(r'\D'), '');
    // Unter neun Ziffern lohnt das Verdecken nicht: es blieben zu wenige
    // übrig, um überhaupt etwas zu erkennen — und Kurznummern sind dabei.
    if (ziffern.length < 9) return anruferAnzeige(r);
    final plus = r.startsWith('+') ? '+' : '';
    final vorne = ziffern.substring(0, 2);
    final hinten = ziffern.substring(ziffern.length - 3);
    // Ein Punkt je verdeckter Ziffer: so bleibt die Länge sichtbar, und zwei
    // verschiedene Anrufer sehen nicht gleich aus.
    final mitte = '·' * (ziffern.length - 5);
    return '$plus$vorne$mitte$hinten';
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
  /// Die Kennung der Tonspur, die die Verbindung GERADE führt.
  ///
  /// 🔴 WARUM NICHT [gegenstelleSpurId] ALLEIN. Jene wird bei
  /// `CallStateEnum.STREAM` gesetzt — aber ein Gespräch bekommt mehr als ein
  /// solches Ereignis: im Protokoll vom 30.08.2026 stehen zwei davon binnen
  /// 37 Sekunden im selben Anruf (21:08:07 und 21:08:44). Das ist eine
  /// Neuverhandlung (re-INVITE, etwa nach Halten), und dabei bekommt die
  /// Gegenstelle eine NEUE Spur mit neuer Kennung.
  ///
  /// Die gespeicherte Kennung zeigt dann ins Leere. Auf der nativen Seite
  /// sucht `getRemoteTrack()` sowohl in den registrierten Spuren als auch in
  /// den Transceivern — findet aber nichts, weil die alte Kennung nirgends
  /// mehr vorkommt. Auf dem Schirm steht „Tonspur der Gegenstelle nicht
  /// gefunden", und es sieht aus, als sei die Mitschrift kaputt.
  ///
  /// ⚠️ Deshalb wird gefragt, nicht erinnert: `getReceivers()` liefert, was die
  /// Verbindung in diesem Augenblick empfängt. Die gespeicherte Kennung bleibt
  /// als Rückfall — sie ist richtig, solange nicht neu verhandelt wurde.
  Future<String?> gegenstelleSpurAktuell() async {
    try {
      final pc = _aktiverRuf?.peerConnection;
      if (pc == null) return gegenstelleSpurId;
      for (final e in await pc.getReceivers()) {
        final t = e.track;
        if (t != null && t.kind == 'audio' && (t.id ?? '').isNotEmpty) {
          return t.id;
        }
      }
    } catch (e) {
      _log.warning('sipgate: Tonspur nicht abfragbar ($e)', tag: 'SIPGATE');
    }
    return gegenstelleSpurId;
  }

  /// Schaltet die Mitschrift von selbst ein, sobald die Tonspur steht.
  ///
  /// Wer schlecht hört, soll nicht erst einen Knopf suchen, während die
  /// Gegenstelle schon redet — die ersten Sätze eines Anrufs sind meistens die,
  /// die sagen, worum es geht.
  ///
  /// ⚠️ NUR WENN DAS MODELL SCHON DA IST. Sonst hiesse „von selbst", dass ein
  /// angenommener Anruf 46 MB über die Mobilfunkleitung zieht, ohne dass jemand
  /// das wollte. Fehlt es, bleibt der Knopf im Bildschirm — dort wird das Holen
  /// angeboten und erklärt.
  ///
  /// ⚠️ NICHT in der Konferenz: die Mitschrift hängt an der Spur von Bein A,
  /// bei zwei Gesprächspartnern läse man den einen und hielte es für beide.
  ///
  /// ⚠️ KEIN gespeicherter Schalter. Wer sie für EIN Gespräch nicht will,
  /// schaltet sie im Bildschirm ab; beim nächsten Anruf ist sie wieder da. Ein
  /// gemerktes „aus" wäre die schlechtere Falle: man schaltet einmal ab, und
  /// Monate später fehlt die Mitschrift, ohne dass noch jemand weiss, warum.
  /// Nach einer Neuverhandlung die laufende Mitschrift auf die neue Spur
  /// setzen — und sonst die Automatik anstossen.
  Future<void> _mitschriftAufNeueSpur() async {
    final u = UntertitelService();
    if (!u.aktiv.value) return _mitschriftVonSelbst();
    final id = await gegenstelleSpurAktuell();
    if (id == null || id.isEmpty) return;
    // ⚠️ Neu anhängen heisst hier: erst lösen, dann binden. Der Sink hängt
    // nativ an der ALTEN Spur; ohne das Lösen liefe er weiter ins Leere und
    // hielte nebenbei eine Spur fest, die niemand mehr braucht.
    await u.beenden();
    final grund = await u.starten(
        id, sprache: await _mitschriftSprache(zustand.value.gespraech?.nummer ?? ''));
    if (grund != null) {
      _log.warning('sipgate: Mitschrift nach Neuverhandlung nicht wieder '
          'gestartet ($grund)', tag: 'SIPGATE');
    } else {
      _log.info('sipgate: Mitschrift auf die neue Tonspur gesetzt',
          tag: 'SIPGATE');
    }
  }

  /// Fragt den Server, welche Sprache an diesem Anschluss zu erwarten ist.
  ///
  /// ⚠️ Ein VORSCHLAG, kein Befund: er kommt aus `users.preferred_language`,
  /// also aus der Sprache der ANWENDUNG des Mitglieds. Ein Mitglied mit
  /// rumänischer Oberfläche kann am Telefon Deutsch sprechen. Deshalb schlägt
  /// eine einmal von Hand getroffene Wahl diesen Vorschlag dauerhaft.
  Future<String?> _spracheNachschlagen(String nummer) async {
    try {
      final a = await ApiService().sipgateAction(
          {'action': 'anrufer', 'nummer': nummer});
      if (a['success'] != true) return null;
      return a['sprache'] as String?;
    } catch (e) {
      _log.warning('sipgate: Sprache nicht nachschlagbar ($e)', tag: 'SIPGATE');
      return null;
    }
  }

  /// Welche Sprache die Mitschrift dieses Gesprächs benutzt.
  Future<String> _mitschriftSprache(String nummer) async {
    if (nummer.isEmpty || anruferAnonym(nummer)) return kMitschriftStandard;
    final gemerkt = await MitschriftSprachwahl.gemerkt(nummer);
    // ⚠️ Nur fragen, wenn nichts gemerkt ist. Sonst kostete jedes Gespräch
    // eine Anfrage für eine Antwort, die ohnehin überstimmt wird.
    final vorschlag =
        gemerkt == null ? await _spracheNachschlagen(nummer) : null;
    return mitschriftSpracheWaehlen(gemerkt: gemerkt, vorschlag: vorschlag);
  }

  /// Stellt die Mitschrift des laufenden Gesprächs auf eine andere Sprache um.
  ///
  /// Die Wahl gilt ab sofort UND beim nächsten Anruf an dieselbe Nummer.
  /// Gibt den Grund zurück, wenn es nicht ging — `null` heisst: läuft.
  Future<String?> mitschriftSpracheWechseln(String sprache) async {
    final spr = mitschriftSprache(sprache);
    if (spr == null) return 'Für diese Sprache gibt es kein Modell.';
    final g = zustand.value.gespraech;
    if (g == null) return 'Es läuft kein Gespräch.';
    await MitschriftSprachwahl.merken(g.nummer, spr);
    final u = UntertitelService();
    final id = await gegenstelleSpurAktuell();
    if (id == null || id.isEmpty) {
      return 'Die Tonspur der Gegenstelle steht noch nicht.';
    }
    // ⚠️ Erst lösen, dann binden — wie bei der Neuverhandlung. Ein zweites
    // `starten` auf einer laufenden Mitschrift kehrt sofort zurück und die
    // Sprache bliebe die alte, ohne dass etwas fehlschlägt.
    await u.beenden();
    return u.starten(id, sprache: spr);
  }

  Future<void> _mitschriftVonSelbst() async {
    final u = UntertitelService();
    if (!u.plattformFaehig || u.aktiv.value) return;
    if (zustand.value.konferenz) return;
    final id = await gegenstelleSpurAktuell();
    if (id == null || id.isEmpty) return;
    try {
      final spr = await _mitschriftSprache(zustand.value.gespraech?.nummer ?? '');
      // 🔴 DIE SPERRE GILT NUR FÜR DEUTSCH, und das war vorher falsch.
      // Gerechnet wird zuerst auf dem SERVER; das Modell im Gerät ist nur der
      // Rückfall. Vorher hing der Selbststart trotzdem an ihm — auf einem
      // Tablet, das die 45 MB nie geholt hat, sprang die Mitschrift also nie
      // von selbst an, obwohl der Server sie gekonnt hätte. Für Englisch und
      // Rumänisch gibt es im Gerät ohnehin kein Modell.
      if (spr == 'de' && !await UntertitelModell().vorhanden()) {
        _log.info('sipgate: Mitschrift ohne Gerätemodell — nur über den Server',
            tag: 'SIPGATE');
      }
      final grund = await u.starten(id, sprache: spr);
      if (grund != null) {
        // ⚠️ Nur ins Protokoll. Von selbst gestartet heisst: der Vorsitzende
        // hat nicht danach gefragt — ihm dafür eine Fehlermeldung über den
        // Bildschirm zu legen, während er gerade abhebt, wäre schlimmer als
        // keine Mitschrift.
        _log.warning('sipgate: Mitschrift startete nicht von selbst ($grund)',
            tag: 'SIPGATE');
      }
    } catch (e) {
      _log.warning('sipgate: Mitschrift von selbst fehlgeschlagen ($e)',
          tag: 'SIPGATE');
    }
  }

  /// Beginnt die Güte-Messung des laufenden Gesprächs.
  ///
  /// ⚠️ Der erste Takt liefert nichts, und das ist richtig so: alle Zähler
  /// sind kumulativ, es braucht also zwei Abfragen, bevor ein Wert entsteht.
  /// Siehe [QualitaetsSonde].
  void _gueteStarten() {
    if (_gueteTakt != null) return;
    _sonde.zuruecksetzen();
    gueteBilanz.leeren();
    guete.value = null;
    _gueteGemeldet = false;
    _gueteTakt = Timer.periodic(kQualitaetTakt, (_) => _gueteAbfragen());
    _gueteAbfragen();
  }

  void _gueteStoppen() {
    _gueteTakt?.cancel();
    _gueteTakt = null;
    guete.value = null;
  }

  Future<void> _gueteAbfragen() async {
    final pc = _aktiverRuf?.peerConnection;
    if (pc == null) return;
    try {
      final probe = _sonde.auswerten(await pc.getStats());
      if (probe == null) return;
      gueteBilanz.hinzu(probe);
      guete.value = probe;
    } catch (e) {
      // ⚠️ Einmal melden, dann still weiterlaufen — und den Takt NICHT
      // abbrechen. Die Güte ist Beiwerk; ein Gespräch darf nie daran
      // scheitern, dass eine Kennzahl nicht zu holen war.
      if (!_gueteGemeldet) {
        _gueteGemeldet = true;
        _log.warning('sipgate: Güte nicht messbar ($e)', tag: 'SIPGATE');
      }
    }
  }

  Future<int?> _anrufProtokoll({
    int? anrufId,
    String? richtung,
    String? nummer,
    String? bezeichnung,
    required String status,
    int? dauerS,
    String? fehler,
    Map<String, dynamic>? guete,
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
        if (guete != null) 'guete': guete,
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

  /// ⚠️ EIN re-INVITE MUSS BEANTWORTET WERDEN — SONST BEANTWORTET IHN NIEMAND.
  ///
  /// Diese Methode war leer, und das ist nicht dasselbe wie „ignorieren".
  /// Nachgesehen in `sip_ua-1.1.0/lib/src/rtc_session.dart:2041`:
  /// `emit(EventReInvite(… callback: acceptReInvite …))` ist die **letzte
  /// Anweisung** von `_receiveReinvite`, danach kommt die schliessende
  /// Klammer. Es gibt keinen Rueckfall. Der Gegensatz steht dreissig Zeilen
  /// tiefer: `_receiveUpdate` antwortet nach dem `emit` selbst (`sendAnswer`).
  /// Wer `accept` also nicht ruft, laesst eine SIP-Anfrage ohne Endantwort.
  ///
  /// ⚠️ WAS DABEI GEMESSEN WURDE, UND WAS NICHT.
  /// Die naheliegende Sorge waren die Session-Timer (RFC 4028): waere sipgate
  /// der Erneuerer und erneuerte per re-INVITE, liefe unser eigener Timer ab
  /// und `_runSessionTimer()` beendete das Gespraech mit `408 Session Timer
  /// Expired`. Das passiert NICHT — am 30.08.2026 an 336 echten Zeilen
  /// nachgezaehlt: **kein einziges 408**, dafuer 95 Gespraeche ueber 90 s
  /// (`SESSION_EXPIRES`) und das laengste ueber 82 Minuten, alle sauber
  /// beendet. Erneuert wird also per UPDATE, und das beantwortet `sip_ua`
  /// selbst.
  ///
  /// Bleibt der Fall, fuer den es keine Messung gibt, weil er sich nicht aus
  /// dem Verlauf ablesen laesst: **die Gegenseite stellt uns in die
  /// Warteschleife.** Das laeuft ueber `_processInDialogSdpOffer`, also ueber
  /// genau diesen re-INVITE — „bleiben Sie bitte in der Leitung" bei einem Amt.
  /// Ob sipgate das durchreicht, ist unerprobt. Eine unbeantwortete Anfrage ist
  /// aber in keinem Fall richtig, und die Antwort kostet eine Zeile.
  ///
  /// Angenommen wird bedingungslos: `acceptReInvite` schickt die Antwort, die
  /// `_processInDialogSdpOffer` ausgehandelt hat. Unsere Verbindung ist
  /// ohnehin nur Ton — ein Video-Angebot kann darin gar nicht zustande kommen,
  /// es muss also auch nicht abgelehnt werden.
  @override
  void onNewReinvite(ReInvite event) {
    final annehmen = event.accept;
    if (annehmen == null) {
      _log.warning('sipgate: re-INVITE ohne Annahmeweg — unbeantwortet',
          tag: 'SIPGATE');
      return;
    }
    // Nicht abgewartet: `callStateChanged` und die Anzeige duerfen nicht auf
    // einer SDP-Aushandlung stehen. Fehler landen im Protokoll statt im
    // Gespraechsablauf.
    annehmen(const <String, dynamic>{}).then(
      (ok) => _log.info(
          'sipgate: re-INVITE beantwortet (Ton=${event.hasAudio}, '
          'Video=${event.hasVideo}, angenommen=$ok)',
          tag: 'SIPGATE'),
      onError: (Object e) => _log.warning(
          'sipgate: re-INVITE nicht beantwortet: $e', tag: 'SIPGATE'),
    );
  }
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
    this.absendernummerBekannt = true,
  });
  final String sipId;
  final String ha1;
  final String realm;
  final String wssUrl;
  final String? bezeichnung;
  final bool geteilt;

  /// Was der Angerufene sieht. Leer/`null` heisst unterdrueckt — **aber nur,
  /// wenn [absendernummerBekannt] wahr ist.**
  final String? absendernummer;

  /// Ob ueber [absendernummer] ueberhaupt etwas bekannt ist.
  ///
  /// ⚠️ `false` heisst NICHT „unterdrueckt", sondern **wir wissen es nicht**.
  /// Der Unterschied ist kein Feinschliff: `null` wird im Bildschirm als
  /// „Angerufene sehen: unterdrueckt" ausgeschrieben, samt der Warnung, dass
  /// viele Aemter dann nicht abnehmen und nicht zurueckrufen koennen. Das ist
  /// eine Aussage ueber die Aussenwirkung JEDES Anrufs — sie darf nur fallen,
  /// wenn wir sie wirklich vom Server haben.
  ///
  /// Zwei Wege fuehren zu `false`, und beide kamen wirklich vor:
  ///  * aus dem Zwischenspeicher angemeldet, weil der Server beim Start nicht
  ///    erreichbar war (dort lagen bis jetzt nur SIP-ID und HA1)
  ///  * eine Antwort eines aelteren Servers, die den Schluessel gar nicht
  ///    kennt — festgehalten im Test „ein aelterer Server ohne
  ///    absendernummer darf die Anmeldung nicht verhindern"
  final bool absendernummerBekannt;

  /// `gesetzt` | `nicht_gesetzt` | `unbekannt` — nur der Zustand, nicht die
  /// Adresse. Ist er nicht `gesetzt`, waere ein Notruf ueber sipgate falsch
  /// geroutet; die Sperre im Client gilt aber ohnehin immer.
  final String notrufstandort;
}

enum SipgateStand {
  aus,
  verbindet,
  registriert,
  fehler,

  /// Dieses Geraet hat **kein eigenes** VoIP-Telefon — der Server hat eines
  /// angeboten, das schon einem anderen Geraet gehoert (`geteilt`).
  ///
  /// ⚠️ Das ist KEIN Fehler und darf nicht rot erscheinen. Es ist eine
  /// Feststellung: hier wird nicht telefoniert, das macht das Geraet, dem das
  /// Telefon gehoert.
  fremdesTelefon,
}

enum SipgateGespraechStand { waehlt, klingelt, verbunden }

@immutable
class SipgateZustand {
  const SipgateZustand({
    this.stand = SipgateStand.aus,
    this.sipId,
    this.bezeichnung,
    this.absendernummer,
    this.absendernummerBekannt = true,
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

  /// Ob ueber [absendernummer] etwas bekannt ist — siehe
  /// [SipgateKonfig.absendernummerBekannt].
  ///
  /// Ist das `false`, darf die Oberflaeche **nichts behaupten**.
  /// [notrufstandort] macht es seit jeher richtig vor: der kennt `unbekannt`
  /// als eigenen Wert und schreibt ihn auch hin.
  final bool absendernummerBekannt;

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
    this.vonGegenseiteGehalten = false,
  });

  final String nummer;
  final String? name;
  final bool eingehend;
  final SipgateGespraechStand stand;
  final DateTime? verbundenSeit;
  final bool stumm;

  /// In der Warteschleife der sipgate-Anlage (`*3`) — von UNS gesetzt.
  final bool gehalten;

  /// Die GEGENSEITE hat uns in die Warteschleife gestellt.
  ///
  /// ⚠️ Ein eigenes Feld, nicht dasselbe wie [gehalten]. Die beiden bedeuten
  /// Entgegengesetztes: dort warten die anderen auf uns, hier warten wir auf
  /// sie. Zusammengelegt stünde bei „Bitte bleiben Sie in der Leitung" auf dem
  /// Schirm, WIR hätten jemanden geparkt.
  ///
  /// Kam bisher nirgends an: `CallStateEnum.HOLD`/`UNHOLD` standen mit leerem
  /// Rumpf im `switch`. Die plötzliche Stille war damit von einer Störung
  /// nicht zu unterscheiden.
  final bool vonGegenseiteGehalten;

  int get dauerSekunden => verbundenSeit == null
      ? 0
      : DateTime.now().difference(verbundenSeit!).inSeconds;

  SipgateGespraech kopie({
    SipgateGespraechStand? stand,
    DateTime? verbundenSeit,
    bool? stumm,
    bool? gehalten,
    bool? vonGegenseiteGehalten,
  }) =>
      SipgateGespraech(
        nummer: nummer,
        name: name,
        eingehend: eingehend,
        stand: stand ?? this.stand,
        verbundenSeit: verbundenSeit ?? this.verbundenSeit,
        stumm: stumm ?? this.stumm,
        gehalten: gehalten ?? this.gehalten,
        vonGegenseiteGehalten:
            vonGegenseiteGehalten ?? this.vonGegenseiteGehalten,
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

  /// Wie [anzeige], aber für die schwebende Karte: die Nummer verdeckt.
  ///
  /// ⚠️ Ein NAME bleibt stehen. Wer als Kontakt hinterlegt ist, steht ohnehin
  /// nur mit dem Namen da, und den zu verdecken hiesse, die Karte unbrauchbar
  /// zu machen — man wüsste nicht mehr, mit wem man spricht. Verdeckt wird,
  /// was jemand abschreiben und benutzen kann: die Rufnummer.
  String get anzeigeVerdeckt {
    final voll = anzeige;
    final nr = SipgateService.anruferAnzeige(nummer);
    return voll == nr ? SipgateService.anruferVerdeckt(nummer) : voll;
  }
}
