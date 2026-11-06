# Instrucciones para agentes — CoreStream Mobile

Estas instrucciones se aplican a todo el proyecto. Comunicarse en español y
mantener los cambios coherentes con las convenciones del código existente.

## Alcance y documentos de entrada

- Esta carpeta es la raíz de desarrollo: Flutter/Dart, FastAPI, PostgreSQL y Redis.
- Consultar `README.md` y `TODO_SETUP.md` antes de desarrollar. El estado,
  decisiones y evidencia histórica están en `docs/estado-actual.md`.
- **Leer primero `docs/traspaso-agente.md`**: resume lo hecho en la etapa 9
  (APP-03/APP-06, Android, push), decisiones a respetar, pendientes y trampas
  del entorno. Para levantar el proyecto: `docs/puesta-en-marcha-equipo.md`.
- Las etapas 1–8, 8-Bis y ARR-FLUTTER están cerradas. **La etapa 9 está en curso
  desde el 04-11-2026 por indicación del usuario, con APP-03 y APP-06**; los demás
  requisitos de E1 necesitan su propia indicación. Una tarea de mantenimiento o
  documentación no autoriza iniciar requisitos nuevos.
- El desarrollo posterior acordado corresponde a Equipo 1: sesión, seguridad y
  plataforma. Requisitos nuevos de E2/E3 requieren ampliar expresamente el alcance.
- Android es el destino móvil; iOS queda fuera del alcance. Edge es la plataforma
  local comprobada y no sustituye la aceptación nativa de biometría, FCM o storage.
- Las carpetas hermanas `corestream/` y `Documentacion/` no son dependencias de
  ejecución. La fuente original se consulta en solo lectura; trabajar en esta raíz.

## Mapa del proyecto

| Ubicación | Responsabilidad |
|---|---|
| `movil/lib/` | Cliente Flutter, Riverpod, modelos, repositorios, sesión y UI |
| `movil/test/` | Pruebas Dart/Flutter y aceptación live con manifiesto explícito |
| `backend/app/` | FastAPI, routers, schemas, modelos y servicios de dominio |
| `backend/alembic/` | Migraciones versionadas |
| `backend/tests/` | Pruebas unitarias e integración |
| `backend/scripts/` | Carga beta, fixtures y comprobaciones de datos |
| `scripts/` | Preparación local, arranque y servidor web |
| `scripts/verification/` | Comprobadores y automatización Edge versionados |
| `docs/` | Arquitectura, contratos, permisos, guías y requisitos |

Consultar `docs/contratos-api.md`, `docs/matriz-beta-api.md` y
`docs/roles-permisos.md` antes de cambiar una interfaz o autorización.
Los Word de `docs/requerimientos/` describen objetivos y algunos estados antiguos:
contrastar sus afirmaciones con el código actual.

## Reglas de implementación

- Reutilizar componentes, transportes y servicios existentes. Mantener separados
  el modo demo y el modo API; una simulación no acredita una operación persistente.
- El backend determina datos, estados y permisos. No inventar métricas, fechas,
  relaciones, historial ni resultados satisfactorios para reproducir la demo.
- Conservar la estética beta y el ciclo de sesión ya comprobado; priorizar cambios
  acotados y regresiones significativas ante problemas reales.
- `CS_API_URL` es un origen sin `/api`, ruta, query, fragmento ni credenciales.
  Las solicitudes usan rutas absolutas `/api/...`.
- Mantener access en memoria, refresh HttpOnly/cookie y CSRF, renovación compartida,
  generación de sesión y cierre pendiente. No guardar tokens o contraseñas en
  SharedPreferences/localStorage. Un 403 de negocio no debe destruir la sesión.
- ADMIN no inicia/completa/plantea preguntas de trabajo en tickets; developer no
  resuelve preguntas bloqueantes. Autorización de servidor, no solo botones ocultos.
- DEVELOPMENT, SUPPORT e incidencias son dominios distintos. Incidencias usan
  REPORTED/INVESTIGATING/MITIGATED/RESOLVED y P1/P2/P3; asignación y estado separados.
- No repetir automáticamente mutaciones con resultado ambiguo: reconsultar el
  recurso y conservar un error visible. No declarar éxito por cambiar un widget.
- WebSocket no equivale a push FCM. Push: `FirebasePushService` solo en Android,
  `NoopPushService` en web/escritorio/pruebas; el destino es el token de `getToken()`. Los tests
  nunca usan la credencial real (conftest vacía `FIREBASE_CREDENTIALS_FILE`).
  La entrega real se acredita en Android, no en Edge.
- La API persiste/publica notificaciones directamente; ARQ no forma parte del arranque.

