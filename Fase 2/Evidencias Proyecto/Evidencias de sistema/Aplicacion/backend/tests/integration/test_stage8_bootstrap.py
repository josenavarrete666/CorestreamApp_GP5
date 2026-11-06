import pytest
from sqlalchemy import delete

from app.database import get_session_maker
from app.models import User
from app.scripts.create_admin import create_admin

pytestmark = pytest.mark.asyncio(loop_scope="session")


async def test_first_admin_hash_authenticates_and_second_bootstrap_preserves_account(client, capsys):
    async with get_session_maker()() as db:
        await db.execute(delete(User))
        await db.commit()
    email, password = "bootstrap@corestream-tests.com", "Bootstrap-Test-Password123!"
    await create_admin(email, password, "Bootstrap test")
    assert password not in capsys.readouterr().out
    client.cookies.clear()
    response = await client.post("/api/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200
    profile = await client.get("/api/auth/me", headers={"Authorization": f"Bearer {response.json()['access_token']}"})
    assert profile.status_code == 200
    assert profile.json()["role"] == "ADMIN"
    with pytest.raises(SystemExit):
        await create_admin("second@corestream-tests.com", password, "Second")
    async with get_session_maker()() as db:
        existing = await db.get(User, UUID(profile.json()["id"]))
        assert existing is not None
from uuid import UUID
