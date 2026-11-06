/// Providers Riverpod de la app.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config.dart';
import 'core/i18n.dart';
import 'data/api_repository.dart';
import 'data/api_client.dart';
import 'data/api_error.dart';
import 'data/demo_repository.dart';
import 'data/repository.dart';
import 'models/models.dart';
import 'models/api_models.dart';
import 'models/session_state.dart';
import 'services/api_auth_service.dart';
import 'services/api_websocket_service.dart';
import 'services/auth_notifier.dart';
import 'services/firebase_push_service.dart';
import 'services/push_platform.dart';
import 'services/push_service.dart';

// ------------------------------------------------------------- infraestructura

/// Se sobreescribe en main() con la instancia real.
final prefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Sobreescrito en main()');
});

final apiModeProvider = Provider<bool>((ref) => !AppConfig.isDemo);
final apiOriginProvider = Provider<String>((ref) => AppConfig.apiBaseUrl);
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(ref.watch(apiOriginProvider));
  ref.onDispose(client.dispose);
  return client;
});
final apiRepositoryProvider = Provider<ApiRepository>((ref) {
  final repo = ApiRepository(ref.watch(apiClientProvider));
  ref.onDispose(repo.dispose);
  return repo;
});
final apiResourcesProvider = Provider<ApiResources>((ref) => ref.watch(apiRepositoryProvider));
final repositoryProvider = Provider<CoreStreamRepository>((ref) {
  if (ref.watch(apiModeProvider)) return ref.watch(apiRepositoryProvider);
  final repo = DemoRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// FCM solo en Android y en modo API; en web, escritorio, demo y pruebas, Noop.
final pushServiceProvider = Provider<PushService>((ref) =>
    supportsFcm && ref.watch(apiModeProvider) ? FirebasePushService() : NoopPushService());

/// Registra el dispositivo en el backend mientras hay sesión (APP-06). El push
/// es opcional: un fallo aquí nunca afecta la sesión ni la navegación.
final AutoDisposeProvider<void> pushRegistrationProvider = Provider.autoDispose<void>((ref) {
  final user = ref.watch(authProvider);
  if (!ref.watch(apiModeProvider) || user == null) return;
  final push = ref.watch(pushServiceProvider);
  final repo = ref.watch(repositoryProvider);
  var active = true;
  Future<void> register(String? token) async {
    if (!active || token == null) return;
    try { await repo.registerDevice(token, push.platform); } on ApiError { /* sin push */ }
  }
  unawaited(push.init().then(register, onError: (Object _) {}));
  final refresh = push.tokenRefresh.listen(register);
  ref.onDispose(() { active = false; refresh.cancel(); });
});

/// Convierte un push tocado en la notificación que abre su recurso.
///
/// Tolerante a propósito: al tocar la notificación del sistema, Android puede
/// entregar el mensaje sin título ni cuerpo. Antes se validaba con el modelo
/// estricto de la API (título y mensaje obligatorios) y el toque se descartaba
/// sin navegar. Lo imprescindible es el `ticket_id`; sin él no hay destino.
AppNotification? notificationFromPush(PushOpen open) {
  final ticketId = open.data['ticket_id'] ?? '';
  if (ticketId.isEmpty) return null;
  final type = open.data['type'] ?? '';
  final kind = switch (type) {
    'QUESTION_RAISED' => NotificationKind.question,
    'TICKET_REDIRECTED' => NotificationKind.redirect,
    '' => NotificationKind.system,
    _ => NotificationKindWire.parse(type),
  };
  return AppNotification(
    id: open.data['notification_id'] ?? ticketId,
    kind: kind,
    title: open.title,
    message: open.body ?? '',
    ts: DateTime.now(),
    ticketId: ticketId,
  );
}

/// Push tocados por el usuario (deep link) que tienen un recurso que abrir.
final pushOpenedProvider = StreamProvider.autoDispose<AppNotification>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return const Stream.empty();
  return ref.watch(pushServiceProvider).opened
      .map(notificationFromPush)
      .where((notification) => notification != null)
      .cast<AppNotification>();
});

/// Revisión de datos: cualquier provider que la observe se recalcula cuando
/// el repositorio emite un cambio (acción propia o evento simulado/WS).
final dataRevisionProvider = StreamProvider<int>(
  (ref) => ref.watch(repositoryProvider).changes,
);

// ------------------------------------------------------------------- sesión

final sessionLifecycleProvider = Provider<SessionLifecycle>((ref) => SessionLifecycle());
final StateNotifierProvider<AuthNotifier, SessionState> authControllerProvider = StateNotifierProvider<AuthNotifier, SessionState>((ref) => AuthNotifier(
    ref.watch(repositoryProvider), ref.watch(prefsProvider),
    api: ref.watch(apiModeProvider) ? ApiAuthService(ref.watch(apiClientProvider)) : null,
    onClosing: ref.watch(sessionLifecycleProvider).close,
    deviceToken: ref.watch(pushServiceProvider).token));
final Provider<User?> authProvider = Provider<User?>((ref) {
  final state = ref.watch(authControllerProvider);
  return state.phase == SessionPhase.authenticated ? state.user : null;
});

