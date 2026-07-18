import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../data/dtos.dart';
import '../../models/models.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';

/// Redeem: scan the guest's wallet QR (a signed token) or type the short
/// code, review the confirmation sheet, optionally attach to an open order.
/// Every backend rejection (used / expired / void / tampered) surfaces
/// verbatim — the hub's message IS the UI message.
class RedeemCouponScreen extends StatefulWidget {
  const RedeemCouponScreen({super.key});
  @override
  State<RedeemCouponScreen> createState() => _RedeemCouponScreenState();
}

class _RedeemCouponScreenState extends State<RedeemCouponScreen> {
  final _codeController = TextEditingController();
  MobileScannerController? _scanner;
  bool _scannerFailed = false;
  bool _lookingUp = false;

  @override
  void initState() {
    super.initState();
    _scanner = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _scanner?.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppTheme.danger));
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_lookingUp) return;
    final raw =
        capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    await _lookUp(token: raw);
  }

  Future<void> _lookUp({String? token, String? code}) async {
    if (_lookingUp) return;
    setState(() => _lookingUp = true);
    final state = context.read<CafeState>();
    final (preview, error) =
        await state.couponPreview(token: token, code: code);
    if (!mounted) return;
    setState(() => _lookingUp = false);
    if (error != null || preview == null) {
      _showError(error ?? L.couldNotLoad);
      return;
    }
    await _showConfirmSheet(preview, token: token, code: code);
  }

  Future<void> _showConfirmSheet(CouponPreviewDto preview,
      {String? token, String? code}) async {
    final state = context.read<CafeState>();
    // Open (not yet paid/cancelled) orders the coupon could attach to.
    final openOrders =
        state.orders.where((o) => o.status != OrderStatus.awaiting).toList();
    String? selectedOrderId =
        openOrders.isNotEmpty ? openOrders.first.id : null;
    var busy = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, set) {
          final coupon = preview.coupon;
          final active = preview.displayStatus == 'active';
          return Container(
            decoration: const BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Text(L.redeemConfirmTitle, style: T.h2)),
                  const SizedBox(height: 16),
                  AppCard(
                    child: Row(children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppTheme.gold.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Center(
                            child: Text(coupon.discountLabel,
                                style: T.priceSmall.copyWith(
                                    color: AppTheme.gold,
                                    fontWeight: FontWeight.w800))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(coupon.displayTitle,
                                  style: T.h3, maxLines: 2),
                              const SizedBox(height: 3),
                              Text(
                                  '${coupon.code} · ${_statusLabel(preview.displayStatus)}',
                                  style: T.small),
                            ]),
                      ),
                    ]),
                  ),
                  if (active && openOrders.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(L.attachToOrder, style: T.smallSemi),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedOrderId,
                      items: [
                        ...openOrders.map((order) {
                          final table = state.tables
                              .where((t) => t.id == order.tableId)
                              .firstOrNull;
                          final label =
                              '${L.tableN(table?.number ?? '?')} · ${order.total.toStringAsFixed(2)} €';
                          return DropdownMenuItem<String>(
                              value: order.id, child: Text(label));
                        }),
                      ],
                      onChanged: (value) => set(() => selectedOrderId = value),
                    ),
                  ] else if (active) ...[
                    const SizedBox(height: 14),
                    Text(
                        'Open an order first — coupons must be attached to a bill.',
                        style: T.small.copyWith(color: AppTheme.danger)),
                  ],
                  const SizedBox(height: 18),
                  PrimaryButton(
                    label: L.redeemAction,
                    icon: Icons.check_circle_outline,
                    enabled: active && !busy && selectedOrderId != null,
                    onTap: !active || busy || selectedOrderId == null
                        ? null
                        : () async {
                            set(() => busy = true);
                            final (redeemed, error) = await state.redeemCoupon(
                                token: token,
                                code: code,
                                orderId: selectedOrderId);
                            if (!sheetContext.mounted) return;
                            if (error != null || redeemed == null) {
                              set(() => busy = false);
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  SnackBar(
                                      content: Text(error ?? L.couldNotSend),
                                      backgroundColor: AppTheme.danger));
                              return;
                            }
                            Navigator.pop(sheetContext);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content:
                                    Text('${L.redeemed} · ${redeemed.code}'),
                                backgroundColor: AppTheme.success));
                          },
                  ),
                  const SizedBox(height: 8),
                  GhostButton(
                      label: L.cancel,
                      onTap: () => Navigator.pop(sheetContext)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
        'active' => L.couponStActive,
        'redeemed' => L.couponStRedeemed,
        'expired' => L.couponStExpired,
        'void' => L.couponStVoid,
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SectionTitle(L.scanCouponQr),
        AppCard(
          padding: const EdgeInsets.all(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 260,
              child: _scannerFailed || _scanner == null
                  ? Container(
                      color: AppTheme.surfaceSunken,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(24),
                      child: Text(L.scannerUnavailable,
                          textAlign: TextAlign.center, style: T.bodySemi),
                    )
                  : MobileScanner(
                      controller: _scanner!,
                      onDetect: _onDetect,
                      errorBuilder: (context, error, child) {
                        // Render the fallback panel and remember the failure
                        // so the manual code path is clearly the way forward.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && !_scannerFailed) {
                            setState(() => _scannerFailed = true);
                          }
                        });
                        return Container(
                          color: AppTheme.surfaceSunken,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(24),
                          child: Text(
                              '${L.scannerUnavailable}\n${error.errorDetails?.message ?? error.errorCode.name}',
                              textAlign: TextAlign.center,
                              style: T.small),
                        );
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SectionTitle(L.couponCode),
        AppCard(
          child: Column(children: [
            AppTextField(
              controller: _codeController,
              label: L.couponCode,
              hint: 'V88RPCRM',
              keyboardType: TextInputType.visiblePassword,
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: L.findCoupon,
              icon: Icons.search,
              enabled: !_lookingUp,
              onTap: _lookingUp
                  ? null
                  : () {
                      final code = _codeController.text.trim();
                      if (code.isNotEmpty) _lookUp(code: code);
                    },
            ),
          ]),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
