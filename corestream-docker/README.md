# CoreStream — Flutter, FastAPI y Docker

Aplicación Flutter con demo en memoria y modo API real para proyectos, tickets,
incidencias, equipo y notificaciones. FastAPI utiliza PostgreSQL y Redis;
el entorno de desarrollo está preparado para Windows/PowerShell y Docker Engine
en Ubuntu-24.04/WSL2.

Esta carpeta es la raíz del repositorio. Para ejecutar la aplicación no se
necesitan las carpetas hermanas `corestream/` ni `Documentacion/`; la procedencia
y decisiones se resumen en [estado actual](docs/estado-actual.md).

## Estado del desarrollo

**Base funcional completada:** login real → Inicio/Mi trabajo,
proyectos/tableros/tickets, incidencias, Equipo, campana/avisos y Ajustes reales.
Etapas 1–8, 8-Bis y ARR-FLUTTER cerradas: operaciones/persistencia con tres roles,
contenido beta, identidad, login, pantallas e interacción aceptados en Edge.
Última regresión registrada (13-10-2026): **79 Flutter + 2 omitidas**, 1 live
adicional, analyze/build correctos; **24 combinaciones/176 capturas nuevas**.
Los resultados anteriores y la evidencia reutilizada tienen su alcance y fecha
en [estado actual](docs/estado-actual.md), junto con los ocho xfail heredados.

**Siguiente desarrollo: requisitos de Equipo 1 y Android.** Etapa 9 permanece
en pausa por indicación del usuario. Alcance y tareas en [TODO_SETUP](TODO_SETUP.md);
contratos de la base en [matriz beta/API](docs/matriz-beta-api.md).
Para recorrer datos locales: [carga y cuentas beta](docs/carga-beta-8bis.md).

El primer intento detectó un error de Redis durante el apagado de Ubuntu.
Se resolvió manteniendo una sesión de Compose en primer plano con
`scripts/start.ps1`. Esa terminal debe permanecer abierta mientras se usa
CoreStream: los servicios de `systemd` por sí solos no mantienen WSL activo.

## Estructura del repositorio

```text
corestream-docker/
├── movil/               Código Flutter, pruebas, web, pubspec y lockfile
├── backend/             FastAPI, Alembic, SQL, Dockerfile, scripts y pruebas
├── docs/                Guías, contratos, requisitos y estado consolidado
├── scripts/             Configuración local, arranque y servidor web
│   └── verification/    Comprobadores y automatizaciones versionables
├── docker-compose.yml   PostgreSQL, Redis, migraciones y API
├── .env.example
├── .gitignore
├── .gitattributes
├── GUIA_EJECUCION.md
└── TODO_SETUP.md
```

Código, pruebas, migraciones, plantillas y documentación se versionan.
Credenciales, cachés, builds, capturas y datos locales se regeneran o se preparan
en cada instalación. Política y pasos para subir este proyecto:
[publicación en GitHub](docs/publicacion-github.md).

## Requisitos del entorno

- Git, para clonar/versionar el proyecto.
- Windows con PowerShell y WSL2 Ubuntu-24.04 con `systemd`.
- Docker Engine y plugin Docker Compose dentro de Ubuntu. Entorno comprobado:
  Engine 29.9.0 / Compose 5.6.0. Docker Desktop no es necesario.
- Flutter >= 3.35.0 en el `PATH`; comprobado con Flutter 3.47.2 / Dart 3.13.2.
- Edge para el recorrido web.
- Node.js >= 22 para servidor estático y herramientas de verificación;
  utilizan módulos incorporados y no requieren `npm install`.

