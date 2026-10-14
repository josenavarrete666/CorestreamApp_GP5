# Guía de ejecución — iniciar y detener CoreStream

Esta guía ejecuta **`corestream-docker`** usando PowerShell en Windows y Docker
Engine en Ubuntu-24.04/WSL2. Sustituir `C:\ruta\corestream-docker` por la ubicación
real de la carpeta clonada. Los comandos se ejecutan uno por uno.

En una instalación nueva, revisar los requisitos del [README](README.md),
generar `.env` y construir la imagen según la sección 8 antes del inicio diario.
Los datos y archivos privados citados como evidencia de la instalación verificada
no se incluyen en GitHub. No se necesita una carpeta hermana `corestream/` para
ejecutar la aplicación.

## 1. Qué voy a iniciar

Hay dos partes que se ejecutan por separado:

| Terminal | Qué ejecuta | Dónde se ve |
|---|---|---|
| **A — Servidor** | Backend FastAPI, PostgreSQL, Redis y migraciones, dentro de Docker/Ubuntu | API en `http://localhost:8001` |
| **B — Aplicación** | Flutter Web, usando el SDK de Windows | App en Edge, `http://localhost:7358` |

**Mantener abiertas ambas terminales mientras se utilizan sus servicios.**
Los comandos de inicio permanecen ejecutándose; es normal que la terminal
muestre mensajes y no vuelva al indicador donde se escriben comandos.

### Estado actual de la aplicación

- El arranque Docker y el acceso a la API desde Windows ya se verificaron.
- El cierre con Ctrl+C, `compose stop`, el arranque desde Ubuntu detenido y la
  persistencia de PostgreSQL, Redis y archivos se comprobaron en la etapa 5.
- `scripts/start-flutter.ps1` inicia **API real**. `flutter run` sin
  `CS_API_URL` inicia demo, cuyos cambios no se guardan en PostgreSQL.
- La beta/API, el contenido persistente y la presentación 8-Bis están aceptados.
  ARR-FLUTTER está comprobado; **etapa 9 en pausa**. Resultados fechados,
  procedencia y límites en [estado actual](docs/estado-actual.md).
- En la instalación verificada se conservan ADMIN, dataset beta y conjunto manual;
  los fixtures temporales de aceptación se retiraron. Una clonación prepara cuentas
  y datos propios; para repetir mutaciones utilizar un fixture fresco de sección 8.
- Se comprobó que, al detener Flutter, el backend, PostgreSQL y Redis siguen
  funcionando en la terminal A.

## 2. Iniciar el servidor — terminal A

### Paso 1: abrir PowerShell y entrar en el proyecto

```powershell
cd "C:\ruta\corestream-docker"
```

### Paso 2: ejecutar el inicio normal

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start.ps1
```

El script inicia Docker en Ubuntu y ejecuta los servicios con Compose.
Las migraciones preparan o actualizan las tablas de la base de datos.

**Dejar esta terminal abierta.** La sesión activa evita que WSL se apague
al terminar una llamada breve de comandos. No hace falta abrir Docker Desktop.

Si el servidor ya está ejecutándose en otra terminal, utilizar esa sesión;
no iniciar una segunda ventana del mismo script.

### Paso 3: comprobar que está listo

Esperar a que finalice el arranque y abrir en Edge:

- **Salud:** <http://localhost:8001/api/health>
- **Swagger, documentación y pruebas de la API:** <http://localhost:8001/api/docs>

En dos ciclos de verificación, la salud estuvo disponible desde Windows en
**49.55 y 53.42 segundos** desde el inicio del script. Son tiempos de referencia;
esperar a la respuesta de salud para comenzar a utilizar la API.

También se puede comprobar desde otra PowerShell:

```powershell
Invoke-RestMethod -Uri "http://localhost:8001/api/health" -TimeoutSec 15
```

Mantener el timeout de 15 segundos: en esta máquina se observaron respuestas
de `localhost` de algo más de 2 segundos, incluso con los servicios saludables.

La respuesta de salud debe incluir:

```json
{
  "status": "ok",
  "checks": {
    "database": "ok",
    "redis": "ok"
  }
}
```

Esto confirma que el backend responde y puede comunicarse con PostgreSQL
y Redis. Swagger es la documentación del backend, no la interfaz Flutter.

## 3. Iniciar la aplicación Flutter — terminal B

Abrir **otra PowerShell**, dejando la terminal A funcionando.

### Arranque diario con API real — un comando

Desde la raíz `corestream-docker/`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-flutter.ps1
```

