import 'dart:async';

import 'package:corestream_mobile/data/api_client.dart';
import 'package:corestream_mobile/main.dart';
import 'package:corestream_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_test_support.dart';

void main() {
  EditableText field(WidgetTester tester, String key) => tester.widget<EditableText>(
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(EditableText)));

  Future<FakeAdapter> mount(WidgetTester tester, {
    FutureOr<ResponseBody> Function(RequestOptions)? handler,
    Map<String, Object> preferences = const {},
    String? csrf,
  }) async {
    SharedPreferences.setMockInitialValues(preferences);
    final prefs = await SharedPreferences.getInstance();
    final platform = FakePlatform(csrf: csrf);
    final adapter = FakeAdapter((r) {
      if (r.path.endsWith('/login')) platform.csrf = 'test-csrf';
      return handler?.call(r) ?? response(switch (r.path) {
        '/api/auth/login' => token(), '/api/auth/me' => profile(),
        '/api/auth/refresh' => token(), '/api/auth/logout' => {'message': 'Sesión cerrada'},
        '/api/notifications/unread-count' => {'unread_count': 0, 'user_id': userId},
        _ => [],
      });
    });
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: platform);
    addTearDown(() async { await tester.pumpWidget(const SizedBox()); client.dispose(); });
    await tester.pumpWidget(ProviderScope(overrides: [
      prefsProvider.overrideWithValue(prefs), apiModeProvider.overrideWithValue(true),
      apiClientProvider.overrideWithValue(client), apiWebsocketProvider.overrideWithValue(null),
    ], child: const CoreStreamApp()));
    await tester.pumpAndSettle();
    return adapter;
  }

  Future<void> credentials(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('login_email')), 'developer@example.com');
    await tester.enterText(find.byKey(const Key('login_password')), 'Password123!');
  }

  for (final width in [390.0, 1280.0]) {
    for (final dark in [true, false]) {
      for (final lang in ['es', 'en']) {
        testWidgets('formulario adaptable $width ${dark ? 'oscuro' : 'claro'} $lang con teclado', (tester) async {
          tester.view.physicalSize = Size(width, width == 390 ? 844 : 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          final adapter = await mount(tester, preferences: {'dark': dark, 'lang': lang});
          expect(find.byKey(const Key('auth_brand')), findsOneWidget);
          expect(find.text(lang == 'es' ? 'Correo electrónico' : 'Email address'), findsOneWidget);
          await tester.tap(find.byKey(const Key('login_email')));
          await tester.testTextInput.receiveAction(TextInputAction.next);
          await tester.pump();
          final password = tester.widget<EditableText>(find.descendant(
            of: find.byKey(const Key('login_password')), matching: find.byType(EditableText)));
          expect(password.focusNode.hasFocus, true);
          await tester.enterText(find.byKey(const Key('login_email')), 'developer@example.com');
          tester.view.viewInsets = const FakeViewPadding(bottom: 320);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(const Key('login_submit')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('login_submit')));
          await tester.pumpAndSettle();
          expect(find.text(lang == 'es' ? 'Campo obligatorio.' : 'Required field.'), findsOneWidget);
          expect(adapter.requests, isEmpty);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('Tab, contraseña visible/oculta y Enter permiten ingreso sin doble envío', (tester) async {
    final gate = Completer<ResponseBody>();
    final adapter = await mount(tester, handler: (r) {
      if (r.path.endsWith('/login')) return gate.future;
      return response(r.path.endsWith('/me') ? profile() : r.path.endsWith('/unread-count') ? {'unread_count': 0, 'user_id': userId} : []);
    });
    await tester.tap(find.byKey(const Key('login_email')));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final password = tester.widget<EditableText>(find.descendant(
      of: find.byKey(const Key('login_password')), matching: find.byType(EditableText)));
    expect(password.focusNode.hasFocus, true);
    await credentials(tester);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();
    expect(field(tester, 'login_password').obscureText, false);
    await tester.tap(find.byTooltip('Ocultar contraseña'));
    await tester.pump();
    expect(field(tester, 'login_password').obscureText, true);
    await tester.tap(find.byKey(const Key('login_password')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('login_submit'))).onPressed, isNull);
    expect(tester.widget<TextFormField>(find.byKey(const Key('login_email'))).enabled, false);
    field(tester, 'login_password').onSubmitted!('Password123!');
    await tester.pump(const Duration(milliseconds: 100));
    expect(adapter.requests.where((r) => r.path.endsWith('/login')).length, 1);
    gate.complete(response(token()));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('429 respeta Retry-After, muestra espera y bloquea Enter/reintento', (tester) async {
    final adapter = await mount(tester, handler: (_) => response({'detail': 'Demasiados intentos'}, 429, {'retry-after': ['2']}));
    await credentials(tester);
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Puedes volver a intentarlo en 2 s.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('login_submit'))).onPressed, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Reintentar')).onPressed, isNull);
    field(tester, 'login_password').onSubmitted!('Password123!');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Puedes volver a intentarlo en 1 s.'), findsOneWidget);
    expect(adapter.requests.length, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login_cooldown')), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const Key('login_submit'))).onPressed, isNotNull);
  });

  testWidgets('error de red mantiene formulario y permite recuperar el ingreso', (tester) async {
    var offline = true;
    final adapter = await mount(tester, handler: (r) {
      if (offline) throw DioException(requestOptions: r, type: DioExceptionType.connectionError);
      return response(r.path.endsWith('/login') ? token() : r.path.endsWith('/me') ? profile() :
        r.path.endsWith('/unread-count') ? {'unread_count': 0, 'user_id': userId} : []);
    });
    await credentials(tester);
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo conectar'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    offline = false;
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(adapter.requests.where((r) => r.path.endsWith('/login')).length, 2);
  });

  testWidgets('restauración pendiente muestra marca y no abre recursos anticipadamente', (tester) async {
    final gate = Completer<ResponseBody>();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final adapter = FakeAdapter((r) {
      if (r.path.endsWith('/refresh')) return gate.future;
      return response(r.path.endsWith('/me') ? profile() : r.path.endsWith('/unread-count') ? {'unread_count': 0, 'user_id': userId} : []);
    });
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    addTearDown(() async { await tester.pumpWidget(const SizedBox()); client.dispose(); });
    await tester.pumpWidget(ProviderScope(overrides: [
      prefsProvider.overrideWithValue(prefs), apiModeProvider.overrideWithValue(true),
      apiClientProvider.overrideWithValue(client), apiWebsocketProvider.overrideWithValue(null),
    ], child: const CoreStreamApp()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('auth_brand')), findsOneWidget);
    expect(find.text('Recuperando sesión…'), findsOneWidget);
    expect(adapter.requests.map((r) => r.path), ['/api/auth/refresh']);
    gate.complete(response(token()));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('cierre pendiente impide login y se confirma al recuperar la conexión', (tester) async {
    var offline = true;
    final adapter = await mount(tester, preferences: {'logout_pending:http://localhost:8001': true}, csrf: 'test-csrf',
      handler: (r) {
        if (offline) throw DioException(requestOptions: r, type: DioExceptionType.connectionError);
        return response(r.path.endsWith('/refresh') ? token() : {'message': 'Sesión cerrada'});
      });
    expect(find.byKey(const Key('auth_brand')), findsOneWidget);
    expect(find.byKey(const Key('logout_pending')), findsOneWidget);
    expect(find.byKey(const Key('login_email')), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    offline = false;
    await tester.tap(find.text('Confirmar cierre con el servidor'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login_email')), findsOneWidget);
    expect(adapter.requests.where((r) => r.path.endsWith('/login')), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('logout_pending:http://localhost:8001'), isNull);
  });

  testWidgets('cambio obligatorio valida coincidencia y Enter ejecuta cambio y cierre una vez', (tester) async {
    var mandatory = true;
    final gate = Completer<ResponseBody>();
    final adapter = await mount(tester, handler: (r) {
      if (r.path.endsWith('/change-password')) { mandatory = false; return gate.future; }
      return response(r.path.endsWith('/login') ? token() : r.path.endsWith('/me') ? profile(passwordRequired: mandatory) : {'message': 'Sesión cerrada'});
    });
    await credentials(tester);
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auth_brand')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('old_password')), 'Password123!');
    await tester.enterText(find.byKey(const Key('new_password')), 'NewPassword123!');
    await tester.enterText(find.byKey(const Key('confirm_password')), 'different');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    expect(adapter.requests.where((r) => r.path.endsWith('/change-password')), isEmpty);
    await tester.enterText(find.byKey(const Key('confirm_password')), 'NewPassword123!');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('change_password_submit'))).onPressed, isNull);
    field(tester, 'confirm_password').onSubmitted!('NewPassword123!');
    await tester.pump(const Duration(milliseconds: 100));
    expect(adapter.requests.where((r) => r.path.endsWith('/change-password')).length, 1);
    gate.complete(response({'message': 'Contraseña actualizada'}));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login_email')), findsOneWidget);
    expect(find.text('Sesión cerrada y revocación confirmada.'), findsOneWidget);
    expect(adapter.requests.where((r) => r.path.endsWith('/logout')).length, 1);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
