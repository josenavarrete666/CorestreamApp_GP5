import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:corestream_mobile/data/http_platform_interface.dart';

const userId = '7e45bf4d-9591-5e3d-88ae-45081542780b';
const notificationId = '22e92ba6-e78d-460d-a185-5dba2f7f3865';
Map<String, Object?> token([String access = 'test-access']) => {
  'access_token': access, 'token_type': 'bearer', 'expires_in': 1800, 'must_change_password': false,
};
Map<String, Object?> profile({String role = 'DEVELOPER', bool passwordRequired = false}) => {
  'id': userId, 'email': 'developer@example.com', 'full_name': 'Developer real',
  'role': role, 'is_active': true, 'created_at': '2026-10-12T01:00:00Z', 'must_change_password': passwordRequired,
};
Map<String, Object?> notification({String id = notificationId, bool read = false}) => {
  'id': id, 'user_id': userId, 'title': 'Notificación real', 'message': 'Mensaje persistido',
  'type': 'QUESTION_RAISED', 'is_read': read, 'created_at': '2026-10-12T01:00:00Z', 'ticket_id': null,
};
ResponseBody response(Object? data, [int status = 200, Map<String, List<String>>? headers]) =>
    ResponseBody.fromString(jsonEncode(data), status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType], ...?headers});

class FakePlatform implements HttpPlatform {
  FakePlatform({this.csrf = 'test-csrf'});
  String? csrf;
  @override
  void configure(Dio dio) {}
  @override
  Future<String?> csrfToken(Uri origin) async => csrf;
}

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions) handler;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }
  @override
  void close({bool force = false}) {}
}
