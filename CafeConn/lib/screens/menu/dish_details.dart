import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';

void showStaffDishDetails(BuildContext context, MenuItem item) {
  showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
            decoration: const BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.all(24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(item.displayName,
                            style: T.h1.copyWith(fontSize: 22))),
                    Text(item.price.rub,
                        style: T.h2.copyWith(color: AppTheme.cta))
                  ]),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: (item.isBar ? AppTheme.bar : AppTheme.warning)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(item.isBar ? Icons.local_bar : Icons.restaurant,
                            size: 13,
                            color:
                                item.isBar ? AppTheme.bar : AppTheme.warning),
                        const SizedBox(width: 5),
                        Text(item.isBar ? L.bar : L.kitchen,
                            style: T.smallSemi.copyWith(
                                color: item.isBar
                                    ? AppTheme.bar
                                    : AppTheme.warning,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: AppTheme.surfaceSunken,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(
                          '${L.minutes(item.prepTime)} · ${item.displayCategory}',
                          style: T.smallSemi),
                    ),
                    if (!item.available)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: AppTheme.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10)),
                        child: Text(L.stopList,
                            style: T.smallSemi.copyWith(
                                color: AppTheme.danger,
                                fontWeight: FontWeight.w800)),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  if (item.displayDescription.isNotEmpty)
                    Text(item.displayDescription,
                        style: T.h3.copyWith(color: AppTheme.ink2)),
                  const SizedBox(height: 20),
                  Text(L.composition, style: T.label),
                  const SizedBox(height: 4),
                  Text(item.composition, style: T.body),
                  const SizedBox(height: 20),
                  Text(L.allergens, style: T.label),
                  const SizedBox(height: 8),
                  Wrap(
                      spacing: 8,
                      children: item.allergens.isEmpty
                          ? [
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: AppTheme.success
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Text(L.noAllergens,
                                      style: T.smallSemi))
                            ]
                          : item.allergens
                              .map((a) => NoteChip(label: a))
                              .toList()),
                  const SizedBox(height: 32),
                  // Menu-capable staff (managers, or anyone a manager granted
                  // the menu capability) can flip an item's stop-list state
                  // straight from the dish sheet.
                  Consumer<CafeState>(builder: (context, state, _) {
                    if (!state.canManageMenu) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppButton(
                        label: item.available
                            ? L.markOutOfStock
                            : L.markAvailable,
                        kind: ButtonKind.ghost,
                        color: item.available
                            ? AppTheme.danger
                            : AppTheme.success,
                        onPressed: () => state.toggleAvailability(item),
                      ),
                    );
                  }),
                  AppButton(
                      label: L.done, onPressed: () => Navigator.pop(context)),
                ]),
          ));
}
