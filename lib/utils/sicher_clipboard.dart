import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Kopiert **geheime** Werte (2FA-Codes, Passwörter, Wiederherstellungs-/
/// Aktivierungscodes) in die Zwischenablage — abgesichert:
///
///  * **Android:** über einen nativen Kanal als `EXTRA_IS_SENSITIVE` markiert
///    (ab Android 13), damit Tastatur- und System-Vorschau (Gboard-Verlauf) den
///    Wert nicht im Klartext zeigen. Flutters [Clipboard.setData] kann dieses
///    Flag nicht setzen; auf anderen Plattformen fällt es auf setData zurück.
///  * **Auto-Löschen:** nach [ttl] wird die Zwischenablage geleert, damit ein
///    Code/Passwort nicht minutenlang mitlesbar bleibt.
///
/// Bewusst wird das Kopieren NICHT unterbunden (OWASP hat diese Forderung
/// zurückgezogen — es zerstört die Nutzbarkeit mit Passwort-Managern); es wird
/// nur abgesichert. Für nicht-geheime Werte (Adresse, Telefon, URL) weiter
/// [Clipboard.setData] bzw. `ClipboardHelper` verwenden.
class SicherClipboard {
  SicherClipboard._();

  static const MethodChannel _kanal =
      MethodChannel('de.icd360sev.vorsitzer/clipboard');

  static const Duration standardTtl = Duration(seconds: 30);

  static Timer? _loeschTimer;

  /// Kopiert [text] als geheim und leert die Zwischenablage nach [ttl].
  static Future<void> kopiere(String text,
      {Duration ttl = standardTtl}) async {
    var nativ = false;
    if (Platform.isAndroid) {
      try {
        final ok = await _kanal.invokeMethod<bool>('copySensitive', {'text': text});
        nativ = ok == true;
      } catch (_) {
        nativ = false;
      }
    }
    if (!nativ) {
      await Clipboard.setData(ClipboardData(text: text));
    }
    _loeschTimer?.cancel();
    _loeschTimer = Timer(ttl, leere);
  }

  /// Leert die Zwischenablage sofort (z. B. wenn der geheime Vorgang fertig ist).
  static Future<void> leere() async {
    _loeschTimer?.cancel();
    _loeschTimer = null;
    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {}
  }
}
