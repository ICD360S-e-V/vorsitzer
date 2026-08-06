import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:icd_netinfo/icd_netinfo.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api_service.dart';
import 'device_key_service.dart';
import 'http_client_factory.dart';
import 'logger_service.dart';
import 'notification_service.dart';
import 'update_service.dart';

final _log = LoggerService();

/// Name des Hintergrundjobs. Wird in `icdHintergrundDispatcher`
/// (termin_sms_gateway_service.dart) wieder erkannt — dort liegt der EINZIGE
/// WorkManager-Dispatcher der App, siehe die Begründung im Kommentar dort.
const String kSpeedtestTask = 'de.icd360sev.vorsitzer.speedtest';
const String _kSpeedtestUniqueName = 'speedtest-messung';

/// 30 Minuten. WorkManager erlaubt frühestens 15; darunter würde Android den
/// Job ohnehin strecken.
const Duration _kTakt = Duration(minutes: 30);

/// Wie lange auf ein GPS-Fix gewartet wird.
///
/// Kurz gehalten: ein Speedtest, der im Keller auf ein Fix wartet, das nie
/// kommt, liefert am Ende gar keinen Messwert. Lieber die zuletzt bekannte
/// Position verwenden und sie als veraltet kennzeichnen.
const Duration _kOrtTimeout = Duration(seconds: 12);

/// Mindestabstand zwischen zwei gleichartigen Meldungen.
///
/// Rund 18 Prozent der Messungen liegen erfahrungsgemäß unter der Untergrenze —
/// ohne Sperre wären das acht bis zehn Meldungen am Tag, und die schaltet man
/// ab. Mit drei Stunden bleiben höchstens acht, realistisch ein bis drei.
const Duration _kMeldeSperre = Duration(hours: 3);

/// Ab wann die Tagesbilanz verschickt werden darf. Früher gerechnet umfasste
/// sie nur einen Bruchteil des Tages und sagte nichts.
const int _kBilanzStunde = 20;

/// Zeitgrenze je Latenzprobe auf leerer Leitung.
const Duration _kLatenzTimeout = Duration(seconds: 5);

/// Zeitgrenze je Sonde unter Last. Kürzer als oben: unter Last sind lange
/// Umlaufzeiten gerade der gesuchte Befund, aber eine Sonde, die zehn Sekunden
/// hängt, blockiert nur die nächste.
const Duration _kLastSondeTimeout = Duration(seconds: 8);

/// Obergrenze der latenzabhängigen Aufwärmphase. Ohne Deckel bliebe bei
/// 300 Mbit/s und 25 MB kein Messfenster mehr übrig.
const int _kAufwaermDeckelMs = 900;

/// Abtastrate des Verlaufsprofils beim Download.
const Duration _kProfilTakt = Duration(milliseconds: 50);

/// Ab so vielen Proben wird die Latenz unter Last überhaupt behauptet.
///
/// Bei zwei Werten wäre ein „Maximum" ein Zufallswert. In einer Beweisreihe
/// ist ein fehlender Wert besser als ein weicher — der Upload trägt hier meist
/// (10 MB gegen einen Mobilfunk-Uplink dauern mehrere Sekunden), der Download
/// nur, wenn die Leitung wirklich langsam ist. Was genau der Fall ist, um den
/// es geht.
const int _kLastMindestproben = 5;

/// Ab wieviel parallelem Fremdverkehr eine Messung als belastet gilt.
///
/// 1 Mbit/s: darunter sind es Hintergrunddienste, die auf einer Leitung, um
/// die gestritten wird, keine Rolle spielen. Darüber wird es ein Argument der
/// Gegenseite, und dann soll es im Datensatz stehen.
const double _kStoerSchwelleMbps = 1.0;

/// Aufschlag von Nutz- auf Leitungsbytes: IP/TCP/TLS-Köpfe, Bestätigungen der
/// Gegenrichtung und die mitlaufende Latenzsonde. Ohne ihn meldete jeder Lauf
/// Nebenverkehr, den es nicht gab. Bei 1500 Byte MTU sind 40 Byte IP+TCP rund
/// 2,7 %, dazu TLS-Rahmen und die Bestätigungen — 8 % sind reichlich bemessen.
const double _kProtokollAufschlag = 1.08;

/// Wieviele nicht eingereichte Messungen zurückgelegt werden.
///
/// 200 ≈ vier Tage ohne Netz. Unbegrenzt zu puffern füllte nach Wochen den
/// Gerätespeicher; bei Überlauf fällt das Älteste heraus.
const int _kOutboxMax = 200;

/// Wieviele Nachzügler ein Lauf mitnimmt. Mehr würde den 30-Minuten-Takt
/// aufhalten und im Hintergrundjob ins Zeitlimit laufen.
const int _kOutboxProLauf = 10;

/// Harte Obergrenze der Upload-Phase. Die Menge wird aus der zuletzt
/// gemessenen Rate bemessen; bricht die Leitung danach ein, laeuft die Phase
/// sonst unbegrenzt weiter (real gemessen: 36,6 s).
const Duration _kUploadDeckel = Duration(seconds: 25);

/// Geschätzte maximale Geschwindigkeit von Business Mobil L (5. Generation).
///
/// Beleg: „Preisliste Mobilfunktarife Telefonieren & Surfen
/// (Geschäftskunden)", telekom.de/agb/downloads/55192.pdf, Stand 01.01.2026,
/// Abschnitt 1 „Business Mobil und Business Card (5. Generation/
/// Vertragsabschluss ab dem 27.01.2025)", Spalte „L und L Vario":
/// „maximale Download-/Upload-Geschwindigkeit 300/50 MBit/s".
///
/// ⚠️ Höchstwert, keine Zusage — im Mobilfunk gibt es keine vertragliche
/// Mindestgeschwindigkeit. Der Wert ist außerdem technologieneutral: für 5G
/// nennt Telekom in keinem Primärdokument eine eigene Zahl.
const double kBusinessMobilLDownloadMax = 300;
const double kBusinessMobilLUploadMax = 50;

/// Groesse der Messdatei auf dem Server
/// (`/home/data/icd360sev/speedtest/rnd_100m.bin`, 100 MB aus /dev/urandom).
///
/// Der Client darf per Range nicht darueber hinaus anfordern: nginx antwortete
/// sonst mit 416 oder lieferte weniger als verlangt, und die Messung waere
/// still zu niedrig. Wird die Datei je vergroessert, muss diese Zahl mit.
const int kSpeedtestQuelleBytes = 100 * 1024 * 1024;

/// Haushaltsdichte der 300-m-Rasterzelle am Standort.
///
/// Bestimmt, welcher Anteil der Höchstgeschwindigkeit nach der
/// BNetzA-Allgemeinverfügung Nr. 35/2026 (Tenor Ziffer I.1, wirksam
/// 20.04.2026) noch als vertragsgemäß gilt. Kontraintuitiv: je dichter
/// besiedelt, desto MEHR wird verlangt.
///
/// Welche Kategorie am eigenen Standort gilt, zeigt die BNetzA-App
/// „Nachweisverfahren Mobilfunk" vor jeder Messung an — aus der App hier
/// heraus ist das nicht ermittelbar.
enum SpeedtestDichte {
  /// ≥ 145 Haushalte je Rasterzelle → 25 % der Höchstgeschwindigkeit.
  hoch(0.25, 'Hohe Haushaltsdichte (≥ 145)', '25 %'),

  /// 45 bis < 145 Haushalte → 15 %.
  mittel(0.15, 'Mittlere Haushaltsdichte (45–144)', '15 %'),

  /// < 45 Haushalte → 10 %.
  gering(0.10, 'Geringe Haushaltsdichte (< 45)', '10 %');

  const SpeedtestDichte(this.anteil, this.bezeichnung, this.prozent);

  final double anteil;
  final String bezeichnung;
  final String prozent;
}

/// Misst Durchsatz, Latenz und Netzzustand — ausschließlich gegen den eigenen
/// Server.
///
/// KEIN FREMDANBIETER IST BETEILIGT. Weder Ookla noch Cloudflare noch
/// fast.com: sonst wüsste ein Dritter alle 30 Minuten, von welcher Leitung aus
/// gemessen wird, mit welcher IP und zu welcher Uhrzeit — eine Bewegungs- und
/// Anwesenheitsspur, die niemanden etwas angeht. Gemessen wird gegen
/// `/api/speedtest/down.php` und `/api/speedtest/sink.php`; die Quelldatei sind
/// 100 MB aus /dev/urandom, die nginx per sendfile ausliefert.
///
/// Nachgemessen am 2026-08-04: der Server liefert über vier Ströme 846 Mbit/s
/// und hat eine 1-Gbit-Anbindung. Er kann also nicht der begrenzende Faktor
/// sein — genau der Einwand, der von der Gegenseite zuerst käme.
class SpeedtestService {
  SpeedtestService._();

  static const String _basis = ApiService.baseUrl;

  static const String _prefGeraetId = 'speedtest_geraet_id';
  static const String _prefSchwelle = 'speedtest_schwelle_mbps';
  static const String _prefDichte = 'speedtest_dichte';
  static const String _prefAuto = 'speedtest_auto_aktiv';
  static const String _prefLetzte = 'speedtest_letzte_messung';
  static const String _prefLetzteLage = 'speedtest_letzte_lage';
  static const String _prefOutbox = 'speedtest_outbox';
  static const String _prefLaufNr = 'speedtest_lauf_nr';
  static const String _prefLetzteUpMbps = 'speedtest_letzte_up_mbps';
  static const String _prefLetzteDownMbps = 'speedtest_letzte_down_mbps';
  static const String _prefVolumenTag = 'speedtest_volumen_tag';
  static const String _prefVolumenMb = 'speedtest_volumen_mb';
  static const String _prefInstallId = 'speedtest_install_id';

  /// Voreinstellung; wird von `plan.php` überschrieben, damit sich die Größen
  /// ohne App-Release nachregeln lassen.
  static SpeedtestPlan _plan = const SpeedtestPlan();

  /// Vom Server gemeldeter Zeitpunkt am Ende des Uploads — der einzige
  /// Zeitstempel im ganzen Lauf, den nicht das Tablet gesetzt hat. Entkräftet
  /// „die Zeitstempel hat das Geraet selbst gesetzt", ohne eine Zeile nginx.
  static double? _serverZeitUpload;

  /// Zeit zwischen dem letzten geschriebenen Byte und dem Ende des Laufs.
  static double _uploadNachlauf = 0;

  /// Fremdverkehr während des Download-Fensters, siehe [_fremdverkehr].
  /// Wurde die Phase nach Zielzeit beendet (gut) oder ging der Byte-Vorrat aus
  /// (dann ist der Wert nur eine Untergrenze)?
  static bool _downloadZeitAbbruch = false;

  /// Upload lief in die harte Zeitgrenze. Kein Messwert, aber auch kein
  /// Netzfehler — die Auswertung muss den Lauf beim Durchsatz auslassen.
  static bool _uploadZeitDeckel = false;

  /// Massenübertragung wegen Tagesbudget oder Roaming ausgelassen.
  static String? _nurLatenzGrund;

  /// Bereits übertragene Bytes je Phase — stehen auch dann, wenn die Phase
  /// mit einer Ausnahme endet. Nur so lässt sich abgerechnetes Volumen buchen,
  /// das die SIM längst gesehen hat.
  static int _teilBytesDown = 0;
  static int _teilBytesUp = 0;

  /// Was die Schnittstelle des Geräts im Messfenster empfangen hat — die
  /// zweite, vom Anwendungscode unabhängige Messung derselben Strecke.
  static double? _downloadSchnittstelleMbps;

  static Map<String, dynamic>? _fremdverkehrDown;

  /// Serverzeit aus dem Antwortkopf des ersten Download-Stroms.
  static double? _serverZeitDownload;

  /// Kennung dieses Laufs, in jedem HTTP-Kopf und damit im nginx-Protokoll.
  static String _messId = '';

  // ── Öffentliche Einstellungen ───────────────────────────────────────────

