# Contratos de API y estado de integración

Base: integración de etapas 7–8 y ampliación 8-Bis, `corestream-docker/`.
Inventario observado el **12 de octubre de 2026 (UTC)**: CoreStream API **1.0.0**,
80 paths / 103 operaciones HTTP; no es un recuento nuevo de la limpieza documental.
Procedencia y decisiones en [estado actual](estado-actual.md).

Documentos de ejecución:

- [Estado, decisiones y evidencia](estado-actual.md).
- [Manifiesto HTTP inicial](contratos-recorrido-inicial.json).
- [Matriz beta/API](matriz-beta-api.md) y [roles/permisos](roles-permisos.md).
- [Guía y datos de aceptación](../GUIA_EJECUCION.md).
- [Tareas pendientes de Equipo 1/Android](../TODO_SETUP.md).

Estos contratos están implementados para el recorrido inicial y ampliación beta,
comprobados en Edge en etapa 8. El almacenamiento protegido y aceptación Android
se acreditan en etapa 10. Los Word conservan los requisitos
objetivo, incluyendo capacidades que no existen en el backend disponible.

## 1. URL y transporte HTTP — 7.2

- `CS_API_URL` representa el **origen**, inicialmente `http://localhost:8001`,
  sin `/api` ni otro path. Cada solicitud usa un path absoluto `/api/...`.
  Validar scheme/host/puerto y rechazar una configuración con path/query/fragment
  inesperado; normalizar la barra final. No concatenar `/api` dos veces.
- Web inicial: `http://localhost:7358`. Mantener `localhost` en ambos servicios;
  cambiar solo uno a `127.0.0.1` cambia el host de cookies/CSRF.
- JSON de request/response en snake_case; IDs UUID como string; fechas ISO 8601
  con zona horaria, convertidas a hora local únicamente para presentación.
- Bearer access en solicitudes protegidas. Login/refresh no dependen de Bearer.
- Respetar barra final en rutas de colección y parámetros `skip/limit` reales.
  Las listas iniciales son arrays, no `{items,total}`. Cargar páginas hasta una
  página con menos de `limit` elementos; no inventar un total global.
- HTTP web: adaptador navegador de Dio con credenciales habilitadas y lector
  de cookie CSRF. Código de navegador separado de `dart:io` mediante imports
  condicionales. El cliente inicial conserva timeouts 10 s conexión / 20 s respuesta.
- Preflight desde 7358 comprobado: 200, origen explícito, credenciales `true`,
  Authorization/Content-Type/X-CSRF-Token permitidos. Cookies HttpOnly son
  gestionadas por el navegador, no por lectura de Set-Cookie desde Dart.

## 2. Operaciones del recorrido inicial

Los schemas de las respuestas tipadas están en OpenAPI. Las respuestas dict de
contador/lectura/logout se completaron mediante inspección de routers y pruebas.

| Operación | Método / path | Entrada | Éxito / respuesta |
|---|---|---|---|
| Login | POST `/api/auth/login` | email/password | 200 TokenResponse + cookies |
| Perfil | GET `/api/auth/me` | Bearer | 200 UserResponse |
| Renovación | POST `/api/auth/refresh` | cookies + X-CSRF-Token; sin body en el flujo elegido | 200 TokenResponse + cookies rotadas |
| Logout | POST `/api/auth/logout` | Bearer + cookie; sin body en flujo elegido | 200 `{"message":"Sesión cerrada"}` |
| Cambio obligatorio | POST `/api/auth/change-password` | Bearer, old_password/new_password | 200 mensaje; comprobar perfil/flag después |
| Aplicaciones | GET `/api/applications/` | Bearer, skip=0/limit=100, máximo 500 | 200 ApplicationResponse[] |
| Notificaciones | GET `/api/notifications/` | Bearer, skip=0/limit=50, máximo 100; unread_only opcional | 200 NotificationResponse[] |
| Contador | GET `/api/notifications/unread-count` | Bearer | 200 `{unread_count: int, user_id: UUID}` |
| Marcar una leída | POST `/api/notifications/mark-read` | Bearer, `{notification_ids:[UUID]}` | 200 `{marked_as_read:int,total_requested:int}` |
| Marcar todas | POST `/api/notifications/mark-all-read` | Bearer, sin body | 200 `{marked_as_read:int}` |
| Credencial WS | POST `/api/auth/ws-ticket` | Bearer, sin body | 200 `{ticket:string}` de un solo uso |

