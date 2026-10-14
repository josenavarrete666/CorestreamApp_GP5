import json
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from sqlalchemy import delete, select

from app.database import get_session_maker
from app.models import Application, Notification, Role, Subtask, Ticket, User
from app.services.auth_service import AuthService
from scripts import beta_content
from tests.integration.conftest import ADMIN

pytestmark = pytest.mark.asyncio(loop_scope="session")


async def prepare(client, tmp_path, monkeypatch):
    settings = SimpleNamespace(ENVIRONMENT="development",
                               DATABASE_URL="postgresql+asyncpg://unused@postgres/corestream",
                               REDIS_URL="redis://redis/0", SQL_ECHO=False)
    monkeypatch.setattr(beta_content, "get_settings", lambda: settings)
    monkeypatch.setattr(beta_content, "LOCAL_DIRECTORY", tmp_path)
    async with get_session_maker()() as db:
        admin = (await db.execute(select(User).join(Role).where(Role.name == "ADMIN"))).scalar_one()
        snapshot = (admin.id, admin.hashed_password, admin.created_at, admin.role_id)
        admin.preferences = {"existing_setting": "preserved"}
        await db.commit()
    source = {"admin_id": str(snapshot[0]), "users": {"admin": dict(ADMIN)}, "untouched": [1, 2]}
    admin_file, related = tmp_path / "admin.json", tmp_path / "related.json"
    beta_content.save_atomic(admin_file, source)
    beta_content.save_atomic(related, source)
    return uuid4(), tmp_path / "content.json", admin_file, related, snapshot


