import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';

class StaffPanelScreen extends StatefulWidget {
  const StaffPanelScreen({super.key});
  @override
  State<StaffPanelScreen> createState() => _StaffPanelScreenState();
}

class _StaffPanelScreenState extends State<StaffPanelScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      bottomNav: null,
      child: Column(
        children: [
          Header(title: 'Панель', subtitle: 'Управление системой', actions: [
            IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => GoRouter.of(context).push('/settings')),
          ]),
          Container(
            height: 38,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AppTheme.cta,
              labelColor: AppTheme.ink,
              unselectedLabelColor: AppTheme.ink2,
              tabs: const [
                Tab(text: 'Обзор'),
                Tab(text: 'Команда'),
                Tab(text: 'Меню'),
                Tab(text: 'Доступ')
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _OverviewTab(),
                const TeamManagementScreen(),
                const MenuManagementScreen(),
                _AccessTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Live numbers from the actual state — the tab used to show hardcoded
    // demo values (fake revenue, fake deltas), which read as "simulated"
    // activity even on a clean install.
    final state = context.watch<CafeState>();
    final now = DateTime.now();
    final todayOrders = state.orders
        .where((o) =>
            o.createdAt.year == now.year &&
            o.createdAt.month == now.month &&
            o.createdAt.day == now.day)
        .toList();
    final revenue = todayOrders.fold(0.0, (s, o) => s + o.total);
    final servedTables = todayOrders.map((o) => o.tableId).toSet().length;
    final avgCheck = servedTables == 0 ? 0.0 : revenue / servedTables;
    final activeTables =
        state.tables.where((t) => t.status != TableStatus.free).length;
    final activeOrders =
        state.orders.where((o) => o.status != OrderStatus.completed).toList();
    final oldestMin = activeOrders.isEmpty
        ? 0
        : activeOrders
            .map((o) => now.difference(o.createdAt).inMinutes)
            .reduce(max);

    // Revenue by hour (today, 08:00–23:00).
    final byHour = List<double>.filled(16, 0);
    for (final o in todayOrders) {
      final h = o.createdAt.hour;
      if (h >= 8 && h <= 23) byHour[h - 8] += o.total;
    }
    final maxHour = byHour.fold(0.0, max);

    return ListView(
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            MetricCard(
                label: 'Выручка',
                value: revenue.rub,
                delta: 'сегодня · ${todayOrders.length} заказов',
                isPositive: true,
                color: AppTheme.success),
            MetricCard(
                label: 'Средний чек',
                value: avgCheck.rub,
                delta: 'по $servedTables столам',
                isPositive: true,
                color: AppTheme.gold,
                index: 1),
            MetricCard(
                label: 'Столы',
                value: '$activeTables / ${state.tables.length}',
                delta: 'занято сейчас',
                isPositive: true,
                color: AppTheme.tOccupied,
                index: 2),
            MetricCard(
                label: 'В работе',
                value: '${activeOrders.length}',
                delta: oldestMin > 0 ? 'старейший $oldestMin мин' : 'нет очереди',
                isPositive: oldestMin <= 20,
                color: AppTheme.warning,
                index: 3),
          ],
        ),
        const SizedBox(height: 20),
        const SectionTitle('Выручка по часам'),
        AppCard(
          height: 160,
          child: maxHour == 0
              ? Center(
                  child: Text('Сегодня заказов ещё не было',
                      style: T.body.copyWith(color: AppTheme.ink2)))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: byHour
                      .map((v) => Container(
                          width: 12,
                          height: v == 0 ? 4 : 8 + 110 * (v / maxHour),
                          decoration: BoxDecoration(
                              color: v == maxHour
                                  ? AppTheme.cta
                                  : const Color(0xFFE4D7C2),
                              borderRadius: BorderRadius.circular(4))))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class TeamManagementScreen extends StatelessWidget {
  const TeamManagementScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    return ListView(children: [
      Row(children: [
        const Expanded(child: SectionTitle('Сотрудники')),
        AppButton(
            label: 'Добавить',
            kind: ButtonKind.ghost,
            icon: Icons.person_add,
            onPressed: () => _showStaffForm(context))
      ]),
      ...state.users.map((u) => StaffMemberRow(user: u)),
    ]);
  }
}

class MenuManagementScreen extends StatelessWidget {
  const MenuManagementScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    return ListView(children: [
      Row(children: [
        const Expanded(child: SectionTitle('Позиции')),
        AppButton(
            label: 'Добавить блюдо',
            kind: ButtonKind.ghost,
            icon: Icons.add,
            onPressed: () => _showMenuForm(context)),
      ]),
      ...state.menu.map((item) => AppCard(
            padding: const EdgeInsets.all(12),
            onTap: () => _showMenuForm(context, item: item),
            child: Row(
              children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: item.isBar ? AppTheme.bar : AppTheme.warning,
                        shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          style: T.h3.copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(
                          '${item.price.rub} · ${item.category} · ${item.isBar ? 'бар' : 'кухня'}',
                          style: T.smallSemi.copyWith(color: AppTheme.ink2)),
                    ],
                  ),
                ),
                CupertinoSwitch(
                    value: item.available,
                    activeColor: AppTheme.success,
                    onChanged: (v) => state.toggleAvailability(item)),
              ],
            ),
          )),
    ]);
  }
}