En lectura individual, `marked_as_read=1` y `total_requested=1` deben confirmarse
para el fixture elegido. Un 200 con cantidad cero no acredita esa operación.
Luego reconsultar lista y contador. Una página vacía es un resultado válido;
una respuesta ilegible o un fallo HTTP produce estado de error, no lista vacía.

## 3. Modelos, roles y permisos — 7.3

### Sesión y perfil

- TokenResponse: `access_token` string no vacío, `token_type=bearer`,
  `expires_in` segundos positivo cuando venga informado, `must_change_password`
  booleano. El schema permite expires_in nulo/ausente; usar renovación ante 401
  si no hay duración utilizable. No esperar refresh_token JSON.
- UserResponse: `id`, `email`, `full_name`, `role`, `is_active`, `created_at`;
  specialty/avatar_url/preferences son opcionales. Conservar must_change_password
  en estado de sesión, no perderlo al convertir a User Dart.
- Perfil como fuente del rol mostrado. Roles canónicos: ADMIN, TEAM_LEADER,
  DEVELOPER. TEAM_LEADER se mapea al líder interno; GROUP_LEADER queda como
  alias de datos demo/legado, no se emite como nuevo rol API.
- Rol desconocido, id inválido o dato obligatorio de tipo incorrecto: error
  de contrato y navegación protegida cerrada. No degradar automáticamente a developer.
- Usuario inactivo: bloquear UI de recursos y limpiar la sesión. El login
  actual devuelve 403 y refresh rechaza usuario inactivo; `get_current_user`
  no acredita por sí solo revocación global al desactivar una cuenta.

### Aplicaciones y notificaciones iniciales

- DTO API de aplicación con `id/name/is_active/created_at` y conteos
  `epic_count/pending_count/delayed_count`. pending_count representa **TODO**;
  no equivale a todos los abiertos. La respuesta no garantiza tickets_total ni
  tickets_done: el inicio API no muestra porcentajes de progreso inventados.
- DTO notificación: id/user_id/title/message/type/is_read/created_at,
  ticket_id opcional. El backend actual no ofrece incident_id.
- Mapear TICKET_ASSIGNED → asignación, QUESTION_RAISED → pregunta,
  TICKET_REDIRECTED → redirección, TICKET_COMPLETED → completado,
  STATUS_CHANGED/SYSTEM → aviso de sistema. Conservar raw type; un tipo futuro
  desconocido puede mostrarse como aviso genérico identificado, sin inventar acción.
- `unread_count` entero no negativo es el campo del contador; no usar cero
  cuando falta ese campo o hay un error de parseo.
- Acceso a notificaciones filtrado por usuario en servidor. Listar `/users/`
  requiere ADMIN/TEAM_LEADER; no es requisito para el login de DEVELOPER.

### Metadata de presentación — 8B.4

- `ApplicationResponse.color/icon`, ya existentes, alimentan el color y el
  monograma decorativo del proyecto. PC/AP/AL no son códigos de negocio;
  los recursos mantienen UUID como identidad.
- `UserResponse.specialty/preferences.avatar_color` alimentan la identidad
  del perfil, directorio y usuarios embebidos en responsables/eventos.
- `GET /api/tickets/team-members` añade `specialty` y `avatar_color`, opcionales
  con default null. Color válido `#RRGGBB`; valor inválido se normaliza a null.
  Proyecta solo esa preferencia y mantiene filtros de activos, roles trabajadores
  y exclusión del usuario actual. No expone el diccionario de preferencias.
- DEVELOPER conserva este selector y no consulta `/api/users/`. Flutter usa azul
  de respaldo para colores ausentes/ilegibles y carpeta cuando `icon` no contiene
  un monograma de 1–3 caracteres ASCII mayúsculos/dígitos. No inventa abreviaturas
  ni solicita imágenes externas. [Decisión y evidencia](estado-actual.md).

