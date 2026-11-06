import 'dart:async';

import 'package:corestream_mobile/data/api_client.dart';
import 'package:corestream_mobile/data/api_error.dart';
import 'package:corestream_mobile/data/api_repository.dart';
import 'package:corestream_mobile/models/api_domain_models.dart';
import 'package:corestream_mobile/models/api_models.dart';
import 'package:corestream_mobile/models/models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'api_test_support.dart';

const appId = '00000000-0000-0000-0000-000000000001';
const epicId = '00000000-0000-0000-0000-000000000002';
const ticketId = '00000000-0000-0000-0000-000000000003';
Map<String, Object?> application() => {'id': appId, 'name': 'Proyecto real',
  'is_active': true, 'created_at': '2026-10-12T01:00:00Z',
  'epic_count': 1, 'pending_count': 1, 'delayed_count': 0};
Map<String, Object?> ticket({String id = ticketId, String status = 'TODO',
    String? assignee = userId, String? completed}) => {
  'id': id, 'title': 'Ticket real', 'description': null, 'epic_id': epicId,
  'priority': 'HIGH', 'status': status, 'ticket_type': 'DEVELOPMENT', 'order_index': 0,
  'assignee_id': assignee, 'assignee': assignee == userId ? profile() : null,
  'created_at': '2026-10-12T01:00:00Z', 'completed_at': completed,
  'time_spent_seconds': 12, 'timer_started_at': null, 'subtasks': [],
};
Map<String, Object?> epic(List<Object?> tickets) => {'id': epicId, 'application_id': appId,
  'title': 'Épica real', 'order_index': 0, 'created_at': '2026-10-12T01:00:00Z', 'tickets': tickets};
Map<String, Object?> incident({String status = 'MITIGATED'}) => {
  'id': notificationId, 'title': 'Incidente real', 'description': null,
  'status': status, 'severity': 'P2', 'application_id': null, 'created_by_id': null,
  'assigned_to_id': userId, 'created_at': '2026-10-12T01:00:00Z',
  'updated_at': '2026-10-12T01:00:00Z', 'affected_environment': 'PRODUCTION',
  'mitigation_state': 'Servicio recuperado temporalmente', 'estimated_resolution_time_seconds': 600,
};

