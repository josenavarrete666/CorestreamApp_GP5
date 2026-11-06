# Traspaso para el agente de desarrollo — Equipo 1, noviembre 2026

Referencia para el asistente de IA (o la persona) que continúe el desarrollo de
CoreStream App. Resume lo hecho desde la base `9756dd3` (31-10-2026), lo que
queda pendiente y lo que hay que tener presente para no romper nada.
**Leer junto con [AGENTS.md](../AGENTS.md)**, que sigue siendo la fuente de
reglas del proyecto. Estado y evidencia: [estado actual](estado-actual.md);
tareas: [TODO_SETUP](../TODO_SETUP.md); contratos: [contratos API](contratos-api.md).
Para levantar el entorno: [puesta en marcha para el equipo](puesta-en-marcha-equipo.md).

## 1. Contexto en una línea

App móvil Flutter (Android) + backend FastAPI/PostgreSQL/Redis para Alloxentric.
Este equipo es **Equipo 1: sesión, seguridad y plataforma**. Requerimientos en
`docs/requerimientos/` (Word del cliente; contrastar siempre con el código).
Repositorio de entrega: `josenavarrete666/Corestream_Grupo1`, rama
`corestream-mobile`. La etapa 9 (requerimientos de E1) está **en curso** con
APP-03 y APP-06 terminados; el resto de E1 necesita indicación del usuario.

## 2. Lo que se hizo

### Requerimientos cerrados y aceptados en dispositivo real (Samsung S20, Android 13)

**APP-03, cierre de sesión con revocación.** El logout revoca los jti de access y
refresh en Redis (ya existía) y ahora además desactiva el dispositivo push si
el cliente envía `fcm_token`. Comprobado: tras cerrar sesión no llega push.

**APP-06, push FCM.** Comprobado: el push llega en segundo y primer plano y al
tocarlo abre el ticket.

| Pieza | Dónde |
|---|---|
| Tabla `user_devices` | `backend/app/models/user_device.py`; migraciones `j6k7l8m9n0o1` y `k7l8m9n0o1p2` |
| Rutas `/api/devices` (registro 201/200, lista, `DELETE /{id}`, preferencias) | `backend/app/routers/devices.py`, `backend/app/schemas/device.py`, `backend/app/services/device_service.py` |
| Envío FCM asíncrono, preferencias, desactivación de tokens inválidos, modo simulado sin credencial | `backend/app/services/push_service.py`, llamado desde `flush_pending_notifications` en `notification_service.py` |
| Logout con `fcm_token` | `backend/app/routers/auth.py`, `LogoutRequest` en `backend/app/schemas/user.py` |
| Credencial | `FIREBASE_CREDENTIALS_FILE` en `config.py`, `docker-compose.yml` y `.env.example` |
| Cliente push Android | `movil/lib/services/firebase_push_service.dart` (solo Android); `NoopPushService` en web, escritorio y pruebas (`push_service.dart`, `push_platform*.dart`) |
| Registro del dispositivo, token en logout y apertura del push tocado | `pushRegistrationProvider`, `pushOpenedProvider` y `notificationFromPush` en `movil/lib/providers.dart`; `AuthNotifier.deviceToken`; `ApiClient.logout(deviceToken:)`; `ApiRepository.registerDevice` |
| Plataforma Android | `movil/android/` con paquete `com.alloxentric.corestream`, plugin google-services 4.4.4, permisos INTERNET y POST_NOTIFICATIONS, HTTP en claro solo en debug |

Pruebas: `backend/tests/test_push_service.py`, `backend/tests/integration/test_devices.py`,
`movil/test/push_device_test.dart`, `movil/test/push_toast_test.dart`.

### Correcciones de errores encontrados durante la aceptación

- **Notificación sin `ticket_id` al crear un ticket** (error del backend
  original): `create_ticket` notificaba antes del flush. Ahora hace
  `await db.flush()` antes de notificar (`backend/app/routers/tickets.py`).
  Afectaba a la campana y al push.
