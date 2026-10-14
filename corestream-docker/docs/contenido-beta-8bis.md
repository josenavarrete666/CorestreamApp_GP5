# Contenido beta — inventario y correspondencia, 8B.2

Correspondencia definida el **12 de octubre de 2026 (UTC)**. Conserva el contenido
y las decisiones usadas por la [carga persistente](carga-beta-8bis.md).
Esta revisión de fuentes es distinta de la aceptación API/SQL y visual posterior,
cuyos resultados y criterios F01–F15 están en [estado actual](estado-actual.md).

## 1. Fuente y conjunto delimitado

La referencia es `_seed()` de `../corestream/movil/lib/data/demo_repository.dart`
y los valores por defecto de sus modelos. La copia versionada de
[DemoRepository](../movil/lib/data/demo_repository.dart), líneas 61–296,
conserva ese seed sin diferencias frente al original. El diff completo solo
contiene `setSession` y una adaptación nullable fuera del seed. Los títulos,
descripciones, preguntas, comentarios, justificaciones y mensajes se toman
literalmente de esa fuente, conservando acentos, signos, idioma y enlaces.
Los valores por defecto se verificaron en los [modelos demo](../movil/lib/models/models.dart).

| Elemento del seed | Cantidad | Destino |
|---|---:|---|
| Personas | 5 | `users`; cuatro cuentas nuevas y ADMIN existente |
| Proyectos | 3 | `applications` |
| Épicas | 5 | `epics` |
| Tickets | 9 | `tickets`, todos `DEVELOPMENT` |
| Subtareas | 20, de ellas 9 completadas | `subtasks` |
| Eventos de tickets | 19 | `ticket_events` |
| Incidencias | 5 | `incidents`, dominio separado de SUPPORT |
| Comentario de incidencia | 1 | Contexto textual de `i1` y procedencia del manifiesto |
| Mensajes iniciales de notificación | 5 plantillas / 8 entregas | `notifications`, una fila por destinatario |

Las ocho notificaciones incluyen **3 leídas y 5 no leídas**. Las cuentas Ana y
Luis reciben tres cada una; Diego recibe dos; Sofía y Marco no reciben mensajes
iniciales. `_runSimStep()` y el temporizador demo no forman parte del conjunto:
sus incidencias, tickets y modificaciones posteriores no se precargan.

Los alias `u1`, `a1`, `t1`, etc. son claves de procedencia para la importación,
no identificadores válidos de la API. La copia versionada permite preparar el
contenido en otra clonación sin depender de la carpeta hermana original.

## 2. Personas, roles e identidad visual — F12/F14

Fuentes de destino: [User](../backend/app/models/user.py) y
[UserResponse/UserUpdate](../backend/app/schemas/user.py).

| Alias | Nombre | Rol API | Correo acordado | Especialidad literal | Color |
|---|---|---|---|---|---|
| u1 | Ana Torres | ADMIN existente | `a.torres@example.com` | Arquitectura de soluciones | `#4C8DFF` |
| u2 | Luis Vega | TEAM_LEADER | `l.vega@example.com` | Backend · Líder equipo Pagos | `#8B7CF6` |
| u3 | Diego Ramos | DEVELOPER | `d.ramos@example.com` | Frontend · Vue / TypeScript | `#2FBF71` |
| u4 | Sofía Márquez | DEVELOPER | `s.marquez@example.com` | Full-stack · Integraciones | `#F2A93B` |
| u5 | Marco Ibáñez | DEVELOPER | `m.ibanez@example.com` | QA · Automatización | `#F0554E` |

- `fullName → full_name`, `specialty → specialty`; los roles apuntan a las
  filas reales de `roles`. `groupLeader/GROUP_LEADER → TEAM_LEADER`.
- `u1` resuelve al UUID del ADMIN del manifiesto local vigente. Se conserva
  UUID, rol, hash/contraseña, fecha de creación y estado de cambio obligatorio.
  Se actualizan nombre, correo, especialidad y metadata visual según lo acordado.
- La API `UserUpdate` no admite correo: el cambio de Ana requiere la herramienta
  local de 8B.3, con comprobación de unicidad y actualización de los manifiestos
  que referencian ese mismo UUID. No se añade una ruta de cambio de correo.
