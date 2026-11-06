/// Notificaciones push del dispositivo (APP-06).
///
/// En Android se usa [FirebasePushService] (FCM, proyecto corestreamappg5).
/// En web y escritorio la implementación activa es [NoopPushService]: allí
/// los avisos llegan por el WebSocket autenticado mientras la app está
/// abierta, y en modo demo los simula DemoRepository.
///
/// El token se registra en el backend con POST /api/devices/ al iniciar
/// sesión y se envía en el logout para que ese dispositivo deje de recibir
/// push (APP-03). El backend decide a quién notificar.
library;

/// Datos de un push que el usuario tocó (deep link hacia el recurso).
class PushOpen {
  const PushOpen({required this.data, this.title, this.body});
  final Map<String, String> data;
  final String? title;
  final String? body;
}

abstract class PushService {
  /// Plataforma que se registra en el backend: "ANDROID" o "IOS" (contrato §4.1).
  String get platform;

  /// Pide permiso al usuario y devuelve el token del dispositivo, o null si
  /// no hay proveedor de push disponible o el permiso fue negado.
  Future<String?> init();

  /// Token actual sin pedir permiso de nuevo; null si no hay. Lo usa el
  /// logout para desactivar este dispositivo.
  Future<String?> token();

  /// Stream de tokens rotados (FCM onTokenRefresh). Se re-registra el
  /// dispositivo cuando emite.
  Stream<String> get tokenRefresh;

  /// Push tocados por el usuario, incluido el que abrió la app.
  Stream<PushOpen> get opened;
}

/// Implementación sin proveedor de push (web, escritorio y pruebas).
class NoopPushService implements PushService {
  @override
  String get platform => 'NONE'; // nunca se registra: init() devuelve null

  @override
  Future<String?> init() async => null;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get tokenRefresh => const Stream.empty();

  @override
  Stream<PushOpen> get opened => const Stream.empty();
}
