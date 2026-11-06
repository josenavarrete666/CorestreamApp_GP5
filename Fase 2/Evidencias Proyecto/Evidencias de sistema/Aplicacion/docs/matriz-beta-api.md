# Matriz de vistas y acciones beta/API

Estado: implementación y aceptación B01–B18 ejecutadas; resultados y procedencia
en [estado actual](estado-actual.md). Integración autorizada el 12-10-2026;
presentación/interacción 8-Bis aceptadas el 13-10-2026.

## Referencia y criterio

La referencia visual es `movil/lib/ui/` de la beta original (solo lectura).
Se reutilizan `HomeShell`, tarjetas `CsCard`, avatares, chips, pestañas,
encabezados, paneles, avisos superiores y `core/theme.dart` de la copia.
El login actual, recuperación, cambio obligatorio y logout pendiente se
conservan. La API actual determina datos, estados y permisos; no hay BFF
`/mobile` registrado. Incidentes `/api/incidents/` son el dominio de Incidencias;
los tickets SUPPORT tienen otro ciclo y no se convierten en incidentes.

## Vistas, consultas y acciones

| Vista / acción beta | Contrato existente | Rol / condición | Adaptación y comprobación prevista |
| --- | --- | --- | --- |
| Inicio / Mi trabajo | GET `/api/applications/`, `/api/epics/by-app/{app_id}`, `/api/incidents/` | Los tres roles autenticados | Composición Flutter, tickets DEVELOPMENT; asignaciones para Mi trabajo. B01/B02/B03 |
| Proyectos / progreso | Aplicaciones paginadas; épicas con todos sus tickets | Los tres roles | Progreso COMPLETED/total, pendientes todo lo no completado; `pending_count` cuenta únicamente TODO y no se usa como total pendiente. B04 |
| Tablero / épicas | GET `/api/epics/by-app/{app_id}` | Los tres roles | Orden `order_index`, UUID; sin numeración T ficticia. B05 |
| Detalle | GET `/api/tickets/{id}`, GET `/api/epics/{id}`, GET `/api/tickets/{id}/events?skip&limit` | Los tres roles | Responsable embebido; historial cronológico completo deduplicado; identidad usuario nula explícita. B06 |
| Tiempo | `time_spent_seconds`, `timer_started_at`, `completed_at`, `block_reason` del ticket | Lectura autenticada | Acumulado más tiempo desde inicio UTC real; no sintetizar inicio, tiempo bloqueado histórico o fecha final. B06/B08 |
| Crear ticket | POST `/api/tickets/`: `epic_id,title,priority,assignee_id` | ADMIN / TEAM_LEADER | Panel beta, UUID y prioridad reales, validar título y resultado. B07 |
| Asignar / reasignar | PUT `/api/tickets/{id}`: `assignee_id` | ADMIN / TEAM_LEADER | Usuarios activos GET `/api/users/`; no afirmar persistencia de comentario inexistente. B07 |
| Iniciar | POST `/api/tickets/{id}/start` | TEAM_LEADER / DEVELOPER, TODO propio o sin asignado | ADMIN no ejecuta trabajo. Sin asignado se reclama en servidor. REDIRECTED no se inicia por esta ruta. B08/B10 |
| Completar | POST `/api/tickets/{id}/complete`: `pr_link` opcional | TEAM_LEADER / DEVELOPER asignado, IN_PROGRESS | COMPLETED; no exigir PR cuando backend permite vacío. Fallo real visible, no convertirlo en error de PR. B08 |
| Pregunta | POST `/api/tickets/{id}/question`: `question_text` 10–2000 caracteres | No ADMIN, asignado, IN_PROGRESS | BLOCKED_QUESTION; mostrar pregunta real y detener tiempo. B08 |
| Resolver pregunta | POST `/api/tickets/{id}/resolve-question`: `resolution` 5–2000 | ADMIN / TEAM_LEADER, BLOCKED o BLOCKED_QUESTION | Developer no resuelve su propia pregunta. B08/B10 |
| Redirigir | POST `/api/tickets/{id}/redirect`: `to_user_id,justification` 10–1000 | Asignado o ADMIN / TEAM_LEADER según servicio actual | IN_PROGRESS vuelve a TODO; conservar estado de otros tickets. Destinos GET `/api/tickets/team-members`, sin acceso developer al directorio restringido. B09 |
| Subtarea | PUT `/api/tickets/{id}/subtasks/{subtask_id}`: `is_completed` | ADMIN / TEAM_LEADER o asignado | Verificar pertenencia y respuesta. B08/B10 |
| Lista / filtros de incidentes | GET `/api/incidents/?skip&limit` | Los tres roles | REPORTED, INVESTIGATING, MITIGATED, RESOLVED; P1/P2/P3. No UNDER_REVIEW para mitigación. B11 |
| Detalle incidente | GET `/api/incidents/{id}` | Los tres roles | Aplicación / creador / responsable nullable; entorno y mitigación reales. Sin INC ficticio, categoría ni comentarios. B11 |
| Asignar incidente | PATCH `/api/incidents/{id}`: `assigned_to_id` | ADMIN / TEAM_LEADER | Una llamada, sin transición implícita a investigación. B12 |
| Estado incidente | PATCH `/api/incidents/{id}/status`: `status` | Autenticado (contrato actual) | Elegir únicamente los cuatro estados existentes; no añadir reglas beta por rol. B12 |
| Tomar incidente | Sin ruta de autoasignación developer | No disponible | Explicación visible; no encadenar asignación y estado como éxito atómico. B11/B12 |
| Revisión / cerrar / reabrir / categoría / comentarios | Sin contrato equivalente en incidentes | No disponible | Explicación visible, conservar demo como referencia. B11 |
| Equipo / carga | GET `/api/users/` + DEVELOPMENT completos + incidentes completos | ADMIN / TEAM_LEADER | Asignaciones activas / en progreso / bloqueadas / incidentes abiertos, no `/teams` ni otro tipo de estadísticas. B13 |
| Directorio de selección | GET `/api/users/` gestores; GET `/api/tickets/team-members` developer | Según operación | Carga/errores visibles; no esconder errores como lista vacía. B07/B09/B13 |
| Campana / bandeja / lectura | GET `/api/notifications/`, GET `/unread-count`, POST `/mark-read`, POST `/mark-all-read` | Propietario autenticado | Conservar 8.1–8.10; leer UUID/tipo de ticket antes de navegar. SUPPORT muestra límite explícito. B14 |
| Aviso superior / actualización | Ticket WS POST `/api/auth/ws-ticket`, `/api/ws/{user_id}?ticket=...` | Usuario sesión vigente | Aviso beta real, invalidación y HTTP tras reconexión, sin simulación en API. B14/B16 |
| Ajustes | Perfil `/api/auth/me`, preferencias ES/EN y tema local, logout existente | Sesión vigente | Misma presentación beta, simulación solo demo. B15/B16 |

