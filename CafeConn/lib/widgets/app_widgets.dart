import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_typography.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../state/cafe_state.dart';

// ================= COMPONENT WIDGETS =================

class AppButton extends StatefulWidget {
  const AppButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.icon,
      this.kind = ButtonKind.primary,
      this.loading = false,
      this.color});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonKind kind;
  final bool loading;
  final Color? color;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool down = false;

  @override
  Widget build(BuildContext context) {
    final primary = widget.kind == ButtonKind.primary;
    final dark = widget.kind == ButtonKind.dark;
    final ghost = widget.kind == ButtonKind.ghost;

    final bg = widget.color ??
        (primary
            ? AppTheme.cta
            : dark
                ? AppTheme.ink
                : ghost
                    ? Colors.transparent
                    : AppTheme.surfaceAlt);
    final fg = primary || dark ? Colors.white : AppTheme.ink;

    return GestureDetector(
      onTapDown: (_) => setState(() => down = true),
      onTapCancel: () => setState(() => down = false),
      onTapUp: (_) => setState(() => down = false),
      onTap: widget.onPressed == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              widget.onPressed!();
            },
      child: AnimatedScale(
        duration: 200.ms,
        curve: Curves.elasticOut,
        scale: down ? .97 : 1,
        child: AnimatedContainer(
          duration: 200.ms,
          height: 50,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: ghost
                    ? Colors.transparent
                    : (primary || dark ? bg : AppTheme.separator)),
            boxShadow: primary && !down
                ? [
                    const BoxShadow(
                        color: Color(0x1F2B2418),
                        blurRadius: 22,
                        spreadRadius: -14,
                        offset: Offset(0, 10))
                  ]
                : null,
          ),
          child: widget.loading
              ? const CupertinoActivityIndicator(color: Colors.white)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, color: fg, size: 19),
                      const SizedBox(width: 8)
                    ],
                    Flexible(
                        child: Text(widget.label,
                            overflow: TextOverflow.ellipsis,
                            style:
                                T.bodySemi.copyWith(color: fg, fontSize: 16))),
                  ],
                ),
        ),
      ),
    );
  }
}

// ===== DESIGN-SYSTEM BUTTONS =====
// Espresso primary: dark bg, ALWAYS white label — contrast can never break.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.enabled = true,
    this.height = 52,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool enabled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final on = enabled && onTap != null;
    return GestureDetector(
      onTap: on
          ? () {
              HapticFeedback.lightImpact();
              onTap!();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: height,
        decoration: BoxDecoration(
          color: on ? const Color(0xFF221F1A) : const Color(0xFFDCD6CB),
          borderRadius: BorderRadius.circular(15),
          boxShadow: on
              ? [
                  BoxShadow(
                      color: const Color(0xFF221F1A).withValues(alpha: 0.30),
                      blurRadius: 22,
                      offset: const Offset(0, 8))
                ]
              : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[
            Icon(icon,
                size: 19, color: on ? Colors.white : const Color(0xFF8A8275)),
            const SizedBox(width: 9),
          ],
          Text(label,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : const Color(0xFF8A8275))),
        ]),
      ),
    );
  }
}

