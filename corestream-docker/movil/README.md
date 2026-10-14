# CoreStream Mobile (Flutter)

La base Flutter ofrece **demo de la beta** e **interfaz beta integrada con la API
actual**: Inicio/Mi trabajo, proyectos/tablero/tickets, incidencias, Equipo,
campana/avisos y Ajustes. El login comparte la estética beta y conserva su ciclo de sesión.

Entorno: [README raíz](../README.md) y [guía de ejecución](../GUIA_EJECUCION.md).
Contrato: [contratos-api.md](../docs/contratos-api.md).
Acciones y límites: [matriz beta/API](../docs/matriz-beta-api.md).
Resultados, decisiones y presentación: [estado actual](../docs/estado-actual.md).
Web ya preparado para Edge; Android se genera y valida en etapa 10.
8B.1–8B.8 completadas; contenido, identidad, login, pantallas e interacción aceptados.
Semántica de segunda épica corregida. ARR-FLUTTER completado y comprobado.
Etapa 9 permanece en pausa; [pendientes de E1/Android](../TODO_SETUP.md).
[Correspondencia del contenido](../docs/contenido-beta-8bis.md).
[Carga y cuentas locales](../docs/carga-beta-8bis.md).
[Roles y permisos](../docs/roles-permisos.md).

## Arranque rápido

Con el backend saludable, desde la raíz `corestream-docker/` en PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-flutter.ps1
```

Prepara/reutiliza el build API y abre Edge en `http://localhost:7358/`. Mantener
la terminal abierta; Ctrl+C detiene solo la web. Después de cambiar Dart, detener
y ejecutar otra vez para recompilar. Requiere Flutter y Node.js >= 22 en `PATH`.
[Opciones y evidencia ARR-FLUTTER](../docs/arranque-flutter.md).

Para demo/debug y comprobaciones, desde `corestream-docker/movil/`, ejecutar
cada línea por separado:

```powershell
$env:PUB_CACHE = Join-Path (Resolve-Path "..").Path ".pub-cache"
flutter pub get
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter run -d edge --web-port=7358
```

> Base verificada con Flutter 3.47.2 / Dart 3.13.2: análisis sin avisos,
> **79 pruebas aprobadas + 2 omitidas**; 1 live adicional de aceptación aprobada.
> Los tests live requieren manifiestos explícitos y la aceptación mutante un fixture fresco;
> demo y beta/API comprobadas en Edge; 8B.8: 24 combinaciones / 176 capturas nuevas,
> evidencia 8B.6 reutilizada (240); build web acreditado.
> Se requiere Flutter >= 3.35.0.
> Fechas, procedencia y límites en [estado actual](../docs/estado-actual.md).

## Modos de datos

| Modo | Cómo se activa | Qué hace |
|---|---|---|
| **Demo** (por defecto) | `flutter run` | Datos del wireframe en memoria, selector de rol en el login, y simulación de eventos del equipo cada ~20 s (nueva incidencia, ticket asignado, completado, pregunta) que llegan como toasts push + campana. Nada se guarda. |
| **API real, arranque diario** | `scripts/start-flutter.ps1` desde la raíz | Prepara/reutiliza el build release, sirve la web y abre Edge; backend independiente. |
| **API real en Edge** | `flutter run --no-pub -d edge --web-port=7358 --dart-define=CS_API_URL=http://localhost:8001` | Credenciales con estética beta → HomeShell beta, dominios/datos/operaciones reales y límites explícitos; cookies/CSRF, refresh, WS y logout. Requiere servidor y cuenta local. |

`CS_API_URL` es un origen sin `/api`. Mantener `localhost` en API y web para
cookies. Sin datos puede haber listas vacías válidas; errores tienen estado y
reintento propios. En la instalación verificada el fixture nativo fue retirado;
ADMIN y `beta-manual.json` se conservan solo allí. Una clonación nueva prepara
cuentas/datos propios; los manifiestos privados no se distribuyen. La guía
explica bootstrap, límites y setup/check/cleanup.
La carga opcional de 8B.3 prepara Ana/Luis/Diego/Sofía/Marco y sus proyectos
en cada instalación. Sus credenciales están en el manifiesto local protegido,
conforme a la documentación enlazada; el modo API conserva el formulario real.
Cambiar modo requiere reiniciar run. Si DWDS/debug falla, usar el build estático
acreditado de la guía (`node ../scripts/serve-web.mjs` desde `movil/`).

