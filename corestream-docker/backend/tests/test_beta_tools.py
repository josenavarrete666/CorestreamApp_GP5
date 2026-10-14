from types import SimpleNamespace
from uuid import uuid4

import pytest

from scripts import acceptance_beta


@pytest.mark.asyncio
async def test_beta_setup_refuses_external_or_test_database_before_writing(tmp_path, monkeypatch):
    for environment, database, redis in (
        ("test", "postgresql+asyncpg://unused@postgres/corestream", "redis://redis/0"),
        ("development", "postgresql+asyncpg://unused@postgres/corestream_test", "redis://redis/0"),
        ("development", "postgresql+asyncpg://unused@remote/corestream", "redis://redis/0"),
        ("development", "postgresql+asyncpg://unused@postgres/corestream", "redis://redis/15"),
    ):
        monkeypatch.setattr(acceptance_beta, "get_settings", lambda environment=environment, database=database, redis=redis: SimpleNamespace(
            ENVIRONMENT=environment, DATABASE_URL=database, REDIS_URL=redis))
        path = tmp_path / "manifest.json"
        with pytest.raises(RuntimeError, match="Expected Docker"):
            await acceptance_beta.run("setup", uuid4(), path)
        assert not path.exists()
