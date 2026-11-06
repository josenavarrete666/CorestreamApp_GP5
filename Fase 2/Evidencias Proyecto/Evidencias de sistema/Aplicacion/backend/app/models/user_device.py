"""
Dispositivos móviles registrados para notificaciones push (APP-03 / APP-06).

Cada fila es el destino FCM de una instalación de la app: el registration
token que entrega FirebaseMessaging.getToken(). Identifica al dispositivo, no
a la persona: si otra cuenta inicia sesión en el mismo teléfono, el registro
se reasigna a esa cuenta.

Desactivar un dispositivo (logout o token inválido) solo detiene los push;
no revoca ninguna sesión. La revocación sigue siendo la de los jti en Redis.
"""

from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING
from uuid import UUID as PyUUID

from sqlalchemy import Boolean, DateTime, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base, BaseEntity

if TYPE_CHECKING:
    from app.models.user import User


class UserDevice(Base, BaseEntity):
    __tablename__ = "user_devices"

    user_id: Mapped[PyUUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    token: Mapped[str] = mapped_column(String(4096), nullable=False, unique=True)
    platform: Mapped[str] = mapped_column(String(20), nullable=False)
    device_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(20), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    deactivated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped["User"] = relationship(lazy="raise_on_sql")