`lib/`, `test/`, `web/`, `pubspec.yaml`, `pubspec.lock`, `.metadata` y configuración
de análisis se versionan. Dependencias, `.dart_tool/`, builds y resultados no se
suben. [Política del repositorio](../docs/publicacion-github.md).

## Estructura

```
lib/
├── main.dart                  arranque + MaterialApp (tema oscuro por defecto)
├── providers.dart             Riverpod: sesión, tema, idioma, datos
├── core/
│   ├── config.dart            CS_API_URL / modo demo
│   ├── theme.dart             paleta CoreStream (claro/oscuro) como ThemeExtension
│   └── i18n.dart              ES/EN sin dependencias, formatos de fecha/duración
├── models/                    DTO API estrictos, sesión y modelos demo/permisos
├── data/
│   ├── repository.dart        contrato + agregados de vista
│   ├── demo_repository.dart   datos wireframe + simulación push
│   ├── api_client.dart        Dio, generación, refresh single-flight y logout
│   ├── http_platform*.dart    adaptadores web/nativo, cookie jar y CSRF
│   ├── api_error.dart         errores HTTP/red/contrato tipados
│   └── api_repository.dart    dominios, composición por sesión, páginas y mutaciones reales
├── services/
│   ├── auth_notifier.dart     máquina de sesión y cierre pendiente por origen
│   ├── api_auth_service.dart  login/perfil/cambio/logout
│   ├── api_websocket_service.dart tickets, eventos y reconexión cancelable
│   └── push_service.dart      Noop; FCM preparado pero desactivado
└── ui/                        layout de sesión, login/cambio y vistas beta compartidas demo/API
test/                          contrato, sesión, widgets, sockets y base demo
```

## Roles y recorrido

Roles API: **ADMIN, TEAM_LEADER, DEVELOPER**. TEAM_LEADER se mapea al líder
interno; GROUP_LEADER queda como alias demo/legado. Un rol desconocido produce
error de contrato, sin degradación automática ni navegación protegida.

Demo conserva simulación y sus permisos. API utiliza HomeShell y repositorio
completo, sin directorio previo al login. ADMIN no ejecuta trabajo; developer
no resuelve preguntas. Gestores usan `/users/`; destinos developer usan
`/tickets/team-members`. Incidencias son `/incidents/`, cuatro estados y P1/P2/P3,
no tickets SUPPORT. Límites sin contrato se explican en pantalla. No se necesita
`/api/mobile` para esta composición. UUID/fechas reales, sin número/código ficticio.

Se recuperan colores de proyecto y `preferences.avatar_color`, especialidades
y monogramas decorativos PC/AP/AL. El selector developer entrega solo
`specialty/avatar_color` adicionales, conservando los permisos. Para el test de
identidad live de solo lectura, definir `CS_BETA_CONTENT` al manifiesto protegido
beta-content y ejecutar `flutter test --no-pub test/beta_identity_live_test.dart`.

## Sesión y tiempo real

Access en memoria; refresh web HttpOnly y CSRF legible, rotación y replay único.
Logout offline guarda solo una marca no secreta e impide restaurar recursos
hasta resolver el cierre. Cambio obligatorio verifica perfil y pide nuevo login.

WS usa ticket opaco de 15 s por conexión, nunca JWT en query. Heartbeat,
actividad acotada, backoff y cancelación por sesión; al reconectar reconsulta
HTTP para recuperar notificaciones persistidas durante el corte. Idle 4000
espera acción del usuario.

## Plataformas y push pendientes

El jar nativo se implementó en memoria y se probó su protocolo; almacenamiento
protegido/persistente se incorpora y acredita en Android. Web no acredita
biometría ni entrega de notificaciones por sistema operativo.

La app compila sin Firebase. Registro/desvinculación de dispositivos,
preferencias, modelos/migraciones/API y configuración FCM son requisitos de
Equipo 1 posteriores. `/api/devices` no existe actualmente. WebSocket activo
y push FCM son mecanismos distintos; generar `android/` y validar entrega
nativa corresponde a la etapa final.
