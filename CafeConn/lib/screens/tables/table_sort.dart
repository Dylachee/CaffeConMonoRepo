import '../../models/models.dart';

/// Operational table order: unresolved guest needs first, then the current
/// waiter's active tables, then the remaining floor in numeric order.
List<CafeTable> sortTablesForWaiter(
  Iterable<CafeTable> tables, {
  required Iterable<CafeOrder> orders,
  required String? activeEmployeeId,
}) {
  final oldestAwaitingOrder = <String, DateTime>{};
  for (final order in orders) {
    if (order.status != OrderStatus.awaiting) continue;
    final current = oldestAwaitingOrder[order.tableId];
    if (current == null || order.createdAt.isBefore(current)) {
      oldestAwaitingOrder[order.tableId] = order.createdAt;
    }
  }

  bool needsAttention(CafeTable table) =>
      table.attention != null ||
      table.status == TableStatus.waiting ||
      oldestAwaitingOrder.containsKey(table.id);

  DateTime? urgencyStartedAt(CafeTable table) {
    DateTime? oldest;
    void include(DateTime? candidate) {
      if (candidate != null &&
          (oldest == null || candidate.isBefore(oldest!))) {
        oldest = candidate;
      }
    }

    if (table.attention != null) include(table.attentionCreatedAt);
    if (table.status == TableStatus.waiting) include(table.openedAt);
    include(oldestAwaitingOrder[table.id]);
    return oldest;
  }

  int priority(CafeTable table) {
    if (needsAttention(table)) return 0;
    final isMine = table.status != TableStatus.free &&
        activeEmployeeId != null &&
        table.waiterId == activeEmployeeId;
    if (isMine) return 1;
    return 2;
  }

  final sorted = tables.toList();
  sorted.sort((a, b) {
    final pa = priority(a);
    final pb = priority(b);
    if (pa != pb) return pa - pb;

    if (pa == 0) {
      final aStarted = urgencyStartedAt(a);
      final bStarted = urgencyStartedAt(b);
      if (aStarted != null && bStarted != null) {
        final byAge = aStarted.compareTo(bStarted);
        if (byAge != 0) return byAge;
      } else if (aStarted != null) {
        return 1;
      } else if (bStarted != null) {
        return -1;
      }
    }

    return a.number.compareTo(b.number);
  });
  return sorted;
}