  /// Stabile Kennung dieses Geräts. Der Server speichert nur ihren SHA-256.
  ///
  /// Bevorzugt die Geräte-ID der Registrierung — die bleibt über
  /// Neuinstallationen hinweg dieselbe, sodass die Messreihe eines Tablets
  /// nicht bei jeder Neuinstallation als neues Gerät auseinanderfällt. Nur
  /// falls die noch nicht geladen ist (früher Hintergrundlauf), wird eine
  /// eigene erzeugt und behalten.
  static Future<String> geraetId() async {
    final registriert = DeviceKeyService().deviceId;
    if (registriert != null && registriert.isNotEmpty) return registriert;

    final p = await SharedPreferences.getInstance();
    var id = p.getString(_prefGeraetId);
    if (id == null || id.isEmpty) {
      final zufall = Random.secure();
      id = List.generate(16, (_) => zufall.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await p.setString(_prefGeraetId, id);
    }
    return id;
  }

  /// Geschätzte maximale Download-Geschwindigkeit des Tarifs in Mbit/s.
  ///
  /// ⚠️ Das ist ein HÖCHSTWERT, keine Zusage. Im Mobilfunk gibt es — anders
  /// als im Festnetz — weder eine vertragliche Mindestgeschwindigkeit noch
  /// eine „normalerweise zur Verfügung stehende". Nachgeschlagen 2026-08-04 in
  /// der „Preisliste Mobilfunktarife Telefonieren & Surfen (Geschäftskunden)",
  /// telekom.de/agb/downloads/55192.pdf, Stand 01.01.2026, Abschnitt 1
  /// (5. Generation ab 27.01.2025), Spalte „L und L Vario":
  /// 300/50 MBit/s, und ausdrücklich „Die maximale Download- und
  /// Upload-Geschwindigkeit entspricht jeweils der maximal geschätzten und der
  /// beworbenen Geschwindigkeit" — es gibt also nur diese eine Zahl.
  static Future<double> maximalGeschwindigkeit() async =>
      (await SharedPreferences.getInstance()).getDouble(_prefSchwelle) ??
          kBusinessMobilLDownloadMax;

  static Future<void> setzeMaximalGeschwindigkeit(double mbps) async =>
      (await SharedPreferences.getInstance()).setDouble(_prefSchwelle, mbps);

  /// Haushaltsdichte am Standort. Entscheidet, welcher Prozentsatz der
  /// Höchstgeschwindigkeit als Untergrenze gilt.
  static Future<SpeedtestDichte> dichte() async {
    final s = (await SharedPreferences.getInstance()).getString(_prefDichte);
    return SpeedtestDichte.values.firstWhere(
      (d) => d.name == s,
      orElse: () => SpeedtestDichte.mittel,
    );
  }

  static Future<void> setzeDichte(SpeedtestDichte d) async =>
      (await SharedPreferences.getInstance()).setString(_prefDichte, d.name);

  /// Der Wert, gegen den tatsächlich ausgewertet wird.
  ///
  /// Gegen die vollen 300 Mbit/s zu messen wäre sinnlos: der Anteil darunter
  /// läge bei nahezu 100 % und sagte nichts. Maßgeblich ist der Prozentsatz
  /// aus der BNetzA-Allgemeinverfügung 35/2026.
  static Future<double> bewertungsschwelle() async {
    final max = await maximalGeschwindigkeit();
    return max * (await dichte()).anteil;
  }

  static Future<bool> autoAktiv() async =>
      (await SharedPreferences.getInstance()).getBool(_prefAuto) ?? false;

  /// Wann lief zuletzt ein Durchlauf — egal ob erfolgreich.
  ///
  /// Gibt es, weil „läuft der Takt überhaupt?" sonst nirgends ablesbar ist:
  /// die Messungen landen verschlüsselt auf dem Server, und ob seit Tagen
  /// nichts mehr ankam, sieht man erst, wenn man das Diagramm aufmacht und
  /// die Lücke bemerkt. Der Schalter allein sagt nichts — WorkManager-Jobs
  /// verschwinden unter Android still (Force Stop, Akku-Optimierung).
  static Future<DateTime?> letzteMessung() async {
    final s = (await SharedPreferences.getInstance()).getString(_prefLetzte);
    return s == null ? null : DateTime.tryParse(s);
  }

  /// Voraussichtlich nächster Durchlauf. Bei WorkManager nur ein Richtwert —
  /// Android streckt den Takt, wenn das Gerät schläft.
  static Future<DateTime?> naechsteMessung() async {
    final letzte = await letzteMessung();
    return letzte?.add(_kTakt);
  }

  static Future<void> _letzteMessungMerken(DateTime wann) async =>
      (await SharedPreferences.getInstance())
          .setString(_prefLetzte, wann.toIso8601String());

  // ── Automatik alle 30 Minuten ───────────────────────────────────────────

  /// Schaltet die automatische Messung ein oder aus.
  ///
  /// Auf Android übernimmt WorkManager, auf dem Desktop ein Timer, solange die
  /// App läuft (sie sitzt ohnehin im Tray).
  static Future<void> setzeAuto(bool an) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefAuto, an);
    if (an) {
      await _jobRegistrieren();
      _vordergrundTimerStarten();
    } else {
      await _jobAbmelden();
      _timer?.cancel();
      _timer = null;
    }
  }

  static Timer? _timer;

  /// Läuft der Job beim System noch?
  ///
  /// Samsung wirft ihn beim „Force Stop", nach manchen Updates und beim Leeren
  /// des App-Speichers raus — dann bliebe der Schalter in der App an, während
  /// seit Wochen nichts mehr gemessen wird und die Messreihe ein stilles Loch
  /// bekommt. Dieselbe Falle wie beim SMS-Gateway.
  static Future<bool> jobLaeuft() async {
    if (!Platform.isAndroid) return _timer?.isActive ?? false;
    try {
      return await Workmanager().isScheduledByUniqueName(_kSpeedtestUniqueName);
    } catch (_) {
      return false;
    }
  }

  /// Meldet den Job neu an, falls er verschwunden ist. Beim App-Start rufen.
  static Future<void> jobNachziehen() async {
    if (!await autoAktiv()) return;
    _vordergrundTimerStarten();
    if (!Platform.isAndroid) return;
    if (await jobLaeuft()) return;
    _log.warning('Speedtest: Job war abgemeldet, wird neu registriert', tag: 'SPEEDTEST');
    await _jobRegistrieren();
  }

  static void _vordergrundTimerStarten() {
    if (Platform.isAndroid) return;   // dort macht WorkManager den Takt
    _timer?.cancel();
    _timer = Timer.periodic(_kTakt, (_) => messen());
  }

  static Future<void> _jobRegistrieren() async {
    if (!Platform.isAndroid) return;
    try {
      await Workmanager().registerPeriodicTask(
        _kSpeedtestUniqueName,
        kSpeedtestTask,
        frequency: _kTakt,
        // Ohne Netz gibt es nichts zu messen — ein Durchlauf ohne Verbindung
        // wäre kein Messwert, sondern nur ein Fehler in der Reihe.
        constraints: Constraints(networkType: NetworkType.connected),
        // keep: ein erneuter App-Start soll den Rhythmus nicht zurücksetzen,
        // sonst verschiebt sich der Takt bei jedem Öffnen.
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 10),
      );
    } catch (e) {
      _log.warning('Speedtest: WorkManager-Registrierung fehlgeschlagen: $e', tag: 'SPEEDTEST');
    }
  }

  static Future<void> _jobAbmelden() async {
    if (!Platform.isAndroid) return;
    try {
      await Workmanager().cancelByUniqueName(_kSpeedtestUniqueName);
    } catch (_) {}
  }

  // ── Messung ─────────────────────────────────────────────────────────────

  /// Führt einen vollständigen Durchlauf aus und reicht ihn beim Server ein.
  ///
  /// Wirft nie: ein fehlgeschlagener Durchlauf ist selbst ein Messwert und
  /// wird als solcher gespeichert. Eine Lücke in der Reihe wäre schlimmer —
  /// gerade der Ausfall ist das, was belegt werden soll.
  /// [imHintergrund] = Aufruf aus dem WorkManager-Isolat. Dort wird ein Lauf
  /// übersprungen, wenn gerade ein anderes Gerät misst; im Vordergrund wartet
  /// die Messung stattdessen kurz, weil jemand davorsitzt und auf ein Ergebnis
  /// wartet.
  static Future<SpeedtestErgebnis> messen({
    void Function(SpeedtestPhase phase, double anteil)? fortschritt,
    bool imHintergrund = false,
  }) async {
    final beginn = DateTime.now();
    final uhr = Stopwatch()..start();
    await _planLaden();

    // Drei Geräte hängen gleichzeitig an demselben Konto und messen alle 30
    // Minuten. Laufen zwei davon zusammen, teilen sie sich die Leitung — am
    // selben WLAN misst dann jedes die Hälfte, und in der Beweisreihe stünde
    // ein Einbruch, den nicht Telekom verursacht hat, sondern wir selbst.
    final id = await geraetId();
    final sperre = await _sperreHolen(id, imHintergrund: imHintergrund);
    if (sperre == _Sperre.abgelehnt) {
      _log.info('Speedtest übersprungen — ein anderes Gerät misst gerade',
          tag: 'SPEEDTEST');
      // Bewusst NICHT einreichen: das war kein Netzfehler, sondern unsere
      // eigene Koordination. Als Fehlmessung gespeichert würde sie die
      // Fehlerquote verfälschen. Der nächste Takt kommt in 30 Minuten.
      return SpeedtestErgebnis.uebersprungen(beginn);
    }

    HttpClient? klient;
    Map<String, dynamic>? netz;
    String? fehler;

    var pingMin = 0.0, pingAvg = 0.0, jitter = 0.0;
    var pingMedian = 0.0, pingMax = 0.0;
    var timeouts = 0, httpFehler = 0, latenzProben = 0;
    var down = 0.0, up = 0.0;
    String? uploadFehler;
    var downBytes = 0, upBytes = 0;
    var downFenster = 0.0, upFenster = 0.0;
    _Lastlatenz lastDown = const _Lastlatenz(null, null, 0);
    _Lastlatenz lastUp = const _Lastlatenz(null, null, 0);
    List<List<num>> downVerlauf = const [];
    _serverZeitUpload = null;
    _uploadNachlauf = 0;
    _fremdverkehrDown = null;
    _serverZeitDownload = null;
    _downloadSchnittstelleMbps = null;
    _uploadZeitDeckel = false;
    _teilBytesDown = 0;
    _teilBytesUp = 0;
    final zufallId = Random.secure();
    _messId = List.generate(12, (_) => zufallId.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    try {
      klient = HttpClientFactory.createPinnedHttpClient();
      // Ohne das bricht dart:io bei den parallelen Strömen auf eine Verbindung
      // zusammen und wir messen den Durchsatz eines einzigen TCP-Stroms — auf
      // Mobilfunk deutlich weniger als die Leitung hergibt.
      klient.maxConnectionsPerHost = _plan.streams + 2;
      klient.idleTimeout = const Duration(seconds: 10);

      final kopf = await _kopfzeilen();

      fortschritt?.call(SpeedtestPhase.latenz, 0);
      final l = await _latenzMessen(klient, kopf, fortschritt);
      pingMin = l.min;
      pingAvg = l.avg;
      jitter = l.jitter;
      pingMedian = l.median;
      pingMax = l.max;
      timeouts = l.timeouts;
      httpFehler = l.httpFehler;
      latenzProben = l.proben;

      // Massenübertragung nur, wenn sie erlaubt und bezahlbar ist. Latenz,
      // Netzlage und Ort werden trotzdem erhoben — eine Lücke in der Reihe
      // wäre teurer als ein Punkt ohne Durchsatzwert.
      _nurLatenzGrund = await _massenSperre(imHintergrund: imHintergrund);
      if (_nurLatenzGrund == null) {
        fortschritt?.call(SpeedtestPhase.download, 0);
        try {
          final d = await _downloadMessen(
              klient, kopf, pingMin, fortschritt, (m) => netz ??= m);
          down = d.mbps;
          downBytes = d.bytes;
          downFenster = d.fensterSekunden;
          downVerlauf = d.verlauf;
          lastDown = d.lastlatenz;
          await _letzteDownloadRateMerken(down);
        } finally {
          // ⚠️ Im `finally`, nicht am Ende des Blocks. Vorher stand die
          // Buchung als LETZTE Anweisung hinter beiden Phasen: warf eine von
          // ihnen, wurde sie übersprungen und das bereits geflossene Volumen
          // zählte nicht gegen den Tagesdeckel. Belegt an einem echten Lauf —
          // 34 MB übertragen, 0 gebucht. Und Verbindungen reissen ausgerechnet
          // auf der schlechten Leitung, also genau dort, wo am meisten gemessen
          // wird. `_teilBytesDown` steht auch nach einem Abbruch.
          await _volumenBuchen(_teilBytesDown, netz);
        }

        fortschritt?.call(SpeedtestPhase.upload, 0);
        try {
          final u = await _uploadMessen(klient, kopf, fortschritt);
          up = u.mbps;
          upBytes = u.bytes;
          upFenster = u.fensterSekunden;
          lastUp = u.lastlatenz;
          await _letzteUploadRateMerken(up);
        } catch (e) {
          // ⚠️ NICHT weiterwerfen. Sonst riss ein gescheiterter Upload den
          // bereits gueltig gemessenen Download mit in den Fehlerfall, und der
          // ganze Lauf stand als Netzausfall in der Reihe — obwohl die
          // Downloadstrecke nachweislich funktioniert hat.
          uploadFehler = e.toString();
          _log.warning('Speedtest: Upload-Phase gescheitert: $e', tag: 'SPEEDTEST');
        } finally {
          await _volumenBuchen(_teilBytesUp, netz);
        }
      } else {
        _log.info('Speedtest: nur Latenz — $_nurLatenzGrund', tag: 'SPEEDTEST');
      }
    } catch (e) {
      fehler = e.toString();
      _log.warning('Speedtest fehlgeschlagen: $e', tag: 'SPEEDTEST');
    } finally {
      klient?.close(force: true);
      // Immer freigeben, auch nach einem Abbruch — sonst blockiert dieses
      // Gerät die anderen beiden bis zum Ablauf der 120 s.
      await _sperreFreigeben(id);
    }

    netz ??= await netzMomentaufnahme();

    // Erst NACH der Messung: ein GPS-Fix kostet Sekunden und würde, davor
    // geholt, in die gemessene Zeit hineinlaufen. Der Ort ändert sich in den
    // paar Sekunden ohnehin nicht.
    final lage = await _standort(imHintergrund: imHintergrund);

    uhr.stop();
    await _letzteMessungMerken(beginn);

    final ergebnis = SpeedtestErgebnis(
      gemessenAm: beginn,
      dauerSekunden: uhr.elapsedMilliseconds / 1000,
      downloadMbps: down,
      uploadMbps: up,
      pingMinMs: pingMin,
      pingAvgMs: pingAvg,
      jitterMs: jitter,
      pingMedianMs: pingMedian,
      pingMaxMs: pingMax,
      anfragenTimeout: timeouts,
      anfragenHttpFehler: httpFehler,
      latenzProben: latenzProben,
      lastlatenzDownMedianMs: lastDown.median,
      lastlatenzDownMaxMs: lastDown.max,
      lastlatenzDownProben: lastDown.proben,
      lastlatenzUpMedianMs: lastUp.median,
      lastlatenzUpMaxMs: lastUp.max,
      lastlatenzUpProben: lastUp.proben,
      downloadVerlauf: downVerlauf,
      uploadNachlaufSekunden: _uploadNachlauf,
      serverZeitDownload: _serverZeitDownload,
      serverZeitUpload: _serverZeitUpload,
      fremdverkehr: _fremdverkehrDown,
      downloadBytes: downBytes,
      uploadBytes: upBytes,
      downloadFensterSekunden: downFenster,
      uploadFensterSekunden: upFenster,
      streams: _plan.streams,
      netz: netz,
      lage: lage,
      fehler: fehler,
      // Beim Auswerten muss erkennbar sein, dass hier möglicherweise ein
      // zweites Gerät mitgezogen hat — sonst steht ein selbstverschuldeter
      // Einbruch als Beleg gegen Telekom in der Reihe.
      alleine: sperre != _Sperre.trotzdem,
      koordiniert: sperre != _Sperre.unkoordiniert,
      nurLatenzGrund: _nurLatenzGrund,
      downloadZeitAbbruch: _downloadZeitAbbruch,
      downloadSchnittstelleMbps: _downloadSchnittstelleMbps,
      uploadFehler: uploadFehler,
      uploadZeitDeckel: _uploadZeitDeckel,
      zielFensterMs: _plan.zielFensterMs,
      mindestFensterMs: _plan.mindestFensterMs,
    );

    await _einreichen(ergebnis);
    await _melden(ergebnis);
    return ergebnis;
  }

  // ── Phasen ──────────────────────────────────────────────────────────────

  /// Latenz auf leerer Leitung.
  ///
  /// Die erste Probe wird VERWORFEN, nicht gemessen. `messen()` baut für jeden
  /// Lauf einen frischen HttpClient mit eigenem SecurityContext; dart:io teilt
  /// weder Verbindungspool noch TLS-Sitzungen über Instanzen. Die erste Anfrage
  /// trägt damit TCP-SYN plus vollen Handshake gegen das gepinnte Zertifikat —
  /// bei 40 ms Umlaufzeit rund 170 ms. Ungefiltert hob das den Mittelwert um
  /// gut 10 ms und bestand der ausgewiesene „Jitter" überwiegend aus dem
  /// Handshake. Nebeneffekt: die Verwerfungsprobe wärmt den Pool für den
  /// Download.
  ///
  /// Bewusst sequenziell: eine feste Taktung würde bei `maxConnectionsPerHost`
  /// mehrere Handshakes gleichzeitig erzeugen und danach den eigenen Rückstau
  /// messen statt der Leitung.
  static Future<_Latenz> _latenzMessen(
    HttpClient klient,
    Map<String, String> kopf,
    void Function(SpeedtestPhase, double)? fortschritt,
  ) async {
    Future<double?> probe() async {
      final uhr = Stopwatch()..start();
      try {
        final anfrage = await klient.getUrl(Uri.parse('$_basis/speedtest/down.php'));
        kopf.forEach(anfrage.headers.set);
        // Ein einzelnes Byte: gemessen wird die Umlaufzeit, nicht der Durchsatz.
        anfrage.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        final antwort = await anfrage.close().timeout(_kLatenzTimeout);
        await antwort.drain<void>();
        uhr.stop();
        if (antwort.statusCode >= 400) return -antwort.statusCode.toDouble();
        return uhr.elapsedMicroseconds / 1000;
      } on TimeoutException {
        return null;
      } catch (_) {
        return null;
      }
    }

    // Verwerfungsprobe. Ergebnis wird vollständig ignoriert — auch ein
    // Fehlschlag, sonst trüge die nächste Probe den Handshake.
    await probe();

    final werte = <double>[];
    var timeouts = 0;
    var httpFehler = 0;

    for (var i = 0; i < _plan.latenzProben; i++) {
      final r = await probe();
      if (r == null) {
        timeouts++;
      } else if (r < 0) {
        // Negativ = HTTP-Fehlerstatus. Das ist UNSER Server, nicht die
        // Leitung: bei einer JWT-Rotation liefern sonst alle Proben 401 und in
        // der Beweisreihe stünde eine Zeile mit „100 % Paketverlust".
        httpFehler++;
      } else {
        werte.add(r);
      }
      fortschritt?.call(SpeedtestPhase.latenz, (i + 1) / _plan.latenzProben);
    }

    if (werte.isEmpty) {
      return _Latenz(0, 0, 0, 0, 0, timeouts, httpFehler, _plan.latenzProben);
    }

    final avg = werte.reduce((a, b) => a + b) / werte.length;
    // Mittlere absolute Abweichung, nicht Standardabweichung: sie beschreibt
    // das, was beim Telefonieren und in Videokonferenzen tatsächlich stört.
    final jitter = werte.map((w) => (w - avg).abs()).reduce((a, b) => a + b) / werte.length;

    final sortiert = [...werte]..sort();

    return _Latenz(
      werte.reduce(min),
      avg,
      jitter,
      sortiert[sortiert.length ~/ 2],
      // Das Maximum gehört mit: die mittlere Abweichung versteckt genau den
      // einen Aussetzer von 800 ms, der ein Gespräch zerreißt.
      werte.reduce(max),
      timeouts,
      httpFehler,
      _plan.latenzProben,
    );
  }

  /// Sonde, die WÄHREND einer Übertragung misst — Latenz unter Last.
  ///
  /// Das ist die Zahl, die den tatsächlichen Schaden zeigt. Auf Mobilfunk sind
  /// 20 ms im Leerlauf und 900 ms unter Last völlig normal; ein reiner
  /// Durchsatzwert erklärt nie, warum Videotelefonie nicht funktioniert. In
  /// der Schlichtung nach § 68 TKG zählt „unter Last unbenutzbar" auch dann,
  /// wenn der Durchsatz die Untergrenze knapp schafft.
  ///
  /// Genau EINE Sonde gleichzeitig, im Rückstoßbetrieb: die nächste Anfrage
  /// erst, wenn die vorige zurück ist. Eine feste Taktung presste bei 900 ms
  /// Umlaufzeit neun Proben in ein Verbindungsbudget von sechs und maße am
  /// Ende die eigene Warteschlange — worauf die Gegenseite nur zeigen müsste.
  ///
  /// ⚠️ Die Sonde braucht DREI Zustände, nicht zwei. Die erste Fassung fragte
  /// `laufend && fenster != null` — beim Start der Sonde ist das Fenster aber
  /// noch gar nicht offen, die Schleifenbedingung also sofort falsch. Ergebnis:
  /// die Sonde lief in keinem einzigen der 38 Produktionsläufe auch nur eine
  /// Runde, sämtliche `lastlatenz_*`-Felder standen dauerhaft auf `null`, und
  /// zwar lautlos. Ausgerechnet die Zahl, die erklärt, warum Videotelefonie
  /// nicht geht, fehlte damit vollständig.
  static Future<_Lastlatenz> _lastSondeStarten(
    HttpClient klient,
    Map<String, String> kopf,
    _SondePhase Function() zustand,
  ) async {
    final werte = <double>[];
    var ersteVerworfen = false;

    while (true) {
      final jetzt = zustand();
      if (jetzt == _SondePhase.fertig) break;
      if (jetzt == _SondePhase.wartet) {
        // Das Fenster ist noch nicht offen. Kurz nachfassen statt abbrechen.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        continue;
      }
      final uhr = Stopwatch()..start();
      try {
        final anfrage = await klient.getUrl(Uri.parse('$_basis/speedtest/down.php'));
        kopf.forEach(anfrage.headers.set);
        anfrage.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        final antwort = await anfrage.close().timeout(_kLastSondeTimeout);
        await antwort.drain<void>();
        uhr.stop();
        if (antwort.statusCode < 400) {
          // Erste Probe je Phase verwerfen: sie trägt einen TLS-Handshake
          // (200–400 ms), der vom gesuchten Effekt nicht zu unterscheiden wäre.
          if (!ersteVerworfen) {
            ersteVerworfen = true;
          } else {
            werte.add(uhr.elapsedMicroseconds / 1000);
          }
        }
      } catch (_) {
        // Ein Aussetzer unter Last ist selbst ein Befund, aber kein Messwert.
      }
    }

    if (werte.isEmpty) return const _Lastlatenz(null, null, 0);
    final sortiert = [...werte]..sort();
    return _Lastlatenz(
      sortiert[sortiert.length ~/ 2],
      werte.reduce(max),
      werte.length,
    );
  }

  /// Aufwärmdauer für ein Messfenster.
  ///
  /// Die feste Vorgabe reicht nicht: vier parallele Ströme teilen sich das
  /// Bandbreiten-Verzögerungs-Produkt, der Slow-Start dauert also mehrere
  /// Umlaufzeiten. Harte Obergrenze, sonst bliebe bei 300 Mbit/s und 25 MB
  /// überhaupt kein Fenster mehr übrig.
  static int _aufwaermMs(double pingMin) {
    final vorschlag = (pingMin * 5).round();
    return vorschlag.clamp(_plan.aufwaermMs, _kAufwaermDeckelMs);
  }

  static Future<_Durchsatz> _downloadMessen(
    HttpClient klient,
    Map<String, String> kopf,
    double pingMin,
    void Function(SpeedtestPhase, double)? fortschritt,
    void Function(Map<String, dynamic>?) netzMerken,
  ) async {
    // Die Quelldatei ist 100 MB gross. Wuerde plan.php mehr verlangen, laegen
    // die Range-Anfragen hinter dem Dateiende: nginx antwortet dann mit 416
    // oder liefert weniger als angefordert, und die Messung waere still zu
    // niedrig. Lieber hier deckeln. Der Wert ist die OBERGRENZE — beendet wird
    // normalerweise nach [SpeedtestPlan.zielFensterMs], siehe dort.
    /*
     * ⚠️ Der Zeitabbruch spart auf einer schnellen Leitung KEIN Byte.
     *
     * Der `break` unten schliesst zwar die Verbindung, aber nginx hat die
     * angeforderte Scheibe zu dem Zeitpunkt längst vollständig in den Socket
     * geschrieben. Im Protokoll steht dann `206 16777216` und nicht `499` —
     * nachgesehen: in vier von acht Läufen exakt viermal die volle Scheibe,
     * also 67,1 MB je Lauf statt der in plan.php angenommenen ~56. Über den
     * Tarif abgerechnet wird, was gesendet wurde, nicht was wir gelesen haben.
     *
     * Deshalb wird die Range aus der ZULETZT gemessenen Rate bemessen, wie
     * beim Upload: soviel, wie das Zielfenster plus eine Aufwärmreserve
     * braucht. Der Deckel aus plan.php bleibt die Obergrenze.
     *
     * Bewusst NICHT in kleine Stücke zerlegt: jede Stückgrenze kostet je Strom
     * eine Umlaufzeit Leerlauf (auf Mobilfunk 40–100 ms), und das drückt den
     * gemessenen Wert genau in die für uns nachteilige Richtung.
     */
    final letzteRate = await _letzteDownloadRate();
    final deckel = min(_plan.downloadBytes, kSpeedtestQuelleBytes);
    final bedarf = letzteRate > 0
        // Zielfenster + Aufwärmphase + 30 % Reserve, damit ein schnellerer Lauf
        // als der letzte nicht vorzeitig trocken läuft.
        ? (letzteRate * 1e6 * (_plan.zielFensterMs + 1500) / 1000 / 8 * 1.3).round()
        : deckel;
    final gesamt = bedarf.clamp(8 * 1024 * 1024, deckel);
    final jeStrom = gesamt ~/ _plan.streams;
    final aufwaermSchwelle = _aufwaermMs(pingMin);
    // Wurde nach Zielzeit abgebrochen (Normalfall) oder ging der Scheibe
    // vorher der Vorrat aus? Im zweiten Fall war die Leitung so schnell, dass
    // selbst der Deckel nicht für das Zielfenster reichte — dann ist der Wert
    // eine UNTERGRENZE und muss als solche gekennzeichnet werden.
    var zeitAbbruch = false;

    var gezaehlt = 0;          // Bytes im Messfenster
    var gesamtBytes = 0;       // Bytes insgesamt, inklusive Aufwärmphase
    Stopwatch? aufwaermUhr;    // startet erst, wenn ALLE Ströme fließen
    Stopwatch? fenster;
    var netzGeholt = false;
    var laufend = true;
    Map<String, dynamic>? zaehlerVor;
    Map<String, dynamic>? zaehlerNach;

    // Erst wenn jeder Strom sein erstes Byte hatte, ist der Aufbau vorbei.
    // Vorher lief die Uhr ab dem Funktionsaufruf — DNS, TCP, TLS gegen das
    // gepinnte Zertifikat und die JWT-Prüfung in down.php lagen damit komplett
    // in der Aufwärmphase, die eigentlich den Slow-Start wegwerfen sollte. Bei
    // 100 ms Umlaufzeit, also gerade bei schlechtem Signal, war sie
    // aufgebraucht, bevor das erste Byte ankam — die Reihe maß die eigene
    // Leitung systematisch zu schlecht, und zwar zu unseren Gunsten.
    final ersteBytes = List<bool>.filled(_plan.streams, false);
    final verlauf = <List<num>>[];
    var aktiveStroeme = 0;

    Future<void> strom(int index) async {
      final von = index * jeStrom;
      final bis = von + jeStrom - 1;
      final anfrage = await klient.getUrl(Uri.parse('$_basis/speedtest/down.php'));
      kopf.forEach(anfrage.headers.set);
      anfrage.headers.set(HttpHeaders.rangeHeader, 'bytes=$von-$bis');
      final antwort = await anfrage.close();
      if (antwort.statusCode >= 400) {
        throw HttpException('Download HTTP ${antwort.statusCode}');
      }
      // down.php sendet diesen Kopf seit jeher — gelesen wurde er nie. Es ist
      // der einzige Zeitstempel im Download, den nicht das Tablet gesetzt hat,
      // und er entkräftet „die Zeitstempel stammen alle vom Gerät selbst",
      // ohne dass eine Zeile nginx angefasst werden müsste.
      _serverZeitDownload ??=
          double.tryParse(antwort.headers.value('x-speedtest-server-time') ?? '');
      aktiveStroeme++;

      await for (final block in antwort) {
        gesamtBytes += block.length;
        _teilBytesDown += block.length;

        if (!ersteBytes[index]) {
          ersteBytes[index] = true;
          if (!ersteBytes.contains(false)) aufwaermUhr = Stopwatch()..start();
        }

        if (fenster == null) {
          if (aufwaermUhr != null &&
              aufwaermUhr!.elapsedMilliseconds >= aufwaermSchwelle) {
            // ⚠️ SYNCHRON lesen, und erst danach die Uhr starten.
            //
            // Vorher stand hier `unawaited(verkehrszaehler().then(…))`. Der
            // Kanalaufruf kehrte irgendwann nach dem Fensterstart zurück, der
            // Anfangsstand gehörte also zu einem anderen Zeitpunkt als das
            // Fenster — und die Differenz enthielt Bytes, die niemand
            // zugeordnet hatte. Ergebnis im Datensatz: `fremd_bytes: 0`, aber
            // `stoerungsfrei: false` mit 28,9 Mbit/s erfundener Störung. Ein
            // Beweismittel, das sich selbst beschuldigt, und ausgerechnet in
            // den schnellen Läufen.
            zaehlerVor = await verkehrszaehler();
            fenster = Stopwatch()..start();
            if (!netzGeholt) {
              netzGeholt = true;
              // Mitten in der Übertragung abfragen, nicht davor oder danach:
              // die Mobilfunkgeneration kann während des Tests umspringen, und
              // dann gehört die zum Durchsatz passende in den Datensatz.
              unawaited(netzMomentaufnahme().then(netzMerken));
            }
          }
        } else {
          gezaehlt += block.length;
        }

        if (fortschritt != null) {
          // Auf Zeit gemessen: der Balken zeigt den Anteil des Fensters, und
          // vor dessen Öffnung den Aufbau. Ein Byte-Anteil stünde bei einer
          // schnellen Leitung nach 3 s bei 12 % und sähe aus wie ein Hänger.
          final f = fenster;
          fortschritt(
            SpeedtestPhase.download,
            f == null
                ? 0.05
                : (f.elapsedMilliseconds / _plan.zielFensterMs).clamp(0.05, 1),
          );
        }

        // Zielzeit erreicht: Strom abbrechen. `break` bricht die Subscription
        // ab, dart:io schließt die Verbindung, nginx protokolliert die Zeile
        // trotzdem — die serverseitige Gegenaufzeichnung bleibt vollständig.
        if (fenster != null && fenster!.elapsedMilliseconds >= _plan.zielFensterMs) {
          zeitAbbruch = true;
          break;
        }
      }
      aktiveStroeme--;
    }

    // Verlaufsprofil: ein Mittelwert kann ein 300-ms-Loch mitten im Transfer
    // prinzipiell nicht enthalten — und genau das ist die Signatur eines
    // Verlusts mit anschließendem Neuversand, also das, was ein Gespräch
    // abreißen lässt. Zeitstempel aus der Stopwatch, weil der Timer während
    // der Blockverarbeitung verrutscht; `aktiveStroeme` mit, sonst wäre der
    // normale Abfall am Ende (drei von vier Scheiben fertig) nicht von einem
    // echten Einbruch zu unterscheiden.
    final profil = Timer.periodic(_kProfilTakt, (_) {
      if (fenster == null) return;
      verlauf.add([fenster!.elapsedMilliseconds, gezaehlt, aktiveStroeme]);
    });

    final sonde = _lastSondeStarten(
        klient,
        kopf,
        () => !laufend
            ? _SondePhase.fertig
            : (fenster == null ? _SondePhase.wartet : _SondePhase.laeuft));

    try {
      await Future.wait(List.generate(_plan.streams, strom));
    } finally {
      // ⚠️ ZUERST die Uhr anhalten, DANN aufräumen. Vorher wurde `sekunden`
      // erst nach `await sonde` und `await verkehrszaehler()` abgelesen, und
      // die Uhr lief die ganze Zeit weiter: eine Kanal-Abfrage und die
      // auslaufende Latenzsonde landeten im NENNER. Am 05.08. protokollierte
      // nginx für denselben Transfer 0,898 s, der Client meldete 1,179 s —
      // 156 statt 233 Mbit/s. Die Reihe maß die eigene Leitung zu schlecht.
      fenster?.stop();
      // Unmittelbar nach dem Anhalten, VOR `await sonde`: sonst deckt die
      // Zählerdifferenz ein längeres Intervall ab als die Uhr, und die
      // Bytes der auslaufenden Latenzsonde erschienen als Fremdverkehr.
      zaehlerNach = await verkehrszaehler();
      laufend = false;
      profil.cancel();
    }
    final last = await sonde;

    final sekunden = (fenster?.elapsedMicroseconds ?? 0) / 1e6;
    _fremdverkehrDown = _fremdverkehr(
        zaehlerVor, zaehlerNach, gezaehlt, sekunden,
        abgebrochen: zeitAbbruch);
    _downloadZeitAbbruch = zeitAbbruch;

    // Zweite, vom Anwendungscode unabhängige Messung derselben Strecke: was
    // die Schnittstelle des Geräts im Fenster tatsächlich empfangen hat.
    //
    // Sie fällt höher aus als der Anwendungswert, und das ist kein Fehler: der
    // Zähler sieht Protokollköpfe und die Bytes, die beim Abbruch noch in
    // Flug waren. Beide nebeneinander zu führen ist ehrlicher, als sich für
    // eine zu entscheiden — der Anwendungswert ist die konservative Untergrenze
    // und bleibt maßgeblich, die Schnittstelle zeigt die Obergrenze.
    _downloadSchnittstelleMbps = _schnittstellenRate(zaehlerVor, zaehlerNach, sekunden);

    if (fenster == null || sekunden <= 0) {
      // Kürzer als die Aufwärmphase. Früher wurde hier auf die Gesamtzeit
      // ausgewichen — die stammt aber aus derselben zu früh gestarteten Uhr
      // und war damit ebenfalls falsch. Lieber ausdrücklich kein Wert: die
      // Anzeige kennzeichnet ein zu kurzes Fenster bereits.
      return _Durchsatz(0, gesamtBytes, 0, const [], last);
    }
    return _Durchsatz(
        gezaehlt * 8 / sekunden / 1e6, gesamtBytes, sekunden, verlauf, last);
  }

  /// Upload — bewusst OHNE Aufwärm-Abzug, und die Uhr endet an der Antwort.
  ///
  /// ⚠️ Die alte Fassung zählte nur Bytes, die nach Ablauf der Aufwärmphase
  /// geschrieben wurden, und stoppte die Uhr am Ende der Schreibschleife.
  /// Beides ist beim Upload falsch, weil `flush()` zurückkehrt, sobald der
  /// KERNEL die Bytes annimmt — nicht, wenn sie auf der Leitung sind. Die
  /// bereits gepufferten Bytes fielen damit aus dem Zähler, ihre Sendezeit
  /// blieb aber im Nenner. Am 05.08.2026 gegengerechnet: nginx las dieselben
  /// vier Ströme in ≤0,802 s (10,49 MB ⇒ rund 105 Mbit/s), der Client meldete
  /// 8,35 Mbit/s — Faktor 12. Im zweiten Fall (39,18 s ⇒ 2,14 Mbit/s) meldete
  /// er 0,79 — Faktor 2,7. Der Fehler war also nicht einmal konstant.
  ///
  /// Jetzt: Fenster von „alle Ströme stehen" bis „alle Antworten da", Zähler
  /// über ALLE gesendeten Bytes. Das nimmt den Slow-Start mit und misst damit
  /// eher zu niedrig als zu hoch — die für uns ungünstige, also unangreifbare
  /// Richtung. Die eigentliche Autorität ist ohnehin die nginx-Zeile, die
  /// submit.php danebenlegt: sie kann nicht vor dem Eintreffen der Bytes enden.
  static Future<_Durchsatz> _uploadMessen(
    HttpClient klient,
    Map<String, String> kopf,
    void Function(SpeedtestPhase, double)? fortschritt,
  ) async {
    // Auf ZEIT messen. Beim Download lässt sich das im Datenstrom abbrechen;
    // beim Upload steht die Content-Length vorher fest, also wird die Menge
    // aus der zuletzt gemessenen Rate gerechnet. Die Rate ist über 30 Minuten
    // stabil genug, und Ausreißer korrigieren sich beim nächsten Takt.
    final letzteRate = await _letzteUploadRate();
    final zielBytes = letzteRate > 0
        ? (letzteRate * 1e6 * _plan.zielFensterMs / 1000 / 8).round()
        : _plan.uploadBytes ~/ 3;
    final gesamt = zielBytes.clamp(2 * 1024 * 1024, _plan.uploadBytes);
    final jeStrom = gesamt ~/ _plan.streams;
    // Einmal erzeugen und wiederverwenden: 2,5 MB Zufall je Strom neu zu
    // würfeln kostet auf einem Tablet mehr Zeit als das Senden selbst und
    // würde direkt als langsamer Upload erscheinen.
    final block = Uint8List(65536);
    final zufall = Random();
    for (var i = 0; i < block.length; i++) {
      block[i] = zufall.nextInt(256);
    }

    var gesendet = 0;          // Bytes insgesamt
    Stopwatch? fenster;
    var laufend = true;

    // Anker ist das Zurückkehren ALLER postUrl(), nicht der erste flush():
    // der kehrt aus dem selbstjustierenden Sendepuffer praktisch sofort zurück
    // und beweist nicht, dass ein Byte die Leitung gesehen hat.
    final verbunden = List<bool>.filled(_plan.streams, false);
    // Ende je Strom = Eintreffen der ANTWORT, nicht Ende der Schreibschleife.
    final enden = List<int>.filled(_plan.streams, 0);
    final schreibEnden = List<int>.filled(_plan.streams, 0);
    final nachlaeufe = List<int>.filled(_plan.streams, 0);

    Future<void> strom(int index) async {
      final anfrage = await klient.postUrl(Uri.parse('$_basis/speedtest/sink.php'));
      kopf.forEach(anfrage.headers.set);
      anfrage.headers.contentType = ContentType('application', 'octet-stream');
      // Content-Length ist Pflicht: ohne sie sendet dart:io chunked, und bei
      // PHP-FPM kommt dann nichts an — nachgemessen, sink.php beantwortet das
      // inzwischen mit HTTP 411 statt still 0 Bytes zu verbuchen.
      anfrage.contentLength = jeStrom;
      verbunden[index] = true;
      // Fenster öffnet, sobald ALLE Ströme stehen — ohne Aufwärm-Abzug, siehe
      // Kopfkommentar.
      if (!verbunden.contains(false)) fenster ??= Stopwatch()..start();

      var rest = jeStrom;
      while (rest > 0) {
        final n = min(block.length, rest);
        anfrage.add(n == block.length ? block : Uint8List.sublistView(block, 0, n));
        // flush() kehrt zurück, wenn der Block an den Socket übergeben ist —
        // näher kommt man aus Dart nicht an „ist auf der Leitung".
        await anfrage.flush();
        rest -= n;
        gesendet += n;
        _teilBytesUp += n;

        if (fortschritt != null) {
          final f = fenster;
          fortschritt(
            SpeedtestPhase.upload,
            f == null
                ? 0.05
                : (f.elapsedMilliseconds / _plan.zielFensterMs).clamp(0.05, 1),
          );
        }
      }
      schreibEnden[index] = fenster?.elapsedMicroseconds ?? 0;

      final antwort = await anfrage.close();
      final text = await antwort.transform(utf8.decoder).join();
      if (antwort.statusCode >= 400) {
        throw HttpException('Upload HTTP ${antwort.statusCode}: $text');
      }
      final j = jsonDecode(text) as Map<String, dynamic>;
      // Kam nicht alles an, war der Strom abgerissen. Der Messwert wäre dann zu
      // gut — weniger Daten in derselben Zeit.
      if (j['vollstaendig'] != true) {
        throw const HttpException('Upload unvollständig beim Server angekommen');
      }
      // Der Server sagt selbst, wann er fertig war — der einzige Zeitstempel
      // im ganzen Lauf, den nicht das Tablet gesetzt hat.
      final st = j['server_time'];
      if (st is num) _serverZeitUpload = st.toDouble();
      // ⚠️ ERST HIER ist bewiesen, dass die Bytes die Leitung verlassen haben.
      // Die Antwort kommt, nachdem nginx den vollständigen Rumpf gelesen hat.
      enden[index] = fenster?.elapsedMicroseconds ?? 0;
      // Schreibschleife fertig, aber Antwort noch aus: die Differenz ist die
      // Zeit, in der die Daten noch in Sende- und Netzpuffern standen. Auf
      // einer gepufferten Mobilfunkstrecke der beste Vorläufer für Bufferbloat.
      nachlaeufe[index] =
          (enden[index] - schreibEnden[index]).clamp(0, 600 * 1000 * 1000).toInt();
    }

    final sonde = _lastSondeStarten(
        klient,
        kopf,
        () => !laufend
            ? _SondePhase.fertig
            : (fenster == null ? _SondePhase.wartet : _SondePhase.laeuft));

    try {
      /*
       * ⚠️ Harte Obergrenze. Die Menge steht wegen der Content-Length vor dem
       * Senden fest und laesst sich waehrend des Laufs nicht mehr korrigieren.
       * Bricht die Leitung nach der Bemessung ein, dauert die Phase
       * entsprechend lange — real gemessen 28,8 und 36,6 s. Ohne Grenze koennte
       * ein Lauf den ganzen Takt auffressen, das Geraet wachhalten und in die
       * naechste Messung hineinlaufen.
       */
      await Future.wait(List.generate(_plan.streams, strom))
          .timeout(_kUploadDeckel);
    } on TimeoutException {
      // Kein Messwert, aber auch kein Netzfehler: ausdruecklich kennzeichnen,
      // damit die Auswertung den Lauf beim Durchsatz auslaesst und nicht als
      // Ausfall zaehlt.
      _uploadZeitDeckel = true;
    } finally {
      fenster?.stop();
      laufend = false;
    }
    final last = await sonde;
    if (_uploadZeitDeckel) return _Durchsatz(0, gesendet, 0, const [], last);

    final fensterEnde = enden.reduce(max);
    final sekunden = fensterEnde / 1e6;
    if (fenster == null || sekunden <= 0) {
      return _Durchsatz(0, gesendet, 0, const [], last);
    }
    _uploadNachlauf = nachlaeufe.reduce(max) / 1e6;
    return _Durchsatz(
        gesendet * 8 / sekunden / 1e6, gesendet, sekunden, const [], last);
  }

  // ── Outbox ──────────────────────────────────────────────────────────────

  /// Wieviele Messungen warten noch darauf, eingereicht zu werden?
  static Future<int> rueckstand() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_prefOutbox) ?? const []).length;
  }

  // ── Datenbudget ─────────────────────────────────────────────────────────

  /// Darf dieser Lauf die Massenübertragung durchführen? `null` heißt ja,
  /// sonst steht hier der Grund, der auch im Datensatz landet.
  ///
  /// Auf Zeit zu messen heißt: je schneller die Leitung, desto mehr Volumen je
  /// Lauf. Ohne Deckel wüchse der Verbrauch also ausgerechnet dann, wenn alles
  /// gut läuft. Zwei harte Sperren:
  ///  - **Roaming.** Der Tarif hat in der EU 91 GB im Monat, nicht unbegrenzt.
  ///    48 Läufe am Tag würden das Kontingent in Tagen aufbrauchen — und im
  ///    Ausland gemessene Werte belegen ohnehin nichts über die deutsche
  ///    Versorgung.
  ///  - **Tagesbudget.** Deckel aus [SpeedtestPlan.tagesvolumenMb], serverseitig
  ///    nachregelbar.
  static Future<String?> _massenSperre({bool imHintergrund = false}) async {
    final netz = await netzMomentaufnahme();
    if (netz != null && netz['roaming'] == true) return 'roaming';

    /*
     * WLAN im Hintergrund: Latenz ja, Massenuebertragung nein.
     *
     * Das Tablet steht am Vereinssitz, wo WLAN anliegt. Ein WLAN-Lauf sagt
     * ueber die Telekom-Leitung nichts aus — er wird in der Auswertung ohnehin
     * ausgeschlossen — kostet aber Zeit und Strom, und bis eben auch das
     * Datenbudget. Im VORDERGRUND bleibt er erlaubt: dort ist er die
     * ausdrueckliche Gegenprobe „nicht das Geraet, nicht der Server, die
     * Leitung", die man an Ort und Stelle machen will.
     *
     * ⚠️ Das ist bewusst KEIN Erzwingen der Mobilfunkstrecke. Dafuer braeuchte
     * es `ConnectivityManager.requestNetwork` mit `TRANSPORT_CELLULAR` und ein
     * an dieses Netz gebundenes Socket. Der einfache Weg dorthin,
     * `bindProcessToNetwork`, wirkt auf den GANZEN Prozess — waehrend der
     * Messung liefen dann Chat, Push und Mail ueber die SIM statt ueber WLAN.
     * Das waere ein zu grosser Nebeneffekt fuer den Gewinn.
     */
    final transport = netz?['transport'];
    if (imHintergrund && transport != null && transport != 'cellular') {
      return 'wlan';
    }

    /*
     * ⚠️ Budget je TAKT, nicht als laufende Tagessumme.
     *
     * Mit einer laufenden Summe schneidet der Deckel immer die spaeten Takte
     * weg — und bevorzugt an den GUTEN Tagen, weil eine schnelle Leitung mehr
     * Volumen je Lauf kostet. Die Stichprobe waere damit systematisch schief:
     * abends fehlten Messungen, und zwar genau dann, wenn tagsueber alles gut
     * lief. Das ist in einer Beweisreihe der Vorwurf, den man am wenigsten
     * gebrauchen kann — die Gegenseite muesste nur auf die Verteilung zeigen.
     *
     * Freigegeben ist deshalb, was bis zum aktuellen Takt anteilig zusteht.
     * Das Tagesmaximum bleibt gedeckelt, ein schneller Vormittag kann den
     * Abend nicht mehr aufessen, und ausgelassene Takte verteilen sich
     * gleichmaessig ueber den Tag.
     */
    final p = await SharedPreferences.getInstance();
    final jetzt = DateTime.now();
    final heute = _tagesschluessel(jetzt);
    if (p.getString(_prefVolumenTag) != heute) return null;
    final verbraucht = p.getDouble(_prefVolumenMb) ?? 0;

    final takteBisher =
        (jetzt.difference(DateTime(jetzt.year, jetzt.month, jetzt.day)).inMinutes /
                _kTakt.inMinutes)
            .floor() + 1;
    final takteProTag = (24 * 60 / _kTakt.inMinutes).round();
    final freigegeben = _plan.tagesvolumenMb * takteBisher / takteProTag;

    return verbraucht >= freigegeben ? 'tagesbudget' : null;
  }

  static Future<void> _volumenBuchen(int bytes, Map<String, dynamic>? netz) async {
    if (bytes <= 0) return;
    /*
     * ⚠️ Nur Mobilfunk zaehlt gegen das Budget.
     *
     * Der Deckel schuetzt das Datenvolumen der Telekom-SIM. Ein Lauf im
     * Vereins-WLAN kostet dort nichts, verbrauchte aber trotzdem das Budget
     * und liess spaeter echte Mobilfunkmessungen ausfallen — ausgerechnet die,
     * um die es geht. Fehlt die Netzangabe, wird gebucht: der unbekannte Fall
     * darf kein Freibrief werden.
     */
    final transport = netz?['transport'];
    if (transport != null && transport != 'cellular') return;

    final p = await SharedPreferences.getInstance();
    final heute = _tagesschluessel(DateTime.now());
    final alt = p.getString(_prefVolumenTag) == heute
        ? (p.getDouble(_prefVolumenMb) ?? 0)
        : 0.0;
    await p.setString(_prefVolumenTag, heute);
    await p.setDouble(_prefVolumenMb, alt + bytes / (1024 * 1024));
  }

  /// Heute verbrauchtes Messvolumen in MB — für die Anzeige.
  static Future<double> tagesvolumenMb() async {
    final p = await SharedPreferences.getInstance();
    if (p.getString(_prefVolumenTag) != _tagesschluessel(DateTime.now())) return 0;
    return p.getDouble(_prefVolumenMb) ?? 0;
  }

  static Future<int> tagesbudgetMb() async {
    await _planLaden();
    return _plan.tagesvolumenMb;
  }

  static String _tagesschluessel(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Zuletzt gemessene Upload-Rate, für die Mengenberechnung des nächsten
  /// Laufs. 0 heißt „noch keine" — dann greift die Vorgabe aus dem Plan.
  /// Zuletzt gemessene Download-Rate. Bemisst die Range des naechsten Laufs,
  /// damit der Zeitabbruch nicht ins Leere greift — siehe [_downloadMessen].
  static Future<double> _letzteDownloadRate() async {
    final p = await SharedPreferences.getInstance();
    return p.getDouble(_prefLetzteDownMbps) ?? 0;
  }

  static Future<void> _letzteDownloadRateMerken(double mbps) async {
    if (mbps <= 0) return;
    final p = await SharedPreferences.getInstance();
    final alt = p.getDouble(_prefLetzteDownMbps) ?? mbps;
    // ⚠️ Nach OBEN geglaettet, nach UNTEN sofort: bricht die Leitung ein, muss
    // die naechste Range sofort kleiner werden (sonst laeuft die Uebertragung
    // minutenlang), erholt sie sich, darf die Menge langsam nachziehen. Ein
    // symmetrischer Mittelwert braeuchte zwei bis drei Laeufe und haette in
    // der Zwischenzeit entweder Volumen verbrannt oder das Fenster verfehlt.
    await p.setDouble(_prefLetzteDownMbps, mbps < alt ? mbps : alt * 0.5 + mbps * 0.5);
  }

  static Future<double> _letzteUploadRate() async {
    final p = await SharedPreferences.getInstance();
    return p.getDouble(_prefLetzteUpMbps) ?? 0;
  }

  static Future<void> _letzteUploadRateMerken(double mbps) async {
    if (mbps <= 0) return;
    final p = await SharedPreferences.getInstance();
    // Geglättet: ein einzelner Ausreißer nach unten würde die nächste Messung
    // auf 2 MB schrumpfen lassen und damit ihr Fenster zerstören — genau der
    // Fehler, den diese Umstellung beseitigen soll.
    final alt = p.getDouble(_prefLetzteUpMbps) ?? mbps;
    // Nach unten sofort, nach oben geglaettet — Begruendung bei
    // [_letzteDownloadRateMerken]. Beim Upload wiegt das schwerer: dort steht
    // die Content-Length vor dem Senden fest, ein zu grosser Wert laesst sich
    // waehrend des Laufs nicht mehr korrigieren. Real gemessen wurden dadurch
    // Upload-Phasen von 28,8 und 36,6 s.
    await p.setDouble(_prefLetzteUpMbps, mbps < alt ? mbps : alt * 0.5 + mbps * 0.5);
  }

  /// Fortlaufende Nummer je Installation.
  ///
  /// ⚠️ Trägt NICHT mehr die Idempotenz. Der Zähler liegt in
  /// SharedPreferences, der `geraet_key` dagegen wird aus der Hardware
  /// abgeleitet und überlebt eine Neuinstallation. Nach einem Neuaufsetzen
  /// beginnt der Zähler wieder bei 1, während der Schlüssel derselbe ist —
  /// jede neue Messung kollidierte dann mit einer alten Zeile und würde vom
  /// Server als Dublette abgewiesen. Die Reihe risse still ab.
  ///
  /// Die Idempotenz hängt jetzt an `mess_id` (24 Hex, je Lauf neu erzeugt und
  /// mit dem Datensatz in der Outbox abgelegt, also auch beim Nachreichen
  /// identisch). Die Nummer bleibt als Lückenanzeiger INNERHALB einer
  /// Installation, zusammen mit [_installId].
  static Future<int> _naechsteLaufNr() async {
    final p = await SharedPreferences.getInstance();
    final n = (p.getInt(_prefLaufNr) ?? 0) + 1;
    await p.setInt(_prefLaufNr, n);
    return n;
  }

  /// Kennung dieser Installation. Ohne sie wäre `lauf_nr` nach einem
  /// Neuaufsetzen nicht mehr von der alten Zählung zu unterscheiden.
  static Future<String> _installId() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString(_prefInstallId);
    if (id == null || id.isEmpty) {
      final r = Random.secure();
      id = List.generate(8, (_) => r.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await p.setString(_prefInstallId, id);
    }
    return id;
  }

  /// Legt eine nicht eingereichte Messung zurück.
  ///
  /// Der bisherige Kommentar begründete das Verwerfen damit, ein fehlender
  /// Punkt ändere nichts an der Aussage. Das stimmt nicht: der Verlust trifft
  /// überproportional die SCHLECHTEN Messungen — ist die Leitung so schwach,
  /// dass das Einreichen scheitert, geht genau der Beleg für die schwache
  /// Leitung verloren. Der wahrscheinlichste Dauerfall ist außerdem gar nicht
  /// die schwache Leitung, sondern ein totes Token; dann scheitert jedes
  /// Einreichen, und ohne Warteschlange fiele die Reihe still komplett aus.
  static Future<void> _inOutbox(Map<String, dynamic> datensatz) async {
    final p = await SharedPreferences.getInstance();
    final liste = [...(p.getStringList(_prefOutbox) ?? const <String>[])];
    liste.add(jsonEncode(datensatz));
    // FIFO: bei Überlauf fällt das Älteste heraus. Ein unbegrenzter Puffer
    // würde nach Wochen ohne Netz den Gerätespeicher füllen.
    while (liste.length > _kOutboxMax) {
      liste.removeAt(0);
    }
    await p.setStringList(_prefOutbox, liste);
  }

  /// Reicht zurückgelegte Messungen nach.
  ///
  /// Läuft NUR nach einer erfolgreichen Einreichung — sonst würde bei totem
  /// Token jeder Takt die ganze Warteschlange erfolglos durchprobieren.
  static Future<void> _outboxLeeren() async {
    final p = await SharedPreferences.getInstance();
    var liste = [...(p.getStringList(_prefOutbox) ?? const <String>[])];
    if (liste.isEmpty) return;

    final geschafft = <String>[];
    for (final roh in liste.take(_kOutboxProLauf)) {
      try {
        final d = Map<String, dynamic>.from(jsonDecode(roh) as Map);
        // Der Server darf seinen eigenen Kontext (IP, Reverse-DNS, Systemlast)
        // bei einem nachgereichten Lauf NICHT als messzeitgleich ablegen —
        // sonst bekäme ein drei Stunden später nachgereichter Datensatz still
        // einen Serverzustand aus einer fremden Stunde als Beleg.
        d['nachgereicht'] = 1;
        final gemessen = DateTime.tryParse((d['gemessen_am'] ?? '') as String);
        if (gemessen != null) {
          d['verzoegerung_s'] = DateTime.now().difference(gemessen).inSeconds;
        }
        final antwort = await ApiService().speedtestEinreichen(d);
        if (antwort['success'] != true) break;
        geschafft.add(roh);
      } catch (_) {
        break;
      }
    }

    if (geschafft.isEmpty) return;
    liste = liste.where((r) => !geschafft.contains(r)).toList();
    await p.setStringList(_prefOutbox, liste);
    _log.info('Speedtest: ${geschafft.length} nachgereicht, ${liste.length} offen',
        tag: 'SPEEDTEST');
  }

  // ── Fremdverkehr ────────────────────────────────────────────────────────

  /// Wieviel Verkehr lief WÄHREND des Messfensters neben der Messung?
  ///
  /// Der Einwand „Ihre 40 Mbit/s sind das, was von 200 übrig blieb" ist ohne
  /// diese Zahlen nicht zu entkräften. Drei Größen statt einer:
  ///  - `fremd_bytes`       andere Apps, System, Tethering
  ///  - `eigen_neben_bytes` DIE EIGENE APP neben der Messung. Ohne dieses Feld
  ///    erschiene ein laufendes Videogespräch als „0 % Fremdverkehr,
  ///    störungsfrei" — ein falscher Freispruch im Beweismaterial.
  ///  - `stoerbytes_mbps`   die Zahl für den Schriftsatz. Bewusst kein Prozent:
  ///    2 % einer langsamen Messung sind belanglos, 2 % einer schnellen viel.
  ///
  /// `null`, wo das Gerät keine Zähler liefert — nie stillschweigend 0.
  static Map<String, dynamic>? _fremdverkehr(
    Map<String, dynamic>? vorher,
    Map<String, dynamic>? nachher,
    int messBytes,
    double fensterSekunden, {
    bool abgebrochen = false,
  }) {
    if (vorher == null || nachher == null) return null;

    int? diff(String feld) {
      final a = vorher[feld], b = nachher[feld];
      if (a is! num || b is! num) return null;
      final d = b.toInt() - a.toInt();
      // Negativ heißt Zählerüberlauf oder Neustart — dann lieber nichts sagen.
      return d < 0 ? null : d;
    }

    final gesamt = _summe(diff('gesamt_rx'), diff('gesamt_tx'));
    final eigen = _summe(diff('eigen_rx'), diff('eigen_tx'));
    if (gesamt == null || eigen == null) return null;

    final fremd = max(0, gesamt - eigen);

    /*
     * ⚠️ Wurde die Übertragung an der Zielzeit ABGEBROCHEN, lässt sich der
     * eigene Nebenverkehr gar nicht bestimmen.
     *
     * Beim `break` bleiben Bytes unterwegs, die der Server schon geschrieben
     * hat und die die Schnittstelle noch zählt, die aber niemand mehr liest.
     * Sie sind von echtem Nebenverkehr nicht zu unterscheiden. Genau daran ist
     * die erste Fassung gescheitert: jeder schnelle Lauf trug den Vermerk
     * „nicht störungsfrei" mit zweistelligen Mbit/s — ein Selbstvorwurf ohne
     * Substanz, den die Gegenseite dankbar aufgegriffen hätte.
     *
     * `fremd_bytes` bleibt gültig: was ANDERE Anwendungen verbraucht haben,
     * ist von unserem Abbruch unberührt. Nur die Aussage über die eigene App
     * entfällt — ausdrücklich, mit Grund, nicht stillschweigend.
     */
    if (abgebrochen) {
      return {
        'fremd_bytes': fremd,
        'eigen_neben_bytes': null,
        'stoerbytes_mbps': null,
        'stoerungsfrei': null,
        'grund': 'zeitabbruch — beim Abbruch noch fliegende Bytes sind von '
            'Nebenverkehr nicht unterscheidbar',
      };
    }
    // ⚠️ `messBytes` sind NUTZbytes, `eigen` sind LEITUNGSbytes: darin stecken
    // IP-, TCP- und TLS-Köpfe, die Bestätigungen der Gegenrichtung und die
    // Latenzsonde, die während des Fensters weiterläuft. Ohne Abschlag war die
    // Differenz deshalb immer positiv, und praktisch jeder Lauf trug den
    // Vermerk „es lief etwas daneben" — ein Selbstvorwurf ohne Substanz, den
    // die Gegenseite dankbar aufgegriffen hätte. Der Aufschlag ist mit 8 %
    // grosszuegig; was darueber liegt, ist echter Nebenverkehr.
    final eigenNeben = max(0, eigen - (messBytes * _kProtokollAufschlag).round());
    final stoer = fensterSekunden > 0
        ? (fremd + eigenNeben) * 8 / fensterSekunden / 1e6
        : null;

    return {
      'fremd_bytes': fremd,
      'eigen_neben_bytes': eigenNeben,
      'stoerbytes_mbps': stoer == null ? null : double.parse(stoer.toStringAsFixed(3)),
      // Nie `true` als Vorgabe: ohne Zähler wird nichts behauptet.
      'stoerungsfrei': stoer == null ? null : stoer < _kStoerSchwelleMbps,
    };
  }

  static int? _summe(int? a, int? b) => (a == null || b == null) ? null : a + b;

  /// Empfangsrate laut Schnittstellenzähler des Geräts.
  ///
  /// Unabhängig vom Anwendungscode und damit die einzige Zahl auf dem Gerät,
  /// die weder von unserer Fensterlogik noch von der Puffergrösse abhängt.
  /// Sie liegt systematisch ÜBER dem Anwendungswert — Protokollköpfe zählen
  /// mit, und beim Abbruch fliegende Bytes ebenfalls. Als Obergrenze zu
  /// führen, nie als Messwert.
  static double? _schnittstellenRate(
    Map<String, dynamic>? vorher,
    Map<String, dynamic>? nachher,
    double sekunden,
  ) {
    if (vorher == null || nachher == null || sekunden <= 0) return null;
    final a = vorher['eigen_rx'], b = nachher['eigen_rx'];
    if (a is! num || b is! num) return null;
    final d = b.toInt() - a.toInt();
    if (d <= 0) return null;
    return double.parse((d * 8 / sekunden / 1e6).toStringAsFixed(2));
  }

  // ── Benachrichtigungen ──────────────────────────────────────────────────

  /// Meldet sich nur, wenn es etwas zu sehen gibt.
  ///
  /// Nicht bei jeder Messung: 48 Meldungen am Tag schaltet man nach einem Tag
  /// ab, und dann sieht man auch die echten Ausreißer nicht mehr. Gemeldet
  /// werden Unterschreitungen und Fehlversuche — beides höchstens alle
  /// [_kMeldeSperre] — sowie einmal am Abend eine Tagesbilanz.
  ///
  /// Wirft nie. Eine Messung darf nicht daran scheitern, dass die
  /// Benachrichtigung nicht durchkommt.
  static Future<void> _melden(SpeedtestErgebnis e) async {
    try {
      // Im WorkManager-Isolat ist der Dienst ein frischer Singleton und noch
      // nicht eingerichtet — dort ginge die Meldung sonst still verloren.
      // initialize() ist idempotent, der Aufruf im Vordergrund kostet nichts.
      await NotificationService().initialize();

      final p = await SharedPreferences.getInstance();
      final jetzt = DateTime.now();

      Future<bool> darf(String schluessel) async {
        final zuletzt = DateTime.tryParse(p.getString(schluessel) ?? '');
        if (zuletzt != null && jetzt.difference(zuletzt) < _kMeldeSperre) return false;
        await p.setString(schluessel, jetzt.toIso8601String());
        return true;
      }

      if (!e.erfolgreich && !e.uebersprungen) {
        if (await darf('speedtest_meldung_fehler')) {
          await NotificationService().show(
            title: 'Speedtest fehlgeschlagen',
            body: e.fehler ?? 'Unbekannter Fehler',
          );
        }
        return;
      }
      if (!e.erfolgreich) return;   // übersprungen: nichts zu melden

      final grenze = await bewertungsschwelle();
      if (grenze > 0 && e.downloadMbps < grenze) {
        if (await darf('speedtest_meldung_unter')) {
          final ort = e.adresse;
          await NotificationService().show(
            title: 'Leitung unter der Untergrenze',
            body: '${e.downloadMbps.toStringAsFixed(1)} statt '
                '${grenze.toStringAsFixed(0)} Mbit/s · ${e.generation}'
                '${ort != null ? ' · $ort' : ''}',
          );
        }
      }

      await _tagesbilanzVielleicht(p, jetzt);
    } catch (err) {
      _log.warning('Speedtest-Meldung fehlgeschlagen: $err', tag: 'SPEEDTEST');
    }
  }

  /// Einmal am Abend eine Bilanz des Tages.
  ///
  /// Erst ab [_kBilanzStunde], damit sie den ganzen Tag abdeckt — eine Bilanz
  /// um 9 Uhr wäre über drei Messungen gerechnet und sagte nichts.
  static Future<void> _tagesbilanzVielleicht(SharedPreferences p, DateTime jetzt) async {
    if (jetzt.hour < _kBilanzStunde) return;
    final heute = '${jetzt.year}-${jetzt.month}-${jetzt.day}';
    if (p.getString('speedtest_bilanz_tag') == heute) return;

    final grenze = await bewertungsschwelle();
    final antwort = await ApiService().speedtestListe(
      range: '1d',
      geraetKey: null,
      schwelle: grenze,
    );
    if (antwort['success'] != true) return;

    final s = (antwort['statistik'] as Map?)?.cast<String, dynamic>() ?? const {};
    final n = (s['n'] as num?)?.toInt() ?? 0;
    if (n == 0) return;

    await p.setString('speedtest_bilanz_tag', heute);

    final schnitt = (s['down_avg'] as num?)?.toDouble();
    final unter = (s['unter_schwelle'] as Map?)?.cast<String, dynamic>();
    final anteil = ((unter?['anteil'] as num?) ?? 0) * 100;
    final fehler = (s['fehler'] as num?)?.toInt() ?? 0;

    await NotificationService().show(
      title: 'Speedtest — Tagesbilanz',
      body: '$n Messungen · Ø ${schnitt?.toStringAsFixed(0) ?? '?'} Mbit/s · '
          '${anteil.toStringAsFixed(0)} % unter ${grenze.toStringAsFixed(0)}'
          '${fehler > 0 ? ' · $fehler fehlgeschlagen' : ''}',
    );
  }

  // ── Standort ────────────────────────────────────────────────────────────

  /// Wo wurde gemessen?
  ///
  /// Gehört zur Beweiskraft: die Schwelle der Bundesnetzagentur hängt an der
  /// Haushaltsdichte der 300-m-Rasterzelle, in der gemessen wurde. Eine
  /// Messreihe ohne Ort kann die Frage „wo genau ist die Leitung schlecht?"
  /// nicht beantworten — und der Anbieter würde sie als Erstes stellen.
  ///
  /// Wirft nie und blockiert nie länger als [_kOrtTimeout]. Ein Speedtest,
  /// der auf ein GPS-Fix wartet, das im Keller nie kommt, wäre schlimmer als
  /// eine Messung ohne Ort — deshalb fällt die Methode auf die zuletzt
  /// bekannte Position zurück und markiert sie als solche.
  static Future<Map<String, dynamic>?> _standort({bool imHintergrund = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return await _letzteLage(grund: 'Ortungsdienst aus');
      }
      var recht = await Geolocator.checkPermission();
      if (recht == LocationPermission.denied) {
        // Im Hintergrund gibt es keine Activity — ein Dialog kann dort gar
        // nicht erscheinen und der Aufruf laeuft nur in den Timeout.
        recht = imHintergrund
            ? recht
            : await Geolocator.requestPermission();
      }
      if (recht == LocationPermission.denied ||
          recht == LocationPermission.deniedForever) {
        return await _letzteLage(grund: 'keine Ortungsberechtigung');
      }
      // ⚠️ Ab Android 10 liefert `whileInUse` im Hintergrund GAR KEINE
      // Position — die Anfrage laeuft stumm in den Timeout. Genau das war der
      // Grund, warum 36 von 38 Produktionslaeufen auf einen Stunden alten Fix
      // zurueckfielen. Hier ausdruecklich benennen, statt es als „Ortung
      // fehlgeschlagen" zu tarnen; der Bildschirm bietet die Berechtigung an.
      if (imHintergrund && recht != LocationPermission.always) {
        return await _letzteLage(
            grund: 'Ortung im Hintergrund nicht erlaubt (nur „während der '
                'Nutzung") — in den Einstellungen auf „immer" stellen');
      }

      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _kOrtTimeout,
        ),
      ).timeout(_kOrtTimeout);

      final lage = <String, dynamic>{
        'breite': p.latitude,
        'laenge': p.longitude,
        'genauigkeit_m': p.accuracy,
        'hoehe_m': p.altitude,
        'tempo_ms': p.speed,
        'zeit': p.timestamp.toIso8601String(),
        'frisch': true,
      };

      // Adresse holt der Server: er fragt Nominatim und hält einen Cache. Von
      // hier aus zu fragen hieße, OpenStreetMap alle 30 Minuten die eigene IP
      // samt exakter Position zu zeigen — genau das, was beim Durchsatz durch
      // den Verzicht auf Fremdanbieter vermieden wurde.
      final adresse = await ApiService().speedtestAdresse(p.latitude, p.longitude);
      if (adresse != null) lage['adresse'] = adresse;

      await _lageMerken(lage);
      return lage;
    } catch (e) {
      return await _letzteLage(grund: 'Ortung fehlgeschlagen: $e');
    }
  }

  /// Darf im Hintergrund geortet werden? Nur `always` genügt dort.
  static Future<bool> hintergrundOrtungErlaubt() async {
    try {
      return await Geolocator.checkPermission() == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Fragt die Hintergrund-Ortung an.
  ///
  /// Android verlangt das in ZWEI Schritten: erst „während der Nutzung", dann
  /// in einem eigenen Dialog „immer". Ein einzelner Aufruf reicht deshalb
  /// nicht; auf vielen Geräten führt der zweite Schritt in die
  /// Systemeinstellungen. Liefert zurück, ob es am Ende gereicht hat.
  static Future<bool> hintergrundOrtungAnfragen() async {
    try {
      var recht = await Geolocator.checkPermission();
      if (recht == LocationPermission.denied) {
        recht = await Geolocator.requestPermission();
      }
      if (recht == LocationPermission.whileInUse) {
        recht = await Geolocator.requestPermission();
      }
      return recht == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _lageMerken(Map<String, dynamic> lage) async =>
      (await SharedPreferences.getInstance())
          .setString(_prefLetzteLage, jsonEncode(lage));

  /// Letzte bekannte Position, ausdrücklich als veraltet gekennzeichnet.
  ///
  /// `frisch: false` muss mit, sonst stünde später ein Messpunkt an einem Ort,
  /// an dem das Gerät zu dem Zeitpunkt gar nicht mehr war — in einer
  /// Beweisreihe wäre das schlimmer als eine Lücke.
  /// Alter der zuletzt bekannten Position in Sekunden, oder `null`.
  static int? _alterSekunden(Map<String, dynamic> lage) {
    final z = DateTime.tryParse((lage['zeit'] ?? '') as String);
    return z == null ? null : DateTime.now().difference(z).inSeconds;
  }

  static Future<Map<String, dynamic>?> _letzteLage({required String grund}) async {
    final roh = (await SharedPreferences.getInstance()).getString(_prefLetzteLage);
    if (roh == null) return {'frisch': false, 'grund': grund};
    try {
      final lage = Map<String, dynamic>.from(jsonDecode(roh) as Map);
      lage['frisch'] = false;
      lage['grund'] = grund;
      // ⚠️ Das Alter MUSS mit. In der Produktion waren 36 von 38 Läufen
      // Rückfälle auf denselben Fix von 06:47 — mit unverändert ausgewiesenen
      // „4,3 m Genauigkeit". Karte und CSV zeigten ihn als Messort. Solange
      // das Tablet an einem Platz steht, ist das harmlos; nach einem Umzug
      // stünde die falsche Adresse im Beweismaterial. Die Genauigkeitsangabe
      // wird deshalb entfernt — sie gilt für den Zeitpunkt der Ortung, nicht
      // für den der Messung.
      final alter = _alterSekunden(lage);
      lage['alter_s'] = alter;
      lage.remove('genauigkeit_m');
      lage.remove('tempo_ms');
      // Nach einem Tag ist eine alte Position kein Beleg mehr, sondern eine
      // Behauptung. Dann lieber gar kein Ort.
      if (alter != null && alter > 24 * 3600) {
        return {'frisch': false, 'grund': grund, 'alter_s': alter, 'verworfen': true};
      }
      return lage;
    } catch (_) {
      return {'frisch': false, 'grund': grund};
    }
  }

  // ── Reihum-Sperre ───────────────────────────────────────────────────────

  /// Holt die Messsperre.
  ///
  /// Im Hintergrund wird bei Kollision sofort aufgegeben — der nächste Takt
  /// kommt in 30 Minuten, und ein übersprungener Punkt ist harmloser als ein
  /// halbierter. Im Vordergrund wird kurz gewartet, weil dort jemand auf ein
  /// Ergebnis sieht; bleibt die Sperre belegt, wird trotzdem gemessen und der
  /// Datensatz als möglicherweise beeinflusst gekennzeichnet.
  static Future<_Sperre> _sperreHolen(String id, {required bool imHintergrund}) async {
    final versuche = imHintergrund ? 1 : 3;
    for (var i = 0; i < versuche; i++) {
      final antwort = await ApiService().speedtestSlot('claim', id);
      if (antwort['erteilt'] == true) {
        return antwort['koordiniert'] == true ? _Sperre.erteilt : _Sperre.unkoordiniert;
      }
      if (i < versuche - 1) await Future<void>.delayed(const Duration(seconds: 6));
    }
    return imHintergrund ? _Sperre.abgelehnt : _Sperre.trotzdem;
  }

  static Future<void> _sperreFreigeben(String id) async {
    try {
      await ApiService().speedtestSlot('release', id);
    } catch (_) {
      // Die Sperre läuft serverseitig nach 120 s von selbst ab.
    }
  }

  // ── Server ──────────────────────────────────────────────────────────────

  static Future<Map<String, String>> _kopfzeilen() async {
    final api = ApiService();
    final token = api.token;
    if (token == null || token.isEmpty) {
      throw const HttpException('Kein gültiges Token — Messung nicht möglich');
    }
    return {
      HttpHeaders.authorizationHeader: 'Bearer $token',
      HttpHeaders.userAgentHeader: 'ICD360S-Vorsitzer/1.0',
      // Klammer zwischen Messung und Serverprotokoll: nginx schreibt diese
      // Kennung mit, submit.php sucht darüber die eigenen Zeilen und legt die
      // dort gemessenen Dauern und Byte-Zahlen mit in den Datensatz. Aus einer
      // Parteibehauptung werden damit zwei sich deckende Aufzeichnungen aus
      // getrennten Systemen. Geht über kopf.forEach automatisch an jede
      // Range-Anfrage und jeden POST.
      'X-Mess-Id': _messId,
    };
  }

  static Future<void> _planLaden() async {
    try {
      final antwort = await ApiService().speedtestPlan();
      if (antwort != null) _plan = SpeedtestPlan.fromJson(antwort);
    } catch (_) {
      // Netz weg oder Endpunkt alt: mit den Voreinstellungen weitermessen.
      // Eine ausgefallene Messung wäre der schlechtere Ausgang.
    }
  }

  static Future<void> _einreichen(SpeedtestErgebnis e) async {
    Map<String, dynamic>? datensatz;
    try {
      final geraet = await _geraetInfo();
      datensatz = {
        'geraet_id': await geraetId(),
        'geraet_name': geraet.name,
        'plattform': geraet.plattform,
        'bauform': geraet.bauform,
        'modell': geraet.modell,
        'os_version': geraet.osVersion,
        'os_variante': geraet.osVariante,
        'geraet_roh': geraet.roh,
        'app_version':
            '${UpdateService.currentVersion}+${UpdateService.currentBuildNumber}',
        // Lückenanzeiger innerhalb einer Installation — NICHT die Idempotenz,
        // die hängt an `mess_id`. Begründung bei [_naechsteLaufNr].
        'lauf_nr': await _naechsteLaufNr(),
        'install_id': await _installId(),
        // Trägt die Idempotenz: UNIQUE(geraet_key, mess_id) auf dem Server
        // verhindert, dass eine Wiederholung nach „gespeichert, Antwort
        // verloren" den Messpunkt verdoppelt. Wird mit dem Datensatz in der
        // Outbox abgelegt, ist beim Nachreichen also unverändert.
        'mess_id': _messId,
        ...e.toJson(),
      };
      final antwort = await ApiService().speedtestEinreichen(datensatz);
      if (antwort['success'] != true) {
        throw StateError(antwort['message']?.toString() ?? 'abgelehnt');
      }
      // Nur nach einem Erfolg: bei totem Token würde sonst jeder Takt die
      // ganze Warteschlange erfolglos durchprobieren.
      await _outboxLeeren();
    } catch (err) {
      // Zurücklegen statt verwerfen — die Begründung steht bei [_inOutbox].
      if (datensatz != null) await _inOutbox(datensatz);
      _log.warning('Speedtest zurückgelegt (nicht eingereicht): $err', tag: 'SPEEDTEST');
    }
  }

  /// Wer misst hier eigentlich?
  ///
  /// Der Verein ist gleichzeitig von drei Geräten mit demselben Konto
  /// angemeldet. Eine Messreihe, in der nicht steht, ob ein Punkt vom Tablet an
  /// der Telekom-SIM oder vom MacBook am WLAN stammt, beantwortet die Frage
  /// nach der Mobilfunkleitung gar nicht. Die Geräte laufen dabei nicht
  /// zusammen: `DeviceKeyService.deviceId` ist hardwareabgeleitet und je Gerät
  /// verschieden (Präfix AND/MAC/LNX/WIN), nicht kontogebunden.
  ///
  /// Die Bauform wird je Plattform aus dem ermittelt, was dort belastbar ist —
  /// nicht aus Modellnamenslisten, die jedes noch nicht gelistete Gerät
  /// verfehlen.
  static Future<_GeraetInfo> _geraetInfo() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        // Bauform kommt aus der kleinsten Bildschirmkante (Androids eigene
        // 600-dp-Grenze), die Variante nur als Indiz — siehe icd_netinfo.
        final profil = await geraeteprofil();
        final bauform = (profil?['bauform'] as String?) ?? 'unbekannt';
        final variante = profil?['os_variante'] as String?;
        final osName = variante != null && variante != 'unbestimmt'
            ? '$variante (Android ${a.version.release}, SDK ${a.version.sdkInt})'
            : 'Android ${a.version.release} (SDK ${a.version.sdkInt})';
        return _GeraetInfo(
          '${a.manufacturer} ${a.model}',
          'android',
          a.model,
          osName,
          bauform: bauform,
          osVariante: variante,
          roh: profil,
        );
      }
      if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        // iOS sagt selbst, ob iPhone oder iPad — kein Raten nötig.
        final m = i.model.toLowerCase();
        return _GeraetInfo(
          i.name, 'ios', i.utsname.machine, '${i.systemName} ${i.systemVersion}',
          bauform: m.contains('ipad') ? 'tablet' : (m.contains('ipod') ? 'handy' : 'handy'),
        );
      }
      if (Platform.isMacOS) {
        final m = await plugin.macOsInfo;
        // `modelName` ist der Klartext („MacBook Pro"), `model` nur die
        // Kennung („Mac15,3"), aus der sich bei neueren Geräten nichts mehr
        // ableiten lässt. Deshalb zuerst der Klartext, und wenn der nichts
        // hergibt, ausdrücklich keine Bauform statt einer geratenen.
        final klartext = m.modelName.toLowerCase();
        final kennung = m.model.toLowerCase();
        final bauform = klartext.contains('book') || kennung.contains('book')
            ? 'laptop'
            : (klartext.contains('imac') ||
                    klartext.contains('mac mini') ||
                    klartext.contains('mac studio') ||
                    klartext.contains('mac pro')
                ? 'desktop'
                : 'unbekannt');
        return _GeraetInfo(
          m.computerName, 'macos',
          m.modelName.isNotEmpty ? m.modelName : m.model,
          'macOS ${m.majorVersion}.${m.minorVersion}.${m.patchVersion}',
          bauform: bauform,
        );
      }
      if (Platform.isLinux) {
        final l = await plugin.linuxInfo;
        // Ein Akku im Gerät heißt Laptop. Das ist unter Linux die einzige
        // Angabe, die ohne Zusatzpaket zuverlässig ist.
        var bauform = 'desktop';
        try {
          final psu = Directory('/sys/class/power_supply');
          if (psu.existsSync() &&
              psu.listSync().any((e) => e.path.split('/').last.startsWith('BAT'))) {
            bauform = 'laptop';
          }
        } catch (_) {
          bauform = 'unbekannt';
        }
        return _GeraetInfo(l.prettyName, 'linux', l.name, l.version ?? '', bauform: bauform);
      }
      if (Platform.isWindows) {
        final w = await plugin.windowsInfo;
        // Windows gibt über device_info_plus keinen Hinweis auf Laptop oder
        // Desktop her. Lieber nichts behaupten.
        return _GeraetInfo(w.computerName, 'windows', w.productName, w.displayVersion,
            bauform: 'unbekannt');
      }
    } catch (_) {
      // Gerätename ist Beiwerk — ohne ihn läuft die Messung genauso.
    }
    return const _GeraetInfo('Unbekannt', 'unbekannt', '', '');
  }
}

