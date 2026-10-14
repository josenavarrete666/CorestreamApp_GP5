import 'dart:async';

import '../models/api_models.dart';
import '../models/api_domain_models.dart';
import '../models/models.dart';
import 'api_client.dart';
import 'api_error.dart';
import 'repository.dart';

abstract class ApiResources {
  Future<List<ApiApplication>> applications();
  Future<List<ApiNotification>> notifications();
  Future<int> unreadCount();
  Future<void> markNotificationRead(String id);
  Future<void> markAllNotificationsRead();
  Stream<int> get changes;
}

class ApiRepository implements CoreStreamRepository, ApiResources {
  ApiRepository(this.client);
  final ApiClient client;
  final _changes = StreamController<int>.broadcast();
  final _push = StreamController<AppNotification>.broadcast();
  int _revision = 0;
  User? _user;
  int _session = 0;
  Future<_Snapshot>? _snapshotFuture;
  _Snapshot? _snapshot;
  Future<List<User>>? _usersFuture;
  final _users = <String, User>{};
  final _mutations = <String>{};

  @override
  void setSession(User? user) {
    _session++;
    _user = user;
    _snapshotFuture = null;
    _snapshot = null;
    _usersFuture = null;
    _users.clear();
    _mutations.clear();
    if (user != null) _users[user.id] = user;
    invalidate();
  }

  User get _current => _user ?? (throw const ApiError(ApiErrorKind.session, 'Inicia sesión para continuar.'));

  void _check(int session, int clientGeneration) {
    if (session != _session || clientGeneration != client.sessionGeneration || _changes.isClosed) {
      throw const ApiError(ApiErrorKind.superseded, 'La sesión cambió.');
    }
  }

  void invalidate() {
    _snapshotFuture = null;
    _snapshot = null;
    _usersFuture = null;
    if (!_changes.isClosed) _changes.add(++_revision);
  }
  void receiveNotification(String userId, Map<String, dynamic> payload) {
    if (_user?.id != userId) return;
    final notification = ApiNotification.fromJson({'user_id': userId, ...payload});
    if (notification.userId != userId) invalid('user_id');
    if (!_push.isClosed) _push.add(notification.display);
  }

  Future<List<T>> _pages<T>(String path, int limit, T Function(Object?) parse, String Function(T) id) async {
    final session = _session;
    final generation = client.sessionGeneration;
    final values = <String, T>{};
    for (var skip = 0; ; skip += limit) {
      _check(session, generation);
      final response = await client.request(path, query: {'skip': skip, 'limit': limit});
      _check(session, generation);
      if (response is! List) invalid('lista $path');
      final previousLength = values.length;
      for (final raw in response) {
        final item = parse(raw);
        values[id(item)] = item;
      }
      if (response.length < limit) break;
      if (values.length == previousLength) invalid('paginación sin avance');
    }
    return values.values.toList();
  }

  @override
  Future<List<ApiApplication>> applications() => _pages('/api/applications/', 100, ApiApplication.fromJson, (a) => a.id);
  @override
  Future<List<ApiNotification>> notifications() => _pages('/api/notifications/', 50, ApiNotification.fromJson, (n) => n.id);
  @override
  Future<List<AppNotification>> fetchNotifications() async => (await notifications()).map((n) => n.display).toList();
  @override
  Future<int> unreadCount() async {
    final json = jsonObject(await client.request('/api/notifications/unread-count'));
    final owner = uuid(json, 'user_id');
    if (_user != null && owner != _user!.id) invalid('unread_count.user_id');
    return count(json, 'unread_count');
  }
  @override
  Future<void> markNotificationRead(String id) async {
    final session = _session, generation = client.sessionGeneration;
    final result = jsonObject(await client.request('/api/notifications/mark-read', method: 'POST', body: {'notification_ids': [id]}));
    _check(session, generation);
    if (count(result, 'total_requested') != 1 || count(result, 'marked_as_read') != 1) {
      throw const ApiError(ApiErrorKind.permission, 'La notificación no pudo marcarse como leída.');
    }
    invalidate();
  }
  @override
  Future<void> markAllNotificationsRead() async {
    final session = _session, generation = client.sessionGeneration;
    count(jsonObject(await client.request('/api/notifications/mark-all-read', method: 'POST')), 'marked_as_read');
    _check(session, generation);
    invalidate();
  }
  @override
  Stream<int> get changes => _changes.stream;
  @override
  Stream<AppNotification> get incomingPush => _push.stream;
  Never _unavailable() => throw const ApiError(ApiErrorKind.operation, 'Esta capacidad requiere su contrato de integración.');
  @override
  Future<List<User>> loginOptions() async => _unavailable();
  @override
  Future<User> login(User user) async => _unavailable();
  @override
  Future<void> logout() async { setSession(null); await client.logout(); }