## Datos ausentes y semántica

- `COMPLETED` se presenta como completado; se conserva el estado API original.
  BLOCKED y BLOCKED_QUESTION son bloqueos diferenciables en el modelo API.
- Incidentes usan estados nuevos de presentación con nombres wire reales;
  no se sobrecargan estados demo. P1/P2/P3 conservan su etiqueta exacta.
- Número humano y código de proyecto no existen en los contratos actuales:
  omitir número/código y mostrar UUID en detalle. `color/icon` permite monogramas
  decorativos PC/AP/AL, con carpeta de respaldo si falta metadata válida.
- Los siete días se calculan de `completed_at`, nunca de `updated_at` ni del total
  histórico. Si hay completados sin fecha, mostrar métrica no disponible.
- Tiempos y eventos se validan; no fabricar eventos para datos que no se registraron.
- Consultas compartidas por sesión y revisión; fan-out secuencial acotado. Las
  páginas se deduplican por UUID, detectando falta de avance. Logout/cambio de
  sesión invalida cachés y resultados de operaciones compuestas antiguas.
- Lecturas del servidor no constituyen aislamiento multiempresa; eso es E1
  posterior. Las reglas aquí descritas son las implementadas actualmente.

## Criterios de aceptación ampliada

Resultado y procedencia (Flutter Edge, HTTP/SQL real o test controlado) en
[estado actual](estado-actual.md). La tabla conserva los criterios de integración;
el login se rediseñó posteriormente en 8B.5 sin cambiar su ciclo de sesión.

| ID | Recorrido y resultado exigido |
| --- | --- |
| B01 | ADMIN: login actual → Inicio beta, cuatro pestañas, datos comparables con API |
| B02 | TEAM_LEADER: cuatro pestañas, carga/acciones de gestión, trabajo solo propio |
| B03 | DEVELOPER: Mi trabajo y tres pestañas; sin consulta anticipada a `/users/` |
| B04 | Aplicaciones y métricas con TODO, IN_PROGRESS, BLOCKED_QUESTION y COMPLETED; casos vacíos/paginados |
| B05 | Proyecto → épica → tablero → detalle con mismos UUID y orden real |
| B06 | Responsable/subtareas/historial/temporizador; sin número ni fecha inventados |
| B07 | Crear y asignar en panel beta → SQL → reconsulta/relogin; doble envío bloqueado |
| B08 | Iniciar → subtarea → pregunta → resolución líder → completar; estados/tiempo/eventos persistidos |
| B09 | Redirección justificada → nuevo asignado TODO; destino y notificación reales |
| B10 | Acciones ajenas/ADMIN trabajo/developer resolución denegadas; 403 conserva sesión |
| B11 | Incidentes reales, filtros cuatro estados, P1/P2/P3, límites beta visibles |
| B12 | Asignación gestor y cambio de estado existente, recarga verifica; sin autoasignación ficticia |
| B13 | Equipo con asignaciones reales; todos los usuarios/páginas sin duplicados |
| B14 | Evento WS → aviso beta/campana/bandeja → tipo de recurso validado → lectura persistente |
| B15 | Oscuro/claro, ES/EN y tamaños 390×844 / 1280×900; navegación/paneles de referencia, login conservado |
| B16 | Detalle/panel abierto → logout/cambio de usuario: rutas, cachés, avisos y resultados antiguos retirados |
| B17 | Error de red/API y validación visible; reintento GET, mutación ambigua reconsultada sin éxito ficticio |
| B18 | Regresión demo, sesión inicial, análisis Flutter; checks backend para cualquier corrección comprobada |

## Datos y evidencia

Fixture ampliado con manifiesto privado en `backend/.local/`, UUID por ejecución,
ADMIN existente conservado, leader/developer y aplicación/épicas/tickets/subtareas/
incidentes/notificaciones rastreados. Preparación, comprobación y retiro con
guardias development; no borrar referencias ajenas. Un conjunto manual se mantiene
y se documenta aparte del conjunto de aceptación retirado. Nunca publicar claves.

El [estado actual](estado-actual.md) conserva los resultados del recorrido inicial,
B01–B18 y 8-Bis. Fuentes de contrato: routers/schemas/services actuales y
[roles/permisos](roles-permisos.md). Preparación/check/cleanup en
[guía](../GUIA_EJECUCION.md), pendientes en [TODO](../TODO_SETUP.md).
Las diferencias estáticas se reproducen por HTTP antes de modificar backend.
