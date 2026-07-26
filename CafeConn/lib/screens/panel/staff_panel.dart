import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils.dart';
import '../../data/dtos.dart';
import '../../data/api_config.dart';
import '../../models/models.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';
import '../content/content_screen.dart';
import '../coupons/coupons_screen.dart';
import '../planner/planner.dart';

class StaffPanelScreen extends StatelessWidget {
  const StaffPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    void open(Widget page) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => page,
          ),
        );

    return AppScaffold(
      bottomNav: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Header(
              title: L.t('Manage', 'Gestisci'),
              subtitle: L.systemManagement,
              actions: [
                IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => GoRouter.of(context).push('/settings')),
              ]),
          if (state.availableRestaurants.length > 1) ...[
            _RestaurantSwitcher(state: state),
            const SizedBox(height: 14),
          ] else if (state.isPlatformOwner) ...[
            _RestaurantSwitcher(state: state),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: ListView(children: [
              if (state.isPlatformOwner) const _OwnerPortfolio(),
              if (state.capReports || state.capManage)
                _ManageGroup(
                  title: L.t('Today', 'Oggi'),
                  items: [
                    if (state.capReports)
                      _ManageItem(
                          L.overview,
                          L.t('Sales, pace and occupancy',
                              'Vendite, ritmo e occupazione'),
                          Icons.insights_outlined,
                          () => open(_ManagePage(
                              title: L.overview, child: _OverviewTab()))),
                    if (state.capManage)
                      _ManageItem(
                          L.planner,
                          L.plannerSub,
                          Icons.event_note_outlined,
                          () => open(const PlannerScreen())),
                    if (state.capReports)
                      _ManageItem(
                          L.history,
                          L.t('Orders signed by the serving waiter',
                              'Ordini firmati dal cameriere'),
                          Icons.receipt_long_outlined,
                          () => open(_ManagePage(
                              title: L.history,
                              child: const _OrderHistoryTab()))),
                  ],
                ),
              if (state.capManage)
                _ManageGroup(
                  title: L.team,
                  items: [
                    _ManageItem(
                        L.team,
                        L.t('People, roles and shift status',
                            'Persone, ruoli e stato turno'),
                        Icons.groups_outlined,
                        () => open(_ManagePage(
                            title: L.team,
                            child: const TeamManagementScreen()))),
                    _ManageItem(
                        L.access,
                        L.t('Effective capabilities by person',
                            'Permessi effettivi per persona'),
                        Icons.admin_panel_settings_outlined,
                        () => open(
                            _ManagePage(title: L.access, child: _AccessTab()))),
                  ],
                ),
              if (state.capMenu || state.canSeeCoupons)
                _ManageGroup(
                  title: L.t('Catalog & offers', 'Catalogo e offerte'),
                  items: [
                    if (state.capMenu)
                      _ManageItem(
                          L.menu,
                          L.t('Items, categories and availability',
                              'Prodotti, categorie e disponibilità'),
                          Icons.restaurant_menu_outlined,
                          () => open(_ManagePage(
                              title: L.menu,
                              child: const MenuManagementScreen()))),
                    if (state.canSeeCoupons)
                      _ManageItem(
                          L.coupons,
                          L.couponsSub,
                          Icons.confirmation_number_outlined,
                          () => open(const CouponsScreen())),
                  ],
                ),
              if (state.canSeeContent)
                _ManageGroup(
                  title: L.t('Public presence', 'Presenza pubblica'),
                  items: [
                    _ManageItem(
                        L.t('Guest page', 'Pagina ospiti'),
                        L.t('Open, copy or show the restaurant QR',
                            'Apri, copia o mostra il QR del ristorante'),
                        Icons.link_rounded,
                        () => open(const _PublicPresenceScreen())),
                    _ManageItem(
                        L.t('Table links', 'Link dei tavoli'),
                        L.t('Open, copy, download and print table QRs',
                            'Apri, copia, scarica e stampa i QR'),
                        Icons.qr_code_2_rounded,
                        () => open(const _TableLinksScreen())),
                    _ManageItem(
                        L.content,
                        L.contentSub,
                        Icons.storefront_outlined,
                        () => open(const ContentScreen())),
                  ],
                ),
              const SizedBox(height: 24),
            ]),
          ),
        ],
      ),
    );
  }
}

