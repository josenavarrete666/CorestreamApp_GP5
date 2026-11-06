import 'package:flutter/services.dart';

import 'push_platform.dart';

const _channel = MethodChannel('corestream/app');

/// Envía la app a segundo plano, como el botón de inicio de Android.
///
/// En la pantalla principal, "atrás" terminaba la actividad: Android cerraba
/// el proceso y con él la sesión, que vive en memoria. Devuelve false si la
/// plataforma no lo soporta (web, escritorio, pruebas) para que el caller
/// aplique el comportamiento normal.
Future<bool> moveAppToBackground() async {
  if (!supportsFcm) return false;
  try {
    return await _channel.invokeMethod<bool>('moveToBackground') ?? false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
