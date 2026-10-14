"""
Servicio de notificaciones para CoreStream — CS-025.

Patrón de dos pasos:
  1. create_notification()  → guarda en DB (síncrono con la sesión del caller)
  2. publish_notification() → publica en Redis para entrega WebSocket (post-commit)

Separar persistencia de entrega garantiza que la notificación nunca se pierda
aunque el WebSocket no esté disponible: queda en la BD y el frontend la
recupera al recargar la lista de notificaciones.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Notification, NotificationType
from app.redis_client import publish_message, user_notifications_channel

logger = logging.getLogger(__name__)

# Upper bound for the Redis publish, so a slow Redis never holds the HTTP
# response: the notification is already committed and can be refetched.
PUBLISH_TIMEOUT_SECONDS = 2.0


# ---------------------------------------------------------------------------
# Paso 1: Persistencia (sincrónica con la sesión del caller)
# ---------------------------------------------------------------------------

async def create_notification(
    db: AsyncSession,
    *,
    user_id: UUID | str,
    title: str,
    message: str,
    notification_type: str,
    ticket_id: Optional[UUID | str] = None,
) -> Notification:
    """
    Guarda la notificación en PostgreSQL usando la sesión activa del caller.

    NO hace commit propio — el caller debe commitear para mantener atomicidad
    con la operación que disparó la notificación (ej. cambio de estado de ticket).

    Después del commit del caller, llamar a publish_notification() con el
    objeto Notification resultante para disparar la entrega WebSocket.
    """
    uid = UUID(str(user_id)) if not isinstance(user_id, UUID) else user_id
    tid = UUID(str(ticket_id)) if ticket_id and not isinstance(ticket_id, UUID) else ticket_id

    # Validar que el tipo existe en el enum
    try:
        ntype = NotificationType(notification_type)
    except ValueError:
        ntype = NotificationType.SYSTEM

    notification = Notification(
        user_id=uid,
        ticket_id=tid,
        title=title[:255],
        message=message[:1000],
        type=ntype,
        is_read=False,
    )
    db.add(notification)
    return notification


# ---------------------------------------------------------------------------
# Paso 2: Entrega en tiempo real (post-commit, publish directo en Redis)
# ---------------------------------------------------------------------------

def _notification_payload(notification: Notification) -> dict:
    # Same shape the ARQ worker used to publish; websocket.py wraps it in
    # {"type": "notification", "data": <payload>} before sending it.
    created_at = notification.created_at or datetime.now(timezone.utc)
    return {
        "id": str(notification.id),
        "type": notification.type.value,
        "title": notification.title,
        "message": notification.message,
        "ticket_id": str(notification.ticket_id) if notification.ticket_id else None,
        "is_read": False,
        "created_at": created_at.isoformat(),
    }


async def publish_notification(notification: Notification) -> bool:
    """
    Publica la notificación ya persistida en el canal Redis del usuario,
    al que está suscrito su WebSocket.

    Debe llamarse DESPUÉS del commit del caller para que el ID sea válido.
    Fallos silenciosos: la notificación ya está en la BD aunque no llegue
    en tiempo real.
    """
    channel = user_notifications_channel(str(notification.user_id))
    try:
        subscribers = await asyncio.wait_for(
            publish_message(channel, _notification_payload(notification)),
            timeout=PUBLISH_TIMEOUT_SECONDS,
        )
    except Exception as exc:
        logger.error("Error al publicar notificación %s: %r", notification.id, exc)
        return False

    logger.debug(
        "Notificación %s publicada | canal=%s | suscriptores=%d",
        notification.id, channel, subscribers,
    )
    return True


# ---------------------------------------------------------------------------
# Helpers de alto nivel — llamar desde routers / services
# ---------------------------------------------------------------------------

async def notify_ticket_assigned(
    db: AsyncSession,
    *,
    ticket_id: UUID | str,
    assignee_id: UUID | str,
    assigner_name: str,
    ticket_title: str,
) -> None:
    """Notifica al nuevo asignado cuando se le asigna un ticket."""
    notif = await create_notification(
        db,
        user_id=assignee_id,
        title="Ticket asignado",
        message=f'{assigner_name} te asignó el ticket "{ticket_title}"',
        notification_type=NotificationType.TICKET_ASSIGNED.value,
        ticket_id=ticket_id,
    )
    db.info["_pending_notifications"] = db.info.get("_pending_notifications", [])
    db.info["_pending_notifications"].append(notif)


async def notify_status_changed(
    db: AsyncSession,
    *,
    ticket_id: UUID | str,
    owner_id: UUID | str,
    actor_name: str,
    ticket_title: str,
    new_status: str,
) -> None:
    """Notifica al creador del ticket cuando el estado cambia."""
    notif = await create_notification(
        db,
        user_id=owner_id,
        title="Estado de ticket actualizado",
        message=f'{actor_name} cambió "{ticket_title}" a {new_status}',
        notification_type=NotificationType.STATUS_CHANGED.value,
        ticket_id=ticket_id,
    )
    db.info["_pending_notifications"] = db.info.get("_pending_notifications", [])
    db.info["_pending_notifications"].append(notif)


async def notify_ticket_redirected(
    db: AsyncSession,
    *,
    ticket_id: UUID | str,
    new_assignee_id: UUID | str,
    redirector_name: str,
    ticket_title: str,
    justification: str,
) -> None:
    """Notifica al nuevo asignado en una redirección."""
    notif = await create_notification(
        db,
        user_id=new_assignee_id,
        title="Ticket redirigido a ti",
        message=f'{redirector_name} te redirigió "{ticket_title}". Motivo: {justification[:200]}',
        notification_type=NotificationType.TICKET_REDIRECTED.value,
        ticket_id=ticket_id,
    )
    db.info["_pending_notifications"] = db.info.get("_pending_notifications", [])
    db.info["_pending_notifications"].append(notif)


async def notify_ticket_completed(
    db: AsyncSession,
    *,
    ticket_id: UUID | str,
    owner_id: UUID | str,
    developer_name: str,
    ticket_title: str,
) -> None:
    """Notifica al líder/creador cuando un ticket se completa."""
    notif = await create_notification(
        db,
        user_id=owner_id,
        title="Ticket completado",
        message=f'{developer_name} completó el ticket "{ticket_title}"',
        notification_type=NotificationType.TICKET_COMPLETED.value,
        ticket_id=ticket_id,
    )
    db.info["_pending_notifications"] = db.info.get("_pending_notifications", [])
    db.info["_pending_notifications"].append(notif)


async def notify_question_raised(
    db: AsyncSession,
    *,
    ticket_id: UUID | str,
    owner_id: UUID | str,
    developer_name: str,
    ticket_title: str,
) -> None:
    """Notifica al líder cuando se levanta una pregunta bloqueante."""
    notif = await create_notification(
        db,
        user_id=owner_id,
        title="Pregunta bloqueante en ticket",
        message=f'{developer_name} levantó una pregunta en "{ticket_title}"',
        notification_type=NotificationType.QUESTION_RAISED.value,
        ticket_id=ticket_id,
    )
    db.info["_pending_notifications"] = db.info.get("_pending_notifications", [])
    db.info["_pending_notifications"].append(notif)


async def flush_pending_notifications(db: AsyncSession) -> None:
    """
    Publica todas las notificaciones pendientes de la sesión actual.

    Llamar DESPUÉS de db.commit() para que los IDs de notificación
    sean válidos y la entrega pueda referenciarlos.

    Patrón de uso en un router:
        notif = await notify_ticket_assigned(db, ...)
        await db.commit()
        await flush_pending_notifications(db)
    """
    pending = db.info.pop("_pending_notifications", [])
    for notif in pending:
        await publish_notification(notif)


# Instancia singleton para compatibilidad con código que usa notification_service.X
notification_service = None  # La nueva API es funcional (no basada en instancias)
