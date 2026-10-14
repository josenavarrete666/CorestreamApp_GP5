"""
Bootstrap del primer ADMIN de CoreStream (plan 3.6).

No hay ningún otro camino para crear un ADMIN: /auth/register ya no existe,
POST /api/users/ fuerza DEVELOPER, y /users/{id}/change-role exige ya ser
ADMIN para llamarlo. Este script es la única puerta de entrada, y es
deliberadamente manual: no se ejecuta en el arranque de la aplicación.

Uso:
    python -m app.scripts.create_admin --email admin@example.com --prompt-password

Use --prompt-password for hidden input or --password-file for a protected file.
Without a password source, the legacy mode generates and prints a password once.

Es idempotente y se niega a crear un segundo ADMIN por accidente: si ya
existe alguno, se detiene y lo informa — usar la propia aplicación
(gestión de equipo) para promover a más administradores a partir de ahí.
"""

from __future__ import annotations

import argparse
import asyncio
import getpass
import secrets
import string
import sys
from pathlib import Path

from sqlalchemy import select

from app.database import get_session_maker
from app.models import Role, User, UserRole
from app.services.auth_service import AuthService


def _generate_password(length: int = 20) -> str:
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()"
    return "".join(secrets.choice(alphabet) for _ in range(length))


async def create_admin(email: str, password: str | None, full_name: str) -> None:
    email = email.lower().strip()

    async with get_session_maker()() as db:
        existing_admin = await db.execute(
            select(User).join(Role, User.role_id == Role.id).where(Role.name == UserRole.ADMIN.value)
        )
        if existing_admin.scalars().first() is not None:
            print(
                "Ya existe al menos un ADMIN en el sistema. Este script no crea un "
                "segundo por seguridad — usa la gestión de equipo dentro de la "
                "aplicación (o POST /api/users/{id}/change-role) para promover a más."
            )
            sys.exit(1)

        existing_user = await db.execute(select(User).where(User.email == email))
        if existing_user.scalars().first() is not None:
            print(f"Ya existe un usuario con el email {email}. Aborta.")
            sys.exit(1)

        role_result = await db.execute(select(Role).where(Role.name == UserRole.ADMIN.value))
        admin_role = role_result.scalars().first()
        if admin_role is None:
            print(
                "El rol ADMIN no existe en la base de datos todavía. "
                "Aplica las migraciones (alembic upgrade head) antes de correr esto."
            )
            sys.exit(1)

        final_password = password or _generate_password()

        # AuthService.hash_password, NO middleware.auth.hash_password: el
        # login (routers/auth.py) verifica con AuthService.verify_password,
        # que antes de bcrypt aplica un pre-hash SHA-256 (evita el límite de
        # 72 bytes de bcrypt). middleware.auth.hash_password es un bcrypt
        # liso sin ese pre-hash — un hash suyo nunca verifica en el login.
        # Se detectó porque este mismo bootstrap fallaba con "credenciales
        # incorrectas" usando la contraseña recién creada.
        admin_user = User(
            email=email,
            full_name=full_name,
            hashed_password=AuthService.hash_password(final_password),
            role_id=admin_role.id,
            is_active=True,
        )
        db.add(admin_user)
        await db.commit()

    print(f"ADMIN creado: {email}")
    if not password:
        print(f"Contraseña generada (guárdala ahora, no se puede recuperar): {final_password}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Crea el primer usuario ADMIN de CoreStream.")
    parser.add_argument("--email", required=True, help="Correo del administrador")
    parser.add_argument("--full-name", default="Administrador", help="Nombre completo")
    parser.add_argument(
        "--password",
        default=None,
        help="Contraseña a usar. Si se omite, se genera una aleatoria y se imprime una vez.",
    )
    parser.add_argument("--password-file", type=Path, help="Archivo local protegido de contraseña")
    parser.add_argument("--prompt-password", action="store_true", help="Entrada oculta interactiva")
    args = parser.parse_args()
    if sum(bool(value) for value in (args.password, args.password_file, args.prompt_password)) > 1:
        parser.error("Elegir una sola fuente de contraseña")
    password = args.password
    if args.password_file:
        password = args.password_file.read_text(encoding="utf-8").rstrip("\r\n")
    elif args.prompt_password:
        password = getpass.getpass("Contraseña: ")
        if password != getpass.getpass("Confirmar contraseña: "):
            parser.error("Las contraseñas no coinciden")
    if password is not None and not 8 <= len(password) <= 128:
        parser.error("La contraseña debe tener entre 8 y 128 caracteres")
    asyncio.run(create_admin(args.email, password, args.full_name))


if __name__ == "__main__":
    main()