// Ghost button: cream bg, ink label — for "Cancel" and secondary actions.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.height = 48,
  });
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppTheme.separator),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppTheme.ink),
            const SizedBox(width: 8),
          ],
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.ink)),
        ]),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.onTap,
      this.index = 0,
      this.borderColor,
      this.elevation = true,
      this.height,
      this.width});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final int index;
  final Color? borderColor;
  final bool elevation;
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      height: height,
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? const Color(0xFFF0EBE1)),
        boxShadow: elevation
            ? [
                const BoxShadow(
                    color: Color(0x0A2B2418),
                    blurRadius: 2,
                    offset: Offset(0, 1)),
                const BoxShadow(
                    color: Color(0x1F2B2418),
                    blurRadius: 22,
                    spreadRadius: -14,
                    offset: Offset(0, 10)),
              ]
            : null,
      ),
      child: child,
    )
        .animate(delay: Duration(milliseconds: index * 40))
        .fadeIn(duration: 260.ms)
        .slideY(begin: .08, end: 0);

    if (onTap == null) return box;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap!();
      },
      child: box,
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.showLabel = false});
  final TableStatus status;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 6,
              spreadRadius: 2),
        ],
      ),
    );

    Widget animatedDot = dot;
    if (status == TableStatus.waiting) {
      // RepaintBoundary confines this endless pulse to its own layer instead
      // of forcing a full repaint of whatever card/list it sits in.
      animatedDot = RepaintBoundary(
        child: dot
            .animate(onPlay: (c) => c.repeat())
            .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.3, 1.3),
                duration: 800.ms)
            .then()
            .scale(end: const Offset(1, 1), duration: 800.ms),
      );
    }

    if (!showLabel) return animatedDot;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          animatedDot,
          const SizedBox(width: 8),
          Text(
            statusLabel(status).toUpperCase(),
            style: T.label.copyWith(
                color: color, fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}

class CategoryChip extends StatelessWidget {
  const CategoryChip(
      {super.key,
      required this.label,
      required this.active,
      required this.onTap,
      this.icon,
      this.dotColor});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: 200.ms,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.cta : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
              color: active ? AppTheme.cta : const Color(0xFFE7E2D8)),
          boxShadow: active
              ? [
                  const BoxShadow(
                      color: Color(0x1F2B2418),
                      blurRadius: 12,
                      offset: Offset(0, 4))
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
            ] else if (icon != null) ...[
              Icon(icon,
                  color: active ? Colors.white : AppTheme.ink2, size: 16),
              const SizedBox(width: 6)
            ],
            Text(
              label,
              style: T.body.copyWith(
                color: active ? Colors.white : AppTheme.ink2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NoteChip extends StatelessWidget {
  const NoteChip({super.key, required this.label, this.onDelete});
  final String label;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF3E6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.flag, color: Color(0xFFA86A24), size: 14),
          const SizedBox(width: 6),
          Text(label,
              style: T.priceSmall.copyWith(color: const Color(0xFFA86A24))),
          if (onDelete != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onDelete,
              child:
                  const Icon(Icons.close, color: Color(0xFFA86A24), size: 14),
            ),
          ],
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard(
      {super.key,
      required this.label,
      required this.value,
      required this.delta,
      required this.isPositive,
      required this.color,
      this.detail,
      this.index = 0});
  final String label;
  final String value;
  final String delta;
  final bool isPositive;
  final Color color;
  final Widget? detail;
  final int index;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      index: index,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(label,
                  style: T.priceSmall.copyWith(
                      color: AppTheme.ink2, fontWeight: FontWeight.w500)),
            ],
          ),
          if (detail == null)
            const Spacer()
          else ...[
            const SizedBox(height: 14),
            Expanded(child: detail!),
            const SizedBox(height: 10),
          ],
          Text(value, style: T.h2.copyWith(fontSize: 22)),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14,
                  color: isPositive ? AppTheme.success : AppTheme.danger),
              const SizedBox(width: 4),
              Text(delta,
                  style: T.smallSemi.copyWith(
                      color: isPositive ? AppTheme.success : AppTheme.danger,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

// Photo widgets (MenuImage/ShimmerBox/MenuGridItem) and the old
// QuantityStepper were removed together with the photo-based ordering UI:
// the staff app is text-first now (see _OrderComposerTile/_CompactStepper).

// ================= NAVIGATION & SCAFFOLD =================

class AppScaffold extends StatelessWidget {
  const AppScaffold(
      {super.key,
      required this.child,
      this.bottomNav,
      this.floatingActionButton});
  final Widget child;
  final Widget? bottomNav;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    return Scaffold(
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNav,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: child,
            ),
            if (!state.online && !state.noConnectionDismissed)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.wifi_off, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(L.offlineBanner,
                            style: T.bodySemi.copyWith(color: Colors.white))),
                    IconButton(
                        onPressed: () {
                          state.noConnectionDismissed = true;
                          state.refresh();
                        },
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 20)),
                  ]),
                ).animate().slideY(
                    begin: -1.2,
                    end: 0,
                    duration: 400.ms,
                    curve: Curves.easeOutQuart),
              ),
          ],
        ),
      ),
    );
  }
}

class AttentionBanner extends StatelessWidget {
  const AttentionBanner(
      {super.key, required this.attention, required this.onAck});
  final String attention;
  final VoidCallback onAck;

