import 'package:corestream_mobile/data/api_client.dart';
import 'package:corestream_mobile/main.dart';
import 'package:corestream_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_test_support.dart';

void main() {
  Future<FakeAdapter> mount(WidgetTester tester, {bool invalid = false, bool mandatory = false}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final platform = FakePlatform(csrf: null);
    final adapter = FakeAdapter((r) {
      if (r.path.endsWith('/login')) {
        if (invalid) return response({'detail': 'Email o contraseña incorrectos'}, 401);
        platform.csrf = 'csrf';
        return response(token());
      }
      if (r.path.endsWith('/me')) return response(profile(role: 'TEAM_LEADER', passwordRequired: mandatory));
      if (r.path.endsWith('/unread-count')) return response({'unread_count': 3, 'user_id': userId});
      if (r.path.endsWith('/logout')) return response({'message': 'Sesión cerrada'});
      return response([]);
    });
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: platform);
    addTearDown(client.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      prefsProvider.overrideWithValue(prefs), apiModeProvider.overrideWithValue(true),
      apiClientProvider.overrideWithValue(client), apiWebsocketProvider.overrideWithValue(null),
    ], child: const CoreStreamApp()));
    await tester.pumpAndSettle();
    return adapter;
  }
  testWidgets('API muestra formulario sin selector ni consulta users', (tester) async {
    final adapter = await mount(tester);
    expect(find.byKey(const Key('login_email')), findsOneWidget);
    expect(find.text('Ana Torres'), findsNothing);
    expect(adapter.requests, isEmpty);
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Introduce un correo válido.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });
  testWidgets('login líder abre beta, campana, Ajustes y logout conserva formulario', (tester) async {
    final adapter = await mount(tester);
    await tester.enterText(find.byKey(const Key('login_email')), 'developer@example.com');
    await tester.enterText(find.byKey(const Key('login_password')), 'password');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('3'), findsOneWidget);
    expect(adapter.requests.any((r) => r.path.contains('/mobile')), false);
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Líder de equipo'), findsOneWidget);
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login_email')), findsOneWidget);
    expect(find.text('Sesión cerrada y revocación confirmada.'), findsOneWidget);
  });
  testWidgets('logout retira rutas y paneles fuera del shell', (tester) async {
    await mount(tester);
    await tester.enterText(find.byKey(const Key('login_email')), 'developer@example.com');
    await tester.enterText(find.byKey(const Key('login_password')), 'password');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(NavigationBar));
    final container = ProviderScope.containerOf(context);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Detalle anterior'))));
    await tester.pumpAndSettle();
    expect(find.text('Detalle anterior'), findsOneWidget);
    final closing = container.read(authControllerProvider.notifier).logout();
    await tester.pumpAndSettle();
    await closing;
    expect(find.text('Detalle anterior'), findsNothing);
    expect(find.byKey(const Key('login_email')), findsOneWidget);
  });
  testWidgets('login inválido muestra error sin recursos', (tester) async {
    await mount(tester, invalid: true);
    await tester.enterText(find.byKey(const Key('login_email')), 'developer@example.com');
    await tester.enterText(find.byKey(const Key('login_password')), 'wrong');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Email o contraseña incorrectos'), findsOneWidget);
    expect(find.text('Aplicaciones'), findsNothing);
  });
  testWidgets('flag obligatorio abre cambio antes de aplicaciones', (tester) async {
    await mount(tester, mandatory: true);
    await tester.enterText(find.byKey(const Key('login_email')), 'developer@example.com');
    await tester.enterText(find.byKey(const Key('login_password')), 'password');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new_password')), findsOneWidget);
    expect(find.text('Aplicaciones'), findsNothing);
  });
}
