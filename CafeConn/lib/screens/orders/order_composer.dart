import 'package:alphabet_scrollbar/alphabet_scrollbar.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';
import '../menu/dish_details.dart';

class WaiterOrderScreen extends StatefulWidget {
  const WaiterOrderScreen({super.key});
  @override
  State<WaiterOrderScreen> createState() => _WaiterOrderScreenState();
}

/// Unified order-taking screen.
///
/// One and the same flow whether it's the FIRST order of a table or an
/// addition to an open one: search + always-visible category chips + compact
/// photo-less cards. Tap adds a dish (multi-category selection just works —
/// the selection is independent of the current filter), the stepper adjusts
/// quantity, long-press shows dish info. Precheck reviews and sends.
class _WaiterOrderScreenState extends State<WaiterOrderScreen> {
  /// Selection lives here (not in the table cart) until the precheck is
  /// confirmed — cancelling leaves no trace on the table's check.
  final Map<MenuItem, int> _selQty = {};
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  // Persistent focus node so adding an item (which rebuilds the list) doesn't
  // drop keyboard focus; _add re-asserts it after the rebuild.
  final _searchFocus = FocusNode();
  // On the web build the browser blurs the input (closing the keyboard) BEFORE
  // the tile's tap handler runs, so checking hasFocus inside _add is already
  // too late. Track when focus was lost: a loss within this window means the
  // keyboard was up for this very tap and must be brought back.
  DateTime? _searchFocusLostAt;
  bool get _keyboardWasUp =>
      _searchFocus.hasFocus ||
      (_searchFocusLostAt != null &&
          DateTime.now().difference(_searchFocusLostAt!) <
              const Duration(milliseconds: 700));
  String _search = '';
  // Family filter: the Popular shelf ('popular'), 'All', or one of
  // MenuFamilies.all. Landing on Popular = the most-sold items are one tap
  // away the moment the screen opens.
  static const _popularFilter = 'popular';
  String _category = _popularFilter;
  // R-Keeper-style 2-column grid: twice the items per screen versus the old
  // full-width rows, so composing an order needs far less scrolling.
  static const int _gridCols = 2;
  static const double _gridTileHeight = 92;
  static const double _gridSpacing = 8;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus) _searchFocusLostAt = DateTime.now();
    });
    // Pull a fresh menu so a since-deleted item (e.g. after a menu cleanup)
    // can't be sent with a stale id and get rejected by the hub.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<CafeState>().refreshMenu());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The effective filter: the Popular shelf is the landing view, but falls
  /// back to Tutti while nothing is pinned yet (empty landing = confused
  /// waiter). Searching always searches the whole menu.
  String _effectiveFilter(CafeState state) {
    if (_search.trim().isNotEmpty) return 'All';
    if (_category == _popularFilter && !state.menu.any((m) => m.isPopular)) {
      return 'All';
    }
    return _category;
  }

  List<MenuItem> _baseFiltered(CafeState state) {
    final q = _search.trim().toLowerCase();
    final filter = _effectiveFilter(state);
    return state.menu.where((m) {
      final okCat = switch (filter) {
        'All' => true,
        _popularFilter => m.isPopular,
        _ => m.family == filter,
      };
      final okSearch = q.isEmpty ||
          m.name.toLowerCase().contains(q) ||
          m.nameIt.toLowerCase().contains(q) ||
          m.category.toLowerCase().contains(q) ||
          m.categoryIt.toLowerCase().contains(q);
      return okCat && okSearch;
    }).toList();
  }

  List<String> _letters(CafeState state) {
    final letters = _baseFiltered(state)
        .map((m) => m.displayName.trim())
        .where((name) => name.isNotEmpty)
        .map((name) => name.substring(0, 1).toUpperCase())
        .where((letter) => RegExp(r'[A-ZÀ-Ü]').hasMatch(letter))
        .toSet()
        .toList()
      ..sort();
    return letters;
  }

  List<MenuItem> _filtered(CafeState state) {
    return state.sortedMenuItems(_baseFiltered(state));
  }

  void _jumpToLetter(String letter, List<MenuItem> items) {
    final target = letter.toUpperCase();
    final index = items.indexWhere((item) {
      final name = item.displayName.trim();
      return name.isNotEmpty && name.substring(0, 1).toUpperCase() == target;
    });
    if (index < 0 || !_scrollCtrl.hasClients) return;
    HapticFeedback.selectionClick();
    final row = index ~/ _gridCols;
    _scrollCtrl.animateTo(
      (row * (_gridTileHeight + _gridSpacing))
          .clamp(0.0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _add(BuildContext context, MenuItem item) {
    if (!item.available) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.stopListed(item.displayName)),
          backgroundColor: AppTheme.danger));
      return;
    }
    HapticFeedback.selectionClick();
    final keepKeyboard = _keyboardWasUp;
    setState(() => _selQty[item] = (_selQty[item] ?? 0) + 1);
    if (keepKeyboard) _keepKeyboardUp();
  }

  /// Belt-and-suspenders next to the TextField's neutralized onTapOutside
  /// (the actual fix): if anything else stole focus, take it back and re-show
  /// the keyboard — synchronously, still inside this tap's user gesture, which
  /// is when mobile browsers allow programmatic keyboards.
  void _keepKeyboardUp() {
    if (!_searchFocus.hasFocus) _searchFocus.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  void _removeOne(MenuItem item) {
    final current = _selQty[item] ?? 0;
    HapticFeedback.selectionClick();
    final keepKeyboard = _keyboardWasUp;
    setState(() {
      if (current <= 1) {
        _selQty.remove(item);
      } else {
        _selQty[item] = current - 1;
      }
    });
    if (keepKeyboard) _keepKeyboardUp();
  }

  /// One compact colored family button. Light family colors (yellow, light
  /// blue/green) get ink text when active so the label stays readable.
  Widget _familyBtn(String label, String value, Color color,
      {IconData? icon}) {
    final active = _category == value;
    final onColor =
        color.computeLuminance() > 0.45 ? AppColors.ink : Colors.white;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _category = value);
      },
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: active ? color : color.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: active ? onColor : color),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: active ? onColor : AppColors.ink)),
        ]),
      ),
    );
  }

  /// Long-press on a tile: pin/unpin on the Popular shelf, or open details.
  void _showItemActions(BuildContext context, CafeState state, MenuItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.displayName, style: T.h2.copyWith(fontSize: 18)),
            const SizedBox(height: 16),
            AppButton(
              label: item.isPopular ? L.unpinPopular : L.pinPopular,
              icon: item.isPopular
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              onPressed: () {
                state.togglePopular(item);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
            AppButton(
              label: L.dishDetails,
              icon: Icons.info_outline,
              kind: ButtonKind.secondary,
              onPressed: () {
                Navigator.pop(context);
                showStaffDishDetails(context, item);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openPrecheck(BuildContext context, String tableId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PrecheckSheet(
        selectionQty: Map.from(_selQty),
        fixedTableId: tableId,
        onConfirmed: (sent) {
          if (!mounted) return;
          setState(() => _selQty.clear());
          if (sent) {
            // Land on the table's detail (now showing the sent items),
            // regardless of whether we came from the table or the menu tab.
            final router = GoRouter.of(context);
            router.go('/tables');
            router.push('/table-details');
          } else if (context.canPop()) {
            context.pop();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final table = state.currentTable ?? state.tables.firstOrNull;
    if (table == null) {
      return AppScaffold(
          child: EmptyState(
              icon: Icons.table_restaurant_outlined,
              title: L.noTables,
              sub: L.addTableFirst));
    }
    final items = _filtered(state);
    final letters = _letters(state);
    final count = _selQty.values.fold(0, (s, v) => s + v);
    final total =
        _selQty.entries.fold(0.0, (s, e) => s + e.key.price * e.value);

    return AppScaffold(
      child: Stack(children: [
        Column(children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back, color: AppTheme.ink),
              ),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(L.tableOrder(table.number),
                          style: T.screenTitle.copyWith(fontSize: 24)),
                      Text(L.tapToAdd, style: T.subtitle),
                    ]),
              ),
            ]),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: (v) => setState(() => _search = v),
              // THE keyboard fix. Flutter's default onTapOutside unfocuses a
              // TextField on any outside touch **on mobile web** (see
              // EditableText._defaultOnTapOutside), firing on pointer-down —
              // before any tile tap handler. That's what kept closing the
              // keyboard between adds. Neutralize it: while composing, only
              // the keyboard's own done/back dismisses.
              onTapOutside: (_) {},
              decoration: InputDecoration(
                hintText: L.searchMenu,
                prefixIcon: const Icon(Icons.search, color: AppTheme.ink3),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close,
                            size: 18, color: AppTheme.ink3),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Family bar, R-Keeper style: ALL buttons visible at once (no
          // horizontal scrolling — that was what made switching slow), one tap
          // to any family, colors matching the tiles below.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _familyBtn(L.popular, _popularFilter, AppColors.famPopular,
                  icon: Icons.star_rounded),
              _familyBtn(L.all, 'All', AppColors.espresso),
              for (final f in MenuFamilies.all)
                _familyBtn(f, f, AppColors.familyColor(f)),
            ],
          ),
          if (_category == _popularFilter &&
              !state.menu.any((m) => m.isPopular))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(L.popularEmpty,
                  style: T.label.copyWith(color: AppTheme.ink2)),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.search_off,
                    title: L.nothingFound,
                    sub: L.changeSearch)
                : Stack(
                    children: [
                      GridView.builder(
                        controller: _scrollCtrl,
                        padding: EdgeInsets.only(
                            top: 2,
                            right: letters.length > 1 ? 38 : 0,
                            bottom: count > 0 ? 130 : 40),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _gridCols,
                          mainAxisExtent: _gridTileHeight,
                          crossAxisSpacing: _gridSpacing,
                          mainAxisSpacing: _gridSpacing,
                        ),
                        itemCount: items.length,
                        itemBuilder: (ctx, i) {
                          final item = items[i];
                          return _OrderComposerTile(
                            item: item,
                            qty: _selQty[item] ?? 0,
                            onAdd: () => _add(ctx, item),
                            onRemove: () => _removeOne(item),
                            onInfo: () => _showItemActions(ctx, state, item),
                          );
                        },
                      ),
                      if (letters.length > 1)
                        Positioned(
                          top: 6,
                          right: 0,
                          bottom: count > 0 ? 96 : 10,
                          child: _OrderAlphabetRail(
                            letters: letters,
                            onLetterChange: (letter) =>
                                _jumpToLetter(letter, items),
                          ),
                        ),
                    ],
                  ),
          ),
        ]),
        if (count > 0)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _ComposerBar(
              count: count,
              total: total,
              onClear: () => setState(() => _selQty.clear()),
              onNext: () => _openPrecheck(context, table.id),
            ),
          ),
      ]),
    );
  }
}