Instalación de herramientas: [WSL](https://learn.microsoft.com/windows/wsl/install),
[Docker Engine en Ubuntu](https://docs.docker.com/engine/install/ubuntu/) y
[Flutter](https://docs.flutter.dev/get-started/install).
Android se genera y valida en la etapa 10.

## Servicios y puertos

| Servicio | Acceso desde Windows | Dentro de Docker |
|---|---|---|
| PostgreSQL 15 | `127.0.0.1:5433` | `postgres:5432` |
| Redis 7 | `127.0.0.1:6380` | `redis:6379` |
| FastAPI | `http://localhost:8001` | `backend:8080` |
| Flutter Web | `http://localhost:7358` | Se ejecuta en Windows |

Los volúmenes propios de Compose conservan la base, Redis y los documentos
dentro del almacenamiento de Docker en Ubuntu. El nombre Compose es
`corestream-docker`.

## Primera ejecución después de clonar

Abrir PowerShell en la raíz clonada, donde está `docker-compose.yml`.
Generar configuración local una vez; se conserva cualquier `.env` existente:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/init-env.ps1
```

Construir e iniciar los servicios en esta terminal y mantenerla abierta:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start.ps1 -Build
```

Para el inicio diario, después de tener la imagen construida:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start.ps1
```

El script comprueba que existe `.env`, espera el inicio de Docker y ejecuta
`docker compose up` en primer plano dentro de Ubuntu. No usar solamente
`docker compose up -d` desde llamadas WSL breves: cuando termina la última
sesión activa, Ubuntu puede apagarse y detener el conjunto.

`migrate` aplica Alembic una vez y debe terminar con código 0. El backend espera
su resultado y la disponibilidad de Redis. Los demás servicios deben quedar
saludables. La versión actualizada publica notificaciones desde la API.

- Salud: <http://localhost:8001/api/health>.
- Swagger: <http://localhost:8001/api/docs>.
- OpenAPI: <http://localhost:8001/api/openapi.json>.

Para detener los servicios conservando los datos, pulsar **Ctrl+C** en la
terminal de `scripts/start.ps1`. Los datos permanecen en los volúmenes locales
de Docker.

Para consultar el estado desde otra terminal PowerShell, manteniendo la primera
abierta:

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose ps -a
```

## Flutter en Windows

Para la **API real**, con el backend saludable en su propia terminal, desde la
raíz `corestream-docker/` ejecutar un comando:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-flutter.ps1
```

Configura la caché, resuelve dependencias y compila cuando corresponda, sirve
la web en `http://localhost:7358/` y abre Edge. Mantener la terminal abierta;
Ctrl+C detiene solo la web. Después de cambiar Dart, detener y volver a ejecutar
el comando para actualizar el build. Opciones: `-PrepareOnly`, `-Rebuild`,
`-NoBrowser`, `-ApiUrl`. [Funcionamiento y evidencia](docs/arranque-flutter.md).

Para la **demo/debug**, desde `corestream-docker/movil/`:

```powershell
$env:PUB_CACHE = Join-Path (Resolve-Path "..").Path ".pub-cache"
flutter pub get
flutter run -d edge --web-port=7358
```

La demo utiliza datos simulados en memoria. Su validación en esta copia está
resumida en [estado actual](docs/estado-actual.md). Para cerrar Flutter, pulsar
Ctrl+C en su terminal; si Windows pregunta si se desea terminar el trabajo por
lotes, responder `S` y Enter hasta volver al indicador PowerShell.

Para depurar la **API real** con Flutter run, con el servidor activo:

```powershell
flutter run --no-pub -d edge --web-port=7358 --dart-define=CS_API_URL=http://localhost:8001
```

Se muestra formulario de credenciales y la interfaz beta integrada. Una base
nueva no contiene las cuentas ni los datos de la instalación donde se registró
la evidencia. Crear el primer ADMIN con el comando siguiente y preparar datos
con las herramientas de la guía; no hay usuario/password predeterminados. Mantener
`localhost` en ambas URLs para cookies/CSRF. Preparación de datos y bootstrap:
[guía de ejecución](GUIA_EJECUCION.md). Contratos y límites de dominios/nativo:
[contratos-api.md](docs/contratos-api.md).

## Comprobaciones posteriores del backend

Una vez verificado el arranque, desde la terminal Ubuntu en esta copia:

```bash
docker compose exec -T backend pytest tests/ --ignore=tests/integration -x -q
docker compose exec -T backend pytest tests/integration -x -q
docker compose exec -T backend ruff check app/ tests/ scripts/acceptance_stage8.py
docker compose exec -T backend mypy app/ scripts/acceptance_stage8.py
```

Las pruebas de integración utilizan su base `corestream_test` y Redis db 15.
La creación del primer administrador se realiza explícitamente una sola vez:

```bash
docker compose exec backend python -m app.scripts.create_admin --email administrador@example.com --prompt-password
```

La entrada es oculta y confirmada; alternativamente admite `--password-file`.
La herramienta rechaza un segundo ADMIN. Si ya existe uno en tu base local,
conservarlo. Los manifiestos privados de la instalación original no se distribuyen.

## Verificar la estructura publicable

Desde la raíz, sin iniciar Docker ni Flutter:

```powershell
node scripts/verification/check-doc-links.mjs
node scripts/verification/check-repository.mjs
```

El segundo comando comprueba inclusiones/exclusiones mediante un Git temporal,
genera una copia aislada de los archivos publicables y verifica sus enlaces y
sintaxis Node. No inicializa Git en esta carpeta ni realiza commits.
[Herramientas y recorridos Edge](scripts/verification/README.md).

## Documentación

- [Guía para iniciar y detener CoreStream](GUIA_EJECUCION.md).
- [Estado actual, decisiones y evidencia consolidada](docs/estado-actual.md).
- [Tareas pendientes de Equipo 1 y Android](TODO_SETUP.md).
- [Estructura y publicación en GitHub](docs/publicacion-github.md).
- [Herramientas de verificación](scripts/verification/README.md).
- [Arquitectura](docs/arquitectura.md).
- [Contratos de API](docs/contratos-api.md).
- [Matriz de acciones beta/API](docs/matriz-beta-api.md).
- [Roles y permisos](docs/roles-permisos.md).
- [Carga beta y cuentas locales](docs/carga-beta-8bis.md).
- [Correspondencia y procedencia del contenido](docs/contenido-beta-8bis.md).
- [Arranque Flutter](docs/arranque-flutter.md).
- [Requisitos](docs/requerimientos/README.md).
