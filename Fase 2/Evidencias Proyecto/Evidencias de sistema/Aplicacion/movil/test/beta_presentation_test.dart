import 'package:corestream_mobile/core/i18n.dart';
import 'package:corestream_mobile/core/theme.dart';
import 'package:corestream_mobile/data/api_client.dart';
import 'package:corestream_mobile/data/api_repository.dart';
import 'package:corestream_mobile/models/api_models.dart';
import 'package:corestream_mobile/models/models.dart';
import 'package:corestream_mobile/providers.dart';
import 'package:corestream_mobile/ui/incidents_screens.dart';
import 'package:corestream_mobile/ui/team_screen.dart';
import 'package:corestream_mobile/ui/ticket_detail_screen.dart';
import 'package:corestream_mobile/ui/ticket_sheets.dart';
import 'package:corestream_mobile/ui/widgets.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_domain_test.dart' show application, epic, ticket, incident, appId, epicId, ticketId;
import 'api_test_support.dart';

void main() {
  Future<FakeAdapter> mount(WidgetTester tester, Widget screen, String lang,
      {List<Map<String, Object?>> events = const [], bool empty = false}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final person = {...profile(role: 'TEAM_LEADER'), 'full_name': 'Responsable con un nombre completo especialmente largo'};
    final item = {...ticket(status: 'IN_PROGRESS'), 'assignee': person,
      'pr_link': 'https://github.com/organization-with-a-long-name/repository/pull/123456'};
    final adapter = FakeAdapter((r) => response(switch (r.path) {
      '/api/auth/login' => token(), '/api/applications/' => empty ? [] : [application()],
      '/api/epics/by-app/$appId' => [epic([item])], '/api/tickets/$ticketId' => item,
      '/api/tickets/$ticketId/events' => events, '/api/users/' => empty ? [] : [person],
      '/api/incidents/' => [], '/api/incidents/$notificationId' => {...incident(),
        'assigned_to_id': epicId, 'created_by_id': epicId},
      _ => throw StateError('Unexpected request ${r.path}'),
    }));
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    SharedPreferences.setMockInitialValues({'lang': lang});
    final prefs = await SharedPreferences.getInstance();
    final repo = ApiRepository(client);
    final user = ApiProfile.fromJson(person).user;
    await tester.runAsync(() => client.login('leader@example.com', 'test-password'));
    repo.setSession(user);
    addTearDown(() async { await tester.pumpWidget(const SizedBox()); repo.dispose(); client.dispose(); });
    await tester.pumpWidget(ProviderScope(overrides: [
      apiModeProvider.overrideWithValue(true), repositoryProvider.overrideWithValue(repo),
      authProvider.overrideWithValue(user), stringsProvider.overrideWithValue(S.byCode(lang)),
      prefsProvider.overrideWithValue(prefs),
    ], child: MaterialApp(theme: buildTheme(lang == 'es' ? Brightness.dark : Brightness.light), home: screen)));
    await tester.pumpAndSettle();
    return adapter;
  }

  for (final lang in ['es', 'en']) {
    testWidgets('API history $lang preserves unknown events and absent transition/destination', (tester) async {
      final s = S.byCode(lang);
      final types = ['CREATED', 'ASSIGNED', 'STATUS_CHANGED', 'QUESTION_RAISED',
        'QUESTION_RESOLVED', 'REDIRECTED', 'COMPLETED', 'COMMENT', 'UPDATED', 'MOVED',
        'TIMER_START', 'TIMER_PAUSE', 'TIMER_SYNC', 'SUBTASK_CREATED', 'SUBTASK_COMPLETED', 'SUBTASK_DELETED', 'FUTURE_EVENT'];
      final labels = ['ev_created', 'ev_assigned', 'ev_status_changed', 'n_QUESTION',
        'ev_resolved', 'ev_redirected', 'n_COMPLETION', 'ev_comment', 'ev_updated', 'ev_moved',
        'ev_timer_start', 'ev_timer_pause', 'ev_timer_sync', 'ev_subtask_created', 'ev_subtask_completed', 'ev_subtask_deleted', 'FUTURE_EVENT'];
      final adapter = await mount(tester, const TicketDetailScreen(ticketId: ticketId), lang,
        events: [for (var i = 0; i < types.length; i++) {
          'id': '00000000-0000-0000-0000-${(i + 100).toString().padLeft(12, '0')}',
          'ticket_id': ticketId, 'event_type': types[i], 'user_id': userId, 'user': profile(),
          'created_at': DateTime.utc(2026, 10, 12, 0, i).toIso8601String(), 'detail': null,
        }]);
      expect(find.text(s('ticket')), findsOneWidget);
      expect(find.text(s('timer_paused')), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final label in labels.reversed) {
        await tester.scrollUntilVisible(find.textContaining(s(label), findRichText: true), 250,
            scrollable: find.byType(Scrollable).first, maxScrolls: 40);
        expect(tester.takeException(), isNull);
      }
      expect(find.textContaining('→', findRichText: true), findsNothing);
      await tester.scrollUntilVisible(find.byType(ResourceIdentity), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text(ticketId), findsOneWidget);
      expect(adapter.requests.where((r) => r.method != 'GET' && !r.path.endsWith('/login')), isEmpty);
    });

    testWidgets('API incident $lang distinguishes unavailable users, real mitigation and identity', (tester) async {
      final s = S.byCode(lang);
      await mount(tester, const IncidentDetailScreen(incidentId: notificationId), lang);
      expect(find.text(s('user_unavailable')), findsNWidgets(2));
      expect(find.text(s('unassigned')), findsNothing);
      expect(find.text('PRODUCTION'), findsOneWidget);
      expect(find.text(s('is_MITIGATED')), findsWidgets);
      expect(find.text(s('is_UNDER_REVIEW')), findsNothing);
      await tester.scrollUntilVisible(find.byType(ResourceIdentity), 250, scrollable: find.byType(Scrollable).first);
      expect(find.text(notificationId), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('API empty team $lang has an explicit empty state', (tester) async {
      await mount(tester, const Scaffold(body: TeamScreen()), lang, empty: true);
      expect(find.text(S.byCode(lang)('no_team')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  }

  testWidgets('ticket panel keeps its submit reachable with keyboard and long user names', (tester) async {
    final adapter = await mount(tester, Scaffold(body: Consumer(builder: (context, ref, _) => TextButton(
      onPressed: () => showNewTicketSheet(context, ref, epic: const Epic(id: epicId, projectId: appId, name: 'Épica real')), child: const Text('Open')))), 'es');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Guardar')).bottom, lessThan(844 - 320));
    expect(tester.takeException(), isNull);
    expect(adapter.requests.where((r) => r.method == 'POST' && !r.path.endsWith('/login')), isEmpty);
  });
}
