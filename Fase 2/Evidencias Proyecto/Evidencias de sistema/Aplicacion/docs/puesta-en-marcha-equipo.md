# Puesta en marcha para el equipo — Windows con Docker Desktop

Guía para que un integrante del equipo descargue la rama `corestream-mobile` y
ejecute el proyecto completo en su equipo: backend, app web y app Android con
push (APP-03/APP-06). La [guía de ejecución](../GUIA_EJECUCION.md) describe la
variante con Docker dentro de Ubuntu/WSL; aquí se usa **Docker Desktop**.

## 1. Qué trae el repositorio y qué no

El repositorio incluye todo el código, las migraciones, la plataforma Android
(`movil/android/`), los logos y la fuente Manrope. **No incluye** archivos
locales ni secretos; cada persona los prepara en su equipo:

| Archivo (fuera de Git) | Para qué sirve | Cómo se obtiene |
|---|---|---|
| `.env` | Contraseña de PostgreSQL y clave JWT locales | Se genera con `scripts/init-env.ps1` (paso 3) |
| `backend/.local/<cuenta-de-servicio>.json` | Credencial de Firebase para que el backend **envíe** push reales | Consola de Firebase (paso 6) |
| `movil/android/app/google-services.json` | Configuración Firebase de la app Android; **sin él no compila el APK** | Consola de Firebase (paso 6) |
| `backend/.local/credenciales-dev.json` | Contraseñas compartidas de las 5 cuentas `@alloxentric` del equipo | Se recibe del equipo por un canal privado (paso 5) |
| `backend/.local/admin.json`, `beta-content.json` | Manifiestos locales de la carga beta | Los crea `scripts/setup-dev-accounts.ps1` (paso 5) |

Nunca subir esos archivos a GitHub ni pegarlos en chats públicos.

## 2. Requisitos

Instalar, idealmente en el disco con más espacio:

- **Git** y acceso al repositorio `josenavarrete666/Corestream_Grupo1`.
- **Docker Desktop** con WSL2 y la virtualización activada en el BIOS.
- **Flutter** 3.35 o superior en el `PATH` (probado con 3.47.9).
- **Node.js** 22 o superior (para el servidor de la app web).
- **Android Studio** con el SDK de Android, solo si se va a probar en un teléfono.

Clonar la rama:

```powershell
git clone --branch corestream-mobile https://github.com/josenavarrete666/Corestream_Grupo1.git
cd Corestream_Grupo1
```

## 3. Backend (API, PostgreSQL y Redis)

Con Docker Desktop abierto y mostrando *Engine running*:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/init-env.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/protect-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-desktop.ps1 -Build
```

La primera vez construye la imagen (incluye `firebase-admin`) y aplica todas las
migraciones, incluidas las de dispositivos push. Dejar esa terminal abierta.
Comprobar desde otra terminal:

```powershell
curl http://localhost:8001/api/health
```

Debe responder `"status":"ok"`. Los días siguientes basta con
`scripts/start-desktop.ps1` sin `-Build`, o en segundo plano:

```powershell
docker compose up -d --no-build
```

Para detener sin perder datos: Ctrl+C en esa terminal o `docker compose stop`.
**Nunca** usar `docker compose down -v`: borra la base de datos.

## 4. App web (navegador)

En otra terminal, desde la raíz del proyecto:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-flutter.ps1
```

Compila la app y la sirve en `http://localhost:7358`, que se abre en el
navegador predeterminado. Si se usa `flutter run` y el navegador no es Edge ni
Chrome (por ejemplo Brave), definir antes `CHROME_EXECUTABLE` con la ruta del
navegador y usar `-d chrome`.

## 5. Cuentas y datos de prueba

La base nace vacía: sin cuentas no se puede iniciar sesión y la app muestra
contadores en cero. El equipo usa **las mismas 5 cuentas `@alloxentric`** en
todos los equipos:

| Persona | Rol | Correo |
|---|---|---|
| Ana Torres | ADMIN | `a.torres@alloxentric.com` |
| Luis Vega | TEAM_LEADER | `l.vega@alloxentric.com` |
| Diego Ramos | DEVELOPER | `d.ramos@alloxentric.com` |
| Sofía Márquez | DEVELOPER | `s.marquez@alloxentric.com` |
| Marco Ibáñez | DEVELOPER | `m.ibanez@alloxentric.com` |

Las contraseñas **no están en GitHub**: van en `credenciales-dev.json`, que un
integrante del equipo comparte por un canal privado.

