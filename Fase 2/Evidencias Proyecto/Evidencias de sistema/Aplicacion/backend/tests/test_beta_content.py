from types import SimpleNamespace
from uuid import uuid4

import pytest

from scripts import beta_content


@pytest.mark.parametrize("environment,database,redis,echo", [
    ("test", "postgres/corestream", "redis/0", False),
    ("development", "postgres/corestream_test", "redis/0", False),
    ("development", "remote/corestream", "redis/0", False),
    ("development", "postgres/corestream", "redis/15", False),
    ("development", "postgres/corestream", "redis/0", True),
])
@pytest.mark.asyncio
async def test_content_refuses_wrong_environment_before_creating_files(
        tmp_path, monkeypatch, environment, database, redis, echo):
    settings = SimpleNamespace(ENVIRONMENT=environment,
                               DATABASE_URL=f"postgresql+asyncpg://unused@{database}",
                               REDIS_URL=f"redis://{redis}", SQL_ECHO=echo)
    monkeypatch.setattr(beta_content, "get_settings", lambda: settings)
    with pytest.raises(beta_content.ContentError):
        await beta_content.run("setup", uuid4(), tmp_path / "content.json")
    assert not list(tmp_path.iterdir())


def test_content_refuses_manifest_outside_protected_directory(tmp_path, monkeypatch):
    monkeypatch.setattr(beta_content, "LOCAL_DIRECTORY", tmp_path / "protected")
    with pytest.raises(beta_content.ContentError, match="inside backend/.local"):
        beta_content.local_path(tmp_path / "content.json")
