import json
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from sqlalchemy import delete, select

from app.database import get_session_maker
from app.models import Application, Role, Ticket, User
from scripts import acceptance_beta, acceptance_stage8
from tests.integration.conftest import ADMIN

pytestmark = pytest.mark.asyncio(loop_scope="session")


async def test_beta_cleanup_refuses_untracked_reference_and_preserves_admin(client, tmp_path, monkeypatch):
    settings = SimpleNamespace(ENVIRONMENT="development",
        DATABASE_URL="postgresql+asyncpg://unused@postgres/corestream", REDIS_URL="redis://redis/0")
    monkeypatch.setattr(acceptance_beta, "get_settings", lambda: settings)
    monkeypatch.setattr(acceptance_stage8, "get_settings", lambda: settings)
    async with get_session_maker()() as db:
        admin = (await db.execute(select(User).join(Role).where(Role.name == "ADMIN"))).scalar_one()
        admin_id = admin.id
    admin_file = tmp_path / "admin.json"
    admin_file.write_text(json.dumps({"admin_id": str(admin_id), "users": {"admin": ADMIN}}))
    run_id = uuid4()
    path = tmp_path / "beta.json"
    result = await acceptance_beta.run("setup", run_id, path, admin_file)
    assert result["verified"] is True
    foreign_id = uuid4()
    async with get_session_maker()() as db:
        db.add(Ticket(id=foreign_id, title="Untracked work", epic_id=UUID(result["ids"]["epic"])))
        await db.commit()
    with pytest.raises(RuntimeError, match="Untracked references in tickets"):
        await acceptance_beta.run("cleanup", run_id, path)
    async with get_session_maker()() as db:
        assert await db.get(Ticket, foreign_id) is not None
        assert await db.get(Application, UUID(result["ids"]["application"])) is not None
        await db.execute(delete(Ticket).where(Ticket.id == foreign_id))
        await db.commit()
    cleaned = await acceptance_beta.run("cleanup", run_id, path)
    assert cleaned["removed"] is True
    async with get_session_maker()() as db:
        assert await db.get(User, admin_id) is not None
        assert await db.get(Application, UUID(result["ids"]["application"])) is None
        assert await db.get(Application, UUID(result["beta_ids"]["empty_application"])) is None
    assert "password" not in json.dumps(cleaned)
