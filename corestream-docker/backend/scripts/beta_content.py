"""Import tracked beta examples into local development; never print credentials."""

from __future__ import annotations

import argparse
import asyncio
import fcntl
import hashlib
import json
import os
import secrets
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from uuid import UUID, uuid5

from sqlalchemy import delete, func, or_, select, text
from sqlalchemy.engine import make_url

from app.config import get_settings
from app.database import dispose_engine, get_session_maker
from app.models import (
    Application,
    Base,
    Epic,
    Notification,
    Role,
    Subtask,
    Ticket,
    TicketEvent,
    User,
)
from app.models.incident import Incident
from app.services.auth_service import AuthService

LOCAL_DIRECTORY = Path(__file__).resolve().parents[1] / ".local"
SEED_FILE = Path(__file__).with_name("beta_content_seed.json")
MODELS: dict[str, Any] = {"users": User, "applications": Application, "epics": Epic, "tickets": Ticket,
          "subtasks": Subtask, "ticket_events": TicketEvent, "incidents": Incident,
          "notifications": Notification}
REFERENCES = {"application_id": "applications", "epic_id": "epics", "ticket_id": "tickets",
              "assignee_id": "users", "created_by_id": "users", "assigned_to_id": "users",
              "user_id": "users", "from_user_id": "users", "to_user_id": "users"}


class ContentError(RuntimeError):
    pass


def guard() -> None:
    settings = get_settings()
    url = make_url(settings.DATABASE_URL)
    redis = urlparse(settings.REDIS_URL)
    if settings.ENVIRONMENT != "development" or url.host != "postgres" or url.database != "corestream":
        raise ContentError("Expected Docker development database corestream")
    if redis.hostname != "redis" or redis.path != "/0":
        raise ContentError("Expected Docker development Redis db 0")
    if settings.SQL_ECHO:
        raise ContentError("Disable SQL_ECHO before importing local credentials")


def local_path(path: Path) -> Path:
    resolved = path.resolve()
    if not resolved.is_relative_to(LOCAL_DIRECTORY.resolve()) or resolved.suffix != ".json":
        raise ContentError("Local manifests must be JSON files inside backend/.local")
    return resolved


def read_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise ContentError("Cannot read a required JSON file") from exc
    if not isinstance(data, dict):
        raise ContentError("Expected a JSON object")
    return data


