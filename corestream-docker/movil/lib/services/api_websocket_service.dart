import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/api_client.dart';
import '../models/api_models.dart';

enum WsStatus { connecting, connected, reconnecting, idle, failed, stopped }

class ApiWebSocketService {
  ApiWebSocketService(this.client, this.userId, {required this.onChange, required this.onNotification,
      WebSocketChannel Function(Uri)? connect}) : connect = connect ?? WebSocketChannel.connect;
  final ApiClient client;
  final String userId;
  final void Function() onChange;
  final void Function(Map<String, dynamic>) onNotification;
  final WebSocketChannel Function(Uri) connect;
  final _status = StreamController<WsStatus>.broadcast();
  Stream<WsStatus> get statuses => _status.stream;
  WsStatus status = WsStatus.stopped;
  WebSocketChannel? _channel;
  Timer? _retry;
  Completer<void>? _waiting;
  int _epoch = 0;
  bool _running = false;
  DateTime? _lastActivity;
  final Set<String> _seen = {};

  void _set(WsStatus value) { status = value; if (!_status.isClosed) _status.add(value); }
  void start() {
    if (_running) return;
    _running = true;
    unawaited(_loop(++_epoch));
  }
  Future<void> _loop(int epoch) async {
    var attempt = 0;
    while (_running && epoch == _epoch) {
      _set(attempt == 0 ? WsStatus.connecting : WsStatus.reconnecting);
      WebSocketChannel? channel;
      try {
        final ticket = text(jsonObject(await client.request('/api/auth/ws-ticket', method: 'POST')), 'ticket');
        if (!_running || epoch != _epoch) return;
        final uri = client.origin.replace(scheme: client.origin.scheme == 'https' ? 'wss' : 'ws',
            path: '/api/ws/$userId', queryParameters: {'ticket': ticket});
        channel = _channel = connect(uri);
        await channel.ready.timeout(const Duration(seconds: 20));
        if (!_running || epoch != _epoch) { await channel.sink.close(); return; }
        await for (final raw in channel.stream) {
          if (!_running || epoch != _epoch) break;
          final message = jsonObject(jsonDecode(raw as String));
          switch (message['type']) {
            case 'connected':
              attempt = 0;
              _set(WsStatus.connected);
              onChange();
            case 'ping':
              channel.sink.add(jsonEncode({'type': 'pong'}));
            case 'notification':
              final payload = message['data'];
              if (payload is Map<String, dynamic> && payload['id'] is String && _seen.add(payload['id'] as String)) {
                if (_seen.length > 500) _seen.remove(_seen.first);
                onNotification(payload);
              }
              onChange();
            case 'update':
              onChange();
          }
        }
        if (channel.closeCode == 4000 && _running && epoch == _epoch) {
          _running = false;
          _set(WsStatus.idle);
          return;
        }
      } catch (_) {
        // HTTP resources remain authoritative after transport/protocol failure.
      } finally {
        await channel?.sink.close();
        if (identical(_channel, channel)) _channel = null;
      }
      if (!_running || epoch != _epoch) return;
      if (attempt >= 5) { _running = false; _set(WsStatus.failed); return; }
      final seconds = [2, 4, 8, 16, 30][attempt.clamp(0, 4)];
      attempt++;
      _waiting = Completer<void>();
      _retry = Timer(Duration(seconds: seconds), () => _waiting?.complete());
      await _waiting!.future;
      _retry = null;
      _waiting = null;
    }
  }

  void activity() {
    if (status == WsStatus.idle || status == WsStatus.failed) { start(); return; }
    if (status != WsStatus.connected) return;
    final now = DateTime.now();
    if (_lastActivity == null || now.difference(_lastActivity!) >= const Duration(minutes: 1)) {
      _lastActivity = now;
      _channel?.sink.add(jsonEncode({'type': 'activity'}));
    }
  }
  void stop() {
    _running = false;
    _epoch++;
    _retry?.cancel();
    if (_waiting != null && !_waiting!.isCompleted) _waiting!.complete();
    unawaited(_channel?.sink.close());
    _set(WsStatus.stopped);
  }
  void dispose() { stop(); _status.close(); }
}