  Future<_Snapshot> _data() {
    _current;
    return _snapshotFuture ??= _load(_session, client.sessionGeneration, _revision);
  }

  Future<_Snapshot> _load(int session, int generation, int revision) async {
    try {
      final apps = await applications();
      _check(session, generation);
      final boards = <String, Board>{};
      final tickets = <String, ApiTicket>{};
      final epics = <String, Epic>{};
      final users = <String, User>{};
      for (final app in apps) {
        _check(session, generation);
        final raw = await client.request('/api/epics/by-app/${app.id}');
        _check(session, generation);
        final items = <String, ApiEpic>{};
        for (final value in jsonList(raw)) {
          final epic = ApiEpic.fromJson(value);
          if (epic.epic.projectId != app.id) invalid('epic.application_id');
          items[epic.epic.id] = epic;
        }
        final ordered = items.values.toList()..sort((a, b) {
          final order = a.epic.orderIndex.compareTo(b.epic.orderIndex);
          return order != 0 ? order : a.epic.id.compareTo(b.epic.id);
        });
        boards[app.id] = Board(project: apiProject(app), epics: [
          for (final item in ordered) EpicBoard(epic: item.epic, tickets: item.tickets.map((t) => t.ticket).toList()),
        ]);
        for (final item in ordered) {
          epics[item.epic.id] = item.epic;
          for (final ticket in item.tickets) {
            if (tickets.containsKey(ticket.ticket.id)) invalid('ticket duplicado entre épicas');
            tickets[ticket.ticket.id] = ticket;
            if (ticket.assignee != null) users[ticket.assignee!.id] = ticket.assignee!;
          }
        }
      }
      _check(session, generation);
      if (revision != _revision) throw const ApiError(ApiErrorKind.superseded, 'Los datos cambiaron; vuelve a consultar.');
      final result = _Snapshot(boards, epics, tickets);
      _snapshot = result;
      _users.addAll(users);
      return result;
    } catch (_) {
      if (session == _session && revision == _revision) _snapshotFuture = null;
      rethrow;
    }
  }

  List<ProjectSummary> _summaries(_Snapshot data) => data.boards.values.map((b) {
    final tickets = b.epics.expand((e) => e.tickets).toList();
    return ProjectSummary(project: b.project, epicsCount: b.epics.length,
        ticketsTotal: tickets.length, ticketsDone: tickets.where((t) => t.status == TicketStatus.done).length,
        overdue: tickets.where((t) => t.isOverdue).length);
  }).toList();

  int? _doneWeek(Iterable<Ticket> tickets) {
    final done = tickets.where((t) => t.status == TicketStatus.done).toList();
    if (done.any((t) => t.completedAt == null)) return null;
    final now = DateTime.now().toUtc();
    final since = now.subtract(const Duration(days: 7));
    return done.where((t) => !t.completedAt!.isBefore(since) && !t.completedAt!.isAfter(now)).length;
  }