class _OrderAlphabetRail extends StatelessWidget {
  const _OrderAlphabetRail({
    required this.letters,
    required this.onLetterChange,
  });

  final List<String> letters;
  final ValueChanged<String> onLetterChange;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.card.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.separator),
        boxShadow: const [AppTheme.shadowCard],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: AlphabetScrollbar(
          onLetterChange: onLetterChange,
          letterCollection: letters,
          selectedLetterColor: AppTheme.cta,
          selectedLetterAdditionalSpace: 8,
          factor: 14,
          padding: EdgeInsets.zero,
          style: T.label.copyWith(
            color: AppTheme.ink3,
            fontWeight: FontWeight.w900,
            fontSize: 10.5,
          ),
        ),
      ),
    );
  }
}

// ===== ORDER COMPOSER WIDGETS (photo-less, built for speed) =====

/// One menu position in the order composer — a compact grid tile, R-Keeper
/// style. The whole tile is a tap target («+1»); the top edge and background
/// tint carry the category color family (coffee/soft/alcohol/food/sweet) so a
/// waiter reads the type before the name. Long-press opens dish details.
class _OrderComposerTile extends StatelessWidget {
  const _OrderComposerTile({
    required this.item,
    required this.qty,
    required this.onAdd,
    required this.onRemove,
    required this.onInfo,
  });
  final MenuItem item;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final catColor = AppColors.familyColor(item.family);
    final selected = qty > 0;

