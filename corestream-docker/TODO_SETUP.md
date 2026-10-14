# TODO_SETUP — Próximos pasos de CoreStream

## Alcance y autorización

**`corestream-docker/` es la raíz de desarrollo acordada.** Cliente Flutter/Dart,
backend FastAPI, PostgreSQL y Redis; entorno local Windows/PowerShell y
Ubuntu-24.04/WSL2. Android es el destino móvil; iOS queda fuera de alcance.

**Etapa 9 en pausa por indicación del usuario.** Las etapas 1–8, 8-Bis y
ARR-FLUTTER están completadas. La limpieza documental no autoriza iniciar
requisitos nuevos. Esperar la indicación expresa para comenzar Equipo 1.

- Mantener la sesión comprobada y las vistas/componentes de la beta. UI-LOGIN
  se completó en 8B.5; no hay otra tarea de rediseño pendiente.
- El backend actual define datos, estados, operaciones y permisos. No inventar
  métricas, relaciones ni éxito de operaciones para imitar la demo.
- Reutilizar lo existente antes de desarrollar; introducir compatibilidad del
  backend ante problemas contrastados, conservando sus reglas de negocio.
- Los requisitos nuevos de E2/E3 no forman parte del desarrollo local acordado;
  coordinar los contratos compartidos necesarios para E1. APP-03/APP-21 usan
  un mismo cierre de sesión, invocado desde Ajustes.
- La fuente original y las carpetas hermanas no son dependencias de arranque.
  Los cambios se realizan en esta raíz; la fuente original se consulta en solo lectura.

## Base cerrada

| Etapa | Estado y resultado |
|---|---|
| 1–3, entorno | Docker/Compose, copia, configuración local, migraciones y acceso Windows comprobados |
| 4–5, backend/operación | Pruebas y análisis; inicio/cierre/reinicio y persistencia comprobados; ocho xfail heredados siguen registrados |
| 6–7, demo/contratos | Demo de tres perfiles, cierre independiente, transporte/sesión y contratos iniciales acordados |
| 8, integración | Recorrido A01–A13/N01–N15 y ampliación B01–B18; punto B cerrado con beta/API |
| 8-Bis | 8B.1–8B.8/punto UI cerrados; contenido persistente, identidad, login, pantallas, semántica e interacción aceptados |
| ARR-FLUTTER | Preparación, reutilización/actualización del build, acceso Edge y Ctrl+C comprobados |
| 9, Equipo 1 | En pausa, pendiente de indicación del usuario |
| 10, Android/entrega | Pendiente de los requisitos necesarios y aceptación nativa |

Última regresión registrada: **79 Flutter + 2 omitidas y 1 live adicional**;
matriz Edge final: **24 combinaciones/176 capturas nuevas**. Fechas, procedencia,
resultados backend, diferencias aceptadas, datos conservados y deuda en
[estado actual](docs/estado-actual.md). Estos resultados no son pruebas nuevas
realizadas durante la limpieza de documentos. Base publicada: `9ccd000`.

## Etapa 9 — Equipo 1: sesión, seguridad y plataforma

**Dependencias satisfechas:** punto B, aceptación 8-Bis y ARR-FLUTTER.
**Dependencia pendiente:** autorización para comenzar. Fuente principal:
[documento de Equipo 1](docs/requerimientos/CoreStream_App_Equipo1_Sesion_Seguridad_Plataforma.docx),
con [API móvil y estándares](docs/requerimientos/README.md).
Contrastar cada afirmación del Word con el código actual.

### Matriz preliminar del alcance

Los criterios siguientes orientan el desglose; no sustituyen la extracción y
acuerdo de aceptación de 9.1 ni afirman que el requisito esté implementado.

| ID | Estado actual / brecha | Evidencia de cierre a concretar |
|---|---|---|
| TRV-01, multiempresa | Falta contexto client_id y autorización de recursos por empresa | Usuarios de empresas distintas no leen/modifican recursos ajenos; contexto y consultas verificados |
| TRV-02, planes/feature gating | No hay plan ni funciones habilitadas en el perfil actual | Rechazos del servidor según plan, UI coherente y contratos compartidos |
| TRV-07, auditoría | Historial de tickets/logging no equivalen a auditoría inmutable y externalizada | Eventos exigidos completos, destino e integridad/consulta comprobados |
| TRV-08, retención | Falta política por plan y mecanismo de aplicación | Límites y ciclo de retención probados conforme a estándares |
| APP-03, logout/revocación | Logout propio, rotación y cierre pendiente comprobados; falta relación sesión/dispositivo push y política remota integral | Jti/cookies/socket/dispositivo consistentes; cierre online/offline y carreras por plataforma |
| APP-06, FCM | Noop activo; faltan modelos, migraciones, rutas, preferencias, credenciales/configuración y envío | Registro/desvinculación y entrega nativa real, incluido segundo plano según requisito |
| NEW-08, 2FA/SSO | Contratos/alcance pendientes | Definir factores/proveedores y demostrar el flujo solicitado con sus errores y recuperación |
| NEW-10, biometría | Pendiente; no reemplaza autenticación servidor | Desbloqueo seguro, fallback/cancelación/invalidez y logout en Android |

