import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppTheme {
  // Фон и поверхности (тёплые)
  static const bg = Color(0xFFF2EFE8);
  static const card = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFFBF9F4);
  static const surfaceSunken = Color(0xFFEBE6DB);

  // Текст
  static const ink = Color(0xFF1E1B16);
  static const ink2 = Color(0x8C1E1B16);
  static const ink3 = Color(0x661E1B16);
  static const separator = Color(0xFFE7E2D8);

  // Действия
  static const cta = Color(0xFF221F1A); // Эспрессо

  // Семантика статусов
  static const success = Color(0xFF3E9C63);
  static const warning = Color(0xFFE0823A); // Зона Кухня
  static const danger = Color(0xFFD9564A);
  static const bar = Color(0xFF3C7BCF); // Зона Бар
  static const gold = Color(0xFFB98A3C);

  // Статусы столов
  static const tFree = Color(0xFFB8B1A3);
  static const tOccupied = Color(0xFF5B86B0);

  // Тени
  static const shadowCard = BoxShadow(
      color: Color(0x1F2B2418),
      blurRadius: 22,
      spreadRadius: -14,
      offset: Offset(0, 10));
  static const shadowSheet = BoxShadow(
      color: Color(0x472B2418),
      blurRadius: 60,
      spreadRadius: -20,
      offset: Offset(0, 30));

  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(
        seedColor: cta,
        brightness: brightness,
        surface: isDark ? const Color(0xFF17150F) : bg,
      ),
      scaffoldBackgroundColor: isDark ? const Color(0xFF17150F) : bg,
    );
    return base.copyWith(
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      cardColor: isDark ? const Color(0xFF201C15) : card,
      dividerColor: isDark ? const Color(0xFF2E2920) : separator,
      textTheme: base.textTheme.copyWith(
        headlineLarge: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6),
        titleLarge: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4),
        titleMedium: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2),
        bodyLarge: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: 0),
        labelSmall: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w400,
            letterSpacing: 0),
      ),
    );
  }
}

// ===== TYPOGRAPHY SCALE =====
class T {
  // Screen-level titles — 30px bold espresso, matches design
  static const screenTitle = TextStyle(
      fontFamily: 'Inter', fontSize: 30, fontWeight: FontWeight.w700,
      letterSpacing: -0.6, color: AppTheme.ink);
  // Section headings inside screens
  static const sectionTitle = TextStyle(
      fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w700,
      color: AppTheme.ink);
  // Secondary subtitle — ink at 50% opacity (warm, not grey)
  static TextStyle get subtitle => const TextStyle(
      fontFamily: 'Inter', fontSize: 13.5, fontWeight: FontWeight.w400,
      color: Color(0x801E1B16));

  static const h1 = TextStyle(fontFamily: 'Inter', fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.ink);
  static const h2 = TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.ink);
  static const h3 = TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.ink);

  static const body = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w400, color: AppTheme.ink);
  static const bodySemi = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.ink);
  static const small = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w400, color: AppTheme.ink2);
  static const smallSemi = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.ink2);

  static const label = TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: AppTheme.ink2);

  // Numerals use JetBrains Mono per the design; falls back to Inter until the
  // JetBrainsMono ttf is bundled (see the commented fonts block in pubspec.yaml).
  static const price = TextStyle(fontFamily: 'JetBrainsMono', fontFamilyFallback: ['Inter'], fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.ink);
  static const priceSmall = TextStyle(fontFamily: 'JetBrainsMono', fontFamilyFallback: ['Inter'], fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.ink);
  static const timer = TextStyle(fontFamily: 'JetBrainsMono', fontFamilyFallback: ['Inter'], fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5);
}
