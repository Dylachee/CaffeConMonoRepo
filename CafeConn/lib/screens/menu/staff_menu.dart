import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';
import 'dish_details.dart';

class StaffMenuScreen extends StatefulWidget {
  const StaffMenuScreen({super.key});

  @override
  State<StaffMenuScreen> createState() => _StaffMenuScreenState();
}

/// Staff menu tab — a read-only showcase (composition, allergens, stop-list).
/// Order taking moved to the dedicated composer screen: «Take order» asks
/// for the table and opens the exact same flow as inside a table. The old
/// long-press multi-select is gone — it hid the category chips (locking the
/// waiter into one category) and hid the bottom navigation without a way back.
class _StaffMenuScreenState extends State<StaffMenuScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _category = 'All';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MenuItem> _filtered(CafeState state) {
    final q = _search.trim().toLowerCase();
    final items = state.menu.where((m) {
      final okCat = _category == 'All' || state.itemInCategory(m, _category);
      final okSearch = q.isEmpty ||
          m.name.toLowerCase().contains(q) ||
          m.nameIt.toLowerCase().contains(q) ||
          m.category.toLowerCase().contains(q) ||
          m.categoryIt.toLowerCase().contains(q);
      return okCat && okSearch;
    });
    return state.sortedMenuItems(items);
  }

  Widget _categoryBtn(String label, String value, Color color) {
    final active = _category == value;
    final onColor =
        color.computeLuminance() > 0.45 ? AppColors.ink : Colors.white;
    return GestureDetector(
      onTap: () => setState(() => _category = value),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: active ? color : color.withValues(alpha: 0.5)),
        ),
        // NB: no `alignment:` here — Container with alignment expands to the
        // full row width inside a Wrap; a min-size Row keeps it chip-sized.
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: active ? onColor : AppColors.ink)),
        ]),
      ),
    );
  }

  void _pickTableAndOrder(BuildContext context) {
    final state = context.read<CafeState>();
    showTablePicker(context, (table) {
      state.currentTable = table;
      GoRouter.of(context).push('/waiter-menu');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final items = _filtered(state);
    final visibleCategories = state.menuCategoriesWithItems();

    return AppScaffold(
      bottomNav: null,
      child: Stack(children: [
        Column(children: [
          Header(title: L.menu, subtitle: L.showcase),
          AppCard(
            padding: EdgeInsets.zero,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: L.searchItem,
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
          const SizedBox(height: 12),
          // Same category bar as the composer/panel: every category visible at
          // once, colors matching the cards below — no chip scrolling.
          Wrap(spacing: 6, runSpacing: 6, children: [
            _categoryBtn(L.all, 'All', AppColors.espresso),
            if (visibleCategories.isNotEmpty)
              for (final category in visibleCategories)
                _categoryBtn(category.name, category.id, category.color)
            else
              for (final category in MenuCategories.all)
                _categoryBtn(
                    category, category, AppColors.categoryColor(category)),
          ]),
          const SizedBox(height: 4),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.search_off,
                    title: L.nothingFound,
                    sub: L.changeSearch)
                : GridView.builder(
                    padding: const EdgeInsets.only(top: 12, bottom: 110),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.92),
                    itemCount: items.length,
                    itemBuilder: (ctx, i) => _MenuShowcaseCard(
                      item: items[i],
                      color: state.categoryColorFor(items[i]),
                      onTap: () => showStaffDishDetails(ctx, items[i]),
                    ),
                  ),
          ),
        ]),
        // Station roles (cook/bartender) have no tables — the menu is a
        // read-only showcase and stop-list for them.
        if (!state.isStationRole)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: PrimaryButton(
              label: L.takeOrder,
              icon: Icons.point_of_sale,
              onTap: () => _pickTableAndOrder(context),
            ),
          ),
      ]),
    );
  }
}

/// Compact photo-less showcase card: zone dot + category, name, price,
/// prep time and availability at a glance.
class _MenuShowcaseCard extends StatelessWidget {
  const _MenuShowcaseCard(
      {required this.item, required this.color, required this.onTap});
  final MenuItem item;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final famColor = color;
    return Opacity(
      opacity: item.available ? 1 : 0.55,
      child: AppCard(
        padding: const EdgeInsets.all(12),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: famColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(item.displayCategory.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.label.copyWith(color: AppTheme.ink3)),
            ),
            if (item.isPopular)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child:
                    Icon(Icons.star_rounded, size: 13, color: AppColors.gold),
              ),
            if (item.tags.contains('client'))
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppTheme.cta.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(L.clientMenu,
                    style: T.label.copyWith(color: AppTheme.cta, fontSize: 9)),
              ),
            if (!item.available)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppTheme.danger,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(L.stop,
                    style: T.label.copyWith(color: Colors.white, fontSize: 9)),
              ),
          ]),
          const SizedBox(height: 8),
          Text(item.displayName,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: T.bodySemi),
          if (item.displayDescription.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(item.displayDescription,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: T.small),
          ],
          const Spacer(),
          Row(children: [
            Text(item.price.rub, style: T.price.copyWith(color: AppTheme.cta)),
            const Spacer(),
            const Icon(Icons.schedule, size: 12, color: AppTheme.ink3),
            const SizedBox(width: 3),
            Text(L.minutes(item.prepTime),
                style: T.label.copyWith(color: AppTheme.ink3)),
          ]),
        ]),
      ),
    );
  }
}

/// «Which table?» — the entry into the unified order flow from the menu tab.
