import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils.dart';
import '../../data/dtos.dart';
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
    _tabController = TabController(length: 5, vsync: this);
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
          SizedBox(
            height: 38,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AppTheme.cta,
              labelColor: AppTheme.ink,
              unselectedLabelColor: AppTheme.ink2,
              tabs: [
                Tab(text: L.overview),
                Tab(text: L.history),
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
                const _OrderHistoryTab(),
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

class _OverviewTab extends StatefulWidget {
  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  @override
  void initState() {
    super.initState();
    // Pull the hub's aggregated analytics once mounted. No-op offline; on an
    // older backend (no stats endpoint) it leaves state.stats null and the
    // panel shows the live client-side fallback below.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<CafeState>().refreshStats());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final s = state.stats; // server aggregate (full history) when available
    final now = DateTime.now();

    // --- Live client-side fallback: today's orders currently in memory. Used
    // when the hub aggregate isn't available (offline/demo or old backend). ---
    final todayOrders = state.orders
        .where((o) =>
            o.createdAt.year == now.year &&
            o.createdAt.month == now.month &&
            o.createdAt.day == now.day)
        .toList();
    final localRevenue = todayOrders.fold(0.0, (sum, o) => sum + o.total);
    final localServed = todayOrders.map((o) => o.tableId).toSet().length;
    final localAvgCheck = localServed == 0 ? 0.0 : localRevenue / localServed;
    final localActiveTables =
        state.tables.where((t) => t.status != TableStatus.free).length;
    final activeOrders =
        state.orders.where((o) => o.status != OrderStatus.completed).toList();
    final localOldestMin = activeOrders.isEmpty
        ? 0
        : activeOrders
            .map((o) => now.difference(o.createdAt).inMinutes)
            .reduce(max);
    final localByHour = List<double>.filled(24, 0);
    for (final o in todayOrders) {
      localByHour[o.createdAt.hour] += o.total;
    }

    // --- Unified values: prefer the hub aggregate, else the live fallback. ---
    final revenue = s?.revenueToday ?? localRevenue;
    final ordersToday = s?.ordersToday ?? todayOrders.length;
    final avgCheck = s?.avgCheck ?? localAvgCheck;
    final servedTables = s?.servedTables ?? localServed;
    final activeTables = s?.activeTables ?? localActiveTables;
    final totalTables = s?.totalTables ?? state.tables.length;
    final freeTables = s?.freeTables ?? (totalTables - activeTables);
    final delayed = s?.delayedOrders ??
        activeOrders
            .where((o) => now.difference(o.createdAt).inMinutes > 20)
            .length;
    final byHour = s?.revenueByHour ?? localByHour;
    // Show the hours that actually have activity (fall back to midday hours),
    // so revenue never hides just because the shift isn't 08:00–23:00.
    final activeHours = [
      for (var h = 0; h < 24; h++)
        if (byHour[h] > 0) h
    ];
    var startH = activeHours.isEmpty ? 10 : activeHours.first;
    var endH = activeHours.isEmpty ? 21 : activeHours.last;
    if (endH - startH < 5) endH = (startH + 5).clamp(0, 23);
    final window = [
      for (var h = startH; h <= endH; h++) (hour: h, value: byHour[h])
    ];
    final maxHour = window.fold(0.0, (m, e) => max(m, e.value));
    final bestHour =
        window.reduce((best, e) => e.value > best.value ? e : best);
    final occupancy = totalTables == 0 ? 0.0 : activeTables / totalTables;

    return RefreshIndicator(
      onRefresh: () => context.read<CafeState>().refreshStats(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (state.statsLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: compact ? 1 : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: compact ? 2.45 : 1.28,
              children: [
                MetricCard(
                    label: L.revenue,
                    value: revenue.rub,
                    delta: s?.revenueDeltaPct != null
                        ? L.vsYesterday(s!.revenueDeltaPct!)
                        : L.todayOrders(ordersToday),
                    isPositive: (s?.revenueDeltaPct ?? 0) >= 0,
                    color: AppTheme.success,
                    detail: _MetricDetail(rows: [
                      _MetricRow(L.orders, '$ordersToday'),
                      _MetricRow(L.bestHour, '${bestHour.hour}:00'),
                    ])),
                MetricCard(
                    label: L.avgCheck,
                    value: avgCheck.rub,
                    delta: s?.avgCheckDeltaPct != null
                        ? L.deltaPct(s!.avgCheckDeltaPct!)
                        : L.acrossTables(servedTables),
                    isPositive: (s?.avgCheckDeltaPct ?? 0) >= 0,
                    color: AppTheme.gold,
                    detail: _MetricDetail(rows: [
                      _MetricRow(L.tables, '$servedTables'),
                      _MetricRow(L.avgPrepTime,
                          L.minutesShort(s?.avgPrepMinutes ?? 0)),
                    ]),
                    index: 1),
                MetricCard(
                    label: L.tables,
                    value: '$activeTables / $totalTables',
                    delta: L.freeCount(freeTables),
                    isPositive: true,
                    color: AppTheme.tOccupied,
                    detail: _OccupancyDetail(
                        occupancy: occupancy,
                        activeTables: activeTables,
                        freeTables: freeTables),
                    index: 2),
                _fourthCard(s, activeOrders.length, localOldestMin, delayed),
              ],
            );
          }),
          const SizedBox(height: 20),
          SectionTitle(L.revenueByHour),
          AppCard(
            height: 170,
            child: maxHour == 0
                ? Center(
                    child: Text(L.noOrdersToday,
                        style: T.body.copyWith(color: AppTheme.ink2)))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: window
                        .map((e) => Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Container(
                                      height: e.value == 0
                                          ? 4
                                          : 8 + 104 * (e.value / maxHour),
                                      decoration: BoxDecoration(
                                          color: e.value == maxHour
                                              ? AppTheme.cta
                                              : const Color(0xFFE4D7C2),
                                          borderRadius:
                                              BorderRadius.circular(4)),
                                    ),
                                    const SizedBox(height: 6),
                                    Text('${e.hour}',
                                        style: T.label.copyWith(
                                            color: AppTheme.ink3, fontSize: 9)),
                                  ],
                                ),
                              ),
                            ))
                        .toList(),
                  ),
          ),
          if (s != null && s.byWaiter.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionTitle(L.byWaiter),
            ...s.byWaiter.map((w) => _WaiterStatRow(waiter: w)),
          ],
        ],
      ),
    );
  }

  /// Fourth metric card: with the hub aggregate it mirrors the design's
  /// "Avg prep time" (real timing from the DB); on the local fallback it shows
  /// the live "In progress" queue instead.
  Widget _fourthCard(StatsDto? s, int inProgress, int oldestMin, int delayed) {
    if (s != null) {
      return MetricCard(
          label: L.avgPrepTime,
          value: L.minutesShort(s.avgPrepMinutes),
          delta: delayed > 0 ? L.delayedCount(delayed) : L.onTime,
          isPositive: delayed == 0,
          color: AppTheme.warning,
          detail: _MetricDetail(rows: [
            _MetricRow(L.inProgress, '$inProgress'),
            _MetricRow(
                L.delayedCount(delayed), delayed == 0 ? L.onTime : '$delayed'),
          ]),
          index: 3);
    }
    return MetricCard(
        label: L.inProgress,
        value: '$inProgress',
        delta: oldestMin > 0 ? L.oldestMin(oldestMin) : L.noQueue,
        isPositive: oldestMin <= 20,
        color: AppTheme.warning,
        detail: _MetricDetail(rows: [
          _MetricRow(L.oldestMin(oldestMin),
              oldestMin > 0 ? L.minutesShort(oldestMin) : L.noQueue),
          _MetricRow(L.delayedCount(delayed), '$delayed'),
        ]),
        index: 3);
  }
}

