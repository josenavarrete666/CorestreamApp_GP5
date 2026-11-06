"""Verify live beta content and preservation of development data without exposing secrets."""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
from pathlib import Path
from uuid import UUID

import httpx
from sqlalchemy import select

from app.database import dispose_engine, get_session_maker
from app.models import Base, User
from scripts import beta_content as content


def require(condition, message: str) -> None:
    if not condition:
        raise content.ContentError(message)


async def database_snapshot() -> dict:
    snapshot = {}
    async with get_session_maker()() as db:
        for table in Base.metadata.sorted_tables:
            rows = (await db.execute(select(table))).mappings()
            snapshot[table.name] = {
                str(row["id"]): hashlib.sha256(
                    json.dumps(dict(row), sort_keys=True, default=str).encode()).hexdigest()
                for row in rows
            }
    return snapshot


async def paginated(client, route: str, headers: dict) -> list:
    items = []
    for skip in range(0, 10000, 100):
        response = await client.get(route, headers=headers, params={"skip": skip, "limit": 100})
        require(response.status_code == 200, f"Read failed: {route}")
        page = response.json()
        require(isinstance(page, list), f"Expected array: {route}")
        items.extend(page)
        if len(page) < 100:
            return items
    raise content.ContentError("Unexpected pagination size")


async def live_api(data: dict, seed: dict, api_url: str) -> dict:
    ids = data["ids"]
    accounts = []
    for user in seed["users"]:
        alias = user["alias"]
        credential = data["users"]["admin" if alias == "u1" else alias]
        async with httpx.AsyncClient(base_url=api_url, timeout=20) as client:
            login = await client.post("/api/auth/login", json={key: credential[key] for key in ("email", "password")})
            require(login.status_code == 200, f"Login failed for {alias}")
            headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
            try:
                require(login.json()["must_change_password"] is False, f"Password change required for {alias}")
                profile_response = await client.get("/api/auth/me", headers=headers)
                require(profile_response.status_code == 200, f"Profile failed for {alias}")
                profile = profile_response.json()
                require(profile["id"] == ids["users"][alias] and profile["role"] == user["role"],
                        f"Profile identity mismatch for {alias}")
                require(profile["email"] == user["email"] and profile["full_name"] == user["full_name"]
                        and profile["specialty"] == user["specialty"]
                        and profile["preferences"]["avatar_color"] == user["avatar_color"],
                         f"Profile metadata mismatch for {alias}")
                members_response = await client.get("/api/tickets/team-members", headers=headers)
                require(members_response.status_code == 200, f"Member selector failed for {alias}")
                members = {member["id"]: member for member in members_response.json()}
                require(ids["users"][alias] not in members and ids["users"]["u1"] not in members,
                        "Member selector identity/role filtering changed")
                for person in seed["users"]:
                    if person["role"] == "ADMIN" or person["alias"] == alias:
                        continue
                    member = members[ids["users"][person["alias"]]]
                    require(member["specialty"] == person["specialty"]
                            and member["avatar_color"] == person["avatar_color"], "Member metadata mismatch")
                    require("preferences" not in member, "Member selector exposes unrelated preferences")
                if user["role"] == "DEVELOPER":
                    require((await client.get("/api/users/", headers=headers)).status_code == 403,
                            "Developer directory restriction changed")
                notifications = await paginated(client, "/api/notifications/", headers)
                require(all(n["user_id"] == ids["users"][alias] for n in notifications), "Notification owner mismatch")
                expected = {ids["notifications"][n["alias"]]: n for n in seed["notifications"] if n["user_id"] == alias}
                actual = {n["id"]: n for n in notifications if n["id"] in expected}
                require(actual.keys() == expected.keys(), f"Missing beta notifications for {alias}")
                for notice_id, item in expected.items():
                    notice = actual[notice_id]
                    require(all(notice[key] == item[key] for key in ("title", "message", "type", "is_read")),
                            "Notification content mismatch")
                    require(notice["ticket_id"] == (ids["tickets"][item["ticket_id"]] if item["ticket_id"] else None),
                            "Notification relationship mismatch")
                count = await client.get("/api/notifications/unread-count", headers=headers)
                require(count.status_code == 200 and count.json()["unread_count"] == sum(not n["is_read"] for n in notifications),
                        "Global unread count mismatch")
                accounts.append({"alias": alias, "email": profile["email"], "role": profile["role"],
                                 "login": "passed", "beta_notifications": len(actual),
                                 "global_unread": count.json()["unread_count"]})
                if alias == "u1":
                    apps = {a["id"]: a for a in await paginated(client, "/api/applications/", headers)}
                    for item in seed["applications"]:
                        require(all(apps[ids["applications"][item["alias"]]][key] == item[key]
                                    for key in ("name", "color", "icon")), "Project metadata mismatch")
                    for app_id in ids["applications"].values():
                        response = await client.get(f"/api/epics/by-app/{app_id}", headers=headers)
                        require(response.status_code == 200, "Board read failed")
                        require(all(e["application_id"] == app_id for e in response.json()), "Epic relationship mismatch")
                    for item in seed["tickets"]:
                        ticket_id = ids["tickets"][item["alias"]]
                        response = await client.get(f"/api/tickets/{ticket_id}", headers=headers)
                        require(response.status_code == 200, "Ticket read failed")
                        ticket = response.json()
                        require(all(ticket[key] == item[key] for key in ("title", "description", "status", "priority", "time_spent_seconds")),
                                "Ticket content mismatch")
                        require(ticket["epic_id"] == ids["epics"][item["epic_id"]]
                                and ticket["created_by_id"] == ids["users"][item["created_by_id"]]
                                and ticket["assignee_id"] == (ids["users"][item["assignee_id"]] if item["assignee_id"] else None),
                                "Ticket relationship mismatch")
                        for key, offset in (("created_at", "created_offset"), ("due_date", "due_offset"), ("completed_at", "completed_offset")):
                            value = ticket[key]
                            expected_date = content.moment(data, item[offset]) if offset in item else None
                            require((content.datetime.fromisoformat(value) if value else None) == expected_date,
                                    "Ticket date mismatch")
                        subtasks = {s["id"]: s for s in ticket["subtasks"]}
                        expected_subtasks = [s for s in seed["subtasks"] if s["ticket_id"] == item["alias"]]
                        require(len(subtasks) == len(expected_subtasks), "Subtask count mismatch")
                        for subtask in expected_subtasks:
                            actual_subtask = subtasks[ids["subtasks"][subtask["alias"]]]
                            require(all(actual_subtask[key] == subtask[key] for key in ("title", "order_index", "is_completed")),
                                    "Subtask content mismatch")
                            require(actual_subtask["completed_at"] is None, "Invented subtask completion date")
                        events = await paginated(client, f"/api/tickets/{ticket_id}/events", headers)
                        expected_events = [e for e in seed["ticket_events"] if e["ticket_id"] == item["alias"]]
                        require({e["id"] for e in events} == {ids["ticket_events"][e["alias"]] for e in expected_events},
                                "History identity mismatch")
                    for item in seed["incidents"]:
                        response = await client.get(f"/api/incidents/{ids['incidents'][item['alias']]}", headers=headers)
                        require(response.status_code == 200, "Incident read failed")
                        incident = response.json()
                        require(all(incident[key] == item[key] for key in ("title", "status", "severity")), "Incident conversion mismatch")
                        require(incident["affected_environment"] == "DEV"
                                and incident["description"] == content.incident_description(item, data, seed),
                                "Incident context mismatch")
            finally:
                logout = await client.post("/api/auth/logout", headers=headers)
                require(logout.status_code == 200, f"Logout failed for {alias}")
    return {"accounts": accounts, "applications": 3, "tickets": 9, "subtasks": 20,
            "events": 19, "incidents": 5, "notifications": 8}


