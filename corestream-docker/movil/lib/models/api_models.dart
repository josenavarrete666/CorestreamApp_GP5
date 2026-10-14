import 'package:flutter/material.dart' show Color;

import '../data/api_error.dart';
import 'models.dart';

Never invalid(String field) => throw ApiError(ApiErrorKind.contract, 'Respuesta API inválida: $field');
Map<String, dynamic> jsonObject(Object? value) => value is Map<String, dynamic> ? value : invalid('objeto JSON');
String text(Map<String, dynamic> json, String key) => json[key] is String && (json[key] as String).isNotEmpty ? json[key] as String : invalid(key);
bool boolean(Map<String, dynamic> json, String key) => json[key] is bool ? json[key] as bool : invalid(key);
int count(Map<String, dynamic> json, String key) => json[key] is int && (json[key] as int) >= 0 ? json[key] as int : invalid(key);
String uuid(Map<String, dynamic> json, String key) {
  final value = text(json, key);
  if (!RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(value)) invalid(key);
  return value;
}
DateTime date(Map<String, dynamic> json, String key) {
  final value = text(json, key);
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) invalid(key);
  return DateTime.tryParse(value)?.toUtc() ?? invalid(key);
}

// Decorative metadata must not prevent access to otherwise valid resources.
Color apiColor(Object? value) => value is String && RegExp(r'^#[0-9a-fA-F]{6}$').stringMatch(value) == value
    ? Color(0xFF000000 | int.parse(value.substring(1), radix: 16))
    : const Color(0xFF4C8DFF);

String apiMonogram(Object? value) => value is String && RegExp(r'^[A-Z0-9]{1,3}$').stringMatch(value) == value
    ? value : '';

class ApiToken {
  ApiToken.fromJson(Object? value) {
    final json = jsonObject(value);
    access = text(json, 'access_token');
    if (text(json, 'token_type').toLowerCase() != 'bearer') invalid('token_type');
    mustChangePassword = boolean(json, 'must_change_password');
    expiresIn = json['expires_in'] == null ? null : count(json, 'expires_in');
    if (expiresIn == 0) invalid('expires_in');
  }
  late final String access;
  late final bool mustChangePassword;
  late final int? expiresIn;
}

class ApiProfile {
  ApiProfile.fromJson(Object? value, {bool passwordRequired = false}) {
    final json = jsonObject(value);
    id = uuid(json, 'id');
    email = text(json, 'email');
    role = text(json, 'role');
    final userRole = switch (role) {
      'ADMIN' => UserRole.admin,
      'TEAM_LEADER' => UserRole.groupLeader,
      'DEVELOPER' => UserRole.developer,
      _ => invalid('role'),
    };
    date(json, 'created_at');
    mustChangePassword = boolean(json, 'must_change_password') || passwordRequired;
    if (json['specialty'] != null && json['specialty'] is! String) invalid('specialty');
    final preferences = json['preferences'];
    user = User(id: id, fullName: text(json, 'full_name'), role: userRole,
        specialty: json['specialty'] as String?, isActive: boolean(json, 'is_active'),
        avatarColor: apiColor(preferences is Map ? preferences['avatar_color'] : null));
  }
  late final String id, email, role;
  late final User user;
  late final bool mustChangePassword;
}

class ApiApplication {
  ApiApplication.fromJson(Object? value) {
    final json = jsonObject(value);
    id = uuid(json, 'id');
    name = text(json, 'name');
    active = boolean(json, 'is_active');
    createdAt = date(json, 'created_at');
    epicCount = count(json, 'epic_count');
    pendingCount = count(json, 'pending_count');
    delayedCount = count(json, 'delayed_count');
    color = apiColor(json['color']);
    monogram = apiMonogram(json['icon']);
  }
  late final String id, name;
  late final bool active;
  late final DateTime createdAt;
  late final int epicCount, pendingCount, delayedCount;
  late final Color color;
  late final String monogram;
}

class ApiNotification {
  ApiNotification.fromJson(Object? value) {
    final json = jsonObject(value);
    id = uuid(json, 'id');
    userId = uuid(json, 'user_id');
    title = text(json, 'title');
    message = text(json, 'message');
    rawType = text(json, 'type');
    read = boolean(json, 'is_read');
    createdAt = date(json, 'created_at');
    ticketId = json['ticket_id'] == null ? null : uuid(json, 'ticket_id');
  }
  late final String id, userId, title, message, rawType;
  late final String? ticketId;
  late final bool read;
  late final DateTime createdAt;
  AppNotification get display => AppNotification(id: id, kind: switch (rawType) {
    'QUESTION_RAISED' => NotificationKind.question,
    'TICKET_REDIRECTED' => NotificationKind.redirect,
    _ => NotificationKindWire.parse(rawType),
  }, title: title, message: message, ts: createdAt, read: read, ticketId: ticketId);
}