- **Banner de aviso que quedaba fijo:** se insertaba con la app en segundo plano
  y el temporizador no lo retiraba por no estar `mounted`. Ahora no se muestra
  en segundo plano y siempre se retira (`showPushToast` en `movil/lib/ui/widgets.dart`).
- **Prueba de sesión intermitente** `401 concurrentes` (`movil/test/api_session_test.dart`):
  esperaba 20 ms fijos; ahora espera el refresh con límite.

### Mejoras de app pedidas por el usuario

- Inicio de líder/ADMIN: los recuadros **Aplicaciones** y **Tickets abiertos**
  llevan a las pestañas Proyectos e Incidencias (`dashboard_screen.dart`, `home_shell.dart`).
  Ojo: «Tickets abiertos» lleva a Incidencias por pedido explícito, aunque son
  dominios distintos.
- Los recuadros de contadores ya no desbordan en teléfonos de 360 dp
  (`StatGrid` en `widgets.dart`).
- «Atrás» en Android: desde otra pestaña vuelve a Inicio; desde Inicio deja la
  app en segundo plano sin cerrar la sesión (`MainActivity.kt` + `app_background.dart`).
- Aviso «Sesión revocada.» que desaparece a los 5 s (`credentials_screen.dart`).
- Marca: logotipo CoreStream con fuente Manrope (OFL, en `movil/assets/fonts/`)
  y crédito «Distribuido por Alloxentric» al pie, con logo claro para el tema
  oscuro (`auth_layout.dart`, `movil/assets/branding/`).

### Entorno y herramientas

- `scripts/start-desktop.ps1`: variante de `start.ps1` para **Docker Desktop**
  (sin Ubuntu en WSL).
- Cuentas compartidas del equipo: el dataset beta usa correos **`@alloxentric.com`**
  (`backend/scripts/beta_content_seed.json`). `scripts/setup-dev-accounts.ps1`
  crea el ADMIN, carga el dataset y aplica las contraseñas del archivo privado
  `backend/.local/credenciales-dev.json` con `backend/scripts/dev_accounts.py`.
  Las contraseñas **no** están en el repositorio.

## 3. Decisiones tomadas (no revertir sin consultar al usuario)

| Tema | Decisión | Motivo |
|---|---|---|
| Logout | Refresh en cookie HttpOnly; body opcional `{fcm_token}`; responde 200 JSON | La especificación (§4.6) pide `refresh_token` en body y 204; la cookie es más segura (decisión D04) |
| Preferencias push | Solo `enabled` y `muted_types` en `users.preferences["push"]` | Sin horario de silencio (§4.4–4.5); dos de los tipos del contrato aún no existen |
| Destino del push | Registration token de `FirebaseMessaging.getToken()` y `Message(token=…)` | La API nueva `register()`/FID **no respondió** en el S20. `getToken`/`token` están marcados obsoletos; ignorados con comentario |
| Credencial | Ruta en `FIREBASE_CREDENTIALS_FILE` | El contrato propone `FIREBASE_CREDENTIALS_JSON` |
| Contrato de dispositivos | Nombres, códigos y mensajes de §4.1–4.3 | Alineado el 05-11-2026 |
| Avisos de incidencias (§7.2) | **No implementados** | El usuario respondió «ahora no»; las incidencias son dominio de E3 |

## 4. Pendiente

**Requerimientos de E1 sin empezar** (necesitan indicación del usuario):

- **TRV-01 multi-tenancy:** `client_id` en las 16 tablas y filtros en los ~110
  endpoints; coordinar con E2/E3 porque toca el backend compartido.
- **TRV-02 feature gating:** depende de TRV-01.
- **TRV-07 auditoría de logs:** es el más independiente; ya existen
  `logging_config.py` (JSON) y `middleware/request_id.py`.
