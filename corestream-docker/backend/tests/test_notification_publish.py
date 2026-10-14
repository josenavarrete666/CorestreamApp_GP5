"""Direct Redis publish of notifications (replaces the ARQ worker)."""

import asyncio
from datetime import datetime, timezone
from types import SimpleNamespace
from uuid import uuid4

from app.models import Notification, NotificationType
from app.services import notification_service as ns


def _notification() -> Notification:
    n = Notification(
        user_id=uuid4(),
        ticket_id=uuid4(),
        title="Ticket asignado",
        message="Ana te asignó el ticket",
        type=NotificationType.TICKET_ASSIGNED,
        is_read=False,
    )
    n.id = uuid4()
    n.created_at = datetime(2026, 9, 30, 12, 0, tzinfo=timezone.utc)
    return n


async def test_publica_en_el_canal_del_usuario_con_el_formato_del_worker(monkeypatch):
    sent = {}

    async def fake_publish(channel, data):
        sent["channel"], sent["data"] = channel, data
        return 1

    monkeypatch.setattr(ns, "publish_message", fake_publish)
    n = _notification()

    assert await ns.publish_notification(n) is True
    assert sent["channel"] == f"corestream:user:{n.user_id}:notifications"
    assert sent["data"] == {
        "id": str(n.id),
        "type": "TICKET_ASSIGNED",
        "title": "Ticket asignado",
        "message": "Ana te asignó el ticket",
        "ticket_id": str(n.ticket_id),
        "is_read": False,
        "created_at": "2026-09-30T12:00:00+00:00",
    }


async def test_error_de_redis_no_propaga(monkeypatch):
    async def broken(channel, data):
        raise ConnectionError("redis caído")

    monkeypatch.setattr(ns, "publish_message", broken)
    assert await ns.publish_notification(_notification()) is False


async def test_redis_lento_no_bloquea_la_respuesta(monkeypatch):
    async def slow(channel, data):
        await asyncio.sleep(10)

    monkeypatch.setattr(ns, "publish_message", slow)
    monkeypatch.setattr(ns, "PUBLISH_TIMEOUT_SECONDS", 0.05)
    assert await ns.publish_notification(_notification()) is False


async def test_flush_publica_y_vacia_las_pendientes(monkeypatch):
    published = []

    async def fake_publish(channel, data):
        published.append(data["id"])
        return 1

    monkeypatch.setattr(ns, "publish_message", fake_publish)
    a, b = _notification(), _notification()
    db = SimpleNamespace(info={"_pending_notifications": [a, b]})

    await ns.flush_pending_notifications(db)

    assert published == [str(a.id), str(b.id)]
    assert "_pending_notifications" not in db.info
