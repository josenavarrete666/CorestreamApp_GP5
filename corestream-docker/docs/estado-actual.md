# Estado actual y evidencia de la base funcional

**Base de código: commit `9ccd000`, 13-10-2026.** Etapas 1–8, ampliación
8-Bis y ARR-FLUTTER completadas. La implementación de los requisitos de Equipo 1
continúa en pausa hasta una indicación expresa del usuario.

Este documento consolida los planes iniciales, informes de integración y aceptación
8-Bis. Los resultados son evidencia de las ejecuciones originales: la limpieza
documental no implica que se hayan repetido las suites ni los recorridos.
Los documentos completos anteriores permanecen recuperables en el historial Git
del commit de referencia.

## Documentación vigente

| Necesidad | Documento |
|---|---|
| Instalar, iniciar y detener | [Guía de ejecución](../GUIA_EJECUCION.md) |
| Entender los componentes | [Arquitectura](arquitectura.md) |
| Consumir HTTP, sesión y WebSocket | [Contratos API](contratos-api.md) |
| Consultar acciones, payloads y límites | [Matriz beta/API](matriz-beta-api.md) |
| Revisar autorización | [Roles y permisos](roles-permisos.md) |
| Preparar usuarios y ejemplos locales | [Carga beta](carga-beta-8bis.md) |
| Entender la procedencia del dataset | [Correspondencia del contenido](contenido-beta-8bis.md) |
| Arrancar Flutter con un comando | [ARR-FLUTTER](arranque-flutter.md) |
| Repetir controles y recorridos | [Herramientas](../scripts/verification/README.md) |
| Continuar el desarrollo | [Tareas pendientes](../TODO_SETUP.md) y [requerimientos](requerimientos/README.md) |

## Base funcional implementada

- Flutter/Dart: formulario real, Inicio/Mi trabajo, proyectos, épicas/tablero,
  tickets, incidencias, Equipo para gestores, avisos/bandeja y Ajustes. Demo y API
  son modos separados; la API no simula eventos de negocio.
- FastAPI, PostgreSQL 15 y Redis 7: datos persistentes, permisos y operaciones
  reales. Alembic se ejecuta antes del backend. Compose conserva los datos en
  volúmenes locales; cada clonación prepara su configuración y cuentas.
- Login, perfil, restauración, refresh, cambio obligatorio y logout comprobados
  en Edge. Access en memoria, refresh HttpOnly y CSRF; revocación de tokens en
  Redis. El refresh consulta la revocación y rota las cookies.
- Un refresh compartido entre solicitudes concurrentes, un replay y generación
  de sesión. Una respuesta tardía de una sesión anterior no invalida un nuevo
  login ni vuelve a publicar sus datos. Logout limpia rutas, cachés y socket propio.
- Logout sin red deja una marca no secreta por origen e impide restaurar recursos
  hasta resolver el cierre. Cambio obligatorio confirma el flag, cierra la sesión
  propia y exige nuevo ingreso; no es cierre global de otras sesiones.
- Crear/asignar/iniciar/preguntar/resolver/completar/redirigir tickets y actualizar
  subtareas: resultado HTTP, SQL y reconsulta/relogin coincidentes. PR opcional.
  Las incidencias usan asignación y cambio de estado separados.
- WebSocket por ticket de un solo uso de 15 s, heartbeat, actividad, reconexión
  cancelable y resincronización HTTP. La bandeja conserva lectura y propietario.
  Una notificación SUPPORT no abre un detalle DEVELOPMENT.
- Errores visibles, reintento GET controlado y doble envío bloqueado. Una mutación
  ambigua provoca reconsulta; no se repite automáticamente ni se presenta como éxito.
- ARR-FLUTTER configura caché, prepara/reutiliza el build API, detecta cambios Dart
  y mantiene un servidor local en primer plano; Ctrl+C detiene solo esa web.

El backend se incorporó desde la fuente del cliente actualizada el 06-10-2026.
ARQ fue retirado de dependencias y arranque: la API persiste avisos y los publica
directamente en Redis. Los documentos Vue/GCP describían otra instalación;
su infraestructura, backup y despliegue no son los de este repositorio móvil.
GCS y Cloud Translation siguen siendo adaptadores del backend, con almacenamiento
local en desarrollo; copiar el código no acredita esas integraciones externas.

### Decisiones de integración conservadas