// ── Datentypen ────────────────────────────────────────────────────────────

enum SpeedtestPhase { latenz, download, upload }

/// Zustand der Lastlatenz-Sonde. Zwei Werte reichen nicht: „noch kein Fenster"
/// und „Phase vorbei" führen sonst beide zum Abbruch, und die Sonde misst nie.
enum _SondePhase { wartet, laeuft, fertig }

/// Ergebnis des Sperrantrags vor einer Messung.
enum _Sperre {
  /// Sperre gehört uns, kein anderes Gerät misst.
  erteilt,

  /// Redis war nicht erreichbar — es wird gemessen, aber ohne Koordination.
  unkoordiniert,

  /// Ein anderes Gerät misst; im Hintergrund wird der Takt ausgelassen.
  abgelehnt,

  /// Ein anderes Gerät misst, aber jemand steht davor und hat den Knopf
  /// gedrückt. Es wird gemessen und der Datensatz gekennzeichnet.
  trotzdem,
}

/// Vom Server steuerbare Messgrößen — so lassen sich Datenverbrauch und
/// Genauigkeit nachregeln, ohne die App neu auszurollen.
@immutable
class SpeedtestPlan {
  /// Obergrenze der Übertragung, NICHT mehr die Zielgröße.
  ///
  /// Vorher war die Datenmenge fest und das Messfenster damit umgekehrt
  /// proportional zur Geschwindigkeit: 25 MB sind bei 150 Mbit/s rund 1,3 s
  /// Übertragung und nach Abzug der Aufwärmphase knapp eine Sekunde Fenster.
  /// In den ersten 38 Produktionsläufen lag der höchste je gemessene Wert bei
  /// 156,5 Mbit/s und wurde immer wieder fast exakt getroffen — das war keine
  /// Grenze der Leitung, sondern die des eigenen Verfahrens. Gemessen wird
  /// jetzt auf ZEIT ([zielFensterMs]); die Byte-Zahl ist nur noch der Deckel,
  /// damit eine schnelle Leitung nicht beliebig Volumen verbrennt.
  final int downloadBytes;
  final int uploadBytes;
  final int streams;

