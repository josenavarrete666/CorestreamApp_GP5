"""Create, check, and remove isolated markers for the local persistence check."""

import argparse
import asyncio
import hashlib
import json
from pathlib import Path
from urllib.parse import urlparse
from uuid import UUID

import redis.asyncio as redis
from sqlalchemy import text
from sqlalchemy.engine import make_url

from app.config import get_settings
from app.database import dispose_engine, get_session_maker
from app.models import Application

DESCRIPTION = "Local persistence verification (stage 5)."


def write_marker(file_path: Path, contents: bytes) -> None:
    file_path.parent.mkdir(parents=True, exist_ok=True)
    with file_path.open("xb") as marker:
        marker.write(contents)


async def run(action: str, marker_id: UUID) -> None:
    settings = get_settings()
    database = make_url(settings.DATABASE_URL)
    redis_url = urlparse(settings.REDIS_URL)
    storage = await asyncio.to_thread(Path(settings.UPLOAD_DIR).resolve)
    if (
        settings.ENVIRONMENT != "development"
        or database.host != "postgres"
        or database.database != "corestream"
        or redis_url.hostname != "redis"
        or redis_url.path != "/0"
        or settings.STORAGE_BACKEND != "local"
        or storage != Path("/app/storage")
    ):
        raise RuntimeError("Expected the local Docker development environment.")

    name = f"Verification stage 5 - {marker_id}"
    key = f"corestream:verification:stage5:{marker_id}"
    value = f"CoreStream stage 5 verification: {marker_id}"
    file_path = storage / "verification" / f"stage5-{marker_id}.txt"
    contents = (value + "\n").encode("utf-8")
    client = redis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        async with get_session_maker()() as db:
            application = await db.get(Application, marker_id)
            if action == "create":
                if (
                    application is not None
                    or await client.exists(key)
                    or await asyncio.to_thread(file_path.exists)
                ):
                    raise RuntimeError("A marker already exists; choose a fresh UUID.")
                application = Application(
                    id=marker_id, name=name, description=DESCRIPTION,
                    is_active=False, owner_id=None,
                )
                db.add(application)
                await db.commit()
                await asyncio.to_thread(write_marker, file_path, contents)
                if not await client.set(key, value, nx=True):
                    raise RuntimeError("Could not create the Redis marker.")

            actual_value = await client.get(key)
            actual_ttl = await client.ttl(key)
            actual_contents = (
                await asyncio.to_thread(file_path.read_bytes)
                if await asyncio.to_thread(file_path.exists) else None
            )
            if (
                application is None
                or application.name != name
                or application.description != DESCRIPTION
                or application.is_active
                or application.owner_id is not None
                or actual_value != value
                or actual_ttl != -1
                or actual_contents != contents
            ):
                raise RuntimeError("A persistence marker is absent or differs from its expected value.")

            revision = (await db.execute(text("SELECT version_num FROM alembic_version"))).scalar_one()
            result = {
                "action": action,
                "marker_id": str(marker_id),
                "database": {
                    "name": database.database,
                    "application_name": application.name,
                    "is_active": application.is_active,
                    "owner_id": application.owner_id,
                    "alembic_revision": revision,
                },
                "redis": {"db": 0, "key": key, "value": actual_value, "ttl": actual_ttl},
                "file": {"path": str(file_path), "sha256": hashlib.sha256(contents).hexdigest()},
                "verified": True,
            }
            if action == "cleanup":
                await db.delete(application)
                await db.commit()
                await client.delete(key)
                await asyncio.to_thread(file_path.unlink)
                if (
                    await db.get(Application, marker_id) is not None
                    or await client.exists(key)
                    or await asyncio.to_thread(file_path.exists)
                ):
                    raise RuntimeError("Marker cleanup was incomplete.")
                result["removed"] = True
            print(json.dumps(result, indent=2))
    finally:
        await client.aclose()
        await dispose_engine()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("create", "check", "cleanup"))
    parser.add_argument("marker_id", type=UUID)
    args = parser.parse_args()
    asyncio.run(run(args.action, args.marker_id))
