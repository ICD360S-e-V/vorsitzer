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

/// Wieviele nicht eingereichte Messungen zurückgelegt werden.
///
/// 200 ≈ vier Tage ohne Netz. Unbegrenzt zu puffern füllte nach Wochen den
/// Gerätespeicher; bei Überlauf fällt das Älteste heraus.
const int _kOutboxMax = 200;

/// Wieviele Nachzügler ein Lauf mitnimmt. Mehr würde den 30-Minuten-Takt
/// aufhalten und im Hintergrundjob ins Zeitlimit laufen.
const int _kOutboxProLauf = 10;

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
    var downBytes = 0, upBytes = 0;
    var downFenster = 0.0, upFenster = 0.0;
    _Lastlatenz lastDown = const _Lastlatenz(null, null, 0);
    _Lastlatenz lastUp = const _Lastlatenz(null, null, 0);
    List<List<num>> downVerlauf = const [];
    _serverZeitUpload = null;
    _uploadNachlauf = 0;
    _fremdverkehrDown = null;
    _serverZeitDownload = null;
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

      fortschritt?.call(SpeedtestPhase.download, 0);
      final d = await _downloadMessen(
          klient, kopf, pingMin, fortschritt, (m) => netz ??= m);
      down = d.mbps;
      downBytes = d.bytes;
      downFenster = d.fensterSekunden;
      downVerlauf = d.verlauf;
      lastDown = d.lastlatenz;

      fortschritt?.call(SpeedtestPhase.upload, 0);
      final u = await _uploadMessen(klient, kopf, pingMin, fortschritt);
      up = u.mbps;
      upBytes = u.bytes;
      upFenster = u.fensterSekunden;
      lastUp = u.lastlatenz;
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
    final lage = await _standort();

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
  static Future<_Lastlatenz> _lastSondeStarten(
    HttpClient klient,
    Map<String, String> kopf,
    bool Function() laeuftNoch,
  ) async {
    final werte = <double>[];
    var ersteVerworfen = false;

    while (laeuftNoch()) {
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
    // niedrig. Lieber hier deckeln.
    final gesamt = min(_plan.downloadBytes, kSpeedtestQuelleBytes);
    final jeStrom = gesamt ~/ _plan.streams;
    // Nach der Ganzzahldivision bleibt ein Rest ungenutzt. Der Fortschritt muss
    // sich auf das beziehen, was tatsaechlich angefordert wird, sonst bleibt
    // der Balken bei 99 % stehen.
    final angefordert = jeStrom * _plan.streams;
    final aufwaermSchwelle = _aufwaermMs(pingMin);

    var gezaehlt = 0;          // Bytes im Messfenster
    var gesamtBytes = 0;       // Bytes insgesamt, inklusive Aufwärmphase
    Stopwatch? aufwaermUhr;    // startet erst, wenn ALLE Ströme fließen
    Stopwatch? fenster;
    var netzGeholt = false;
    var laufend = true;
    Map<String, dynamic>? zaehlerVor;

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

        if (!ersteBytes[index]) {
          ersteBytes[index] = true;
          if (!ersteBytes.contains(false)) aufwaermUhr = Stopwatch()..start();
        }

        if (fenster == null) {
          if (aufwaermUhr != null &&
              aufwaermUhr!.elapsedMilliseconds >= aufwaermSchwelle) {
            fenster = Stopwatch()..start();
            // An der FENSTERgrenze ablesen, nicht um den ganzen Lauf: die
            // Latenzproben sind überwiegend Leerlauf, in dem Fremdbytes
            // auflaufen, ohne den Durchsatz zu stören.
            unawaited(verkehrszaehler().then((v) => zaehlerVor = v));
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

        if (fortschritt != null && angefordert > 0) {
          fortschritt(SpeedtestPhase.download, (gesamtBytes / angefordert).clamp(0, 1));
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

    final sonde = _lastSondeStarten(klient, kopf, () => laufend && fenster != null);

    try {
      await Future.wait(List.generate(_plan.streams, strom));
    } finally {
      laufend = false;
      profil.cancel();
    }
    final last = await sonde;
    final zaehlerNach = await verkehrszaehler();

    final sekunden = (fenster?.elapsedMicroseconds ?? 0) / 1e6;
    _fremdverkehrDown =
        _fremdverkehr(zaehlerVor, zaehlerNach, gezaehlt, sekunden);

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

  static Future<_Durchsatz> _uploadMessen(
    HttpClient klient,
    Map<String, String> kopf,
    double pingMin,
    void Function(SpeedtestPhase, double)? fortschritt,
  ) async {
    final jeStrom = _plan.uploadBytes ~/ _plan.streams;
    // Wie beim Download: der Rest der Ganzzahldivision wird nicht gesendet,
    // der Fortschritt muss sich am tatsaechlich Gesendeten messen.
    final angefordert = jeStrom * _plan.streams;
    final aufwaermSchwelle = _aufwaermMs(pingMin);
    // Einmal erzeugen und wiederverwenden: 2,5 MB Zufall je Strom neu zu
    // würfeln kostet auf einem Tablet mehr Zeit als das Senden selbst und
    // würde direkt als langsamer Upload erscheinen.
    final block = Uint8List(65536);
    final zufall = Random();
    for (var i = 0; i < block.length; i++) {
      block[i] = zufall.nextInt(256);
    }

    var gesendet = 0;          // Bytes insgesamt, inklusive Aufwärmphase
    var gezaehlt = 0;          // Bytes im Messfenster
    Stopwatch? aufwaermUhr;
    Stopwatch? fenster;
    var laufend = true;

    // Anker ist das Zurückkehren ALLER postUrl(), nicht der erste flush():
    // der kehrt aus dem selbstjustierenden Sendepuffer praktisch sofort zurück
    // und beweist nicht, dass ein Byte die Leitung gesehen hat.
    final verbunden = List<bool>.filled(_plan.streams, false);
    // Ende je Strom, um das Fenster am SPÄTESTEN zu schließen. Ein
    // fenster.stop() beim ersten fertigen Strom hielte die gemeinsame Uhr an
    // und überschätzte den Durchsatz.
    final enden = List<int>.filled(_plan.streams, 0);

    Future<void> strom(int index) async {
      final anfrage = await klient.postUrl(Uri.parse('$_basis/speedtest/sink.php'));
      kopf.forEach(anfrage.headers.set);
      anfrage.headers.contentType = ContentType('application', 'octet-stream');
      // Content-Length ist Pflicht: ohne sie sendet dart:io chunked, und bei
      // PHP-FPM kommt dann nichts an — nachgemessen, sink.php beantwortet das
      // inzwischen mit HTTP 411 statt still 0 Bytes zu verbuchen.
      anfrage.contentLength = jeStrom;
      verbunden[index] = true;
      if (!verbunden.contains(false)) aufwaermUhr ??= Stopwatch()..start();

      var rest = jeStrom;
      while (rest > 0) {
        final n = min(block.length, rest);
        anfrage.add(n == block.length ? block : Uint8List.sublistView(block, 0, n));
        // flush() kehrt zurück, wenn der Block an den Socket übergeben ist —
        // näher kommt man aus Dart nicht an „ist auf der Leitung".
        await anfrage.flush();
        rest -= n;
        gesendet += n;

        // Aufwärmphase auch beim Upload verwerfen. Auf Mobilfunk ist der
        // Upload die schwächere Richtung, dort schlägt der Slow-Start
        // anteilig stärker durch als beim Download.
        if (fenster == null) {
          if (aufwaermUhr != null &&
              aufwaermUhr!.elapsedMilliseconds >= aufwaermSchwelle) {
            fenster = Stopwatch()..start();
          }
        } else {
          gezaehlt += n;
        }

        if (fortschritt != null && angefordert > 0) {
          fortschritt(SpeedtestPhase.upload, (gesendet / angefordert).clamp(0, 1));
        }
      }
      // Stand NACH der Schreibschleife, aber VOR close(): alles danach ist ein
      // Umlauf plus PHP-Übergabe, in dem kein Byte mehr dazukommt. Früher
      // stand das im Nenner und drückte den Wert.
      enden[index] = fenster?.elapsedMicroseconds ?? 0;

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
    }

    final sonde = _lastSondeStarten(klient, kopf, () => laufend && fenster != null);

    try {
      await Future.wait(List.generate(_plan.streams, strom));
    } finally {
      laufend = false;
    }
    final last = await sonde;

    final fensterEnde = enden.reduce(max);
    final sekunden = fensterEnde / 1e6;
    if (fenster == null || sekunden <= 0) {
      // Kürzer als die Aufwärmphase. Wie beim Download ausdrücklich kein Wert,
      // statt auf eine Uhr auszuweichen, die den Verbindungsaufbau enthält.
      return _Durchsatz(0, gesendet, 0, const [], last);
    }
    // Nachlauf: was zwischen dem letzten geschriebenen Byte und dem Ende des
    // Laufs verstrichen ist. Auf einer gepufferten Mobilfunkstrecke ist das
    // die Zeit, in der die Daten noch in der Warteschlange stehen — ein guter
    // Vorläufer für Bufferbloat.
    _uploadNachlauf =
        ((fenster!.elapsedMicroseconds - fensterEnde) / 1e6).clamp(0, 600);
    return _Durchsatz(
        gezaehlt * 8 / sekunden / 1e6, gesendet, sekunden, const [], last);
  }

  // ── Outbox ──────────────────────────────────────────────────────────────

  /// Wieviele Messungen warten noch darauf, eingereicht zu werden?
  static Future<int> rueckstand() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_prefOutbox) ?? const []).length;
  }

  /// Fortlaufende Nummer je Gerät.
  ///
  /// Trägt die Idempotenz: der Server hat UNIQUE(geraet_key, lauf_nr), sodass
  /// eine Wiederholung nach „gespeichert, aber Antwort verloren" den Messpunkt
  /// nicht verdoppelt. NICHT als Nachweis der Lückenlosigkeit brauchbar — bei
  /// einem vom Betriebssystem unterdrückten Takt steht der Zähler still, weil
  /// [messen] gar nicht erst aufgerufen wird.
  static Future<int> _naechsteLaufNr() async {
    final p = await SharedPreferences.getInstance();
    final n = (p.getInt(_prefLaufNr) ?? 0) + 1;
    await p.setInt(_prefLaufNr, n);
    return n;
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
    double fensterSekunden,
  ) {
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
    final eigenNeben = max(0, eigen - messBytes);
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
  static Future<Map<String, dynamic>?> _standort() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return await _letzteLage(grund: 'Ortungsdienst aus');
      }
      var recht = await Geolocator.checkPermission();
      if (recht == LocationPermission.denied) {
        recht = await Geolocator.requestPermission();
      }
      if (recht == LocationPermission.denied ||
          recht == LocationPermission.deniedForever) {
        return await _letzteLage(grund: 'keine Ortungsberechtigung');
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

  static Future<void> _lageMerken(Map<String, dynamic> lage) async =>
      (await SharedPreferences.getInstance())
          .setString(_prefLetzteLage, jsonEncode(lage));

  /// Letzte bekannte Position, ausdrücklich als veraltet gekennzeichnet.
  ///
  /// `frisch: false` muss mit, sonst stünde später ein Messpunkt an einem Ort,
  /// an dem das Gerät zu dem Zeitpunkt gar nicht mehr war — in einer
  /// Beweisreihe wäre das schlimmer als eine Lücke.
  static Future<Map<String, dynamic>?> _letzteLage({required String grund}) async {
    final roh = (await SharedPreferences.getInstance()).getString(_prefLetzteLage);
    if (roh == null) return {'frisch': false, 'grund': grund};
    try {
      final lage = Map<String, dynamic>.from(jsonDecode(roh) as Map);
      lage['frisch'] = false;
      lage['grund'] = grund;
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
        // Trägt die Idempotenz: UNIQUE(geraet_key, lauf_nr) auf dem Server
        // verhindert, dass eine Wiederholung nach „gespeichert, Antwort
        // verloren" den Messpunkt verdoppelt.
        'lauf_nr': await _naechsteLaufNr(),
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
  /// 25 MB. Bei den ~150 Mbit/s, um die es auf dem 5G-Tarif geht, sind das
  /// rund 1,3 s Übertragung — nach Abzug der Aufwärmphase knapp 1 s Messfenster.
  final int downloadBytes;
  final int uploadBytes;
  final int streams;

  /// 300 ms. Deckt den TCP-Slow-Start bei mobilfunküblichen Umlaufzeiten ab,
  /// ohne von einer 1,3-s-Übertragung zu viel wegzunehmen.
  final int aufwaermMs;
  final int latenzProben;

  const SpeedtestPlan({
    this.downloadBytes = 25 * 1024 * 1024,
    this.uploadBytes = 10 * 1024 * 1024,
    this.streams = 4,
    this.aufwaermMs = 300,
    this.latenzProben = 12,
  });

  factory SpeedtestPlan.fromJson(Map<String, dynamic> j) => SpeedtestPlan(
        downloadBytes: (j['download_bytes'] as num?)?.toInt() ?? 25 * 1024 * 1024,
        uploadBytes: (j['upload_bytes'] as num?)?.toInt() ?? 10 * 1024 * 1024,
        streams: (j['streams'] as num?)?.toInt() ?? 4,
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
      };
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