- Para u2–u5, crear usuarios activos con contraseñas locales generadas y
  `must_change_password=False` como cuentas de ejemplo. La beta no define
  contraseñas ni correos; las direcciones anteriores son las acordadas, no
  información descubierta en el seed. El alta local no sustituye el flujo de
  invitaciones de la aplicación ni crea otro ADMIN.
- Persistir el color RGB en `preferences.avatar_color` como `#RRGGBB`,
  combinándolo con las preferencias existentes de Ana. No guardar un color
  como URL ni fabricar imágenes; las iniciales se calculan desde `full_name`.
- La especialidad «Líder equipo Pagos» es texto del perfil: no implica un Team,
  membresía, propietario de aplicación ni restricción RBAC nueva.

### Compatibilidad identificada para 8B.4

[ApiProfile](../movil/lib/models/api_models.dart) ya lee especialidad, pero
omite el color; [apiTeamMember](../movil/lib/models/api_domain_models.dart)
omite ambos. `UserResponse` sí transmite especialidad y preferencias.
Sin embargo, [TeamMemberResponse](../backend/app/schemas/ticket_redirection.py)
y su [router](../backend/app/routers/ticket_redirection.py) solo transmiten
id/nombre/correo/rol. Para reproducir los selectores developer se necesita una
compatibilidad aditiva: `specialty` y `avatar_color` opcionales en esa respuesta,
con color obtenido de `preferences.avatar_color`, y adaptadores coherentes para
perfil, directorio, responsable y eventos. No consultar `/users/` con un developer
ni exponer todas las preferencias a través del selector.

## 3. Proyectos y épicas — F05/F06/F07

Destino: [Application](../backend/app/models/application.py),
[ApplicationResponse](../backend/app/schemas/application.py) y
[Epic](../backend/app/models/epic.py).

| Alias | Nombre literal | Abreviatura decorativa | `color` | Épicas | Tickets |
|---|---|---|---|---|---:|
| a1 | Portal Clientes | PC | `#4C8DFF` | e1, e2 | 4 |
| a2 | API Pagos | AP | `#2FBF71` | e3, e4 | 3 |
| a3 | App Logística | AL | `#8B7CF6` | e5 | 2 |

La beta no define descripciones, fechas de creación ni propietarios para estos
proyectos. `description=null`, `is_active=True`; `owner_id` será Ana como
propietaria técnica de la carga local, con procedencia explícita. Persistir
PC/AP/AL en `Application.icon` como texto decorativo, permitido por el campo
actual. En 8B.4 se presentará como monograma de dos letras, no como `code` de
negocio ni identificador buscable. Los UUID continúan identificando recursos.
No completar descripciones con texto inventado.

| Alias | `application_id` | `title` literal | `order_index` | Tickets en orden |
|---|---|---|---:|---|
| e1 | a1 | Autenticación y seguridad | 0 | t1, t2 |
| e2 | a1 | Panel de autogestión | 1 | t3, t4 |
| e3 | a2 | Conciliación bancaria | 0 | t5, t6 |
| e4 | a2 | Webhooks de pago | 1 | t7 |
| e5 | a3 | Seguimiento de flotas | 0 | t8, t9 |

`Epic.name → title`, `projectId → application_id`. Descripción, vencimiento y
equipo de las épicas quedan nulos; `is_collapsed=False` es el valor técnico
inicial. El orden de tickets y subtareas se materializa con índices desde cero
dentro de su padre, siguiendo la lista del seed.

## 4. Tickets, estados y fechas — F04/F07/F08

Destino: [Ticket](../backend/app/models/ticket.py) y
[TicketResponse](../backend/app/schemas/ticket.py). `D` y `H` significan días y
horas respecto de **T0**, la fecha UTC de referencia fijada una sola vez en 8B.3.
El número beta se conserva en la procedencia, no se convierte en UUID ni se
añade al título: la API actual no tiene un campo de numeración humana.

