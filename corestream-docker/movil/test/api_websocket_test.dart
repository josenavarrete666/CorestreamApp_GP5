import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:corestream_mobile/data/api_client.dart';
import 'package:corestream_mobile/services/api_websocket_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'api_test_support.dart';

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 600; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('WebSocket condition was not reached');
}

void main() {
  test('WS real: ticket, pong, aviso identificado, deduplicación e invalidación', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    WebSocket? socket;
    Uri? handshake;
    final received = <Map<String, dynamic>>[];
    server.listen((request) async {
      handshake = request.uri;
      socket = await WebSocketTransformer.upgrade(request);
      socket!.listen((raw) => received.add(jsonDecode(raw as String) as Map<String, dynamic>));
      for (final message in [
        {'type': 'connected'}, {'type': 'ping'},
        {'type': 'notification', 'data': notification()},
        {'type': 'notification', 'data': notification()},
        {'type': 'notification', 'data': {'type': 'TICKET_ASSIGNED', 'data': {'ticket_id': userId}}},
        {'type': 'update', 'data': {'ticket_id': userId}},
      ]) { socket!.add(jsonEncode(message)); }
    });
    final adapter = FakeAdapter((r) => r.path.endsWith('/login') ? response(token()) : response({'ticket': 'opaque-ticket'}));
    final client = ApiClient('http://127.0.0.1:${server.port}', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    await client.login('developer@example.com', 'password');
    var changes = 0;
    final notifications = <Map<String, dynamic>>[];
    final service = ApiWebSocketService(client, userId, onChange: () => changes++, onNotification: notifications.add);
    addTearDown(() async { service.dispose(); client.dispose(); await socket?.close(); await server.close(force: true); });
    service.start();
    await until(() => changes >= 5 && received.isNotEmpty);
    expect(handshake!.path, '/api/ws/$userId');
    expect(handshake!.queryParameters, {'ticket': 'opaque-ticket'});
    expect(notifications.single['id'], notificationId);
    expect(received.single['type'], 'pong');
    service.activity(); service.activity();
    await until(() => received.length == 2);
    expect(received.last['type'], 'activity');
    expect(received.where((m) => m['type'] == 'activity').length, 1);
  });
  test('reconexión obtiene ticket nuevo; cierre 4000 espera interacción', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    final tickets = <String>[];
    server.listen((request) async {
      tickets.add(request.uri.queryParameters['ticket']!);
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.add(jsonEncode({'type': 'connected'}));
      if (sockets.length < 3) await socket.close(sockets.length == 1 ? 1011 : 4000);
    });
    var issued = 0;
    final adapter = FakeAdapter((r) => r.path.endsWith('/login') ? response(token()) : response({'ticket': 'ticket-${++issued}'}));
    final client = ApiClient('http://127.0.0.1:${server.port}', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    await client.login('developer@example.com', 'password');
    var syncs = 0;
    final service = ApiWebSocketService(client, userId, onChange: () => syncs++, onNotification: (_) {});
    addTearDown(() async { service.dispose(); client.dispose(); for (final socket in sockets) { await socket.close(); } await server.close(force: true); });
    service.start();
    await until(() => service.status == WsStatus.idle);
    expect(tickets, ['ticket-1', 'ticket-2']);
    expect(syncs, 2);
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(issued, 2);
    service.activity();
    await until(() => service.status == WsStatus.connected);
    expect(tickets.last, 'ticket-3');
  });
  test('cierre durante petición de ticket impide abrir un socket tardío', () async {
    final gate = Completer<void>();
    final adapter = FakeAdapter((r) async {
      if (r.path.endsWith('/login')) return response(token());
      await gate.future;
      return response({'ticket': 'late-ticket'});
    });
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    await client.login('developer@example.com', 'password');
    var connections = 0;
    final service = ApiWebSocketService(client, userId, onChange: () {}, onNotification: (_) {},
      connect: (_) { connections++; throw StateError('No connection expected'); });
    addTearDown(() { service.dispose(); client.dispose(); });
    service.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    service.stop();
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(connections, 0);
    expect(service.status, WsStatus.stopped);
  });
}
