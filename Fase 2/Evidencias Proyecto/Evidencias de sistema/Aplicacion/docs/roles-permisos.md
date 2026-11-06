# Roles y permisos del backend actual

Resumen de autorización de la base `9ccd000`, contrastado con los routers y
helpers actuales. Las reglas se aplican en el servidor: ocultar un botón en
Flutter no reemplaza la autorización. Payloads, rutas y estados en
[contratos API](contratos-api.md) y [matriz de acciones](matriz-beta-api.md).

## Roles y mecanismo

- **ADMIN:** administra identidades y estructura; no inicia, completa ni plantea
  preguntas de trabajo sobre tickets.
- **TEAM_LEADER:** gestiona proyectos y trabajo del equipo; ejecuta trabajo propio.
  Puede invitar únicamente DEVELOPER, no crear otro líder/ADMIN por invitación.
- **DEVELOPER:** ejecuta trabajo propio, con asignación y estado válidos.

Roles definidos en `backend/app/models/role.py` y tabla `roles`. GROUP_LEADER es
alias demo/legado, no un nuevo rol emitido por la API. `require_role` en
`backend/app/middleware/auth.py` es la dependencia utilizada por los routers;
el decorador histórico `require_permissions` no debe asumirse como mecanismo activo.

## Proyectos, épicas y equipos

| Recurso / acción | ADMIN | TEAM_LEADER | DEVELOPER |
|---|---|---|---|
| Aplicaciones: listar/ver | Sí | Sí | Sí |
| Aplicaciones: crear/editar | Sí | Sí | No |
| Aplicaciones: borrar | Sí | No | No |
| Épicas: listar/ver | Sí | Sí | Sí |
| Épicas: crear/editar/reordenar | Sí | Sí | No |
| Épicas: borrar | Sí | No | No |
| Equipos: listar/ver/crear/editar/agregar/quitar miembros | Sí | Sí | No |
| Equipos: borrar | Sí | No | No |

Rutas de épicas bajo `/api/epics/` y consulta `/api/epics/by-app/{app_id}`.
`/api/teams` agrupa miembros/épicas; no es el endpoint de carga de trabajo de la
pantalla Equipo. Borrar un equipo deja `epics.team_id` nulo, no elimina las épicas.

## Tickets DEVELOPMENT

| Acción | ADMIN | TEAM_LEADER | DEVELOPER |
|---|---|---|---|
| Listar/ver/eventos | Sí | Sí | Sí |
| Crear | Sí | Sí | No |
| Editar campos/mover/reordenar | Sí | Sí | Solo asignado |
| Asignar/reasignar | Sí | Sí | No |
| Borrar | Sí | No | No |
| Iniciar | No | Propio o sin asignado | Propio o sin asignado |
| Completar/plantear pregunta | No | Solo asignado | Solo asignado |
| Resolver pregunta bloqueante | Sí | Sí | No |
| Redirigir | Sí | Sí | Solo asignado |
| Gestionar subtareas | Sí | Sí | Solo asignado del ticket padre |

Estas condiciones también requieren estado de negocio válido. Iniciar un ticket
libre lo reclama en el servidor; no permite apropiarse de uno asignado a otro.
Completar admite PR opcional. Resolver usa
`POST /api/tickets/{id}/resolve-question` con `resolution`; redirigir usa
`POST /api/tickets/{id}/redirect` con `to_user_id` y `justification`.

Helpers compartidos en `backend/app/services/ticket_permissions.py`:
`require_non_admin`, `require_admin_or_leader`, `assert_can_manage_ticket`,
`assert_is_current_assignee` y `claim_or_assert_assignee`. Las reglas de
redirección están en su router/servicio, montado antes del router de tickets.

Gestores consultan `/api/users/`; el selector developer usa
`/api/tickets/team-members`, excluyendo ADMIN, inactivos y usuario actual.
Solo proyecta metadata opcional specialty/avatar_color, no preferencias completas.

## Identidad e invitaciones

| Acción | ADMIN | TEAM_LEADER | DEVELOPER |
|---|---|---|---|
| Perfil propio autenticado | Sí | Sí | Sí |
| Directorio/listado de usuarios | Sí | Sí | No |
| Consultar usuario por ID (GET /api/users/{id}) | Sí | Sí | Sí |
| Crear usuario directamente/cambiar rol/resetear clave ajena | Sí | No | No |
| Editar/borrar usuario ajeno | Sí | No | No |
| Crear invitación | Cualquier rol | Solo DEVELOPER | No |
| Listar invitaciones pendientes | Todas | Solo propias | No |
| Reenviar invitación | Cualquiera | Solo propias DEVELOPER | No |

Consulta y aceptación del token de invitación son públicas. El primer ADMIN se
crea explícitamente con `app.scripts.create_admin`; no hay alta pública de usuarios
ni cuentas/contraseñas predeterminadas al clonar. El reenvío reemplaza el token y
renueva su expiración. Las rutas backend existentes no implican que todos esos
formularios ya estén integrados en Flutter.

## Notificaciones, documentos y reuniones

- **Notificaciones:** listar, contar y marcar se filtran por `current_user.id`.
  Un usuario no manipula las notificaciones de otro. Títulos/UUID vienen de API;
  se valida el dominio antes de navegar.
- **Documentos:** autenticados pueden listar/ver/subir/descargar/traducir;
  borrado permitido al autor o gestores. Confirmar una subida requiere el usuario
  que pidió su URL. Contrato upload-url → carga directa → confirm; download-url
  para descarga. GCS usa URLs firmadas; desarrollo utiliza el adaptador local.
  Estas capacidades backend no están acreditadas como pantallas Flutter actuales.
- **Reuniones:** todos los roles listan/ven; ADMIN y TEAM_LEADER crean, editan y
  registran asistencia. Edición PATCH; asistencia es un objeto, no una lista.

## Incidencias y SUPPORT

| Recurso / acción | ADMIN | TEAM_LEADER | DEVELOPER |
|---|---|---|---|
| Incidencias: crear/listar/ver | Sí | Sí | Sí |
| Incidencias: editar/asignar | Sí | Sí | No |
| Incidencias: cambiar estado | Sí | Sí | Sí |
| SUPPORT: crear/listar/ver/investigar/resolver | Sí | Sí | Sí |
| SUPPORT: asignar | No | Sí | No |

El cambio de estado de incidencia permite autenticados sin restricción de
asignación en el contrato actual; no se debe inventar una regla adicional de UI.
Asignar (`assigned_to_id`) y cambiar estado son PATCH separados. Solo existen
REPORTED/INVESTIGATING/MITIGATED/RESOLVED y P1/P2/P3, sin autoasignación developer.
SUPPORT es otro dominio; no se transforma en incidente ni en DEVELOPMENT.

## Verificación y límites de seguridad

Pruebas backend: `backend/tests/integration/test_rbac.py` y `test_tickets.py`.
La aceptación real verificó denegaciones para ADMIN trabajando, developer
trabajando sobre ticket ajeno y developer resolviendo preguntas. El estado y
la procedencia de esas ejecuciones están en [estado actual](estado-actual.md).

El login/refresh rechaza usuarios inactivos, pero la dependencia común y el
WebSocket no acreditan una política global de desactivación/revocación de todas
las sesiones. Multiempresa, planes, auditoría y sesiones por dispositivo son
requisitos pendientes de Equipo 1. Las consultas autenticadas actuales no
prueban aislamiento por empresa.
