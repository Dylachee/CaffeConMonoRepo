import 'package:cafeconnect/models/models.dart';
import 'package:cafeconnect/screens/tables/table_sort.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CafeTable table(int number, TableStatus status) =>
      CafeTable('$number', number, Colors.brown, status, 0);

  List<int> numbers(List<CafeTable> tables) =>
      tables.map((table) => table.number).toList();

  List<CafeTable> sorted(List<CafeTable> tables) => sortTablesForWaiter(
        tables,
        orders: const <CafeOrder>[],
        activeEmployeeId: '7',
      );

  test('defaults to numeric table order', () {
    expect(
      numbers(sorted([
        table(6, TableStatus.free),
        table(1, TableStatus.free),
        table(2, TableStatus.free),
      ])),
      [1, 2, 6],
    );
  });

  test('does not promote a free table with a stale waiter assignment', () {
    final stale = table(6, TableStatus.free)..waiterId = '7';
    expect(
      numbers(sorted([stale, table(1, TableStatus.free)])),
      [1, 6],
    );
  });

  test('promotes active tables assigned to the current waiter', () {
    final mine = table(6, TableStatus.occupied)..waiterId = '7';
    expect(
      numbers(sorted(
          [table(1, TableStatus.free), mine, table(2, TableStatus.free)])),
      [6, 1, 2],
    );
  });

  test('puts unresolved calls first, oldest call before newer calls', () {
    final newer = table(4, TableStatus.waiting)
      ..attention = 'call'
      ..attentionCreatedAt = DateTime.utc(2026, 6, 28, 10, 5);
    final older = table(2, TableStatus.waiting)
      ..attention = 'bill'
      ..attentionCreatedAt = DateTime.utc(2026, 6, 28, 10);
    final mine = table(1, TableStatus.occupied)..waiterId = '7';

    expect(numbers(sorted([mine, newer, older])), [2, 4, 1]);
  });
}