class _ManageItem {
  const _ManageItem(this.title, this.subtitle, this.icon, this.onTap);
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _ManageGroup extends StatelessWidget {
  const _ManageGroup({required this.title, required this.items});
  final String title;
  final List<_ManageItem> items;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle(title),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.separator),
            ),
            child: Column(children: [
              for (var index = 0; index < items.length; index++) ...[
                ListTile(
                  minTileHeight: 58,
                  leading: Icon(items[index].icon, color: AppTheme.ink2),
                  title: Text(items[index].title, style: T.bodySemi),
                  subtitle: Text(items[index].subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.small.copyWith(color: AppTheme.ink2)),
                  trailing:
                      const Icon(Icons.chevron_right, color: AppTheme.ink3),
                  onTap: items[index].onTap,
                ),
                if (index < items.length - 1)
                  const Divider(height: 1, indent: 56),
              ],
            ]),
          ),
        ]),
      );
}

class _RestaurantSwitcher extends StatelessWidget {
  const _RestaurantSwitcher({required this.state});
  final CafeState state;

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController();
    final slug = TextEditingController();
    final create = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L.t('Add restaurant', 'Aggiungi ristorante')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: name,
            autofocus: true,
            decoration: InputDecoration(labelText: L.t('Name', 'Nome')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: slug,
            decoration: const InputDecoration(labelText: 'URL slug'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(L.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(L.t('Create', 'Crea'))),
        ],
      ),
    );
    if (create != true ||
        name.text.trim().isEmpty ||
        slug.text.trim().isEmpty) {
      name.dispose();
      slug.dispose();
      return;
    }
    final error = await state.createRestaurant(
        name.text.trim(), slug.text.trim().toLowerCase());
    name.dispose();
    slug.dispose();
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: DropdownButtonFormField<String>(
          initialValue: state.activeRestaurant?.slug,
          decoration: InputDecoration(
            labelText: L.t('Restaurant', 'Ristorante'),
            prefixIcon: const Icon(Icons.storefront_outlined),
          ),
          items: state.availableRestaurants
              .map((restaurant) => DropdownMenuItem(
                  value: restaurant.slug, child: Text(restaurant.name)))
              .toList(),
          onChanged: (slug) async {
            final restaurant = state.availableRestaurants
                .firstWhere((item) => item.slug == slug);
            final error = await state.switchRestaurant(restaurant);
            if (error != null && context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(error)));
            }
          },
        )),
        if (state.isPlatformOwner) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton.filled(
              tooltip: L.t('Add restaurant', 'Aggiungi ristorante'),
              onPressed: () => _create(context),
              icon: const Icon(Icons.add),
            ),
          ),
        ],
      ]);
}

class _ManagePage extends StatelessWidget {
  const _ManagePage({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppScaffold(
        bottomNav: null,
        child: Column(children: [
          Header(
            title: title,
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            actions: const [],
          ),
          Expanded(child: child),
        ]),
      );
}

String _publicUrl(String suffix) {
  final base = Uri.parse(ApiConfig.baseUrl);
  return base.resolve(suffix).toString();
}

Future<void> _openExternal(String url) => launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );

void _copyLink(BuildContext context, String url) {
  Clipboard.setData(ClipboardData(text: url));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(L.t('Link copied', 'Link copiato'))),
  );
}