class _MetricRow {
  const _MetricRow(this.label, this.value);
  final String label;
  final String value;
}

class _MetricDetail extends StatelessWidget {
  const _MetricDetail({required this.rows});
  final List<_MetricRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: rows
          .map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(children: [
                  Expanded(
                    child: Text(row.label,
                        overflow: TextOverflow.ellipsis,
                        style: T.small.copyWith(color: AppTheme.ink3)),
                  ),
                  const SizedBox(width: 8),
                  Text(row.value,
                      style: T.smallSemi.copyWith(
                          color: AppTheme.ink, fontWeight: FontWeight.w800)),
                ]),
              ))
          .toList(),
    );
  }
}

class _OccupancyDetail extends StatelessWidget {
  const _OccupancyDetail({
    required this.occupancy,
    required this.activeTables,
    required this.freeTables,
  });
  final double occupancy;
  final int activeTables;
  final int freeTables;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: occupancy.clamp(0.0, 1.0),
            backgroundColor: AppTheme.surfaceSunken,
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.tOccupied),
          ),
        ),
        const SizedBox(height: 10),
        _MetricDetail(rows: [
          _MetricRow(L.active, '$activeTables'),
          _MetricRow(L.free, '$freeTables'),
        ]),
      ],
    );
  }
}

class _WaiterStatRow extends StatelessWidget {
  const _WaiterStatRow({required this.waiter});
  final WaiterStatDto waiter;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Avatar(label: waiter.name),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(waiter.name,
                style:
                    T.h3.copyWith(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(L.waiterOrdersTables(waiter.orders, waiter.tables),
                style: T.priceSmall.copyWith(color: AppTheme.ink2)),
          ]),
        ),
        Text(waiter.revenue.rub,
            style: AppTypography.mono(
                size: 15, weight: FontWeight.w800, color: AppColors.ink)),
      ]),
    );
  }
}

