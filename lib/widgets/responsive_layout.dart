import 'package:flutter/material.dart';
import '../services/platform_service.dart';

/// Responsive Layout Widget - adapts UI for desktop and mobile
/// Breakpoints:
/// - Mobile: < 600px width
/// - Tablet: 600px - 900px
/// - Desktop: > 900px
class ResponsiveLayout extends StatelessWidget {
  /// Widget to show on mobile devices (< 600px or mobile platform)
  final Widget mobile;

  /// Widget to show on tablet devices (600-900px) - optional, falls back to mobile
  final Widget? tablet;

  /// Widget to show on desktop devices (> 900px or desktop platform)
  final Widget desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  /// Check if current layout should be mobile
  static bool isMobile(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width < 600 || PlatformService.isMobile;
  }

  /// Breite, unterhalb derer die Oberfläche für ein Telefon eingerichtet wird.
  ///
  /// ⚠️ Bewusst nach **gemessener Breite**, nicht nach Plattform: [isMobile]
  /// ist auf dem Samsung Tab A11 ebenfalls true (es prüft zusätzlich
  /// `PlatformService.isMobile`), dort sind aber 800 dp da und die
  /// Telefon-Notlösungen wären eine Verschlechterung.
  ///
  /// Die Geräte, um die es geht:
  /// * Pixel 8      1080×2400 px, densityDpi 420 → **411 × 914 dp**
  /// * Pixel 8 Pro  1344×2992 px, densityDpi 480 → **448 × 997 dp**
  /// * Tab A11                                   → 800 × 1280 dp
  static const double telefonGrenze = 600;

  /// True auf Telefonbreite — Pixel 8 und Pixel 8 Pro liegen beide darunter.
  static bool istTelefon(BuildContext context) =>
      MediaQuery.of(context).size.width < telefonGrenze;

  /// Check if current layout should be tablet
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 900 && !PlatformService.isMobile;
  }

  /// Check if current layout should be desktop
  static bool isDesktop(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 900 || (PlatformService.isDesktop && width >= 600);
  }

  /// Get responsive value based on current layout
  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet ?? mobile;
    return mobile;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    // Force mobile layout on mobile platforms regardless of screen size
    if (PlatformService.isMobile) {
      if (width >= 600 && tablet != null) {
        return tablet!;
      }
      return mobile;
    }

    // Desktop platforms - use screen width breakpoints
    if (width >= 900) {
      return desktop;
    } else if (width >= 600 && tablet != null) {
      return tablet!;
    }
    return mobile;
  }
}

/// Responsive padding helper
class ResponsivePadding extends StatelessWidget {
  final Widget child;
  final EdgeInsets mobilePadding;
  final EdgeInsets? tabletPadding;
  final EdgeInsets desktopPadding;

  const ResponsivePadding({
    super.key,
    required this.child,
    this.mobilePadding = const EdgeInsets.all(8),
    this.tabletPadding,
    this.desktopPadding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveLayout.responsiveValue(
      context,
      mobile: mobilePadding,
      tablet: tabletPadding,
      desktop: desktopPadding,
    );
    return Padding(padding: padding, child: child);
  }
}

/// Responsive sized box helper
class ResponsiveSizedBox extends StatelessWidget {
  final double? mobileWidth;
  final double? mobileHeight;
  final double? tabletWidth;
  final double? tabletHeight;
  final double? desktopWidth;
  final double? desktopHeight;
  final Widget? child;

  const ResponsiveSizedBox({
    super.key,
    this.mobileWidth,
    this.mobileHeight,
    this.tabletWidth,
    this.tabletHeight,
    this.desktopWidth,
    this.desktopHeight,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final width = ResponsiveLayout.responsiveValue(
      context,
      mobile: mobileWidth,
      tablet: tabletWidth,
      desktop: desktopWidth,
    );
    final height = ResponsiveLayout.responsiveValue(
      context,
      mobile: mobileHeight,
      tablet: tabletHeight,
      desktop: desktopHeight,
    );
    return SizedBox(width: width, height: height, child: child);
  }
}

/// Responsive dialog wrapper - adjusts dialog width for different screen sizes
class ResponsiveDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget>? actions;
  final double mobileWidthFactor;
  final double desktopWidth;

  const ResponsiveDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
    this.mobileWidthFactor = 0.9,
    this.desktopWidth = 600,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = ResponsiveLayout.isMobile(context);
    final telefon = ResponsiveLayout.istTelefon(context);

    final dialogWidth = isMobile
        ? screenWidth * mobileWidthFactor
        : desktopWidth.clamp(400.0, screenWidth * 0.8);

    return Dialog(
      // ⚠️ Ohne das war `mobileWidthFactor` wirkungslos: der Standardrand des
      // Dialogs nimmt 2 × 40 dp, auf einem 448-dp-Telefon blieben 368 statt
      // der angeforderten 403. Gemessen, nicht geschätzt — der Test
      // `aufloesungswechsel_test.dart` hält beide Zahlen fest.
      insetPadding: telefon
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 16)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: content,
              ),
            ),
            // Actions
            if (actions != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Extension for easy responsive values
extension ResponsiveContext on BuildContext {
  bool get isMobile => ResponsiveLayout.isMobile(this);
  bool get isTablet => ResponsiveLayout.isTablet(this);
  bool get isDesktop => ResponsiveLayout.isDesktop(this);

  T responsive<T>({
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    return ResponsiveLayout.responsiveValue(
      this,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }
}