Future<void> _showQr(BuildContext context, String title, String url) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 260,
          height: 300,
          child: Column(children: [
            Expanded(
              child: QrImageView(
                data: url,
                backgroundColor: Colors.white,
                padding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(url, textAlign: TextAlign.center, style: T.small),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => _copyLink(dialogContext, url),
            child: Text(L.t('Copy link', 'Copia link')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(L.t('Done', 'Fine')),
          ),
        ],
      ),
    );

class _PublicPresenceScreen extends StatelessWidget {
  const _PublicPresenceScreen();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final restaurant = state.activeRestaurant;
    final url =
        _publicUrl('/r/${restaurant?.slug ?? ApiConfig.restaurantSlug}/');
    return AppScaffold(
      bottomNav: null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Header(
          title: L.t('Guest page', 'Pagina ospiti'),
          subtitle: restaurant?.name,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(L.t('Public restaurant link', 'Link pubblico del ristorante'),
                style: T.bodySemi),
            const SizedBox(height: 8),
            SelectableText(url, style: T.small.copyWith(color: AppTheme.ink2)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => _openExternal(url),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(L.t('Open', 'Apri')),
              ),
              OutlinedButton.icon(
                onPressed: () => _copyLink(context, url),
                icon: const Icon(Icons.copy_rounded),
                label: Text(L.t('Copy', 'Copia')),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _showQr(context, restaurant?.name ?? 'CafeConnect', url),
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('QR'),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _TableLinksScreen extends StatelessWidget {
  const _TableLinksScreen();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final slug = state.activeRestaurant?.slug ?? ApiConfig.restaurantSlug;
    return AppScaffold(
      bottomNav: null,
      child: Column(children: [
        Header(
          title: L.t('Table links', 'Link dei tavoli'),
          subtitle: state.activeRestaurant?.name,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: state.tables.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final table = state.tables[index];
              final url = _publicUrl('/r/$slug/n/${table.number}/');
              final svg =
                  _publicUrl('/r/$slug/qr/n/${table.number}.svg?download=1');
              final print = _publicUrl('/r/$slug/qr/n/${table.number}/print/');
              return AppCard(
                child: Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text('${table.number}', style: T.h3),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(L.tableN(table.number), style: T.bodySemi)),
                  IconButton(
                    tooltip: L.t('Open', 'Apri'),
                    onPressed: () => _openExternal(url),
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                  IconButton(
                    tooltip: L.t('Copy', 'Copia'),
                    onPressed: () => _copyLink(context, url),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  PopupMenuButton<String>(
                    tooltip: L.t('More', 'Altro'),
                    onSelected: (action) {
                      if (action == 'qr') {
                        _showQr(context, L.tableN(table.number), url);
                      } else if (action == 'download') {
                        _openExternal(svg);
                      } else {
                        _openExternal(print);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'qr',
                          child: Text(L.t('Show QR', 'Mostra QR'))),
                      PopupMenuItem(
                          value: 'download',
                          child: Text(L.t('Download SVG', 'Scarica SVG'))),
                      PopupMenuItem(
                          value: 'print', child: Text(L.t('Print', 'Stampa'))),
                    ],
                  ),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _OwnerPortfolio extends StatefulWidget {
  const _OwnerPortfolio();

  @override
  State<_OwnerPortfolio> createState() => _OwnerPortfolioState();
}

class _OwnerPortfolioState extends State<_OwnerPortfolio> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<CafeState>().refreshPortfolio());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final restaurants = state.portfolioRestaurants;
    if (state.portfolioLoading && restaurants.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }
    return _ManageGroup(
      title: L.t('Portfolio', 'Portafoglio'),
      items: restaurants
          .map((restaurant) => _ManageItem(
                restaurant.name,
                '${restaurant.currency} ${restaurant.todaySales.toStringAsFixed(2)} · '
                '${restaurant.activeTables}/${restaurant.tableCount} ${L.tables.toLowerCase()} · '
                '${restaurant.openCalls} ${L.t('calls', 'chiamate')} · '
                '${restaurant.onShiftStaff} ${L.onShift.toLowerCase()}',
                restaurant.openCalls > 0
                    ? Icons.notifications_active_outlined
                    : Icons.storefront_outlined,
                () => state.switchRestaurant(restaurant),
              ))
          .toList(),
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
          // The day's number is the hero (impeccable product register: money
          // leads, chrome recedes) — no more four identical metric cards.
          AppCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(L.revenue,
                    style: T.label.copyWith(
                        color: AppTheme.ink2, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (s?.revenueDeltaPct != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: ((s!.revenueDeltaPct ?? 0) >= 0
                              ? AppTheme.success
                              : AppTheme.danger)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(L.vsYesterday(s.revenueDeltaPct!),
                        style: T.label.copyWith(
                            color: (s.revenueDeltaPct ?? 0) >= 0
                                ? AppTheme.success
                                : AppTheme.danger,
                            fontWeight: FontWeight.w800)),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(revenue.rub,
                  style: AppTypography.mono(
                      size: 34, weight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 8),
              Text(
                  '$ordersToday ${L.orders.toLowerCase()} · '
                  '${L.avgCheck.toLowerCase()} ${avgCheck.rub} · '
                  '${L.bestHour.toLowerCase()} ${bestHour.hour}:00',
                  style: T.smallSemi.copyWith(color: AppTheme.ink2)),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _StatCell(
                label: L.tables,
                value: '$activeTables/$totalTables',
                sub: '${L.freeCount(freeTables)} · $servedTables ✓',
                color: AppTheme.tOccupied,
                progress: occupancy,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCell(
                label: L.avgPrepTime,
                value: L.minutesShort(s?.avgPrepMinutes ?? 0),
                sub: '${L.inProgress}: ${activeOrders.length}',
                color: AppTheme.warning,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCell(
                label: L.delayedLabel,
                value: '$delayed',
                sub: delayed == 0 ? L.onTime : L.oldestMin(localOldestMin),
                color: delayed == 0 ? AppTheme.success : AppTheme.danger,
              ),
            ),
          ]),
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
                                              : AppColors.sunken,
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
          // What's actually selling today — top 5 by quantity, category-colored.
          if (s != null && s.topItems.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionTitle(L.topDishesToday),
            AppCard(
              child: Column(children: [
                for (var i = 0; i < s.topItems.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                        bottom: i == s.topItems.length - 1 ? 0 : 12),
                    child: Row(children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: state
                                  .categoryColorForName(s.topItems[i].category),
                              shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(s.topItems[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.bodySemi),
                      ),
                      Text('${s.topItems[i].qty}×',
                          style: AppTypography.mono(
                              size: 13,
                              weight: FontWeight.w800,
                              color: AppColors.ink55)),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 76,
                        child: Text(s.topItems[i].revenue.rub,
                            textAlign: TextAlign.right,
                            style: AppTypography.mono(
                                size: 13,
                                weight: FontWeight.w800,
                                color: AppColors.ink)),
                      ),
                    ]),
                  ),
              ]),
            ),
          ],
          if (s != null && s.byWaiter.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionTitle(L.byWaiter),
            ...s.byWaiter.map((w) => _WaiterStatRow(waiter: w)),
          ],
        ],
      ),
    );
  }
}

/// One compact supporting stat under the revenue hero: label, mono value,
/// colored sub-line, optional occupancy bar.
class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    this.progress,
  });
  final String label;
  final String value;
  final String sub;
  final Color color;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.label.copyWith(color: AppTheme.ink3)),
        const SizedBox(height: 6),
        Text(value,
            style: AppTypography.mono(
                size: 20, weight: FontWeight.w800, color: AppColors.ink)),
        if (progress != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress!.clamp(0.0, 1.0),
              backgroundColor: AppTheme.surfaceSunken,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
        const SizedBox(height: 5),
        Text(sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.label.copyWith(color: color, fontWeight: FontWeight.w800)),
      ]),
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
    // Owner (admin) accounts are super-users managed from /system-admin/ —
    // they don't belong on the floor team list and managers can't edit them.
    final staff = state.staffAccounts.where((e) => e.role != 'admin').toList();
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
  String _category = 'All';
  String _visibility = 'all';

  List<MenuItem> _filtered(CafeState state) {
    final q = _search.trim().toLowerCase();
    return state.menu.where((m) {
      final okCat = _category == 'All' || state.itemInCategory(m, _category);
      final guest = m.tags.contains('client');
      final okVisibility = _visibility == 'all' ||
          (_visibility == 'guest' && guest) ||
          (_visibility == 'staff' && !guest);
      final okSearch = q.isEmpty ||
          m.name.toLowerCase().contains(q) ||
          m.nameIt.toLowerCase().contains(q) ||
          m.category.toLowerCase().contains(q);
      return okCat && okSearch && okVisibility;
    }).toList()
      ..sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
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
        IconButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final error = await state.copyMenuSnapshot();
            messenger.showSnackBar(SnackBar(
              content: Text(error ??
                  L.t('Full menu snapshot copied',
                      'Snapshot completo del menu copiato')),
              backgroundColor:
                  error == null ? AppTheme.success : AppTheme.danger,
            ));
          },
          tooltip: L.t('Copy full menu snapshot', 'Copia snapshot completo'),
          icon: const Icon(Icons.content_copy_rounded, color: AppTheme.ink2),
        ),
        // Owner's category console: rename + recolor menu categories.
        IconButton(
          onPressed: () => _showCategoryEditor(context),
          tooltip: L.categoriesTitle,
          icon: const Icon(Icons.palette_outlined, color: AppTheme.ink2),
        ),
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
      Row(children: [
        for (final option in const [
          ('all', 'All'),
          ('guest', 'Guest menu'),
          ('staff', 'Staff only'),
        ])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 5),
              child: ChoiceChip(
                label: Center(child: Text(option.$2)),
                selected: _visibility == option.$1,
                onSelected: (_) => setState(() => _visibility = option.$1),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 5, runSpacing: 5, children: [
        _categoryBtn(L.all, 'All', AppColors.espresso),
        if (state.menuCategories.isNotEmpty)
          for (final category in state.menuCategories)
            _categoryBtn(category.name, category.id, category.color)
        else
          for (final category in MenuCategories.all)
            _categoryBtn(category, category, AppColors.categoryColor(category)),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(L.itemsCount(items.length),
            style: T.label.copyWith(color: AppTheme.ink3)),
      ),
      ...items.map((item) {
        final famColor = state.categoryColorFor(item);
        return AppCard(
          padding: const EdgeInsets.all(12),
          onTap: () => _showMenuForm(context, item: item),
          child: Row(
            children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: famColor, shape: BoxShape.circle)),
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

/// The owner's category console: every category with its color; tap one to
/// rename it or pick a new color. Changes go to the hub and every device.
void _showCategoryEditor(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Consumer<CafeState>(
      builder: (context, state, _) => Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        decoration: const BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(L.categoriesTitle, style: T.h2)),
              IconButton(
                onPressed: state.backendConnected
                    ? () => _createCategory(context)
                    : null,
                tooltip: L.addCategory,
                icon:
                    const Icon(Icons.add_circle_outline, color: AppTheme.ink2),
              ),
            ]),
            const SizedBox(height: 4),
            Text(L.categoriesSub,
                style: T.small.copyWith(color: AppTheme.ink2)),
            const SizedBox(height: 14),
            if (state.menuCategories.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                    state.backendConnected ? L.noCategories : L.connectToManage,
                    style: T.body.copyWith(color: AppTheme.ink2)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final category in state.menuCategories)
                      AppCard(
                        padding: const EdgeInsets.all(12),
                        onTap: () => _editCategory(context, category),
                        child: Row(children: [
                          Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                  color: category.color,
                                  borderRadius: BorderRadius.circular(7))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(category.name, style: T.bodySemi)),
                          const Icon(Icons.edit_outlined,
                              size: 16, color: AppTheme.ink3),
                        ]),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

void _createCategory(BuildContext context) {
  final state = context.read<CafeState>();
  final name = TextEditingController();
  var selected =
      _categoryPalette[state.menuCategories.length % _categoryPalette.length];
  var busy = false;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StatefulBuilder(
      builder: (context, set) => Container(
        decoration: const BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L.addCategory, style: T.h2),
            const SizedBox(height: 16),
            AppTextField(controller: name, label: L.name),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hex in _categoryPalette)
                  GestureDetector(
                    onTap: () => set(() => selected = hex),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: CafeCategory.parseHex(hex, AppColors.free),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: selected == hex
                                ? AppColors.ink
                                : AppTheme.separator,
                            width: selected == hex ? 2.5 : 1),
                      ),
                      child: selected == hex
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            AppButton(
              label: L.addCategory,
              icon: Icons.add,
              onPressed: busy
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final nm = name.text.trim();
                      if (nm.isEmpty) return;
                      set(() => busy = true);
                      final err = await context
                          .read<CafeState>()
                          .createMenuCategory(name: nm, color: selected);
                      if (!context.mounted) return;
                      if (err != null) {
                        set(() => busy = false);
                        messenger.showSnackBar(SnackBar(content: Text(err)));
                        return;
                      }
                      messenger.showSnackBar(SnackBar(
                          content: Text(L.savedToHub),
                          backgroundColor: AppTheme.success));
                      Navigator.pop(context);
                    },
            ),
          ],
        ),
      ),
    ),
  );
}

