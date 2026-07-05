import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
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
          Header(title: L.panel, subtitle: L.systemManagement, actions: [
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
              tabs: [
                Tab(text: L.overview),
                Tab(text: L.team),
                Tab(text: L.menu),
                Tab(text: L.access)
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
                label: L.revenue,
                value: revenue.rub,
                delta: L.todayOrders(todayOrders.length),
                isPositive: true,
                color: AppTheme.success),
            MetricCard(
                label: L.avgCheck,
                value: avgCheck.rub,
                delta: L.acrossTables(servedTables),
                isPositive: true,
                color: AppTheme.gold,
                index: 1),
            MetricCard(
                label: L.tables,
                value: '$activeTables / ${state.tables.length}',
                delta: L.occupiedNow,
                isPositive: true,
                color: AppTheme.tOccupied,
                index: 2),
            MetricCard(
                label: L.inProgress,
                value: '${activeOrders.length}',
                delta: oldestMin > 0 ? L.oldestMin(oldestMin) : L.noQueue,
                isPositive: oldestMin <= 20,
                color: AppTheme.warning,
                index: 3),
          ],
        ),
        const SizedBox(height: 20),
        SectionTitle(L.revenueByHour),
        AppCard(
          height: 160,
          child: maxHour == 0
              ? Center(
                  child: Text(L.noOrdersToday,
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
        Expanded(child: SectionTitle(L.staff)),
        AppButton(
            label: L.add,
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
        Expanded(child: SectionTitle(L.items)),
        AppButton(
            label: L.addItem,
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
                      Text(item.displayName,
                          style: T.h3.copyWith(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(
                          '${item.price.rub} · ${item.displayCategory} · ${item.isBar ? L.bar.toLowerCase() : L.kitchen.toLowerCase()}',
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
  final category = TextEditingController(text: item?.category ?? 'Kitchen');
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
                Text(item == null ? L.newItem : L.editItem,
                    style: T.h1.copyWith(fontSize: 22)),
                const SizedBox(height: 20),
                AppTextField(controller: name, label: L.name),
                const SizedBox(height: 12),
                AppTextField(
                    controller: desc,
                    label: L.description,
                    hint: L.descriptionHint),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: AppTextField(
                            controller: price,
                            label: L.price,
                            keyboardType: TextInputType.number)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: AppTextField(
                            controller: prep,
                            label: L.timeMin,
                            keyboardType: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 12),
                AppTextField(controller: category, label: L.category),
                const SizedBox(height: 16),
                // Where the position is prepared — this is what routes the
                // order to the kitchen or bar screen.
                Text(L.station, style: T.label),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: CategoryChip(
                      label: L.kitchen,
                      active: station == 'kitchen',
                      icon: Icons.restaurant,
                      onTap: () => setModalState(() => station = 'kitchen'),
                    ),
                  ),
                  Expanded(
                    child: CategoryChip(
                      label: L.bar,
                      active: station == 'bar',
                      icon: Icons.local_bar,
                      onTap: () => setModalState(() => station = 'bar'),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                AppButton(
                  label: L.save,
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
                            ? 'Kitchen'
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
        SectionTitle(L.rolePermissions),
        _roleAccessCard(L.roleWaiter, [
          (L.orders, true),
          (L.bill, true),
          (L.menu, true),
          (L.roleAdmin, false)
        ]),
        _roleAccessCard(L.roleCook, [
          (L.orders, true),
          (L.tables, false),
          (L.menu, true),
          (L.roleAdmin, false)
        ]),
        _roleAccessCard(L.roleBartender, [
          (L.orders, true),
          (L.tables, false),
          (L.menu, true),
          (L.roleAdmin, false)
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
                  Text(user == null ? L.newStaffMember : L.edit,
                      style: T.h2),
                  const SizedBox(height: 20),
                  AppTextField(controller: name, label: L.name),
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
                      label: L.save,
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