| Alias / número beta | Título literal | Épica / índice | Autor → responsable | Estado destino | Prioridad | Creación / vencimiento |
|---|---|---|---|---|---|---|
| t1 / 132 | Implementar login con doble factor (TOTP) | e1 / 0 | u2 → u3 | IN_PROGRESS | HIGH | −4D / +2D |
| t2 / 128 | Bloqueo de cuenta tras 5 intentos fallidos | e1 / 1 | u2 → u4 | BLOCKED_QUESTION | MEDIUM | −6D / +1D |
| t3 / 141 | Descarga de facturas en PDF desde el panel | e2 / 0 | u1 → ninguno | TODO | MEDIUM | −2D / +6D |
| t4 / 139 | Editar datos fiscales con validación de NIF/CIF | e2 / 1 | u2 → u5 | COMPLETED | LOW | −9D / −1D |
| t5 / 145 | Matching automático de transferencias SEPA | e3 / 0 | u2 → u4 | IN_PROGRESS | URGENT | −8D / −1D |
| t6 / 143 | Alertas de descuadre superior a 50 € | e3 / 1 | u1 → u3 | TODO | HIGH | −3D / +4D |
| t7 / 137 | Reintentos exponenciales en webhooks fallidos | e4 / 0 | u2 → u3 | TODO, con redirección histórica | HIGH | −7D / +3D |
| t8 / 146 | Mapa en vivo con posiciones GPS cada 30 s | e5 / 0 | u1 → u5 | IN_PROGRESS | MEDIUM | −5D / +9D |
| t9 / 134 | Firma digital de albaranes en la entrega | e5 / 1 | u1 → ninguno | TODO | LOW | −1D / +14D |

Las nueve descripciones se copian completas del seed. `created_at` se obtiene
del evento CREATED; `due_date` del plazo explícito. Prioridades low/medium/high/
urgent corresponden exactamente a LOW/MEDIUM/HIGH/URGENT. `done → COMPLETED`,
`todo → TODO`, `inProgress → IN_PROGRESS`.

### Adaptaciones de estado declaradas

- **t2:** el bloqueo procede de una pregunta explícita sin resolución. Por ello
  se usa BLOCKED_QUESTION, no un bloqueo genérico. `block_reason` contiene la
  pregunta literal; `blocked_at=T0−5H`; `blocked_question` puede quedar nulo,
  siguiendo la escritura actual de la máquina de estados. No fabricar respuesta.
- **t7:** la beta conserva REDIRECTED y permite iniciar desde ese estado. En la
  API [canStart](../movil/lib/models/api_domain_models.dart) requiere TODO;
  la [redirección real](../backend/app/services/ticket_redirection.py) devuelve
  a TODO un ticket en progreso. Se importa como TODO con responsable Diego y
  su evento REDIRECTED. Conservar `beta_status=REDIRECTED` en la procedencia
  del evento/manifiesto. Es una adaptación operativa explícita, no equivalencia
  literal ni una transición nueva ejecutada. El estado previo a la redirección
  no figura en el seed: no inventar IN_PROGRESS ni eventos adicionales.
- Ninguno de estos nueve tickets es SUPPORT; las incidencias no se convierten
  en tickets de soporte para aprovechar otro enum.

### Acumuladores y snapshot del temporizador

| Ticket | `spentSeconds` beta | `blockedSeconds` beta | `time_spent_seconds` inicial | `blocked_time_seconds` |
|---|---:|---:|---:|---:|
| t1 | 15720 | 2100 | 16440 | 2100 |
| t2 | 7800 | 10800 | 7800 | 10800 |
| t3 | 0 | 0 | 0 | 0 |
| t4 | 24300 | 0 | 24300 | 0 |
| t5 | 33120 | 3300 | 33120 | 3300 |
| t6 | 0 | 0 | 0 | 0 |
| t7 | 5400 | 0 | 5400 | 0 |
| t8 | 11100 | 0 | 11100 | 0 |
| t9 | 0 | 0 | 0 | 0 |

t1 incluye `runningSince=T0−12 minutos`. La importación consolidará esos
720 segundos en el snapshot: 15720 + 720 = 16440. Todos los timers iniciales
quedarán pausados (`timer_started_at=null`), manteniendo los estados del cuadro.
Así la preparación no acumula días de trabajo ficticio entre ejecuciones.
La procedencia conserva el acumulado original y el intervalo consolidado;
el aspecto de contador activo de t1 será una diferencia declarada. Las acciones
posteriores usan el [timer real](../backend/app/services/timer_service.py).

