import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api_error.dart';
import '../data/repository.dart';
import '../models/api_models.dart';
import '../models/models.dart';
import '../models/session_state.dart';
import 'api_auth_service.dart';

class SessionLifecycle {
  final Set<void Function()> closers = {};
  void close() { for (final callback in closers.toList()) { callback(); } }
}

class AuthNotifier extends StateNotifier<SessionState> {
  AuthNotifier(this.repo, this.prefs, {this.api, this.onClosing})
      : super(SessionState(api == null ? SessionPhase.signedOut : SessionPhase.restoring)) {
    if (api != null) {
      api!.client.onSessionLost = _sessionLost;
      api!.client.onPasswordRequired = () {
        if (!_closed && state.phase == SessionPhase.authenticated) {
          repo.setSession(null);
          state = SessionState(SessionPhase.passwordRequired, user: state.user, profile: state.profile);
          onClosing?.call();
        }
      };
      unawaited(Future<void>.microtask(restore));
    }
  }
  final CoreStreamRepository repo;
  final SharedPreferences prefs;
  final ApiAuthService? api;
  final void Function()? onClosing;
  int _generation = 0;
  bool _closed = false;
  String get pendingKey => 'logout_pending:${api!.client.origin.origin}';
  bool _current(int generation) => !_closed && generation == _generation;

  void _sessionLost(ApiError error) {
    if (_closed || state.phase == SessionPhase.signingOut) return;
    _generation++;
    api?.client.abandonSession();
    repo.setSession(null);
    state = SessionState(SessionPhase.signedOut, error: error);
    onClosing?.call();
  }

  void _accept(ApiProfile profile) {
    if (!profile.user.isActive) {
      throw const ApiError(ApiErrorKind.session, 'Cuenta desactivada.', status: 403);
    }
    repo.setSession(profile.mustChangePassword ? null : profile.user);
    state = SessionState(profile.mustChangePassword ? SessionPhase.passwordRequired : SessionPhase.authenticated,
        user: profile.user, profile: profile);
  }

  Future<void> restore() async {
    if (api == null || _closed || state.phase == SessionPhase.signingIn || state.phase == SessionPhase.signingOut) return;
    final generation = ++_generation;
    if (prefs.getBool(pendingKey) == true) {
      state = const SessionState(SessionPhase.logoutPending);
      await resolvePendingLogout();
      return;
    }
    state = const SessionState(SessionPhase.restoring);
    repo.setSession(null);
    try {
      final profile = await api!.restore();
      if (_current(generation)) _accept(profile);
    } on ApiError catch (error) {
      if (_current(generation)) {
        api!.client.abandonSession();
        state = SessionState(SessionPhase.signedOut, error: error.status == 401 ? null : error);
      }
    }
  }

  Future<void> loginAs(User user) async {
    if (api != null || state.busy) return;
    final generation = ++_generation;
    state = const SessionState(SessionPhase.signingIn);
    final actual = await repo.login(user);
    if (_current(generation)) state = SessionState(SessionPhase.authenticated, user: actual);
  }

  Future<void> login(String email, String password) async {
    if (api == null || state.busy || state.phase == SessionPhase.logoutPending) return;
    final generation = ++_generation;
    state = const SessionState(SessionPhase.signingIn);
    try {
      final profile = await api!.login(email, password);
      if (_current(generation)) _accept(profile);
    } on ApiError catch (error) {
      if (_current(generation)) {
        api!.client.abandonSession();
        state = SessionState(SessionPhase.signedOut, error: error);
      }
    }
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    if (api == null || state.phase != SessionPhase.passwordRequired || state.busy) return;
    final generation = _generation;
    final profile = state.profile;
    state = SessionState(SessionPhase.signingIn, profile: profile);
    try {
      await api!.changePassword(oldPassword, newPassword);
      final updated = await api!.profile();
      if (!_current(generation)) return;
      if (updated.mustChangePassword) invalid('must_change_password');
      await logout();
    } on ApiError catch (error) {
      if (_current(generation)) state = SessionState(SessionPhase.passwordRequired, profile: profile, error: error);
    }
  }

  Future<void> logout() async {
    if (state.phase == SessionPhase.signingOut || _closed) return;
    final generation = ++_generation;
    state = const SessionState(SessionPhase.signingOut);
    repo.setSession(null);
    onClosing?.call();
    if (api == null) {
      await repo.logout();
      if (_current(generation)) state = const SessionState(SessionPhase.signedOut);
      return;
    }
    // Persist the barrier before any asynchronous operation can be interrupted.
    await prefs.setBool(pendingKey, true);
    try {
      final confirmed = await api!.logout();
      await prefs.remove(pendingKey);
      if (_current(generation)) state = SessionState(SessionPhase.signedOut, revocationConfirmed: confirmed);
    } on ApiError catch (error) {
      if (_current(generation)) state = SessionState(SessionPhase.logoutPending, error: error);
    }
  }

  Future<void> resolvePendingLogout() async {
    if (api == null || _closed) return;
    final generation = ++_generation;
    state = const SessionState(SessionPhase.signingOut);
    try {
      await api!.logout();
      await prefs.remove(pendingKey);
      if (_current(generation)) state = const SessionState(SessionPhase.signedOut);
    } on ApiError catch (error) {
      if (_current(generation)) state = SessionState(SessionPhase.logoutPending, error: error);
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    if (api != null) { api!.client.onSessionLost = null; api!.client.onPasswordRequired = null; }
    super.dispose();
  }
}
