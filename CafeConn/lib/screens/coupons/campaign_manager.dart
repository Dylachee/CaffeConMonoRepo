import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../data/dtos.dart';
import '../../models/models.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';

/// Campaigns (SMM / content capability): list with live counters —
/// issued / redeemed / per-utm breakdown — plus create & edit.
class CampaignManagerScreen extends StatefulWidget {
  const CampaignManagerScreen({super.key});
  @override
  State<CampaignManagerScreen> createState() => _CampaignManagerScreenState();
}

class _CampaignManagerScreenState extends State<CampaignManagerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<CafeState>().refreshCouponCampaigns());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final campaigns = state.couponCampaigns;

    return RefreshIndicator(
      onRefresh: () => context.read<CafeState>().refreshCouponCampaigns(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(children: [
            Expanded(child: SectionTitle(L.campaignsTab)),
            if (state.couponCampaignsLoading)
              const CupertinoActivityIndicator()
            else
              AppButton(
                  label: L.newCampaign,
                  kind: ButtonKind.ghost,
                  onPressed: () => _showCampaignSheet(context)),
          ]),
          if (campaigns.isEmpty && !state.couponCampaignsLoading)
            EmptyState(
                icon: Icons.campaign_outlined,
                title: L.noCampaigns,
                sub: L.couponsSub)
          else
            ...campaigns.map((campaign) => _CampaignCard(campaign: campaign)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({required this.campaign});
  final CouponCampaignDto campaign;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => _showCampaignSheet(context, campaign: campaign),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(campaign.discountLabel,
                style: T.priceSmall.copyWith(
                    color: AppTheme.gold, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(campaign.displayTitle, style: T.h3, maxLines: 2)),
          if (!campaign.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppTheme.separator,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(L.stop,
                  style: T.label.copyWith(fontWeight: FontWeight.w800)),
            ),
        ]),
        const SizedBox(height: 8),
        Text(L.issuedRedeemed(campaign.issuedCount, campaign.redeemedCount),
            style: T.smallSemi.copyWith(color: AppTheme.ink2)),
        if (campaign.byUtm.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(L.byUtmTitle, style: T.label),
          const SizedBox(height: 4),
          ...campaign.byUtm.map((row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        row.utmSource.isEmpty ? L.directSource : row.utmSource,
                        style: T.small,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text(L.issuedRedeemed(row.issued, row.redeemed),
                      style: T.small),
                ]),
              )),
        ],
      ]),
    );
  }
}

/// Create / edit sheet. Validation mirrors the hub (positive value, percent
/// ≤ 100); the hub stays the authority and its message is shown verbatim.
void _showCampaignSheet(BuildContext context, {CouponCampaignDto? campaign}) {
  final title = TextEditingController(text: campaign?.title ?? '');
  final titleIt = TextEditingController(text: campaign?.titleIt ?? '');
  final desc = TextEditingController(text: campaign?.description ?? '');
  final descIt = TextEditingController(text: campaign?.descriptionIt ?? '');
  final value = TextEditingController(
      text: campaign == null ? '' : campaign.discountValue.toStringAsFixed(2));
  final utm = TextEditingController(text: campaign?.sourceUtm ?? '');
  final maxIssues = TextEditingController(
      text: campaign?.maxTotalIssues?.toString() ?? '');
  var discountType = campaign?.discountType ?? 'percent';
  var perWallet = campaign?.perWalletLimit ?? 1;
  var isActive = campaign?.isActive ?? true;
  var busy = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StatefulBuilder(
      builder: (sheetContext, set) => Container(
        decoration: const BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(campaign == null ? L.newCampaign : L.editCampaign,
                style: T.h2),
            const SizedBox(height: 18),
            AppTextField(controller: title, label: L.campaignTitleEn),
            const SizedBox(height: 10),
            AppTextField(controller: titleIt, label: L.campaignTitleIt),
            const SizedBox(height: 10),
            AppTextField(controller: desc, label: L.campaignDescEn),
            const SizedBox(height: 10),
            AppTextField(controller: descIt, label: L.campaignDescIt),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: discountType,
                  items: [
                    DropdownMenuItem(
                        value: 'percent', child: Text(L.discountPercent)),
                    DropdownMenuItem(
                        value: 'fixed', child: Text(L.discountFixed)),
                  ],
                  onChanged: (v) => set(() => discountType = v ?? 'percent'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppTextField(
                    controller: value,
                    label: L.discountValueLbl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true)),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: AppTextField(
                    controller: maxIssues,
                    label: L.maxIssuesLbl,
                    keyboardType: TextInputType.number),
              ),
              const SizedBox(width: 10),
              Expanded(child: AppTextField(controller: utm, label: L.utmLbl)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text(L.perWalletLimitLbl, style: T.body)),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed:
                    perWallet > 1 ? () => set(() => perWallet -= 1) : null,
              ),
              Text('$perWallet', style: T.h3),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed:
                    perWallet < 10 ? () => set(() => perWallet += 1) : null,
              ),
            ]),
            Row(children: [
              Expanded(child: Text(L.campaignActive, style: T.body)),
              Switch.adaptive(
                value: isActive,
                activeThumbColor: AppTheme.success,
                onChanged: (v) => set(() => isActive = v),
              ),
            ]),
            const SizedBox(height: 16),
            AppButton(
              label: L.save,
              onPressed: busy
                  ? null
                  : () async {
                      final valueText =
                          value.text.trim().replaceAll(',', '.');
                      final parsed = double.tryParse(valueText);
                      if (title.text.trim().isEmpty ||
                          parsed == null ||
                          parsed <= 0 ||
                          (discountType == 'percent' && parsed > 100)) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(content: Text(L.fillAllFields)));
                        return;
                      }
                      set(() => busy = true);
                      final fields = <String, dynamic>{
                        'title': title.text.trim(),
                        'title_it': titleIt.text.trim(),
                        'description': desc.text.trim(),
                        'description_it': descIt.text.trim(),
                        'discount_type': discountType,
                        'discount_value': valueText,
                        'source_utm': utm.text.trim(),
                        'per_wallet_limit': perWallet,
                        'max_total_issues': maxIssues.text.trim().isEmpty
                            ? null
                            : int.tryParse(maxIssues.text.trim()),
                        'is_active': isActive,
                      };
                      final err = await sheetContext
                          .read<CafeState>()
                          .saveCouponCampaign(fields, id: campaign?.id);
                      if (!sheetContext.mounted) return;
                      if (err != null) {
                        set(() => busy = false);
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(
                                content: Text(err),
                                backgroundColor: AppTheme.danger));
                        return;
                      }
                      ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(
                          content: Text(L.campaignSaved),
                          backgroundColor: AppTheme.success));
                      Navigator.pop(sheetContext);
                    },
            ),
          ]),
        ),
      ),
    ),
  );
}