`blocked_time_seconds` existe en SQL, pero no viaja en TicketResponse ni lo
recupera el adaptador. Se conservan los valores de origen sin afirmar que la
UI puede mostrar ese dato ni calcularlo a partir del tiempo de trabajo o de la
pregunta. La vista API conserva su semántica de tiempos actual. No añadir un
contador de espera simulado para igualar la beta.

`completed_at` de t4 es T0−1D, tomado de su evento COMPLETED; los demás quedan
nulos. Su PR es `https://github.com/wellq/portal/pull/412`, un enlace de ejemplo
del seed, no un PR de este repositorio ni evidencia de implementación. Los
otros PR quedan nulos y todas las estimaciones quedan en 0, sin estimación.

## 5. Checklist completo — F07/F09

Destino: [Subtask](../backend/app/models/subtask.py), `done → is_completed`.
Cada fila lleva el UUID del ticket padre y su propio UUID rastreado. La beta no
aporta fechas de completado de subtareas: `completed_at=null`, incluso cuando
`is_completed=True`; no usar el cierre del ticket para deducir cuándo se marcó.

| Alias | Ticket / índice | Título literal | Completada |
|---|---|---|---|
| s1 | t1 / 0 | Pantalla de enrolamiento TOTP | Sí |
| s2 | t1 / 1 | Validación de código de 6 dígitos | Sí |
| s3 | t1 / 2 | Códigos de respaldo descargables | No |
| s4 | t1 / 3 | Tests E2E del flujo completo | No |
| s5 | t2 / 0 | Contador de intentos en Redis | Sí |
| s6 | t2 / 1 | Plantilla de correo de aviso | No |
| s7 | t3 / 0 | Endpoint GET /invoices/:id/pdf | No |
| s8 | t3 / 1 | Listado con paginación | No |
| s9 | t4 / 0 | Validador NIF/CIF | Sí |
| s10 | t4 / 1 | Mensajes de error accesibles | Sí |
| s11 | t5 / 0 | Parser de extractos CAMT.053 | Sí |
| s12 | t5 / 1 | Motor de matching por referencia | Sí |
| s13 | t5 / 2 | Cola de revisión manual | No |
| s14 | t5 / 3 | Informe diario de no conciliados | No |
| s15 | t6 / 0 | Umbral configurable por app | No |
| s16 | t7 / 0 | Scheduler de reintentos | Sí |
| s17 | t7 / 1 | Panel de entregas fallidas | No |
| s18 | t8 / 0 | Canal WS /fleet/positions | Sí |
| s19 | t8 / 1 | Clustering de marcadores | No |
| s20 | t8 / 2 | Modo ahorro de datos | No |

## 6. Historial completo — F08

Destino: [TicketEvent y su enum](../backend/app/models/ticket_event.py).
Las claves `tN/evento/N` identifican la posición original para generar UUID,
sin crear numeración de negocio. Todos llevan `ticket_id`, `user_id` y fecha
de origen. El comentario y la justificación se copian completos del seed.

| Clave | Evento beta → `event_type` | Actor / destinatario | Fecha | Detalle adicional |
|---|---|---|---|---|
| t1/evento/0 | CREATED → CREATED | u2 | −4D | Procedencia |
| t1/evento/1 | ASSIGNED → ASSIGNED | u2 → u3 | −4D | `to_user_id` |
| t1/evento/2 | STATUS → STATUS_CHANGED | u3 | −3D | `from_status=TODO`, `to_status=IN_PROGRESS` |
| t1/evento/3 | COMMENT → COMMENT | u2 | −1D | `message`: comentario sobre compatibilidad con 1Password |
| t2/evento/0 | CREATED → CREATED | u2 | −6D | Procedencia |
| t2/evento/1 | ASSIGNED → ASSIGNED | u2 → u4 | −6D | `to_user_id` |
| t2/evento/2 | QUESTION → QUESTION_RAISED | u4 | −5H | `question`: pregunta sobre API y portal web |
| t3/evento/0 | CREATED → CREATED | u1 | −2D | Procedencia |
| t4/evento/0 | CREATED → CREATED | u2 | −9D | Procedencia |
| t4/evento/1 | COMPLETED → COMPLETED | u5 | −1D | `pr_link` del ticket |
| t5/evento/0 | CREATED → CREATED | u2 | −8D | Procedencia |
| t5/evento/1 | ASSIGNED → ASSIGNED | u2 → u4 | −8D | `to_user_id` |
| t6/evento/0 | CREATED → CREATED | u1 | −3D | Procedencia |
| t6/evento/1 | ASSIGNED → ASSIGNED | u1 → u3 | −3D | `to_user_id` |
| t7/evento/0 | CREATED → CREATED | u2 | −7D | Procedencia |
| t7/evento/1 | REDIRECTED → REDIRECTED | u5 → u3 | −2D | `justification`, `to_user_id`, estado beta conservado |
| t8/evento/0 | CREATED → CREATED | u1 | −5D | Procedencia |
| t8/evento/1 | ASSIGNED → ASSIGNED | u1 → u5 | −5D | `to_user_id` |
| t9/evento/0 | CREATED → CREATED | u1 | −1D | Procedencia |

