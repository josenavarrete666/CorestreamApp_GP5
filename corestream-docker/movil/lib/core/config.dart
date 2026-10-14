/// Configuración de la app.
///
/// Modo de datos:
///   - `demo` (por defecto): repositorio en memoria con los datos del
///     wireframe y simulación de notificaciones push. No requiere servidor.
///   - `api`: cliente HTTP contra el backend FastAPI. Se activa compilando con:
///
///       flutter run -d edge --web-port=7358 --dart-define=CS_API_URL=http://localhost:8001
///
///     (10.0.2.2 es localhost visto desde el emulador Android).
library;

class AppConfig {
  AppConfig._();

  /// URL base del backend. Vacía => modo demo.
  static const String apiBaseUrl = String.fromEnvironment('CS_API_URL');

  static bool get isDemo => apiBaseUrl.isEmpty;

  static String validateOrigin(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery ||
        uri.hasFragment || (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('CS_API_URL debe ser un origen HTTP/HTTPS sin /api');
    }
    return uri.origin;
  }

  /// Intervalo de la simulación de eventos del equipo en modo demo.
  static const Duration demoEventInterval = Duration(seconds: 20);
}