### Dominios posteriores

- Ticket desarrollo: COMPLETED → hecho; BLOCKED_QUESTION → bloqueado por
  pregunta, conservando estado original/motivo. Estados SUPPORT tienen otro
  flujo y no se convierten silenciosamente a TODO.
- Resolver pregunta usa `/resolve-question` con **resolution**; redirigir
  usa **justification**, no reason. PR opcional conforme al backend.
- Permisos de ticket combinan rol, asignación y estado: ADMIN gestiona, pero
  no inicia/completa trabajo. La visibilidad UI no sustituye los checks del router.
- Incidencias beta y backend no tienen una equivalencia completa de estados,
  severidades ni categorías. B02 de estado actual mantiene esa decisión con E3.

## 4. Ciclo de sesión — 7.4

### Web

1. Estado inicial **recuperando sesión**. Sin logout pendiente, intentar refresh
   con cookie y el CSRF legible; si no hay sesión válida, mostrar formulario.
2. Login por credenciales; guardar access únicamente en memoria y obtener perfil.
   Sin perfil válido, no entrar a recursos ni utilizar el selector demo como login API.
3. Si must_change_password está activo, mostrar cambio obligatorio y permitir
   logout. Conservar el flag de login/refresh aunque el perfil todavía no lo
   refleje; bloquear recursos/replay mientras esté activo. POST change-password,
   comprobar flag mediante GET me y reautenticar
   con la nueva contraseña tras cerrar la sesión propia. No afirmar cierre de
   todas las sesiones: esa política es requisito posterior de E1.
4. Ante 401 de una solicitud protegida, **una sola renovación compartida**
   entre peticiones concurrentes; leer CSRF actualizado, obtener access nuevo
   y reintentar la solicitud una vez. Excluir login/refresh/logout del bucle.
5. Cada login/logout cambia la generación de sesión. Resultados tardíos de
   refresh, recursos o WS de una generación anterior se descartan. Cancelar
   reintentos/timers y limpiar cachés/providers al cerrar o cambiar de usuario.
   Logout espera el login/refresh en curso antes del borrado remoto de cookies.
6. Refresh 401: volver a login. Refresh 403 de CSRF: estado explícito de sesión
   inválida, sin bucle ni conversión a permiso de negocio. Fallo de red se
   muestra como problema de conexión; no se informa revocación inexistente.

Cookies actuales: refresh_token **HttpOnly**, Path `/api/auth`; csrf_token
legible, Path `/`; SameSite Strict. Secure depende del entorno de producción.
Refresh cookie exige header X-CSRF-Token igual a csrf_token. Al renovar,
el backend revoca el refresh usado y entrega cookies refresh/CSRF nuevas.

### Logout

- Cerrar el WS propio, impedir nuevas operaciones y renovación automática,
  y llamar POST logout con Bearer y cookies, aunque no haya refresh JSON.
- Si access expiró y la cookie es válida, obtener access para revocar y
  reintentar logout una vez; mantener la UI de recursos cerrada durante ello.
- Éxito 200: limpiar estado y marcar **revocación confirmada**. El access
  anterior y la cookie de refresh anterior deben ser rechazados en la aceptación.
- Sin red/error de servidor: cerrar estado local y persistir únicamente una
  marca no secreta **logout pendiente**, impidiendo restauración automática
  por la cookie que aún puede existir. Al volver la red, resolver la revocación
  usando cookie/CSRF y después permitir un nuevo login. Si refresh ya no es
  válido, terminar la restauración pendiente sin afirmar una revocación nueva.
- No guardar access, refresh ni contraseña en SharedPreferences/localStorage.
  La marca pendiente es estado operativo no secreto. No confundir borrado local
  con baja FCM o revocación remota de otras sesiones.

### Android: contrato de transporte definido, validación nativa posterior

Reutilizar login/refresh/logout **por cookie** con un jar nativo por origen API:
capturar Set-Cookie, aplicar dominio/path/expiración, leer csrf_token del jar y
enviar X-CSRF-Token. Conservar rotación y eliminación de cookies. La persistencia
de credenciales del jar debe usar almacenamiento protegido de Android; access
permanece en memoria. Adaptador/jar en memoria y pruebas de dominio/path,
rotación/eliminación se implementaron en etapa 8; persistencia protegida y
aceptación de plataforma se verifican en etapa 10.