Las claves de detalle se eligieron según lo que consume
[ApiTicketEvent](../movil/lib/models/api_domain_models.dart). En asignaciones
y redirección, duplicar el destino en la columna `to_user_id` y en
`detail.to_user_id`: la respuesta usada por Flutter no expone las columnas
from/to del modelo, pero sí `detail`. Para t7, `from_user_id=u5` identifica al
actor de la redirección; no prueba que fuera el responsable anterior.

La procedencia en `detail` será un objeto `beta_source` con versión del seed,
alias del ticket, índice del evento y tipo original, además de la adaptación
de estado cuando corresponda. Los eventos describen ejemplos históricos
importados, no llamadas realizadas ahora a `/start`, `/complete` o `/redirect`.
No generar estados previos, cambios de subtareas, asignaciones faltantes ni
eventos RESOLVED/TICKET_COMPLETED inexistentes en este seed.

Varios CREATED/ASSIGNED comparten fecha. Se preservan esos empates; no inventar
microsegundos. El [router de eventos](../backend/app/routers/tickets.py) ordena
por fecha descendente sin desempate explícito. Su orden relativo no se acredita
como idéntico a la lista demo; registrar esa limitación al comparar el historial.

## 7. Incidencias y contenido sin campo equivalente — F10/F11

Destino: [Incident y enums](../backend/app/models/incident.py) y
[IncidentResponse](../backend/app/schemas/incident.py).
Regla de severidad del conjunto: CRITICAL → P1, HIGH → P2,
MEDIUM/LOW → P3. Es una conversión de cuatro niveles a tres, con pérdida de
distinción entre media y baja; conservar la severidad original en la procedencia
y mostrar la prioridad real de la API, no una etiqueta demo que la contradiga.

| Alias / número beta | Título literal | Proyecto | Reporta → responsable | Estado beta → destino | Severidad beta → API | Creación |
|---|---|---|---|---|---|---|
| i1 / 57 | Timeout al conciliar extractos de más de 5 000 líneas | a2 | u2 → u4 | IN_PROGRESS → INVESTIGATING | CRITICAL → P1 | −26H |
| i2 / 58 | El selector de idioma no persiste tras cerrar sesión | a1 | u3 → ninguno | OPEN → REPORTED | LOW → P3 | −8H |
| i3 / 55 | Añadir exportación de movimientos a Excel | a1 | u1 → u3 | UNDER_REVIEW → REPORTED, adaptación declarada | MEDIUM → P3 | −3D |
| i4 / 52 | Contraste insuficiente en el mapa nocturno | a3 | u5 → u5 | RESOLVED → RESOLVED | MEDIUM → P3 | −6D |
| i5 / 60 | Webhook duplicado cuando el receptor responde 5xx lento | a2 | u4 → ninguno | OPEN → REPORTED | HIGH → P2 | −3H |

- Las descripciones originales se conservan, añadiendo un bloque claramente
  identificado como **Contexto importado de la beta** con número original,
  categoría, estado y severidad de origen. Categorías por registro:
  i1/i5 CRITICAL_ERROR; i2 NON_CRITICAL_ERROR; i3 NEW_FEATURE;
  i4 USABILITY_ISSUE. Ese bloque es texto histórico, no un campo editable de
  categoría ni un estado adicional de la aplicación.
- **i3 no tiene equivalencia de estado.** REPORTED será su representación
  conservadora como registro reportado, preservando «En revisión» como contexto.
  No se afirma que siga en revisión mediante la API, ni que se haya investigado,
  mitigado o resuelto. No convertirlo en MITIGATED. Su adaptación se incluye
  entre las diferencias de aceptación de 8B.8.