El launcher selecciona `.pub-cache/`, resuelve dependencias cuando corresponde,
genera/reutiliza el build API y sirve `http://localhost:7358/`, abriendo Edge.
Requiere Flutter y Node.js >= 22 en `PATH`. Si el backend no está saludable,
el puerto está ocupado o la preparación falla, muestra el error y termina.

**Mantener la terminal B abierta. Ctrl+C detiene solo la web.** Después de editar
Dart, detener y ejecutar de nuevo el mismo comando: detecta los cambios y recompila.
No utiliza hot reload. Opciones: `-PrepareOnly` prepara sin servir; `-Rebuild`
fuerza compilación; `-NoBrowser` omite abrir Edge; `-ApiUrl` selecciona el origen.
[Detalles y resultados comprobados](docs/arranque-flutter.md).

Los pasos siguientes permiten ejecutar demo o depuración con Flutter run.

### Paso 1: entrar en la carpeta de Flutter

```powershell
cd "C:\ruta\corestream-docker\movil"
```

### Paso 2: seleccionar la caché local y resolver las dependencias

```powershell
$env:PUB_CACHE = Join-Path (Resolve-Path "..").Path ".pub-cache"
flutter pub get
```

La primera línea hace que esta terminal use la caché de paquetes dentro de
`corestream-docker/`. Ejecutarla nuevamente cuando se abra una nueva terminal
para Flutter. Si `flutter pub get` termina con un error, resolverlo antes de
continuar con el inicio.

### Paso 3: ejecutar en Edge — elegir modo

**Demo**, datos simulados y selector de perfil:

```powershell
flutter run -d edge --web-port=7358
```

**API real**, con servidor saludable en terminal A:

```powershell
flutter run --no-pub -d edge --web-port=7358 --dart-define=CS_API_URL=http://localhost:8001
```

Ejecutar un modo a la vez. Cambiar modo requiere cerrar el run anterior y
reiniciar con su comando; una recarga no cambia los dart-defines.

Esperar a que Flutter prepare la aplicación y abra Edge. La dirección es:

<http://localhost:7358>

**Dejar la terminal B abierta.** Cerrar una pestaña de Edge no sustituye el
cierre del proceso Flutter.

Para revisar únicamente las pantallas de la demo, Flutter puede ejecutarse
sin el backend, porque el modo demo usa datos simulados.

### Paso 4: recorrer la demo

1. Elegir **Ana Torres** (administrador), **Luis Vega** (líder) o
   **Diego Ramos** (desarrollador) en el selector inicial.
2. Abrir Inicio/Mi trabajo, Proyectos e Incidencias. Ana y Luis también tienen
   la pestaña Equipo. Desde un proyecto se puede abrir el tablero y un ticket.
3. Con las notificaciones simuladas activas en Ajustes, esperar unos 20 segundos:
   aparece un aviso y se actualiza el contador de la campana para el destinatario.
   Esperar a que el aviso desaparezca antes de pulsar la campana; al pulsar el
   propio aviso se abre su recurso asociado.
4. Abrir la campana para revisar notificaciones y marcarlas como leídas.
5. En **Ajustes → Cerrar sesión**, volver al selector y elegir otro perfil.

El primer inicio comprobado tardó **46.1 s** en conectar el depurador Edge.
Esperar al selector visible para empezar a utilizar la aplicación.

### Paso 4 en modo API: recorrer los datos reales

1. Ingresar correo/contraseña de la cuenta local. Perfil/rol vienen de la API.
   Si exige cambio de contraseña, completar el formulario y volver a ingresar.
   En la instalación preparada por 8B.3, Ana utiliza `a.torres@example.com` y
   la contraseña anterior del ADMIN. Las cinco cuentas y claves del manifiesto
   local están descritas en [carga beta](docs/carga-beta-8bis.md).
2. Recorrer **Inicio/Mi trabajo, Proyectos e Incidencias**; gestores también
   **Equipo**. Proyecto → épica/tablero → ticket. Progreso y datos vienen de
   la API, con estados y permisos reales. Sin datos aparecen vacíos explícitos.
3. Usar paneles de creación/asignación como gestor y trabajo como asignado.
   ADMIN no inicia trabajo; developer no resuelve preguntas. PR es opcional.
   Incidentes usan Reportada/Investigando/Mitigada/Resuelta y P1/P2/P3; asignación
   y cambio de estado son acciones separadas. Límites restantes se explican.