    return GestureDetector(
      onTap: onAdd,
      onLongPress: onInfo,
      behavior: HitTestBehavior.opaque,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.cta.withValues(alpha: 0.05)
              : catColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? AppTheme.cta : AppTheme.separator,
              width: selected ? 1.4 : 1),
          boxShadow: const [AppTheme.shadowCard],
        ),
        child: Opacity(
          opacity: item.available ? 1 : 0.5,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Category color bar along the top edge (same idiom as the table
            // cards' color tag).
            Container(height: 4, color: catColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(item.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: T.bodySemi.copyWith(
                              fontSize: 13.5, height: 1.18)),
                    ),
                    Row(children: [
                      if (item.isPopular)
                        const Padding(
                          padding: EdgeInsets.only(right: 3),
                          child: Icon(Icons.star_rounded,
                              size: 13, color: AppColors.gold),
                        ),
                      if (!item.available)
                        Container(
                          margin: const EdgeInsets.only(right: 5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                              color: AppTheme.danger,
                              borderRadius: BorderRadius.circular(5)),
                          child: Text(L.stop,
                              style: T.label.copyWith(
                                  color: Colors.white, fontSize: 8.5)),
                        ),
                      Expanded(
                        child: Text(item.price.rub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.priceSmall.copyWith(
                                fontSize: 13,
                                color:
                                    selected ? AppTheme.cta : AppTheme.ink2)),
                      ),
                      if (!selected)
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                              color: AppTheme.cta, shape: BoxShape.circle),
                          child: const Icon(Icons.add,
                              color: Colors.white, size: 16),
                        )
                      else
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          GestureDetector(
                            onTap: onRemove,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: const BoxDecoration(
                                  color: AppTheme.surfaceSunken,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.remove, size: 15),
                            ),
                          ),
                          SizedBox(
                            width: 24,
                            child: Center(
                                child: Text('$qty',
                                    style: AppTypography.mono(
                                        size: 14,
                                        weight: FontWeight.w800,
                                        color: AppColors.ink))),
                          ),
                          Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                                color: AppTheme.cta, shape: BoxShape.circle),
                            child: const Icon(Icons.add,
                                color: Colors.white, size: 15),
                          ),
                        ]),
                    ]),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CompactStepper extends StatelessWidget {
  const _CompactStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _btn(Icons.remove, () {
        if (value > 1) onChanged(value - 1);
      }),
      SizedBox(
          width: 30, child: Center(child: Text('$value', style: T.bodySemi))),
      _btn(Icons.add, () => onChanged(value + 1)),
    ]);
  }

  Widget _btn(IconData icon, VoidCallback action) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          action();
        },
        child: Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
              color: AppTheme.surfaceSunken, shape: BoxShape.circle),
          child: Icon(icon, size: 14),
        ),
      );
}