  @override
  Widget build(BuildContext context) {
    final color = attentionColor(attention);
    final (label, icon) = switch (attention) {
      'call' => (L.guestCalling, Icons.pan_tool_rounded),
      'bill' => (L.guestBill, Icons.receipt_long_rounded),
      'arrived' => (L.guestSeated, Icons.chair_rounded),
      _ => (L.guestSignal, Icons.notifications_active_rounded),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppTypography.bodySemi())),
          GestureDetector(
            onTap: onAck,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Text(L.acknowledge,
                  style: AppTypography.bodySemi().copyWith(fontSize: 13)),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.1, end: 0);
  }
}

// ================= HELPERS & UTILS =================

class Header extends StatelessWidget {
  const Header(
      {super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 16),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.separator),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/images/cafeconnect-logo.png',
            fit: BoxFit.cover,
          ),
        ),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: T.screenTitle),
          if (subtitle != null) Text(subtitle!, style: T.subtitle),
        ])),
        ...actions,
      ]));
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(children: [
        Expanded(child: Text(title, style: T.sectionTitle)),
        if (action != null)
          AppButton(label: L.all, kind: ButtonKind.ghost, onPressed: action),
      ]));
}

class Avatar extends StatelessWidget {
  const Avatar(
      {super.key, required this.label, this.online = false, this.color});
  final String label;
  final bool online;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final initials = label
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part.substring(0, 1).toUpperCase())
        .take(2)
        .join();
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
          color: (color ?? AppTheme.cta).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14)),
      child: Center(
          child: Text(initials,
              style: T.bodySemi.copyWith(
                  color: color ?? AppTheme.cta, fontWeight: FontWeight.w800))),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField(
      {super.key,
      required this.controller,
      required this.label,
      this.hint,
      this.obscure = false,
      this.keyboardType,
      this.onChanged});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: T.body.copyWith(color: AppTheme.ink),
        cursorColor: AppTheme.cta,
        decoration: InputDecoration(
          hintText: hint ?? label,
          hintStyle: T.body.copyWith(color: AppTheme.ink2),
          filled: true,
          fillColor: AppTheme.surfaceSunken,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.cta, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}

void showForwardSheet(BuildContext context, CafeTable table) {
  final comment = TextEditingController();
  showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
            decoration: const BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L.forward, style: T.h2.copyWith(fontSize: 20)),
                  const SizedBox(height: 16),
                  AppTextField(controller: comment, label: L.addComment),
                  const SizedBox(height: 24),
                  Text(L.sendTo, style: T.label),
                  const SizedBox(height: 12),
                  ...context.read<CafeState>().groups.map((g) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Avatar(
                            label: switch (g.type) {
                          FeedType.kitchen => L.kitchen,
                          FeedType.bar => L.bar,
                          _ => L.generalChat,
                        }),
                        title: Text(
                            switch (g.type) {
                              FeedType.kitchen => L.kitchen,
                              FeedType.bar => L.bar,
                              _ => L.generalChat,
                            },
                            style: T.bodySemi),
                        trailing:
                            const Icon(Icons.send_rounded, color: AppTheme.cta),
                        onTap: () {
                          context
                              .read<CafeState>()
                              .forwardTable(table, g, comment.text);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(L.sentToChat)));
                        },
                      )),
                ]),
          ));
}

class LiveTimer extends StatefulWidget {
  const LiveTimer({super.key, required this.createdAt, required this.color});
  final DateTime createdAt;
  final Color color;
  @override
  State<LiveTimer> createState() => _LiveTimerState();
}

class _LiveTimerState extends State<LiveTimer> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(1.seconds, (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.createdAt);
    return Text(
        '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}',
        style: T.timer.copyWith(color: widget.color, fontSize: 16));
  }
}

class BlurBar extends StatelessWidget {
  const BlurBar({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withValues(alpha: .82),
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(20)),
                child: child)),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  const EmptyState(
      {super.key, required this.icon, required this.title, required this.sub});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppTheme.success.withValues(alpha: .3)),
            const SizedBox(height: 12),
            Text(title, style: T.h2),
            Text(sub, style: T.body.copyWith(color: AppTheme.ink2)),
          ],
        ),
      );
}
