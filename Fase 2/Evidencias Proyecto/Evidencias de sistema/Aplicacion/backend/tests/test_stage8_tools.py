import json
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from app.scripts import create_admin
from scripts import acceptance_stage8


def test_bootstrap_password_file_does_not_print_secret(tmp_path, monkeypatch, capsys):
    password = "Only-A-Test-Password123!"
    path = tmp_path / "password"
    path.write_text(password + "\n", encoding="utf-8")
    creator = AsyncMock()
    monkeypatch.setattr(create_admin, "create_admin", creator)
    monkeypatch.setattr("sys.argv", ["create_admin", "--email", "admin@example.com", "--password-file", str(path)])
    create_admin.main()
    creator.assert_awaited_once_with("admin@example.com", password, "Administrador")
    assert password not in capsys.readouterr().out


def test_bootstrap_rejects_mixed_password_sources(tmp_path, monkeypatch):
    monkeypatch.setattr("sys.argv", ["create_admin", "--email", "admin@example.com", "--password", "test-password", "--prompt-password"])
    with pytest.raises(SystemExit) as failure:
        create_admin.main()
    assert failure.value.code == 2


@pytest.mark.asyncio
async def test_acceptance_refuses_test_or_external_database_before_writing(tmp_path, monkeypatch):
    for url in ("postgresql+asyncpg://user:password@postgres/corestream_test", "postgresql+asyncpg://user:password@remote/corestream"):
        monkeypatch.setattr(acceptance_stage8, "get_settings", lambda url=url: SimpleNamespace(ENVIRONMENT="development", DATABASE_URL=url))
        path = tmp_path / "credentials.json"
        with pytest.raises(RuntimeError, match="Expected Docker"):
            await acceptance_stage8.run("setup", uuid4(), path)
        assert not path.exists()


def test_local_credential_file_is_not_written_into_result(tmp_path):
    path = tmp_path / "credentials.json"
    acceptance_stage8.save(path, {"password": "local-test-password"})
    assert json.loads(path.read_text())["password"] == "local-test-password"
    assert path.stat().st_mode & 0o077 == 0