La alternativa refresh en body se mantiene para scripts/tests. Consume el
refresh pero no devuelve uno nuevo; no es el ciclo persistente elegido.
FCM, sesiones por dispositivo y biometría pertenecen a sus contratos de E1 en 9–10.

## 5. Errores HTTP

Normalizar en el cliente: error de red/timeout, sesión inválida, permiso,
validación, conflicto, rate limit, servidor y contrato JSON. Conservar status
y detalle útil; credenciales y tokens no se incluyen en mensajes/logs.

| Resultado | Comportamiento del cliente |
|---|---|
| 400 | Error de operación/negocio; mostrar detalle y conservar datos editables |
| 401 | Login inválido o sesión expirada/revocada; aplicar política de sesión, no reintento infinito |
| 403 | Cuenta desactivada, permiso o CSRF según operación; no renovar por cada denegación de negocio |
| 404 | Recurso/ruta inexistente; no representarlo como lista vacía satisfactoria |
| 409 | Conflicto; informar y permitir reconsulta/corrección |
| 422 | `detail` puede ser lista de errores; mapear loc/msg a campos de formulario |
| 429 | Respetar Retry-After si está presente; no reintentar inmediatamente |
| 5xx / timeout | Error visible y reintento controlado por usuario; no repetir automáticamente una mutación cuyo resultado se desconoce |
| JSON inválido | Error de contrato; no sustituir por métricas cero, fecha actual o rol predeterminado |

OpenAPI no enumera todos los HTTPException de los routers. Perfil sin Bearer
desde el puerto publicado respondió **401**, `{"detail":"Not authenticated"}`.
La matriz beta/API registra tratamiento y límites de los dominios integrados.

## 6. WebSocket — 7.5

HTTP: POST `/api/auth/ws-ticket`, Bearer; respuesta ticket opaco, TTL **15 s**.
WS: `ws://localhost:8001/api/ws/{user_id}?ticket=<ticket>` en desarrollo;
https se transforma en wss. Ticket nuevo por cada intento de conexión y
user_id del perfil, nunca JWT en query. No es `/ws/mobile/notifications`.

Transporte común web/nativo implementado con `web_socket_channel` 3.0.3;
aceptación web y pruebas de sockets registradas en etapa 8.

| Mensaje del servidor | Tratamiento |
|---|---|
| `{type:connected,message,timestamp}` | Marcar conexión lista y reconsultar bandeja/contador |
| `{type:ping,message,timestamp}` | Enviar `{type:pong}`; no crear notificación |
| `{type:notification,data,timestamp}` | Payload bajo data; si tiene id/type/message/created_at, mapear aviso y reconsultar HTTP |
| `{type:notification,data:{type,data,timestamp},timestamp}` | Variante de evento de dominio; invalidar recursos, no inventar un ID de notificación |
| `{type:update,data,timestamp}` | Invalidación de datos de tickets; no crear un AppNotification ficticio |

Eventos de usuario `{type:activity}` como máximo una vez/minuto mientras hay
interacción real; pong no reinicia la inactividad. Heartbeat cada ~30 s,
backstop de inactividad configurado inicialmente a 1200 s.

- Ticket ausente/inválido/usado o usuario distinto: rechazo de handshake;
  1008 en servidor. Navegador puede observar cierre genérico/1006: no depender
  de leer el motivo exacto para pedir ticket nuevo con límite de reintentos.
- 4000: inactividad; esperar acción explícita del usuario para reconectar.
- 1011/transporte interrumpido: backoff limitado, 2/4/8/16/30 s, sin superar
  30 s; ticket nuevo cada intento. Tras cinco reintentos fallidos, esperar
  reanudación manual. Cancelar al hacer logout/cambiar sesión.
- Al reconectar, resincronizar por HTTP; pub/sub no garantiza replay.
- El servidor autentica al abrir, sin revalidación periódica de jti/usuario.
  El cierre remoto integral se registra como B07, no se acredita por cerrar
  solo el socket de este cliente. FCM es un mecanismo de entrega independiente.