class _OrderHistoryTab extends StatefulWidget {
  const _OrderHistoryTab();

  @override
  State<_OrderHistoryTab> createState() => _OrderHistoryTabState();
}

class _OrderHistoryTabState extends State<_OrderHistoryTab> {
  String _query = '';
  String _dateFilter = 'today';
  String _stationFilter = 'all';
  String _statusFilter = 'all';
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<CafeState>().refreshOrderHistory());
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _customRange,
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _dateFilter = 'custom';
      });
    }
  }

  String get _customRangeLabel {
    final r = _customRange;
    if (r == null) return L.custom;
    String d(DateTime x) => '${x.day}/${x.month}';
    return '${d(r.start)} – ${d(r.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final history = state.orderHistory;
    final filtered = history.where(_matchesFilters).toList();
    return RefreshIndicator(
      onRefresh: () => context.read<CafeState>().refreshOrderHistory(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(children: [
            Expanded(child: SectionTitle(L.orderHistory)),
            if (state.orderHistoryLoading)
              const CupertinoActivityIndicator()
            else
              Text(L.pullToRefresh,
                  style: T.smallSemi.copyWith(color: AppTheme.ink3)),
          ]),
          _HistoryFilters(
            dateFilter: _dateFilter,
            stationFilter: _stationFilter,
            statusFilter: _statusFilter,
            customRangeLabel: _customRangeLabel,
            onQuery: (value) => setState(() => _query = value),
            onDate: (value) {
              if (value == 'custom') {
                _pickCustomRange();
              } else {
                setState(() => _dateFilter = value);
              }
            },
            onStation: (value) => setState(() => _stationFilter = value),
            onStatus: (value) => setState(() => _statusFilter = value),
          ),
          const SizedBox(height: 12),
          if (history.isEmpty)
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: L.noOrderHistory,
              sub: state.backendConnected ? L.pullToRefresh : L.localMode,
            )
          else if (filtered.isEmpty)
            EmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: L.nothingFound,
              sub: L.changeSearch,
            )
          else
            ...filtered.map((order) => _OrderHistoryCard(order: order)),
        ],
      ),
    );
  }

  bool _matchesFilters(OrderHistoryDto order) {
    final now = DateTime.now();
    final localCreated = order.createdAt.toLocal();
    if (_dateFilter == 'today' &&
        (localCreated.year != now.year ||
            localCreated.month != now.month ||
            localCreated.day != now.day)) {
      return false;
    }
    if (_dateFilter == 'week' && now.difference(localCreated).inDays >= 7) {
      return false;
    }
    if (_dateFilter == 'custom' && _customRange != null) {
      final start = DateTime(_customRange!.start.year,
          _customRange!.start.month, _customRange!.start.day);
      final end = DateTime(_customRange!.end.year, _customRange!.end.month,
          _customRange!.end.day, 23, 59, 59);
      if (localCreated.isBefore(start) || localCreated.isAfter(end)) {
        return false;
      }
    }
    if (_stationFilter != 'all' && order.station != _stationFilter) {
      return false;
    }
    if (_statusFilter != 'all' && order.status != _statusFilter) {
      return false;
    }
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final haystack = [
      order.id,
      '${order.tableNumber}',
      order.status,
      order.source,
      order.station,
      order.employee,
      order.guestName,
      ...order.items.map((item) => item.name),
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }
}