// Curated swatches: the 8 defaults plus 8 extras, all readable on the cream
// surface. The owner picks; hex lands in the DB and every surface follows.
const _categoryPalette = [
  '#E0823A',
  '#5BAEDC',
  '#3E9C63',
  '#C0463B',
  '#3C7BCF',
  '#DFAF2B',
  '#8A6FC0',
  '#7CC488',
  '#B98A3C',
  '#D9564A',
  '#5B86B0',
  '#C95D8F',
  '#8C6239',
  '#2E8B8B',
  '#6B7F3A',
  '#4A4238',
];

String _hexOf(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

void _editCategory(BuildContext context, CafeCategory category) {
  final name = TextEditingController(text: category.name);
  var selected = _hexOf(category.color);
  var busy = false;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StatefulBuilder(
      builder: (context, set) => Container(
        decoration: const BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(category.name, style: T.h2),
            const SizedBox(height: 16),
            AppTextField(controller: name, label: L.name),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hex in _categoryPalette)
                  GestureDetector(
                    onTap: () => set(() => selected = hex),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: CafeCategory.parseHex(hex, AppColors.free),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: selected == hex
                                ? AppColors.ink
                                : AppTheme.separator,
                            width: selected == hex ? 2.5 : 1),
                      ),
                      child: selected == hex
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: AppButton(
                  label: L.deleteCategory,
                  kind: ButtonKind.ghost,
                  icon: Icons.delete_outline,
                  color: AppTheme.danger.withValues(alpha: 0.08),
                  onPressed: busy
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          set(() => busy = true);
                          final err = await context
                              .read<CafeState>()
                              .deleteMenuCategory(category.id);
                          if (!context.mounted) return;
                          if (err != null) {
                            set(() => busy = false);
                            messenger
                                .showSnackBar(SnackBar(content: Text(err)));
                            return;
                          }
                          messenger.showSnackBar(SnackBar(
                              content: Text(L.savedToHub),
                              backgroundColor: AppTheme.success));
                          Navigator.pop(context);
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: L.save,
                  onPressed: busy
                      ? null
                      : () async {
                          final state = context.read<CafeState>();
                          final messenger = ScaffoldMessenger.of(context);
                          final nm = name.text.trim();
                          if (nm.isEmpty) return;
                          set(() => busy = true);
                          final err = await state.updateMenuCategory(
                              category.id,
                              name: nm,
                              color: selected);
                          if (!context.mounted) return;
                          if (err != null) {
                            set(() => busy = false);
                            messenger
                                .showSnackBar(SnackBar(content: Text(err)));
                            return;
                          }
                          messenger.showSnackBar(SnackBar(
                              content: Text(L.savedToHub),
                              backgroundColor: AppTheme.success));
                          Navigator.pop(context);
                        },
                ),
              ),
            ]),
          ],
        ),
      ),
    ),
  );
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
  final state = context.read<CafeState>();
  final categories = List<CafeCategory>.of(state.menuCategories);
  var selectedCategoryId = item?.categoryId ?? '';
  if (selectedCategoryId.isEmpty && item != null) {
    selectedCategoryId = state.categoryFor(item)?.id ?? '';
  }
  if (selectedCategoryId.isEmpty && item == null && categories.isNotEmpty) {
    selectedCategoryId = categories.first.id;
  }
  final priceInputFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
  ];
  final name = TextEditingController(text: item?.name ?? '');
  final desc = TextEditingController(text: item?.description ?? '');
  final price = TextEditingController(text: item?.price.toString() ?? '');
  final category = TextEditingController(
      text: item?.category ??
          (categories.isNotEmpty ? categories.first.name : 'Kitchen'));
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
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: priceInputFormatters)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: AppTextField(
                            controller: prep,
                            label: L.timeMin,
                            keyboardType: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 12),
                if (categories.isNotEmpty) ...[
                  Text(L.category, style: T.label),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue:
                        categories.any((c) => c.id == selectedCategoryId)
                            ? selectedCategoryId
                            : null,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.surfaceAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(13),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    items: [
                      for (final category in categories)
                        DropdownMenuItem(
                          value: category.id,
                          child: Row(children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: category.color,
                                  shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 10),
                            Flexible(child: Text(category.name)),
                          ]),
                        ),
                    ],
                    onChanged: (value) => setModalState(
                        () => selectedCategoryId = value ?? selectedCategoryId),
                  ),
                ] else
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

                        CafeCategory? selectedCategory;
                        for (final category in categories) {
                          if (category.id == selectedCategoryId) {
                            selectedCategory = category;
                            break;
                          }
                        }
                        final categoryName = selectedCategory?.name ??
                            (category.text.trim().isEmpty
                                ? (item?.category ?? 'Panini')
                                : category.text.trim());
                        final categoryId = selectedCategory?.id ?? '';
                        final parsedPrice = double.tryParse(
                            price.text.trim().replaceAll(',', '.'));

                        final MenuItem target;
                        final isNew = item == null;
                        if (isNew) {
                          target = MenuItem(
                            id: 'm${DateTime.now().millisecondsSinceEpoch}',
                            name: name.text.trim(),
                            description: desc.text.trim(),
                            price: parsedPrice ?? 0.0,
                            category: categoryName,
                            imageUrl: '',
                            tags: tags,
                            prepTime: int.tryParse(prep.text) ?? 10,
                            station: station,
                            promo: guestPromo,
                            categoryId: categoryId,
                          );
                        } else {
                          target = item;
                          target.name = name.text.trim();
                          target.description = desc.text.trim();
                          target.price = parsedPrice ?? target.price;
                          target.category = categoryName;
                          target.categoryIt = '';
                          target.prepTime =
                              int.tryParse(prep.text) ?? target.prepTime;
                          target.station = station;
                          target.tags = tags;
                          target.promo = guestPromo;
                          target.categoryId = categoryId;
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
      'smm' => 'can_content',
      _ => null,
    };
    final caps = <(String, String, bool)>[
      ('can_wait', L.capWaiter, employee.canWait),
      ('can_bar', L.capBar, employee.canBar),
      ('can_kitchen', L.capKitchen, employee.canKitchen),
      ('can_manage_menu', L.capMenu, employee.canManageMenu),
      ('can_content', L.capContent, employee.canContent),
      ('can_grant_discount', L.capDiscount, employee.canGrantDiscount),
      ('can_manage', L.t('Manage', 'Gestione'), employee.canManage),
      ('can_reports', L.t('Reports', 'Report'), employee.canReports),
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
      onTap: () => _showStaffEditSheet(context, employee),
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
        const Icon(Icons.edit_outlined, size: 16, color: AppTheme.ink3),
        const SizedBox(width: 8),
        Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: AppTheme.success, shape: BoxShape.circle)),
      ]),
    );
  }
}