## 7. BFF y contratos compartidos — 7.6–7.8

El recorrido inicial usó aplicaciones/notificaciones. La ampliación usa las
pantallas beta con `ApiRepository` completo y rutas existentes; no llama a BFF
ausentes. El login actual conserva su contrato y no consulta directorio antes
de autenticar. La demo mantiene datos y permisos simulados independientes.

Los BFF objetivo bajo `/api/mobile` para dashboard/tablero/detalle/workload
siguen pendientes de diseño completo con E2/E3. No existen en esta versión.
Su ausencia no bloquea la composición actual acreditada; no se desarrolla ese
BFF como parte de 8.11–8.18.
Dispositivos/FCM requieren modelos, migraciones, API y ciclo de sesión E1.
Consultar B01–B10 del [estado actual](estado-actual.md) para responsables y pendientes.

Perfil actual no incluye client_id, empresa activa, planes ni flags. Esas
capacidades necesitan contrato y autorización transversal en etapa 9. La base
inicial local no acredita aislamiento multiempresa ni políticas comerciales.
Eliminar un dispositivo push no revoca una sesión; biometría desbloquea una
sesión autenticada y no reemplaza al login del servidor.

La integración está aceptada con evidencia de cliente, servidor y datos,
consolidada en [estado actual](estado-actual.md). Los requisitos posteriores
tienen aceptación propia; la base actual no los da por completados.

## 8. Contratos beta/API implementados — 8.11–8.18

Tabla completa: [matriz beta/API](matriz-beta-api.md). Se mantiene el login,
cliente HTTP/WS y manejo de sesión anterior; las nuevas vistas no introducen
cookies, tokens ni un coordinador alternativo.

- Proyectos: aplicaciones paginadas, GET `/api/epics/by-app/{app_id}` con todos
  los DEVELOPMENT. Progreso = COMPLETED/total; pendientes = total − COMPLETED,
  no `applications.pending_count` (solo TODO). Siete días por `completed_at`;
  sin fecha suficiente, `—`. UUID visibles; sin T/INC/código ficticios.
- Tickets: GET detalle/épica/eventos y PUT subtareas; creación POST, asignación
  PUT, `/start`, `/complete`, `/question`, `/resolve-question`, `/redirect`.
  Payloads/resultados/roles según matriz. PR opcional; ADMIN no trabaja;
  developer no resuelve. Pregunta/resolución 2000, redirección 1000, título 255.
- Directorio: gestores GET `/api/users/`; developer GET
  `/api/tickets/team-members`. Errores visibles, sin sustituirlos por vacío.
- Incidentes: `/api/incidents/`, cuatro estados REPORTED/INVESTIGATING/MITIGATED/
  RESOLVED y P1/P2/P3. PATCH asignación y PATCH status son operaciones separadas.
  Sin autoasignación developer, revisión/cierre/reapertura/categorías/comentarios
  equivalentes. No mapear SUPPORT ni MITIGATED a dominio/estado demo distinto.
- Equipo: asignaciones DEVELOPMENT e incidentes abiertos por usuario autorizado.
  No equiparar `/teams` ni otro agregado estadístico a workload.
- Notificaciones: conservar **título API**, UUID, propietario y tipo; aviso/bandeja
  comparten presentación. Antes de navegar se verifica DEVELOPMENT; SUPPORT se
  lee y explica su límite. Evento `update` invalida, sin fabricar notificación.
- Snapshot por sesión/revisión, páginas deduplicadas y fan-out secuencial.
  Un cambio de sesión descarta resultados viejos. Reconectar WS resincroniza HTTP.
  Puede haber nuevas lecturas por revisión/evento; no se promete una sola petición
  de cada ruta durante toda la sesión.
- Mutaciones bloquean envío simultáneo del mismo recurso. Tras fallo ambiguo
  se invalida cache y se reconsulta; no se repite automáticamente el POST ni se
  declara éxito porque cambió un widget. 403 de negocio conserva sesión.

HTTP nativo, Edge y SQL acreditados en B01–B18; fixture manual conservado y
fixture de aceptación retirado. No fue necesario modificar negocio backend.