final applicationsProvider = FutureProvider.autoDispose<List<ApiApplication>>((ref) {
  final user = ref.watch(authProvider);
  ref.watch(dataRevisionProvider);
  if (user == null) return const [];
  return ref.watch(apiResourcesProvider).applications();
});
final apiNotificationsProvider = FutureProvider.autoDispose<List<ApiNotification>>((ref) {
  final user = ref.watch(authProvider);
  ref.watch(dataRevisionProvider);
  if (user == null) return const [];
  return ref.watch(apiResourcesProvider).notifications();
});
final AutoDisposeProvider<ApiWebSocketService?> apiWebsocketProvider = Provider.autoDispose<ApiWebSocketService?>((ref) {
  final user = ref.watch(authProvider);
  if (!ref.watch(apiModeProvider) || user == null) return null;
  Timer? debounce;
  final repo = ref.watch(apiRepositoryProvider);
  final service = ApiWebSocketService(ref.watch(apiClientProvider), user.id,
      onChange: () {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 150), repo.invalidate);
      }, onNotification: (payload) => repo.receiveNotification(user.id, payload));
  final lifecycle = ref.watch(sessionLifecycleProvider);
  lifecycle.closers.add(service.stop);
  ref.onDispose(() { lifecycle.closers.remove(service.stop); debounce?.cancel(); service.dispose(); });
  service.start();
  return service;
});
final websocketStatusProvider = StreamProvider.autoDispose<WsStatus>((ref) {
  final service = ref.watch(apiWebsocketProvider);
  return service?.statuses ?? Stream.value(WsStatus.stopped);
});
final liveApiNotificationProvider = StreamProvider.autoDispose<AppNotification>((ref) {
  if (ref.watch(authProvider) == null) return const Stream.empty();
  return ref.watch(apiRepositoryProvider).incomingPush;
});

// -------------------------------------------------------------- preferencias

class ThemeDarkNotifier extends StateNotifier<bool> {
  ThemeDarkNotifier(this._prefs) : super(_prefs.getBool('dark') ?? true);
  final SharedPreferences _prefs;

  void set(bool dark) {
    state = dark;
    _prefs.setBool('dark', dark);
  }
}

/// true = tema oscuro (por defecto, como pidió el diseño).
final darkModeProvider =
    StateNotifierProvider<ThemeDarkNotifier, bool>((ref) => ThemeDarkNotifier(ref.watch(prefsProvider)));

class LangNotifier extends StateNotifier<String> {
  LangNotifier(this._prefs) : super(_prefs.getString('lang') ?? 'es');
  final SharedPreferences _prefs;

  void set(String lang) {
    state = lang;
    _prefs.setString('lang', lang);
  }
}

final langProvider =
    StateNotifierProvider<LangNotifier, String>((ref) => LangNotifier(ref.watch(prefsProvider)));

final stringsProvider = Provider<S>((ref) => S.byCode(ref.watch(langProvider)));

// -------------------------------------------------------------------- datos

final dashboardProvider = FutureProvider.autoDispose<Dashboard>((ref) {
  ref.watch(dataRevisionProvider);
  ref.watch(authProvider);
  return ref.watch(repositoryProvider).fetchDashboard();
});

final projectsProvider = FutureProvider.autoDispose<List<ProjectSummary>>((ref) {
  ref.watch(authProvider);
  ref.watch(dataRevisionProvider);
  return ref.watch(repositoryProvider).fetchProjects();
});

final boardProvider = FutureProvider.autoDispose.family<Board, String>((ref, projectId) {
  ref.watch(authProvider);
  ref.watch(dataRevisionProvider);
  return ref.watch(repositoryProvider).fetchBoard(projectId);
});

final ticketDetailProvider =
    FutureProvider.autoDispose.family<TicketDetail, String>((ref, ticketId) {
  ref.watch(dataRevisionProvider);
  ref.watch(authProvider);
  return ref.watch(repositoryProvider).fetchTicketDetail(ticketId);
});

final incidentsProvider = FutureProvider.autoDispose<List<Incident>>((ref) {
  ref.watch(dataRevisionProvider);
  ref.watch(authProvider);
  return ref.watch(repositoryProvider).fetchIncidents();
});

final incidentProvider =
    FutureProvider.autoDispose.family<Incident, String>((ref, incidentId) {
  ref.watch(authProvider);
  ref.watch(dataRevisionProvider);
  return ref.watch(repositoryProvider).fetchIncident(incidentId);
});

final teamWorkloadProvider = FutureProvider.autoDispose<List<MemberLoad>>((ref) {
  ref.watch(authProvider);
  ref.watch(dataRevisionProvider);
  return ref.watch(repositoryProvider).fetchTeamWorkload();
});

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) {
  ref.watch(dataRevisionProvider);
  ref.watch(authProvider);
  return ref.watch(repositoryProvider).fetchNotifications();
});

final unreadCountProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(dataRevisionProvider);
  if (ref.watch(authProvider) == null) return 0;
  return ref.watch(repositoryProvider).unreadCount();
});

final usersProvider = FutureProvider.autoDispose<List<User>>((ref) {
  ref.watch(authProvider);
  ref.watch(dataRevisionProvider);
  return ref.watch(repositoryProvider).fetchUsers();
});

void refreshApiData(WidgetRef ref) {
  final repo = ref.read(repositoryProvider);
  if (repo is ApiRepository) repo.invalidate();
}
