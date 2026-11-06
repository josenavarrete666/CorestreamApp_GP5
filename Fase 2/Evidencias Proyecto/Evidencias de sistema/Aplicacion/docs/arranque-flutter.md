# ARR-FLUTTER — Arranque local simplificado

**Estado: completado el 13-10-2026**, después de la
[aceptación de 8-Bis](estado-actual.md). Etapa 9 permanece en pausa por
indicación del usuario.

## Comando diario

Con el backend saludable en su propia terminal, desde la raíz del proyecto:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-flutter.ps1
```

Requiere Windows/PowerShell 5.1, Flutter >= 3.35.0 y Node.js >= 22 disponibles
en `PATH`, y Edge instalado. Entorno comprobado: Flutter 3.47.2 / Dart 3.13.2,
Node.js 24.21.0. No requiere npm. El backend conserva su comando independiente:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start.ps1
```

El launcher prepara Flutter, sirve el build API en `http://localhost:7358/` y
abre Edge; si no encuentra su instalación habitual, usa el navegador asociado.
Mantener ambas terminales abiertas. **Ctrl+C en la terminal de Flutter detiene
solo su servidor web**. Cerrar la pestaña no detiene el servidor.

Una clonación nueva necesita preparar cuentas/datos propios según la
[guía de ejecución](../GUIA_EJECUCION.md); no se distribuyen credenciales locales.

## Preparación y actualización

- Resuelve `movil/` y las herramientas respecto del script, independientemente
  de la carpeta actual. Configura `.pub-cache/` durante la ejecución y restaura
  el valor anterior de `PUB_CACHE` al finalizar.
- Ejecuta `flutter pub get` si falta la preparación o cambia el SDK,
  `pubspec.yaml` o `pubspec.lock`. También comprueba caché y `package_config.json`.
- Genera `flutter build web --no-pub --dart-define=CS_API_URL=...` si cambian
  los archivos de `lib/`, `web/` o `assets/`, dependencias, SDK u origen API;
  también si falta el bundle o se solicita `-Rebuild`.
- Guarda las huellas SHA256 en `.cache/flutter-web.json`, ignorada por Git.
  Invalida ese registro antes de una preparación/build y solo lo guarda después
  del éxito. Un registro ilegible o incompleto se trata como preparación pendiente.
- Sin cambios, reutiliza el build. **No ofrece hot reload**: después de editar
  Dart, detener con Ctrl+C y ejecutar de nuevo el mismo comando.
- Verifica salud API y puerto 7358 libre antes de servir. Un fallo de herramientas,
  dependencias o compilación termina con error antes de arrancar la web.
- Sirve únicamente en loopback y sin caché HTTP. El sondeo interno usa
  `127.0.0.1` para evitar el timeout de resolución observado; el navegador y API
  conservan `localhost` para cookies/CSRF.

## Opciones

| Opción | Uso |
|---|---|
| `-PrepareOnly` | Prepara/reutiliza el build sin iniciar servidor ni navegador; no exige salud API ni puerto libre |
| `-Rebuild` | Fuerza el build aunque las huellas no cambien |
| `-NoBrowser` | Mantiene el servidor en primer plano sin abrir el navegador automáticamente |
| `-ApiUrl http://localhost:8001` | Origen API; sin `/api`, ruta, query, fragmento o credenciales |

El modo normal siempre prepara **API real**, no demo. Mantener `localhost` en
API y navegador en el entorno local acreditado. Los comandos debug/demo siguen
disponibles en la guía.

## Comprobaciones ejecutadas

Todos los casos se comprobaron con el servidor web detenido cuando correspondía;
el backend permaneció independiente. Los errores esperados tienen salida 1,
los recorridos exitosos salida 0.

| Caso | Resultado |
|---|---|
| Primera preparación `-PrepareOnly` | `pub get` y build API correctos; compilación 72.0 s |
| Repetición sin cambios | Reutiliza el build, sin resolver paquetes ni compilar de nuevo |
| Arranque diario desde `.verification/` con ruta absoluta y `-NoBrowser` | Servidor listo y mensaje de primer plano; último ciclo 7.55 s |
| Edge aislado CDP 9244 sobre el launcher | Login Diego/API 200, datos beta visibles, recarga restaura sesión, logout + recarga vuelve al formulario; 34 respuestas API registradas, cero excepciones |
| Ctrl+C | Evento de consola Windows real enviado al grupo de consola aislado; launcher sale, Node deja de escuchar, API/PostgreSQL/Redis siguen saludables |
| Puerto ocupado / origen con `/api` / API no disponible | Error explícito, sin iniciar otro servidor |
| Error de dependencias | `flutter pub get` fallido inyectado mediante herramienta sustituta en copia aislada; no se compila ni sirve la web |
| Error de compilación | Símbolo Dart inexistente introducido temporalmente en `main.dart`; build falla y no se inicia servidor |
| Recuperación de la compilación | Retirada la línea inválida, preparación y build correctos; compilación 87.3 s |
| Cambio Dart con preparación vigente | Retirada de un comentario temporal detectada por hash; recompila automáticamente, sin `pub get` ni `-Rebuild`; compilación 84.5 s |
| Reutilización y segundo ciclo tras restaurar fuente | Build vigente, acceso Edge y Ctrl+C nuevamente correctos |
| Análisis final | `flutter analyze --no-pub`: sin problemas, 2.5 s |
| Contenido final | Verificador SQL/HTTP aprueba cinco cuentas, dataset, baseline e identidad ADMIN; no leídos 6/2/1/0/0 |

`main.dart` quedó restaurado a su contenido anterior a estas comprobaciones.
No se repitieron las mutaciones de los fixtures retirados ni la matriz visual
completa: se conserva la aceptación 8B.8 y se comprobó el acceso del nuevo launcher.

### Evidencia local

Archivos ignorados en `.verification/`: `arr-launcher-control.json`,
`arr-launcher-console.log`, `arr-guards.json`, `arr-occupied-port.log`,
`arr-invalid-origin.log`, `arr-unavailable.log`, `arr-dependency-failure.log`,
`arr-compile-failure.json/.log`, `arr-restored-build.json/.log`,
`arr-dart-change.json/.log`, `arr-edge-report.json` y `arr-edge-home.png`.
Las trazas Edge no guardan cuerpos HTTP, contraseñas ni tokens.

El primer sondeo con `localhost` falló aunque el servidor respondía; se corrigió
a IPv4 y se aprobaron los ciclos posteriores. Un intento inicial del navegador
incluyó una excepción de una extensión externa; la aceptación final utilizó
el perfil aislado con extensiones desactivadas. El helper de login también se
corrigió para reemplazar campos conservados entre sesiones. Estos intentos no
se cuentan como resultados aprobados.

El servidor histórico de pruebas se identificó por PID/comando antes de detenerlo.
Edge CDP 9244 quedó cerrado y el puerto 7358 libre después del último Ctrl+C.
La salud del backend se comprobó después del cierre. El resumen general y los
comandos de control documental están en [estado actual](estado-actual.md).