4. Abrir la campana: marcar una o todas como leídas y comprobar la reconsulta.
   Una notificación SUPPORT explica el dominio no disponible en ese detalle.
   Cambios y notificaciones se guardan en PostgreSQL.
5. Recargar: con cookies válidas se restaura la sesión. Revisar estado de tiempo
   real; al reconectar se actualiza la bandeja desde HTTP.
6. **Ajustes → Cerrar sesión**: esperar la
   confirmación. Sin conexión, queda cierre pendiente; volver a la red y usar
   **Confirmar cierre con el servidor** antes de iniciar otra sesión.

La beta post-login está integrada en API; Ajustes muestra perfil real, tema e
idioma. La simulación solo existe en demo. [Resultados](docs/estado-actual.md).

### Ejecución web estable comprobada, sin DWDS

Se detectó un fallo `removeChild` de DWDS al reiniciar/recargar debug en esta
máquina. La aceptación final se realizó sobre build release servido estáticamente.
Para usar ese procedimiento, cerrar el run/servidor web anterior de 7358 y,
desde `movil/`, ejecutar cada línea por separado:

```powershell
$env:PUB_CACHE = Join-Path (Resolve-Path "..").Path ".pub-cache"
flutter build web --no-pub --dart-define=CS_API_URL=http://localhost:8001
node ../scripts/serve-web.mjs
```

Abrir <http://localhost:7358> en Edge. Node sirve solo en loopback, sin cache de
respuestas, y debe permanecer en la terminal B. Ctrl+C detiene este servidor;
el backend sigue en la terminal A. Los cambios Dart requieren repetir el build
y recargar la página. No ofrece hot reload; la configuración corresponde a los
dart-defines de ese build. El aviso de CupertinoIcons no impidió la compilación.
La instancia aislada de aceptación se ejecutó con extensiones deshabilitadas.

## 4. Detener todo al terminar

### Paso 1: detener Flutter

En la **terminal B**, pulsar **Ctrl+C** y esperar a que termine el proceso.
Si aparece **«¿Desea terminar el trabajo por lotes (S/N)?»**, escribir **S**
y pulsar **Enter**. Esperar a que vuelva el indicador `PS ...>` antes de cerrar
la ventana. Este paso se observó al ejecutar `flutter.bat` en Windows.

Se comprobó que el puerto 7358 queda libre y que la API de la terminal A
continúa respondiendo con base de datos y Redis `ok`.

### Paso 2: detener el servidor

Activar la **terminal A** haciendo clic en su barra de título, pulsar **Ctrl+C**
y esperar a que Compose detenga los servicios y termine el comando.

Después se pueden cerrar las terminales.

**Detener los servicios no borra la base de datos.** PostgreSQL, Redis y los
documentos utilizan volúmenes de Docker que conservan sus datos entre sesiones.
Los cambios de la demo Flutter, en cambio, son temporales.

Para volver a trabajar otro día, repetir los pasos de inicio.

### Comprobar el cierre

Desde otra PowerShell se puede consultar Ubuntu sin iniciarlo:

```powershell
wsl --list --verbose
```

Si Ubuntu-24.04 aparece como `Stopped`, sus servicios también están detenidos.
Si sigue activo, consultar el estado de Compose con el comando de la sección 6;
backend, PostgreSQL y Redis deben aparecer como `Exited`. En la verificación,
los tres terminaron con código 0 y la API dejó de responder.

Ubuntu puede apagarse automáticamente después de cerrar Compose. El siguiente
`scripts/start.ps1` inicia Ubuntu y Docker nuevamente; ese recorrido también
se comprobó conservando los datos.

## 5. Si perdí la terminal del servidor

Abrir PowerShell y ejecutar:

```powershell
cd "C:\ruta\corestream-docker"
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose stop
```

Esto detiene los servicios de esta copia y conserva los datos.

Se comprobó que también finaliza el comando Compose de la terminal A. Esperar
a que ese comando termine antes de volver a iniciar el servidor. En la prueba,
`compose stop` tardó 5.31 segundos y todos los servicios quedaron `Exited (0)`.

`$PWD` significa «carpeta actual». Para este comando debe ser la raíz
`corestream-docker/`, donde está `docker-compose.yml`, no `movil/`.

## 6. Consultar estado y mensajes

Usar una **tercera terminal PowerShell** para estas consultas, manteniendo
la terminal A abierta.

