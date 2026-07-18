import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../state/cafe_state.dart';
import '../../widgets/alert_banner.dart';
import '../chat/chat.dart';
import '../orders/order_feed.dart';
import '../panel/staff_panel.dart';
import '../tables/table_grid.dart';

// ================= SCREENS =================

// ===== MAIN SHELL (PageView tabs + swipe navigation) =====

class _ShellTab {
  const _ShellTab(this.id, this.label, this.icon, this.page, {this.badge = 0});
  final ShellDestination id;
  final String label;
  final IconData icon;
  final Widget page;
  final int badge;
}

enum ShellDestination { team, work, manage }

ShellDestination defaultShellDestination({
  required bool isPlatformOwner,
  required bool canManage,
  required bool worksOrders,
  required bool isOnShift,
}) {
  if (isPlatformOwner) return ShellDestination.manage;
  if (canManage && !isOnShift) return ShellDestination.manage;
  if (worksOrders && isOnShift) return ShellDestination.work;
  if (canManage) return ShellDestination.manage;
  return ShellDestination.team;
}

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});
  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  PageController _pageController = PageController();
  int _currentIndex = 0;
  ShellDestination? _currentDestination;
  String _lastSignature = '';
  bool? _lastOnShift;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Four stable workspaces at most. Catalog, coupons and content live under
  /// Manage instead of competing with daily service in the footer.
  List<_ShellTab> _tabsFor(CafeState state) => [
        _ShellTab(ShellDestination.team, L.team, Icons.forum_outlined,
            const StaffChatListScreen(),
            badge: state.chatUnreadTotal),
        if (state.worksOrders && state.isOnShift)
          _ShellTab(
              ShellDestination.work,
              L.t('Work', 'Lavoro'),
              state.canSeeTables ? Icons.table_bar : Icons.assignment,
              state.canSeeTables
                  ? const WaiterTableGridScreen()
                  : const UnifiedOrderFeedScreen(),
              badge:
                  state.canSeeTables ? state.pendingApprovalOrders.length : 0),
        if (state.canSeeManage)
          _ShellTab(ShellDestination.manage, L.t('Manage', 'Gestisci'),
              Icons.space_dashboard_outlined, const StaffPanelScreen()),
      ];

  void _syncTabs(CafeState state, List<_ShellTab> tabs) {
    final signature = tabs.map((tab) => tab.id.name).join('|');
    final shiftStarted = _lastOnShift == false && state.isOnShift;
    _lastOnShift = state.isOnShift;
    if (_lastSignature == signature && !shiftStarted) return;
    _lastSignature = signature;
    final ids = tabs.map((tab) => tab.id).toSet();
    final fallback = defaultShellDestination(
      isPlatformOwner: state.isPlatformOwner,
      canManage: state.canSeeManage,
      worksOrders: state.worksOrders,
      isOnShift: state.isOnShift,
    );
    final next = shiftStarted && ids.contains(ShellDestination.work)
        ? ShellDestination.work
        : ids.contains(_currentDestination)
            ? _currentDestination!
            : ids.contains(fallback)
                ? fallback
                : tabs.first.id;
    _currentDestination = next;
    _currentIndex = tabs.indexWhere((tab) => tab.id == next);
    final old = _pageController;
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final tabs = _tabsFor(state);

    _syncTabs(state, tabs);

    void select(int index) {
      setState(() {
        _currentIndex = index;
        _currentDestination = tabs[index].id;
      });
      _pageController.animateToPage(index,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic);
    }

    final content = Column(
      children: [
        const AlertBannerStack(),
        Expanded(
          child: PageView(
            key: ValueKey(_lastSignature),
            controller: _pageController,
            onPageChanged: (index) => setState(() {
              _currentIndex = index;
              _currentDestination = tabs[index].id;
            }),
            children: tabs.map((tab) => tab.page).toList(),
          ),
        ),
      ],
    );

    // The bottom nav is ALWAYS visible on the shell. The old multi-select
    // flow hid it (state.shellHideNav) and never brought it back after the
    // precheck was confirmed — waiters ended up on «Orders» with no tabs at
    // all. Ordering now happens on a dedicated pushed screen, so the shell
    // never needs to hide its navigation.
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Scaffold(
          backgroundColor: AppTheme.bg,
          body: wide
              ? Row(children: [
                  _ShellRail(
                    tabs: tabs,
                    selectedIndex: _currentIndex,
                    onTap: select,
                    showShift: state.worksOrders,
                  ),
                  VerticalDivider(
                      width: 1, color: Theme.of(context).dividerColor),
                  Expanded(child: content),
                ])
              : content,
          bottomNavigationBar: wide
              ? null
              : _ShellBottomNav(
                  selectedIndex: _currentIndex,
                  onTap: select,
                  labels: tabs.map((t) => t.label).toList(),
                  icons: tabs.map((t) => t.icon).toList(),
                  badges: tabs.map((t) => t.badge).toList(),
                  showShift: state.worksOrders,
                ),
        );
      },
    );
  }
}

class _ShellRail extends StatelessWidget {
  const _ShellRail({
    required this.tabs,
    required this.selectedIndex,
    required this.onTap,
    required this.showShift,
  });
  final List<_ShellTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final bool showShift;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: NavigationRail(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          selectedIndex: selectedIndex,
          onDestinationSelected: onTap,
          labelType: NavigationRailLabelType.all,
          trailing: showShift
              ? const Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: ShiftFooterControl(compact: true),
                    ),
                  ),
                )
              : null,
          destinations: tabs
              .map((tab) => NavigationRailDestination(
                    icon: Badge(
                      isLabelVisible: tab.badge > 0,
                      label: Text('${tab.badge}'),
                      child: Icon(tab.icon),
                    ),
                    label: Text(tab.label),
                  ))
              .toList(),
        ),
      );
}

class _ShellBottomNav extends StatelessWidget {
  const _ShellBottomNav({
    required this.selectedIndex,
    required this.onTap,
    required this.labels,
    required this.icons,
    required this.badges,
    required this.showShift,
  });
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<String> labels;
  final List<IconData> icons;
  final List<int> badges;
  final bool showShift;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:
            Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: SafeArea(
            top: false,
            child: Row(children: [
              Expanded(
                  child: NavigationBar(
                backgroundColor: Colors.transparent,
                indicatorColor: Colors.transparent,
                selectedIndex: selectedIndex,
                onDestinationSelected: onTap,
                destinations: List.generate(labels.length, (i) {
                  final active = i == selectedIndex;
                  final icon = Icon(icons[i],
                      color: active ? AppTheme.ink : const Color(0xFFA8A091));
                  return NavigationDestination(
                    icon: badges[i] > 0
                        ? Badge(
                            label: Text('${badges[i]}'),
                            backgroundColor: AppTheme.warning,
                            child: icon)
                        : icon,
                    label: labels[i],
                  );
                }),
              )),
              if (showShift) ...[
                const SizedBox(width: 4),
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: ShiftFooterControl(),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
