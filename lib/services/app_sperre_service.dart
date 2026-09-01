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
/// ⚠️ **Es gibt KEINE Sperre nach Leerlauf mehr.** Bis zum 02.09.2026 sperrte
/// die App nach 15 Minuten ohne Bedienung. Entscheidung des Users: das hat im
/// Alltag mitten in der Arbeit nach dem Passwort gefragt und war damit vor
/// allem eines — lästig. Gesperrt wird jetzt nur noch aus drei Anlässen, und
/// alle drei sind für den Bedienenden vorhersehbar:
///
///  1. **Die App wurde geschlossen und neu gestartet.** [laden] setzt den
///     gesperrten Zustand, sobald ein Passwort abgelegt ist. Das ist der Fall,
///     der wirklich zählt: ein gefundenes oder gestohlenes Gerät.
///  2. **Der Schloss-Knopf in der Kopfzeile** ([sperren]) — für den Moment, in
///     dem man das Gerät aus der Hand gibt.
///  3. **Die App kommt über dem System-Sperrbildschirm nach vorn**
///     ([ueberLockschirmPruefen]) — sonst wären Mitgliedsdaten ohne Entsperren
///     des Geräts sichtbar, weil `showWhenLocked` für die ganze App gilt.
///
/// ⚠️ Wer hier je wieder eine Leerlaufsperre einbaut, braucht auch den ganzen
/// Apparat zurück, den es dafür brauchte: Zeigerlauscher und Tastaturhaken über
/// dem gesamten Baum, eine Entprellung, einen Sekundentakt und einen
/// Hinweisstreifen. Und die Zeit müsste **an der Uhr** gemessen werden, nicht
/// heruntergezählt — ein `Timer` läuft nicht weiter, wenn Android die App
/// einfriert oder der Rechner schlafen geht.
class AppSperreService extends ChangeNotifier {
  AppSperreService._();
  static final AppSperreService _i = AppSperreService._();
  factory AppSperreService() => _i;

  static const String _schluesselPasswort = 'app_sperre_v1';
  static const String _schluesselFehler = 'app_sperre_fehler_v1';

  final SecureStore _speicher = SecureStore();
  final LoggerService _log = LoggerService();

  SperrePasswort? _abgelegt;
  bool _gesperrt = false;
  bool _geladen = false;
  int _fehlversuche = 0;
  DateTime? _sperrfristBis;

  bool get istEingerichtet => _abgelegt != null;
  bool get istGesperrt => _gesperrt;
  bool get istGeladen => _geladen;
  int get fehlversuche => _fehlversuche;

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
    notifyListeners();
  }

  Future<void> passwortSetzen(String passwort) async {
    final neu = await sperrePasswortErzeugen(passwort);
    await _speicher.write(key: _schluesselPasswort, value: neu.alsJson());
    _abgelegt = neu;
    _gesperrt = false;
    await _fehlerZuruecksetzen();
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

  /// Sperrt von Hand — der Schloss-Knopf in der Kopfzeile.
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
  /// greifen. Sonst wären Mitgliedsdaten ohne Entsperren des Geräts sichtbar
  /// (`showWhenLocked` gilt für die ganze App).
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