/// Sticky bottom bar of the composer: running total + jump to the precheck.
class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.count,
    required this.total,
    required this.onClear,
    required this.onNext,
  });
  final int count;
  final double total;
  final VoidCallback onClear;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.viewPaddingOf(context).bottom + 12),
      decoration: const BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [AppTheme.shadowSheet],
      ),
      child: Row(children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L.itemsCount(count), style: T.smallSemi),
                Text(total.rub, style: T.h2),
              ]),
        ),
        GhostButton(
          label: L.clear,
          onTap: onClear,
          height: 44,
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 132,
          child: PrimaryButton(
            label: L.precheck,
            height: 44,
            onTap: onNext,
          ),
        ),
      ]),
    );
  }
}

// ===== PRECHECK SHEET =====

class _PrecheckSheet extends StatefulWidget {
  const _PrecheckSheet({
    required this.selectionQty,
    required this.fixedTableId,
    this.onConfirmed,
  });
  final Map<MenuItem, int> selectionQty;
  final String? fixedTableId;
  // Called after the sheet closes; `sent` = the order actually went through.
  final ValueChanged<bool>? onConfirmed;

  @override
  State<_PrecheckSheet> createState() => _PrecheckSheetState();
}

class _PrecheckSheetState extends State<_PrecheckSheet> {
  late final Map<MenuItem, int> _items;
  final Map<MenuItem, TextEditingController> _noteCtrl = {};
  final Map<MenuItem, bool> _noteExp = {};
  String? _tableId;