class _HistoryFilters extends StatelessWidget {
  const _HistoryFilters({
    required this.dateFilter,
    required this.stationFilter,
    required this.statusFilter,
    required this.customRangeLabel,
    required this.onQuery,
    required this.onDate,
    required this.onStation,
    required this.onStatus,
  });
  final String dateFilter;
  final String stationFilter;
  final String statusFilter;
  final String customRangeLabel;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onDate;
  final ValueChanged<String> onStation;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      elevation: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CupertinoSearchTextField(
          placeholder: L.searchOrders,
          onChanged: onQuery,
          style: T.body,
        ),
        const SizedBox(height: 10),
        _FilterRow(options: [
          _FilterOption('today', L.today),
          _FilterOption('week', L.last7Days),
          _FilterOption('all', L.all),
          _FilterOption('custom', customRangeLabel),
        ], selected: dateFilter, onSelected: onDate),
        const SizedBox(height: 8),
        _FilterRow(options: [
          _FilterOption('all', L.all),
          _FilterOption('kitchen', L.kitchen),
          _FilterOption('bar', L.bar),
          _FilterOption('mixed', L.mixed),
        ], selected: stationFilter, onSelected: onStation),
        const SizedBox(height: 8),
        _FilterRow(options: [
          _FilterOption('all', L.status),
          _FilterOption('paid', L.done),
          _FilterOption('completed', L.osCompleted),
          _FilterOption('cancelled', L.cancel),
        ], selected: statusFilter, onSelected: onStatus),
      ]),
    );
  }
}

class _FilterOption {
  const _FilterOption(this.value, this.label);
  final String value;
  final String label;
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.options,
    required this.selected,
    required this.onSelected,
  });
  final List<_FilterOption> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options
            .map((option) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(option.label),
                    selected: selected == option.value,
                    onSelected: (_) => onSelected(option.value),
                    showCheckmark: false,
                    selectedColor: AppTheme.cta,
                    backgroundColor: AppTheme.card,
                    labelStyle: T.smallSemi.copyWith(
                      color: selected == option.value
                          ? Colors.white
                          : AppTheme.ink2,
                    ),
                    side: BorderSide(
                      color: selected == option.value
                          ? AppTheme.cta
                          : AppTheme.separator,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _OrderHistoryCard extends StatelessWidget {
  const _OrderHistoryCard({required this.order});
  final OrderHistoryDto order;

  @override
  Widget build(BuildContext context) {
    final created = order.createdAt.toLocal();
    final hhmm =
        '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
    final date =
        '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}';
    final subtitle = [
      '$date $hhmm',
      '${L.source}: ${_sourceLabel(order.source)}',
      if (order.employee.isNotEmpty) order.employee,
      if (order.guestName.isNotEmpty) '${L.guest}: ${order.guestName}',
    ].join(' · ');
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              '${L.table} ${order.tableNumber} · #${order.id}',
              style: T.h3.copyWith(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          Text(order.total.rub, style: T.h2.copyWith(color: AppTheme.cta)),
        ]),
        const SizedBox(height: 4),
        Text(subtitle, style: T.smallSemi.copyWith(color: AppTheme.ink2)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _historyChip(_statusLabel(order.status), AppTheme.tOccupied),
            _historyChip(_stationLabel(order.station), AppTheme.warning),
          ],
        ),
        const Divider(height: 24),
        ...order.items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Text('${item.qty}×',
                    style: T.timer.copyWith(color: AppTheme.ink2)),
                const SizedBox(width: 10),
                Expanded(child: Text(item.name, style: T.body)),
                Text(_stationLabel(item.station),
                    style: T.smallSemi.copyWith(color: AppTheme.ink3)),
              ]),
            )),
      ]),
    );
  }

  Widget _historyChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(label,
            style: T.smallSemi
                .copyWith(color: color, fontWeight: FontWeight.w800)),
      );

  String _sourceLabel(String source) => switch (source) {
        'guest_web' => 'QR',
        'staff_app' => L.staff,
        'admin_web' => L.panel,
        _ => source,
      };

  String _stationLabel(String station) => switch (station) {
        'kitchen' => L.kitchen,
        'bar' => L.bar,
        'mixed' => L.all,
        _ => station,
      };

  String _statusLabel(String status) => switch (status) {
        'new' => L.osAccepted,
        'cooking' => L.osCooking,
        'ready' => L.osReady,
        'completed' => L.osCompleted,
        'paid' => L.done,
        'cancelled' => L.cancel,
        _ => status,
      };
}