void _showMenuForm(BuildContext context, {MenuItem? item}) {
  final name = TextEditingController(text: item?.name ?? '');
  final desc = TextEditingController(text: item?.description ?? '');
  final price = TextEditingController(text: item?.price.toString() ?? '');
  final category = TextEditingController(text: item?.category ?? 'Кухня');
  final prep = TextEditingController(text: item?.prepTime.toString() ?? '10');
  var station = item == null ? 'kitchen' : (item.isBar ? 'bar' : 'kitchen');

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item == null ? 'Новая позиция' : 'Редактировать позицию',
                    style: T.h1.copyWith(fontSize: 22)),
                const SizedBox(height: 20),
                AppTextField(controller: name, label: 'Название'),
                const SizedBox(height: 12),
                AppTextField(
                    controller: desc,
                    label: 'Описание',
                    hint: 'Состав, особенности...'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: AppTextField(
                            controller: price,
                            label: 'Цена',
                            keyboardType: TextInputType.number)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: AppTextField(
                            controller: prep,
                            label: 'Время (мин)',
                            keyboardType: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 12),
                AppTextField(controller: category, label: 'Категория'),
                const SizedBox(height: 16),
                // Where the position is prepared — this is what routes the
                // order to the kitchen or bar screen.
                const Text('ГОТОВИТ', style: T.label),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: CategoryChip(
                      label: 'Кухня',
                      active: station == 'kitchen',
                      icon: Icons.restaurant,
                      onTap: () => setModalState(() => station = 'kitchen'),
                    ),
                  ),
                  Expanded(
                    child: CategoryChip(
                      label: 'Бар',
                      active: station == 'bar',
                      icon: Icons.local_bar,
                      onTap: () => setModalState(() => station = 'bar'),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                AppButton(
                  label: 'Сохранить',
                  onPressed: () {
                    final state = context.read<CafeState>();
                    if (name.text.trim().isEmpty) return;
                    if (item == null) {
                      state.upsertMenuItem(MenuItem(
                        id: 'm${DateTime.now().millisecondsSinceEpoch}',
                        name: name.text.trim(),
                        description: desc.text.trim(),
                        price: double.tryParse(price.text) ?? 0.0,
                        category: category.text.trim().isEmpty
                            ? 'Кухня'
                            : category.text.trim(),
                        imageUrl: '',
                        tags: [],
                        prepTime: int.tryParse(prep.text) ?? 10,
                        station: station,
                      ));
                    } else {
                      item.name = name.text.trim();
                      item.description = desc.text.trim();
                      item.price = double.tryParse(price.text) ?? item.price;
                      item.category = category.text.trim().isEmpty
                          ? item.category
                          : category.text.trim();
                      item.prepTime = int.tryParse(prep.text) ?? item.prepTime;
                      item.station = station;
                      state.upsertMenuItem(item);
                    }
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _AccessTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SectionTitle('Права ролей'),
        _roleAccessCard('Официант', [
          ('Заказы', true),
          ('Счёт', true),
          ('Меню', true),
          ('Админка', false)
        ]),
        _roleAccessCard('Повар', [
          ('Заказы', true),
          ('Столы', false),
          ('Меню', true),
          ('Админка', false)
        ]),
      ],
    );
  }

  Widget _roleAccessCard(String title, List<(String, bool)> perms) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: T.h3.copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          Wrap(
              spacing: 8,
              children: perms
                  .map((p) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: p.$2
                              ? AppTheme.success.withValues(alpha: 0.12)
                              : AppTheme.separator,
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(p.$2 ? Icons.check_circle : Icons.circle,
                            size: 12,
                            color: p.$2 ? AppTheme.success : AppTheme.ink3),
                        const SizedBox(width: 4),
                        Text(p.$1,
                            style: T.smallSemi.copyWith(
                                color: p.$2 ? AppTheme.success : AppTheme.ink3,
                                fontWeight: FontWeight.w700))
                      ])))
                  .toList()),
        ]),
      );
}

class StaffMemberRow extends StatelessWidget {
  const StaffMemberRow({super.key, required this.user});
  final AppUser user;
  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => _showStaffForm(context, user: user),
      child: Row(children: [
        Avatar(label: user.name),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user.name,
              style: T.h3.copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
          Text(roleLabel(user.role),
              style: T.priceSmall.copyWith(color: AppTheme.ink2)),
        ])),
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: user.online ? AppTheme.success : AppTheme.ink3,
                shape: BoxShape.circle)),
      ]),
    );
  }
}

void _showStaffForm(BuildContext context, {AppUser? user}) {
  final name = TextEditingController(text: user?.name ?? '');
  var role = user?.role ?? UserRole.waiter;
  showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
          builder: (context, set) => Container(
                decoration: const BoxDecoration(
                    color: AppTheme.surfaceAlt,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24))),
                padding: EdgeInsets.fromLTRB(
                    20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(user == null ? 'Новый сотрудник' : 'Редактировать',
                      style: T.h2),
                  const SizedBox(height: 20),
                  AppTextField(controller: name, label: 'Имя'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField(
                      value: role,
                      items: UserRole.values
                          .map((r) => DropdownMenuItem(
                              value: r, child: Text(roleLabel(r))))
                          .toList(),
                      onChanged: (v) => set(() => role = v!)),
                  const SizedBox(height: 20),
                  AppButton(
                      label: 'Сохранить',
                      onPressed: () {
                        if (user == null) {
                          context
                              .read<CafeState>()
                              .createStaff(name.text, role);
                        } else {
                          user.name = name.text;
                          user.role = role;
                          context.read<CafeState>().refresh();
                        }
                        Navigator.pop(context);
                      }),
                ]),
              )));
}
