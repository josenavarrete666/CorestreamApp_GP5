// Push FCM (APP-06) y desactivación del dispositivo en el logout (APP-03).

import 'dart:async';

import 'package:corestream_mobile/data/api_client.dart';
import 'package:corestream_mobile/data/api_error.dart';
import 'package:corestream_mobile/data/api_repository.dart';
import 'package:corestream_mobile/data/demo_repository.dart';
import 'package:corestream_mobile/data/repository.dart';
import 'package:corestream_mobile/models/models.dart';
import 'package:corestream_mobile/models/session_state.dart';
import 'package:corestream_mobile/providers.dart';
import 'package:corestream_mobile/services/api_auth_service.dart';
import 'package:corestream_mobile/services/auth_notifier.dart';
import 'package:corestream_mobile/services/push_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_test_support.dart';

const ticketId = 'b7926d68-59ec-59a6-95e8-7f3a5b66eff0';

class FakePush implements PushService {
  FakePush({this.current = 'fcm-token-1'});
  String? current;
  final refreshes = StreamController<String>.broadcast();
  final opens = StreamController<PushOpen>.broadcast();
  @override
  String get platform => 'ANDROID';
  @override
  Future<String?> init() async => current;
  @override
  Future<String?> token() async => current;
  @override
  Stream<String> get tokenRefresh => refreshes.stream;
  @override
  Stream<PushOpen> get opened => opens.stream;
}

class RecordingRepository extends DemoRepository {
  final registered = <(String, String)>[];
  bool fail = false;
  @override
  Future<void> registerDevice(String fcmToken, String platform) async {
    registered.add((fcmToken, platform));
    if (fail) throw const ApiError(ApiErrorKind.operation, 'sin red');
  }
}

ApiClient _client(FakeAdapter adapter, [FakePlatform? platform]) =>
    ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: platform ?? FakePlatform());

FakeAdapter _server({bool Function()? offline}) => FakeAdapter((r) {
      if (offline?.call() ?? false) throw DioException(requestOptions: r, type: DioExceptionType.connectionError);
      if (r.path.endsWith('/login')) return response(token());
      if (r.path.endsWith('/refresh')) return response(token('restored'));
      if (r.path.endsWith('/logout')) return response({'message': 'Sesión cerrada', 'device_deactivated': true});
      if (r.path == '/api/devices/') {
        return response({'id': notificationId, 'platform': 'ANDROID', 'is_active': true,
            'last_seen_at': '2026-11-04T12:00:00Z', 'deactivated_at': null, 'created_at': '2026-11-04T12:00:00Z'});
      }
      return response(profile());
    });