class TeamManagementScreen extends StatefulWidget {
  const TeamManagementScreen({super.key});

  @override
  State<TeamManagementScreen> createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends State<TeamManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<CafeState>().refreshStaffAccounts());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final staff = state.staffAccounts;
    return RefreshIndicator(
      onRefresh: () => context.read<CafeState>().refreshStaffAccounts(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(children: [
            Expanded(child: SectionTitle(L.staff)),
            if (state.staffAccountsLoading)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: CupertinoActivityIndicator(),
              ),
            AppButton(
                label: L.add,
                kind: ButtonKind.ghost,
                icon: Icons.person_add,
                onPressed: () => _showStaffForm(context))
          ]),
          if (!state.backendConnected)
            EmptyState(
              icon: Icons.people_outline,
              title: L.staff,
              sub: L.connectToManage,
            )
          else if (staff.isEmpty && !state.staffAccountsLoading)
            EmptyState(
                icon: Icons.people_outline,
                title: L.noStaffFound,
                sub: L.pullToRefresh)
          else
            ...staff.map((u) => StaffMemberRow(employee: u)),
        ],
      ),
    );
  }
}

class MenuManagementScreen extends StatefulWidget {
  const MenuManagementScreen({super.key});
  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  String _search = '';
  String _family = 'All';

  List<MenuItem> _filtered(CafeState state) {
    final q = _search.trim().toLowerCase();
    return state.menu.where((m) {
      final okFam = _family == 'All' || m.family == _family;
      final okSearch = q.isEmpty ||
          m.name.toLowerCase().contains(q) ||
          m.nameIt.toLowerCase().contains(q) ||
          m.category.toLowerCase().contains(q);
      return okFam && okSearch;
    }).toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  }

  Widget _famBtn(String label, String value, Color color) {
    final active = _family == value;
    final onColor =
        color.computeLuminance() > 0.45 ? AppColors.ink : Colors.white;
    return GestureDetector(
      onTap: () => setState(() => _family = value),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: active ? color : color.withValues(alpha: 0.5)),
        ),
        // No `alignment:` — Container with alignment expands to full width
        // inside a Wrap; a min-size Row keeps it chip-sized.
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

