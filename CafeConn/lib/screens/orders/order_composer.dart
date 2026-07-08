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
  String _search = '';
  String _category = 'All';
  String _letter = 'All';

  @override
  void initState() {
    super.initState();
    // Pull a fresh menu so a since-deleted item (e.g. after a menu cleanup)
    // can't be sent with a stale id and get rejected by the hub.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<CafeState>().refreshMenu());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MenuItem> _baseFiltered(CafeState state) {
    final q = _search.trim().toLowerCase();
    return state.menu.where((m) {
      final okCat = _category == 'All' || m.category == _category;
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
    return ['All', ...letters];
  }

  List<MenuItem> _filtered(CafeState state) {
    final items = _baseFiltered(state).where((m) {
      if (_letter == 'All') return true;
      final name = m.displayName.trim();
      return name.isNotEmpty && name.substring(0, 1).toUpperCase() == _letter;
    });
    return state.sortedMenuItems(items);
  }

  void _add(BuildContext context, MenuItem item) {
    if (!item.available) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.stopListed(item.displayName)),
          backgroundColor: AppTheme.danger));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _selQty[item] = (_selQty[item] ?? 0) + 1);
  }

  void _removeOne(MenuItem item) {
    final current = _selQty[item] ?? 0;
    HapticFeedback.selectionClick();
    setState(() {
      if (current <= 1) {
        _selQty.remove(item);
      } else {
        _selQty[item] = current - 1;
      }
    });
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
    if (_letter != 'All' && !letters.contains(_letter)) _letter = 'All';
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
              onChanged: (v) => setState(() => _search = v),
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
          // Category chips stay visible at every moment of the selection —
          // switching categories must never drop what's already picked.
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: state.categories
                  .map((c) => CategoryChip(
                        label: state.categoryDisplay(c),
                        active: _category == c,
                        onTap: () => setState(() => _category = c),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: letters
                  .map((letter) => CategoryChip(
                        label: letter == 'All' ? L.all : letter,
                        active: _letter == letter,
                        onTap: () => setState(() => _letter = letter),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.search_off,
                    title: L.nothingFound,
                    sub: L.changeSearch)
                : ListView.builder(
                    padding:
                        EdgeInsets.only(top: 6, bottom: count > 0 ? 130 : 40),
                    itemCount: items.length,
                    itemBuilder: (ctx, i) {
                      final item = items[i];
                      return _OrderComposerTile(
                        item: item,
                        qty: _selQty[item] ?? 0,
                        onAdd: () => _add(ctx, item),
                        onRemove: () => _removeOne(item),
                        onInfo: () => showStaffDishDetails(ctx, item),
                      );
                    },
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

// ===== ORDER COMPOSER WIDGETS (photo-less, built for speed) =====

/// One menu position in the order composer. The whole row is a tap target
/// («+1»); a stepper appears once the dish is selected; long-press (or the
/// info icon) opens dish details. No photos — a colored zone bar tells
/// kitchen from bar at a glance.
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
    final zoneColor = item.isBar ? AppTheme.bar : AppTheme.warning;
    final selected = qty > 0;

    return GestureDetector(
      onTap: onAdd,
      onLongPress: onInfo,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
        decoration: BoxDecoration(
          color:
              selected ? AppTheme.cta.withValues(alpha: 0.04) : AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? AppTheme.cta : const Color(0xFFF0EBE1),
              width: selected ? 1.4 : 1),
          boxShadow: const [AppTheme.shadowCard],
        ),
        child: Opacity(
          opacity: item.available ? 1 : 0.5,
          child: Row(children: [
            // Zone bar: orange = kitchen, blue = bar.
            Container(
              width: 4,
              height: 62,
              decoration: BoxDecoration(
                color: zoneColor,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(13)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.bodySemi.copyWith(fontSize: 15)),
                      const SizedBox(height: 3),
                      Row(children: [
                        Text(
                            '${L.minutes(item.prepTime)} · ${item.displayCategory}',
                            style: T.label.copyWith(color: AppTheme.ink3)),
                        if (!item.available) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                                color: AppTheme.danger,
                                borderRadius: BorderRadius.circular(5)),
                            child: Text(L.stop,
                                style: T.label.copyWith(
                                    color: Colors.white, fontSize: 8.5)),
                          ),
                        ],
                      ]),
                    ]),
              ),
            ),
            const SizedBox(width: 8),
            Text(item.price.rub,
                style: T.priceSmall.copyWith(
                    fontSize: 14,
                    color: selected ? AppTheme.cta : AppTheme.ink)),
            const SizedBox(width: 10),
            if (!selected)
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                    color: AppTheme.cta, shape: BoxShape.circle),
                child: const Icon(Icons.add, color: Colors.white, size: 18),
              )
            else
              Row(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: onRemove,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                        color: AppTheme.surfaceSunken, shape: BoxShape.circle),
                    child: const Icon(Icons.remove, size: 18),
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Center(
                      child: Text('$qty',
                          style: AppTypography.mono(
                              size: 16,
                              weight: FontWeight.w800,
                              color: AppColors.ink))),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                      color: AppTheme.cta, shape: BoxShape.circle),
                  child: const Icon(Icons.add, color: Colors.white, size: 18),
                ),
              ]),
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

  static List<String> get _presets => L.notePresetsShort;

  @override
  Widget build(BuildContext context) {
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
            children: _presets
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
