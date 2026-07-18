import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../core/color_utils.dart' as cu;
import '../../core/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../data/dtos.dart';

/// Native miniature of the guest storefront, painted from a DRAFT palette and
/// texts — the editor's live preview before saving.
///
/// Why native and not a WebView on /menu/?preview=<token>: the staff app is
/// shipped as a web PWA (plus Android), Flutter web has no WebView, and the
/// hub sends X-Frame-Options: DENY so an iframe can't host the guest page
/// either. A native replica renders instantly, offline, and identically on
/// every target. (The hub still exposes POST /api/staff/venue/preview/ for a
/// full-fidelity check in a normal browser tab when needed.)
class StorefrontPreview extends StatelessWidget {
  const StorefrontPreview({
    super.key,
    required this.palette,
    required this.name,
    required this.tagline,
    required this.badges,
    required this.blocks,
    this.coverUrl = '',
    this.logoUrl = '',
  });

  /// bg / card / ink / mut / line / accent / accent_deep / accent_soft → hex.
  final Map<String, String> palette;
  final String name;
  final String tagline;
  final List<Map<String, String>> badges;
  final List<StorefrontBlockDto> blocks;
  final String coverUrl;
  final String logoUrl;

  Color _c(String key, Color fallback) {
    final rgb = cu.rgbFromHex(palette[key] ?? '');
    if (rgb == null) return fallback;
    return Color(0xFF000000 | (rgb.$1 << 16) | (rgb.$2 << 8) | rgb.$3);
  }

  bool _visible(String key) =>
      blocks.where((b) => b.key == key).firstOrNull?.visible ?? true;

  @override
  Widget build(BuildContext context) {
    final bg = _c('bg', const Color(0xFFF2EFE8));
    final card = _c('card', Colors.white);
    final ink = _c('ink', const Color(0xFF1E1B16));
    final mut = _c('mut', const Color(0xFF8B8377));
    final line = _c('line', const Color(0xFFE7E2D8));
    final accent = _c('accent', const Color(0xFFC8821E));
    final accentDeep = _c('accent_deep', const Color(0xFF9A6310));
    final accentSoft = _c('accent_soft', const Color(0xFFF1E2C8));

    final orderedBodyKeys = [
      for (final b in blocks)
        if ((b.key == 'popular' || b.key == 'about') && b.visible) b.key,
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        color: bg,
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_visible('cover'))
            SizedBox(
              height: 132,
              width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        accent.withValues(alpha: .28),
                        accentDeep.withValues(alpha: .9)
                      ],
                    ),
                    image: coverUrl.isEmpty
                        ? null
                        : DecorationImage(
                            image: NetworkImage(coverUrl), fit: BoxFit.cover),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: card,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [AppTheme.shadowCard],
                          image: logoUrl.isEmpty
                              ? null
                              : DecorationImage(
                                  image: NetworkImage(logoUrl),
                                  fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                          child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                          Text(tagline,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  color: Colors.white.withValues(alpha: .84))),
                        ],
                      )),
                    ]),
                  ),
                ),
              ]),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
              child: Text(name,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: ink)),
            ),
          if (_visible('facts'))
            Transform.translate(
              offset: const Offset(0, -8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  _factPill(card, line, mut, ink, Icons.place_outlined),
                  const SizedBox(width: 6),
                  _factPill(card, line, mut, ink, Icons.schedule),
                ]),
              ),
            ),
          if (_visible('badges') && badges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Wrap(spacing: 5, runSpacing: 5, children: [
                for (final badge in badges.take(3))
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: accentSoft,
                        borderRadius: BorderRadius.circular(9)),
                    child: Text(
                        L.isIt
                            ? (badge['it'] ?? badge['en'] ?? '')
                            : (badge['en'] ?? ''),
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: accentDeep)),
                  ),
              ]),
            ),
          if (_visible('cta'))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(children: [
                Expanded(
                    child: Container(
                        height: 30,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                            child: Text(L.menu,
                                style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white))))),
                const SizedBox(width: 6),
                Expanded(
                    child: Container(
                        height: 30,
                        decoration: BoxDecoration(
                          color: card,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [AppTheme.shadowCard],
                        ),
                        child: Center(
                            child: Icon(Icons.notifications_none,
                                size: 16, color: ink)))),
              ]),
            ),
          for (final key in orderedBodyKeys)
            if (key == 'popular')
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(children: [
                  for (var i = 0; i < 3; i++) ...[
                    Expanded(
                      child: Container(
                        height: 44,
                        margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                        decoration: BoxDecoration(
                          color: card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: line),
                        ),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                  width: 22,
                                  height: 14,
                                  decoration: BoxDecoration(
                                      color: accentSoft,
                                      borderRadius: BorderRadius.circular(4))),
                              const SizedBox(height: 4),
                              Container(
                                  width: 30,
                                  height: 4,
                                  decoration: BoxDecoration(
                                      color: mut.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(2))),
                            ]),
                      ),
                    ),
                  ],
                ]),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: line),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            width: 60,
                            height: 6,
                            decoration: BoxDecoration(
                                color: ink.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(3))),
                        const SizedBox(height: 6),
                        Container(
                            width: double.infinity,
                            height: 4,
                            decoration: BoxDecoration(
                                color: mut.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(2))),
                        const SizedBox(height: 3),
                        Container(
                            width: 120,
                            height: 4,
                            decoration: BoxDecoration(
                                color: mut.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(2))),
                      ]),
                ),
              ),
        ]),
      ),
    );
  }

  Widget _factPill(
          Color card, Color line, Color mut, Color ink, IconData icon) =>
      Expanded(
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: card,
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(icon, size: 11, color: mut),
            const SizedBox(width: 4),
            Expanded(
                child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                        color: ink.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(2)))),
          ]),
        ),
      );
}