async def test_content_api_accounts_and_repeat_preserve_real_changes(client, tmp_path, monkeypatch):
    dataset, path, source, related, before = await prepare(client, tmp_path, monkeypatch)
    result = await beta_content.run("setup", dataset, path, source, [related])
    assert result["counts"] == {"users": 5, "applications": 3, "epics": 5, "tickets": 9,
                                "subtasks": 20, "ticket_events": 19, "incidents": 5, "notifications": 8}
    assert result["unread"] == {"u1": 2, "u2": 2, "u3": 1, "u4": 0, "u5": 0}
    manifest = beta_content.read_json(path)
    ids = manifest["ids"]
    async with get_session_maker()() as db:
        admin = await db.get(User, before[0])
        assert (admin.id, admin.hashed_password, admin.created_at, admin.role_id) == before
        assert admin.preferences == {"existing_setting": "preserved", "avatar_color": "#4C8DFF"}
        t1 = await db.get(Ticket, UUID(ids["tickets"]["t1"]))
        assert t1.time_spent_seconds == 16440 and t1.timer_started_at is None
    for name in (source, related):
        saved = beta_content.read_json(name)
        assert saved["users"]["admin"]["email"] == "a.torres@example.com"
        assert saved["users"]["admin"]["password"] == ADMIN["password"]
        assert saved["untouched"] == [1, 2]
        assert name.stat().st_mode & 0o777 == 0o600
    assert path.stat().st_mode & 0o777 == 0o600
    seed = beta_content.read_json(beta_content.SEED_FILE)
    for row in seed["users"]:
        alias = row["alias"]
        login = await client.post("/api/auth/login", json=manifest["users"]["admin" if alias == "u1" else alias])
        assert login.status_code == 200
        assert login.json()["must_change_password"] is False
        headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
        profile = await client.get("/api/auth/me", headers=headers)
        assert profile.status_code == 200
        assert profile.json()["id"] == ids["users"][alias]
        assert profile.json()["role"] == row["role"]
        assert profile.json()["specialty"] == row["specialty"]
        assert profile.json()["preferences"]["avatar_color"] == row["avatar_color"]
        notices = await client.get("/api/notifications/", headers=headers)
        assert notices.status_code == 200
        assert all(n["user_id"] == ids["users"][alias] for n in notices.json())
        count = await client.get("/api/notifications/unread-count", headers=headers)
        assert count.json()["unread_count"] == result["unread"][alias]
        if alias == "u1":
            for app_id in ids["applications"].values():
                board = await client.get(f"/api/epics/by-app/{app_id}", headers=headers)
                assert board.status_code == 200
            for ticket in seed["tickets"]:
                ticket_id = ids["tickets"][ticket["alias"]]
                detail = await client.get(f"/api/tickets/{ticket_id}", headers=headers)
                assert detail.status_code == 200
                assert detail.json()["description"] == ticket["description"]
                assert detail.json()["status"] == ticket["status"]
                history = await client.get(f"/api/tickets/{ticket_id}/events", headers=headers)
                assert history.status_code == 200
                assert len(history.json()) == sum(e["ticket_id"] == ticket["alias"] for e in seed["ticket_events"])
            incident = await client.get(f"/api/incidents/{ids['incidents']['i3']}", headers=headers)
            assert incident.status_code == 200
            assert incident.json()["status"] == "REPORTED"
            assert "UNDER_REVIEW" in incident.json()["description"]
        if alias == "u3":
            changed = await client.put(f"/api/tickets/{ids['tickets']['t7']}", headers=headers,
                                       json={"title": "Real edited title"})
            assert changed.status_code == 200
            toggled = await client.put(f"/api/tickets/{ids['tickets']['t1']}/subtasks/{ids['subtasks']['s3']}", headers=headers,
                                       json={"is_completed": True})
            assert toggled.status_code == 200
            read = await client.post("/api/notifications/mark-read", headers=headers,
                                     json={"notification_ids": [ids["notifications"]["demo-7"]]})
            assert read.status_code == 200 and read.json()["marked_as_read"] == 1
            started = await client.post(f"/api/tickets/{ids['tickets']['t7']}/start", headers=headers)
            assert started.status_code == 200
        logout = await client.post("/api/auth/logout", headers=headers)
        assert logout.status_code == 200
        client.cookies.clear()
    async with get_session_maker()() as db:
        ticket = await db.get(Ticket, UUID(ids["tickets"]["t7"]))
        assert ticket.title == "Real edited title" and ticket.status.value == "IN_PROGRESS"
        assert ticket.timer_started_at is not None
        started_at = ticket.timer_started_at
        subtask = await db.get(Subtask, UUID(ids["subtasks"]["s3"]))
        assert subtask.is_completed is True
        notice = await db.get(Notification, UUID(ids["notifications"]["demo-7"]))
        assert notice.is_read is True
        user = await db.get(User, UUID(ids["users"]["u3"]))
        user.hashed_password = AuthService.hash_password("ChangedByUser123!")
        user.must_change_password = True
        changed_hash = user.hashed_password
        await db.commit()
    repeated = await beta_content.run("setup", dataset, path)
    assert repeated["reused"] is True and repeated["counts"] == result["counts"]
    assert repeated["reference_at"] == result["reference_at"]
    assert repeated["unread"]["u3"] == 0
    async with get_session_maker()() as db:
        ticket = await db.get(Ticket, UUID(ids["tickets"]["t7"]))
        assert ticket.title == "Real edited title" and ticket.status.value == "IN_PROGRESS"
        assert ticket.timer_started_at == started_at
        assert (await db.get(Subtask, UUID(ids["subtasks"]["s3"]))).is_completed is True
        assert (await db.get(Notification, UUID(ids["notifications"]["demo-7"]))).is_read is True
        user = await db.get(User, UUID(ids["users"]["u3"]))
        assert user.hashed_password == changed_hash and user.must_change_password is True
    with pytest.raises(beta_content.ContentError, match="identity or seed"):
        await beta_content.run("check", uuid4(), path)
    assert "password" not in json.dumps(result)


async def test_content_cleanup_blocks_foreign_references_and_preserves_admin(client, tmp_path, monkeypatch):
    dataset, path, source, related, before = await prepare(client, tmp_path, monkeypatch)
    result = await beta_content.run("setup", dataset, path, source, [related])
    foreign_id = uuid4()
    async with get_session_maker()() as db:
        db.add(Ticket(id=foreign_id, title="Foreign work", epic_id=UUID(result["ids"]["epics"]["e1"])))
        await db.commit()
    with pytest.raises(beta_content.ContentError, match="Untracked references in tickets"):
        await beta_content.run("cleanup", dataset, path)
    assert beta_content.read_json(path)["state"] == "active"
    async with get_session_maker()() as db:
        assert await db.get(Ticket, foreign_id) is not None
        await db.execute(delete(Ticket).where(Ticket.id == foreign_id))
        await db.commit()
    cleaned = await beta_content.run("cleanup", dataset, path)
    assert cleaned["removed"] is True
    async with get_session_maker()() as db:
        admin = await db.get(User, before[0])
        assert admin is not None and admin.email == "a.torres@example.com"
        assert admin.hashed_password == before[1]
        assert await db.get(User, UUID(result["ids"]["users"]["u2"])) is None
        assert await db.get(Application, UUID(result["ids"]["applications"]["a1"])) is None
    assert (await beta_content.run("cleanup", dataset, path))["removed"] is True
    with pytest.raises(beta_content.ContentError, match="Retired"):
        await beta_content.run("setup", dataset, path)