  Widget _badge(String text, Color color) => Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final items = _filtered(state);
    return ListView(children: [
      Row(children: [
        Expanded(child: SectionTitle(L.items)),
        AppButton(
            label: L.addItem,
            kind: ButtonKind.ghost,
            icon: Icons.add,
            onPressed: () => _showMenuForm(context)),
      ]),
      AppCard(
        padding: EdgeInsets.zero,
        child: TextField(
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(
            hintText: L.searchItem,
            prefixIcon: const Icon(Icons.search, color: AppTheme.ink3),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 5, runSpacing: 5, children: [
        _famBtn(L.all, 'All', AppColors.espresso),
        for (final f in MenuFamilies.all)
          _famBtn(f, f, AppColors.familyColor(f)),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(L.itemsCount(items.length),
            style: T.label.copyWith(color: AppTheme.ink3)),
      ),
      ...items.map((item) {
        final famColor = AppColors.familyColor(item.family);
        return AppCard(
          padding: const EdgeInsets.all(12),
          onTap: () => _showMenuForm(context, item: item),
          child: Row(
            children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: famColor, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.h3.copyWith(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(
                        '${item.price.rub} · ${item.displayCategory} · ${item.isBar ? L.bar.toLowerCase() : L.kitchen.toLowerCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.smallSemi.copyWith(color: AppTheme.ink2)),
                    const SizedBox(height: 4),
                    Row(children: [
                      if (item.tags.contains('client'))
                        _badge(L.clientMenu, AppTheme.bar),
                      if (item.isPopular) _badge('★', AppColors.gold),
                      if (item.promo) _badge(L.promoTag, AppTheme.success),
                    ]),
                  ],
                ),
              ),
              CupertinoSwitch(
                  value: item.available,
                  activeTrackColor: AppTheme.success,
                  onChanged: (v) => state.toggleAvailability(item)),
            ],
          ),
        );
      }),
    ]);
  }
}

Widget _menuFormSwitch({
  required IconData icon,
  required Color color,
  required String label,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: T.bodySemi.copyWith(fontSize: 14))),
      CupertinoSwitch(
          value: value, activeTrackColor: color, onChanged: onChanged),
    ]),
  );
}

