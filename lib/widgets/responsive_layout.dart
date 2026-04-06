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

    final dialogWidth = isMobile
        ? screenWidth * mobileWidthFactor
        : desktopWidth.clamp(400.0, screenWidth * 0.8);

    return Dialog(
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
