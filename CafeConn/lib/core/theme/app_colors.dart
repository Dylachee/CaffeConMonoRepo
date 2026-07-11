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

  // ── Menu category families (order composer) ──────────────────────────────
  // R-Keeper-style quick recognition: the waiter reads the color before the
  // name. Five families cover the whole menu; resolver below maps a category
  // to its family.
  static const catCoffee = Color(0xFF8C6239); // roast brown — caffetteria/hot
  static const catSoft = bar; //                 blue — bibite/analcolici
  static const catAlcohol = bill; //             violet — birra/vino/cocktails
  static const catFood = kitchen; //             orange — cucina/panini/colazione
  static const catSweet = Color(0xFFC95D8F); //  berry — dolci/gelati

  /// Category → color family. Matches the Italian category names the menu
  /// uses (plus English fallbacks); unknown categories fall back by station.
  static Color categoryColor(String category, {required bool isBar}) {
    final c = category.toLowerCase();
    bool has(List<String> keys) => keys.any(c.contains);
    if (has(const ['dolc', 'gelat', 'dessert', 'sweet'])) return catSweet;
    if (has(const ['caff', 'tè', 'tisan', 'coffee', 'tea'])) return catCoffee;
    if (has(const [
      'birra',
      'vino',
      'aperitiv',
      'cocktail',
      'liquor',
      'grapp',
      'amari',
      'beer',
      'wine',
      'spritz',
    ])) {
      return catAlcohol;
    }
    if (has(const ['bibit', 'bevand', 'analcolic', 'succ', 'soft', 'drink'])) {
      return catSoft;
    }
    if (has(const [
      'panin',
      'cucina',
      'spuntin',
      'stuzzic',
      'colazion',
      'food',
      'menu del',
    ])) {
      return catFood;
    }
    return isBar ? catSoft : catFood;
  }
}
