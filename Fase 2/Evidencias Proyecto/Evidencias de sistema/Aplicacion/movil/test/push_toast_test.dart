// Banner flotante de avisos (showPushToast).

import 'package:corestream_mobile/core/theme.dart';
import 'package:corestream_mobile/models/models.dart';
import 'package:corestream_mobile/providers.dart';
import 'package:corestream_mobile/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _notification = AppNotification(
  id: 'n1',
  kind: NotificationKind.assignment,
  title: 'Ticket asignado',
  message: 'Ana Torres te asignó el ticket "Prueba02"',
  ts: DateTime(2026, 11, 6),
);

Future<void Function()> _mount(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  late BuildContext ctx;
  late WidgetRef widgetRef;
  await tester.pumpWidget(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(theme: buildTheme(Brightness.dark), home: Consumer(builder: (context, ref, _) {
      ctx = context;
      widgetRef = ref;
      return const Scaffold(body: SizedBox());
    })),
  ));
  return () => showPushToast(ctx, widgetRef, _notification, onOpen: (_) {});
}

void main() {
  testWidgets('el banner se muestra con su texto y desaparece a los 5 segundos', (tester) async {
    final show = await _mount(tester);
    show();
    await tester.pump();
    expect(find.text('Ticket asignado'), findsOneWidget);
    // Evita regresiones de codificación: el separador es «·», no «Â·».
    expect(find.text('CORESTREAM · AHORA'), findsOneWidget);

    await tester.pump(pushToastDuration);
    await tester.pump();
    expect(find.text('Ticket asignado'), findsNothing);
  });

  testWidgets('con la app en segundo plano no se inserta banner', (tester) async {
    final show = await _mount(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    show();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Ticket asignado'), findsNothing);
  });

  testWidgets('un banner que aún no se dibujó también se retira', (tester) async {
    final show = await _mount(tester);
    show();
    // Sin pump: el banner está insertado pero aún no montado, como ocurría
    // cuando el aviso llegaba justo al pasar a segundo plano.
    await tester.pump(pushToastDuration);
    await tester.pump();
    expect(find.text('Ticket asignado'), findsNothing);
  });
}