| ID original | Decisión vigente |
|---|---|
| D01 | Backend actual como contrato de partida; los Word son requisitos objetivo, no rutas ya disponibles. |
| D02 | CS_API_URL solo origen, paths absolutos /api; mismo host para cookies y WS construido desde ese origen. |
| D03 | TEAM_LEADER canónico, mapeo explícito de líder; roles API desconocidos producen error de contrato. |
| D04 | Web con refresh HttpOnly, CSRF y access en memoria, sin refresh JSON en el ciclo elegido. |
| D05 | Android reutiliza cookie/CSRF mediante jar; persistencia protegida y aceptación nativa posteriores. |
| D06 | El recorrido inicial usó aplicaciones y notificaciones propias con persistencia real. |
| D07 | La ampliación sustituyó el inicio API simplificado por las vistas beta completas, compuestas con rutas existentes; BFF ya no bloquea esas vistas. |
| D08 | WS con ticket, separado de FCM; Edge no acredita push Android. |
| D09 | Datos, permisos y capacidades explícitos; demo no sustituye operaciones reales ni capacidades ausentes. |
| D10 | Ocho xfail conservados como deuda del consumidor Vue, sin impedir el recorrido Edge elegido. |

## Presentación e interacción aceptadas

La comparación F01–F15 conservó el tema Flutter de la beta, tarjetas, navegación,
paneles, avatares y jerarquía visual. No es una declaración de igualdad píxel a
píxel ni de cumplimiento exhaustivo con lectores de pantalla.

| Criterios consolidados | Resultado y decisión vigente |
|---|---|
| F01–F02, login | Marca C/degradado compartida, formulario real ES/EN, autofill, Tab/Enter, mostrar contraseña, busy y avisos semánticos. Ancho máximo 440 y scroll/SafeArea. 429 respeta Retry-After con ceil, mínimo 1 s, fallback 30 s; timer dispuesto al cerrar. |
| F03–F04, inicio | Navegación por rol y controles reales de conexión/actualización; grilla beta y métricas derivadas de datos disponibles. Vacío y fallo son estados distintos. |
| F05–F07, proyectos/tablero | Colores, especialidades y monogramas decorativos PC/AP/AL persistidos; UUID como identidad. Color #RRGGBB exacto, fallback #4C8DFF; monograma 1–3 ASCII mayúsculas/dígitos, sin imágenes externas. |
| F08–F09, detalle/paneles | UUID secundario, historial fiel ES/EN, campos largos flexibles y paneles desplazables con teclado. El tiempo de trabajo no se etiqueta como espera. No se infiere destinatario del historial si el DTO no lo entrega. |
| F10–F11, incidencias | REPORTED/INVESTIGATING/MITIGATED/RESOLVED y P1/P2/P3. Sin revisión/cierre/reapertura/categorías/comentarios o autoasignación developer inventados. Entorno y mitigación reales. |
| F12–F14, identidad/avisos/Ajustes | Identidad coherente en perfil, responsables, autores y selectores. Developer usa team-members, no el directorio restringido. Contenido de registros conserva su idioma de origen. |
| F15, recuperación | Carga/error/vacío explícitos, reintento y límites de navegación; sin éxito local ante rechazo API. |

En 8B.7 se corrigió la fusión semántica de la tarjeta de la segunda épica:
`CsCard` establece una frontera de botón y `ProgressBar` un nodo propio. El ticket
t7 se abrió por Tab/Enter en Edge y en pruebas de los tres roles. Se retiró el
fallback de coordenadas del controlador; la matriz final exige botón semántico.

## Evidencia consolidada

Las cantidades de tests y capturas son resultados de incrementos distintos:
**no se suman como si fueran pruebas independientes ni se presentan como nuevas.**