  @override
  Future<Dashboard> fetchDashboard() async {
    final me = _current;
    final session = _session, generation = client.sessionGeneration;
    final data = await _data();
    final incidents = await fetchIncidents();
    _check(session, generation);
    final tickets = data.tickets.values.map((t) => t.ticket).toList();
    final open = tickets.where((t) => t.status != TicketStatus.done).toList();
    if (me.isLead) {
      final attention = <AttentionItem>[
        for (final t in open.where((t) => t.status == TicketStatus.blocked || t.isOverdue))
          AttentionItem.ticket(t, data.boards[data.epics[t.epicId]?.projectId]?.project.name ?? ''),
        for (final i in incidents.where((i) => i.isOpen && {IncidentSeverity.p1, IncidentSeverity.p2}.contains(i.severity)))
          AttentionItem.incident(i, data.boards[i.projectId]?.project.name ?? ''),
      ];
      return Dashboard(role: me.role, projects: _summaries(data), attention: attention,
          stats: {'apps': data.boards.length, 'open': open.length,
            'blocked': open.where((t) => t.status == TicketStatus.blocked).length,
            'late': open.where((t) => t.isOverdue).length});
    }
    final mine = open.where((t) => t.assigneeId == me.id).toList()..sort((a, b) =>
        (a.dueDate ?? DateTime.utc(9999)).compareTo(b.dueDate ?? DateTime.utc(9999)));
    final myIncidents = incidents.where((i) => i.isOpen && i.assigneeId == me.id).toList();
    return Dashboard(role: me.role, myTickets: mine, myIncidents: myIncidents,
        stats: {'mine': mine.length, 'prog': mine.where((t) => t.status == TicketStatus.inProgress).length,
          'doneWeek': _doneWeek(tickets.where((t) => t.assigneeId == me.id)), 'incidents': myIncidents.length});
  }
  @override
  Future<List<ProjectSummary>> fetchProjects() async => _summaries(await _data());
  @override
  Future<Board> fetchBoard(String projectId) async => (await _data()).boards[projectId] ??
      (throw const ApiError(ApiErrorKind.operation, 'Proyecto no disponible.', status: 404));
  @override
  Future<TicketDetail> fetchTicketDetail(String ticketId) async {
    final me = _current;
    final session = _session, generation = client.sessionGeneration;
    final item = ApiTicket.fromJson(await client.request('/api/tickets/$ticketId'));
    if (item.ticket.id != ticketId) invalid('ticket.id');
    _check(session, generation);
    final data = await _data();
    _check(session, generation);
    final epic = data.epics[item.ticket.epicId];
    final board = data.boards[epic?.projectId];
    if (epic == null || board == null) throw const ApiError(ApiErrorKind.operation, 'Contexto del ticket no disponible.');
    final events = await _pages('/api/tickets/$ticketId/events', 100, ApiTicketEvent.fromJson, (e) => e.id);
    _check(session, generation);
    events.sort((a, b) => a.event.ts.compareTo(b.event.ts));
    for (final event in events) {
      if (event.ticketId != ticketId) invalid('event.ticket_id');
      item.ticket.events.add(event.event);
      if (event.user != null) _users[event.user!.id] = event.user!;
    }
    if (item.assignee != null) _users[item.assignee!.id] = item.assignee!;
    return TicketDetail(ticket: item.ticket, epic: epic, project: board.project,
        permissions: item.permissions(me), assignee: item.assignee,
        createdBy: userById(item.ticket.createdById));
  }

