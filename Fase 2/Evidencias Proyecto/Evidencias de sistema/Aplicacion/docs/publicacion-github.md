# Estructura del repositorio y publicación en GitHub

La raíz del repositorio es **`corestream-docker/`**: subir su contenido, sin
incluir las carpetas hermanas `corestream/` ni `Documentacion/`.
La aplicación demo/API utiliza los archivos de esta raíz. Las referencias a
esas carpetas en registros históricos describen la procedencia del trabajo.

## Archivos que se versionan

| Ubicación | Contenido que debe acompañar al proyecto |
|---|---|
| Raíz | README, guía, TODO, Compose, `.gitignore`, `.gitattributes`, `.env.example` |
| `backend/app/` | Código FastAPI y servicios |
| `backend/alembic/`, `backend/migrations/`, `alembic.ini` | Migraciones y SQL de estructura, no copias de datos |
| Configuración backend | Dockerfile, `.dockerignore`, `.env.example`, `requirements*.txt`, `pyproject.toml`, `pytest.ini` |
| `backend/tests/`, `backend/scripts/` | Pruebas y herramientas de preparación/comprobación de datos |
| `movil/lib/`, `movil/test/`, `movil/web/` | Aplicación Flutter, regresión y plataforma web |
| Configuración Flutter | `pubspec.yaml`, **`pubspec.lock`**, `analysis_options.yaml`, `.metadata`, `.gitignore`, README |
| `scripts/` | Generador de configuración, arranque, servidor web y herramientas de verificación |
| `docs/` | Arquitectura, contratos/permisos, requisitos Word, wireframe, guías y estado consolidado |

Conservar el lockfile de la aplicación Flutter, los tests y las migraciones.
Cuando se genere Android en etapa 10, su código/configuración de proyecto también
se versiona; `local.properties`, `.gradle`, builds y claves de firma continúan
excluidos. Los informes y referencias anteriores están consolidados en
[estado actual](estado-actual.md); sus versiones completas permanecen en Git.

## Archivos que permanecen locales

- `.env` y variantes con valores reales. Las plantillas `.env.example` son públicas.
- `backend/.local/`: credenciales y manifiestos con UUID del entorno preparado.
- `.pub-cache/`, `.cache/` (huellas del launcher), `.dart_tool/`, cachés Python,
  entornos virtuales y `node_modules/`.
- `build/`, cobertura, logs, capturas y `.verification/`.
- `storage/`, `backups/`, archivos SQLite y datos físicos de PostgreSQL.
- Configuración personal de editores/sistema y claves de firma Android.
- `commands.txt`: recordatorio local con rutas de este equipo. Se conserva en
  disco, ignorado; los comandos útiles ya están en la guía y los scripts.

La exclusión no borra esos archivos. `.gitattributes` normaliza los finales de
línea de fuentes/scripts y conserva Word/imágenes como binarios.
`backend/.dockerignore` excluye además `.local/`: el contexto Docker se filtra
independientemente de Git y no debe copiar los manifiestos privados a la imagen.

PostgreSQL, Redis y documentos persistentes se conservan en **volúmenes Docker
locales**. No se suben con el código. Una clonación prepara su configuración,
aplica las migraciones y crea sus propias cuentas/datos; no distribuye los
usuarios y contraseñas de la instalación donde se generó la evidencia.

## Comprobar la estructura antes de subir

Con Git y Node.js >= 22 instalados, desde esta raíz:

```powershell
node scripts/verification/check-doc-links.mjs
node scripts/verification/check-repository.mjs
```

El segundo comando simula la selección de archivos usando las reglas Git,
comprueba exclusiones e inclusiones necesarias y valida una copia aislada con
solo los candidatos. Usa un Git temporal y lo retira al terminar; no inicializa
este repositorio ni hace commits. El alcance es estructura, enlaces y sintaxis
Node; no sustituye las suites de aplicación ni inspecciona el historial Git.

Herramientas y automatizaciones Edge:
[scripts/verification/README.md](../scripts/verification/README.md).
Para ejecutar una instalación nueva: [README](../README.md) y
[guía](../GUIA_EJECUCION.md).

## Publicación por el propietario

Estos pasos son para cuando decidas subir el proyecto. Crear en GitHub un
repositorio vacío y sustituir `TU_USUARIO`/`TU_REPOSITORIO` por sus valores.
Desde la raíz de `corestream-docker/`, ejecutar uno por uno:

```powershell
git init -b main
git add .
git status --short
git diff --cached --stat
```

Revisar la selección: debe contener el código/configuración/documentación
descritos arriba, no `.env`, `backend/.local/`, `.pub-cache/`, `.verification/`
ni builds. Después:

```powershell
git commit -m "Initial project setup"
git remote add origin https://github.com/TU_USUARIO/TU_REPOSITORIO.git
git push -u origin main
```

Si ya inicializaste Git o configuraste el remoto, revisar `git status` y
`git remote -v` en lugar de repetir esa inicialización. `.gitignore` no retira
archivos ya versionados: la selección del primer commit se revisa antes de enviarla.

La preparación de la carpeta no crea repositorio remoto ni publica archivos.
El estado vigente se sigue en [TODO_SETUP](../TODO_SETUP.md): 8B.1–8B.8
completadas, [ARR-FLUTTER comprobada](arranque-flutter.md); etapa 9 permanece en pausa.