| Ejecución original, UTC | Resultado registrado |
|---|---|
| Entorno/operación/demo, hasta el 12-10-2026 | Docker/Compose y puertos comprobados. Backend de etapa 4: 205 unitarias/174 integración + 8 xfail, Ruff/Mypy limpios; correcciones de tipos y regresiones de épica/roles. Ctrl+C/stop/reinicio conservaron marcadores SQL/Redis/archivo, luego retirados. Demo: análisis limpio, 17 Flutter y tres perfiles Edge. |
| Contratos, 12-10-2026 | 27 expresiones Dio (no 27 endpoints), 80 paths/103 operaciones observados; 11 operaciones/30 campos del manifiesto contrastados. 18 tests de contrato + 8 xfail, y 36 de auth/bandeja aprobados; CORS publicado comprobado. |
| Integración inicial, 12-10-2026 | A01–A13/N01–N15; 42 Flutter; 211 unitarias backend, 175 integración + 8 xfail heredados; análisis, Ruff/Mypy y persistencia comprobados. |
| Integración beta B01–B18, 12-10-2026 | 52 Flutter + 1 omitida; 1 live independiente; 2 pruebas backend de herramientas. HTTP/SQL/Edge y permisos reales; no repitió las suites globales backend. |
| 8B.3–8B.4, 12–13-10-2026 | Carga idempotente, SQL y cinco cuentas HTTP; 7 unitarias/8 integración de carga. Identidad: 54 Flutter + 2 omitidas, 1 live, 35 integración y 28 capturas. |
| 8B.5, 13-10-2026 | 68 Flutter + 2 omitidas; 14 nuevas de presentación incluidas; 57 capturas (40 visuales, 13 de sesión, 4 de cambio obligatorio). |
| 8B.6, 13-10-2026 | 75 Flutter + 2 omitidas; 12 casos/240 capturas oscuro ES y claro EN; cero escrituras de contenido. |
| 8B.7–8B.8, 13-10-2026 | **79 Flutter + 2 omitidas**, 4 nuevas incluidas; **1 live adicional**. Ciclo completo, subtarea, redirección, incidencia y lectura persistentes; denegaciones 403 reales. |
| Matriz final 8B.8, 13-10-2026 | **24 combinaciones/176 capturas nuevas**: Ana/Luis/Diego × oscuro/claro × ES/EN × 390×844/1280×900. Cero excepciones/escrituras de contenido; reutiliza explícitamente 240 capturas de 8B.6 y 57 de 8B.5. |
| ARR-FLUTTER, 13-10-2026 | Preparación inicial, caché reutilizada, cambio Dart recompilado, acceso Edge, refresh/logout y dos cierres Ctrl+C sin servidor huérfano. Errores de dependencias/compilación detienen el arranque. Análisis final limpio, 2.5 s. |

La aceptación final 8B.8 está en `.verification/8b8-acceptance-report.json`,
completa a `2026-10-13T03:08:43.335Z`. Los tres roles recorrieron las pantallas
comunes; oscuro EN/claro ES añadieron paneles y pantallas que faltaban en 8B.6.
Reanudación desde checkpoint usó el mismo build/dataset, sin duplicar casos.

La evidencia diferencia Edge/API/SQL reales, pruebas de widget/transporte y fallos
inyectados CDP. En login, 429 y fallo de red de logout fueron inyectados; cambio
de contraseña, restauración y revocación usaron la API. Un test de widget no
reemplaza una operación SQL; CDP no acredita un corte físico. HTTP 200 con cero
notificaciones marcadas tampoco acredita lectura: se verifican cantidades y datos.

### Aceptación funcional B01–B18

Resultados originales del **12-10-2026, consolidación 20:07:32 UTC**, anteriores
a los ajustes 8-Bis. Los criterios/payloads completos permanecen en la matriz API.
Estos IDs de aceptación son distintos de los B01–B10 de dependencias más abajo.

| Caso | Procedencia y resultado registrado |
|---|---|
| B01–B03 | Edge real: ADMIN/líder con cuatro pestañas y developer con tres; login/perfil, Inicio/Mi trabajo y permisos. Developer no consulta /users/. |
| B04 | Edge: métricas/vacío; HTTP nativo: progreso inicial 20%. Tests controlados: páginas/deduplicación y fecha semanal ausente. Tras acciones manuales SQL/progreso 50%, sin confundir ambos momentos. |
| B05–B06 | Edge: proyecto/épica/tablero/detalle por UUID y orden; responsable, subtareas, eventos y tiempo corroborados en SQL, SUPPORT fuera del tablero. |
| B07 | Edge ADMIN crea/asigna, manifiesto rastrea ticket; SQL/relogin preservan UUID/responsable. Doble envío probado de forma controlada. |
| B08 | Edge y HTTP nativo: TODO → IN_PROGRESS → BLOCKED_QUESTION → resolución líder → IN_PROGRESS → COMPLETED, PR vacío permitido; subtarea/eventos/fechas/timer persistidos. |
| B09 | Redirección developer real 200: nuevo asignado/TODO, acumulado/eventos/notificación confirmados por SQL. |
| B10 | HTTP real: 403 ADMIN iniciar, developer iniciar ajeno/resolver pregunta. Test controlado: 403 de negocio conserva sesión. |
| B11–B12 | Edge/API/SQL: cuatro estados y P1/P2/P3, filtros/entorno/mitigación; asignación no cambia estado, PATCH status posterior persiste. Sin autoasignación ficticia. |
| B13 | Edge Equipo gestores; HTTP nativo valida carga por asignados reales. Páginas deduplicadas, no agregado /teams. |
| B14 | Evento persistido y publicado → frame UUID → aviso/campana/bandeja/detalle DEVELOPMENT/lectura. SUPPORT muestra límite; lectura conjunta y título API corroborados. |
| B15 | Tres roles/dos tamaños, oscuro ES y claro EN; capturas y paneles legibles. El diseño login conservado en esta etapa se rediseñó después en 8B.5. |
| B16 | Edge logout/relogin sin residual. Tests controlados: retiro de ruta externa, fan-out/generación y carreras de sesión antigua. |
| B17 | Fallo HTTP inyectado CDP: error/reintento GET recupera sesión. Respuesta mutante vencida simulada: no repite POST, invalida caché y reconsulta COMPLETED. |
| B18 | Analyze/build, 52 Flutter + 1 omitida; 1 live separado; Ruff/Mypy y 2 tests de herramientas aprobados, sin repetir backend global. |

