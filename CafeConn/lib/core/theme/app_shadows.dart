import 'package:flutter/material.dart';

/// Design tokens — shadows.
class AppShadows {
  const AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0D2B2418), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(
        color: Color(0x382B2418),
        blurRadius: 22,
        spreadRadius: -15,
        offset: Offset(0, 10)),
  ];

  static const List<BoxShadow> sheet = [
    BoxShadow(color: Color(0x1A2B2418), blurRadius: 40, offset: Offset(0, -8)),
  ];
}