  /// Länge des angestrebten Messfensters. Darunter misst man überwiegend den
  /// TCP-Aufbau; ein Fenster in dieser Größe ist auch das, was die
  /// Bundesnetzagentur ihrer eigenen Messung zugrunde legt.
  final int zielFensterMs;

  /// Unterhalb dieser Fensterlänge gilt der Durchsatzwert als weich. Er wird
  /// weiterhin gespeichert, aber ausgewiesen — und aus der Bewertung genommen.
  final int mindestFensterMs;

  /// Tagesbudget in MB. Auf Zeit zu messen heißt: je schneller die Leitung,
  /// desto mehr Volumen je Lauf. Ohne Deckel wüchse der Verbrauch genau dann,
  /// wenn die Leitung gut ist. Ist das Budget aufgebraucht, laufen Latenz,
  /// Netz-Momentaufnahme und Ortung weiter — nur die Massenübertragung fällt
  /// aus, gekennzeichnet mit `nur_latenz`.
  final int tagesvolumenMb;

  /// 300 ms. Deckt den TCP-Slow-Start bei mobilfunküblichen Umlaufzeiten ab.
  final int aufwaermMs;
  final int latenzProben;

  const SpeedtestPlan({
    this.downloadBytes = 64 * 1024 * 1024,
    this.uploadBytes = 24 * 1024 * 1024,
    this.streams = 4,
    this.zielFensterMs = 3000,
    this.mindestFensterMs = 1200,
    this.tagesvolumenMb = 3000,
    this.aufwaermMs = 300,
    this.latenzProben = 12,
  });