Reconexión adicional inyectó cierre 3001 solo al socket del navegador: ticket nuevo,
handshake y reconsulta HTTP; no cambió idle backend de 1200 s. En los datos manuales,
los completados conservaron 59 s y el creado por UI 6 s; el redirigido, 4829 s.
La UI abrevia menos de 60 s como `0 min`, no significa acumulado SQL igual a cero.

## Datos locales y reproducción

- Dataset beta verificado: `a8cae710-913d-468c-b872-9239ed8d6585`, T0
  `2026-10-12T23:35:27.543646+00:00`: 5 usuarios, 3 aplicaciones, 5 épicas,
  9 tickets, 20 subtareas, 19 eventos, 5 incidencias y 8 avisos. Al cierre se
  conservaron baseline/ADMIN y no leídos globales 6/2/1/0/0. El uso posterior
  puede cambiar estados, cantidades y lecturas; estas cifras no son un reset.
- Conjunto técnico manual conservado en esa instalación:
  `ec818fea-557a-4b2a-aa00-1c4872ff670a`, `backend/.local/beta-manual.json`.
  Es distinto del dataset beta; conviven y sus recursos afectan conteos globales.
  La guía mantiene sus comandos de check/event. No existe automáticamente al clonar.
- Fixtures de aceptación retirados: `1ed20fd7-6dcc-4506-af13-f8f1dd2d4d73`
  (beta nativa), `b8bbc6ac-e725-44b8-9e7b-805000000005` (auth 8B.5),
  `489282fd-d64a-4de5-ad95-9d22f2a6b787` (Edge 8B.7) y
  `94a02d1e-762b-479d-af0a-765c6cecb8a8` (live 8B.8). No reutilizarlos.
- Para repetir pruebas mutantes, generar UUID/manifiesto frescos, comprobar el
  destino development y registrar recursos creados. Cleanup por UUID preserva
  ADMIN y aborta ante referencias ajenas. Tests usan `corestream_test`/Redis db15;
  desarrollo usa `corestream`/db0. Redis pub/sub no está aislado por índice.
- Credenciales solo en `backend/.local/`; resultados/capturas en `.verification/`.
  Ambos están excluidos de Git; `.local/` también del contexto Docker. En NTFS/WSL,
  comprobar ACL Windows: chmod 0600 no sustituye esa protección.

Checklist de regresión para cambios de sesión: login/perfil por rol, restauración,
refresh concurrente y rotación, token anterior rechazado, cambio obligatorio y
nuevo ingreso, logout offline/recuperación, carreras de sesión antigua, propiedad
de notificaciones, WS/reconexión y persistencia tras recarga/relogin. Los comandos
y requisitos de cada fixture están en la guía y las herramientas versionadas.

## Responsabilidades y dependencias compartidas

E1 coordina sesión, seguridad y plataforma; E2, proyectos/tickets y escalabilidad;
E3, incidencias/equipo/UX. Las asignaciones son ámbitos funcionales, no promesas de
entrega de otra persona. Requisitos nuevos E2/E3 quedan fuera del desarrollo local
acordado. APP-03 E1 y APP-21 E3 deben usar un mismo cierre de sesión.