- i1 tiene un único comentario de Sofía en T0−20H: «Reproducido con el extracto
  de 8 200 líneas. El cuello está en el parser, no en la BD.». Conservarlo en
  el bloque de contexto, con autora y fecha, y en el manifiesto de procedencia;
  no presentarlo como un comentario creado con una API que no existe.
- El seed no declara entorno. Usar **DEV** como entorno técnico explícito de
  estos ejemplos locales y registrarlo como valor añadido, sin inferir producción
  del título. Estimación 0, sin estimación; `mitigation_state=null`. El seed no
  tiene mitigaciones ni fecha de resolución de i4.
- CLOSED y REOPENED existen en la demo, pero no en estos cinco registros ni en
  el contrato de incidentes. No importar filas adicionales para representar esos
  estados. Asignación y cambio de estado seguirán siendo operaciones separadas.

## 8. Notificaciones iniciales — F13

Destino: [Notification](../backend/app/models/notification.py) y
[NotificationResponse](../backend/app/schemas/notification.py).
Se conservan los cinco mensajes literales del seed. Los títulos siguientes son
etiquetas descriptivas añadidas para satisfacer el título obligatorio de la API.

| Claves del seed | Destinatario | Tipo API / título | Relación | Fecha | Leída |
|---|---|---|---|---|---|
| demo-0 | u3 | TICKET_ASSIGNED / Asignación de ticket | t6 | −3D | Sí |
| demo-1, demo-2 | u1, u2 respectivamente | QUESTION_RAISED / Pregunta pendiente | t2 | −5H | No |
| demo-3, demo-4 | u1, u2 respectivamente | SYSTEM / Incidencia reportada | Sin `ticket_id`; origen i5 | −3H | No |
| demo-5, demo-6 | u1, u2 respectivamente | TICKET_COMPLETED / Ticket completado | t4 | −1D | Sí |
| demo-7 | u3 | TICKET_REDIRECTED / Ticket redirigido | t7 | −2D | No |

Los destinatarios y las marcas de lectura son independientes. Para las tres
leídas, `is_read=True` y `read_at=null`: no hay fecha de lectura en la beta.
La lectura posterior usa las rutas reales, sin restablecer flags al repetir setup.

El aviso de incidencia no puede usar un tipo INCIDENT ni `incident_id`:
ambos faltan en el contrato. Se importa como SYSTEM con su mensaje original
y origen i5 en el manifiesto, sin enlazarlo a un ticket distinto ni fabricar
navegación al incidente. Su presentación genérica es una diferencia declarada.
La carga histórica no publica ocho avisos WS como si acabaran de ocurrir;
las operaciones posteriores generan sus notificaciones reales.

## 9. Reglas de preparación y convivencia para 8B.3

1. **Identidad del conjunto:** un manifiesto local protegido registra propósito
   `beta-content`, versión del seed, `dataset_id` UUID, T0 y mapa completo
   alias→UUID. Generar UUIDv5 desde ese dataset y una clave tipada estable
   (`user/u2`, `ticket/t1`, `ticket/t1/evento/0`, `notification/demo-0`, etc.).
   u1 siempre resuelve al ADMIN existente. `dataset_id` y T0 se fijan solo en
   la primera preparación válida; una repetición utiliza el mismo manifiesto.
2. **Unicidad y colisiones:** comprobar correos, ADMIN real/rol/hash y UUID
   previstos antes de escribir. Un correo o UUID ocupado por una fila no
   rastreada detiene la carga; no adoptar ni sobrescribir cuentas por su nombre.
   También comprobar que la cuenta ADMIN no cambió entre manifiesto y SQL.
3. **Convivencia:** crear un conjunto separado del fixture técnico de etapa 8.
   Las cuentas/aplicaciones/tickets de ese fixture no se renombran ni se retiran.
   La UI puede mostrar ambos conjuntos; conteos globales incluyen todo lo que
   la API entregue. Para comparaciones visuales, seleccionar recursos beta por
   UUID y registrar los datos adicionales, sin ocultarlos mediante un filtro local.
