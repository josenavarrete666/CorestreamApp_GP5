import 'dart:ui' show Tristate;

import 'package:corestream_mobile/core/i18n.dart';
import 'package:corestream_mobile/core/theme.dart';
import 'package:corestream_mobile/data/repository.dart';
import 'package:corestream_mobile/models/models.dart';
import 'package:corestream_mobile/providers.dart';
import 'package:corestream_mobile/ui/projects_screens.dart';
import 'package:corestream_mobile/ui/ticket_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final role in UserRole.values) {
    testWidgets('single-ticket epic keeps its button and keyboard navigation: ${role.name}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final handle = tester.ensureSemantics();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const project = Project(id: 'p', name: 'API Pagos', code: 'AP', color: Colors.green);
      const first = Epic(id: 'e1', projectId: 'p', name: 'Conciliación bancaria');
      const second = Epic(id: 'e2', projectId: 'p', name: 'Webhooks de pago');
      final selected = Ticket(id: 'selected', number: 0, epicId: second.id,
          title: 'Reintentos exponenciales en webhooks fallidos', description: 'Detalle correcto');
      final board = Board(project: project, epics: [
        EpicBoard(epic: first, tickets: [Ticket(id: 'first', number: 0, epicId: first.id,
            title: 'Primer ticket', description: '')]),
        EpicBoard(epic: second, tickets: [selected]),
      ]);
      await tester.pumpWidget(ProviderScope(overrides: [
        apiModeProvider.overrideWithValue(false),
        prefsProvider.overrideWithValue(prefs),
        authProvider.overrideWithValue(User(id: 'u', fullName: 'Persona', role: role)),
        stringsProvider.overrideWithValue(S.byCode('es')),
        boardProvider.overrideWith((ref, id) async => board),
        ticketDetailProvider.overrideWith((ref, id) async {
          expect(id, selected.id);
          return TicketDetail(ticket: selected, epic: second, project: project,
              permissions: const TicketPermissions());
        }),
      ], child: MaterialApp(theme: buildTheme(Brightness.dark), home: const BoardScreen(projectId: 'p'))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(selected.title));
      await tester.pumpAndSettle();
      final semantics = tester.getSemantics(find.text(selected.title)).getSemanticsData();
      expect(semantics.label, contains(selected.title));
      expect(semantics.flagsCollection.isButton, isTrue);
      expect(semantics.flagsCollection.isFocused, isNot(Tristate.none));
      for (var i = 0; i < 12 && find.byType(TicketDetailScreen).evaluate().isEmpty; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        if (tester.getSemantics(find.text(selected.title)).getSemanticsData().flagsCollection.isFocused == Tristate.isTrue) {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
        }
      }
      expect(find.byType(TicketDetailScreen), findsOneWidget);
      expect(find.text('Detalle correcto'), findsOneWidget);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });
  }
}
