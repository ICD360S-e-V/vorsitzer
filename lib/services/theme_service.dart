import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hell / Dunkel / System — gespeichert auf dem Gerät.
///
/// Bewusst ein [ValueNotifier] und kein Singleton mit `setState`: die
/// [MaterialApp] hört über einen [ValueListenableBuilder] zu, damit ein
/// Moduswechsel den ganzen Baum neu aufbaut und die Tokens in `F` (siehe
/// `utils/app_farben.dart`) gleich mitgezogen werden.
///
/// ⚠️ Voreinstellung ist [ThemeMode.system]. Wer nichts einstellt, bekommt
/// nachts das dunkle Erscheinungsbild seines Geräts — genau wie auf
/// `icd360s.de`, das dieselbe Logik fährt.
class ThemeService {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  static const _schluessel = 'app_theme_mode';

  final ValueNotifier<ThemeMode> modus = ValueNotifier(ThemeMode.system);

  /// Liest die gespeicherte Wahl. Fehlt sie oder ist sie unlesbar, bleibt es
  /// bei [ThemeMode.system] — ein kaputter Eintrag darf die Anwendung nicht
  /// an einem Modus festnageln.
  Future<void> laden() async {
    try {
      final p = await SharedPreferences.getInstance();
      modus.value = _ausText(p.getString(_schluessel));
    } catch (_) {
      modus.value = ThemeMode.system;
    }
  }

  Future<void> setzen(ThemeMode neu) async {
    if (modus.value == neu) return;
    modus.value = neu;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_schluessel, _alsText(neu));
    } catch (_) {
      // Die Anzeige hat bereits umgeschaltet. Dass das Speichern scheitert,
      // darf den Wechsel nicht rückgängig machen — beim nächsten Start steht
      // dann eben wieder die Voreinstellung.
    }
  }

  /// Reihum: System → Hell → Dunkel → System.
  ///
  /// ⚠️ Die Reihenfolge beginnt bei System, damit der erste Druck auf den Knopf
  /// eine *sichtbare* Wirkung hat. Ginge es von System nach Hell, während das
  /// Gerät ohnehin hell steht, würde sich nichts ändern und der Knopf wirkte
  /// kaputt.
  Future<void> weiterschalten(Brightness aktuelleHelligkeit) async {
    switch (modus.value) {
      case ThemeMode.system:
        await setzen(aktuelleHelligkeit == Brightness.dark
            ? ThemeMode.light
            : ThemeMode.dark);
      case ThemeMode.light:
        await setzen(ThemeMode.dark);
      case ThemeMode.dark:
        await setzen(ThemeMode.system);
    }
  }

  static ThemeMode _ausText(String? t) => switch (t) {
        'hell' => ThemeMode.light,
        'dunkel' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _alsText(ThemeMode m) => switch (m) {
        ThemeMode.light => 'hell',
        ThemeMode.dark => 'dunkel',
        ThemeMode.system => 'system',
      };

  static String bezeichnung(ThemeMode m) => switch (m) {
        ThemeMode.light => 'Hell',
        ThemeMode.dark => 'Dunkel',
        ThemeMode.system => 'System',
      };

  static IconData symbol(ThemeMode m) => switch (m) {
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
        ThemeMode.system => Icons.brightness_auto_outlined,
      };
}
