# Carga persistente del contenido beta — 8B.3

**12 de octubre de 2026 (UTC).** Implementación y aceptación del conjunto definido
en [8B.2](contenido-beta-8bis.md). Resultado local: datos persistidos en PostgreSQL,
cinco cuentas comprobadas por HTTP, preparación repetida sin duplicados y contenido
conservado después de reiniciar el backend. Evidencia: [estado actual](estado-actual.md).

## Herramientas y alcance

- [beta_content_seed.json](../backend/scripts/beta_content_seed.json): contenido
  público versionado, textos del seed y conversiones explícitas de 8B.2. Incluye
  offsets temporales; no contiene contraseñas ni UUID propios de una instalación.
- [beta_content.py](../backend/scripts/beta_content.py): `setup`, `check` y
  `cleanup`, con UUIDv5 por dataset/alias, snapshot de procedencia y T0 estable.
- [check_beta_content.py](../backend/scripts/check_beta_content.py): baseline
  de huellas SQL y aceptación HTTP del conjunto recién preparado. Compara las
  filas anteriores y comprueba las cinco cuentas, metadata, tickets, fechas,
  subtareas, historial, incidencias y notificaciones.
- [protect-local.ps1](../scripts/protect-local.ps1): protección Windows de
  `backend/.local/` para usuario actual, SYSTEM y Administradores. `-Check`
  verifica las reglas del directorio sin modificarlas.
- Pruebas: [unitarias](../backend/tests/test_beta_content.py) e
  [integración PostgreSQL/HTTP](../backend/tests/integration/test_beta_content.py).

La carga utiliza el Docker de desarrollo `corestream`, Redis db 0 y SQL_ECHO
desactivado. Las pruebas usan `corestream_test` y Redis db 15. La herramienta de
carga no publica notificaciones históricas por WS y no necesita migraciones.

## Cuentas de la instalación preparada

| Alias | Nombre | Rol | Correo | Clave de credenciales en el manifiesto |
|---|---|---|---|---|
| u1 | Ana Torres | ADMIN | `a.torres@example.com` | `users.admin` |
| u2 | Luis Vega | TEAM_LEADER | `l.vega@example.com` | `users.u2` |
| u3 | Diego Ramos | DEVELOPER | `d.ramos@example.com` | `users.u3` |
| u4 | Sofía Márquez | DEVELOPER | `s.marquez@example.com` | `users.u4` |
| u5 | Marco Ibáñez | DEVELOPER | `m.ibanez@example.com` | `users.u5` |

Las contraseñas están exclusivamente en `backend/.local/beta-content.json`.
Ana utiliza la contraseña anterior del ADMIN. Las otras cuatro fueron generadas
al preparar el conjunto. El manifiesto contiene `email` y `password` en cada
entrada de la tabla; se consulta localmente para ingresar por credenciales.
Los comandos de comprobación imprimen resultados públicos, no contraseñas.

En esta instalación, `stage8.json` y `beta-manual.json` se actualizaron con el
correo nuevo del mismo ADMIN, conservando las demás claves y credenciales. Los
archivos históricos del fixture retirado conservan su procedencia anterior.

Al entrar nuevamente al modo API se consultan los datos persistidos. El conjunto
beta convive con los datos técnicos anteriores: existen **5 aplicaciones en
total**, 3 beta y 2 técnicas; SQL contiene **9 usuarios**, 5 anteriores
incluido ADMIN y 4 nuevos. El directorio API excluye usuarios inactivos.
Los contadores globales reflejan esa convivencia.
En la aceptación, Ana tenía 6 avisos no leídos: 4 anteriores más 2 beta.

La metadata de color/especialidad está persistida. Su presentación coherente en
Flutter, la ampliación del selector developer y el rediseño del login se completaron
en 8-Bis; [decisiones y resultados consolidados](estado-actual.md).

## Preparación en una instalación nueva

Arrancar los servicios según la [guía de ejecución](../GUIA_EJECUCION.md).
Desde la raíz clonada, proteger el directorio antes de guardar credenciales:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/protect-local.ps1
```

Después preparar el primer ADMIN y su manifiesto según esa guía. El ejemplo
siguiente presupone `backend/.local/admin.json` con `admin_id` y
`users.admin.email/password`.

En un filesystem Linux nativo, los manifiestos se escriben atómicamente con
modo 0600. En este montaje Windows/WSL, `stat` muestra 777 aunque se aplique
`chmod`; la protección efectiva se comprobó mediante ACL de Windows. Los
archivos nuevos heredan las reglas privadas de `.local/`.

Elegir un UUID de dataset **una sola vez**, antes de la primera carga:

```powershell
$dataset = [guid]::NewGuid().ToString()
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.beta_content setup $dataset --local-file .local/beta-content.json --admin-file .local/admin.json
```

Si hay otros manifiestos vigentes que contienen ese mismo ADMIN, añadir
`--related-admin-file .local/otro-manifiesto.json` por cada uno. La herramienta
verifica identidad, correo y contraseña coincidentes antes de insertar, y
actualiza únicamente el correo de `users.admin` en esos archivos.

El primer setup conserva en el manifiesto el UUID del dataset, T0, mapa de
identificadores, snapshot del seed, credenciales generadas y estado de la carga.
Los UUID de una instalación no se copian a otra. La aplicación mantiene su flujo
normal de invitaciones; estas cuentas se preparan con una herramienta local.

## Repetición y comprobación habitual

Para una instalación ya preparada, usar su `dataset_id`, consultable en el
manifiesto local. En esta instalación concreta:

```powershell
$dataset = 'a8cae710-913d-468c-b872-9239ed8d6585'
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.beta_content check $dataset --local-file .local/beta-content.json
```

Repetir `setup` con **ese mismo UUID y archivo** verifica el conjunto existente;
no restablece títulos, estados, lectura, contraseñas, fechas o timers modificados
durante el uso. La comprobación admite asignaciones nuevas y cambios de contenido,
pero exige filas rastreadas, identidad de cuentas y relaciones dentro del conjunto.
No recrea registros eliminados ni adopta usuarios o UUID ajenos.

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.beta_content setup $dataset --local-file .local/beta-content.json
```

