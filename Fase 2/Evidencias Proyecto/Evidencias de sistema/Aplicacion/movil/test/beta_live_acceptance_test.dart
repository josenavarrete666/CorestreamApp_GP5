import 'dart:convert';
import 'dart:io';

import 'package:corestream_mobile/data/api_client.dart';
import 'package:corestream_mobile/data/api_error.dart';
import 'package:corestream_mobile/data/api_repository.dart';
import 'package:corestream_mobile/models/models.dart';
import 'package:corestream_mobile/services/api_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

void main() {
  final path = Platform.environment['CS_BETA_FIXTURE'];
  test('beta real: tres roles, composición, ciclos persistentes y permisos', () async {
    final file = File(path!);
    final fixture = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (fixture['purpose'] != 'beta-development') throw StateError('Development fixture required');
    final ids = Map<String, dynamic>.from(fixture['ids'] as Map);
    final extra = Map<String, dynamic>.from(fixture['beta_ids'] as Map);
    final clients = <String, ApiClient>{};
    final repos = <String, ApiRepository>{};
    addTearDown(() { for (final repo in repos.values) { repo.dispose(); } for (final client in clients.values) { client.dispose(); } });
    for (final role in ['admin', 'leader', 'developer']) {
      final client = ApiClient('http://localhost:8001');
      clients[role] = client;
      final credentials = fixture['users'][role] as Map;
      final profile = await ApiAuthService(client).login(credentials['email'] as String, credentials['password'] as String);
      expect(profile.mustChangePassword, false);
      final repo = ApiRepository(client)..setSession(profile.user);
      repos[role] = repo;
      final dashboard = await repo.fetchDashboard();
      expect(dashboard.role, switch (role) { 'admin' => UserRole.admin, 'leader' => UserRole.groupLeader, _ => UserRole.developer });
      final project = (await repo.fetchProjects()).singleWhere((p) => p.project.id == ids['application']);
      expect(project.ticketsTotal, 5);
      expect(project.pending, 4);
      expect(project.ticketsDone, 1);
      expect(project.progress, .2);
      expect((await repo.fetchBoard(ids['application'] as String)).epics.length, 2);
      final detail = await repo.fetchTicketDetail(ids['ticket'] as String);
      expect(detail.ticket.subtasks.length, 2);
      expect(detail.assignee?.id, ids['developer']);
      expect((await repo.fetchIncidents()).where((i) => i.projectId == ids['application']).length, 4);
      expect((await repo.fetchIncident(extra['mitigated'] as String)).status, IncidentStatus.mitigated);
      if (role != 'developer') {
        final team = await repo.fetchTeamWorkload();
        final developer = team.singleWhere((m) => m.user.id == ids['developer']);
        expect(developer.activeTickets, 2);
        expect(developer.inProgress, 1);
        expect(developer.openIncidents, 2);
      }
      expect(await repo.isDevelopmentTicket(extra['support'] as String), false);
      debugPrint('READ $role: project=${project.project.id}, tickets=5, pending=4, done=1, incidents=4');
    }
    final admin = repos['admin']!, leader = repos['leader']!, developer = repos['developer']!;
    final mainTicket = ids['ticket'] as String;
    await expectLater(admin.startTicket(mainTicket), throwsA(isA<ApiError>().having((e) => e.status, 'HTTP', 403)));
    await expectLater(developer.startTicket(extra['blocked'] as String), throwsA(isA<ApiError>().having((e) => e.status, 'HTTP', 403)));
    await expectLater(developer.resolveQuestion(extra['blocked'] as String, 'Respuesta no autorizada'),
        throwsA(isA<ApiError>().having((e) => e.status, 'HTTP', 403)));
    await developer.startTicket(mainTicket);
    final started = await developer.fetchTicketDetail(mainTicket);
    expect(started.ticket.status, TicketStatus.inProgress);
    expect(started.ticket.runningSince, isNotNull);
    await developer.toggleSubtask(mainTicket, extra['subtask'] as String, true);
    expect((await developer.fetchTicketDetail(mainTicket)).ticket.subtasks.where((s) => s.done).length, 1);
    await developer.raiseQuestion(mainTicket, '¿Cuál es el criterio de aceptación para este flujo?');
    final blocked = await developer.fetchTicketDetail(mainTicket);
    expect(blocked.ticket.status, TicketStatus.blocked);
    expect(blocked.ticket.runningSince, isNull);
    expect(blocked.ticket.blockReason, isNotEmpty);
    await leader.resolveQuestion(mainTicket, 'Verificar persistencia y permisos de los tres roles.');
    final resumed = await developer.fetchTicketDetail(mainTicket);
    expect(resumed.ticket.status, TicketStatus.inProgress);
    expect(resumed.ticket.assigneeId, ids['developer']);
    expect(resumed.ticket.runningSince, isNotNull);
    await developer.completeTicket(mainTicket, '');
    final completed = await developer.fetchTicketDetail(mainTicket);
    expect(completed.ticket.status, TicketStatus.done);
    expect(completed.ticket.completedAt, isNotNull);
    expect(completed.ticket.runningSince, isNull);
    expect(completed.ticket.events.where((e) => e.type == 'QUESTION'), isNotEmpty);
    debugPrint('CYCLE ticket=$mainTicket: TODO→IN_PROGRESS→BLOCKED_QUESTION→IN_PROGRESS→COMPLETED');
    await developer.redirectTicket(extra['progress'] as String, ids['other'] as String, 'Traspaso justificado durante aceptación real.');
    final redirected = await developer.fetchTicketDetail(extra['progress'] as String);
    expect(redirected.ticket.status, TicketStatus.todo);
    expect(redirected.ticket.assigneeId, ids['other']);
    expect(redirected.ticket.runningSince, isNull);
    final title = 'Ticket creado aceptación ${fixture['run_id']}';
    await admin.createTicket(epicId: ids['epic'] as String, title: title, priority: TicketPriority.high);
    final created = (await admin.fetchBoard(ids['application'] as String)).epics.expand((e) => e.tickets).singleWhere((t) => t.title == title);
    (fixture['tracked_tickets'] as List).add(created.id);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(fixture));
    await leader.assignTicket(created.id, ids['developer'] as String);
    expect((await leader.fetchTicketDetail(created.id)).ticket.assigneeId, ids['developer']);
    await admin.assignIncident(extra['reported'] as String, ids['developer'] as String);
    expect((await admin.fetchIncident(extra['reported'] as String)).status, IncidentStatus.reported);
    await developer.setIncidentStatus(extra['reported'] as String, IncidentStatus.investigating);
    expect((await developer.fetchIncident(extra['reported'] as String)).status, IncidentStatus.investigating);
    final notifications = await developer.notifications();
    if (notifications.any((n) => !n.read)) {
      await developer.markNotificationRead(notifications.firstWhere((n) => !n.read).id);
    }
    await developer.markAllNotificationsRead();
    expect(await developer.unreadCount(), 0);
    for (final client in clients.values) { await client.logout(); }
    final login = await ApiAuthService(clients['developer']!).login(fixture['users']['developer']['email'] as String,
        fixture['users']['developer']['password'] as String);
    developer.setSession(login.user);
    expect((await developer.fetchTicketDetail(mainTicket)).ticket.status, TicketStatus.done);
    expect(await developer.unreadCount(), 0);
    await clients['developer']!.logout();
    debugPrint('PERSISTENCE: completed=$mainTicket, redirected=${extra['progress']}, created=${created.id}, incident=${extra['reported']}, unread=0; relogin verified');
  }, skip: path == null ? 'Set CS_BETA_FIXTURE to a fresh protected development manifest.' : false,
      timeout: const Timeout(Duration(minutes: 4)));
}