## Entorno e inicio local

Windows/PowerShell 5.1 y Docker Engine/Compose dentro de Ubuntu-24.04/WSL2.
Flutter >= 3.35.0 y Node.js >= 22 en PATH; las herramientas Node no requieren npm.
Procedimiento completo y bootstrap de ADMIN: `GUIA_EJECUCION.md`.

Desde la raíz, en dos terminales independientes que permanecen abiertas:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start.ps1
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-flutter.ps1
```

- API: `http://localhost:8001`; Flutter Web: `http://localhost:7358`.
  Conservar `localhost` en ambos para cookies/CSRF.
- Ctrl+C en el launcher Flutter detiene solo la web. Tras editar Dart, detener
  y volver a ejecutar para recompilar; el launcher no ofrece hot reload.
- Una instalación nueva usa `scripts/init-env.ps1`, después `scripts/start.ps1 -Build`
  y prepara cuentas/datos propios. No sobrescribir `.env` ni ADMIN existentes.
- PostgreSQL Docker se publica en 5433 y Redis en 6380 desde Windows.
- Preferir comandos PowerShell sencillos, uno por uno, desde la carpeta apropiada.
  No asumir que los servicios siguen activos porque una evidencia anterior lo indica.

## Datos, credenciales y pruebas mutantes

- Preservar ADMIN, dataset beta, datos manuales y volúmenes. Para detener el entorno
  usar Ctrl+C o `docker compose stop`; **no usar `docker compose down -v`**.
- `.env`, `backend/.local/`, `.verification/`, `.cache/`, `.pub-cache/`, builds,
  storage y backups son locales y están excluidos. No versionar sus valores.
- Consultar `docs/carga-beta-8bis.md` para carga/check/cleanup y protección local.
  En NTFS/WSL, chmod no sustituye las ACL Windows.
- Preparar UUID/manifiesto frescos para aceptación mutante. No reutilizar fixtures
  retirados ni ejecutar esas pruebas sobre el dataset beta o el conjunto manual.
- Cleanup por UUID debe conservar ADMIN y abortar ante referencias ajenas.
- Desarrollo usa `corestream`/Redis db0; integración usa `corestream_test`/db15.
  Redis pub/sub no queda aislado por el índice de base.

## Verificación y evidencia

Ejecutar las comprobaciones afectadas por el cambio. Desde `movil/`, con las
dependencias preparadas y PUB_CACHE local cuando corresponda:

```powershell
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
```

Los tests live requieren manifiestos explícitos; seguir la guía antes de ejecutarlos.
Para backend, desde la raíz con Docker iniciado, seleccionar las suites apropiadas:

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend pytest tests/ --ignore=tests/integration -x -q
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend pytest tests/integration -x -q
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend ruff check app/ tests/
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend mypy app/
```

Para documentación y selección publicable, desde la raíz sin iniciar servicios:

```powershell
node scripts/verification/check-doc-links.mjs
node scripts/verification/check-repository.mjs
git diff --check
```

- Revisar también los enlaces de este archivo: el comprobador actual enumera
  README/guía/TODO/móvil y Markdown de docs/scripts, no AGENTS.md.
- Registrar fecha, comando, salida, resultado y alcance real. Mantener evidencia
  privada en `.verification/` y resumen sanitizado en `docs/estado-actual.md`.
- No presentar resultados históricos como suites reejecutadas ni sumar capturas
  reutilizadas como evidencia nueva. Demo/widget/CDP/API/SQL acreditan cosas distintas.
- Mantener los ocho xfail heredados de `test_api_contract.py` clasificados y strict
  hasta resolver y verificar sus contratos; no retirarlos para aparentar éxito.
- Actualizar guía, contratos, permisos y arquitectura cuando cambie su contenido.

## Git y destinos de publicación

- Inspeccionar estado, diff y remoto/rama antes de operar. Preservar trabajo ajeno.
- Crear commits o publicar solo cuando el usuario lo solicite. No hacer force push
  ni cambiar autenticación/configuración Git para resolver una publicación.
- El fork de entrega es `josenavarrete666/Corestream_Grupo1`, rama
  **`corestream-mobile`**: nuestro proyecto ocupa directamente la raíz de esa rama.
  `master` conserva la aplicación web; no modificarla al publicar la versión móvil.
- También existe una copia en `josenavarrete666/CorestreamApp_GP5`, bajo
  `corestream-docker/`; conservar sus carpetas de fases si se solicita actualizarla.
- No asumir que `origin` apunta al fork: la copia local puede seguir vinculada a
  `HealthyW/Corestream_APP`. Confirmar siempre destino y rama y verificar el resultado.