void _showMenuForm(BuildContext context, {MenuItem? item}) {
  final name = TextEditingController(text: item?.name ?? '');
  final desc = TextEditingController(text: item?.description ?? '');
  final price = TextEditingController(text: item?.price.toString() ?? '');
  final category = TextEditingController(text: item?.category ?? 'Kitchen');
  final prep = TextEditingController(text: item?.prepTime.toString() ?? '10');
  var station = item == null ? 'kitchen' : (item.isBar ? 'bar' : 'kitchen');
  // The three visibility/promotion switches. Guest-popular (is_promoted) and
  // waiter-popular ('popular' tag) are DELIBERATELY separate fields: the owner
  // can promote a product to guests without touching the waiter shelf.
  var guestVisible = item?.tags.contains('client') ?? true;
  var waiterPopular = item?.isPopular ?? false;
  var guestPromo = item?.promo ?? false;

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
                const SizedBox(height: 16),
                _menuFormSwitch(
                  icon: Icons.storefront_outlined,
                  color: AppTheme.bar,
                  label: L.guestVisible,
                  value: guestVisible,
                  onChanged: (v) => setModalState(() => guestVisible = v),
                ),
                _menuFormSwitch(
                  icon: Icons.star_rounded,
                  color: AppColors.gold,
                  label: L.waiterShelf,
                  value: waiterPopular,
                  onChanged: (v) => setModalState(() => waiterPopular = v),
                ),
                _menuFormSwitch(
                  icon: Icons.campaign_outlined,
                  color: AppTheme.success,
                  label: L.promoGuests,
                  value: guestPromo,
                  onChanged: (v) => setModalState(() => guestPromo = v),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  if (item != null) ...[
                    Expanded(
                      child: AppButton(
                        label: L.deleteItem,
                        kind: ButtonKind.ghost,
                        icon: Icons.delete_outline,
                        color: AppTheme.danger.withValues(alpha: 0.08),
                        onPressed: () => _confirmDeleteMenuItem(context, item),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: AppButton(
                      label: L.save,
                      onPressed: () async {
                        final state = context.read<CafeState>();
                        final messenger = ScaffoldMessenger.of(context);
                        if (name.text.trim().isEmpty) return;

                        final tags = List<String>.of(item?.tags ?? const []);
                        void setTag(String tag, bool on) {
                          if (on) {
                            if (!tags.contains(tag)) tags.add(tag);
                          } else {
                            tags.remove(tag);
                          }
                        }

                        setTag('client', guestVisible);
                        setTag('popular', waiterPopular);

                        final MenuItem target;
                        final isNew = item == null;
                        if (isNew) {
                          target = MenuItem(
                            id: 'm${DateTime.now().millisecondsSinceEpoch}',
                            name: name.text.trim(),
                            description: desc.text.trim(),
                            price: double.tryParse(price.text) ?? 0.0,
                            category: category.text.trim().isEmpty
                                ? 'Food'
                                : category.text.trim(),
                            imageUrl: '',
                            tags: tags,
                            prepTime: int.tryParse(prep.text) ?? 10,
                            station: station,
                            promo: guestPromo,
                          );
                        } else {
                          target = item;
                          target.name = name.text.trim();
                          target.description = desc.text.trim();
                          target.price =
                              double.tryParse(price.text) ?? target.price;
                          target.category = category.text.trim().isEmpty
                              ? target.category
                              : category.text.trim();
                          target.prepTime =
                              int.tryParse(prep.text) ?? target.prepTime;
                          target.station = station;
                          target.tags = tags;
                          target.promo = guestPromo;
                        }
                        Navigator.pop(context);
                        final err =
                            await state.saveMenuItem(target, isNew: isNew);
                        messenger.showSnackBar(SnackBar(
                          content: Text(err == null
                              ? L.savedToHub
                              : '${L.notSavedErr}: $err'),
                          backgroundColor:
                              err == null ? AppTheme.success : AppTheme.danger,
                        ));
                      },
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _confirmDeleteMenuItem(BuildContext context, MenuItem item) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(L.deleteItemQ(item.displayName), style: T.h2),
      content: Text(L.deleteItemWarn, style: T.body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L.cancel)),
        FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(L.yesDelete)),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final err = await context.read<CafeState>().deleteMenuItem(item);
  if (!context.mounted) return;
  if (err != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    return;
  }
  Navigator.pop(context);
}

class _AccessTab extends StatefulWidget {
  @override
  State<_AccessTab> createState() => _AccessTabState();
}

class _AccessTabState extends State<_AccessTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<CafeState>().refreshStaffAccounts());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    if (!state.backendConnected) {
      return ListView(children: [
        const SizedBox(height: 8),
        EmptyState(
          icon: Icons.lock_person_outlined,
          title: L.staffAccess,
          sub: L.connectToManage,
        ),
      ]);
    }
    final staff = state.staffAccounts;
    return RefreshIndicator(
      onRefresh: () => context.read<CafeState>().refreshStaffAccounts(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(children: [
            Expanded(child: SectionTitle(L.staffAccess)),
            if (state.staffAccountsLoading) const CupertinoActivityIndicator(),
          ]),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(L.accessHint,
                style: T.smallSemi.copyWith(color: AppTheme.ink3)),
          ),
          if (staff.isEmpty && !state.staffAccountsLoading)
            EmptyState(
                icon: Icons.people_outline,
                title: L.noStaffFound,
                sub: L.pullToRefresh)
          else
            ...staff.map((e) => _StaffAccessCard(employee: e)),
        ],
      ),
    );
  }
}

class _StaffAccessCard extends StatelessWidget {
  const _StaffAccessCard({required this.employee});
  final EmployeeDto employee;

