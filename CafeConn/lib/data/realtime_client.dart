import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_config.dart';
import 'dtos.dart';

enum RealtimeEventType {
  connectionReady,
  orderCreated,
  orderUpdated,
  attentionCreated,
  attentionAcked,
  unknown,
}

/// A single decoded message from the staff realtime feed.
class RealtimeEvent {
  final RealtimeEventType type;
  final OrderDto? order;
  final AttentionDto? attention;
  final Map<String, dynamic> raw;
  const RealtimeEvent(this.type,
      {this.order, this.attention, this.raw = const {}});
}

/// Subscribes to the staff realtime feed (`ws://host/ws/staff/?token=...`).
///
/// Exposes a broadcast [events] stream and reconnects automatically with capped
/// exponential backoff. It never throws to the caller; connection problems
/// surface as [isConnected] flipping to false and a scheduled reconnect.
class StaffRealtimeClient {
  StaffRealtimeClient({Duration? maxBackoff})
      : _maxBackoff = maxBackoff ?? const Duration(seconds: 30);

  final Duration _maxBackoff;
  final StreamController<RealtimeEvent> _controller =
      StreamController<RealtimeEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retryTimer;
  String? _token;
  bool _disposed = false;
  bool _connected = false;
  int _attempt = 0;

  Stream<RealtimeEvent> get events => _controller.stream;
  bool get isConnected => _connected;

  /// Open the socket with the given DRF token. Auto-reconnects on drop.
  Future<void> connect(String token) async {
    _token = token;
    _disposed = false;
    await _open();
  }

  Future<void> _open() async {
    if (_disposed || _token == null) return;
    await _teardownSocket();
    try {
      final channel = WebSocketChannel.connect(ApiConfig.staffSocket(_token!));
      _channel = channel;
      await channel.ready;
      _connected = true;
      _attempt = 0;
      _sub = channel.stream.listen(
        _onData,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _connected = false;
      _scheduleReconnect();
    }
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return;
      map = decoded.cast<String, dynamic>();
    } catch (_) {
      return; // ignore malformed frames rather than crash the feed
    }
    _controller.add(_parse(map));
  }

  RealtimeEvent _parse(Map<String, dynamic> map) {
    final event = (map['event'] ?? '').toString();
    switch (event) {
      case 'connection.ready':
        return RealtimeEvent(RealtimeEventType.connectionReady, raw: map);
      case 'order.created':
      case 'order.updated':
        final order = map['order'];
        return RealtimeEvent(
          event == 'order.created'
              ? RealtimeEventType.orderCreated
              : RealtimeEventType.orderUpdated,
          order: order is Map
              ? OrderDto.fromDrf(order.cast<String, dynamic>())
              : null,
          raw: map,
        );
      case 'attention.created':
      case 'attention.acked':
        final signal = map['signal'];
        return RealtimeEvent(
          event == 'attention.created'
              ? RealtimeEventType.attentionCreated
              : RealtimeEventType.attentionAcked,
          attention: signal is Map
              ? AttentionDto.fromDrf(signal.cast<String, dynamic>())
              : null,
          raw: map,
        );
      default:
        return RealtimeEvent(RealtimeEventType.unknown, raw: map);
    }
  }

  void _scheduleReconnect() {
    _connected = false;
    if (_disposed || _token == null) return;
    _attempt += 1;
    // 2,4,8,16,32 ... capped at maxBackoff seconds.
    final backoff = 1 << _attempt.clamp(1, 5);
    final seconds = backoff.clamp(1, _maxBackoff.inSeconds);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: seconds), _open);
  }

  Future<void> _teardownSocket() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {
      // ignore close errors
    }
    _channel = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    await _teardownSocket();
    await _controller.close();
  }
}