  factory SpeedtestPlan.fromJson(Map<String, dynamic> j) => SpeedtestPlan(
        downloadBytes: (j['download_bytes'] as num?)?.toInt() ?? 64 * 1024 * 1024,
        uploadBytes: (j['upload_bytes'] as num?)?.toInt() ?? 24 * 1024 * 1024,
        streams: (j['streams'] as num?)?.toInt() ?? 4,
        zielFensterMs: (j['ziel_fenster_ms'] as num?)?.toInt() ?? 3000,
        mindestFensterMs: (j['mindest_fenster_ms'] as num?)?.toInt() ?? 1200,
        tagesvolumenMb: (j['tagesvolumen_mb'] as num?)?.toInt() ?? 3000,
        aufwaermMs: (j['aufwaerm_ms'] as num?)?.toInt() ?? 300,
        latenzProben: (j['latenz_proben'] as num?)?.toInt() ?? 12,
      );
}

@immutable
class SpeedtestErgebnis {
  final DateTime gemessenAm;
  final double dauerSekunden;
  final double downloadMbps;
  final double uploadMbps;
  final double pingMinMs;
  final double pingAvgMs;
  final double jitterMs;

  /// Median und Maximum der Latenz. Die mittlere Abweichung allein versteckt
  /// genau den einen Aussetzer, der ein Gespräch zerreißt.
  final double pingMedianMs;
  final double pingMaxMs;