  @override
  Widget build(BuildContext context) {
    final state = context.read<CafeState>();
    final role = employee.role;
    final boss = role == 'manager' || role == 'admin';
    // Which grant flag the role already provides — shown as a fixed chip.
    final roleField = switch (role) {
      'waiter' => 'can_wait',
      'bar' => 'can_bar',
      'kitchen' => 'can_kitchen',
      _ => null,
    };
    final caps = <(String, String, bool)>[
      ('can_wait', L.capWaiter, employee.canWait),
      ('can_bar', L.capBar, employee.canBar),
      ('can_kitchen', L.capKitchen, employee.canKitchen),
      ('can_manage_menu', L.capMenu, employee.canManageMenu),
    ];

    Future<void> toggle(String field, bool value) async {
      final err = await state.setEmployeeCapability(employee.id, field, value);
      if (err != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
      }
    }

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(label: employee.name),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(employee.name,
                  style:
                      T.h3.copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
              Text('${roleLabel(roleFromWire(role))} · @${employee.username}',
                  style: T.priceSmall.copyWith(color: AppTheme.ink2)),
            ]),
          ),
          if (boss)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(L.fullAccess,
                  style: T.label.copyWith(
                      color: AppTheme.success, fontWeight: FontWeight.w800)),
            ),
        ]),
        if (!boss) ...[
          const SizedBox(height: 6),
          ...caps.map((c) {
            final isRoleBase = c.$1 == roleField;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(child: Text(c.$2, style: T.body)),
                if (isRoleBase)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppTheme.separator,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(L.includedWithRole,
                        style: T.label.copyWith(
                            color: AppTheme.ink2, fontWeight: FontWeight.w700)),
                  )
                else
                  Switch.adaptive(
                    value: c.$3,
                    activeThumbColor: AppTheme.success,
                    onChanged: (v) => toggle(c.$1, v),
                  ),
              ]),
            );
          }),
        ],
      ]),
    );
  }
}

class StaffMemberRow extends StatelessWidget {
  const StaffMemberRow({super.key, required this.employee});
  final EmployeeDto employee;
  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(children: [
        Avatar(label: employee.name),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(employee.name,
              style: T.h3.copyWith(fontWeight: FontWeight.w700, fontSize: 16)),
          Text(
              '${roleLabel(roleFromWire(employee.role))} · @${employee.username}',
              style: T.priceSmall.copyWith(color: AppTheme.ink2)),
        ])),
        Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: AppTheme.success, shape: BoxShape.circle)),
      ]),
    );
  }
}

void _showStaffForm(BuildContext context) {
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  var role = UserRole.waiter;
  var busy = false;
  // A manager can create floor/station staff and other managers, but not
  // admins — mirrors the hub's StaffAccountCreateView.CREATABLE_ROLES.
  final roleOptions =
      UserRole.values.where((r) => r != UserRole.admin).toList();
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
                  Text(L.newStaffMember, style: T.h2),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                        child: AppTextField(
                            controller: firstName, label: L.firstName)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: AppTextField(
                            controller: lastName, label: L.lastName)),
                  ]),
                  const SizedBox(height: 12),
                  AppTextField(
                      controller: username,
                      label: L.username,
                      keyboardType: TextInputType.visiblePassword),
                  const SizedBox(height: 12),
                  AppTextField(
                      controller: password, label: L.password, obscure: true),
                  const SizedBox(height: 12),
                  DropdownButtonFormField(
                      initialValue: role,
                      items: roleOptions
                          .map((r) => DropdownMenuItem(
                              value: r, child: Text(roleLabel(r))))
                          .toList(),
                      onChanged: (v) => set(() => role = v!)),
                  const SizedBox(height: 20),
                  AppButton(
                      label: L.createAccount,
                      onPressed: busy
                          ? null
                          : () async {
                              final first = firstName.text.trim();
                              final last = lastName.text.trim();
                              final nm = [first, last]
                                  .where((part) => part.isNotEmpty)
                                  .join(' ');
                              final un = username.text.trim();
                              final pw = password.text;
                              if (first.isEmpty ||
                                  last.isEmpty ||
                                  un.isEmpty ||
                                  pw.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(L.fillAllFields)));
                                return;
                              }
                              set(() => busy = true);
                              final err = await context
                                  .read<CafeState>()
                                  .createStaffAccount(
                                      name: nm,
                                      firstName: first,
                                      lastName: last,
                                      username: un,
                                      password: pw,
                                      role: role);
                              if (!context.mounted) return;
                              if (err != null) {
                                set(() => busy = false);
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text(err)));
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(L.accountCreated)));
                              Navigator.pop(context);
                            }),
                ]),
              )));
}