/// Manager taps a member: edit name and role, see the username, change the
/// login (username / new password). Owner accounts never reach this sheet —
/// they're filtered out of the list and the hub refuses them anyway.
void _showStaffEditSheet(BuildContext context, EmployeeDto employee) {
  final name = TextEditingController(text: employee.name);
  final username = TextEditingController(text: employee.username);
  final password = TextEditingController();
  var role = roleFromWire(employee.role);
  var busy = false;
  final roleOptions =
      UserRole.values.where((r) => r != UserRole.admin).toList();
  if (!roleOptions.contains(role)) role = UserRole.waiter;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StatefulBuilder(
      builder: (context, set) => Container(
        decoration: const BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(L.editStaffMember, style: T.h2),
            const SizedBox(height: 20),
            AppTextField(controller: name, label: L.name),
            const SizedBox(height: 12),
            DropdownButtonFormField(
                initialValue: role,
                items: roleOptions
                    .map((r) =>
                        DropdownMenuItem(value: r, child: Text(roleLabel(r))))
                    .toList(),
                onChanged: (v) => set(() => role = v!)),
            const SizedBox(height: 12),
            AppTextField(
                controller: username,
                label: L.username,
                keyboardType: TextInputType.visiblePassword),
            const SizedBox(height: 12),
            AppTextField(
                controller: password,
                label: L.password,
                hint: L.newPasswordHint,
                obscure: true),
            const SizedBox(height: 20),
            AppButton(
                label: L.save,
                onPressed: busy
                    ? null
                    : () async {
                        final state = context.read<CafeState>();
                        final messenger = ScaffoldMessenger.of(context);
                        final nm = name.text.trim();
                        final un = username.text.trim();
                        final pw = password.text;
                        if (nm.isEmpty || un.isEmpty) {
                          messenger.showSnackBar(
                              SnackBar(content: Text(L.fillAllFields)));
                          return;
                        }
                        set(() => busy = true);
                        // Profile (name/role) and login (username/password)
                        // travel on separate endpoints.
                        var err = await state.updateStaffProfile(employee.id,
                            name: nm, role: roleToWire(role));
                        if (err == null &&
                            (un != employee.username || pw.isNotEmpty)) {
                          err = await state.setStaffCredentials(employee.id,
                              username: un != employee.username ? un : null,
                              password: pw.isNotEmpty ? pw : null);
                        }
                        if (!context.mounted) return;
                        if (err != null) {
                          set(() => busy = false);
                          messenger.showSnackBar(SnackBar(content: Text(err)));
                          return;
                        }
                        messenger.showSnackBar(SnackBar(
                            content: Text(L.savedToHub),
                            backgroundColor: AppTheme.success));
                        Navigator.pop(context);
                      }),
          ]),
        ),
      ),
    ),
  );
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
