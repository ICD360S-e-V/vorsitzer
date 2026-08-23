import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/sperre_passwort.dart';
import 'logger_service.dart';
import 'secure_store.dart';
import 'voice_call_service.dart';

/// Bildschirmsperre der App — mit einem EIGENEN Passwort, nicht mit dem des
/// Geräts.
///
/// Warum kein Fingerabdruck und keine Geräte-PIN: die entsperren das Gerät,
/// nicht die Akte. Wer die Geräte-PIN kennt — Familie, ein Blick über die
/// Schulter — käme damit auch an die Mitgliederdaten. Ein eigenes Passwort ist
/// ein zweiter, davon unabhängiger Riegel. Entscheidung des Users, 22.08.2026.
///
/// ⚠️ **Die Zeit wird an der Uhr gemessen, nicht heruntergezählt.** Das ist der
/// Kern: ein `Timer` läuft nicht weiter, wenn Android die App einfriert oder
/// der Rechner schlafen geht. Wer die Restzeit mitzählt, hat nach acht Stunden
/// Schlaf eine App, die noch elf Minuten übrig zu haben glaubt. Gemerkt wird
/// der **Zeitpunkt** der letzten Bedienung; die verstrichene Zeit wird bei
/// jedem Blick neu ausgerechnet, auch beim Zurückkehren aus dem Hintergrund.
class AppSperreService extends ChangeNotifier {
  AppSperreService._();
  static final AppSperreService _i = AppSperreService._();
  factory AppSperreService() => _i;

  /// Nach dieser Zeit ohne Bedienung wird gesperrt.
  static const Duration leerlauf = Duration(minutes: 15);

  /// So lange vorher erscheint der Hinweis mit dem Countdown.
  static const Duration warnungAb = Duration(minutes: 1);

  /// Bedienung wird höchstens so oft vermerkt. Ohne diese Bremse liefe bei
  /// jeder Fingerbewegung Arbeit mit — eine Bildlaufgeste erzeugt hunderte
  /// Zeigerereignisse in wenigen Sekunden.
  static const Duration _entprellung = Duration(seconds: 2);

  static const String _schluesselPasswort = 'app_sperre_v1';
  static const String _schluesselFehler = 'app_sperre_fehler_v1';

  final SecureStore _speicher = SecureStore();
  final LoggerService _log = LoggerService();

  DateTime _letzteBedienung = DateTime.now();
  DateTime? _letzterVermerk;
  SperrePasswort? _abgelegt;
  bool _gesperrt = false;
  bool _geladen = false;
  int _fehlversuche = 0;
  DateTime? _sperrfristBis;
  Timer? _takt;

  bool get istEingerichtet => _abgelegt != null;
  bool get istGesperrt => _gesperrt;
  bool get istGeladen => _geladen;
  int get fehlversuche => _fehlversuche;

  /// Verbleibende Zeit bis zur Sperre, an der Uhr gerechnet.
  Duration get verbleibend {
    final rest = leerlauf - DateTime.now().difference(_letzteBedienung);
    return rest.isNegative ? Duration.zero : rest;
  }

  /// Die letzte Minute läuft — die Oberfläche zeigt den Hinweis.
  bool get warntGleich =>
      istEingerichtet && !_gesperrt && verbleibend <= warnungAb;

  /// Wie lange die Eingabe noch gesperrt ist (nach zu vielen Fehlversuchen).
  Duration get wartezeitRest {
    final bis = _sperrfristBis;
    if (bis == null) return Duration.zero;
    final rest = bis.difference(DateTime.now());
    return rest.isNegative ? Duration.zero : rest;
  }

  // ── Einrichtung ───────────────────────────────────────────────────────────

  Future<void> laden() async {
    try {
      _abgelegt = SperrePasswort.ausJson(
          await _speicher.read(key: _schluesselPasswort));
      final f = await _speicher.read(key: _schluesselFehler);
      if (f != null) {
        final teile = f.split('|');
        _fehlversuche = int.tryParse(teile.first) ?? 0;
        if (teile.length > 1) {
          _sperrfristBis = DateTime.tryParse(teile[1]);
        }
      }
    } catch (e) {
      _log.warning('Sperre: Zustand nicht lesbar: $e', tag: 'SPERRE');
      _abgelegt = null;
    }
    // Beim Start gesperrt, sobald ein Passwort gesetzt ist — das ist die
    // Vorgabe „beim Öffnen fragen".
    _gesperrt = _abgelegt != null;
    _geladen = true;
    _letzteBedienung = DateTime.now();
    notifyListeners();
  }

  Future<void> passwortSetzen(String passwort) async {
    final neu = await sperrePasswortErzeugen(passwort);
    await _speicher.write(key: _schluesselPasswort, value: neu.alsJson());
    _abgelegt = neu;
    _gesperrt = false;
    await _fehlerZuruecksetzen();
    vermerkeBedienung(erzwingen: true);
    notifyListeners();
  }

  /// Prüft das Passwort und entsperrt bei Erfolg.
  Future<bool> entsperren(String passwort) async {
    if (wartezeitRest > Duration.zero) return false;
    final ok = await sperrePasswortPruefen(_abgelegt, passwort);
    if (!ok) {
      _fehlversuche++;
      final warten = sperreWartezeit(_fehlversuche);
      _sperrfristBis =
          warten > Duration.zero ? DateTime.now().add(warten) : null;
      await _fehlerSichern();
      _log.warning('Sperre: Fehlversuch $_fehlversuche', tag: 'SPERRE');
      notifyListeners();
      return false;
    }
    _gesperrt = false;
    await _fehlerZuruecksetzen();
    vermerkeBedienung(erzwingen: true);
    notifyListeners();
    return true;
  }