void main() {
  Future<ApiRepository> repository(FakeAdapter adapter, {String role = 'DEVELOPER'}) async {
    final client = ApiClient('http://localhost:8001', dio: Dio()..httpClientAdapter = adapter, platform: FakePlatform());
    final repo = ApiRepository(client);
    addTearDown(() { repo.dispose(); client.dispose(); });
    await client.login('developer@example.com', 'password');
    repo.setSession(ApiProfile.fromJson(profile(role: role)).user);
    return repo;
  }

  test('composición completa comparte consultas y no confunde TODO con pendientes', () async {
    final tickets = [ticket(), ticket(id: '00000000-0000-0000-0000-000000000004', status: 'IN_PROGRESS'),
      ticket(id: '00000000-0000-0000-0000-000000000005', status: 'BLOCKED_QUESTION'),
      ticket(id: '00000000-0000-0000-0000-000000000006', status: 'COMPLETED', completed: DateTime.now().toUtc().toIso8601String())];
    final adapter = FakeAdapter((r) => response(switch (r.path) {
      '/api/auth/login' => token(), '/api/applications/' => [application()],
      '/api/epics/by-app/$appId' => [epic(tickets)], '/api/incidents/' => [incident()],
      _ => throw StateError('Ruta inesperada ${r.path}'),
    }));
    final repo = await repository(adapter);
    final projects = await Future.wait([repo.fetchProjects(), repo.fetchProjects()]);
    expect(projects.first.single.pending, 3);
    expect(projects.first.single.progress, .25);
    expect(adapter.requests.where((r) => r.path == '/api/applications/').length, 1);
    final dashboard = await repo.fetchDashboard();
    expect(dashboard.stats, {'mine': 3, 'prog': 1, 'doneWeek': 1, 'incidents': 1});
    expect(repo.projectOfTicket(dashboard.myTickets.first)?.id, appId);
    expect(projects.first.single.project.code, isEmpty);
    expect(adapter.requests.where((r) => r.path == '/api/users/'), isEmpty);
  });

  test('completados sin fecha hacen la métrica semanal no disponible', () async {
    final adapter = FakeAdapter((r) => response(switch (r.path) {
      '/api/auth/login' => token(), '/api/applications/' => [application()],
      '/api/epics/by-app/$appId' => [epic([ticket(status: 'COMPLETED')])], '/api/incidents/' => [],
      _ => throw StateError(r.path),
    }));
    final repo = await repository(adapter);
    expect((await repo.fetchDashboard()).stats['doneWeek'], isNull);
  });

  test('permisos actuales: ADMIN no trabaja; developer no resuelve ni inicia ajeno', () {
    final admin = ApiProfile.fromJson(profile(role: 'ADMIN')).user;
    final developer = ApiProfile.fromJson(profile()).user;
    expect(ApiTicket.fromJson(ticket()).permissions(admin).canStart, false);
    expect(ApiTicket.fromJson(ticket(assignee: null)).permissions(developer).canStart, true);
    expect(ApiTicket.fromJson(ticket(assignee: appId)).permissions(developer).canStart, false);
    expect(ApiTicket.fromJson(ticket(status: 'BLOCKED_QUESTION')).permissions(developer).canResolveQuestion, false);
    expect(ApiTicket.fromJson(ticket(status: 'BLOCKED_QUESTION')).permissions(admin).canResolveQuestion, true);
    expect(ApiTicket.fromJson(ticket(status: 'REDIRECTED')).permissions(developer).canStart, false);
  });

  test('incidente conserva mitigación, P2, nullable; no convierte SUPPORT', () {
    final parsed = apiIncident(incident());
    expect(parsed.status, IncidentStatus.mitigated);
    expect(parsed.severity, IncidentSeverity.p2);
    expect(parsed.projectId, isNull);
    expect(parsed.category, isNull);
    expect(parsed.reporterId, isNull);
    expect(parsed.mitigation, 'Servicio recuperado temporalmente');
    expect(() => apiIncident(incident(status: 'UNDER_REVIEW')), throwsA(isA<ApiError>()));
    expect(() => ApiTicket.fromJson({...ticket(), 'ticket_type': 'SUPPORT'}), throwsA(isA<ApiError>()));
    expect(() => ApiTicket.fromJson({...ticket(), 'status': 'UNKNOWN'}), throwsA(isA<ApiError>()));
  });

  test('cambio de sesión entre consultas impide caché y fan-out del usuario anterior', () async {
    final waiting = Completer<ResponseBody>();
    final started = Completer<void>();
    final adapter = FakeAdapter((r) {
      if (r.path == '/api/auth/login') return response(token());
      if (r.path == '/api/applications/') { started.complete(); return waiting.future; }
      throw StateError('No debe continuar a ${r.path}');
    });
    final repo = await repository(adapter);
    final request = repo.fetchProjects();
    final rejected = expectLater(request, throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.superseded)));
    await started.future;
    repo.setSession(null);
    waiting.complete(response([application()]));
    await rejected;
    expect(repo.userById(userId), isNull);
    expect(repo.projectOfTicket(ApiTicket.fromJson(ticket()).ticket), isNull);
    expect(adapter.requests.where((r) => r.path.startsWith('/api/epics')), isEmpty);
  });

  test('duplicado en mutation se bloquea y errores 403 preservan usuario', () async {
    final waiting = Completer<ResponseBody>();
    final adapter = FakeAdapter((r) {
      if (r.path == '/api/auth/login') return response(token());
      return waiting.future;
    });
    final repo = await repository(adapter);
    final operation = repo.startTicket(ticketId);
    final rejected = expectLater(operation, throwsA(isA<ApiError>().having((e) => e.status, 'status', 403)));
    await expectLater(repo.startTicket(ticketId), throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.operation)));
    waiting.complete(response({'detail': 'Ticket ajeno'}, 403));
    await rejected;
    expect(repo.userById(userId)?.id, userId);
    expect(adapter.requests.where((r) => r.path.endsWith('/start')).length, 1);
  });

  test('timeout de mutación no repite POST y reconsulta el estado persistido', () async {
    var completed = false;
    final adapter = FakeAdapter((r) {
      if (r.path.endsWith('/complete')) {
        completed = true;
        throw DioException(requestOptions: r, type: DioExceptionType.receiveTimeout);
      }
      return response(switch (r.path) {
        '/api/auth/login' => token(), '/api/applications/' => [application()],
        '/api/epics/by-app/$appId' => [epic([ticket(status: completed ? 'COMPLETED' : 'IN_PROGRESS',
          completed: completed ? DateTime.now().toUtc().toIso8601String() : null)])],
        _ => throw StateError(r.path),
      });
    });
    final repo = await repository(adapter);
    expect((await repo.fetchBoard(appId)).epics.single.tickets.single.status, TicketStatus.inProgress);
    await expectLater(repo.completeTicket(ticketId, ''),
        throwsA(isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.network)));
    expect((await repo.fetchBoard(appId)).epics.single.tickets.single.status, TicketStatus.done);
    expect(adapter.requests.where((r) => r.path.endsWith('/complete')).length, 1);
    expect(adapter.requests.where((r) => r.path == '/api/applications/').length, 2);
    expect(repo.userById(userId)?.id, userId);
  });

  test('historial paginado ordena cronológicamente y verifica ticket propietario', () async {
    final adapter = FakeAdapter((r) => response(switch (r.path) {
      '/api/auth/login' => token(), '/api/applications/' => [application()],
      '/api/epics/by-app/$appId' => [epic([ticket()])], '/api/tickets/$ticketId' => ticket(),
      '/api/tickets/$ticketId/events' => [
        {'id': appId, 'ticket_id': ticketId, 'event_type': 'QUESTION_RAISED',
          'user_id': userId, 'created_at': '2026-10-12T02:00:00Z', 'user': profile(), 'detail': {'question': 'Pregunta registrada'}},
        {'id': epicId, 'ticket_id': ticketId, 'event_type': 'CREATED',
          'user_id': null, 'created_at': '2026-10-12T01:00:00Z', 'detail': null},
      ],
      _ => throw StateError(r.path),
    }));
    final repo = await repository(adapter);
    final detail = await repo.fetchTicketDetail(ticketId);
    expect(detail.ticket.number, 0);
    expect(detail.ticket.events.map((e) => e.type), ['CREATED', 'QUESTION']);
    expect(detail.ticket.events.last.text, 'Pregunta registrada');
    expect(detail.ticket.events.first.userId, isNull);
  });

  test('developer obtiene destinos desde team-members y nunca directorio restringido', () async {
    final adapter = FakeAdapter((r) => response(switch (r.path) {
      '/api/auth/login' => token(), '/api/tickets/team-members' => [
        {'id': appId, 'email': 'leader@example.com', 'full_name': 'Líder real', 'role': 'TEAM_LEADER',
          'specialty': 'Backend · Líder equipo Pagos', 'avatar_color': '#8B7CF6'},
      ], _ => throw StateError(r.path),
    }));
    final repo = await repository(adapter);
    expect((await repo.fetchUsers()).single.role, UserRole.groupLeader);
    expect(repo.userById(appId)?.fullName, 'Líder real');
    expect(repo.userById(appId)?.specialty, 'Backend · Líder equipo Pagos');
    expect(repo.userById(appId)?.avatarColor, const Color(0xFF8B7CF6));
    expect(adapter.requests.where((r) => r.path == '/api/users/'), isEmpty);
  });

  test('metadata conserva identidad entre directorio, tablero, responsable e historial', () async {
    final person = {...profile(), 'specialty': 'Frontend · Vue / TypeScript',
      'preferences': {'avatar_color': '#2FBF71', 'other_setting': true}};
    final app = {...application(), 'color': '#8B7CF6', 'icon': 'AL'};
    final assigned = {...ticket(), 'assignee': person};
    final adapter = FakeAdapter((r) => response(switch (r.path) {
      '/api/auth/login' => token(), '/api/applications/' => [app],
      '/api/users/' => [person], '/api/epics/by-app/$appId' => [epic([assigned])],
      '/api/tickets/$ticketId' => assigned, '/api/tickets/$ticketId/events' => [
        {'id': epicId, 'ticket_id': ticketId, 'event_type': 'CREATED', 'user_id': userId,
          'created_at': '2026-10-12T01:00:00Z', 'user': person, 'detail': null},
      ], _ => throw StateError(r.path),
    }));
    final repo = await repository(adapter, role: 'ADMIN');
    final directory = (await repo.fetchUsers()).single;
    final project = (await repo.fetchProjects()).single.project;
    final board = await repo.fetchBoard(appId);
    final detail = await repo.fetchTicketDetail(ticketId);
    expect(project.id, appId);
    expect(project.code, 'AL');
    expect(project.color, const Color(0xFF8B7CF6));
    expect(board.project, same(project));
    expect(detail.project, same(project));
    for (final user in [directory, detail.assignee!, repo.userById(detail.ticket.events.single.userId)!]) {
      expect(user.id, userId);
      expect(user.specialty, 'Frontend · Vue / TypeScript');
      expect(user.avatarColor, const Color(0xFF2FBF71));
    }
  });

  test('metadata opcional ausente o inválida mantiene recursos y decoración de respaldo', () {
    for (final value in [null, '', '#123', '#12345678', '#123456\n', 'PC\n', 'https://example.com/color', 123]) {
      final user = ApiProfile.fromJson({...profile(), 'preferences': {'avatar_color': value}}).user;
      final member = apiTeamMember({...profile(), 'avatar_color': value});
      final project = apiProject(ApiApplication.fromJson({...application(), 'color': value, 'icon': value}));
      expect(user.avatarColor, const Color(0xFF4C8DFF));
      expect(member.avatarColor, user.avatarColor);
      expect(project.color, user.avatarColor);
      expect(project.code, isEmpty);
      expect(project.id, appId);
    }
    expect(ApiProfile.fromJson(profile()).user.avatarColor, const Color(0xFF4C8DFF));
    expect(apiTeamMember(profile()).specialty, isNull);
    expect(apiColor('#aabbcc'), const Color(0xFFAABBCC));
    expect(apiProject(ApiApplication.fromJson({...application(), 'icon': 'folder'})).code, isEmpty);
  });
}
