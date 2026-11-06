"""
Router de dispositivos push y preferencias de notificación (APP-03 / APP-06).

Contrato: CoreStream-Mobile-Especificacion-API §4.1–4.5 (Alloxentric).
Cada usuario solo registra, consulta y da de baja sus propios dispositivos.
El logout también desactiva el dispositivo actual (ver auth.py).
"""

from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.middleware.auth import get_current_user
from app.models import User, UserDevice
from app.schemas.device import DeviceRegister, DeviceResponse, PushPreferences
from app.services.device_service import register_device
from app.services.push_service import push_preferences

router = APIRouter(tags=["Dispositivos"])


@router.post(
    "/",
    response_model=DeviceResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar dispositivo (token FCM)",
    description=(
        "Registra el dispositivo del usuario autenticado para push. Idempotente por "
        "fcm_token: 201 si es nuevo, 200 si ya existía (también si era de otra cuenta)."
    ),
)
async def register_current_device(
    body: DeviceRegister,
    response: Response,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> DeviceResponse:
    if not body.fcm_token.strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="El token FCM no puede estar vacío",
        )
    device, created = await register_device(
        db,
        user_id=current_user.id,
        token=body.fcm_token,
        platform=body.platform,
        device_name=body.device_name,
        app_version=body.app_version,
    )
    if not created:
        response.status_code = status.HTTP_200_OK
    return DeviceResponse.model_validate(device)


@router.get(
    "/",
    response_model=List[DeviceResponse],
    summary="Listar mis dispositivos",
)
async def list_my_devices(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> List[DeviceResponse]:
    result = await db.execute(
        select(UserDevice)
        .where(UserDevice.user_id == current_user.id)
        .order_by(UserDevice.last_seen_at.desc())
    )
    return [DeviceResponse.model_validate(d) for d in result.scalars().all()]


@router.get(
    "/preferences",
    response_model=PushPreferences,
    summary="Obtener mis preferencias de push",
)
async def get_push_preferences(current_user: User = Depends(get_current_user)) -> PushPreferences:
    return push_preferences(current_user.preferences)


@router.put(
    "/preferences",
    response_model=PushPreferences,
    summary="Actualizar mis preferencias de push",
)
async def update_push_preferences(
    body: PushPreferences,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PushPreferences:
    # Se asigna un dict nuevo: la columna JSON no detecta mutaciones in situ.
    current_user.preferences = {**(current_user.preferences or {}), "push": body.model_dump(mode="json")}
    db.add(current_user)
    await db.commit()
    return body


@router.delete(
    "/{device_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Dar de baja un dispositivo",
    description="Elimina el dispositivo y deja de enviarle push. No cierra ninguna sesión.",
)
async def delete_device(
    device_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    device = await db.get(UserDevice, device_id)
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dispositivo no encontrado")
    if device.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No puede eliminar dispositivos de otro usuario",
        )
    await db.delete(device)
    await db.commit()