Primero entrar en la raíz del proyecto:

```powershell
cd "C:\ruta\corestream-docker"
```

### Estado de los servicios

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose ps -a
```

| Resultado | Qué significa |
|---|---|
| `Up ... (healthy)` | Servicio funcionando y comprobaciones correctas |
| `health: starting` | Todavía está inicializándose |
| `unhealthy` | Está fallando su comprobación de salud |
| `migrate` con `Exited (0)` | Las migraciones terminaron correctamente; es normal |
| Backend, PostgreSQL o Redis con `Exited` | Ese servicio está detenido |

### Últimos mensajes del backend

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose logs --no-color --tail 80 backend
```

### Últimos mensajes de todos los servicios

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose logs --no-color --tail 80
```

Si aparece un error, anotar el comando utilizado y su salida para revisarlo.
Estos comandos muestran información; no necesitan detener la sesión principal.

## 7. Cuándo reconstruir la imagen

El inicio diario usa la imagen que ya construimos. Para construirla por primera
vez o actualizarla después de cambiar dependencias de Python o el Dockerfile:

1. Detener la sesión del servidor con Ctrl+C si está ejecutándose.
2. Desde `corestream-docker/`, ejecutar:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start.ps1 -Build
```

Este comando construye la imagen y luego inicia los servicios. También debe
permanecer ejecutándose en su terminal.

Los cambios habituales en el código Python se detectan mediante la recarga
automática del backend; no requieren reconstruir la imagen cada vez.

## 8. Preparación inicial y datos

La instalación donde se registró la evidencia ya tiene Docker Engine en Ubuntu,
Compose, Flutter y `.env`. Una clonación debe instalar los requisitos del README
y generar su propia configuración. La plantilla raíz `.env.example` corresponde
al Compose de esta copia; `backend/.env.example` conserva la referencia ampliada
del backend de origen y no sustituye al generador raíz.

**No hace falta instalar todo ni generar credenciales en cada sesión.**
Si en una nueva copia falta `.env`, generarlo una vez desde la raíz:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/init-env.ps1
```

El generador conserva un `.env` existente. Ese archivo contiene configuración
y credenciales locales, y no se sube al control de versiones.

Construir e iniciar por primera vez en terminal A:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start.ps1 -Build
```

Esperar salud `ok` y migraciones terminadas. En terminal B, desde `movil/`,
resolver dependencias con `flutter pub get` antes del run/build. No copiar
`.pub-cache/`, `.dart_tool/` ni `build/` de otro equipo. Se puede recorrer la demo
sin crear cuentas del backend; modo API necesita una cuenta real.

### Primer ADMIN en una base nueva

En la instalación verificada el ADMIN ya existe. Para una base nueva, con migraciones aplicadas,
ejecutar desde la raíz en una terminal interactiva:

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec backend python -m app.scripts.create_admin --email administrador@example.com --prompt-password
```

Elegir correo propio y contraseña (8–128 caracteres); la contraseña se introduce
oculta y se confirma. `--password-file` permite un archivo protegido. El script
rechaza crear un segundo ADMIN y no se ejecuta automáticamente al iniciar Docker.

### Manifiesto ADMIN para preparar aceptación beta en otra instalación

El ingreso normal no necesita manifiesto. `acceptance_beta setup` y la carga
de contenido de 8B.3 sí necesitan
un archivo local de la identidad ADMIN existente, porque valida UUID, correo y
contraseña antes de preparar los datos.

Antes de guardar las credenciales, preparar el directorio protegido desde la raíz:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/protect-local.ps1
```

Después de crear el ADMIN, obtener su UUID desde `/api/auth/me` usando la sesión
de esa cuenta en Swagger. Crear localmente `backend/.local/admin.json` con esta
estructura, reemplazando los marcadores por los datos de **tu** instalación:

```json
{
  "admin_id": "UUID-REAL-DEL-ADMIN",
  "users": {
    "admin": {
      "email": "administrador@example.com",
      "password": "CONTRASENA-LOCAL-ELEGIDA"
    }
  }
}
```