- **TRV-08 retención por plan:** depende de TRV-02 y TRV-07.
- **NEW-08 2FA/SSO** y **NEW-10 biometría.**

**Fuera de alcance acordado, pero pedido por la especificación:**

- §7.2: `incident_id` en notificaciones y tipos `INCIDENT_ASSIGNED`/`INCIDENT_REPORTED`.
  Hoy asignar una incidencia **no** genera aviso ni push.
- Horario de silencio y preferencias por tipo completas.

**Limitaciones conocidas:**

- La sesión vive en memoria (cookie jar sin persistencia en
  `http_platform_native.dart`): si Android mata el proceso, hay que volver a
  ingresar. La persistencia protegida es de la etapa 10.
- Cierre remoto o global de otras sesiones y revalidación del WebSocket (B07): no hecho.
- Con letra del sistema al 130 % aún desbordan la pantalla de perfiles de la
  demo y las etiquetas `CsChip`.
- Aviso de compilación: `firebase_core` aplica el plugin de Kotlin (KGP);
  versiones futuras de Flutter lo exigirán migrado.
- Build release sin firma propia (usa la de debug).

## 5. Lo que hay que saber antes de codificar

**Entorno Windows y PowerShell 5.1**

- **Codificación:** leer y escribir archivos con UTF-8 explícito. Un
  `Get-Content -Raw` seguido de reescritura dañó los acentos de `widgets.dart`
  una vez. Los `.ps1` con acentos necesitan BOM.
- **Docker:** el usuario trabaja con Docker Desktop. Usar `docker compose` directo
  (no `wsl … docker compose`). **Nunca** `docker compose down -v` sobre el
  proyecto: borra la base.
- **Archivos en disco D:** el usuario no quiere archivos en C:. Flutter está en
  `D:\flutter`, el SDK de Android en `D:\Program Files\AndroidSDK` y la caché de
  Gradle en `D:\Android\.gradle` (`GRADLE_USER_HOME`).

**Android**

- **Conexión al backend:** el backend publica solo en `127.0.0.1:8001`. Teléfono
  por USB: `adb reverse tcp:8001 tcp:8001` (se pierde al reconectar). Emulador:
  `CS_API_URL=http://10.0.2.2:8001` y al menos 4 GB de RAM en el AVD.
- **Compilar:** desde `movil/`:
  `flutter build apk --debug --dart-define=CS_API_URL=http://localhost:8001`.
  Requiere `movil/android/app/google-services.json`, que no está en Git.

**Pruebas**

- Los tests **nunca** usan la credencial real de Firebase: ambos `conftest.py`
  vacían `FIREBASE_CREDENTIALS_FILE`.
- En pruebas de integración que cierran sesión, crear una sesión propia (los
  headers de sesión de `conftest` no deben revocarse) y limpiar las cookies del cliente.
- Para validar un arreglo, confirmar que la prueba nueva **falla sin él**.
  Se hizo así con el `ticket_id`, el banner y el desborde.

**Forma de trabajo con el usuario**

- **Commits:** no hacer commit ni push hasta que el usuario lo pida.
- **Evidencia:** no hacer capturas de pantalla; él comprueba en su app. Cerrar
  cada cambio con análisis y pruebas.
- **Datos locales:** no inventar datos ni declarar éxito sin evidencia
  (`AGENTS.md`). Los tickets de prueba creados durante la aceptación se borraron.

## 6. Verificación al terminar un cambio

Desde `movil/`:

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

Desde la raíz, con el backend arriba:

```powershell
docker compose exec -T backend ruff check app/ tests/
docker compose exec -T backend mypy app/
docker compose exec -T backend pytest tests/ --ignore=tests/integration -q
docker compose exec -T backend pytest tests/integration -q
node scripts/verification/check-doc-links.mjs
```

Últimos resultados (06-11-2026): Flutter 97 aprobadas + 2 omitidas; backend
245 unitarias y 201 de integración + 8 xfail heredados; Ruff y Mypy limpios.
