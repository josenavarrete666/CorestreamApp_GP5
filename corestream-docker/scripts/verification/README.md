# Herramientas de verificación

Herramientas versionadas que utilizan módulos incorporados de **Node.js >= 22**.
No requieren `npm install`. Se resuelven respecto de la raíz del proyecto, no
respecto de la ruta de este equipo. Resultados y capturas se guardan en
`.verification/`, que continúa ignorada por Git.

## Comprobaciones sin servidor

El arranque diario de la web API se realiza con `scripts/start-flutter.ps1`
desde la raíz; [ARR-FLUTTER](../../docs/arranque-flutter.md) registra preparación,
actualización Dart, acceso Edge, errores y cierre con Ctrl+C. La caché y la
evidencia de ese recorrido permanecen excluidas de la publicación.

Desde la raíz:

```powershell
node scripts/verification/check-doc-links.mjs
node scripts/verification/check-repository.mjs
```

- `check-doc-links.mjs`: comprueba enlaces a archivos locales en README, guía,
  TODO y todos los Markdown de `docs/` y `scripts/`; omite URLs externas y bloques
  de código. No comprueba los fragmentos de encabezados.
- `check-repository.mjs`: requiere Git, crea un repositorio temporal fuera de
  la carpeta de trabajo y comprueba qué archivos incluirían las reglas actuales.
  Verifica 27 casos de exclusión y archivos esenciales, copia los candidatos a
  una carpeta aislada y ejecuta allí comprobaciones de enlaces/sintaxis Node.
  Retira la carpeta temporal al terminar. No crea `.git` en este proyecto,
  no prepara commits y no contacta con GitHub.
- Para elegir una carpeta temporal existente:
  `node scripts/verification/check-repository.mjs --temp-dir "C:\ruta\temporal"`.
- El comprobador simula una primera publicación de los archivos de trabajo.
  Si después ya tienes un repositorio, revisar también `git status` y los archivos
  preparados: las reglas de ignore no retiran archivos previamente versionados.

## Automatizaciones Edge — beta/API actual

`edge-beta.mjs` conserva el controlador utilizado en B01–B18. Requiere el build
API en `http://localhost:7358`, backend en `http://localhost:8001`, interfaz ES y
una instancia aislada de Edge con CDP habilitado. Para iniciarla en Windows:

```powershell
$edge = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
& $edge --remote-debugging-port=9237 --user-data-dir="$env:TEMP\corestream-verification-edge" --disable-extensions --no-first-run http://localhost:7358/
```

Los perfiles de aceptación pertenecen a datos preparados con
`backend/scripts/acceptance_beta.py`, descritos en la
[guía](../../GUIA_EJECUCION.md). El manifiesto privado por defecto es
`backend/.local/beta-manual.json`; para elegir un conjunto fresco:

```powershell
$env:CS_BETA_FIXTURE = (Resolve-Path 'backend/.local/beta-NUEVO-UUID.json').Path
node scripts/verification/edge-beta.mjs 9237 state
node scripts/verification/edge-beta.mjs 9237 login developer
```

`state` no necesita manifiesto. Los demás recorridos que usan cuentas o recursos
requieren uno real, generado en esa instalación. Los nombres de proyecto,
incidentes y tickets esperados son los del fixture técnico de etapa 8.

| Acción | Efecto |
|---|---|
| `state`, `screenshot <nombre>` | Consultar pantalla / guardar imagen local |
| `login <rol>`, `switch <rol>`, `logout` | Ingresar/cambiar/cerrar sesiones del navegador aislado |
| `read-suite`, `visual-suite` | Recorrer perfiles/pantallas; cambia sesión y preferencias de presentación |
| `identity-suite` | Metadata beta-content, tres roles / dos tamaños, oscuro ES, 28 capturas; sin mutaciones de contenido |
| `screens-suite`, `screens-suite --resume` | Pantallas/paneles beta-content, tres roles / dos tamaños, oscuro ES y claro EN, 240 capturas; sin envíos de contenido |
| `board-check` | Beta-content, ES; t7 como botón y selección con Tab/Enter |
| `interaction-check --report` | Fixture técnico fresco: red/avisos/lecturas/SUPPORT/aislamiento; modifica notificaciones temporales |
| `acceptance-suite --report`, `acceptance-suite --resume --report` | Beta-content, 24 combinaciones, 176 capturas; sin escrituras de contenido |
| `operations`, `ticket-cycle`, `incident-operations` | Modificar recursos reales; utilizar un fixture de aceptación fresco |
| `event`, `support-event` | Crear/publicar notificación rastreada mediante Docker/WSL |
| `network-suite`, `reconnect`, `filters` | Comprobar recuperación HTTP, conexión WS o filtros |