Refresh ya consulta revocación; no duplicar un arreglo basado en el estado antiguo
del Word. Eliminar un dispositivo push no revoca una sesión. WebSocket no acredita
FCM. El BFF móvil ausente no bloquea la composición de la beta ya integrada.

### Tareas pendientes y orden

- [ ] **9.1** Extraer matriz definitiva: ID, alcance, aceptación, estado real,
  dependencias, componentes y evidencia prevista; contrastar Word/código.
- [ ] **9.2** Identificar lo existente/adaptado/pendiente. Contabilizar la sesión
  actual sin declararla equivalente a todos los requisitos de E1.
- [ ] **9.3** Desglosar sesión, seguridad, revocación, logout y vínculo con
  dispositivos; mantener el cierre compartido con Ajustes.
- [ ] **9.4** Desglosar registro/desvinculación, preferencias y FCM, incluyendo
  configuración, pruebas y dependencia Android.
- [ ] **9.5** Concretar 2FA, SSO y biometría antes de fijar sus contratos y pruebas.
- [ ] **9.6** Desglosar aislamiento multiempresa, autorización, planes, auditoría
  y retención conforme a los documentos.
- [ ] **9.7** Acordar controles/contratos con E2/E3: errores, sesión, contexto,
  permisos y responsables; no presuponer entregas externas.
- [ ] **9.8** Convertir requisitos en incrementos pequeños con dependencias y
  aceptación; implementar/verificar cada incremento antes del siguiente.
- [ ] **9.9** Mantener trazabilidad requisito → cambio → prueba → resultado;
  actualizar contratos y documentación al modificar interfaces.

**Cierre:** cada requisito tiene evidencia de aceptación. Lo que exige Android
queda vinculado a etapa 10 y no se cierra con pruebas Edge o HTTP nativo.

## Etapa 10 — Android y entrega final

**Dependencia:** base integrada y requisitos implementados hasta el punto necesario
para comprobar sus capacidades nativas sobre la misma aplicación Flutter.

- [ ] **10.1** Generar `movil/android/`, conservando el paquete Dart y definiendo
  el identificador Android del proyecto.
- [ ] **10.2** Preparar SDK, Command-line Tools y licencias; revisar `flutter doctor`.
- [ ] **10.3** Configurar API para emulador/dispositivo y permisos. `localhost` en
  un teléfono no representa el PC que sirve el backend.
- [ ] **10.4** Configurar Firebase/FCM e integraciones nativas acordadas.
- [ ] **10.5** Compilar/ejecutar Android y comprobar sesión, datos y cierre,
  incluido almacenamiento protegido del jar nativo.
- [ ] **10.6** Validar biometría y push en segundo plano en las condiciones exigidas.
- [ ] **10.7** Completar aceptación entre componentes, resolver bloqueos y cerrar
  la matriz con resultados reales.
- [ ] **10.8** Preparar artefacto, versiones/configuración e instrucciones
  reproducibles, incluido el entorno API necesario.

**Cierre:** artefacto Android probado, requisitos acreditados en su plataforma y
documentación de ejecución/entrega vigente.

## Reglas de verificación y documentación

- Marcar `[x]` después de ejecutar la comprobación y registrar evidencia, no por intención.
- Ejecutar comandos uno por uno; diagnosticar fallos antes de pasos dependientes.
- Registrar ID/fecha, comando, salida, esperado/observado, cantidades y fallos;
  conservar resultados y capturas privados en `.verification/` y publicar un
  resumen sanitizado en [estado actual](docs/estado-actual.md).
- Demo, pruebas controladas y fuente original no sustituyen API/SQL/Edge reales.
  Mantener los ocho xfail heredados clasificados y strict hasta verificar su solución.
- Preparar UUID/manifiestos frescos para aceptación mutante; preservar ADMIN,
  dataset beta y otros datos manuales. No reutilizar fixtures retirados.
- Sincronizar [guía](GUIA_EJECUCION.md), [contratos](docs/contratos-api.md),
  [matriz API](docs/matriz-beta-api.md), [permisos](docs/roles-permisos.md) y
  [arquitectura](docs/arquitectura.md) cuando cambie su alcance.
- Ejecutar [comprobadores documentales/publicables](scripts/verification/README.md)
  y las pruebas afectadas por cada cambio. Backend integración usa
  `corestream_test`/Redis db15; pub/sub no se aísla por índice.

## Enlaces de trabajo

- [Inicio/cierre diario y preparación local](GUIA_EJECUCION.md).
- [Contenido y cuentas beta](docs/carga-beta-8bis.md) y
  [procedencia/conversiones](docs/contenido-beta-8bis.md).
- [Comando Flutter y caché/build](docs/arranque-flutter.md).
- [Herramientas y recorridos reproducibles](scripts/verification/README.md).
- [Estructura y publicación](docs/publicacion-github.md).