4. **Preparación atómica y repetible:** insertar el conjunto y actualizar Ana
   en una transacción; preparar el manifiesto y su recuperación coherentemente.
   Si ya existe el conjunto, verificar sus relaciones e identidad y preservar
   las modificaciones de uso. No volver a insertar, reiniciar fechas/timers,
   sobrescribir estados/lecturas ni resetear contraseñas. La segunda ejecución
   debe acreditar ausencia de duplicados, incluso con datos ya modificados.
5. **Fechas:** T0 con zona UTC; offsets del seed convertidos una sola vez.
   Creación de tickets/incidentes/eventos/notificaciones según los cuadros.
   Usuarios nuevos, proyectos, épicas y subtareas no tienen creación histórica:
   usar fecha técnica de carga con esa procedencia. `updated_at` inicial puede
   reflejar la carga; no reconstruir una última actualización desconocida.
6. **Procedencia:** incluir textos de origen y campos sin equivalente en el
   manifiesto, junto con conversiones de estado/severidad, metadatos técnicos y
   snapshot del timer. En `ticket_events.detail.beta_source`, identificar los
   eventos importados. No introducir campos nuevos en respuestas para transportar
   toda la procedencia. Las credenciales y el manifiesto quedan en
   `backend/.local/`, excluidos de Git y del contexto Docker.
7. **Verificación y retiro:** comprobar mediante API/SQL IDs, relaciones y
   conteos del conjunto. Delimitar un retiro explícito por UUID que detecte
   referencias ajenas antes de borrar; ADMIN no es propiedad de la carga ni se
   elimina. Una eventual restauración de su identidad anterior necesita tratar
   los manifiestos y cambios posteriores, no deshacerla automáticamente.
8. **Negocio posterior:** las acciones de usuarios siguen UI → API → SQL y
   permisos existentes. La herramienta local sirve para importar ejemplos, no
   para acreditar invitaciones, TOTP, SMS, PDF, flotas u otros requisitos E1/E2/E3.

### Valores esperados del conjunto recién preparado

Estos valores definen el seed inicial; no son conteos actualizados de una base en uso.
La aceptación de la carga inicial está en [carga beta](carga-beta-8bis.md):

| Medida | Valor esperado del conjunto beta |
|---|---|
| Tickets por estado | TODO 4; IN_PROGRESS 3; BLOCKED_QUESTION 1; COMPLETED 1 |
| Progreso por proyecto | a1: 1/4 = 25%; a2: 0/3 = 0%; a3: 0/2 = 0% |
| Pendientes, total menos COMPLETED | 8; no confundir con `applications.pending_count`, que solo cuenta TODO |
| Trabajo activo por persona | Ana 0, Luis 0, Diego 3, Sofía 2, Marco 1 |
| Completado por Marco | t4, con fecha T0−1D; entra en «últimos 7 días» solo mientras corresponda |
| Incidencias por estado | REPORTED 3; INVESTIGATING 1; RESOLVED 1; MITIGATED 0 |
| Checklist | 20 filas, 9 completadas; t9 no tiene subtareas |
| Historial | 19 filas: CREATED 9, ASSIGNED 5 y uno de cada STATUS_CHANGED, COMMENT, QUESTION_RAISED, COMPLETED, REDIRECTED |
| No leídas | Ana 2, Luis 2, Diego 1, Sofía 0, Marco 0 |

El dashboard conserva sus reglas reales: por ejemplo, la atención API puede
incluir incidencias INVESTIGATING P1/P2, mientras la beta limita esa parte a
OPEN/REOPENED. No alterar permisos o fórmulas para forzar los mismos contadores.

## 10. Aplicación de esta correspondencia

El inventario cubre cada alias del seed y asigna destino o tratamiento explícito
a campos, eventos, fechas y relaciones. Las conversiones t2/t7/i3, severidades,
categorías/comentario de incidencias, timer y avisos sin enlace están identificadas
para la aceptación. La metadata del selector developer se completó en 8B.4.

La [carga, cuentas y resultados](carga-beta-8bis.md) se verificaron con esta
correspondencia. 8-Bis está aceptada con contenido conservado; los cuadros de este
documento describen la importación y no un restablecimiento de cambios posteriores.
[Decisiones y evidencia consolidadas](estado-actual.md),
[ARR-FLUTTER completada](arranque-flutter.md); etapa 9 en pausa.
