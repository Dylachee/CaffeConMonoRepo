import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import 'feed_manager.dart';
import 'storefront_editor.dart';

/// The "Content" section: the venue's public face. Two tabs —
///   Feed: the guest page's social feed (paste URL, pin, hide, delete);
///   Storefront: the venue vibe constructor (texts, palette, layout, images).
/// Visible only with the `content` capability (SMM role, granted
/// can_content, or manager/admin) — the shell gates the tab.
class ContentScreen extends StatefulWidget {
  const ContentScreen({super.key});
  @override
  State<ContentScreen> createState() => _ContentScreenState();
}

class _ContentScreenState extends State<ContentScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      bottomNav: null,
      child: Column(
        children: [
          Header(title: L.content, subtitle: L.contentSub, actions: [
            IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => GoRouter.of(context).push('/settings')),
          ]),
          SizedBox(
            height: 38,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.cta,
              labelColor: AppTheme.ink,
              unselectedLabelColor: AppTheme.ink2,
              tabs: [Tab(text: L.feedTab), Tab(text: L.storefrontTab)],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                FeedManagerScreen(),
                StorefrontEditorScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