async def test_content_sql_rollback_can_resume_prepared_manifest(client, tmp_path, monkeypatch):
    dataset, path, source, related, before = await prepare(client, tmp_path, monkeypatch)
    original = beta_content.insert_content

    async def fail_after_insert(db, data, seed):
        await original(db, data, seed)
        raise beta_content.ContentError("Injected SQL rollback")

    monkeypatch.setattr(beta_content, "insert_content", fail_after_insert)
    with pytest.raises(beta_content.ContentError, match="Injected SQL"):
        await beta_content.run("setup", dataset, path, source, [related])
    prepared = beta_content.read_json(path)
    assert prepared["state"] == "prepared"
    async with get_session_maker()() as db:
        assert (await db.get(User, before[0])).email == ADMIN["email"]
        assert await db.get(Application, UUID(prepared["ids"]["applications"]["a1"])) is None
    monkeypatch.setattr(beta_content, "insert_content", original)
    result = await beta_content.run("setup", dataset, path)
    assert result["state"] == "active" and result["reference_at"] == prepared["reference_at"]


async def test_content_reconciles_manifests_after_committed_sql(client, tmp_path, monkeypatch):
    dataset, path, source, related, before = await prepare(client, tmp_path, monkeypatch)
    original = beta_content.sync_admin_sources

    def fail_sync(data):
        raise beta_content.ContentError("Injected filesystem failure")

    monkeypatch.setattr(beta_content, "sync_admin_sources", fail_sync)
    with pytest.raises(beta_content.ContentError, match="filesystem"):
        await beta_content.run("setup", dataset, path, source, [related])
    prepared = beta_content.read_json(path)
    assert prepared["state"] == "prepared"
    async with get_session_maker()() as db:
        assert (await db.get(User, before[0])).email == "a.torres@example.com"
    assert beta_content.read_json(source)["users"]["admin"]["email"] == ADMIN["email"]
    monkeypatch.setattr(beta_content, "sync_admin_sources", original)
    result = await beta_content.run("setup", dataset, path)
    assert result["state"] == "active" and result["counts"]["tickets"] == 9
    assert result["reference_at"] == prepared["reference_at"]
    assert beta_content.read_json(related)["users"]["admin"]["email"] == "a.torres@example.com"


@pytest.mark.parametrize("collision", ["email", "uuid", "related"])
async def test_content_collisions_do_not_rename_admin_or_overwrite_rows(client, tmp_path, monkeypatch, collision):
    dataset, path, source, related, before = await prepare(client, tmp_path, monkeypatch)
    async with get_session_maker()() as db:
        if collision == "email":
            role = (await db.execute(select(Role).where(Role.name == "DEVELOPER"))).scalar_one()
            db.add(User(email="l.vega@example.com", full_name="Existing unrelated user", role_id=role.id,
                        hashed_password=AuthService.hash_password("ExistingUser123!")))
        elif collision == "uuid":
            seed = beta_content.read_json(beta_content.SEED_FILE)
            ids = beta_content.identifiers(dataset, before[0], seed)
            db.add(Application(id=UUID(ids["applications"]["a1"]), name="Existing unrelated app"))
        else:
            data = beta_content.read_json(related)
            data["users"]["admin"]["email"] = "different@example.com"
            beta_content.save_atomic(related, data)
        await db.commit()
    with pytest.raises(beta_content.ContentError, match="collision|inconsistent"):
        await beta_content.run("setup", dataset, path, source, [related])
    assert not path.exists()
    async with get_session_maker()() as db:
        assert (await db.get(User, before[0])).email == ADMIN["email"]