def save_atomic(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            json.dump(data, out, ensure_ascii=False, indent=2)
            out.write("\n")
            out.flush()
            os.fsync(out.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def acquire_lock(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path.with_suffix(".lock"), os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as exc:
        os.close(fd)
        raise ContentError("An operation is already running for this manifest") from exc
    return fd


def digest(data: dict) -> str:
    return hashlib.sha256(json.dumps(data, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def identifiers(dataset_id: UUID, admin_id: UUID, seed: dict) -> dict:
    ids = {table: {row["alias"]: str(uuid5(dataset_id, f"beta-v1/{table}/{row['alias']}"))
                   for row in seed[table]} for table in MODELS}
    ids["users"]["u1"] = str(admin_id)
    return ids


def credentials(data: dict) -> dict:
    try:
        UUID(data["admin_id"])
        result = data["users"]["admin"]
        if not isinstance(result["email"], str) or not isinstance(result["password"], str):
            raise ValueError
        if not result["email"] or not result["password"]:
            raise ValueError
    except (KeyError, TypeError, ValueError) as exc:
        raise ContentError("Existing ADMIN manifest is incomplete") from exc
    return result


def validate_manifest(data: dict, dataset_id: UUID, seed: dict) -> None:
    try:
        valid = (data["purpose"] == "beta-content" and data["schema_version"] == 1
                 and data["dataset_id"] == str(dataset_id) and data["seed_sha256"] == digest(seed)
                 and data["ids"] == identifiers(dataset_id, UUID(data["admin_id"]), seed)
                 and data["state"] in {"prepared", "active", "removing", "removed"}
                 and datetime.fromisoformat(data["reference_at"]).utcoffset() == timedelta(0))
        credentials(data)
        for alias in ("u2", "u3", "u4", "u5"):
            if not data["users"][alias]["password"]:
                valid = False
    except (KeyError, TypeError, ValueError) as exc:
        raise ContentError("Content manifest is incomplete") from exc
    if not valid:
        raise ContentError("Content manifest identity or seed version mismatch")


async def rows_by_table(db, data: dict) -> dict:
    rows = {}
    for table, model in MODELS.items():
        ids = [UUID(value) for value in data["ids"][table].values()]
        rows[table] = {str(item.id): item for item in
                       (await db.execute(select(model).where(model.id.in_(ids)))).scalars()}
    return rows


def owned_ids(data: dict) -> dict:
    return {table: [UUID(value) for alias, value in values.items()
                    if not (table == "users" and alias == "u1")]
            for table, values in data["ids"].items()}


async def assert_no_collisions(db, data: dict, seed: dict) -> None:
    for table, model in MODELS.items():
        ids = owned_ids(data)[table]
        if (await db.execute(select(func.count()).select_from(model).where(model.id.in_(ids)))).scalar_one():
            raise ContentError(f"UUID collision in {table}; no existing data overwritten")
    for row in seed["users"]:
        occupant = (await db.execute(select(User).where(User.email == row["email"]))).scalar_one_or_none()
        if occupant is not None and str(occupant.id) != data["admin_id"]:
            raise ContentError("Email collision; no existing account adopted")


async def prepare_manifest(db, dataset_id: UUID, seed: dict, admin_file: Path,
                           related_files: list[Path]) -> dict:
    source_paths = list(dict.fromkeys([admin_file, *related_files]))
    sources = [(path, await asyncio.to_thread(read_json, path)) for path in source_paths]
    source = sources[0][1]
    admin_credentials = credentials(source)
    admin = await db.get(User, UUID(source["admin_id"]))
    roles = {role.name: role.id for role in (await db.execute(select(Role))).scalars()}
    if not {"ADMIN", "TEAM_LEADER", "DEVELOPER"}.issubset(roles):
        raise ContentError("Required roles are missing")
    if (admin is None or admin.role_id != roles["ADMIN"] or not admin.is_active
            or admin.email != admin_credentials["email"]
            or not AuthService.verify_password(admin_credentials["password"], admin.hashed_password)):
        raise ContentError("Existing ADMIN identity or credentials do not match")
    for _, other in sources:
        other_credentials = credentials(other)
        if (other.get("admin_id") != str(admin.id)
                or any(other_credentials[key] != admin_credentials[key] for key in ("email", "password"))):
            raise ContentError("Related ADMIN manifests are inconsistent")
    now = datetime.now(timezone.utc).isoformat()
    data: dict[str, Any] = {"purpose": "beta-content", "schema_version": 1, "dataset_id": str(dataset_id),
            "seed_sha256": digest(seed), "source_snapshot": seed, "state": "prepared",
            "reference_at": now, "admin_id": str(admin.id),
            "ids": identifiers(dataset_id, admin.id, seed),
            "admin_sources": [str(path) for path in source_paths],
            "admin_before": {"email": admin.email, "full_name": admin.full_name,
                             "specialty": admin.specialty, "preferences": admin.preferences,
                             "role_id": str(admin.role_id), "created_at": admin.created_at.isoformat(),
                             "must_change_password": admin.must_change_password,
                             "password_fingerprint": hashlib.sha256(admin.hashed_password.encode()).hexdigest()},
            "users": {"admin": {"email": seed["users"][0]["email"],
                                "password": admin_credentials["password"]}}}
    for row in seed["users"][1:]:
        data["users"][row["alias"]] = {"email": row["email"],
                                      "password": secrets.token_urlsafe(24) + "Aa1!"}
    await assert_no_collisions(db, data, seed)
    return data


def moment(data: dict, offset: int = 0) -> datetime:
    return datetime.fromisoformat(data["reference_at"]) + timedelta(seconds=offset)


def incident_description(row: dict, data: dict, seed: dict) -> str:
    context = ["Contexto importado de la beta:", f"Referencia original: INC-{row['beta_number']}",
               f"Categoría original: {row['beta_category']}",
               f"Estado original: {row['beta_status']}", f"Severidad original: {row['beta_severity']}"]
    for comment in row.get("comments", []):
        author = next(user["full_name"] for user in seed["users"] if user["alias"] == comment["user_id"])
        timestamp = moment(data, comment["created_offset"]).isoformat()
        context.append(f"Comentario histórico de {author} ({timestamp}): {comment['message']}")
    return row["description"] + "\n\n" + "\n".join(context)


async def insert_content(db, data: dict, seed: dict) -> None:
    roles = {role.name: role.id for role in (await db.execute(select(Role))).scalars()}
    admin = await db.get(User, UUID(data["admin_id"]))
    before = data["admin_before"]
    if (admin is None or str(admin.role_id) != before["role_id"] or admin.email != before["email"]
            or hashlib.sha256(admin.hashed_password.encode()).hexdigest() != before["password_fingerprint"]):
        raise ContentError("ADMIN changed after preparation; no data overwritten")
    for row in seed["users"]:
        alias = row["alias"]
        user = admin if alias == "u1" else User(
            id=UUID(data["ids"]["users"][alias]), role_id=roles[row["role"]], is_active=True,
            must_change_password=False, created_at=moment(data),
            hashed_password=AuthService.hash_password(data["users"][alias]["password"]))
        user.full_name, user.email, user.specialty = row["full_name"], row["email"], row["specialty"]
        user.preferences = {**(user.preferences or {}), "avatar_color": row["avatar_color"]}
        if alias != "u1":
            db.add(user)
    await db.flush()
    for table, model in MODELS.items():
        if table == "users":
            continue
        for row in seed[table]:
            fields = {key: value for key, value in row.items() if key in model.__table__.columns}
            for key, target in REFERENCES.items():
                if key in fields and fields[key] is not None:
                    fields[key] = UUID(data["ids"][target][fields[key]])
            fields.update(id=UUID(data["ids"][table][row["alias"]]),
                          created_at=moment(data, row.get("created_offset", 0)), updated_at=moment(data))
            for source, target in (("due_offset", "due_date"), ("completed_offset", "completed_at"),
                                   ("blocked_offset", "blocked_at")):
                if source in row:
                    fields[target] = moment(data, row[source])
            if table == "applications":
                fields["owner_id"] = UUID(data["admin_id"])
            elif table == "ticket_events":
                detail = dict(row["detail"])
                for key in ("from_user_id", "to_user_id"):
                    if detail.get(key):
                        detail[key] = data["ids"]["users"][detail[key]]
                ticket = next(t for t in seed["tickets"] if t["alias"] == row["ticket_id"])
                detail["beta_source"] = {"version": seed["version"], "ticket_alias": row["ticket_id"],
                                         "event_index": int(row["alias"].rsplit("/", 1)[1]),
                                         "event_type": row.get("beta_type", row["event_type"]),
                                         "ticket_status": ticket["beta_status"]}
                fields["detail"] = detail
            elif table == "incidents":
                fields["description"] = incident_description(row, data, seed)
                fields["affected_environment"] = "DEV"
            db.add(model(**fields))
        await db.flush()


async def verify_content(db, data: dict, seed: dict) -> dict:
    rows = await rows_by_table(db, data)
    if any(len(rows[table]) != len(seed[table]) for table in MODELS):
        raise ContentError("Tracked content is missing; setup will not recreate deleted rows")
    roles = {role.name: role.id for role in (await db.execute(select(Role))).scalars()}
    for row in seed["users"]:
        user = rows["users"][data["ids"]["users"][row["alias"]]]
        if user.email != row["email"] or user.role_id != roles[row["role"]]:
            raise ContentError("Tracked user identity changed")
    for table, items in rows.items():
        for item in items.values():
            for key, target in REFERENCES.items():
                if hasattr(type(item), key):
                    value = getattr(item, key)
                    if value is not None and table not in {"users", "applications"}:
                        # Assignments may change to another real user during normal use.
                        if target != "users" and str(value) not in rows[target]:
                            raise ContentError(f"Tracked relationship changed in {table}")
            if table == "tickets" and item.ticket_type.value != "DEVELOPMENT":
                raise ContentError("Tracked ticket domain changed")
            if table == "ticket_events" and (item.detail or {}).get("beta_source", {}).get("version") != seed["version"]:
                raise ContentError("Imported event provenance changed")
    return {"dataset_id": data["dataset_id"], "reference_at": data["reference_at"],
            "admin_id": data["admin_id"], "verified": True,
            "counts": {table: len(items) for table, items in rows.items()},
            "ids": data["ids"],
            "users": [{"id": str(user.id), "email": user.email, "full_name": user.full_name}
                      for user in rows["users"].values()],
            "tickets": [{"id": str(t.id), "status": t.status.value,
                         "assignee_id": str(t.assignee_id) if t.assignee_id else None,
                         "time_spent_seconds": t.time_spent_seconds,
                         "timer_running": t.timer_started_at is not None} for t in rows["tickets"].values()],
            "unread": {alias: sum(not n.is_read and str(n.user_id) == user_id
                                  for n in rows["notifications"].values())
                       for alias, user_id in data["ids"]["users"].items()}}


def sync_admin_sources(data: dict) -> None:
    target = data["users"]["admin"]
    for name in data["admin_sources"]:
        path = local_path(Path(name))
        source = read_json(path)
        current = credentials(source)
        if (source["admin_id"] != data["admin_id"] or current["password"] != target["password"]
                or current["email"] not in {data["admin_before"]["email"], target["email"]}):
            raise ContentError("Related ADMIN manifest changed; reconciliation stopped")
        if current["email"] != target["email"]:
            current["email"] = target["email"]
            save_atomic(path, source)


async def cleanup(db, data: dict) -> None:
    owned = owned_ids(data)
    for table in Base.metadata.sorted_tables:
        references = [column.in_(owned[fk.column.table.name]) for column in table.columns
                      for fk in column.foreign_keys if fk.column.table.name in owned]
        if references:
            statement = select(func.count()).select_from(table).where(or_(*references))
            if table.name in owned:
                statement = statement.where(table.c.id.not_in(owned[table.name]))
            if (await db.execute(statement)).scalar_one():
                raise ContentError(f"Untracked references in {table.name}; cleanup aborted")
    for table in reversed(Base.metadata.sorted_tables):
        if table.name in owned:
            await db.execute(delete(table).where(table.c.id.in_(owned[table.name])))


async def run(action: str, dataset_id: UUID, path: Path, admin_file: Path | None = None,
              related_files: list[Path] | None = None) -> dict:
    guard()
    if action not in {"setup", "check", "cleanup"}:
        raise ContentError("Unknown content action")
    path = local_path(path)
    related = [local_path(item) for item in (related_files or [])]
    if admin_file is not None:
        admin_file = local_path(admin_file)
    if path in [admin_file, *related]:
        raise ContentError("Content and ADMIN manifests must have different paths")
    seed = await asyncio.to_thread(read_json, SEED_FILE)
    lock = await asyncio.to_thread(acquire_lock, path)
    try:
        exists = await asyncio.to_thread(path.exists)
        data = await asyncio.to_thread(read_json, path) if exists else None
        if data is not None:
            validate_manifest(data, dataset_id, seed)
        elif action != "setup" or admin_file is None:
            raise ContentError("Initial setup requires an existing ADMIN manifest")
        async with get_session_maker()() as db:
            async with db.begin():
                await db.execute(text("SELECT pg_advisory_xact_lock(843003)"))
                if data is None:
                    assert admin_file is not None
                    data = await prepare_manifest(db, dataset_id, seed, admin_file, related)
                    await asyncio.to_thread(save_atomic, path, data)
                rows = await rows_by_table(db, data)
                present = sum(len(items) for table, items in rows.items() if table != "users")
                present += len(rows["users"]) - int(data["admin_id"] in rows["users"])
                if data["state"] in {"removed", "removing"} and present == 0:
                    if action == "setup":
                        raise ContentError("Retired dataset cannot be prepared again")
                    data["state"] = "removed"
                    await asyncio.to_thread(save_atomic, path, data)
                    return {"dataset_id": str(dataset_id), "removed": True, "admin_id": data["admin_id"]}
                if data["state"] == "prepared" and present == 0:
                    if action != "setup":
                        raise ContentError("Prepared manifest needs setup to finish")
                    await assert_no_collisions(db, data, seed)
                    await insert_content(db, data, seed)
                elif action == "setup" and data["state"] in {"removing", "removed"}:
                    raise ContentError("Retired dataset cannot be prepared again")
                result = await verify_content(db, data, seed)
                if action == "cleanup":
                    # A committed removal can be reconciled after a filesystem failure.
                    await cleanup(db, data)
                    data["state"] = "removing"
                    await asyncio.to_thread(save_atomic, path, data)
            if action == "setup":
                if data["state"] == "prepared":
                    await asyncio.to_thread(sync_admin_sources, data)
                    data["state"] = "active"
                    await asyncio.to_thread(save_atomic, path, data)
                result["reused"] = exists
            elif action == "cleanup":
                data["state"] = "removed"
                await asyncio.to_thread(save_atomic, path, data)
                result["removed"] = True
            result["state"] = data["state"]
            return result
    finally:
        await asyncio.to_thread(os.close, lock)


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("setup", "check", "cleanup"))
    parser.add_argument("dataset_id", type=UUID)
    parser.add_argument("--local-file", required=True, type=Path)
    parser.add_argument("--admin-file", type=Path)
    parser.add_argument("--related-admin-file", action="append", type=Path, default=[])
    args = parser.parse_args()
    try:
        result = await run(args.action, args.dataset_id, args.local_file,
                           args.admin_file, args.related_admin_file)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except ContentError as exc:
        print(f"Content operation stopped: {exc}")
        return 1
    except Exception as exc:
        print(f"Content operation failed ({type(exc).__name__}); credentials not printed")
        return 1
    finally:
        await dispose_engine()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
