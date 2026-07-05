import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../state/cafe_state.dart';
import '../chat/chat.dart';
import '../menu/staff_menu.dart';
import '../orders/order_feed.dart';
import '../panel/staff_panel.dart';
import '../tables/table_grid.dart';

// ================= SCREENS =================

// ===== MAIN SHELL (PageView tabs + swipe navigation) =====

class _ShellTab {
  const _ShellTab(this.label, this.icon, this.page);
  final String label;
  final IconData icon;
  final Widget page;
}

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});
  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  PageController _pageController = PageController();
  int _currentIndex = 0;
  UserRole? _lastRole;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Tab set per role (the whole point of the shell):
  ///   cook / bartender — their order feed, the menu and the chats;
  ///   waiter — everything except the analytics panel;
  ///   manager / admin — everything.
  List<_ShellTab> _tabsFor(CafeState state) => [
        if (state.canSeeTables)
          _ShellTab(L.tables, Icons.table_bar, const WaiterTableGridScreen()),
        _ShellTab(L.orders, Icons.assignment, const UnifiedOrderFeedScreen()),
        _ShellTab(L.menu, Icons.restaurant_menu, const StaffMenuScreen()),
        _ShellTab(L.chats, Icons.chat_bubble, const StaffChatListScreen()),
        if (state.canSeePanel)
          _ShellTab(L.panel, Icons.analytics, const StaffPanelScreen()),
      ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final tabs = _tabsFor(state);

    // Role changed (login/logout): the tab list is different now — restart
    // on the first tab with a fresh controller so the PageView can't sit on
    // an index that no longer exists.
    if (_lastRole != state.currentRole) {
      _lastRole = state.currentRole;
      _currentIndex = 0;
      final old = _pageController;
      _pageController = PageController();
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    if (_currentIndex >= tabs.length) _currentIndex = 0;

    // The bottom nav is ALWAYS visible on the shell. The old multi-select
    // flow hid it (state.shellHideNav) and never brought it back after the
    // precheck was confirmed — waiters ended up on «Orders» with no tabs at
    // all. Ordering now happens on a dedicated pushed screen, so the shell
    // never needs to hide its navigation.
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: PageView(
        key: ValueKey(state.currentRole),
        controller: _pageController,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        children: tabs.map((t) => t.page).toList(),
      ),
      bottomNavigationBar: _ShellBottomNav(
        selectedIndex: _currentIndex,
        onTap: (i) {
          setState(() => _currentIndex = i);
          _pageController.animateToPage(i,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut);
        },
        labels: tabs.map((t) => t.label).toList(),
        icons: tabs.map((t) => t.icon).toList(),
      ),
    );
  }
}

class _ShellBottomNav extends StatelessWidget {
  const _ShellBottomNav({
    required this.selectedIndex,
    required this.onTap,
    required this.labels,
    required this.icons,
  });
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<String> labels;
  final List<IconData> icons;

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
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            indicatorColor: Colors.transparent,
            selectedIndex: selectedIndex,
            onDestinationSelected: onTap,
            destinations: List.generate(labels.length, (i) {
              final active = i == selectedIndex;
              return NavigationDestination(
                icon: Icon(icons[i],
                    color: active ? AppTheme.ink : const Color(0xFFA8A091)),
                label: labels[i],
              );
            }),
          ),
        ),
      ),
    );
  }
}
