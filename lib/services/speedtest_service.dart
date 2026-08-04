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

  /// Voreinstellung; wird von `plan.php` überschrieben, damit sich die Größen
  /// ohne App-Release nachregeln lassen.
  static SpeedtestPlan _plan = const SpeedtestPlan();

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

    var pingMin = 0.0, pingAvg = 0.0, jitter = 0.0, verlust = 0.0;
    var down = 0.0, up = 0.0;
    var downBytes = 0, upBytes = 0;
    var downFenster = 0.0, upFenster = 0.0;

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
      verlust = l.verlust;

      fortschritt?.call(SpeedtestPhase.download, 0);
      final d = await _downloadMessen(klient, kopf, fortschritt, (m) => netz ??= m);
      down = d.mbps;
      downBytes = d.bytes;
      downFenster = d.fensterSekunden;

      fortschritt?.call(SpeedtestPhase.upload, 0);
      final u = await _uploadMessen(klient, kopf, fortschritt);
      up = u.mbps;
      upBytes = u.bytes;
      upFenster = u.fensterSekunden;
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
      paketverlustProzent: verlust,
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

  static Future<_Latenz> _latenzMessen(
    HttpClient klient,
    Map<String, String> kopf,
    void Function(SpeedtestPhase, double)? fortschritt,
  ) async {
    final werte = <double>[];
    var fehlgeschlagen = 0;

    for (var i = 0; i < _plan.latenzProben; i++) {
      final uhr = Stopwatch()..start();
      try {
        final anfrage = await klient.getUrl(Uri.parse('$_basis/speedtest/down.php'));
        kopf.forEach(anfrage.headers.set);
        // Ein einzelnes Byte: gemessen wird die Umlaufzeit, nicht der Durchsatz.
        anfrage.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        final antwort = await anfrage.close().timeout(const Duration(seconds: 5));
        await antwort.drain<void>();
        uhr.stop();
        if (antwort.statusCode < 400) {
          werte.add(uhr.elapsedMicroseconds / 1000);
        } else {
          fehlgeschlagen++;
        }
      } catch (_) {
        fehlgeschlagen++;
      }
      fortschritt?.call(SpeedtestPhase.latenz, (i + 1) / _plan.latenzProben);
    }

    if (werte.isEmpty) {
      return _Latenz(0, 0, 0, 100);
    }

    final avg = werte.reduce((a, b) => a + b) / werte.length;
    // Mittlere absolute Abweichung, nicht Standardabweichung: sie beschreibt
    // das, was beim Telefonieren und in Videokonferenzen tatsächlich stört.
    final jitter = werte.map((w) => (w - avg).abs()).reduce((a, b) => a + b) / werte.length;

    return _Latenz(
      werte.reduce(min),
      avg,
      jitter,
      fehlgeschlagen / _plan.latenzProben * 100,
    );
  }

  static Future<_Durchsatz> _downloadMessen(
    HttpClient klient,
    Map<String, String> kopf,
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

    var gezaehlt = 0;          // Bytes im Messfenster
    var gesamtBytes = 0;       // Bytes insgesamt, inklusive Aufwärmphase
    Stopwatch? fenster;        // startet, wenn die Aufwärmphase vorbei ist
    var netzGeholt = false;

    final aufwaermUhr = Stopwatch()..start();

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

      await for (final block in antwort) {
        gesamtBytes += block.length;

        if (fenster == null) {
          // Aufwärmphase verwerfen: die ersten Millisekunden zeigen nur den
          // TCP-Slow-Start. Wer sie mitrechnet, meldet die eigene Leitung
          // schlechter, als sie ist — und verschenkt damit genau das Argument,
          // um das es geht.
          if (aufwaermUhr.elapsedMilliseconds >= _plan.aufwaermMs) {
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

        if (fortschritt != null && angefordert > 0) {
          fortschritt(SpeedtestPhase.download, (gesamtBytes / angefordert).clamp(0, 1));
        }
      }
    }

    await Future.wait(List.generate(_plan.streams, strom));

    final sekunden = (fenster?.elapsedMicroseconds ?? 0) / 1e6;
    if (fenster == null || sekunden <= 0) {
      // Die Übertragung war kürzer als die Aufwärmphase — auf sehr schnellen
      // Leitungen. Dann lieber die Gesamtzeit nehmen und das im Datensatz
      // ausweisen, als gar keinen Wert zu liefern.
      final gesamtSek = aufwaermUhr.elapsedMicroseconds / 1e6;
      return _Durchsatz(
        gesamtSek > 0 ? gesamtBytes * 8 / gesamtSek / 1e6 : 0,
        gesamtBytes,
        gesamtSek,
      );
    }
    return _Durchsatz(gezaehlt * 8 / sekunden / 1e6, gesamtBytes, sekunden);
  }

  static Future<_Durchsatz> _uploadMessen(
    HttpClient klient,
    Map<String, String> kopf,
    void Function(SpeedtestPhase, double)? fortschritt,
  ) async {
    final jeStrom = _plan.uploadBytes ~/ _plan.streams;
    // Wie beim Download: der Rest der Ganzzahldivision wird nicht gesendet,
    // der Fortschritt muss sich am tatsaechlich Gesendeten messen.
    final angefordert = jeStrom * _plan.streams;
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
    Stopwatch? fenster;
    final aufwaermUhr = Stopwatch()..start();

    Future<void> strom(int index) async {
      final anfrage = await klient.postUrl(Uri.parse('$_basis/speedtest/sink.php'));
      kopf.forEach(anfrage.headers.set);
      anfrage.headers.contentType = ContentType('application', 'octet-stream');
      // Content-Length ist Pflicht: ohne sie sendet dart:io chunked, und bei
      // PHP-FPM kommt dann nichts an — nachgemessen, sink.php beantwortet das
      // inzwischen mit HTTP 411 statt still 0 Bytes zu verbuchen.
      anfrage.contentLength = jeStrom;

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
        // anteilig stärker durch als beim Download — ohne diesen Abzug meldet
        // die Reihe den Upload dauerhaft zu schlecht.
        if (fenster == null) {
          if (aufwaermUhr.elapsedMilliseconds >= _plan.aufwaermMs) {
            fenster = Stopwatch()..start();
          }
        } else {
          gezaehlt += n;
        }

        if (fortschritt != null && angefordert > 0) {
          fortschritt(SpeedtestPhase.upload, (gesendet / angefordert).clamp(0, 1));
        }
      }

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
    }

    await Future.wait(List.generate(_plan.streams, strom));

    final sekunden = (fenster?.elapsedMicroseconds ?? 0) / 1e6;
    if (fenster == null || sekunden <= 0) {
      // Kürzer als die Aufwärmphase — auf sehr schnellen Leitungen. Dann die
      // Gesamtzeit nehmen und das im Datensatz ausweisen, statt gar keinen
      // Wert zu liefern.
      final gesamtSek = aufwaermUhr.elapsedMicroseconds / 1e6;
      return _Durchsatz(
        gesamtSek > 0 ? gesendet * 8 / gesamtSek / 1e6 : 0,
        gesendet,
        gesamtSek,
      );
    }
    return _Durchsatz(gezaehlt * 8 / sekunden / 1e6, gesendet, sekunden);
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
    try {
      final geraet = await _geraetInfo();
      await ApiService().speedtestEinreichen({
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
        ...e.toJson(),
      });
    } catch (err) {
      // Nicht eingereicht heißt nicht verloren: der nächste Durchlauf kommt in
      // 30 Minuten. Ein Wiederholungsspeicher lohnt den Aufwand nicht, weil ein
      // fehlender Punkt in der Reihe nichts an der Aussage ändert.
      _log.warning('Speedtest konnte nicht eingereicht werden: $err', tag: 'SPEEDTEST');
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
  final double paketverlustProzent;
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
    required this.paketverlustProzent,
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
        paketverlustProzent: 0,
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
        'paketverlust_prozent': double.parse(paketverlustProzent.toStringAsFixed(1)),
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
  final double min, avg, jitter, verlust;
  const _Latenz(this.min, this.avg, this.jitter, this.verlust);
}

@immutable
class _Durchsatz {
  final double mbps;
  final int bytes;
  final double fensterSekunden;
  const _Durchsatz(this.mbps, this.bytes, this.fensterSekunden);
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