  Future<bool> isDevelopmentTicket(String ticketId) async {
    _current;
    final session = _session, generation = client.sessionGeneration;
    final json = jsonObject(await client.request('/api/tickets/$ticketId'));
    _check(session, generation);
    if (uuid(json, 'id') != ticketId) invalid('ticket.id');
    return switch (text(json, 'ticket_type')) {
      'DEVELOPMENT' => true, 'SUPPORT' => false, _ => invalid('ticket_type'),
    };
  }
  @override
  Future<List<Incident>> fetchIncidents() async {
    _current;
    return _pages('/api/incidents/', 100, apiIncident, (i) => i.id);
  }
  @override
  Future<Incident> fetchIncident(String incidentId) async {
    _current;
    final session = _session, generation = client.sessionGeneration;
    final incident = apiIncident(await client.request('/api/incidents/$incidentId'));
    if (incident.id != incidentId) invalid('incident.id');
    _check(session, generation);
    await fetchUsers();
    _check(session, generation);
    return incident;
  }
  @override
  Future<List<MemberLoad>> fetchTeamWorkload() async {
    if (!_current.isLead) throw const ApiError(ApiErrorKind.permission, 'Carga del equipo disponible para gestores.', status: 403);
    final session = _session, generation = client.sessionGeneration;
    final users = await fetchUsers();
    final data = await _data();
    _check(session, generation);
    final incidents = await fetchIncidents();
    _check(session, generation);
    return users.where((u) => u.role != UserRole.admin).map((u) {
      final tickets = data.tickets.values.map((t) => t.ticket).where((t) => t.assigneeId == u.id).toList();
      return MemberLoad(user: u, activeTickets: tickets.where((t) => t.status != TicketStatus.done).length,
          inProgress: tickets.where((t) => t.status == TicketStatus.inProgress).length,
          blocked: tickets.where((t) => t.status == TicketStatus.blocked).length,
          doneLast7d: _doneWeek(tickets), openIncidents: incidents.where((i) => i.assigneeId == u.id && i.isOpen).length);
    }).toList();
  }
  @override
  Future<List<User>> fetchUsers() => _usersFuture ??= _loadUsers(_current, _session, client.sessionGeneration, _revision);

  Future<List<User>> _loadUsers(User me, int session, int generation, int revision) async {
    try {
      final users = me.isLead
          ? await _pages('/api/users/', 100, (v) => ApiProfile.fromJson(v).user, (u) => u.id)
          : jsonList(await client.request('/api/tickets/team-members')).map(apiTeamMember).toList();
      _check(session, generation);
      _users.addAll({for (final u in users) u.id: u});
      return users;
    } catch (_) {
      if (session == _session && revision == _revision) _usersFuture = null;
      rethrow;
    }
  }
  @override
  User? userById(String? id) => _users[id];
  @override
  Project? projectOfTicket(Ticket t) => _snapshot?.boards[_snapshot?.epics[t.epicId]?.projectId]?.project;

  Future<void> _mutate(String resource, String path, {String method = 'POST', Object? body,
      required void Function(Object?) validate}) async {
    _current;
    final session = _session, generation = client.sessionGeneration;
    if (!_mutations.add(resource)) throw const ApiError(ApiErrorKind.operation, 'La operación ya está en curso.');
    try {
      final result = await client.request(path, method: method, body: body);
      _check(session, generation);
      validate(result);
    } finally {
      if (session == _session) {
        _mutations.remove(resource);
        invalidate();
      }
    }
  }

