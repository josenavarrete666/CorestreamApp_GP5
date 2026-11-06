# Base de datos — CoreStream App (Fase 2)

Exportación de la base PostgreSQL 15 de desarrollo del 05-11-2026, con las
migraciones hasta `k7l8m9n0o1p2` (dispositivos push, APP-06).

| Archivo | Contenido |
|---|---|
| `01_esquema.sql` | Esquema completo: 18 tablas, índices, claves y tipos enumerados |
| `02_datos_beta.sql` | Datos del dataset beta: 5 usuarios `@alloxentric.com`, 3 roles, 3 aplicaciones, 5 épicas, 10 tickets, 20 subtareas, 20 eventos, 5 incidencias y 9 notificaciones |

## Qué se excluyó por seguridad

- `users.hashed_password`: reemplazado por `!SIN-HASH`, que no valida ninguna
  contraseña. Las contraseñas del equipo no se publican.
- `user_devices` (tokens FCM de teléfonos reales), `invitations` y
  `password_reset_tokens`: solo esquema, sin filas.

## Restaurar en una base vacía

```powershell
docker compose exec -T postgres psql -U corestream -c "CREATE DATABASE corestream_evidencia"
Get-Content 01_esquema.sql, 02_datos_beta.sql -Encoding UTF8 | docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U corestream -d corestream_evidencia
```

Para iniciar sesión con estas cuentas hay que asignarles contraseña con
`scripts/setup-dev-accounts.ps1` del proyecto (carpeta `Aplicacion/`).
La restauración se comprobó en una base temporal: 5 usuarios, 10 tickets y
9 notificaciones, sin errores.