  @override
  void initState() {
    super.initState();
    _items = Map.from(widget.selectionQty);
    _tableId = widget.fixedTableId;
    for (final item in _items.keys) {
      _noteCtrl[item] = TextEditingController();
      _noteExp[item] = false;
    }
  }

  @override
  void dispose() {
    for (final c in _noteCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final total = _items.entries.fold(0.0, (s, e) => s + e.key.price * e.value);
    // Split preview by the real station (kitchen/bar), not by category name.
    final kitchenCount = _items.entries
        .where((e) => !e.key.isBar)
        .fold(0, (s, e) => s + e.value);
    final barCount =
        _items.entries.where((e) => e.key.isBar).fold(0, (s, e) => s + e.value);
    final selectedTable = _tableId != null
        ? state.tables.firstWhereOrNull((t) => t.id == _tableId)
        : null;

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.88,
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppTheme.separator,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.ink),
                onPressed: () => Navigator.pop(context)),
            Expanded(
                child: Text(L.newOrder, style: T.h1.copyWith(fontSize: 20))),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Table section
              if (widget.fixedTableId == null) ...[
                Text(L.tableU, style: T.label),
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: state.tables.map((t) {
                      final active = _tableId == t.id;
                      return GestureDetector(
                        onTap: () => setState(() => _tableId = t.id),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: active ? AppTheme.cta : AppTheme.card,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                                color:
                                    active ? AppTheme.cta : AppTheme.separator),
                          ),
                          child: Text(L.tableN(t.number),
                              style: T.priceSmall.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: active ? Colors.white : AppTheme.ink)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),
              ] else if (selectedTable != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: AppTheme.surfaceSunken,
                      borderRadius: BorderRadius.circular(11)),
                  child: Row(children: [
                    const Icon(Icons.table_restaurant,
                        size: 16, color: AppTheme.ink2),
                    const SizedBox(width: 8),
                    Text(L.tableN(selectedTable.number), style: T.bodySemi),
                  ]),
                ),
                const SizedBox(height: 20),
              ],

              // Items
              Text(L.itemsU, style: T.label),
              const SizedBox(height: 12),
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: Text(L.allItemsRemoved,
                          style: T.body.copyWith(color: AppTheme.ink2))),
                ),
              ..._items.entries.map((entry) => _PrecheckItemRow(
                    item: entry.key,
                    qty: entry.value,
                    noteController: _noteCtrl[entry.key]!,
                    expanded: _noteExp[entry.key] ?? false,
                    onQtyChanged: (v) => setState(() => _items[entry.key] = v),
                    onToggleNote: () => setState(() =>
                        _noteExp[entry.key] = !(_noteExp[entry.key] ?? false)),
                    onPreset: (p) {
                      final c = _noteCtrl[entry.key]!;
                      c.text = c.text.isEmpty ? p : '${c.text}, $p';
                    },
                    // Position can be removed right up until the send —
                    // after that it lives on the station screens.
                    onDelete: () => setState(() => _items.remove(entry.key)),
                  )),

              // Split preview
              const Divider(height: 24),
              if (kitchenCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    const Icon(Icons.restaurant,
                        size: 16, color: AppTheme.warning),
                    const SizedBox(width: 8),
                    Text(L.toKitchen(kitchenCount),
                        style: T.bodySemi.copyWith(color: AppTheme.warning)),
                  ]),
                ),
              if (barCount > 0)
                Row(children: [
                  const Icon(Icons.local_bar, size: 16, color: AppTheme.bar),
                  const SizedBox(width: 8),
                  Text(L.toBar(barCount),
                      style: T.bodySemi.copyWith(color: AppTheme.bar)),
                ]),
              const Divider(height: 32),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(L.total, style: T.h2),
                Text(total.rub, style: T.h2.copyWith(color: AppTheme.cta)),
              ]),
              const SizedBox(height: 24),
            ]),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.viewPaddingOf(context).bottom + 16),
          child: PrimaryButton(
            label: L.sendOrder,
            icon: Icons.send,
            height: 52,
            enabled: _items.isNotEmpty &&
                _tableId != null &&
                !state.isSubmitting(_tableId),
            onTap: _items.isNotEmpty &&
                    _tableId != null &&
                    !state.isSubmitting(_tableId)
                ? () => _confirm(context, state)
                : null,
          ),
        ),
      ]),
    );
  }

  Future<void> _confirm(BuildContext context, CafeState state) async {
    final tableId = _tableId!;
    final table = state.tables.firstWhere((t) => t.id == tableId);
    final kitchenCount = _items.entries
        .where((e) => !e.key.isBar)
        .fold(0, (s, e) => s + e.value);
    final barCount =
        _items.entries.where((e) => e.key.isBar).fold(0, (s, e) => s + e.value);

    for (final entry in _items.entries) {
      final note = _noteCtrl[entry.key]?.text.trim() ?? '';
      state.addToCart(entry.key, entry.value, note, tableId: tableId);
    }
    final order = await state.submitOrder(tableId: tableId);

    if (!context.mounted) return;
    // Centre-screen toast (on the root overlay) so it survives the navigation
    // back to the table and reads at eye level, not tucked at the bottom.
    if (order != null) {
      showCenterToast(
          context, L.orderSent(table.number, kitchenCount, barCount));
    } else {
      showCenterToast(
        context,
        state.backendError == null
            ? L.nothingToSend
            : L.notSentSaved(state.backendError!),
        color: AppTheme.danger,
        icon: Icons.error_outline_rounded,
      );
    }
    Navigator.pop(context);
    widget.onConfirmed?.call(order != null);
  }
}