  Future<void> _ticketAction(String id, String suffix, {String method = 'POST', Object? body,
      String? expectedStatus}) => _mutate('ticket:$id', '/api/tickets/$id$suffix', method: method,
      body: body, validate: (raw) {
        final ticket = ApiTicket.fromJson(raw).ticket;
        if (ticket.id != id || (expectedStatus != null && ticket.apiStatus != expectedStatus)) invalid('resultado ticket');
      });
  @override
  Future<void> assignTicket(String ticketId, String assigneeId, {String? comment}) async {
    if (comment != null && comment.trim().isNotEmpty) _unavailable();
    await _mutate('ticket:$ticketId', '/api/tickets/$ticketId', method: 'PUT', body: {'assignee_id': assigneeId},
        validate: (raw) {
          final ticket = ApiTicket.fromJson(raw).ticket;
          if (ticket.id != ticketId || ticket.assigneeId != assigneeId) invalid('resultado asignación');
        });
  }
  @override
  Future<void> startTicket(String ticketId) => _ticketAction(ticketId, '/start', expectedStatus: 'IN_PROGRESS');
  @override
  Future<void> completeTicket(String ticketId, String prLink) => _ticketAction(ticketId, '/complete',
      body: {'pr_link': prLink.trim().isEmpty ? null : prLink.trim()}, expectedStatus: 'COMPLETED');
  @override
  Future<void> raiseQuestion(String ticketId, String question) => _ticketAction(ticketId, '/question',
      body: {'question_text': question.trim()}, expectedStatus: 'BLOCKED_QUESTION');
  @override
  Future<void> resolveQuestion(String ticketId, String resolution) => _ticketAction(ticketId, '/resolve-question',
      body: {'resolution': resolution.trim()}, expectedStatus: 'IN_PROGRESS');
  @override
  Future<void> redirectTicket(String ticketId, String toUserId, String reason) =>
      _mutate('ticket:$ticketId', '/api/tickets/$ticketId/redirect',
          body: {'to_user_id': toUserId, 'justification': reason.trim()}, validate: (raw) {
            final json = jsonObject(raw);
            if (uuid(json, 'ticket_id') != ticketId || uuid(json, 'to_user_id') != toUserId) invalid('resultado redirección');
            uuid(json, 'from_user_id');
            apiTicketStatus(text(json, 'new_status'));
            date(json, 'redirected_at');
          });
  @override
  Future<void> toggleSubtask(String ticketId, String subtaskId, bool done) =>
      _mutate('ticket:$ticketId', '/api/tickets/$ticketId/subtasks/$subtaskId', method: 'PUT',
          body: {'is_completed': done}, validate: (raw) {
            final subtask = apiSubtask(raw);
            if (subtask.id != subtaskId || subtask.done != done) invalid('resultado subtarea');
          });
  @override
  Future<void> createTicket({required String epicId, required String title, required TicketPriority priority, String? assigneeId}) =>
      _mutate('create:$epicId', '/api/tickets/', body: {'epic_id': epicId, 'title': title.trim(),
        'priority': priority.wire, 'assignee_id': assigneeId}, validate: (raw) {
          final ticket = ApiTicket.fromJson(raw).ticket;
          if (ticket.epicId != epicId || ticket.title != title.trim() || ticket.priority != priority ||
              ticket.assigneeId != assigneeId || ticket.apiStatus != 'TODO') {
            invalid('resultado creación');
          }
        });
  @override
  Future<void> takeIncident(String incidentId) async => throw const ApiError(ApiErrorKind.operation,
      'El backend actual no ofrece autoasignación de incidentes. Solicita asignación a un gestor.');
  @override
  Future<void> assignIncident(String incidentId, String assigneeId) =>
      _mutate('incident:$incidentId', '/api/incidents/$incidentId', method: 'PATCH',
          body: {'assigned_to_id': assigneeId}, validate: (raw) {
            final incident = apiIncident(raw);
            if (incident.id != incidentId || incident.assigneeId != assigneeId) invalid('resultado asignación incidente');
          });
  @override
  Future<void> setIncidentStatus(String incidentId, IncidentStatus status) async {
    if (!apiIncidentStatuses.contains(status)) {
      _unavailable();
    }
    await _mutate('incident:$incidentId', '/api/incidents/$incidentId/status', method: 'PATCH',
        body: {'status': status.wire}, validate: (raw) {
          final incident = apiIncident(raw);
          if (incident.id != incidentId || incident.status != status) invalid('resultado estado incidente');
        });
  }
  @override
  Future<void> registerDevice(String fcmToken, String platform) async => _unavailable();
  @override
  void dispose() { setSession(null); _changes.close(); _push.close(); }
}

class _Snapshot {
  const _Snapshot(this.boards, this.epics, this.tickets);
  final Map<String, Board> boards;
  final Map<String, Epic> epics;
  final Map<String, ApiTicket> tickets;
}
