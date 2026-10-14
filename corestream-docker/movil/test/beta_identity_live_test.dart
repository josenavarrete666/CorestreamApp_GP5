import 'dart:convert';
import 'dart:io';

import 'package:corestream_mobile/data/api_client.dart';
import 'package:corestream_mobile/data/api_repository.dart';
import 'package:corestream_mobile/models/models.dart';
import 'package:corestream_mobile/services/api_auth_service.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final path = Platform.environment['CS_BETA_CONTENT'];
  test('identidad beta real: cinco perfiles, proyectos, directorio, selector e historial', () async {
    final manifest = jsonDecode(await File(path!).readAsString()) as Map<String, dynamic>;
    if (manifest['purpose'] != 'beta-content' || manifest['state'] != 'active') {
      throw StateError('Active beta-content manifest required');
    }
    final seed = jsonDecode(await File('../backend/scripts/beta_content_seed.json').readAsString()) as Map<String, dynamic>;
    final ids = manifest['ids'] as Map<String, dynamic>;
    final people = <String, Map<String, dynamic>>{
      for (final raw in seed['users'] as List)
        ids['users'][raw['alias']] as String: Map<String, dynamic>.from(raw as Map),
    };
    Color color(String value) => Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
    void checkUser(User? user, String id) {
      expect(user, isNotNull);
      final person = people[id]!;
      expect(user!.id, id);
      expect(user.fullName, person['full_name']);
      expect(user.specialty, person['specialty']);
      expect(user.avatarColor, color(person['avatar_color'] as String));
    }
    final client = ApiClient('http://localhost:8001');
    final repo = ApiRepository(client);
    addTearDown(() { repo.dispose(); client.dispose(); });
    final auth = ApiAuthService(client);
    for (final alias in ['u1', 'u2', 'u3', 'u4', 'u5', 'u3']) {
      final credentials = manifest['users'][alias == 'u1' ? 'admin' : alias] as Map;
      final profile = await auth.login(credentials['email'] as String, credentials['password'] as String);
      try {
        repo.setSession(profile.user);
        checkUser(profile.user, ids['users'][alias] as String);
        expect(profile.mustChangePassword, false);
        final users = await repo.fetchUsers();
        for (final person in people.entries) {
          if (!profile.user.isLead && (person.value['role'] == 'ADMIN' || person.key == profile.id)) continue;
          checkUser(users.singleWhere((u) => u.id == person.key), person.key);
        }
        final projects = await repo.fetchProjects();
        for (final app in seed['applications'] as List) {
          final id = ids['applications'][app['alias']] as String;
          final project = projects.singleWhere((p) => p.project.id == id).project;
          expect(project.name, app['name']);
          expect(project.code, app['icon']);
          expect(project.color, color(app['color'] as String));
          expect((await repo.fetchBoard(id)).project, same(project));
        }
        for (final item in seed['tickets'] as List) {
          final detail = await repo.fetchTicketDetail(ids['tickets'][item['alias']] as String);
          if (detail.assignee != null && people.containsKey(detail.assignee!.id)) {
            checkUser(detail.assignee, detail.assignee!.id);
          }
          for (final event in detail.ticket.events) {
            if (people.containsKey(event.userId)) checkUser(repo.userById(event.userId), event.userId!);
          }
        }
        if (profile.user.isLead) {
          final team = await repo.fetchTeamWorkload();
          for (final person in people.entries.where((p) => p.value['role'] != 'ADMIN')) {
            checkUser(team.singleWhere((m) => m.user.id == person.key).user, person.key);
          }
        }
      } finally {
        await client.logout();
        repo.setSession(null);
      }
      expect(repo.userById(ids['users'][alias] as String), isNull);
    }
  }, skip: path == null ? 'Set CS_BETA_CONTENT to a protected active beta-content manifest (read-only).' : false,
      timeout: const Timeout(Duration(minutes: 3)));
}
