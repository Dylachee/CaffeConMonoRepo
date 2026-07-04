import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'screens/chat/chat.dart';
import 'screens/orders/order_composer.dart';
import 'screens/settings/settings.dart';
import 'screens/shell/main_shell.dart';
import 'screens/tables/table_details.dart';
import 'state/cafe_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Hive.initFlutter();
  await Hive.openBox('cafeconnect');
  runApp(const CafeConnectApp());
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
        GoRoute(
            path: '/tables',
            builder: (_, __) => const MainShellScreen()),
        GoRoute(
            path: '/table-details',
            builder: (_, __) => const TableDetailsScreen()),
        GoRoute(
            path: '/waiter-menu',
            builder: (_, __) => const WaiterOrderScreen()),
        GoRoute(path: '/chat', builder: (_, __) => const StaffChatScreen()),
        GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen()),
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
