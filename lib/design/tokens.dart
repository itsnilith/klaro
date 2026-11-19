import 'package:flutter/material.dart';

/// Klaro design tokens — calibrated directly to the CourseBox primary visual
/// reference: bright cool-alabaster canvas (#F6F7FB), pure white elevated cards
/// with soft ambient shadows, deep carbon primary surfaces (#18181B) for the
/// floating navigation pill and primary action buttons, and clean geometric
/// sans-serif typography (Inter) throughout.
@immutable
class MColors extends ThemeExtension<MColors> {
  const MColors({
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceSunken,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.line,
    required this.lineStrong,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.amber,
    required this.amberSoft,
    required this.danger,
    required this.dangerSoft,
    required this.success,
    required this.shadow,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceSunken;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color line;
  final Color lineStrong;
  final Color accent;
  final Color accentInk;
  final Color accentSoft;
  final Color amber;
  final Color amberSoft;
  final Color danger;
  final Color dangerSoft;
  final Color success;
  final Color shadow;

  static const light = MColors(
    canvas: Color(0xFFF6F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF9FAFC),
    surfaceSunken: Color(0xFFEDEEF3),
    ink: Color(0xFF161618),
    inkMuted: Color(0xFF6B7280),
    inkFaint: Color(0xFF9CA3AF),
    line: Color(0xFFEAECEF),
    lineStrong: Color(0xFFD5D8E0),
    accent: Color(0xFF18181B),
    accentInk: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFECEDF2),
    amber: Color(0xFFD97706),
    amberSoft: Color(0xFFFEF3C7),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0xFFFEE2E2),
    success: Color(0xFF16A34A),
    shadow: Color(0x0D0F172A),
  );

  static const dark = MColors(
    canvas: Color(0xFF0E1014),
    surface: Color(0xFF171A20),
    surfaceAlt: Color(0xFF1E222A),
    surfaceSunken: Color(0xFF12151B),
    ink: Color(0xFFF3F4F6),
    inkMuted: Color(0xFF9CA3AF),
    inkFaint: Color(0xFF6B7280),
    line: Color(0xFF262A34),
    lineStrong: Color(0xFF373D4B),
    accent: Color(0xFFF3F4F6),
    accentInk: Color(0xFF111318),
    accentSoft: Color(0xFF252A34),
    amber: Color(0xFFF59E0B),
    amberSoft: Color(0xFF3B2A14),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0xFF3B1A1A),
    success: Color(0xFF4ADE80),
    shadow: Color(0x66000000),
  );

  @override
  MColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceSunken,
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? line,
    Color? lineStrong,
    Color? accent,
    Color? accentInk,
    Color? accentSoft,
    Color? amber,
    Color? amberSoft,
    Color? danger,
    Color? dangerSoft,
    Color? success,
    Color? shadow,
  }) {
    return MColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkFaint: inkFaint ?? this.inkFaint,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      accentSoft: accentSoft ?? this.accentSoft,
      amber: amber ?? this.amber,
      amberSoft: amberSoft ?? this.amberSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      success: success ?? this.success,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  MColors lerp(ThemeExtension<MColors>? other, double t) {
    if (other is! MColors) return this;
    return MColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      amberSoft: Color.lerp(amberSoft, other.amberSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

class MSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x14 = 56;
  static const double x18 = 72;
}

class MRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 30;
  static const double pill = 999;
}

class MType {
  static const display = TextStyle(
    fontFamily: 'Inter',
    fontSize: 40,
    height: 1.12,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.1,
  );
  static const h1 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 26,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
  );
  static const h2 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );
  static const h3 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );
  static const body = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );
  static const bodyStrong = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w600,
  );
  static const small = TextStyle(
    fontFamily: 'Inter',
    fontSize: 12.5,
    height: 1.4,
    fontWeight: FontWeight.w400,
  );
  static const label = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11.5,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
  );
  static const mono = TextStyle(
    fontFamily: 'Consolas',
    fontSize: 13,
    height: 1.5,
  );
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? MColors.dark : MColors.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    splashFactory: InkSparkle.splashFactory,
  );
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.accentInk,
    primaryContainer: c.accentSoft,
    onPrimaryContainer: c.ink,
    secondary: c.amber,
    onSecondary: c.accentInk,
    secondaryContainer: c.amberSoft,
    onSecondaryContainer: c.ink,
    error: c.danger,
    onError: brightness == Brightness.dark ? c.canvas : Colors.white,
    errorContainer: c.dangerSoft,
    onErrorContainer: brightness == Brightness.dark ? c.danger : c.ink,
    surface: c.surface,
    onSurface: c.ink,
    surfaceContainerHighest: c.surfaceAlt,
    onSurfaceVariant: c.inkMuted,
    outline: c.line,
    outlineVariant: c.line,
    shadow: c.shadow,
    scrim: Colors.black54,
    inverseSurface: c.ink,
    onInverseSurface: c.surface,
    inversePrimary: c.accentSoft,
  );
  return base.copyWith(
    colorScheme: scheme,
    textTheme: base.textTheme.apply(
      bodyColor: c.ink,
      displayColor: c.ink,
      fontFamily: 'Inter',
    ),
    dividerColor: c.line,
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    extensions: [c],
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: BorderRadius.circular(MRadius.sm),
      ),
      textStyle: MType.small.copyWith(color: c.surface),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(8),
      radius: const Radius.circular(8),
      thumbColor: WidgetStateProperty.all(c.lineStrong),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      hintStyle: MType.body.copyWith(color: c.inkFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MRadius.md),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MRadius.md),
        borderSide: BorderSide(color: c.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MRadius.md),
        borderSide: BorderSide(color: c.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MRadius.md),
        borderSide: BorderSide(color: c.danger),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MRadius.xl),
        side: BorderSide(color: c.line),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: MType.body.copyWith(color: c.surface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MRadius.md),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: c.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MRadius.lg),
        side: BorderSide(color: c.line),
      ),
      textStyle: MType.small.copyWith(color: c.ink, fontSize: 12.5),
    ),
  );
}

extension MColorsX on BuildContext {
  MColors get c => Theme.of(this).extension<MColors>()!;
  TextTheme get t => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Shared elevation opacity preserves the calibrated light values while
  /// using stronger black shadows on dark surfaces, separating raised controls
  /// from the similarly dark canvas underneath them.
  Color elevationShadow(double lightAlpha, {required double darkAlpha}) {
    return c.shadow.withValues(alpha: isDark ? darkAlpha : lightAlpha);
  }
}
