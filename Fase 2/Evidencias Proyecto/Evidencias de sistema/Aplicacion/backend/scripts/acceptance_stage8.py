"""Prepare isolated development acceptance data; never print credentials."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import secrets
from datetime import timedelta
from pathlib import Path
from urllib.parse import urlparse
from uuid import UUID, uuid4, uuid5

from sqlalchemy import delete, func, or_, select
from sqlalchemy.engine import make_url

from app.config import get_settings
from app.database import dispose_engine, get_session_maker
from app.middleware.auth import create_access_token
from app.models import Application, Base, Epic, Notification, Role, Ticket, User
from app.redis_client import close_redis, init_redis
from app.scripts.create_admin import create_admin
from app.services.auth_service import AuthService
from app.services.notification_service import create_notification, publish_notification


def save(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as out:
        json.dump(data, out, indent=2)
    path.chmod(0o600)


def identifiers(run_id: UUID) -> dict[str, str]:
    return {key: str(uuid5(run_id, key)) for key in (
        "leader", "developer", "other", "inactive", "application", "epic", "ticket",
    )}


async def run(action: str, run_id: UUID, path: Path) -> dict:
    settings = get_settings()
    url = make_url(settings.DATABASE_URL)
    if settings.ENVIRONMENT != "development" or url.host != "postgres" or url.database != "corestream":
        raise RuntimeError("Expected Docker development database corestream")
    redis_url = urlparse(settings.REDIS_URL)
    if redis_url.hostname != "redis" or redis_url.path != "/0":
        raise RuntimeError("Expected Docker development Redis db 0")
    prefix = f"Verification stage 8 - {run_id}"
    ids = identifiers(run_id)
    if action == "setup" and not await asyncio.to_thread(path.exists):
        data = {"run_id": str(run_id), "ids": ids, "notifications": [], "users": {
            key: {"email": f"stage8-{run_id.hex[:12]}-{key}@example.com",
                  "password": secrets.token_urlsafe(24) + "Aa1!"}
            for key in ("admin", "leader", "developer", "other", "inactive")
        }}
        await asyncio.to_thread(save, path, data)
    data = json.loads(await asyncio.to_thread(path.read_text, encoding="utf-8"))
    if data["run_id"] != str(run_id) or data["ids"] != ids:
        raise RuntimeError("Fixture identity mismatch")
    async with get_session_maker()() as db:
        roles = {role.name: role.id for role in (await db.execute(select(Role))).scalars()}
        if action == "setup":
            admin = (await db.execute(select(User).where(User.role_id == roles["ADMIN"]))).scalars().first()
            if admin is None:
                credentials = data["users"]["admin"]
                await create_admin(credentials["email"], credentials["password"], "Administrador local")
                admin = (await db.execute(select(User).where(User.email == credentials["email"]))).scalar_one()
            data["admin_id"] = str(admin.id)
            if await db.get(Application, UUID(ids["application"])):
                raise RuntimeError("Fixture already exists; use check or a fresh run UUID")
            for key in ("leader", "developer", "other", "inactive"):
                credentials = data["users"][key]
                if (await db.execute(select(User).where(User.email == credentials["email"]))).scalar_one_or_none():
                    raise RuntimeError("User collision; no data overwritten")
                db.add(User(id=UUID(ids[key]), email=credentials["email"],
                            full_name=f"Stage 8 {key}", role_id=roles["TEAM_LEADER" if key == "leader" else "DEVELOPER"],
                            hashed_password=AuthService.hash_password(credentials["password"]),
                            is_active=key != "inactive", must_change_password=key == "other"))
            await db.flush()
            db.add(Application(id=UUID(ids["application"]), name=prefix, owner_id=admin.id, is_active=True))
            await db.flush()
            db.add(Epic(id=UUID(ids["epic"]), title=prefix, application_id=UUID(ids["application"])))
            await db.flush()
            db.add(Ticket(id=UUID(ids["ticket"]), title=prefix, epic_id=UUID(ids["epic"]),
                          assignee_id=UUID(ids["developer"]), created_by_id=UUID(ids["leader"])))
            await db.flush()
            for key in ("developer", "other"):
                notification = await create_notification(db, user_id=ids[key], title=prefix,
                    message=f"Aceptación real: {key}", notification_type="TICKET_ASSIGNED", ticket_id=ids["ticket"])
                await db.flush()
                data["notifications"].append(str(notification.id))
            await db.commit()
            await asyncio.to_thread(save, path, data)
        application = await db.get(Application, UUID(ids["application"]))
        if not application or application.name != prefix:
            raise RuntimeError("Fixture application missing or changed")
        for key in ("leader", "developer", "other", "inactive"):
            user = await db.get(User, UUID(ids[key]))
            expected_role = roles["TEAM_LEADER" if key == "leader" else "DEVELOPER"]
            if not user or user.email != data["users"][key]["email"] or user.role_id != expected_role:
                raise RuntimeError("Fixture user missing or changed")
        epic = await db.get(Epic, UUID(ids["epic"]))
        ticket = await db.get(Ticket, UUID(ids["ticket"]))
        if not epic or epic.application_id != application.id or not ticket or ticket.epic_id != epic.id:
            raise RuntimeError("Fixture relationship missing or changed")
        if action == "expired-access":
            data["expired_access"] = create_access_token(
                {"sub": ids["developer"], "role": "DEVELOPER"},
                expires_delta=timedelta(seconds=-30),
            )
            await asyncio.to_thread(save, path, data)
            return {"run_id": str(run_id), "expired_access_prepared": True}
        if action == "event":
            notification = await create_notification(db, user_id=ids["developer"], title=prefix,
                message=f"Evento WS real {uuid4()}", notification_type="SYSTEM", ticket_id=ids["ticket"])
            await db.commit()
            await db.refresh(notification)
            data["notifications"].append(str(notification.id))
            await asyncio.to_thread(save, path, data)
            await init_redis()
            try:
                published = await publish_notification(notification)
            finally:
                await close_redis()
            return {"run_id": str(run_id), "notification_id": str(notification.id), "published": published}
        notifications = (await db.execute(select(Notification).where(
            Notification.id.in_([UUID(value) for value in data["notifications"]])))).scalars().all()
        if len(notifications) != len(data["notifications"]) or any(n.title != prefix for n in notifications):
            raise RuntimeError("Fixture notification missing or changed")
        result = {"run_id": str(run_id), "ids": ids, "admin_id": data["admin_id"],
                  "notifications": [{"id": str(n.id), "user_id": str(n.user_id), "is_read": n.is_read}
                                    for n in notifications], "verified": True}
        if action == "cleanup":
            owned = {
                "users": [UUID(ids[key]) for key in ("leader", "developer", "other", "inactive")],
                "applications": [application.id], "epics": [epic.id], "tickets": [ticket.id],
                "notifications": [n.id for n in notifications],
            }
            for table in Base.metadata.sorted_tables:
                references = [column.in_(owned[fk.column.table.name])
                              for column in table.columns for fk in column.foreign_keys
                              if fk.column.table.name in owned]
                if not references:
                    continue
                statement = select(func.count()).select_from(table).where(or_(*references))
                if table.name in owned:
                    statement = statement.where(table.c.id.not_in(owned[table.name]))
                if (await db.execute(statement)).scalar_one():
                    raise RuntimeError(f"Untracked references in {table.name}; cleanup aborted")
            await db.execute(delete(Notification).where(Notification.id.in_([n.id for n in notifications])))
            await db.execute(delete(Ticket).where(Ticket.id == UUID(ids["ticket"])))
            await db.execute(delete(Epic).where(Epic.id == UUID(ids["epic"])))
            await db.execute(delete(Application).where(Application.id == application.id))
            for key in ("leader", "developer", "other", "inactive"):
                user = await db.get(User, UUID(ids[key]))
                if not user or user.email != data["users"][key]["email"]:
                    raise RuntimeError("User identity changed; cleanup aborted")
                await db.execute(delete(User).where(User.id == user.id))
            await db.commit()
            result["removed"] = True
        return result


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("setup", "check", "event", "expired-access", "cleanup"))
    parser.add_argument("run_id", type=UUID)
    parser.add_argument("--local-file", type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(await run(args.action, args.run_id, args.local_file), indent=2))
    finally:
        await dispose_engine()


if __name__ == "__main__":
    asyncio.run(main())