Las acciones mutantes no se ejecutan sobre el conjunto manual para comprobar
solo la estructura del repositorio. `CS_BETA_FIXTURE` selecciona el manifiesto;
los eventos requieren que esté dentro de `backend/`, accesible en el bind mount.
Los scripts no imprimen contraseñas ni tokens. La acción `fill` es un control
genérico de texto, no el procedimiento recomendado para introducir credenciales.

### Identidad beta persistente — 8B.4

`identity-suite` usa el manifiesto de `backend/scripts/beta_content.py`, no el
fixture técnico de etapa 8. Requiere build API, idioma ES y tema oscuro en un
perfil Edge aislado con CDP (por ejemplo 9240):

```powershell
$env:CS_BETA_FIXTURE = (Resolve-Path 'backend/.local/beta-content.json').Path
node scripts/verification/edge-beta.mjs 9240 identity-suite
node scripts/verification/edge-beta.mjs 9240 close
```

Revisa proyectos/monogramas, Equipo, Ajustes, responsable y selector autorizado.
Guarda `beta-8b4-*.png` en `.verification/`, cierra sesiones y comprueba que no
hubo escrituras de contenido. Los recorridos mutantes y `read-suite/visual-suite`
conservan expectativas del fixture técnico; no usarlos con beta-content.
[Evidencia y límites](../../docs/estado-actual.md).

### Login y estados de sesión — 8B.5

`edge-auth.mjs` requiere build API, backend y un perfil Edge aislado con CDP
(por ejemplo 9241). Cambia preferencias de tema/idioma y tamaño del navegador.
Ejecutar cada línea por separado, desde la raíz:

```powershell
$env:CS_AUTH_FIXTURE = (Resolve-Path 'backend/.local/beta-content.json').Path
node scripts/verification/edge-auth.mjs 9241 visual
node scripts/verification/edge-auth.mjs 9241 sessions
```

- `visual`: ocho combinaciones oscuro/claro × ES/EN × 390×844/1280×900,
  cinco estados; 40 capturas. Usa credenciales visibles de ejemplo y un 429
  inyectado con CDP; no necesita leer un manifiesto ni dispara el rate-limit real.
- `sessions`: manifiesto beta-content activo (predeterminado), ADMIN/Luis/Diego;
  login, refresh y logout reales, 401 real, cierre pendiente con fallo de transporte
  inyectado y recuperación real. No modifica contenido beta; 13 capturas.
- `password`: modifica contraseña/flag de la cuenta `other` de un fixture stage8
  fresco. Guarda la contraseña nueva solo en su manifiesto privado para recuperación,
  comprueba reingreso y termina con logout; cuatro capturas. No usar beta-content.

Para `password`, definir `$proyecto` como raíz de la copia y preparar un UUID nuevo:

```powershell
$authRun = [guid]::NewGuid().ToString()
$authFile = ".local/auth-$authRun.json"
wsl -d Ubuntu-24.04 -u root --cd "$proyecto" --exec /usr/bin/docker compose exec -T backend python -m scripts.acceptance_stage8 setup $authRun --local-file $authFile
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/protect-local.ps1 -Check
$env:CS_AUTH_FIXTURE = (Resolve-Path "backend/$authFile").Path
node scripts/verification/edge-auth.mjs 9241 password
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/protect-local.ps1 -Check
wsl -d Ubuntu-24.04 -u root --cd "$proyecto" --exec /usr/bin/docker compose exec -T backend python -m scripts.acceptance_stage8 cleanup $authRun --local-file $authFile
node scripts/verification/edge-beta.mjs 9241 close
```

Revisar cada resultado antes del siguiente paso; si el recorrido falla, conservar
el manifiesto para diagnóstico/retiro por UUID. Una segunda prueba de cambio
obligatorio necesita otro fixture nuevo. Cleanup conserva el ADMIN y aborta si
hay referencias ajenas. En NTFS/WSL, comprobar ACL Windows; permisos Linux 0600
no sustituyen esa comprobación. Si la ACL no está preparada, seguir
[la guía de protección local](../../docs/carga-beta-8bis.md).

Los reportes `8b5-{visual,sessions,password}-report.json` y las capturas `8b5-*.png`
se guardan localmente; repetir el mismo recorrido sobrescribe sus nombres.
No se imprimen credenciales ni se registran cuerpos de requests/respuestas.
`edge-beta close` admite desconexión antes de responder a Browser.close. Contrastar
el cierre con puerto CDP/proceso, aunque CDP termine por timeout o desconexión.
[Resultados y límites](../../docs/estado-actual.md).

### Pantallas y paneles persistentes — 8B.6

`screens-suite` requiere manifiesto beta-content activo, build API y backend,
con perfil Edge aislado/CDP (por ejemplo 9242). Desde la raíz, uno por uno:

```powershell
$env:CS_BETA_FIXTURE = (Resolve-Path 'backend/.local/beta-content.json').Path
node scripts/verification/edge-beta.mjs 9242 screens-suite
node scripts/verification/edge-beta.mjs 9242 close
```

Recorre Ana/Luis/Diego, 390×844 y 1280×900, oscuro ES y claro EN: 12 casos,
240 capturas. Abre pantallas, detalles, historial y paneles autorizados sin enviar
acciones ni marcar avisos leídos. Cambia sesiones/preferencias y termina en oscuro
ES con logout. No acredita la matriz independiente tema × idioma de 8B.8.

Reporte `beta-8b6-screens-report.json` y `beta-8b6-*.png` en `.verification/`;
repetir sobrescribe esos nombres. El reporte guarda checkpoints por caso y solo
marca `complete:true` al completar los doce, sin excepciones/escrituras. Para
continuar un reporte incompleto sin excepciones, antes de cerrar Edge:

```powershell
node scripts/verification/edge-beta.mjs 9242 screens-suite --resume
```

Reanudar presupone mismo build/dataset y reporte local existente; no mezclar
resultados de versiones distintas. `state` incluye viewport; la emulación de
tamaño pertenece a la conexión CDP, por lo que puede revertirse al desconectarla.
El controlador comprueba dimensiones durante cada caso. En 8B.7 se corrigió la
omisión semántica de t7 y se retiró el fallback; ahora exige un botón visible.
[Comparación, resultados y corrección semántica](../../docs/estado-actual.md).

### Interacción y aceptación final — 8B.7–8B.8

Con un fixture técnico fresco preparado mediante `scripts.acceptance_beta`,
ADMIN autenticado y CS_BETA_FIXTURE apuntando a ese manifiesto:

```powershell
node scripts/verification/edge-beta.mjs 9243 operations --report
node scripts/verification/edge-beta.mjs 9243 incident-operations --report
node scripts/verification/edge-beta.mjs 9243 interaction-check --report
```

Ejecutar uno por uno y revisar el resultado; operations termina en developer,
incident-operations mantiene esa cuenta e interaction-check termina sin sesión.
Para reconexión: `switch developer --report`, luego `reconnect --report` y logout.
No repetir operaciones a ciegas después de un fallo: revisar SQL/estado y usar un
fixture nuevo si se necesita repetir el ciclo. Cleanup por UUID conserva el ADMIN.
`--report` guarda trazas sanitizadas locales y presenta un resumen de mutaciones.

Después del retiro de los datos temporales, usar beta-content activo:

```powershell
$env:CS_BETA_FIXTURE = (Resolve-Path 'backend/.local/beta-content.json').Path
node scripts/verification/edge-beta.mjs 9243 acceptance-suite --report
node scripts/verification/edge-beta.mjs 9243 close
```

La matriz valida 24 casos. Cinco imágenes por caso, más pantallas/paneles de las
combinaciones faltantes de 8B.6: total 176. Reutiliza evidencia histórica de las
otras pantallas, termina en oscuro ES/logout y guarda `8b8-acceptance-report.json`.
Para continuar un checkpoint aprobado con el mismo build/dataset:
`acceptance-suite --resume --report`. Los casos completados no se repiten.
[Resultados, datos y límites](../../docs/estado-actual.md).

## Automatización demo

`edge-demo.mjs` se utiliza con la aplicación compilada/ejecutada **sin**
`CS_API_URL`, interfaz ES y otro perfil/puerto CDP. Por ejemplo, con CDP 9239:

```powershell
node scripts/verification/edge-demo.mjs 9239 state
node scripts/verification/edge-demo.mjs 9239 tap 'Ana Torres'
```

Las capturas `stage6-*.png` se escriben en `.verification/` sin sobrescribir las
existentes. Cerrar el servidor de 7358 antes de cambiar demo/API y recompilar o
reiniciar Flutter con el modo elegido.

## Referencias históricas locales

Los comandos históricos `.verification/edge-beta.mjs` y `edge-demo.mjs` tenían
sus controladores en la carpeta de resultados. En esta instalación se mantienen
pequeños wrappers locales de compatibilidad; una clonación usa los comandos de
`scripts/verification/` documentados arriba.

El antiguo `check-copy.mjs` comparaba hashes con `../corestream` para auditar la
copia inicial. Su comprobación de enlaces se reemplaza por `check-doc-links.mjs`.
El controlador API inicial y el recolector de la beta original permanecen como
instrumentación histórica local: no son requisitos para ejecutar esta aplicación.
La referencia visual se obtuvo de esa beta original; sus informes están
consolidados en [estado actual](../../docs/estado-actual.md) y recuperables en Git.