  /// ⚠️ KEIN Paketverlust. Über TCP verschwindet echter Verlust in
  /// Retransmits — 3 % Verlust ergäben hier zuverlässig 0,0 %. Gezählt werden
  /// fehlgeschlagene ANFRAGEN, und zwar getrennt: Zeitüberschreitungen liegen
  /// am Netz, HTTP-Fehlerstatus an unserem eigenen Server.
  final int anfragenTimeout;
  final int anfragenHttpFehler;
  final int latenzProben;

  /// Latenz WÄHREND der Übertragung — die Zahl, die den tatsächlichen Schaden
  /// zeigt. Auf Mobilfunk sind 20 ms im Leerlauf und 900 ms unter Last normal;
  /// ein reiner Durchsatzwert erklärt nie, warum Videotelefonie nicht geht.
  /// `null` bei zu wenigen Proben — dann wird gar nichts behauptet.
  final double? lastlatenzDownMedianMs;
  final double? lastlatenzDownMaxMs;
  final int lastlatenzDownProben;
  final double? lastlatenzUpMedianMs;
  final double? lastlatenzUpMaxMs;
  final int lastlatenzUpProben;

  /// Tripel [ms, Bytes, aktive Ströme] im 50-ms-Takt. Ein Mittelwert kann ein
  /// 300-ms-Loch mitten im Transfer prinzipiell nicht enthalten.
  final List<List<num>> downloadVerlauf;

