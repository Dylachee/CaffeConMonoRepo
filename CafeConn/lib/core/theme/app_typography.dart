import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Design tokens — typography.
/// UI text = Inter (bundled). Numbers/prices/timers/quantities = JetBrains Mono.
/// `JetBrainsMono` falls back to Inter until the ttf is bundled in assets/fonts/.
class AppTypography {
  const AppTypography._();

  static const fontUI = 'Inter';
  static const fontMono = 'JetBrainsMono';
  static const List<String> _monoFallback = ['Inter'];

  static TextStyle h1({Color? color}) => TextStyle(
      fontFamily: fontUI,
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
      color: color ?? AppColors.ink);
  static TextStyle h2({Color? color}) => TextStyle(
      fontFamily: fontUI,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      color: color ?? AppColors.ink);
  static TextStyle h3({Color? color}) => TextStyle(
      fontFamily: fontUI,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: color ?? AppColors.ink);
  static TextStyle body({Color? color}) => TextStyle(
      fontFamily: fontUI,
      fontSize: 14.5,
      fontWeight: FontWeight.w400,
      color: color ?? AppColors.ink);
  static TextStyle bodySemi({Color? color}) => TextStyle(
      fontFamily: fontUI,
      fontSize: 14.5,
      fontWeight: FontWeight.w600,
      color: color ?? AppColors.ink);
  static TextStyle small({Color? color}) => TextStyle(
      fontFamily: fontUI,
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      color: color ?? AppColors.ink55);
  static TextStyle label({Color? color}) => TextStyle(
      fontFamily: fontUI,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
      color: color ?? AppColors.ink55);
  static TextStyle price({Color? color}) => TextStyle(
      fontFamily: fontMono,
      fontFamilyFallback: _monoFallback,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: color ?? AppColors.ink);
  static TextStyle timer({Color? color}) => TextStyle(
      fontFamily: fontMono,
      fontFamilyFallback: _monoFallback,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: color ?? AppColors.ink);
  static TextStyle mono(
          {Color? color, double size = 14, FontWeight weight = FontWeight.w600}) =>
      TextStyle(
          fontFamily: fontMono,
          fontFamilyFallback: _monoFallback,
          fontSize: size,
          fontWeight: weight,
          color: color ?? AppColors.ink);
}
