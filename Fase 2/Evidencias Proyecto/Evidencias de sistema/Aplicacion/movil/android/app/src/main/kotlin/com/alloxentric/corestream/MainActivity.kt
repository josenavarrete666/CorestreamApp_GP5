package com.alloxentric.corestream

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "Atrás" en la pantalla principal: enviar la app a segundo plano como
        // el botón de inicio, en lugar de terminar la actividad. La sesión vive
        // en memoria y se perdía al cerrar el proceso (lib/services/app_background.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "corestream/app")
            .setMethodCallHandler { call, result ->
                if (call.method == "moveToBackground") {
                    result.success(moveTaskToBack(true))
                } else {
                    result.notImplemented()
                }
            }
    }
}