1. Copiar `credenciales-dev.json` en `backend/.local/`.
2. Con el backend arriba (paso 3), ejecutar desde la raíz:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup-dev-accounts.ps1
   ```

   Crea el ADMIN (Ana), carga el contenido beta (5 personas, 3 proyectos,
   9 tickets, 5 incidencias y 8 notificaciones), aplica las contraseñas del
   archivo y verifica el conjunto. Termina con «Cuentas @alloxentric listas».

Si se vuelve a ejecutar, no duplica nada: solo realinea las contraseñas con el
archivo (útil si el equipo las cambia). Los datos de cada base son
independientes: lo que se cree o modifique en un equipo no aparece en el otro.

Formato de `credenciales-dev.json`: una lista con `nombre`, `rol`, `email` y
`password` por cuenta, con exactamente una cuenta `ADMIN`. Para cargar los
datos a mano, ver [carga beta](carga-beta-8bis.md).

## 6. Firebase (push en Android)

El proyecto Firebase ya existe: **`corestreamappg5`**, con la app Android
`com.alloxentric.corestream`. **No hay que crear otro**; hay que obtener dos
archivos de ese proyecto.

El acceso al repositorio de GitHub **no** da acceso a Firebase; son permisos
separados.

- **Recomendado:** que el dueño del proyecto lo agregue en
  [console.firebase.google.com](https://console.firebase.google.com): proyecto
  `corestreamappg5` → ⚙️ → *Usuarios y permisos* → *Agregar miembro*, con su
  correo de Google y rol **Editor**. Así cada uno descarga los archivos con su
  propia cuenta.
- **Alternativa:** recibir los dos archivos por un canal privado. El
  `google-services.json` es el mismo para todos; la clave de cuenta de servicio
  conviene que cada uno genere la suya.

Pasos con acceso a la consola:

1. *Configuración del proyecto → General → Tus apps → Android*: descargar
   **`google-services.json`** y copiarlo en `movil/android/app/`.
2. *Configuración del proyecto → Cuentas de servicio → Generar nueva clave
   privada*: guardar el JSON en `backend/.local/`.
3. Añadir al `.env` la ruta **dentro del contenedor**:

   ```
   FIREBASE_CREDENTIALS_FILE=/app/.local/<nombre-del-archivo>.json
   ```

4. Recrear el backend para que lea la variable: `docker compose up -d --no-build`.

Sin la credencial del paso 2 todo funciona igual, pero el envío push queda
**simulado** (solo se registra en el log del backend). Sin el
`google-services.json` del paso 1 **no compila** la app Android; la web no lo necesita.

## 7. App Android en un teléfono

1. En Android Studio, instalar el SDK de Android y apuntar Flutter a él:

   ```powershell
   flutter config --android-sdk "<ruta-del-SDK>"
   ```

   Opcional: definir la variable de usuario `GRADLE_USER_HOME` en un disco con
   espacio, porque la primera compilación descarga varios GB.

2. En el teléfono: activar *Opciones de desarrollador* (tocar 7 veces *Número de
   compilación*) y *Depuración USB*. Conectar por cable de datos y aceptar el
   aviso de depuración. Comprobar que aparece como `device`:

   ```powershell
   adb devices
   ```

3. El backend solo escucha en `127.0.0.1` del PC, así que el teléfono lo alcanza
   por el cable USB. Repetir este comando cada vez que se reconecte el cable:

   ```powershell
   adb reverse tcp:8001 tcp:8001
   ```

4. Compilar e instalar, desde `movil/`:

   ```powershell
   flutter build apk --debug --dart-define=CS_API_URL=http://localhost:8001
   adb install -r build\app\outputs\flutter-apk\app-debug.apk
   ```

   O directamente: `flutter run --dart-define=CS_API_URL=http://localhost:8001`.
   En un emulador se usa `http://10.0.2.2:8001` en lugar de `localhost`. Si el
   emulador se queda en el logo de Google, subirle la RAM a 4 GB.

`adb` está en `<ruta-del-SDK>\platform-tools\`; agregar esa carpeta al `PATH` o
usar la ruta completa.

## 8. Comprobar push (APP-03 y APP-06)

1. Iniciar sesión en el teléfono como Diego (`d.ramos@alloxentric.com`) y
   aceptar el permiso de notificaciones. La app registra el dispositivo.
2. Dejar la app en segundo plano (botón de inicio o «atrás» desde Inicio).
3. Desde la web, como Luis (`l.vega@alloxentric.com`), crear un ticket asignado
   a Diego: debe llegar el push al teléfono, y al tocarlo se abre el ticket.
4. En el teléfono, *Ajustes → Cerrar sesión* (aparece «Sesión revocada.») y
   asignar otro ticket: ya **no** debe llegar.

Con Samsung, si el push no llega con la app cerrada, poner la batería de la app
en *Sin restricciones*.

## 9. Pruebas y verificación

Desde `movil/`:

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

Desde la raíz, con el backend arriba:

```powershell
docker compose exec -T backend pytest tests/ --ignore=tests/integration -q
docker compose exec -T backend pytest tests/integration -q
```

Las pruebas nunca usan la credencial real de Firebase. Contratos de la API en
[contratos API](contratos-api.md) y estado del proyecto en [estado actual](estado-actual.md).
