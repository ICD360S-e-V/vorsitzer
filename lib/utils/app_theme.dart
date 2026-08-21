import 'dart:io';
import 'package:flutter/material.dart';
import 'app_farben.dart';

/// Die beiden Erscheinungsbilder der Anwendung.
///
/// ⚠️ Beide Themen werden **vollständig** gesetzt, nicht nur über die
/// [ColorScheme]. Der Grund ist gemessen: die Anwendung ruft an nur 69 Stellen
/// `Theme.of(context)` auf, aber tausendfach feste Farben. Alles, was das Thema
/// von sich aus einfärben kann — Karten, Dialoge, Eingabefelder, Trennlinien —
/// muss es hier auch tun, sonst bleiben genau die Widgets hell, die niemand
/// von Hand angefasst hat.
class AppTheme {
  AppTheme._();

  /// Markenblau des Vereins. In beiden Modi derselbe Ausgangspunkt — die Marke
  /// wechselt nicht mit der Tageszeit.
  static const saat = Color(0xFF4a90d9);

  /// ⚠️ Systemschrift je Plattform. Stand vorher direkt in `main.dart`; wird
  /// hier für beide Themen aus einer Quelle gesetzt, damit Hell und Dunkel
  /// nicht auseinanderlaufen.
  static String? get _schrift => Platform.isWindows ? 'Segoe UI' : null;

  static ThemeData get hell => _bauen(Brightness.light);
  static ThemeData get dunkel => _bauen(Brightness.dark);

  static ThemeData _bauen(Brightness helligkeit) {
    final dunkelModus = helligkeit == Brightness.dark;

    // ⚠️ `F` wird hier gesetzt, damit die Tokens beim Bauen des Themas bereits
    // zum richtigen Modus passen. `MaterialApp.builder` setzt es danach noch
    // einmal für den Widget-Baum — beides ist nötig: dieses hier greift, wenn
    // das Thema gebaut wird, jenes, wenn die Anwendung baut.
    F.istDunkel = dunkelModus;

    final schema = ColorScheme.fromSeed(
      seedColor: saat,
      brightness: helligkeit,
    );

    final basis = ThemeData(
      colorScheme: schema,
      useMaterial3: true,
      fontFamily: _schrift,
      brightness: helligkeit,
      scaffoldBackgroundColor: F.hintergrund,
      canvasColor: F.flaeche,
      dividerColor: F.rand,
      shadowColor: F.schatten,
    );

    return basis.copyWith(
      cardTheme: basis.cardTheme.copyWith(
        color: F.flaeche,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: basis.dialogTheme.copyWith(
        backgroundColor: F.flaeche,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: basis.popupMenuTheme.copyWith(
        color: F.flaeche,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: basis.bottomSheetTheme.copyWith(
        backgroundColor: F.flaeche,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: basis.drawerTheme.copyWith(
        backgroundColor: F.flaeche,
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: basis.listTileTheme.copyWith(
        textColor: F.textStark,
        iconColor: F.textSchwach,
      ),
      dividerTheme: basis.dividerTheme.copyWith(
        color: F.rand,
        space: basis.dividerTheme.space,
      ),
      // ⚠️ Die Kopfleiste bleibt in BEIDEN Modi dunkelblau (0xFF1a1a2e). Sie
      // war nie hell — sie im Dunkelmodus umzufärben hätte die einzige Fläche
      // verändert, die ohnehin schon stimmt, und die Marke mitgenommen.
      appBarTheme: basis.appBarTheme.copyWith(
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: basis.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: F.flaecheGedaempft,
        hintStyle: TextStyle(color: F.textLeise),
        labelStyle: TextStyle(color: F.textSchwach),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: F.rand),
          borderRadius: BorderRadius.circular(8),
        ),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: F.rand),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      // Im Dunkeln steht der Text der Anwendung auf `textStark`; im Hellen
      // bleibt es bei den Material-Vorgaben, damit sich am gewohnten Bild
      // nichts verschiebt.
      textTheme: dunkelModus
          ? basis.textTheme.apply(
              bodyColor: F.textStark,
              displayColor: F.textStark,
            )
          : basis.textTheme,
      iconTheme: basis.iconTheme.copyWith(color: F.textSchwach),
    );
  }
}