class _PrecheckItemRow extends StatelessWidget {
  const _PrecheckItemRow({
    required this.item,
    required this.qty,
    required this.noteController,
    required this.expanded,
    required this.onQtyChanged,
    required this.onToggleNote,
    required this.onPreset,
    required this.onDelete,
  });
  final MenuItem item;
  final int qty;
  final TextEditingController noteController;
  final bool expanded;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onToggleNote;
  final ValueChanged<String> onPreset;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final presets = item.notePresets;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [AppTheme.shadowCard],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                  color: item.isBar ? AppTheme.bar : AppTheme.warning,
                  shape: BoxShape.circle)),
          Expanded(child: Text(item.displayName, style: T.price)),
          Text((item.price * qty).rub,
              style: T.bodySemi.copyWith(color: AppTheme.cta)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _CompactStepper(value: qty, onChanged: onQtyChanged),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onToggleNote,
            child: Text(expanded ? L.minusNote : L.plusNote,
                style: T.priceSmall.copyWith(color: AppTheme.bar)),
          ),
          const Spacer(),
          // Delete the position while the order is still a draft.
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              onDelete();
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_outline,
                  size: 18, color: AppTheme.danger),
            ),
          ),
        ]),
        if (expanded) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: presets
                .map((p) => GestureDetector(
                      onTap: () => onPreset(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: AppTheme.surfaceSunken,
                            borderRadius: BorderRadius.circular(9)),
                        child: Text(p, style: T.smallSemi),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          AppTextField(controller: noteController, label: L.addNote),
        ],
      ]),
    );
  }
}

// ===== END SELECTION / PRECHECK WIDGETS =====