  /// Wird beim Abmelden gerufen — das Passwort gehört zu diesem Konto.
  Future<void> zuruecksetzen() async {
    try {
      await _speicher.delete(key: _schluesselPasswort);
      await _speicher.delete(key: _schluesselFehler);
    } catch (_) {}
    _abgelegt = null;
    _gesperrt = false;
    _fehlversuche = 0;
    _sperrfristBis = null;
    notifyListeners();
  }

  // ── Betrieb ───────────────────────────────────────────────────────────────

  /// Vermerkt Bedienung. Entprellt, ausser bei [erzwingen].
  void vermerkeBedienung({bool erzwingen = false}) {
    final jetzt = DateTime.now();
    if (!erzwingen &&
        _letzterVermerk != null &&
        jetzt.difference(_letzterVermerk!) < _entprellung) {
      return;
    }
    _letzterVermerk = jetzt;
    final warnteVorher = warntGleich;
    _letzteBedienung = jetzt;
    // Nur melden, wenn sich für die Oberfläche etwas ändert — sonst baute jede
    // Berührung den Hinweisstreifen neu auf.
    if (warnteVorher) notifyListeners();
  }

  void sperren() {
    if (!istEingerichtet || _gesperrt) return;
    _gesperrt = true;
    notifyListeners();
  }

  static const MethodChannel _keyguardKanal =
      MethodChannel('de.icd360sev.vorsitzer/keyguard');

  /// Beim Zurückkehren in den Vordergrund: erscheint die App ÜBER dem
  /// System-Sperrbildschirm (Anruf-Fullscreen-Intent, Tipp auf eine
  /// Benachrichtigung auf dem Sperrbildschirm), muss die App-Sperre SOFORT
  /// greifen — unabhängig von den 15 Minuten. Sonst wären Mitgliedsdaten ohne
  /// Entsperren des Geräts sichtbar (`showWhenLocked` gilt für die ganze App).
  /// Ausnahme: ein laufendes/eingehendes Gespräch — sonst stünde die
  /// Passwortabfrage vor dem Anrufbildschirm.
  Future<void> ueberLockschirmPruefen() async {
    if (!Platform.isAndroid) return;
    if (!istEingerichtet || _gesperrt) return;
    bool geraetGesperrt;
    try {
      geraetGesperrt =
          await _keyguardKanal.invokeMethod<bool>('isKeyguardLocked') ?? false;
    } catch (_) {
      return; // ohne verlässliche Auskunft nicht sperren
    }
    if (sollUeberLockschirmSperren(geraetGesperrt)) sperren();
  }

  /// Reine Entscheidung, ohne Plattformkanal — dadurch prüfbar: sperren, wenn
  /// das Gerät gesperrt ist, ein Passwort gesetzt ist, noch nicht gesperrt
  /// wurde und gerade kein Gespräch läuft.
  @visibleForTesting
  bool sollUeberLockschirmSperren(bool geraetGesperrt) {
    if (!geraetGesperrt || !istEingerichtet || _gesperrt) return false;
    try {
      if (VoiceCallService().callState != CallState.idle) return false;
    } catch (_) {
      // Der Anrufdienst darf die Entscheidung nicht aufhalten.
    }
    return true;
  }

  /// Schaut auf die Uhr. Wird vom Takt und beim Zurückkehren aus dem
  /// Hintergrund gerufen.
  void pruefen() {
    if (!istEingerichtet || _gesperrt) return;

    // ⚠️ Ein laufendes Gespräch gilt als Bedienung. Sperrte die App mitten im
    // Gespräch, liefe der Ton weiter, aber niemand käme mehr an den
    // Auflegen-Knopf — man müsste sich erst anmelden, um das Gespräch zu
    // beenden, das man gerade führt.
    try {
      if (VoiceCallService().callState != CallState.idle) {
        vermerkeBedienung(erzwingen: true);
        return;
      }
    } catch (_) {
      // Der Anrufdienst darf die Sperre nicht aufhalten.
    }

    if (verbleibend == Duration.zero) {
      _log.info('Sperre: Leerlauf abgelaufen', tag: 'SPERRE');
      sperren();
      return;
    }
    // In der letzten Minute (und solange eine Wartestaffel läuft) muss die
    // Anzeige jede Sekunde nachziehen.
    if (warntGleich || wartezeitRest > Duration.zero) notifyListeners();
  }

  void taktStarten() {
    _takt?.cancel();
    // Eine Sekunde, damit die letzte Minute wirklich herunterzählt. Der Takt
    // rechnet nicht mit, er schaut nur auf die Uhr.
    _takt = Timer.periodic(const Duration(seconds: 1), (_) => pruefen());
  }

  void taktStoppen() {
    _takt?.cancel();
    _takt = null;
  }

  @override
  void dispose() {
    taktStoppen();
    super.dispose();
  }

  // ── Innereien ─────────────────────────────────────────────────────────────

  Future<void> _fehlerSichern() async {
    try {
      await _speicher.write(
        key: _schluesselFehler,
        value: '$_fehlversuche|${_sperrfristBis?.toIso8601String() ?? ''}',
      );
    } catch (_) {
      // Nicht schlimm: die Staffel gilt dann nur bis zum nächsten Start.
    }
  }

  Future<void> _fehlerZuruecksetzen() async {
    _fehlversuche = 0;
    _sperrfristBis = null;
    try {
      await _speicher.delete(key: _schluesselFehler);
    } catch (_) {}
  }
}
