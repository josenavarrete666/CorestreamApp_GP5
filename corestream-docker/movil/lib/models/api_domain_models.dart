import 'api_models.dart';
import 'models.dart';

String? optionalText(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : json[key] is String ? json[key] as String : invalid(key);
String? optionalUuid(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : uuid(json, key);
DateTime? optionalDate(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : date(json, key);
List<dynamic> jsonList(Object? value) => value is List ? value : invalid('lista JSON');

UserRole apiRole(String value) => switch (value) {
  'ADMIN' => UserRole.admin,
  'TEAM_LEADER' => UserRole.groupLeader,
  'DEVELOPER' => UserRole.developer,
  _ => invalid('role'),
};

User apiTeamMember(Object? value) {
  final json = jsonObject(value);
  text(json, 'email');
  return User(id: uuid(json, 'id'), fullName: text(json, 'full_name'),
      role: apiRole(text(json, 'role')), specialty: optionalText(json, 'specialty'),
      avatarColor: apiColor(json['avatar_color']));
}

Project apiProject(ApiApplication app) => Project(
    id: app.id, name: app.name, code: app.monogram, color: app.color);

TicketStatus apiTicketStatus(String value) => switch (value) {
  'TODO' => TicketStatus.todo,
  'IN_PROGRESS' => TicketStatus.inProgress,
  'BLOCKED' || 'BLOCKED_QUESTION' => TicketStatus.blocked,
  'REDIRECTED' => TicketStatus.redirected,
  'COMPLETED' => TicketStatus.done,
  _ => invalid('ticket.status'),
};

class ApiTicket {
  ApiTicket.fromJson(Object? value) {
    final json = jsonObject(value);
    if (text(json, 'ticket_type') != 'DEVELOPMENT') invalid('ticket_type: se requiere DEVELOPMENT');
    orderIndex = count(json, 'order_index');
    date(json, 'created_at');
    final status = text(json, 'status');
    final priority = switch (text(json, 'priority')) {
      'LOW' => TicketPriority.low, 'MEDIUM' => TicketPriority.medium,
      'HIGH' => TicketPriority.high, 'URGENT' => TicketPriority.urgent,
      _ => invalid('ticket.priority'),
    };
    assignee = json['assignee'] == null ? null : ApiProfile.fromJson(json['assignee']).user;
    ticket = Ticket(id: uuid(json, 'id'), number: 0, epicId: uuid(json, 'epic_id'),
        title: text(json, 'title'), description: optionalText(json, 'description') ?? '',
        status: apiTicketStatus(status), apiStatus: status, priority: priority,
        assigneeId: optionalUuid(json, 'assignee_id'), createdById: optionalUuid(json, 'created_by_id'),
        dueDate: optionalDate(json, 'due_date'), completedAt: optionalDate(json, 'completed_at'),
        spentSeconds: count(json, 'time_spent_seconds'),
        runningSince: optionalDate(json, 'timer_started_at'), prLink: optionalText(json, 'pr_link'),
        blockReason: optionalText(json, 'block_reason') ?? optionalText(json, 'blocked_question'),
        subtasks: jsonList(json['subtasks']).map(apiSubtask).toList());
    if (assignee != null && assignee!.id != ticket.assigneeId) invalid('assignee.id');
  }
  late final Ticket ticket;
  late final User? assignee;
  late final int orderIndex;

  TicketPermissions permissions(User user) {
    final manager = user.isLead;
    final mine = ticket.assigneeId == user.id;
    final worker = user.role != UserRole.admin;
    return TicketPermissions(
        canAssign: manager,
        canStart: worker && (mine || ticket.assigneeId == null) && ticket.apiStatus == 'TODO',
        canComplete: worker && mine && ticket.apiStatus == 'IN_PROGRESS',
        canQuestion: worker && mine && ticket.apiStatus == 'IN_PROGRESS',
        canResolveQuestion: manager && ticket.status == TicketStatus.blocked,
        canRedirect: manager || mine,
        canEditSubtasks: manager || mine,
        canEdit: manager || mine,
        canDelete: user.role == UserRole.admin);
  }
}

Subtask apiSubtask(Object? value) {
  final json = jsonObject(value);
  count(json, 'order_index');
  optionalDate(json, 'completed_at');
  return Subtask(id: uuid(json, 'id'), title: text(json, 'title'), done: boolean(json, 'is_completed'));
}

class ApiEpic {
  ApiEpic.fromJson(Object? value) {
    final json = jsonObject(value);
    date(json, 'created_at');
    epic = Epic(id: uuid(json, 'id'), projectId: uuid(json, 'application_id'),
        name: text(json, 'title'), orderIndex: count(json, 'order_index'));
    final unique = <String, ApiTicket>{};
    for (final raw in jsonList(json['tickets'])) {
      final item = jsonObject(raw);
      final type = text(item, 'ticket_type');
      if (type == 'SUPPORT') continue;
      final ticket = ApiTicket.fromJson(item);
      if (ticket.ticket.epicId != epic.id) invalid('ticket.epic_id');
      unique[ticket.ticket.id] = ticket;
    }
    tickets = unique.values.toList()..sort((a, b) {
      final order = a.orderIndex.compareTo(b.orderIndex);
      return order != 0 ? order : a.ticket.id.compareTo(b.ticket.id);
    });
  }
  late final Epic epic;
  late final List<ApiTicket> tickets;
}

class ApiTicketEvent {
  ApiTicketEvent.fromJson(Object? value) {
    final json = jsonObject(value);
    id = uuid(json, 'id');
    ticketId = uuid(json, 'ticket_id');
    user = json['user'] == null ? null : ApiProfile.fromJson(json['user']).user;
    final detail = json['detail'] == null ? <String, dynamic>{} : jsonObject(json['detail']);
    final rawType = text(json, 'event_type');
    event = TicketEvent(type: switch (rawType) {
      'STATUS_CHANGED' => 'STATUS', 'QUESTION_RAISED' => 'QUESTION',
      'QUESTION_RESOLVED' => 'RESOLVED', 'TICKET_COMPLETED' => 'COMPLETED',
      'TICKET_ASSIGNED' => 'ASSIGNED', _ => rawType,
    }, userId: optionalUuid(json, 'user_id'), ts: date(json, 'created_at'),
        text: optionalText(detail, 'question_text') ?? optionalText(detail, 'question') ??
            optionalText(detail, 'resolution') ?? optionalText(detail, 'justification') ??
            optionalText(detail, 'message'),
        toUserId: optionalUuid(detail, 'to_user_id'),
        fromStatus: detail['from_status'] == null ? null : apiTicketStatus(text(detail, 'from_status')),
        toStatus: detail['to_status'] == null ? null : apiTicketStatus(text(detail, 'to_status')));
    if (user != null && user!.id != event.userId) invalid('event.user.id');
  }
  late final String id, ticketId;
  late final User? user;
  late final TicketEvent event;
}

const apiIncidentStatuses = [IncidentStatus.reported, IncidentStatus.investigating,
  IncidentStatus.mitigated, IncidentStatus.resolved];

Incident apiIncident(Object? value) {
  final json = jsonObject(value);
  final status = switch (text(json, 'status')) {
    'REPORTED' => IncidentStatus.reported, 'INVESTIGATING' => IncidentStatus.investigating,
    'MITIGATED' => IncidentStatus.mitigated, 'RESOLVED' => IncidentStatus.resolved,
    _ => invalid('incident.status'),
  };
  final severity = switch (text(json, 'severity')) {
    'P1' => IncidentSeverity.p1, 'P2' => IncidentSeverity.p2, 'P3' => IncidentSeverity.p3,
    _ => invalid('incident.severity'),
  };
  final environment = text(json, 'affected_environment');
  if (!{'PRODUCTION', 'STAGING', 'DEV'}.contains(environment)) invalid('affected_environment');
  date(json, 'updated_at');
  count(json, 'estimated_resolution_time_seconds');
  return Incident(id: uuid(json, 'id'), number: 0, projectId: optionalUuid(json, 'application_id'),
      title: text(json, 'title'), description: optionalText(json, 'description') ?? '',
      category: null, severity: severity, status: status,
      reporterId: optionalUuid(json, 'created_by_id'), assigneeId: optionalUuid(json, 'assigned_to_id'),
      createdAt: date(json, 'created_at'), environment: environment,
      mitigation: optionalText(json, 'mitigation_state'));
}
