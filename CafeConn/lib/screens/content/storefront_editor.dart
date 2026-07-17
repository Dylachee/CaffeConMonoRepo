import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/color_utils.dart' as cu;
import '../../core/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api_config.dart';
import '../../data/dtos.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';
import 'storefront_preview.dart';

/// Storefront editor — the venue vibe constructor. Edits a local DRAFT
/// (palette, texts, badges, block layout, images) with a live native preview
/// on top; nothing reaches the hub until "Save". Validation mirrors the
/// backend (hex format client-side; everything else is the hub's answer,
/// shown verbatim). The ink/bg WCAG-AA check warns and never blocks.
class StorefrontEditorScreen extends StatefulWidget {
  const StorefrontEditorScreen({super.key});
  @override
  State<StorefrontEditorScreen> createState() => _StorefrontEditorScreenState();
}

const _paletteKeys = [
  'bg',
  'card',
  'ink',
  'mut',
  'line',
  'accent',
  'accent_deep',
  'accent_soft',
];

class _StorefrontEditorScreenState extends State<StorefrontEditorScreen> {
  bool _hydrated = false;
  bool _saving = false;

  final Map<String, TextEditingController> _colors = {
    for (final key in _paletteKeys) key: TextEditingController(),
  };
  final _name = TextEditingController();
  final _tagline = TextEditingController();
  final _taglineIt = TextEditingController();
  final _about = TextEditingController();
  final _aboutIt = TextEditingController();
  final _address = TextEditingController();
  final _addressIt = TextEditingController();
  final _hours = TextEditingController();
  final _hoursIt = TextEditingController();
  final _mapsUrl = TextEditingController();
  List<StorefrontBlockDto> _blocks = [];
  final List<({TextEditingController en, TextEditingController it})> _badges =
      [];
  int _pinnedLimit = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<CafeState>().refreshVenueSettings());
  }

  @override
  void dispose() {
    for (final ctrl in _colors.values) {
      ctrl.dispose();
    }
    for (final badge in _badges) {
      badge.en.dispose();
      badge.it.dispose();
    }
    _name.dispose();
    _tagline.dispose();
    _taglineIt.dispose();
    _about.dispose();
    _aboutIt.dispose();
    _address.dispose();
    _addressIt.dispose();
    _hours.dispose();
    _hoursIt.dispose();
    _mapsUrl.dispose();
    super.dispose();
  }

  void _hydrate(VenueSettingsDto venue) {
    _hydrated = true;
    for (final key in _paletteKeys) {
      _colors[key]!.text = venue.palette[key] ?? '';
    }
    _name.text = venue.name;
    _tagline.text = venue.tagline;
    _taglineIt.text = venue.taglineIt;
    _about.text = venue.about;
    _aboutIt.text = venue.aboutIt;
    _address.text = venue.address;
    _addressIt.text = venue.addressIt;
    _hours.text = venue.hours;
    _hoursIt.text = venue.hoursIt;
    _mapsUrl.text = venue.mapsUrl;
    _blocks = List.of(venue.blocks);
    for (final badge in _badges) {
      badge.en.dispose();
      badge.it.dispose();
    }
    _badges.clear();
    for (final badge in venue.badges) {
      _badges.add((
        en: TextEditingController(text: badge['en'] ?? ''),
        it: TextEditingController(text: badge['it'] ?? ''),
      ));
    }
    _pinnedLimit = venue.pinnedPostsLimit;
  }

  Map<String, String> get _draftPalette =>
      {for (final key in _paletteKeys) key: _colors[key]!.text.trim()};

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppTheme.danger));
  }

  void _applyPreset(ThemePresetDto preset) {
    setState(() {
      for (final key in _paletteKeys) {
        final value = preset.palette[key];
        if (value != null) _colors[key]!.text = value;
      }
    });
    HapticFeedback.selectionClick();
  }

  void _generateFromAccent() {
    final accent = _colors['accent']!.text.trim();
    if (!cu.isValidHex(accent)) {
      _showError(L.invalidHex);
      return;
    }
    final pair = cu.deriveAccentPair(accent);
    setState(() {
      _colors['accent_deep']!.text = pair.deep;
      _colors['accent_soft']!.text = pair.soft;
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _pickImage(String kind) async {
    final state = context.read<CafeState>();
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final err = await state.setVenueImage(kind,
        bytes: bytes, filename: picked.name.isEmpty ? '$kind.jpg' : picked.name);
    if (err != null) _showError(err);
  }

  Future<void> _save() async {
    if (_saving) return;
    final palette = _draftPalette;
    for (final entry in palette.entries) {
      if (!cu.isValidHex(entry.value)) {
        _showError('${_colorLabel(entry.key)}: ${L.invalidHex}');
        return;
      }
    }
    final badges = <Map<String, String>>[];
    for (final badge in _badges) {
      final en = badge.en.text.trim();
      final it = badge.it.text.trim();
      if (en.isEmpty && it.isEmpty) continue;
      badges.add({'en': en.isEmpty ? it : en, 'it': it.isEmpty ? en : it});
    }
    final fields = <String, dynamic>{
      'name': _name.text.trim(),
      'tagline': _tagline.text.trim(),
      'tagline_it': _taglineIt.text.trim(),
      'about': _about.text.trim(),
      'about_it': _aboutIt.text.trim(),
      'address': _address.text.trim(),
      'address_it': _addressIt.text.trim(),
      'hours': _hours.text.trim(),
      'hours_it': _hoursIt.text.trim(),
      'maps_url': _mapsUrl.text.trim(),
      'badges': badges,
      'storefront_blocks': _blocks.map((b) => b.toJson()).toList(),
      'pinned_posts_limit': _pinnedLimit,
      for (final entry in palette.entries)
        VenueSettingsDto.paletteWireName(entry.key): entry.value,
    };
    setState(() => _saving = true);
    final err = await context.read<CafeState>().saveVenueSettings(fields);
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      _showError(err);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.storefrontSaved), backgroundColor: AppTheme.success));
  }

  String _colorLabel(String key) => switch (key) {
        'bg' => L.colorBg,
        'card' => L.colorCard,
        'ink' => L.colorInk,
        'mut' => L.colorMut,
        'line' => L.colorLine,
        'accent' => L.colorAccent,
        'accent_deep' => L.colorAccentDeep,
        'accent_soft' => L.colorAccentSoft,
        _ => key,
      };

  String _absoluteUrl(String url) {
    if (url.isEmpty || url.startsWith('http')) return url;
    return '${ApiConfig.baseUrl}$url';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final venue = state.venueSettings;
    if (venue != null && !_hydrated) _hydrate(venue);

    if (venue == null) {
      return state.venueLoading
          ? const Center(child: CupertinoActivityIndicator())
          : ListView(children: [
              const SizedBox(height: 8),
              EmptyState(
                  icon: Icons.storefront_outlined,
                  title: L.storefrontTitle,
                  sub: L.connectToManage),
            ]);
    }

    final palette = _draftPalette;
    final ink = palette['ink'] ?? '';
    final bg = palette['bg'] ?? '';
    final lowContrast = cu.isValidHex(ink) &&
        cu.isValidHex(bg) &&
        !cu.meetsWcagAA(ink, bg);

    return RefreshIndicator(
      onRefresh: () async {
        _hydrated = false;
        await context.read<CafeState>().refreshVenueSettings();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // ---- live preview ----
          SectionTitle(L.livePreview),
          StorefrontPreview(
            palette: palette,
            name: _name.text.trim(),
            tagline: (L.isIt ? _taglineIt.text : _tagline.text).trim(),
            badges: [
              for (final badge in _badges)
                {'en': badge.en.text, 'it': badge.it.text}
            ],
            blocks: _blocks,
            coverUrl: _absoluteUrl(venue.coverUrl),
            logoUrl: _absoluteUrl(venue.logoUrl),
          ),
          if (lowContrast)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.contrast, color: AppTheme.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(L.contrastWarning, style: T.small)),
              ]),
            ),

          // ---- theme presets ----
          SectionTitle(L.themePresets),
          SizedBox(
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: state.themePresets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final preset = state.themePresets[i];
                return GestureDetector(
                  onTap: () => _applyPreset(preset),
                  child: Container(
                    width: 112,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.separator),
                      boxShadow: const [AppTheme.shadowCard],
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            for (final key in ['bg', 'accent', 'ink'])
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: _Swatch(hex: preset.palette[key] ?? ''),
                              ),
                          ]),
                          const Spacer(),
                          Text(L.isIt ? preset.nameIt : preset.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: T.smallSemi.copyWith(color: AppTheme.ink)),
                        ]),
                  ),
                );
              },
            ),
          ),

          // ---- palette ----
          SectionTitle(L.paletteSection),
          AppCard(
            child: Column(children: [
              for (final key in _paletteKeys)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    _Swatch(hex: palette[key] ?? '', size: 26),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_colorLabel(key), style: T.body)),
                    SizedBox(
                      width: 118,
                      child: AppTextField(
                        controller: _colors[key]!,
                        label: '#RRGGBB',
                        keyboardType: TextInputType.visiblePassword,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 10),
              GhostButton(
                label: L.generateFromAccent,
                icon: Icons.auto_awesome,
                onTap: _generateFromAccent,
              ),
            ]),
          ),

          // ---- venue texts ----
          SectionTitle(L.venueTexts),
          AppCard(
            child: Column(children: [
              AppTextField(
                  controller: _name,
                  label: L.venueNameLbl,
                  onChanged: (_) => setState(() {})),
              const SizedBox(height: 10),
              AppTextField(
                  controller: _tagline,
                  label: L.taglineEn,
                  onChanged: (_) => setState(() {})),
              const SizedBox(height: 10),
              AppTextField(
                  controller: _taglineIt,
                  label: L.taglineIt,
                  onChanged: (_) => setState(() {})),
              const SizedBox(height: 10),
              AppTextField(controller: _about, label: L.aboutEn),
              const SizedBox(height: 10),
              AppTextField(controller: _aboutIt, label: L.aboutIt),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child:
                        AppTextField(controller: _address, label: L.addressEn)),
                const SizedBox(width: 10),
                Expanded(
                    child: AppTextField(
                        controller: _addressIt, label: L.addressItLbl)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: AppTextField(controller: _hours, label: L.hoursEn)),
                const SizedBox(width: 10),
                Expanded(
                    child:
                        AppTextField(controller: _hoursIt, label: L.hoursIt)),
              ]),
              const SizedBox(height: 10),
              AppTextField(
                  controller: _mapsUrl,
                  label: L.mapsUrlLbl,
                  keyboardType: TextInputType.url),
            ]),
          ),

          // ---- badges ----
          SectionTitle(L.badgesSection),
          AppCard(
            child: Column(children: [
              for (var i = 0; i < _badges.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                        child: AppTextField(
                            controller: _badges[i].en,
                            label: L.badgeEnHint,
                            onChanged: (_) => setState(() {}))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: AppTextField(
                            controller: _badges[i].it,
                            label: L.badgeItHint,
                            onChanged: (_) => setState(() {}))),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          size: 18, color: AppTheme.danger),
                      onPressed: () => setState(() {
                        final removed = _badges.removeAt(i);
                        removed.en.dispose();
                        removed.it.dispose();
                      }),
                    ),
                  ]),
                ),
              if (_badges.length < 8)
                GhostButton(
                  label: L.addBadge,
                  onTap: () => setState(() => _badges.add((
                        en: TextEditingController(),
                        it: TextEditingController(),
                      ))),
                ),
            ]),
          ),

          // ---- storefront blocks ----
          SectionTitle(L.blocksSection),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(L.blocksHint,
                style: T.smallSemi.copyWith(color: AppTheme.ink3)),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: true,
              itemCount: _blocks.length,
              onReorder: (oldIndex, newIndex) => setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final block = _blocks.removeAt(oldIndex);
                _blocks.insert(newIndex, block);
              }),
              itemBuilder: (_, i) {
                final block = _blocks[i];
                return ListTile(
                  key: ValueKey(block.key),
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 8, right: 40),
                  leading: const Icon(Icons.drag_indicator,
                      size: 18, color: AppTheme.ink3),
                  title: Text(L.blockName(block.key), style: T.body),
                  trailing: Switch.adaptive(
                    value: block.visible,
                    activeThumbColor: AppTheme.success,
                    onChanged: (v) => setState(() => _blocks[i] =
                        StorefrontBlockDto(key: block.key, visible: v)),
                  ),
                );
              },
            ),
          ),

          // ---- logo & cover ----
          SectionTitle(L.imagesSection),
          AppCard(
            child: Column(children: [
              _ImageRow(
                label: L.uploadLogo,
                url: _absoluteUrl(venue.logoUrl),
                onUpload: () => _pickImage('logo'),
                onRemove: venue.logoUrl.isEmpty
                    ? null
                    : () async {
                        final err = await context
                            .read<CafeState>()
                            .setVenueImage('logo');
                        if (err != null) _showError(err);
                      },
              ),
              const SizedBox(height: 10),
              _ImageRow(
                label: L.uploadCover,
                url: _absoluteUrl(venue.coverUrl),
                onUpload: () => _pickImage('cover'),
                onRemove: venue.coverUrl.isEmpty
                    ? null
                    : () async {
                        final err = await context
                            .read<CafeState>()
                            .setVenueImage('cover');
                        if (err != null) _showError(err);
                      },
              ),
            ]),
          ),

          // ---- pinned limit ----
          AppCard(
            child: Row(children: [
              Expanded(child: Text(L.pinnedLimitLbl, style: T.body)),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: _pinnedLimit > 0
                    ? () => setState(() => _pinnedLimit -= 1)
                    : null,
              ),
              Text('$_pinnedLimit', style: T.h3),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: _pinnedLimit < 12
                    ? () => setState(() => _pinnedLimit += 1)
                    : null,
              ),
            ]),
          ),

          const SizedBox(height: 16),
          PrimaryButton(
            label: L.saveStorefront,
            icon: Icons.save_outlined,
            enabled: !_saving,
            onTap: _saving ? null : _save,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.hex, this.size = 18});
  final String hex;
  final double size;
  @override
  Widget build(BuildContext context) {
    final rgb = cu.rgbFromHex(hex);
    final color = rgb == null
        ? AppTheme.separator
        : Color(0xFF000000 | (rgb.$1 << 16) | (rgb.$2 << 8) | rgb.$3);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 3),
        border: Border.all(color: AppTheme.separator),
      ),
    );
  }
}

class _ImageRow extends StatelessWidget {
  const _ImageRow(
      {required this.label,
      required this.url,
      required this.onUpload,
      this.onRemove});
  final String label;
  final String url;
  final VoidCallback onUpload;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 52,
        height: 52,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppTheme.surfaceSunken,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.separator),
        ),
        child: url.isEmpty
            ? const Icon(Icons.image_outlined, color: AppTheme.ink3, size: 22)
            : Image.network(url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image,
                    color: AppTheme.ink3, size: 22)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: GhostButton(
            label: label, icon: Icons.upload_outlined, onTap: onUpload),
      ),
      if (onRemove != null) ...[
        const SizedBox(width: 8),
        IconButton(
          tooltip: L.removeImage,
          icon: const Icon(Icons.delete_outline,
              size: 20, color: AppTheme.danger),
          onPressed: onRemove,
        ),
      ],
    ]);
  }
}