Los estados del manifiesto son `prepared`, `active`, `removing` y `removed`:

- `prepared`: existe una preparación recuperable. Si SQL falló, se reintenta la
  inserción atómica con las mismas credenciales/T0. Si SQL se confirmó y falló
  la actualización de archivos, se reconcilian los manifiestos sin insertar otra vez.
- `active`: contenido preparado; las repeticiones solo verifican identidad y relaciones.
- `removing`: retiro iniciado; una repetición de cleanup reconcilia un retiro
  ya confirmado o completa la operación tras un fallo.
- `removed`: dataset retirado. Ese manifiesto no vuelve a preparar datos.

Las operaciones sobre el mismo manifiesto tienen bloqueo de archivo y la carga
usa un advisory lock transaccional en PostgreSQL. Cambios en fuentes ADMIN,
colisiones o filas incompletas se notifican sin sobrescribir información.

## Aceptación del conjunto recién preparado

El baseline se obtiene **antes** de la primera carga; contiene huellas de filas,
no sus valores ni credenciales. En una instalación nueva, ejecutar antes de setup:

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.check_beta_content baseline --baseline-file .local/beta-content-before.json
```

Después del setup, la verificación real utiliza el mismo baseline y dataset:

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.check_beta_content verify --dataset-id $dataset --content-file .local/beta-content.json --baseline-file .local/beta-content-before.json
```

La aceptación HTTP usa el servidor TCP del contenedor en `127.0.0.1:8080`,
inicia y cierra una sesión propia por cuenta y consulta las rutas `/api/...`.
Este recorrido compara el contenido inicial exactamente; después de editarlo
por uso normal, utilizar `beta_content check` para la comprobación habitual.

## Retiro explícito

`cleanup` solo retira las cuatro cuentas nuevas y los recursos identificados
en ese manifiesto. Ana es una identidad compartida: se conserva su cuenta con
el nombre/correo actualizado. Las referencias ajenas, incluidos eventos o
notificaciones posteriores no rastreados, detienen el retiro antes de borrar.

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.beta_content cleanup $dataset --local-file .local/beta-content.json
```

El retiro se verificó con un dataset de pruebas aislado. El conjunto manual
real se conservó al cierre para recorrer la aplicación. Los archivos `.local/` están
excluidos de Git y del contexto Docker y conservan las credenciales/procedencia.

## Resultados de esta instalación

- Dataset: `a8cae710-913d-468c-b872-9239ed8d6585`.
- T0: **2026-10-12T23:35:27.543646+00:00**.
- ADMIN conservado: `283e96d0-08c7-47a4-af65-e731112d4bb7`.
- Proyectos a1/a2/a3: `cc3c016a-6daa-5ed0-a478-f80b5e6864fb`,
  `8da9ac67-9508-59ad-8a81-f1895b40531d`, `be5c11c3-af20-5202-9452-b879599663b1`.
- Conjunto comprobado: 5 personas, 3 aplicaciones, 5 épicas, 9 DEVELOPMENT,
  20 subtareas, 19 eventos, 5 incidencias y 8 notificaciones.
- Segunda preparación: mismos UUID, T0, conteos y estado `active`; `reused=True`.
- Baseline SQL: filas técnicas anteriores intactas; ADMIN conserva rol,
  UUID, hash/contraseña, creación y flag de cambio obligatorio.
- Login/perfil/notificaciones/logout: **5 de 5 cuentas aprobadas**, antes y
  después del reinicio del backend; metadata y recursos consultables por HTTP.
- **7 pruebas unitarias** (6 nuevas + 1 herramienta anterior) y **8 de
  integración** (7 nuevas + 1 herramienta anterior) aprobadas. Ruff limpio;
  Mypy con `--explicit-package-bases`, 78 fuentes sin errores.
- En el dataset de test, las acciones HTTP de edición, subtarea, lectura e
  inicio de trabajo persistieron en SQL y sobrevivieron a la repetición de setup;
  también se preservaron un cambio de contraseña y su flag.

Las diferencias de estados, severidades, contexto de incidencias y timer se
aplicaron según [correspondencia del contenido](contenido-beta-8bis.md).
Identidad, login, pantallas e interacción 8-Bis están aceptados; fixtures temporales
retirados y cinco cuentas/baseline preservados. [Estado y evidencia](estado-actual.md),
[ARR-FLUTTER completada](arranque-flutter.md); etapa 9 en pausa.
