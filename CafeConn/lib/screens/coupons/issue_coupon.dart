import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../data/dtos.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';

/// Issue: pick an active campaign, get a signed claim link from the hub and
/// show it as a fullscreen high-contrast QR for the guest's phone camera.
class IssueCouponScreen extends StatefulWidget {
  const IssueCouponScreen({super.key});
  @override
  State<IssueCouponScreen> createState() => _IssueCouponScreenState();
}

class _IssueCouponScreenState extends State<IssueCouponScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<CafeState>().refreshCouponCampaigns());
  }

  Future<void> _issue(CouponCampaignDto campaign) async {
    if (_busy) return;
    setState(() => _busy = true);
    final state = context.read<CafeState>();
    final (issue, error) = await state.issueCoupon(campaign.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null || issue == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error ?? L.couldNotLoad),
          backgroundColor: AppTheme.danger));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _IssueQrScreen(issue: issue),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final campaigns = state.issuableCampaigns;

    return RefreshIndicator(
      onRefresh: () => context.read<CafeState>().refreshCouponCampaigns(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(children: [
            Expanded(child: SectionTitle(L.issuePickCampaign)),
            if (state.couponCampaignsLoading)
              const CupertinoActivityIndicator(),
          ]),
          if (campaigns.isEmpty && !state.couponCampaignsLoading)
            EmptyState(
                icon: Icons.confirmation_number_outlined,
                title: L.noCampaigns,
                sub: L.noCampaignsSub)
          else
            ...campaigns.map((campaign) => AppCard(
                  onTap: _busy ? null : () => _issue(campaign),
                  child: Row(children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Center(
                          child: Text(campaign.discountLabel,
                              style: T.priceSmall.copyWith(
                                  color: AppTheme.gold,
                                  fontWeight: FontWeight.w800))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(campaign.displayTitle,
                                style: T.h3, maxLines: 2),
                            const SizedBox(height: 3),
                            Text(
                                L.issuedRedeemed(campaign.issuedCount,
                                    campaign.redeemedCount),
                                style: T.small),
                          ]),
                    ),
                    const Icon(Icons.qr_code_2,
                        size: 26, color: AppTheme.ink2),
                  ]),
                )),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Fullscreen claim QR: white background, black modules — maximum contrast
/// for any guest phone camera, whatever the venue theme.
class _IssueQrScreen extends StatelessWidget {
  const _IssueQrScreen({required this.issue});
  final CouponIssueDto issue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: Text(issue.campaign.displayTitle,
            style: T.h2.copyWith(color: Colors.black)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Text(issue.campaign.discountLabel,
                style: T.screenTitle.copyWith(
                    color: Colors.black, fontSize: 40, letterSpacing: -1)),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: AspectRatio(
                aspectRatio: 1,
                child: QrImageView(
                  data: issue.claimUrl,
                  version: QrVersions.auto,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square, color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(L.showQrToGuest,
                  textAlign: TextAlign.center,
                  style: T.bodySemi.copyWith(color: Colors.black87)),
            ),
            const SizedBox(height: 6),
            Text(L.claimQrExpires,
                style: T.small.copyWith(color: Colors.black45)),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: PrimaryButton(
                label: L.done,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