| Registro conservado | Estado y responsable |
|---|---|
| B01, dashboard/tablero/detalle | E2, permisos E1. Composición actual acreditada con rutas existentes; BFF bajo /api/mobile sigue como objetivo externo, no bloqueo local. |
| B02, incidencias/carga | E3. Dominio actual integrado; diferencias de estados/campos explícitas en matriz API. |
| B03, dispositivos/FCM | E1 con Ajustes E3. Faltan modelos, migraciones, rutas, preferencias, envío y relación sesión/dispositivo; aceptación Android posterior. |
| B04, empresa/planes | E1 con E2/E3. Perfil/token no incluyen el contexto client_id/plan requerido; autenticación actual no acredita aislamiento multiempresa. |
| B05, auditoría/2FA/SSO/biometría | E1. Requieren criterios y aceptación propios; historial de tickets/logs JSON no son auditoría inmutable con retención por plan. |
| B06, contratos Vue heredados | E2/E3. Ocho xfail de consumidor externo, detallados abajo; no son fallos nuevos de Flutter. |
| B07, revocación y WS remoto | E1. Socket propio cerrado; backend autentica al entrar, sin revalidación periódica. Cierre global/remoto no acreditado. |
| B08, errores de redirección | E2. Camino permitido HTTP/SQL aprobado; catch genérico heredado pendiente, sin convertir rechazo en éxito del cliente. |
| B09, contraseña obligatoria | E1. Flujo cliente comprobado; enforcement global backend y revocación de otras sesiones pendientes. |
| B10, aceptación real de sesión | E1. Edge, cookies/CSRF, refresh, revocación propia y cierre pendiente comprobados. |

## Deuda heredada y límites

Los ocho xfail strict pertenecen a
`backend/tests/integration/test_api_contract.py`, que reproduce el consumidor Vue
ausente de esta copia. Reejecución histórica: 18 aprobados + 8 xfail, sin fallos
inesperados. Su cierre exige adaptar ese consumidor y convertir los casos en
regresiones verificadas, no retirar las marcas.

| Caso | Contrato que debe respetar el consumidor |
|---|---|
| X01, mover ticket usa POST | PATCH /api/tickets/{id}/move, new_epic_id |
| X02, workbench usa otra ruta | GET /api/tickets/my-workbench |
| X03, performance sin proyecto | GET /api/analytics/performance/{app_id} |
| X04, burndown usa proyecto | GET /api/analytics/burndown/{epic_id} |
| X05, reunión usa PUT | PATCH /api/meetings/{id} |
| X06, asistencia envía lista | POST /api/meetings/{id}/attendance, objeto user_id/status/notes |
| X07, asistencia espera is_present | Respuesta usa status |
| X08, incidente usa PUT | PATCH /api/incidents/{id} |

DWDS/debug produjo `removeChild` al reiniciar/recargar; release estático pasó y
es el arranque diario. Eso no acredita haber resuelto el fallo de debug. El aviso
CupertinoIcons/Wasm no impidió el build. Las aceptaciones Edge usaron perfiles
aislados sin extensiones después de fallos externos diagnosticados.

El jar nativo existe en memoria; almacenamiento protegido, ejecución Android,
biometría y FCM en segundo plano no se acreditan con Edge ni con HTTP nativo.
La eliminación de un dispositivo push no equivale a revocar una sesión.
Los Word describen una versión anterior en algunos puntos: contrastar cada
requisito con el código actual, especialmente auth_ext, mobile_api y push_service.

## Siguiente desarrollo

La base está preparada para empezar Equipo 1. Permanecen pendientes TRV-01
(multiempresa), TRV-02 (planes/feature gating), TRV-07 (auditoría), TRV-08
(retención), APP-03 (completar logout/dispositivo), APP-06 (FCM), NEW-08
(alcance 2FA/SSO) y NEW-10 (biometría). Matriz, tareas y aceptación por plataforma
en TODO_SETUP; iOS está excluido y Android es el destino móvil acordado.

## Controles de la documentación vigente

Después de modificar documentación, comprobar enlaces, selección publicable y
whitespace. El snapshot usa una carpeta temporal existente y no hace commits:

```powershell
node scripts/verification/check-doc-links.mjs
node scripts/verification/check-repository.mjs
git diff --check
```

Limpieza documental verificada el **13-10-2026**: 16 Markdown/170 enlaces locales
válidos; snapshot aislado de 258 archivos, 44 esenciales y 27 exclusiones aprobadas,
con sintaxis Node correcta. Whitespace revisado sin incidencias. Los informes
consolidados y el archivo ARQ se retiraron del árbol de trabajo; las referencias
operativas apuntan a la documentación vigente.

Estos controles no sustituyen pruebas de aplicación. Los scripts de verificación,
tests y herramientas de carga permanecen versionados para repetir la aceptación.