void main() {
  test('logout con dispositivo envía su token para desactivarlo', () async {
    final adapter = _server();
    final client = _client(adapter);
    addTearDown(client.dispose);
    await client.login('developer@example.com', 'password');

    expect(await client.logout(deviceToken: 'fcm-token-1'), true);
    expect(adapter.requests.last.path, '/api/auth/logout');
    expect(adapter.requests.last.data, {'fcm_token': 'fcm-token-1'});
  });

  test('logout sin push conserva la petición sin cuerpo', () async {
    final adapter = _server();
    final client = _client(adapter);
    addTearDown(client.dispose);
    await client.login('developer@example.com', 'password');

    expect(await client.logout(), true);
    expect(adapter.requests.last.data, isNull);
  });

  test('el cierre pendiente sin red también desactiva el dispositivo al confirmarse', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var offline = false;
    final adapter = _server(offline: () => offline);
    final client = _client(adapter);
    final repo = DemoRepository()..simulationEnabled = false;
    final push = FakePush();
    final auth = AuthNotifier(repo, prefs, api: ApiAuthService(client), deviceToken: push.token);
    addTearDown(() { auth.dispose(); repo.dispose(); client.dispose(); });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await auth.login('developer@example.com', 'password');

    offline = true;
    await auth.logout();
    expect(auth.state.phase, SessionPhase.logoutPending);

    offline = false;
    await auth.resolvePendingLogout();
    expect(auth.state.phase, SessionPhase.signedOut);
    final logouts = adapter.requests.where((r) => r.path == '/api/auth/logout').toList();
    expect(logouts.last.data, {'fcm_token': 'fcm-token-1'});
    expect(prefs.getKeys().any((key) => key.contains('fcm') || key.contains('device')), false);
  });

  test('un fallo al leer el token push no impide cerrar sesión', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final adapter = _server();
    final client = _client(adapter);
    final repo = DemoRepository()..simulationEnabled = false;
    final auth = AuthNotifier(repo, prefs, api: ApiAuthService(client),
        deviceToken: () async => throw StateError('Firebase no disponible'));
    addTearDown(() { auth.dispose(); repo.dispose(); client.dispose(); });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await auth.login('developer@example.com', 'password');

    await auth.logout();
    expect(auth.state.phase, SessionPhase.signedOut);
    expect(adapter.requests.last.data, isNull);
  });

  test('registrar el dispositivo usa la ruta de dispositivos y valida la respuesta', () async {
    final adapter = _server();
    final client = _client(adapter);
    final repo = ApiRepository(client);
    addTearDown(() { repo.dispose(); client.dispose(); });
    await client.login('developer@example.com', 'password');

    await repo.registerDevice('fcm-token-1', 'ANDROID');
    final request = adapter.requests.last;
    expect(request.path, '/api/devices/');
    expect(request.method, 'POST');
    expect(request.data, {'fcm_token': 'fcm-token-1', 'platform': 'ANDROID'});
  });

  test('una respuesta sin is_active es un error de contrato', () async {
    final adapter = FakeAdapter((r) => r.path.endsWith('/login') ? response(token()) : response({'id': notificationId}));
    final client = _client(adapter);
    final repo = ApiRepository(client);
    addTearDown(() { repo.dispose(); client.dispose(); });
    await client.login('developer@example.com', 'password');

    await expectLater(repo.registerDevice('fcm-token-1', 'ANDROID'),
        throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.contract)));
  });

  group('con sesión iniciada', () {
    late ProviderContainer container;
    late FakePush push;
    late RecordingRepository repo;
    const user = User(id: userId, fullName: 'Developer real', role: UserRole.developer);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      push = FakePush();
      repo = RecordingRepository()..simulationEnabled = false;
      container = ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(prefs),
        apiModeProvider.overrideWithValue(true),
        authProvider.overrideWithValue(user),
        pushServiceProvider.overrideWithValue(push),
        repositoryProvider.overrideWithValue(repo as CoreStreamRepository),
      ]);
      addTearDown(() { container.dispose(); repo.dispose(); });
    });

    test('registra el dispositivo y lo vuelve a registrar si el token rota', () async {
      container.listen(pushRegistrationProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(repo.registered, [('fcm-token-1', 'ANDROID')]);

      push.refreshes.add('fcm-token-2');
      await Future<void>.delayed(Duration.zero);
      expect(repo.registered.last, ('fcm-token-2', 'ANDROID'));
    });

    test('sin permiso de push no registra nada', () async {
      push.current = null;
      container.listen(pushRegistrationProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(repo.registered, isEmpty);
    });

    test('un fallo de registro no propaga errores a la sesión', () async {
      repo.fail = true;
      final errors = <Object>[];
      await runZonedGuarded(() async {
        container.listen(pushRegistrationProvider, (_, __) {});
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => errors.add(error));
      expect(repo.registered, hasLength(1));
      expect(errors, isEmpty);
    });

    test('un push tocado se convierte en la notificación de su ticket', () async {
      final opened = <AppNotification>[];
      container.listen(pushOpenedProvider, (_, next) { if (next.valueOrNull != null) opened.add(next.value!); });
      push.opens.add(const PushOpen(
        data: {'notification_id': notificationId, 'type': 'TICKET_ASSIGNED', 'ticket_id': ticketId,
            'route': '/tickets/$ticketId'},
        title: 'Ticket asignado', body: 'Ana te asignó el ticket',
      ));
      await Future<void>.delayed(Duration.zero);
      expect(opened, hasLength(1));
      expect(opened.single.id, notificationId);
      expect(opened.single.ticketId, ticketId);
      expect(opened.single.kind, NotificationKind.assignment);
      expect(opened.single.title, 'Ticket asignado');
    });

    test('un push tocado sin título ni cuerpo también abre su ticket', () async {
      final opened = <AppNotification>[];
      container.listen(pushOpenedProvider, (_, next) { if (next.valueOrNull != null) opened.add(next.value!); });
      // Android puede entregar el toque solo con los datos, sin el bloque de texto.
      push.opens.add(const PushOpen(data: {'notification_id': notificationId, 'type': 'TICKET_ASSIGNED',
          'ticket_id': ticketId, 'route': '/tickets/$ticketId'}));
      await Future<void>.delayed(Duration.zero);
      expect(opened.single.ticketId, ticketId);
    });

    test('un push sin ticket no intenta navegar', () async {
      final opened = <AppNotification>[];
      container.listen(pushOpenedProvider, (_, next) { if (next.valueOrNull != null) opened.add(next.value!); });
      push.opens.add(const PushOpen(data: {'notification_id': notificationId, 'type': 'SYSTEM',
          'ticket_id': '', 'route': '/notifications'}));
      await Future<void>.delayed(Duration.zero);
      expect(opened, isEmpty);
    });
  });
}
