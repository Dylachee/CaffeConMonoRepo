/// Pure-Dart color helpers for the storefront theme editor: hex parsing,
/// WCAG contrast, and deriving accent-deep / accent-soft from one accent
/// color in HSL space. No Flutter imports — unit-testable as plain Dart.
library;

import 'dart:math' as math;

/// '#RRGGBB' → (r, g, b) or null when malformed.
(int, int, int)? rgbFromHex(String hex) {
  final h = hex.replaceAll('#', '').trim();
  if (h.length != 6) return null;
  final value = int.tryParse(h, radix: 16);
  if (value == null) return null;
  return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF);
}

bool isValidHex(String hex) => rgbFromHex(hex) != null;

String hexFromRgb(int r, int g, int b) {
  String two(int v) => v.clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(r)}${two(g)}${two(b)}';
}

/// WCAG relative luminance of an sRGB color (0..1).
double relativeLuminance(String hex) {
  final rgb = rgbFromHex(hex);
  if (rgb == null) return 0;
  double channel(int v) {
    final c = v / 255.0;
    return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(rgb.$1) +
      0.7152 * channel(rgb.$2) +
      0.0722 * channel(rgb.$3);
}

/// WCAG contrast ratio between two colors (1..21).
double contrastRatio(String hexA, String hexB) {
  final la = relativeLuminance(hexA);
  final lb = relativeLuminance(hexB);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// WCAG AA for normal body text.
bool meetsWcagAA(String foreground, String background) =>
    contrastRatio(foreground, background) >= 4.5;

// --- HSL round-trip ----------------------------------------------------------

(double, double, double) _rgbToHsl(int r, int g, int b) {
  final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
  final maxC = math.max(rf, math.max(gf, bf));
  final minC = math.min(rf, math.min(gf, bf));
  final l = (maxC + minC) / 2;
  if (maxC == minC) return (0, 0, l);
  final d = maxC - minC;
  final s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC);
  double h;
  if (maxC == rf) {
    h = (gf - bf) / d + (gf < bf ? 6 : 0);
  } else if (maxC == gf) {
    h = (bf - rf) / d + 2;
  } else {
    h = (rf - gf) / d + 4;
  }
  return (h / 6, s, l);
}

double _hueToRgb(double p, double q, double t) {
  var tt = t;
  if (tt < 0) tt += 1;
  if (tt > 1) tt -= 1;
  if (tt < 1 / 6) return p + (q - p) * 6 * tt;
  if (tt < 1 / 2) return q;
  if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
  return p;
}

(int, int, int) _hslToRgb(double h, double s, double l) {
  if (s == 0) {
    final v = (l * 255).round();
    return (v, v, v);
  }
  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;
  return (
    (_hueToRgb(p, q, h + 1 / 3) * 255).round(),
    (_hueToRgb(p, q, h) * 255).round(),
    (_hueToRgb(p, q, h - 1 / 3) * 255).round(),
  );
}

String _withHsl(String hex, {double? saturation, double? lightness}) {
  final rgb = rgbFromHex(hex);
  if (rgb == null) return hex;
  final (h, s, l) = _rgbToHsl(rgb.$1, rgb.$2, rgb.$3);
  final (r, g, b) = _hslToRgb(
    h,
    (saturation ?? s).clamp(0.0, 1.0),
    (lightness ?? l).clamp(0.0, 1.0),
  );
  return hexFromRgb(r, g, b);
}

/// Derive the two companion accents from one accent color, in HSL:
///   deep — same hue, darker and slightly more saturated (buttons' text/deep
///          accents, must read on light surfaces);
///   soft — same hue, pale wash (chips/badges background).
/// Mirrors how the Sissi palette relates: #c8821e → deep #9a6310 ≈ L−0.14,
/// soft #f1e2c8 ≈ L 0.86 at low saturation.
({String deep, String soft}) deriveAccentPair(String accentHex) {
  final rgb = rgbFromHex(accentHex);
  if (rgb == null) return (deep: accentHex, soft: accentHex);
  final (_, s, l) = _rgbToHsl(rgb.$1, rgb.$2, rgb.$3);
  final deep = _withHsl(accentHex,
      saturation: (s * 1.15).clamp(0.0, 1.0), lightness: (l - 0.14).clamp(0.08, 0.6));
  final soft = _withHsl(accentHex, saturation: (s * 0.55).clamp(0.0, 1.0), lightness: 0.86);
  return (deep: deep, soft: soft);
}
