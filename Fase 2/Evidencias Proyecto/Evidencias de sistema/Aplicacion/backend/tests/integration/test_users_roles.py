"""Role changes through the HTTP API with real PostgreSQL."""

import pytest
from sqlalchemy import delete, select

from app.database import get_session_maker
from app.models import Role, User

pytestmark = pytest.mark.asyncio(loop_scope="session")


async def test_demote_without_developer_role_preserves_leader(client, admin_headers, leader_id):
    async with get_session_maker()() as db:
        developer_roles = select(Role.id).where(Role.name == "DEVELOPER")
        await db.execute(delete(User).where(User.role_id.in_(developer_roles)))
        await db.execute(delete(Role).where(Role.name == "DEVELOPER"))
        await db.commit()

    response = await client.post(f"/api/users/{leader_id}/demote", headers=admin_headers)
    assert response.status_code == 400
    assert "DEVELOPER" in response.json()["detail"]

    stored = await client.get(f"/api/users/{leader_id}", headers=admin_headers)
    assert stored.status_code == 200
    assert stored.json()["role"] == "TEAM_LEADER"


async def test_demote_with_developer_role_updates_user(client, admin_headers, leader_id):
    response = await client.post(f"/api/users/{leader_id}/demote", headers=admin_headers)
    assert response.status_code == 200
    assert response.json()["role"] == "DEVELOPER"

    stored = await client.get(f"/api/users/{leader_id}", headers=admin_headers)
    assert stored.status_code == 200
    assert stored.json()["role"] == "DEVELOPER"
