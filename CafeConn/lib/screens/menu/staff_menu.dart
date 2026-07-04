import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
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
/// Order taking moved to the dedicated composer screen: «Принять заказ» asks
/// for the table and opens the exact same flow as inside a table. The old
/// long-press multi-select is gone — it hid the category chips (locking the
/// waiter into one category) and hid the bottom navigation without a way back.
class _StaffMenuScreenState extends State<StaffMenuScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _category = 'Все';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MenuItem> _filtered(CafeState state) {
    final q = _search.trim().toLowerCase();
    return state.menu.where((m) {
      final okCat = _category == 'Все' || m.category == _category;
      final okSearch = q.isEmpty ||
          m.name.toLowerCase().contains(q) ||
          m.category.toLowerCase().contains(q);
      return okCat && okSearch;
    }).toList();
  }

  void _pickTableAndOrder(BuildContext context) {
    final state = context.read<CafeState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TablePickerSheet(
        onPicked: (table) {
          state.currentTable = table;
          GoRouter.of(context).push('/waiter-menu');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final items = _filtered(state);

    return AppScaffold(
      bottomNav: null,
      child: Stack(children: [
        Column(children: [
          const Header(title: 'Меню', subtitle: 'Витрина и стоп-лист'),
          AppCard(
            padding: EdgeInsets.zero,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Поиск блюда...',
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
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: state.categories
                  .map((c) => CategoryChip(
                        label: c,
                        active: _category == c,
                        onTap: () => setState(() => _category = c),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: items.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'Ничего не найдено',
                    sub: 'Поменяйте запрос или категорию')
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
                      onTap: () => showStaffDishDetails(ctx, items[i]),
                    ),
                  ),
          ),
        ]),
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: PrimaryButton(
            label: 'Принять заказ',
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
  const _MenuShowcaseCard({required this.item, required this.onTap});
  final MenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zoneColor = item.isBar ? AppTheme.bar : AppTheme.warning;
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
                    BoxDecoration(color: zoneColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(item.category.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.label.copyWith(color: AppTheme.ink3)),
            ),
            if (!item.available)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppTheme.danger,
                    borderRadius: BorderRadius.circular(6)),
                child: Text('СТОП',
                    style: T.label
                        .copyWith(color: Colors.white, fontSize: 9)),
              ),
          ]),
          const SizedBox(height: 8),
          Text(item.name,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: T.bodySemi),
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(item.description,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: T.small),
          ],
          const Spacer(),
          Row(children: [
            Text(item.price.rub, style: T.price.copyWith(color: AppTheme.cta)),
            const Spacer(),
            const Icon(Icons.schedule, size: 12, color: AppTheme.ink3),
            const SizedBox(width: 3),
            Text('${item.prepTime} мин',
                style: T.label.copyWith(color: AppTheme.ink3)),
          ]),
        ]),
      ),
    );
  }
}

/// «На какой стол?» — the entry into the unified order flow from the menu tab.
class _TablePickerSheet extends StatelessWidget {
  const _TablePickerSheet({required this.onPicked});
  final ValueChanged<CafeTable> onPicked;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
              color: AppTheme.separator,
              borderRadius: BorderRadius.circular(2)),
        ),
        Text('На какой стол?', style: T.h2.copyWith(fontSize: 20)),
        const SizedBox(height: 16),
        Flexible(
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.1),
            itemCount: state.tables.length,
            itemBuilder: (_, i) {
              final t = state.tables[i];
              final color = statusColor(t.status);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(context);
                  onPicked(t);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(t.number.toString().padLeft(2, '0'),
                            style: AppTypography.mono(
                                size: 18,
                                weight: FontWeight.w800,
                                color: AppColors.ink)),
                        const SizedBox(height: 4),
                        Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle)),
                      ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
