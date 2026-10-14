import 'package:cookie_jar/cookie_jar.dart';
import 'package:corestream_mobile/core/config.dart';
import 'package:corestream_mobile/data/api_client.dart';
import 'package:corestream_mobile/data/api_error.dart';
import 'package:corestream_mobile/data/api_repository.dart';
import 'package:corestream_mobile/data/http_platform_native.dart';
import 'package:corestream_mobile/models/api_models.dart';
import 'package:corestream_mobile/models/models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'api_test_support.dart';

void main() {
  test('origen normalizado y rutas sin prefijo duplicado', () async {
    expect(AppConfig.validateOrigin('http://localhost:8001/'), 'http://localhost:8001');
    for (final value in ['http://localhost:8001/api', 'http://localhost:8001?q=1', 'ftp://localhost', 'http://user:pass@localhost', 'invalid']) {
      expect(() => AppConfig.validateOrigin(value), throwsFormatException);
    }
    final adapter = FakeAdapter((r) => response(token()));
    final client = ApiClient('http://localhost:8001/', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    addTearDown(client.dispose);
    await client.login(' DEVELOPER@EXAMPLE.COM ', 'password');
    expect(adapter.requests.single.uri.toString(), 'http://localhost:8001/api/auth/login');
    expect(adapter.requests.single.data['email'], 'developer@example.com');
  });
  test('perfil conserva líder y contraseña obligatoria; rol desconocido falla', () {
    final parsed = ApiProfile.fromJson(profile(role: 'TEAM_LEADER', passwordRequired: true));
    expect(parsed.user.role, UserRole.groupLeader);
    expect(parsed.mustChangePassword, true);
    expect(() => ApiProfile.fromJson(profile(role: 'SUPERUSER')), throwsA(isA<ApiError>()));
    expect(() => ApiProfile.fromJson({...profile(), 'id': null}), throwsA(isA<ApiError>()));
    expect(() => ApiProfile.fromJson({...profile(), 'created_at': '2026-10-12'}), throwsA(isA<ApiError>()));
  });
  test('aplicación usa conteos API y rechaza métricas faltantes', () {
    final raw = {'id': userId, 'name': 'Aplicación', 'is_active': true, 'created_at': '2026-10-12T01:00:00+00:00', 'epic_count': 1, 'pending_count': 2, 'delayed_count': 0};
    expect(ApiApplication.fromJson(raw).pendingCount, 2);
    expect(() => ApiApplication.fromJson({...raw, 'pending_count': null}), throwsA(isA<ApiError>()));
  });
  test('notificaciones conservan UUID, tipo original y fecha; tipo futuro visible', () {
    expect(ApiNotification.fromJson(notification()).display.kind, NotificationKind.question);
    final future = ApiNotification.fromJson({...notification(), 'type': 'FUTURE_EVENT'});
    expect(future.rawType, 'FUTURE_EVENT');
    expect(future.display.kind, NotificationKind.system);
    expect(() => ApiNotification.fromJson({...notification(), 'created_at': 'invalid'}), throwsA(isA<ApiError>()));
  });
  test('contador ausente no se convierte a cero', () async {
    final adapter = FakeAdapter((r) => r.path.endsWith('/login') ? response(token()) : response({'count': 3, 'user_id': userId}));
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    final repo = ApiRepository(client);
    addTearDown(() { repo.dispose(); client.dispose(); });
    await client.login('developer@example.com', 'password');
    await expectLater(repo.unreadCount(), throwsA(isA<ApiError>()));
  });
  test('mark-read 200 con cantidad cero no se informa como éxito', () async {
    final adapter = FakeAdapter((r) => r.path.endsWith('/login') ? response(token()) : response({'marked_as_read': 0, 'total_requested': 1}));
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    final repo = ApiRepository(client);
    addTearDown(() { repo.dispose(); client.dispose(); });
    await client.login('developer@example.com', 'password');
    await expectLater(repo.markNotificationRead(notificationId), throwsA(isA<ApiError>()));
  });
  test('paginación completa, página final y deduplicación por UUID', () async {
    final adapter = FakeAdapter((r) {
      if (r.path.endsWith('/login')) return response(token());
      final skip = r.queryParameters['skip'] as int;
      return response(skip == 0 ? List.generate(50, (i) => notification(id: '00000000-0000-0000-0000-${i.toString().padLeft(12, '0')}'))
          : [notification(id: '00000000-0000-0000-0000-000000000049'), notification()]);
    });
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    final repo = ApiRepository(client);
    addTearDown(() { repo.dispose(); client.dispose(); });
    await client.login('developer@example.com', 'password');
    expect((await repo.notifications()).length, 51);
    expect(adapter.requests.last.queryParameters['skip'], 50);
  });
  test('jar nativo respeta path, rota CSRF y elimina cookies', () async {
    final jar = CookieJar();
    final platform = NativeHttpPlatform(jar: jar);
    final origin = Uri.parse('http://localhost:8001');
    await jar.saveFromResponse(origin.resolve('/api/auth/login'), [
      Cookie.fromSetCookieValue('refresh_token=first; Path=/api/auth; HttpOnly'),
      Cookie.fromSetCookieValue('csrf_token=first-csrf; Path=/'),
    ]);
    expect((await jar.loadForRequest(origin.resolve('/api/applications/'))).any((c) => c.name == 'refresh_token'), false);
    expect(await platform.csrfToken(origin), 'first-csrf');
    expect(await platform.csrfToken(Uri.parse('http://127.0.0.1:8001')), null);
    await jar.saveFromResponse(origin.resolve('/api/auth/refresh'), [Cookie.fromSetCookieValue('csrf_token=rotated; Path=/')]);
    expect(await platform.csrfToken(origin), 'rotated');
    await jar.saveFromResponse(origin.resolve('/api/auth/logout'), [
      Cookie.fromSetCookieValue('csrf_token=; Path=/; Max-Age=0'),
      Cookie.fromSetCookieValue('refresh_token=; Path=/api/auth; Max-Age=0'),
    ]);
    expect(await platform.csrfToken(origin), null);
    expect(await jar.loadForRequest(origin.resolve('/api/auth/refresh')), isEmpty);
  });
}
