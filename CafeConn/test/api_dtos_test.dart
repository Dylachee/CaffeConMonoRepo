import 'package:cafeconnect/data/dtos.dart';
import 'package:flutter_test/flutter_test.dart';

/// Critical-flow coverage for the backend<->app contract: parsing both server
/// shapes (bootstrap camelCase and DRF snake_case) and the status mappings that
/// keep realtime events consistent with the bootstrap payload.
void main() {
  group('Bootstrap shape (GET /api/staff/bootstrap/)', () {
    final bootstrap = {
      'currentUser': {'id': '7', 'username': 'elena', 'name': 'Елена Соколова'},
      'tables': [
        {
          'id': '3',
          'number': 3,
          'name': 'Стол 03',
          'seats': 4,
          'guestCount': 2,
          'status': 'awaitingPayment',
          'colorTag': '',
          'waiter': 'Елена',
          'openedAt': '2026-06-28T10:00:00Z',
          'currentOrderId': '1201',
          'attention': null,
          'attentionReason': '',
          'ack': false,
        }
      ],
      'menu': [
        {
          'id': '1',
          'name': 'Флэт уайт',
          'description': 'Эспрессо с молоком',
          'price': 4.5,
          'category': 'Кофе',
          'imageUrl': 'http://x/y.png',
          'tags': ['Dairy'],
          'prepTime': 4,
          'available': true,
          'promo': true,
          'composition': 'Эспрессо, молоко',
          'allergens': ['Dairy'],
          'station': 'bar',
        }
      ],
      'orders': [
        {
          'id': '1201',
          'tableId': '3',
          'status': 'cooking',
          'station': 'kitchen',
          'items': [
            {
              'id': '9',
              'dishId': '1',
              'name': 'Флэт уайт',
              'qty': 2,
              'price': 4.5,
              'notes': ['без сахара'],
              'station': 'bar',
              'ready': false,
              'done': false,
            }
          ],
        }
      ],
      'preferences': {'theme': 'light'},
    };

    test('parses currentUser, tables, menu and orders', () {
      final dto = BootstrapDto.fromJson(bootstrap);
      expect(dto.currentUser?.name, 'Елена Соколова');
      expect(dto.tables.single.status, 'awaitingPayment');
      expect(dto.tables.single.seats, 4);
      expect(dto.menu.single.station, 'bar');
      expect(dto.menu.single.price, 4.5);
      expect(dto.orders.single.status, 'cooking');
      expect(dto.orders.single.items.single.qty, 2);
      expect(dto.orders.single.items.single.notes, ['без сахара']);
    });
  });

  group('DRF shape (WebSocket order.* events)', () {
    final drfOrder = {
      'event': 'order.created',
      'order': {
        'id': 1201,
        'table': {
          'id': 3,
          'number': 3,
          'label': 'Стол 03',
          'capacity': 4,
          'guest_count': 2,
          'status': 'new_order',
          'color_tag': '',
          'attention': 'call',
          'attention_reason': 'позвали',
          'attention_acknowledged': false,
        },
        'status': 'cooking',
        'station_scope': 'mixed',
        'items': [
          {
            'id': 9,
            'menu_item': {'id': 1, 'name': 'Флэт уайт'},
            'quantity': 2,
            'unit_price': '4.50',
            'station': 'bar',
            'notes': ['без сахара'],
            'ready': false,
            'done': false,
          }
        ],
      },
    };

    test('OrderDto.fromDrf reads nested table id, items and maps status', () {
      final order =
          OrderDto.fromDrf((drfOrder['order'] as Map).cast<String, dynamic>());
      expect(order.id, '1201');
      expect(order.tableId, '3');
      expect(order.status, 'cooking');
      expect(order.station, 'mixed');
      expect(order.items.single.dishId, '1');
      expect(order.items.single.qty, 2);
      expect(order.items.single.price, 4.5); // parsed from string "4.50"
    });

    test('TableDto.fromDrf maps django status to flutter status', () {
      final table = TableDto.fromDrf(
          ((drfOrder['order'] as Map)['table'] as Map).cast<String, dynamic>());
      expect(table.status, 'newOrder'); // new_order -> newOrder
      expect(table.attention, 'call');
      expect(table.seats, 4);
    });

    test('AttentionDto.fromDrf reads table id and signal type', () {
      final signal = {
        'id': 5,
        'table': {'id': 3, 'number': 3},
        'signal_type': 'bill_request',
        'reason': 'счёт',
        'ack': false,
      };
      final dto = AttentionDto.fromDrf(signal);
      expect(dto.tableId, '3');
      expect(dto.signalType, 'bill_request');
    });
  });

  group('Status mappings mirror the backend', () {
    test('order status: django -> flutter', () {
      expect(flutterOrderStatusFromDjango('new'), 'accepted');
      expect(flutterOrderStatusFromDjango('pending'), 'accepted');
      expect(flutterOrderStatusFromDjango('preparing'), 'cooking');
      expect(flutterOrderStatusFromDjango('ready'), 'ready');
      expect(flutterOrderStatusFromDjango('paid'), 'completed');
      expect(flutterOrderStatusFromDjango('???'), 'accepted');
    });

    test('table status: django -> flutter', () {
      expect(flutterTableStatusFromDjango('awaiting_payment'), 'awaitingPayment');
      expect(flutterTableStatusFromDjango('new_order'), 'newOrder');
      expect(flutterTableStatusFromDjango('needs_service'), 'newOrder');
      expect(flutterTableStatusFromDjango('free'), 'free');
    });
  });
}