  /// Zeit zwischen dem letzten geschriebenen Byte und dem Ende des Uploads.
  final double uploadNachlaufSekunden;

  /// Zeitstempel des Servers zu Beginn des Downloads und am Ende des Uploads.
  /// Die einzigen Zeitangaben im Lauf, die nicht vom Gerät stammen.
  final double? serverZeitDownload;
  final double? serverZeitUpload;

  /// Wieviel lief neben der Messung? Siehe `_fremdverkehr`. `null`, wo das
  /// Gerät keine Zähler liefert — nie stillschweigend „störungsfrei".
  final Map<String, dynamic>? fremdverkehr;
  final int downloadBytes;
  final int uploadBytes;

  /// Länge des tatsächlich ausgewerteten Fensters (ohne Aufwärmphase).
  /// Deutlich unter einer Sekunde heißt: der Wert ist weich, weil die
  /// Übertragung zu kurz war, um den Slow-Start hinter sich zu lassen.
  final double downloadFensterSekunden;
  final double uploadFensterSekunden;

  final int streams;
  final Map<String, dynamic>? netz;

  /// Wo gemessen wurde: Koordinaten, Genauigkeit und — vom Server ergänzt —
  /// die Adresse. `frisch: false` heißt, es ist die zuletzt bekannte Position,
  /// weil kein GPS-Fix zustande kam.
  final Map<String, dynamic>? lage;

