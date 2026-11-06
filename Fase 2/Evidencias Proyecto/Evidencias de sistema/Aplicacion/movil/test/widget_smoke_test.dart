// Smoke test de UI: login por rol y navegación básica.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corestream_mobile/main.dart';
import 'package:corestream_mobile/providers.dart';
import 'package:corestream_mobile/data/demo_repository.dart';
import 'package:corestream_mobile/ui/widgets.dart';

void main() {
  testWidgets('login como Admin muestra el dashboard y permite cerrar sesión',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(overrides: [
      prefsProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    // desactivar la simulación para no dejar timers pendientes
    final repo = container.read(repositoryProvider);
    (repo as DemoRepository).simulationEnabled = false;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CoreStreamApp(),
    ));
    await tester.pumpAndSettle();

    // pantalla de login con los tres roles demo
    expect(find.text('CoreStream'), findsOneWidget);
    expect(find.text('Ana Torres'), findsOneWidget);
    expect(find.text('Diego Ramos'), findsOneWidget);

    // entrar como Admin
    await tester.tap(find.text('Ana Torres'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Hola, Ana'), findsOneWidget);
    expect(find.text('Proyectos'), findsWidgets);
    expect(find.text('Portal Clientes'), findsWidgets);

    // cerrar sesión (cancela el timer de simulación)
    await container.read(authControllerProvider.notifier).logout();
    await tester.pumpAndSettle();
    expect(find.text('Ana Torres'), findsOneWidget);
  });

  testWidgets('los contadores Aplicaciones y Tickets abiertos abren sus pestañas',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      prefsProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    (container.read(repositoryProvider) as DemoRepository).simulationEnabled = false;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CoreStreamApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Torres'));
    await tester.pumpAndSettle();

    int selectedTab() => tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;
    expect(selectedTab(), 0);

    await tester.tap(find.widgetWithText(StatTile, 'Aplicaciones'));
    await tester.pumpAndSettle();
    expect(selectedTab(), 1);

    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    expect(selectedTab(), 0);

    await tester.tap(find.widgetWithText(StatTile, 'Tickets abiertos'));
    await tester.pumpAndSettle();
    expect(selectedTab(), 2);

    await container.read(authControllerProvider.notifier).logout();
    await tester.pumpAndSettle();
  });

  Future<ProviderContainer> loginAna(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    (container.read(repositoryProvider) as DemoRepository).simulationEnabled = false;
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CoreStreamApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Torres'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('los recuadros no desbordan en un Samsung S20 (360×800 dp)', (tester) async {
    // Medidas reales del S20 de pruebas: 1080×2400 a densidad 480 (3x), font_scale 1.0.
    // Con la proporción fija anterior el recuadro medía 69 px y el contenido ~72.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final container = await loginAna(tester);

    // Un "BOTTOM OVERFLOWED" se reporta como excepción del framework.
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(StatTile, 'Tickets abiertos'), findsOneWidget);

    await container.read(authControllerProvider.notifier).logout();
    await tester.pumpAndSettle();
  });

  testWidgets('atrás en otra pestaña vuelve a Inicio sin cerrar la sesión', (tester) async {
    final container = await loginAna(tester);
    int selectedTab() => tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

    await tester.tap(find.text('Proyectos').last);
    await tester.pumpAndSettle();
    expect(selectedTab(), 1);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(selectedTab(), 0);
    expect(container.read(authProvider), isNotNull);

    await container.read(authControllerProvider.notifier).logout();
    await tester.pumpAndSettle();
  });
}
