import 'package:flutter/material.dart';

/// Design tokens — colors.
/// Extracted from CafeConnectDesighn/CafeConnect Staff.dc.html. Single source of
/// truth: do not hardcode hex values outside this class.
class AppColors {
  const AppColors._();

  // Backgrounds
  static const bg = Color(0xFFF2EFE8); // warm cream — main background
  static const surface = Color(0xFFFFFFFF); // white — cards, sheets
  static const sunken = Color(0xFFEBE6DB); // sunken fills, inputs
  static const shellBg = Color(0xFFF2EFE8);

  // Text
  static const ink = Color(0xFF1E1B16); // primary
  static const ink55 = Color(0x8C1E1B16); // secondary (55%)
  static const ink40 = Color(0x661E1B16); // tertiary (40%)
  static const hairline = Color(0xFFE7E2D8); // dividers, borders

  // Primary action — buttons, send, active nav. Never blue for buttons.
  static const espresso = Color(0xFF221F1A);

  // Zone colors — semantic only, never button fills
  static const kitchen = Color(0xFFE0823A); // orange — kitchen + call-waiter
  static const bar = Color(0xFF3C7BCF); // blue — bar + arrived signal
  static const ok = Color(0xFF3E9C63); // green — ready, success
  static const late = Color(0xFFD9564A); // red — late, danger
  static const gold = Color(0xFFB98A3C); // gold — manager, rank #1
  static const bill = Color(0xFF8A6FC0); // purple — bill-requested signal
  static const free = Color(0xFFB8B1A3); // grey — free table

  // Attention tint backgrounds (~15% opacity)
  static const arrivedTint = Color(0x263E78C9);
  static const callTint = Color(0x26E0823A);
  static const billTint = Color(0x268A6FC0);

  // Kitchen amber (notes, warnings)
  static const amber = Color(0xFFA86A24);
  static const amberBg = Color(0xFFFBF3E6);

  // Occupied table blue
  static const occupied = Color(0xFF5B86B0);

  // ── Menu categories (waiter composer, R-Keeper style) ────────────────────
  // Fallback colors when the backend category color is not available.
  static const famCaffetteria = kitchen; //          orange
  static const famBevande = Color(0xFF5BAEDC); //    light blue
  static const famLiquori = ok; //                   green
  static const famVino = Color(0xFFC0463B); //       red (wine)
  static const famGelati = bar; //                   blue
  static const famFood = Color(0xFFDFAF2B); //       yellow
  static const famDolci = bill; //                   purple
  static const famAperitivi = Color(0xFF7CC488); //  light green
  static const famPopular = gold; //                 ★ the Popular shelf

  static Color categoryColor(String category) => switch (category) {
        'Caffetteria' => famCaffetteria,
        'Bevande' => famBevande,
        'Analcolici' => ok,
        'Birra' => famFood,
        'Vino' => famVino,
        'Cocktail & Aperitivi' => famAperitivi,
        'Liquori/Grappe/Amari' => famLiquori,
        'Pasticceria' => const Color(0xFFB88746),
        'Dolci' => famDolci,
        'Gelati' => famGelati,
        'Panini' => famFood,
        'Piadine' => const Color(0xFFC9A227),
        'Tortel' => const Color(0xFFB97832),
        'Secondi' => const Color(0xFFA94D3E),
        'Uova/colazione salata' => const Color(0xFF6F8F42),
        'Toast' => const Color(0xFF9A7A45),
        'Fritti/stuzzichini' => const Color(0xFFB66A2D),
        _ => famFood,
      };
}