  final String? fehler;

  /// Grund, warum die Massenübertragung ausgelassen wurde (`roaming`,
  /// `tagesbudget`) — sonst `null`. Ein solcher Punkt zählt für Latenz und
  /// Abdeckung, aber nicht für den Durchsatz.
  final String? nurLatenzGrund;

  /// Endete der Download an der Zielzeit? Sonst reichte der Byte-Deckel nicht
  /// bis zum Zielfenster und der Wert ist eine Untergrenze.
  final bool downloadZeitAbbruch;

  /// Empfangsrate laut Schnittstellenzähler des Geräts — die zweite, vom
  /// Anwendungscode unabhängige Messung. Liegt systematisch ÜBER
  /// [downloadMbps] (Protokollköpfe, beim Abbruch fliegende Bytes) und ist
  /// deshalb die Obergrenze, nicht der Messwert.
  final double? downloadSchnittstelleMbps;

  /// Die Upload-Phase ist gescheitert, der Download aber gültig. Beides
  /// getrennt zu führen verhindert, dass ein gültiger Messpunkt als
  /// Netzausfall in der Reihe steht.
  final String? uploadFehler;

  /// Upload lief in die harte Zeitgrenze — kein Messwert, aber kein Ausfall.
  final bool uploadZeitDeckel;

  /// Womit gemessen wurde. plan.php ist ohne Release änderbar; ohne diese
  /// beiden Zahlen liesse sich ein alter Punkt später nicht mehr einordnen.
  final int zielFensterMs;
  final int mindestFensterMs;

  /// Hat dieses Gerät als einziges gemessen?
  ///
  /// Drei Geräte hängen am selben Konto. Lief ein zweites parallel, ist der
  /// Wert womöglich selbstverschuldet niedrig und darf nicht ungeprüft als
  /// Beleg gegen Telekom herhalten.
  final bool alleine;

  /// War die Reihum-Sperre überhaupt erreichbar? Bei `false` ist [alleine]
  /// nur eine Annahme.
  final bool koordiniert;

  /// Wurde der Lauf ausgelassen, weil ein anderes Gerät gemessen hat?
  /// Solche Läufe werden NICHT eingereicht — sonst verfälschten sie die
  /// Fehlerquote mit einem Fehler, den das Netz nicht zu verantworten hat.
  final bool uebersprungen;

  const SpeedtestErgebnis({
    required this.gemessenAm,
    required this.dauerSekunden,
    required this.downloadMbps,
    required this.uploadMbps,
    required this.pingMinMs,
    required this.pingAvgMs,
    required this.jitterMs,
    this.pingMedianMs = 0,
    this.pingMaxMs = 0,
    this.anfragenTimeout = 0,
    this.anfragenHttpFehler = 0,
    this.latenzProben = 0,
    this.lastlatenzDownMedianMs,
    this.lastlatenzDownMaxMs,
    this.lastlatenzDownProben = 0,
    this.lastlatenzUpMedianMs,
    this.lastlatenzUpMaxMs,
    this.lastlatenzUpProben = 0,
    this.downloadVerlauf = const [],
    this.uploadNachlaufSekunden = 0,
    this.serverZeitDownload,
    this.serverZeitUpload,
    this.fremdverkehr,
    required this.downloadBytes,
    required this.uploadBytes,
    required this.downloadFensterSekunden,
    required this.uploadFensterSekunden,
    required this.streams,
    required this.netz,
    required this.fehler,
    this.lage,
    this.alleine = true,
    this.koordiniert = true,
    this.uebersprungen = false,
    this.nurLatenzGrund,
    this.downloadZeitAbbruch = false,
    this.downloadSchnittstelleMbps,
    this.uploadFehler,
    this.uploadZeitDeckel = false,
    this.zielFensterMs = 3000,
    this.mindestFensterMs = 1200,
  });

  /// Lauf ausgelassen, weil ein anderes Gerät gerade misst.
  factory SpeedtestErgebnis.uebersprungen(DateTime wann) => SpeedtestErgebnis(
        gemessenAm: wann,
        dauerSekunden: 0,
        downloadMbps: 0,
        uploadMbps: 0,
        pingMinMs: 0,
        pingAvgMs: 0,
        jitterMs: 0,
        downloadBytes: 0,
        uploadBytes: 0,
        downloadFensterSekunden: 0,
        uploadFensterSekunden: 0,
        streams: 0,
        netz: null,
        fehler: null,
        alleine: false,
        uebersprungen: true,
      );

  bool get erfolgreich => fehler == null && !uebersprungen;

  /// Was das Netz selbst zu liefern behauptet, in Mbit/s.
  double? get gemeldetDownMbps {
    final k = netz?['gemeldet_down_kbps'];
    return k is num ? k / 1000 : null;
  }

  /// Schlechtester Latenzwert unter Last, über beide Richtungen.
  ///
  /// Unter [_kLastMindestproben] Proben wird nichts behauptet — bei zwei
  /// Messwerten wäre ein „Maximum" nur ein Zufallswert, und in einer
  /// Beweisreihe ist ein fehlender Wert besser als ein weicher.
  double? get lastlatenzMaxMs {
    final werte = <double>[
      if (lastlatenzDownProben >= _kLastMindestproben && lastlatenzDownMaxMs != null)
        lastlatenzDownMaxMs!,
      if (lastlatenzUpProben >= _kLastMindestproben && lastlatenzUpMaxMs != null)
        lastlatenzUpMaxMs!,
    ];
    return werte.isEmpty ? null : werte.reduce(max);
  }

  /// Kurze, lesbare Adresse — oder null, wenn keine ermittelt wurde.
  String? get adresse => lage?['adresse']?['kurz'] as String?;

  /// Position bekannt und aktuell?
  bool get ortFrisch => lage?['frisch'] == true;

  String get generation =>
      (netz?['netz_generation'] as String?) ?? (netz?['transport'] as String?) ?? 'unbekannt';

  Map<String, dynamic> toJson() => {
        'gemessen_am': gemessenAm.toIso8601String(),
        'dauer_s': double.parse(dauerSekunden.toStringAsFixed(2)),
        'download_mbps': double.parse(downloadMbps.toStringAsFixed(2)),
        'upload_mbps': double.parse(uploadMbps.toStringAsFixed(2)),
        'ping_min_ms': double.parse(pingMinMs.toStringAsFixed(1)),
        'ping_avg_ms': double.parse(pingAvgMs.toStringAsFixed(1)),
        'jitter_ms': double.parse(jitterMs.toStringAsFixed(1)),
        'ping_median_ms': double.parse(pingMedianMs.toStringAsFixed(1)),
        'ping_max_ms': double.parse(pingMaxMs.toStringAsFixed(1)),
        // Bewusst NICHT mehr 'paketverlust_prozent': der Name behauptete eine
        // Groesse, die ueber TCP gar nicht messbar ist.
        'anfragen_timeout': anfragenTimeout,
        'anfragen_http_fehler': anfragenHttpFehler,
        'latenz_proben': latenzProben,
        'lastlatenz_down_median_ms': lastlatenzDownMedianMs,
        'lastlatenz_down_max_ms': lastlatenzDownMaxMs,
        'lastlatenz_down_proben': lastlatenzDownProben,
        'lastlatenz_up_median_ms': lastlatenzUpMedianMs,
        'lastlatenz_up_max_ms': lastlatenzUpMaxMs,
        'lastlatenz_up_proben': lastlatenzUpProben,
        'download_verlauf': downloadVerlauf,
        'upload_nachlauf_s': double.parse(uploadNachlaufSekunden.toStringAsFixed(3)),
        'server_zeit_download': serverZeitDownload,
        'server_zeit_upload': serverZeitUpload,
        'fremdverkehr': fremdverkehr,
        'download_bytes': downloadBytes,
        'upload_bytes': uploadBytes,
        'download_fenster_s': double.parse(downloadFensterSekunden.toStringAsFixed(3)),
        'upload_fenster_s': double.parse(uploadFensterSekunden.toStringAsFixed(3)),
        'streams': streams,
        'netz': netz,
        'lage': lage,
        'fehler': fehler,
        'alleine': alleine,
        'koordiniert': koordiniert,
        // Wurde die Massenübertragung ausgelassen (Roaming/Tagesbudget)? Der
        // Punkt zählt dann für Latenz und Abdeckung, aber NICHT für Durchsatz.
        'nur_latenz': nurLatenzGrund,
        // Endete der Download an der Zielzeit (gut) oder am Byte-Deckel? Im
        // zweiten Fall ist der Wert eine Untergrenze der wahren Leistung.
        'download_zeit_abbruch': downloadZeitAbbruch,
        'download_schnittstelle_mbps': downloadSchnittstelleMbps,
        'upload_fehler': uploadFehler,
        'upload_zeit_deckel': uploadZeitDeckel,
        // Womit gemessen wurde — sonst lässt sich ein alter Datenpunkt später
        // nicht mehr einordnen, wenn plan.php längst andere Werte liefert.
        'plan': {
          'ziel_fenster_ms': zielFensterMs,
          'mindest_fenster_ms': mindestFensterMs,
        },
        // Für die Auswertung entscheidend: nur was auf der Mobilfunkstrecke
        // gemessen wurde, gehört in die Bewertung gegen den Tarif.
        'ist_mobilfunk': istMobilfunk,
        'fenster_ausreichend': fensterAusreichend,
      };

  /// Lief dieser Lauf über die Telekom-SIM — oder über WLAN?
  ///
  /// Ohne diese Trennung rettet ein WLAN-Lauf still einen beanstandeten Tag:
  /// die Tagesbestwert-Logik der Vfg 35/2026 fragt nur, ob EINE Messung des
  /// Tages die Untergrenze schafft. Am Vereinssitz liegt WLAN an, also träfe
  /// das praktisch jeden Tag zu — die ganze Auswertung wäre wertlos.
  bool get istMobilfunk => netz?['transport'] == 'cellular';

  /// War das Messfenster lang genug, um mehr als den TCP-Aufbau zu sehen?
  bool get fensterAusreichend =>
      downloadFensterSekunden * 1000 >= mindestFensterMs;
}

@immutable
class _Latenz {
  final double min, avg, jitter, median, max;

  /// Aufgeschlüsselt statt als eine Zahl „Paketverlust": Zeitüberschreitungen
  /// liegen am Netz, HTTP-Fehlerstatus an UNSEREM Server. Bei einer
  /// JWT-Rotation lieferten sonst alle Proben 401, und in der Beweisreihe
  /// stünde eine Zeile mit „100 % Paketverlust".
  final int timeouts, httpFehler, proben;

  const _Latenz(this.min, this.avg, this.jitter, this.median, this.max,
      this.timeouts, this.httpFehler, this.proben);
}

/// Latenz während einer laufenden Übertragung.
@immutable
class _Lastlatenz {
  final double? median;
  final double? max;
  final int proben;
  const _Lastlatenz(this.median, this.max, this.proben);
}

@immutable
class _Durchsatz {
  final double mbps;
  final int bytes;
  final double fensterSekunden;

  /// Tripel [ms seit Fensterbeginn, Bytes im Fenster, aktive Ströme].
  final List<List<num>> verlauf;

  final _Lastlatenz lastlatenz;

  const _Durchsatz(this.mbps, this.bytes, this.fensterSekunden, this.verlauf,
      this.lastlatenz);
}

@immutable
class _GeraetInfo {
  final String name, plattform, modell, osVersion;

  /// `handy` · `tablet` · `laptop` · `desktop` · `unbekannt`.
  ///
  /// Bewusst mit einem eigenen Wert für „weiß ich nicht": bei drei gleichzeitig
  /// angemeldeten Geräten ist eine geratene Bauform schlimmer als eine fehlende
  /// — sie führt beim Auswerten zur falschen Leitung.
  final String bauform;

  /// Nur ein Indiz (GrapheneOS/CalyxOS/…), siehe icd_netinfo.
  final String? osVariante;

  /// Roh-Build-Felder von Android, damit sich die Einstufung später
  /// nachvollziehen lässt, ohne das Gerät in der Hand zu haben.
  final Map<String, dynamic>? roh;

  const _GeraetInfo(
    this.name,
    this.plattform,
    this.modell,
    this.osVersion, {
    this.bauform = 'unbekannt',
    this.osVariante,
    this.roh,
  });
}
