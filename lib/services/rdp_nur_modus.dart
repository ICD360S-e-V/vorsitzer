import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'logger_service.dart';

final _log = LoggerService();

/// „Nur Remote Desktop" — Kiosk-Betrieb für ein Gerät, das nichts anderes tun
/// soll als sich auf den Bürorechner zu schalten.
///
/// WOFÜR DAS DA IST
/// Das Pixel liegt neben dem Schreibtisch und wird nur für eines benutzt: einmal
/// auf den Rechner tippen und im Remote Desktop landen. Die dreißig Module des
/// Vorsitzer-Panels sind darauf nicht nur unnötig, sondern hinderlich — auf
/// 448 dp Breite ist die halbe Oberfläche ein Suchspiel, und die Abfragetakte
/// von Chat, Wetter, ÖPNV und Abzeichen ziehen den Akku leer, während das
/// Telefon eigentlich nur wartet.
///
/// ⚠️ WAS DIESER MODUS NICHT ABSCHALTET
/// Die Hintergrundrollen des Geräts laufen weiter — allen voran die **Fernwahl**
/// ([AnrufGatewayService]): ein Klick auf eine Rufnummer am Linux-Rechner lässt
/// genau dieses Telefon wählen. Würde der Kiosk-Modus sie mitnehmen, bliebe der
/// Schalter in den Einstellungen auf „an", und der Klick am Rechner liefe ins
/// Leere — ohne Fehler, ohne Hinweis. Deshalb startet [RdpOnlyScreen] denselben
/// Hintergrund-Block wie das Dashboard.
///
/// ⚠️ UMKEHRBAR, IMMER
/// Der Modus ist ein Schalter pro Gerät, kein fest verdrahtetes Modell. Auf
/// einem Google Pixel steht er beim ersten Start von allein auf „an" (das ist
/// das Gerät, um das es geht), aber jede Entscheidung von Hand gewinnt danach
/// dauerhaft — sonst wäre ein Telefon, dessen RDP-Ziel sich geändert hat, ein
/// Telefon, das sich nicht mehr selbst reparieren kann.
class RdpNurModus {
  RdpNurModus._();

  static const _kAn = 'rdp.nur_modus_an';

  /// true = der Wert stammt aus der Geräteerkennung, nicht vom Benutzer.
  /// Nur für die Anzeige in den Einstellungen; die Wirkung ist dieselbe.
  static const _kAuto = 'rdp.nur_modus_automatisch';

  /// Gelesener Zustand, damit die Weiche nach dem Login nicht bei jedem
  /// Bildschirmwechsel erneut auf die Platte muss.
  static bool? _cache;

  /// Nur für Tests: verwirft den gemerkten Zustand.
  static void cacheLeeren() => _cache = null;

  /// Soll dieses Gerät ausschließlich den Remote Desktop zeigen?
  ///
  /// Beim allerersten Aufruf ohne gespeicherten Wert entscheidet die
  /// Geräteerkennung und das Ergebnis wird festgeschrieben — danach läuft die
  /// Erkennung nie wieder, ein einmal umgelegter Schalter bleibt also liegen.
  static Future<bool> istAn() async {
    final c = _cache;
    if (c != null) return c;

    final sp = await SharedPreferences.getInstance();
    final gespeichert = sp.getBool(_kAn);
    if (gespeichert != null) {
      _cache = gespeichert;
      return gespeichert;
    }

    final auto = await istPixel();
    await sp.setBool(_kAn, auto);
    await sp.setBool(_kAuto, auto);
    _cache = auto;
    if (auto) {
      _log.info('Nur-Remote-Desktop automatisch eingeschaltet (Pixel erkannt)',
          tag: 'RDP_ONLY');
    }
    return auto;
  }

  /// Legt den Schalter um. Eine Entscheidung von Hand überschreibt die
  /// Erkennung endgültig.
  static Future<void> setzen(bool an) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kAn, an);
    await sp.setBool(_kAuto, false);
    _cache = an;
    _log.info('Nur-Remote-Desktop ${an ? 'ein' : 'aus'}geschaltet', tag: 'RDP_ONLY');
  }

  /// Wurde der aktuelle Zustand von der Erkennung gesetzt und seither nicht
  /// angefasst? Nur ein Hinweistext, keine Logik hängt daran.
  static Future<bool> istAutomatisch() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kAuto) ?? false;
  }

  /// Google Pixel? Nur die Vorgabe beim ersten Start.
  ///
  /// ⚠️ `Build.BRAND` und `Build.MODEL` sind auf Android setzbar (auf
  /// GrapheneOS wird genau davon Gebrauch gemacht). Das ist hier unerheblich —
  /// die Erkennung ist eine Bequemlichkeit, keine Zugangsprüfung, und wer sie
  /// nicht will, legt den Schalter um.
  static Future<bool> istPixel() async {
    if (!Platform.isAndroid) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final marke = info.brand.toLowerCase().trim();
      final hersteller = info.manufacturer.toLowerCase().trim();
      final modell = info.model.toLowerCase().trim();
      final vonGoogle = marke == 'google' || hersteller == 'google';
      return vonGoogle && modell.startsWith('pixel');
    } catch (e) {
      // Ein Gerät, das seine eigene Modellbezeichnung nicht herausgibt, wird
      // nicht geraten — es bekommt die vollständige App.
      _log.warning('Geräteerkennung fehlgeschlagen: $e', tag: 'RDP_ONLY');
      return false;
    }
  }
}
