import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';
import 'campaign_manager.dart';
import 'issue_coupon.dart';
import 'redeem_coupon.dart';

/// The "Coupons" area. Tabs follow the capability split:
///   Issue / Redeem — `discount` (a manager-granted flag, boss included);
///   Campaigns      — `content` (SMM's marketing job: CRUD + UTM counters).
/// The shell shows the area when either capability is present; here the tab
/// set narrows to what this person may actually do.
class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});
  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  int _tabCount = 0;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final tabs = <Tab>[
      if (state.capDiscount) Tab(text: L.issueTab),
      if (state.capDiscount) Tab(text: L.redeemTab),
      if (state.canSeeContent) Tab(text: L.campaignsTab),
    ];
    final pages = <Widget>[
      if (state.capDiscount) const IssueCouponScreen(),
      if (state.capDiscount) const RedeemCouponScreen(),
      if (state.canSeeContent) const CampaignManagerScreen(),
    ];
    // Capabilities can change on re-bootstrap — rebuild the controller when
    // the tab set does.
    if (_tabController == null || _tabCount != tabs.length) {
      _tabController?.dispose();
      _tabCount = tabs.length;
      _tabController = TabController(length: tabs.length, vsync: this);
    }

    return AppScaffold(
      bottomNav: null,
      child: Column(
        children: [
          Header(title: L.coupons, subtitle: L.couponsSub, actions: [
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
              tabs: tabs,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const AlwaysScrollableScrollPhysics(),
              children: pages,
            ),
          ),
        ],
      ),
    );
  }
}
