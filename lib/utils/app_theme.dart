import 'dart:io';
import 'package:flutter/material.dart';
import 'app_farben.dart';

/// Die beiden Erscheinungsbilder der Anwendung.
///
/// ⚠️ **Der Hellmodus ist Zeile für Zeile das alte Thema.** Diese Änderung
/// fügt einen Dunkelmodus HINZU; sie gestaltet den Hellmodus nicht um. Der
/// erste Anlauf hat genau das getan, ohne es zu sagen: `scaffoldBackgroundColor`
/// und die Flächen wurden für beide Modi gesetzt, und damit wurde aus dem von
/// Material 3 aus der Markenfarbe abgeleiteten Untergrund `(248, 249, 255)`
/// ein neutrales `(245, 245, 245)` — auf jedem Bildschirm. Aufgefallen ist es
/// erst bei einem Bildvergleich gegen `origin/main`; im PR stand da schon das
/// Gegenteil.
///
/// Alle Flächen-, Trenner- und Eingabefeld-Vorgaben gelten deshalb **nur im
/// Dunkelmodus**. Sie sind dort nötig, weil die Anwendung nur an 69 Stellen
/// `Theme.of(context)` fragt: was niemand von Hand angefasst hat, bliebe sonst
/// hell.
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

    // ⚠️ `F` wird hier nur VORÜBERGEHEND umgelegt und danach zurückgestellt.
    // Der erste Anlauf hat den Wert einfach gesetzt und stehen lassen — und
    // weil `MaterialApp` in jedem Aufbau BEIDE Themen auswertet, gewann immer
    // das zuletzt gebaute (`darkTheme`). Ergebnis: `F.istDunkel` stand auch im
    // Hellmodus auf `true`. Gemessen in einem Versuch, nicht überlegt: eine
    // Fläche, die nur `F.flaeche` liest, blieb beim Umschalten weiss, während
    // die Material-Farben längst dunkel waren.
    //
    // Einzige Instanz, die den Wert dauerhaft setzt, ist `MaterialApp.builder`.
    final vorher = F.istDunkel;
    F.istDunkel = dunkelModus;

    final schema = ColorScheme.fromSeed(
      seedColor: saat,
      brightness: helligkeit,
    );

    // ⚠️ Das ist WÖRTLICH das alte Thema aus `main.dart`. Im Hellmodus wird
    // es unverändert zurückgegeben — kein zusätzliches Feld, keine Fläche,
    // kein Trenner. Nur so bleibt das gewohnte Bild Pixel für Pixel gleich.
    final basis = ThemeData(
      colorScheme: schema,
      useMaterial3: true,
      fontFamily: _schrift,
    );
    if (!dunkelModus) {
      F.istDunkel = vorher;
      return basis;
    }

    final thema = basis
        .copyWith(
          scaffoldBackgroundColor: F.hintergrund,
          canvasColor: F.flaeche,
          dividerColor: F.rand,
          shadowColor: F.schatten,
        )
        .copyWith(
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
      textTheme: basis.textTheme.apply(
        bodyColor: F.textStark,
        displayColor: F.textStark,
      ),
      iconTheme: basis.iconTheme.copyWith(color: F.textSchwach),
    );

    F.istDunkel = vorher;
    return thema;
  }
}
