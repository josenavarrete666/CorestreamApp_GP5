"""
Esquemas de dispositivos push y preferencias de notificación (APP-03 / APP-06).

Contrato según CoreStream-Mobile-Especificacion-API §4.1–4.3 (Alloxentric).
"""

from datetime import datetime
from typing import Literal, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.models import NotificationType

DevicePlatform = Literal["ANDROID", "IOS"]


class DeviceRegister(BaseModel):
    """Token FCM del dispositivo actual, enviado tras iniciar sesión (§4.1)."""
    # Sin min_length: el router responde el mensaje literal del contrato
    # ("El token FCM no puede estar vacío") en lugar del genérico de Pydantic.
    fcm_token: str = Field(..., max_length=4096)
    platform: DevicePlatform
    device_name: Optional[str] = Field(default=None, max_length=120)
    app_version: Optional[str] = Field(default=None, max_length=20)


class DeviceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    platform: str
    device_name: Optional[str]
    app_version: Optional[str]
    is_active: bool
    created_at: datetime
    last_seen_at: datetime
    deactivated_at: Optional[datetime]


class PushPreferences(BaseModel):
    """Se guarda en users.preferences["push"]; ausente = todo activado."""
    enabled: bool = True
    muted_types: list[NotificationType] = Field(default_factory=list)
