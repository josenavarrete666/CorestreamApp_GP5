"""
Entrega de notificaciones push por Firebase Cloud Messaging (APP-06).

Tercer paso del flujo de notification_service, después de persistir y de
publicar por WebSocket:
  - Asíncrono: schedule_push() lanza una tarea en segundo plano y vuelve de
    inmediato; la operación que originó el aviso no espera a Firebase.
  - Respeta users.preferences["push"] (enabled / muted_types).
  - Solo envía a dispositivos activos; el logout los desactiva (APP-03).
  - Un token que Firebase rechaza (UNREGISTERED / INVALID_ARGUMENT) marca el
    dispositivo como inactivo.

Sin FIREBASE_CREDENTIALS_FILE el servicio queda en modo simulado: registra
en el log lo que habría enviado y no contacta a Firebase.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Any, Literal
from uuid import UUID

from sqlalchemy import select, update

from app.config import get_settings
from app.database import get_session_maker
from app.models import Notification, User, UserDevice
from app.schemas.device import PushPreferences

logger = logging.getLogger(__name__)

SEND_TIMEOUT_SECONDS = 10.0

SendResult = Literal["sent", "simulated", "invalid", "error"]

_tasks: set[asyncio.Task[None]] = set()
_firebase_app: Any = None
_firebase_failed = False


def push_preferences(preferences: dict | None) -> PushPreferences:
    """Preferencias de push guardadas; ausentes o corruptas = todo activado."""
    raw = (preferences or {}).get("push")
    if not isinstance(raw, dict):
        return PushPreferences()
    try:
        return PushPreferences.model_validate(raw)
    except ValueError:
        return PushPreferences()


def push_allowed(preferences: dict | None, notification_type: str) -> bool:
    prefs = push_preferences(preferences)
    return prefs.enabled and notification_type not in {t.value for t in prefs.muted_types}


def push_data(notification: Notification) -> dict[str, str]:
    """Datos de navegación (deep link). FCM exige que todos los valores sean str."""
    ticket_id = str(notification.ticket_id) if notification.ticket_id else ""
    return {
        "notification_id": str(notification.id),
        "type": notification.type.value,
        "ticket_id": ticket_id,
        "route": f"/tickets/{ticket_id}" if ticket_id else "/notifications",
    }


def _get_firebase_app() -> Any:
    """Inicializa Firebase una sola vez; None = modo simulado."""
    global _firebase_app, _firebase_failed
    if _firebase_app is not None or _firebase_failed:
        return _firebase_app
    path = get_settings().FIREBASE_CREDENTIALS_FILE
    if not path:
        return None
    try:
        import firebase_admin
        from firebase_admin import credentials

        _firebase_app = firebase_admin.initialize_app(
            credentials.Certificate(path), name="corestream-push"
        )
    except Exception as exc:
        # Una credencial ausente o inválida no debe romper ninguna operación:
        # se queda en modo simulado y se avisa una vez.
        _firebase_failed = True
        logger.error("Firebase no se pudo inicializar; push en modo simulado: %r", exc)
    return _firebase_app


async def send_to_device(token: str, notification: Notification) -> SendResult:
    app = _get_firebase_app()
    if app is None:
        logger.info("Push simulado | notificación=%s | tipo=%s", notification.id, notification.type.value)
        return "simulated"

    from firebase_admin import exceptions, messaging

    # El destino es el registration token que la app obtiene con getToken().
    # firebase-admin 7.7 marca `token` como obsoleto en favor de `fid`, pero la
    # API `register()`/`onRegistered` del cliente no respondió en un Android 13
    # real, así que se usa el token estable.
    message = messaging.Message(
        token=token,
        notification=messaging.Notification(title=notification.title, body=notification.message),
        data=push_data(notification),
        android=messaging.AndroidConfig(priority="high"),
    )
    try:
        await asyncio.wait_for(
            asyncio.to_thread(messaging.send, message, app=app), timeout=SEND_TIMEOUT_SECONDS
        )
    except (messaging.UnregisteredError, exceptions.InvalidArgumentError, exceptions.NotFoundError):
        return "invalid"
    except Exception as exc:
        logger.error("Error al enviar push de %s: %r", notification.id, exc)
        return "error"
    return "sent"


async def deliver_push(notification_ids: list[UUID]) -> dict[str, int]:
    """
    Envía cada notificación a los dispositivos activos de su destinatario.

    Abre su propia sesión: corre después de que la petición original terminó.
    Devuelve el conteo por resultado, útil para pruebas y diagnóstico.
    """
    counts: dict[str, int] = {}
    async with get_session_maker()() as db:
        notifications = (
            await db.execute(select(Notification).where(Notification.id.in_(notification_ids)))
        ).scalars().all()
        for notification in notifications:
            preferences = (
                await db.execute(select(User.preferences).where(User.id == notification.user_id))
            ).scalar_one_or_none()
            if not push_allowed(preferences, notification.type.value):
                counts["muted"] = counts.get("muted", 0) + 1
                continue
            devices = (
                await db.execute(
                    select(UserDevice).where(
                        UserDevice.user_id == notification.user_id, UserDevice.is_active
                    )
                )
            ).scalars().all()
            for device in devices:
                result = await send_to_device(device.token, notification)
                counts[result] = counts.get(result, 0) + 1
                if result == "invalid":
                    await db.execute(
                        update(UserDevice)
                        .where(UserDevice.id == device.id)
                        .values(is_active=False, deactivated_at=datetime.now(timezone.utc))
                    )
        await db.commit()
    return counts


async def _run(notification_ids: list[UUID]) -> None:
    try:
        await deliver_push(notification_ids)
    except Exception as exc:
        # Fallo silencioso como el de publish_notification: el aviso ya está en la BD.
        logger.error("Error en la entrega push de %s: %r", notification_ids, exc)


def schedule_push(notification_ids: list[UUID]) -> None:
    """Lanza la entrega en segundo plano sin bloquear al caller."""
    if not notification_ids:
        return
    task = asyncio.create_task(_run(list(notification_ids)))
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)


async def drain_pending_push() -> None:
    """Espera las entregas en curso (pruebas y apagado ordenado)."""
    while _tasks:
        await asyncio.gather(*list(_tasks), return_exceptions=True)
