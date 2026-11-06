"""
Registro, desactivación y baja de dispositivos push (APP-03 / APP-06).

Lo usan el router de dispositivos y el logout, para que el cierre de sesión
y la baja manual traten el dispositivo de la misma forma.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, cast
from uuid import UUID

from sqlalchemy import CursorResult, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import UserDevice


def _now() -> datetime:
    return datetime.now(timezone.utc)


async def register_device(
    db: AsyncSession,
    *,
    user_id: UUID,
    token: str,
    platform: str,
    device_name: str | None = None,
    app_version: str | None = None,
) -> tuple[UserDevice, bool]:
    """
    Registra o reactiva el token para el usuario actual y hace commit.
    Devuelve (dispositivo, creado): creado=False si el token ya existía.

    El token pertenece al dispositivo físico: si estaba registrado a otra
    cuenta (otra persona inició sesión antes en ese teléfono), pasa a esta.
    """
    for attempt in range(2):
        device = (
            await db.execute(select(UserDevice).where(UserDevice.token == token))
        ).scalar_one_or_none()
        now = _now()
        created = device is None
        if device is None:
            device = UserDevice(user_id=user_id, token=token, platform=platform,
                                device_name=device_name, app_version=app_version,
                                is_active=True, last_seen_at=now)
            db.add(device)
        else:
            device.user_id = user_id
            device.platform = platform
            device.device_name = device_name
            device.app_version = app_version
            device.is_active = True
            device.last_seen_at = now
            device.deactivated_at = None
        try:
            await db.commit()
        except IntegrityError:
            # Otro registro concurrente insertó el mismo token: reintentar como actualización.
            await db.rollback()
            if attempt:
                raise
            continue
        await db.refresh(device)
        return device, created
    raise AssertionError("unreachable")


async def deactivate_device(db: AsyncSession, *, user_id: UUID, token: str) -> bool:
    """
    Desactiva el token si pertenece al usuario. No hace commit: el caller
    decide (el logout lo agrupa con el resto del cierre).
    """
    result = cast(CursorResult[Any], await db.execute(
        update(UserDevice)
        .where(UserDevice.token == token, UserDevice.user_id == user_id, UserDevice.is_active)
        .values(is_active=False, deactivated_at=_now())
    ))
    return bool(result.rowcount)