Este ejemplo es un formato, no credenciales válidas. Guardar el archivo en el
directorio preparado; comprobar sus permisos de Windows desde la raíz:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/protect-local.ps1 -Check
```

Al preparar un fixture, utilizar `--admin-file /app/.local/admin.json` en lugar
de `stage8.json`. No copiar un manifiesto de otra base. El archivo queda fuera
de Git y del contexto Docker, pero el bind mount local permite usarlo en el
contenedor de desarrollo.

### Contenido beta persistente — 8B.3

Para preparar las cinco identidades y los tres proyectos originales en otra
instalación, seguir [carga beta](docs/carga-beta-8bis.md), con ese ADMIN y un UUID
de dataset propio. La herramienta ofrece setup/check/cleanup y protege relaciones.
El conjunto beta convive con los fixtures técnicos; sus credenciales se guardan
en `backend/.local/beta-content.json`. Después de 8B.3, los manifiestos vigentes
del ADMIN contienen el correo actualizado de Ana.

### Datos del recorrido inicial (histórico)

Desde la raíz, con servidor activo, ejecutar cada línea por separado:

```powershell
$runId = [guid]::NewGuid().ToString()
$localFile = "/app/.local/stage8-$runId.json"
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.acceptance_stage8 setup $runId --local-file $localFile
icacls "backend\.local\stage8-$runId.json" /inheritance:r /grant:r "${env:USERNAME}:(F)"
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.acceptance_stage8 check $runId --local-file $localFile
```

El resultado muestra únicamente IDs/estado. El archivo local ignorado guarda
credenciales de líder, developer, other (cambio obligatorio) e inactive. Consultar
esas credenciales localmente para ingresar. Si existe ADMIN, se conserva: sus
credenciales siguen siendo las propias, no las aleatorias del fixture nuevo.

Con Flutter conectado como developer, generar un aviso persistido y publicado:

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.acceptance_stage8 event $runId --local-file $localFile
```

Al terminar, cerrar la sesión API y retirar solamente ese fixture:

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.acceptance_stage8 cleanup $runId --local-file $localFile
```

La herramienta valida destino development, identidad y referencias. Si hay
datos adicionales que apuntan al fixture, aborta cleanup; revisar esos recursos
antes de repetir. ADMIN permanece. El run anterior de la evidencia ya fue retirado;
utilizar UUID y archivo nuevos para repetir, no sus credenciales de usuarios eliminados.

### Datos beta disponibles para recorrido manual

En la instalación verificada, el conjunto
**`ec818fea-557a-4b2a-aa00-1c4872ff670a`** permanece en development.
Esta sección describe ese conjunto histórico/manual; no se crea al clonar.
Consultar localmente `backend/.local/beta-manual.json`, sección `users`, para
ingresar como `admin`, `leader`, `developer` u `other`; no publicar el archivo.
ADMIN original se conservó. `inactive` sirve para comprobar el rechazo de login.

Hay una aplicación principal y otra **Vacía**. La principal tiene dos épicas,
seis DEVELOPMENT (tres completados, tres pendientes, 50%), dos subtareas, cuatro
incidentes y notificaciones reales. El SUPPORT separado no está en el tablero.
Las acciones de aceptación modificaron los datos: el ticket original y el creado
por UI están completados; «Trabajo en progreso» quedó TODO asignado al colaborador,
y el incidente originalmente reportado está Investigando. No se restablecen al
recargar. La comprobación siguiente y el manifiesto permiten consultar los UUID
y estados de esa instalación. [Contexto y evidencia](docs/estado-actual.md).

Comprobarlos desde la raíz, con el servidor activo:

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.acceptance_beta check ec818fea-557a-4b2a-aa00-1c4872ff670a --local-file /app/.local/beta-manual.json
```

