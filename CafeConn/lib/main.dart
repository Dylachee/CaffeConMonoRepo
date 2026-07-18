import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'screens/chat/chat.dart';
import 'screens/orders/order_composer.dart';
import 'screens/planner/planner.dart';
import 'screens/settings/settings.dart';
import 'screens/shell/main_shell.dart';
import 'screens/station/station_mode.dart';
import 'screens/tables/table_details.dart';
import 'screens/tables/table_history.dart';
import 'state/cafe_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Hive.initFlutter();
  await Hive.openBox('cafeconnect');
  runApp(const CafeConnectApp());
}

/// Enables cursor/trackpad/stylus dragging in addition to touch, so the
/// tab PageView and horizontal lists swipe with a mouse on web/desktop.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class CafeConnectApp extends StatefulWidget {
  const CafeConnectApp({super.key});
  @override
  State<CafeConnectApp> createState() => _CafeConnectAppState();
}

class _CafeConnectAppState extends State<CafeConnectApp> {
  late final CafeState _cafeState;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _cafeState = CafeState()..boot();
    _router = GoRouter(
      refreshListenable: _cafeState,
      initialLocation: '/tables',
      routes: [
        GoRoute(path: '/tables', builder: (_, __) => const MainShellScreen()),
        GoRoute(
            path: '/table-details',
            builder: (_, __) => const TableDetailsScreen()),
        GoRoute(
            path: '/table-history',
            builder: (_, __) => const TableHistoryScreen()),
        GoRoute(
            path: '/waiter-menu',
            builder: (_, __) => const WaiterOrderScreen()),
        GoRoute(path: '/chat', builder: (_, __) => const StaffChatScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(
            path: '/station', builder: (_, __) => const StationModeScreen()),
        GoRoute(path: '/planner', builder: (_, __) => const PlannerScreen()),
      ],
    );
  }

  @override
  void dispose() {
    _cafeState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _cafeState,
      child: Consumer<CafeState>(
        builder: (context, state, _) => MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'CafeConnect Staff',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: state.themeMode,
          // Let mouse/trackpad drag scroll & swipe on the web/desktop builds
          // (Flutter disables mouse dragging by default) so the tab PageView
          // and the swipe-back gesture respond to the cursor, not just touch.
          scrollBehavior: const _AppScrollBehavior(),
          routerConfig: _router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(state.textScale)),
            child: child!,
          ),
        ),
      ),
    );
  }
}
