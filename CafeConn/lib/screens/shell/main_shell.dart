import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../chat/chat.dart';
import '../menu/staff_menu.dart';
import '../orders/order_feed.dart';
import '../panel/staff_panel.dart';
import '../tables/table_grid.dart';

// ================= SCREENS =================

// ===== MAIN SHELL (PageView tabs + swipe navigation) =====

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});
  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  late final PageController _pageController;
  int _currentIndex = 0;

  static const _labels = ['Столы', 'Заказы', 'Меню', 'Чаты', 'Панель'];
  static const _icons = [
    Icons.table_bar,
    Icons.assignment,
    Icons.restaurant_menu,
    Icons.chat_bubble,
    Icons.analytics,
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The bottom nav is ALWAYS visible on the shell. The old multi-select
    // flow hid it (state.shellHideNav) and never brought it back after the
    // precheck was confirmed — waiters ended up on «Заказы» with no tabs at
    // all. Ordering now happens on a dedicated pushed screen, so the shell
    // never needs to hide its navigation.
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        children: const [
          WaiterTableGridScreen(),
          UnifiedOrderFeedScreen(),
          StaffMenuScreen(),
          StaffChatListScreen(),
          StaffPanelScreen(),
        ],
      ),
      bottomNavigationBar: _ShellBottomNav(
        selectedIndex: _currentIndex,
        onTap: (i) {
          setState(() => _currentIndex = i);
          _pageController.animateToPage(i,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut);
        },
        labels: _labels,
        icons: _icons,
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
        color: Theme.of(context)
            .scaffoldBackgroundColor
            .withValues(alpha: 0.92),
        border:
            Border(top: BorderSide(color: Theme.of(context).dividerColor)),
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
                    color: active
                        ? AppTheme.ink
                        : const Color(0xFFA8A091)),
                label: labels[i],
              );
            }),
          ),
        ),
      ),
    );
  }
}
