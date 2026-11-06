import 'dart:async';

import 'package:corestream_mobile/core/theme.dart';
import 'package:corestream_mobile/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pending operation blocks a second click and failure allows explicit retry', (tester) async {
    var calls = 0;
    late Completer<void> pending;
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark), home: Scaffold(
      body: CsMutationButton(child: const Text('Guardar'), onPressed: () {
        calls++;
        pending = Completer<void>();
        return pending.future;
      }),
    )));
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    pending.completeError(StateError('Operación rechazada'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Operación rechazada'), findsOneWidget);
    expect(calls, 1);
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(calls, 2);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
