"""Apply the team's shared development passwords to the beta accounts; never print credentials.

The beta loader (beta_content) generates random passwords per installation.
This tool replaces them with the ones in a private file shared by the team
(`backend/.local/credenciales-dev.json`, never versioned), so every developer
signs in with the same @alloxentric accounts. It also keeps the local
manifests (`admin.json`, `beta-content.json`) in sync with those passwords.

File format, a list of objects (extra keys such as nombre/rol are ignored):
    [{"email": "a.torres@alloxentric.com", "password": "..."}, ...]
"""

from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path

from sqlalchemy import select

from app.database import dispose_engine, get_session_maker
from app.models import User
from app.services.auth_service import AuthService
from scripts.beta_content import ContentError, guard, local_path, read_json, save_atomic

MIN_PASSWORD_LENGTH = 8


def read_credentials(path: Path) -> dict[str, str]:
    """email -> password, validated. Raises ContentError without echoing values."""
    try:
        data = json.loads(local_path(path).read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as exc:
        raise ContentError("Cannot read the credentials file") from exc
    if isinstance(data, dict):
        data = data.get("users")
    if not isinstance(data, list) or not data:
        raise ContentError("The credentials file must be a non-empty list of accounts")
    credentials: dict[str, str] = {}
    for entry in data:
        email = entry.get("email") if isinstance(entry, dict) else None
        password = entry.get("password") if isinstance(entry, dict) else None
        if not isinstance(email, str) or "@" not in email or not isinstance(password, str):
            raise ContentError("Every account needs an email and a password")
        if len(password) < MIN_PASSWORD_LENGTH:
            raise ContentError(f"Passwords must have at least {MIN_PASSWORD_LENGTH} characters")
        credentials[email.strip().lower()] = password
    return credentials


def sync_manifest(path: Path, credentials: dict[str, str]) -> int:
    """Update passwords of matching emails in a local manifest; returns how many changed."""
    if not path.exists():
        return 0
    data = read_json(path)
    users = data.get("users")
    if not isinstance(users, dict):
        return 0
    changed = 0
    for entry in users.values():
        if not isinstance(entry, dict) or not isinstance(entry.get("email"), str):
            continue
        password = credentials.get(entry["email"].lower())
        if password is not None and entry.get("password") != password:
            entry["password"] = password
            changed += 1
    if changed:
        save_atomic(path, data)
    return changed


async def apply(credentials_file: Path, manifests: list[Path]) -> dict:
    guard()
    credentials = read_credentials(credentials_file)
    updated, missing = [], []
    async with get_session_maker()() as db:
        for email, password in credentials.items():
            user = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
            if user is None:
                missing.append(email)
                continue
            user.hashed_password = AuthService.hash_password(password)
            user.must_change_password = False
            updated.append(email)
        await db.commit()
    synced = {str(path.name): await asyncio.to_thread(sync_manifest, local_path(path), credentials)
              for path in manifests}
    return {"accounts_updated": updated, "accounts_missing": missing, "manifest_entries_synced": synced}


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("apply",))
    parser.add_argument("--credentials-file", required=True, type=Path)
    parser.add_argument("--manifest", action="append", type=Path, default=[],
                        help="Local manifest to keep in sync (admin.json, beta-content.json)")
    args = parser.parse_args()
    try:
        result = await apply(args.credentials_file, args.manifest)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if not result["accounts_missing"] else 2
    except ContentError as exc:
        print(f"Accounts operation stopped: {exc}")
        return 1
    except Exception as exc:
        print(f"Accounts operation failed ({type(exc).__name__}); credentials not printed")
        return 1
    finally:
        await dispose_engine()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
