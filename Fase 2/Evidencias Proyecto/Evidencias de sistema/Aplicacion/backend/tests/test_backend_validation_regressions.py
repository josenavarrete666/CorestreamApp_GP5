"""Regression coverage for error paths found during backend type validation."""

import pytest
from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Epic, User
from app.routers.epics import reorder_epic
from app.schemas.epic import EpicResponse


async def test_reorder_serialization_failure_is_not_reported_as_success(
    db_session: AsyncSession, sample_epic: Epic, sample_user: User, monkeypatch,
):
    await db_session.commit()

    def invalid_response(*args, **kwargs):
        raise ValueError("Invalid epic response")

    monkeypatch.setattr(EpicResponse, "model_validate", invalid_response)

    with pytest.raises(HTTPException) as exc:
        await reorder_epic(
            sample_epic.id, {"new_index": 0}, current_user=sample_user, db=db_session,
        )

    assert exc.value.status_code == 400
    assert "Invalid epic response" in exc.value.detail
