import 'dart:async';

import 'package:corestream_mobile/data/api_client.dart';
import 'package:corestream_mobile/data/api_error.dart';
import 'package:corestream_mobile/data/demo_repository.dart';
import 'package:corestream_mobile/models/session_state.dart';
import 'package:corestream_mobile/services/api_auth_service.dart';
import 'package:corestream_mobile/services/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_test_support.dart';

void main() {
  test('flag de login se conserva aunque el perfil aún no lo refleje', () async {
    final adapter = FakeAdapter((r) => r.path.endsWith('/login') ? response({...token(), 'must_change_password': true}) : response(profile()));
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    addTearDown(client.dispose);
    expect((await ApiAuthService(client).login('developer@example.com', 'password')).mustChangePassword, true);
    await expectLater(client.request('/api/applications/'), throwsA(isA<ApiError>()));
    expect(adapter.requests.length, 2);
  });
  test('flag activado en refresh bloquea replay de recursos y notifica al coordinador', () async {
    final adapter = FakeAdapter((r) {
      if (r.path.endsWith('/login')) return response(token());
      if (r.path.endsWith('/refresh')) return response({...token('new'), 'must_change_password': true});
      return response({'detail': 'Expired'}, 401);
    });
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    addTearDown(client.dispose);
    var passwordRequired = false;
    client.onPasswordRequired = () => passwordRequired = true;
    await client.login('developer@example.com', 'password');
    await expectLater(client.request('/api/applications/'), throwsA(isA<ApiError>()));
    expect(passwordRequired, true);
    expect(adapter.requests.where((r) => r.path == '/api/applications/').length, 1);
  });
  test('401 concurrentes comparten refresh y reintentan una vez', () async {
    final gate = Completer<void>();
    var refreshes = 0;
    final adapter = FakeAdapter((r) async {
      if (r.path.endsWith('/login')) return response(token('old'));
      if (r.path.endsWith('/refresh')) { refreshes++; await gate.future; return response(token('new')); }
      return r.headers['Authorization'] == 'Bearer new' ? response({'ok': true}) : response({'detail': 'Expired'}, 401);
    });
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    addTearDown(client.dispose);
    await client.login('developer@example.com', 'password');
    final first = client.request('/api/applications/');
    final second = client.request('/api/notifications/');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(refreshes, 1);
    gate.complete();
    await Future.wait([first, second]);
    expect(refreshes, 1);
    expect(adapter.requests.where((r) => r.path == '/api/applications/').length, 2);
    expect(adapter.requests.where((r) => r.path == '/api/notifications/').length, 2);
  });
  test('refresh CSRF 403 invalida sesión sin bucle', () async {
    final adapter = FakeAdapter((r) => r.path.endsWith('/login') ? response(token()) : response({'detail': 'Rejected'}, r.path.endsWith('/refresh') ? 403 : 401));
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    addTearDown(client.dispose);
    ApiError? lost;
    client.onSessionLost = (error) => lost = error;
    await client.login('developer@example.com', 'password');
    await expectLater(client.request('/api/auth/me'), throwsA(isA<ApiError>()));
    expect(lost?.status, 403);
    expect(adapter.requests.where((r) => r.path.endsWith('/refresh')).length, 1);
  });
  test('403 de negocio después de renovar no cierra la sesión', () async {
    final adapter = FakeAdapter((r) {
      if (r.path.endsWith('/login')) return response(token('old'));
      if (r.path.endsWith('/refresh')) return response(token('new'));
      return response({'detail': 'Denied'}, r.headers['Authorization'] == 'Bearer new' ? 403 : 401);
    });
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    addTearDown(client.dispose);
    var lost = false;
    client.onSessionLost = (_) => lost = true;
    await client.login('developer@example.com', 'password');
    await expectLater(client.request('/api/users/'), throwsA(isA<ApiError>()));
    expect(lost, false);
  });
  test('logout espera refresh, revoca último access y descarta respuesta tardía', () async {
    final gate = Completer<void>();
    final adapter = FakeAdapter((r) async {
      if (r.path.endsWith('/login')) return response(token('old'));
      if (r.path.endsWith('/refresh')) { await gate.future; return response(token('new')); }
      if (r.path.endsWith('/logout')) return response({'message': 'Sesión cerrada'});
      return response({'detail': 'Expired'}, 401);
    });
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    addTearDown(client.dispose);
    await client.login('developer@example.com', 'password');
    final resource = client.request('/api/notifications/');
    final assertion = expectLater(resource, throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.superseded)));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final logout = client.logout();
    gate.complete();
    expect(await logout, true);
    await assertion;
    expect(adapter.requests.last.path, '/api/auth/logout');
    expect(adapter.requests.last.headers['Authorization'], 'Bearer new');
    expect(adapter.requests.where((r) => r.path == '/api/notifications/').length, 1);
  });
  test('401 tardío del replay no invalida una sesión nueva', () async {
    final replayStarted = Completer<void>();
    final releaseReplay = Completer<void>();
    var logins = 0;
    var resources = 0;
    final adapter = FakeAdapter((r) async {
      if (r.path.endsWith('/login')) return response(token(++logins == 1 ? 'old' : 'next-session'));
      if (r.path.endsWith('/refresh')) return response(token('rotated'));
      if (r.path.endsWith('/logout')) return response({'message': 'Sesión cerrada'});
      resources++;
      if (resources == 2) {
        replayStarted.complete();
        await releaseReplay.future;
      }
      return resources <= 2 ? response({'detail': 'Expired'}, 401) : response({'ok': true});
    });
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    addTearDown(client.dispose);
    var lost = false;
    client.onSessionLost = (_) => lost = true;
    await client.login('developer@example.com', 'password');
    final resource = client.request('/api/applications/');
    final assertion = expectLater(resource, throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.superseded)));
    await replayStarted.future;
    expect(await client.logout(), true);
    await client.login('other@example.com', 'password');
    releaseReplay.complete();
    await assertion;
    expect(lost, false);
    expect(await client.request('/api/applications/'), {'ok': true});
    expect(adapter.requests.last.headers['Authorization'], 'Bearer next-session');
    expect(adapter.requests.where((r) => r.path.endsWith('/refresh')).length, 1);
  });
  test('logout expirado obtiene access y reintenta solo una vez', () async {
    final adapter = FakeAdapter((r) {
      if (r.path.endsWith('/login')) return response(token('old'));
      if (r.path.endsWith('/refresh')) return response(token('new'));
      return r.headers['Authorization'] == 'Bearer new' ? response({'message': 'Sesión cerrada'}) : response({'detail': 'Expired'}, 401);
    });
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    addTearDown(client.dispose);
    await client.login('developer@example.com', 'password');
    expect(await client.logout(), true);
    expect(adapter.requests.where((r) => r.path.endsWith('/logout')).length, 2);
  });
  test('logout pendiente sobrevive recarga y se resuelve sin mostrar recursos', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var offline = false;
    final platform = FakePlatform(csrf: null);
    final adapter = FakeAdapter((r) {
      if (offline) throw DioException(requestOptions: r, type: DioExceptionType.connectionError);
      if (r.path.endsWith('/login')) { platform.csrf = 'csrf'; return response(token()); }
      if (r.path.endsWith('/refresh')) return response(token('restored'));
      if (r.path.endsWith('/logout')) return response({'message': 'Sesión cerrada'});
      return response(profile());
    });
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: platform);
    final repo = DemoRepository()..simulationEnabled = false;
    final auth = AuthNotifier(repo, prefs, api: ApiAuthService(client));
    addTearDown(() { auth.dispose(); repo.dispose(); client.dispose(); });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await auth.login('developer@example.com', 'password');
    expect(auth.state.phase, SessionPhase.authenticated);
    offline = true;
    await auth.logout();
    expect(auth.state.phase, SessionPhase.logoutPending);
    expect(prefs.getBool(auth.pendingKey), true);
    await auth.restore();
    expect(auth.state.phase, SessionPhase.logoutPending);
    expect(auth.state.user, null);
    offline = false;
    await auth.resolvePendingLogout();
    expect(auth.state.phase, SessionPhase.signedOut);
    expect(prefs.getBool(auth.pendingKey), null);
    expect(prefs.getKeys().any((key) => key.contains('token') || key.contains('password')), false);
  });
  test('422/429/5xx y timeout no repiten mutaciones', () async {
    for (final status in [422, 429, 500]) {
      final adapter = FakeAdapter((r) => r.path.endsWith('/login') ? response(token()) : response({'detail': 'Failed'}, status));
      final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
      await client.login('developer@example.com', 'password');
      await expectLater(client.request('/api/notifications/mark-read', method: 'POST'), throwsA(isA<ApiError>()));
      expect(adapter.requests.length, 2);
      client.dispose();
    }
    final adapter = FakeAdapter((r) {
      if (r.path.endsWith('/login')) return response(token());
      throw DioException(requestOptions: r, type: DioExceptionType.receiveTimeout);
    });
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    await client.login('developer@example.com', 'password');
    await expectLater(client.request('/api/notifications/mark-read', method: 'POST'), throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.network)));
    expect(adapter.requests.length, 2);
    client.dispose();
  });
}
