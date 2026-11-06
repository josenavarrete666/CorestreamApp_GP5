import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_service.dart';

/// Push reales con Firebase Cloud Messaging (solo Android).
///
/// Firebase se inicializa con android/app/google-services.json (plugin de
/// Gradle), por eso no hace falta firebase_options.dart. El destino del push
/// es el registration token de FCM (`getToken`), que se registra en el backend.
/// La API nueva `register()`/`onRegistered` (FID) se probó en un Samsung S20
/// con Android 13 y no responde, por eso se usa la API estable.
///
/// Mientras la app está en segundo plano, Android muestra el push por sí
/// mismo; en primer plano el aviso ya llega por el WebSocket como toast.
class FirebasePushService implements PushService {
  static const tokenTimeout = Duration(seconds: 20);

  final _opened = StreamController<PushOpen>.broadcast();
  Future<bool>? _ready;
  String? _token;
  /// Push que abrió la app desde cerrada: se guarda hasta que alguien escuche.
  PushOpen? _pending;

  @override
  String get platform => 'ANDROID';

  void _emit(PushOpen open) {
    if (_opened.hasListener) {
      _opened.add(open);
    } else {
      _pending = open;
    }
  }

  Future<bool> _initialize() async {
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;
    FirebaseMessaging.onMessageOpenedApp.listen((message) => _emit(_open(message)));
    final initial = await messaging.getInitialMessage();
    if (initial != null) _emit(_open(initial));
    return true;
  }

  Future<bool> _ensureReady() => _ready ??= _initialize().catchError((Object _) {
        _ready = null;
        return false;
      });

  static PushOpen _open(RemoteMessage message) => PushOpen(
        data: {for (final entry in message.data.entries) entry.key: '${entry.value}'},
        title: message.notification?.title,
        body: message.notification?.body,
      );

  @override
  Future<String?> init() async {
    if (!await _ensureReady()) return null;
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
    try {
      // ignore: deprecated_member_use
      return _token = await messaging.getToken().timeout(tokenTimeout);
    } on TimeoutException {
      return null;
    }
  }

  @override
  Future<String?> token() async => _token;

  /// Token nuevo cuando Firebase lo rota; se re-registra en el backend.
  /// Espera a que Firebase esté inicializado: FirebaseMessaging.instance lanza
  /// `core/no-app` si se toca antes de Firebase.initializeApp().
  @override
  Stream<String> get tokenRefresh async* {
    if (!await _ensureReady()) return;
    // ignore: deprecated_member_use
    yield* FirebaseMessaging.instance.onTokenRefresh.map((token) => _token = token);
  }

  @override
  Stream<PushOpen> get opened async* {
    final pending = _pending;
    _pending = null;
    if (pending != null) yield pending;
    yield* _opened.stream;
  }
}