Para generar un evento real dirigido al developer de ese conjunto:

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.acceptance_stage8 event ec818fea-557a-4b2a-aa00-1c4872ff670a --local-file /app/.local/beta-manual.json
```

La herramienta `acceptance_beta support-event` permite comprobar además una
notificación SUPPORT rastreada. No retirar el conjunto manual al cerrar el día.
La base usa las migraciones del backend web, pero no contiene un backup de sus
registros; estos recursos son datos locales de esta copia.

### Preparar y retirar un conjunto beta fresco

Con ADMIN existente y su manifiesto protegido, desde la raíz ejecutar cada
línea por separado. Elegir el archivo de tu instalación: `admin.json` recién
preparado o `stage8.json` del entorno verificado, según corresponda:

```powershell
$runId = [guid]::NewGuid().ToString()
$adminFile = "/app/.local/admin.json"
$localFile = "/app/.local/beta-$runId.json"
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.acceptance_beta setup $runId --local-file $localFile --admin-file $adminFile
icacls "backend\.local\beta-$runId.json" /inheritance:r /grant:r "${env:USERNAME}:(F)" "SYSTEM:(F)"
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.acceptance_beta check $runId --local-file $localFile
```

`setup` comprueba las credenciales/identidad del ADMIN existente y rechaza un
manifiesto destino ya presente; no sobrescribe usuarios ni contraseñas. Las
cuentas activas beta no exigen cambio obligatorio; ese flujo conserva aceptación
inicial independiente. El archivo de ADMIN de una base nueva debe corresponder
a esa identidad real, no a un ADMIN aleatorio de otro fixture.

Para la aceptación HTTP nativa, usar **solo ese conjunto fresco**. Desde `movil/`:

```powershell
$env:CS_BETA_FIXTURE = (Resolve-Path "../backend/.local/beta-$runId.json").Path
flutter test --no-pub --reporter expanded test/beta_live_acceptance_test.dart
Remove-Item Env:CS_BETA_FIXTURE
```

Esa prueba modifica recursos y registra el ticket creado en `tracked_tickets`.
Sin variable, la suite general omite este caso y protege los datos manuales.
Al finalizar y con sesiones cerradas, desde la raíz:

```powershell
wsl -d Ubuntu-24.04 -u root --cd "$PWD" --exec /usr/bin/docker compose exec -T backend python -m scripts.acceptance_beta cleanup $runId --local-file $localFile
```

Cleanup comprueba UUID/relaciones y aborta ante referencias no rastreadas,
sin borrar parcialmente el conjunto. Tickets adicionales de aceptación deben
registrarse por UUID en el manifiesto antes del retiro; revisar toda referencia
ajena si la guardia aborta. ADMIN y otros conjuntos se conservan. El run nativo
`1ed20fd7-6dcc-4506-af13-f8f1dd2d4d73` ya fue retirado; no reutilizarlo.

Para el cierre diario usar Ctrl+C o `compose stop`. **No utilizar
`docker compose down -v` para detener el proyecto:** la opción `-v` elimina
los volúmenes y sus datos.

## 9. Direcciones y puertos de referencia

`localhost` y `127.0.0.1` representan este computador cuando se usan desde Windows.

| Servicio | Dirección desde Windows | Dirección interna de Docker |
|---|---|---|
| API FastAPI | `http://localhost:8001` | `backend:8080` |
| Salud | `http://localhost:8001/api/health` | Comprobación del backend y sus dependencias |
| Swagger | `http://localhost:8001/api/docs` | Documentación de la API |
| Flutter Web | `http://localhost:7358` | Se ejecuta en Windows |
| PostgreSQL de Docker | `127.0.0.1:5433` | `postgres:5432` |
| Redis de Docker | `127.0.0.1:6380` | `redis:6379` |

PostgreSQL y Redis no sirven páginas web; sus direcciones se utilizan con
clientes de base de datos. El backend los encuentra por sus nombres internos.

También existe una instalación PostgreSQL independiente en Windows, en el
puerto `5432`. **Para esta copia se usa PostgreSQL de Docker en el puerto
`5433` desde Windows.** Detener Compose no detiene el PostgreSQL de Windows.

## Verificación del repositorio

Desde la raíz, sin iniciar servicios:

```powershell
node scripts/verification/check-doc-links.mjs
node scripts/verification/check-repository.mjs
```

[Herramientas Edge y fixtures](scripts/verification/README.md) y
[estructura para GitHub](docs/publicacion-github.md). Las herramientas se suben
en `scripts/verification/`; sus resultados permanecen locales en `.verification/`.

## 10. Recordatorio rápido

```text
INICIAR
  Terminal A → raíz corestream-docker → scripts/start.ps1
  Comprobar → http://localhost:8001/api/health
  Terminal B → raíz corestream-docker → scripts/start-flutter.ps1 (API real)
    Demo/debug: seguir sección 3 desde movil/ con caché local y dependencias resueltas.

TRABAJAR
  Mantener abiertas las terminales de inicio.
  Usar otra terminal si se necesita consultar el estado o los logs.

TERMINAR
  Ctrl+C en Flutter o en el servidor Node, según el modo ejecutado.
  Ctrl+C en el servidor.
  Esperar a que terminen y cerrar las terminales.

VOLVER OTRO DÍA
  Repetir el inicio; los datos de Docker se conservan.
```

Más información: [README](README.md), [tareas pendientes](TODO_SETUP.md)
y [estado y resultados verificados](docs/estado-actual.md).