async def run(args) -> dict:
    content.guard()
    baseline_path = content.local_path(args.baseline_file)
    if args.action == "baseline":
        require(not await asyncio.to_thread(baseline_path.exists), "Baseline already exists")
        snapshot = await database_snapshot()
        await asyncio.to_thread(content.save_atomic, baseline_path,
                                {"purpose": "beta-content-baseline", "rows": snapshot})
        return {"baseline_saved": True, "counts": {name: len(rows) for name, rows in snapshot.items()}}
    require(args.dataset_id is not None and args.content_file is not None, "Verification requires dataset and content manifest")
    baseline = await asyncio.to_thread(content.read_json, baseline_path)
    require(baseline["purpose"] == "beta-content-baseline", "Baseline purpose mismatch")
    path = content.local_path(args.content_file)
    data = await asyncio.to_thread(content.read_json, path)
    sql = await content.run("check", args.dataset_id, path)
    require(sql["state"] == "active", "Setup reconciliation is incomplete")
    snapshot = await database_snapshot()
    for table, old_rows in baseline["rows"].items():
        for identifier, fingerprint in old_rows.items():
            if table == "users" and identifier == data["admin_id"]:
                continue
            require(snapshot[table].get(identifier) == fingerprint, f"Existing data changed in {table}")
        added = set(snapshot[table]) - set(old_rows)
        require(added == {str(i) for i in content.owned_ids(data).get(table, [])}, f"Unexpected added rows in {table}")
    async with get_session_maker()() as db:
        admin = await db.get(User, UUID(data["admin_id"]))
        before = data["admin_before"]
        require(admin is not None and str(admin.role_id) == before["role_id"]
                and admin.created_at.isoformat() == before["created_at"]
                and admin.must_change_password == before["must_change_password"] and admin.is_active
                and hashlib.sha256(admin.hashed_password.encode()).hexdigest() == before["password_fingerprint"],
                "ADMIN UUID, role, password or session flag changed")
    seed = await asyncio.to_thread(content.read_json, content.SEED_FILE)
    api = await live_api(data, seed, args.api_url)
    return {"dataset_id": str(args.dataset_id), "verified": True, "reference_at": data["reference_at"],
            "sql_counts": sql["counts"], "existing_data_preserved": True,
            "admin_identity_preserved": True, "http": api}


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("baseline", "verify"))
    parser.add_argument("--baseline-file", type=Path, required=True)
    parser.add_argument("--content-file", type=Path)
    parser.add_argument("--dataset-id", type=UUID)
    parser.add_argument("--api-url", default="http://127.0.0.1:8080")
    args = parser.parse_args()
    try:
        print(json.dumps(await run(args), ensure_ascii=False, indent=2))
        return 0
    except content.ContentError as exc:
        print(f"Verification stopped: {exc}")
        return 1
    except Exception as exc:
        print(f"Verification failed ({type(exc).__name__}); credentials not printed")
        return 1
    finally:
        await dispose_engine()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
