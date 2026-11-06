"""Push FCM (APP-06): preferencias, datos de navegación y resultados del envío."""

import asyncio
from datetime import datetime, timezone
from uuid import uuid4

import pytest
from firebase_admin import exceptions, messaging

from app.models import Notification, NotificationType
from app.services import push_service as ps


def _notification(ticket=True) -> Notification:
    n = Notification(
        user_id=uuid4(),
        ticket_id=uuid4() if ticket else None,
        title="Ticket asignado",
        message="Ana te asignó el ticket",
        type=NotificationType.TICKET_ASSIGNED,
        is_read=False,
    )
    n.id = uuid4()
    n.created_at = datetime(2026, 11, 4, 12, 0, tzinfo=timezone.utc)
    return n


@pytest.mark.parametrize(
    ("preferences", "allowed"),
    [
        (None, True),
        ({}, True),
        ({"avatar_color": "#4C8DFF"}, True),
        ({"push": {"enabled": False}}, False),
        ({"push": {"enabled": True, "muted_types": ["TICKET_ASSIGNED"]}}, False),
        ({"push": {"enabled": True, "muted_types": ["STATUS_CHANGED"]}}, True),
        ({"push": "corrupto"}, True),
        ({"push": {"enabled": True, "muted_types": ["NO_EXISTE"]}}, True),
    ],
)
def test_preferencias_deciden_si_se_envia(preferences, allowed):
    assert ps.push_allowed(preferences, "TICKET_ASSIGNED") is allowed


def test_datos_de_navegacion_apuntan_al_ticket():
    n = _notification()
    assert ps.push_data(n) == {
        "notification_id": str(n.id),
        "type": "TICKET_ASSIGNED",
        "ticket_id": str(n.ticket_id),
        "route": f"/tickets/{n.ticket_id}",
    }


def test_sin_ticket_la_navegacion_va_a_la_bandeja():
    data = ps.push_data(_notification(ticket=False))
    assert data["ticket_id"] == ""
    assert data["route"] == "/notifications"


async def test_sin_credencial_queda_en_modo_simulado(monkeypatch):
    monkeypatch.setattr(ps, "_get_firebase_app", lambda: None)
    assert await ps.send_to_device("token", _notification()) == "simulated"


@pytest.mark.parametrize(
    "error",
    [
        messaging.UnregisteredError("token dado de baja"),
        exceptions.InvalidArgumentError("token mal formado"),
    ],
)
async def test_token_rechazado_se_informa_como_invalido(monkeypatch, error):
    def fake_send(message, app=None):
        raise error

    monkeypatch.setattr(ps, "_get_firebase_app", lambda: object())
    monkeypatch.setattr(messaging, "send", fake_send)
    assert await ps.send_to_device("token", _notification()) == "invalid"


async def test_otro_error_no_desactiva_el_dispositivo(monkeypatch):
    def fake_send(message, app=None):
        raise exceptions.UnavailableError("FCM caído")

    monkeypatch.setattr(ps, "_get_firebase_app", lambda: object())
    monkeypatch.setattr(messaging, "send", fake_send)
    assert await ps.send_to_device("token", _notification()) == "error"


async def test_envio_correcto_lleva_titulo_cuerpo_y_datos(monkeypatch):
    sent = []
    monkeypatch.setattr(ps, "_get_firebase_app", lambda: object())
    monkeypatch.setattr(messaging, "send", lambda message, app=None: sent.append(message))
    n = _notification()

    assert await ps.send_to_device("token-abc", n) == "sent"
    assert sent[0].token == "token-abc"
    assert sent[0].notification.title == "Ticket asignado"
    assert sent[0].data == ps.push_data(n)


async def test_programar_no_bloquea_y_drain_espera(monkeypatch):
    started = asyncio.Event()
    release = asyncio.Event()
    delivered = []

    async def slow_deliver(ids):
        started.set()
        await release.wait()
        delivered.extend(ids)

    monkeypatch.setattr(ps, "deliver_push", slow_deliver)
    ids = [uuid4()]

    ps.schedule_push(ids)
    await started.wait()
    assert delivered == []  # el caller ya siguió sin esperar al envío

    release.set()
    await ps.drain_pending_push()
    assert delivered == ids


def test_lista_vacia_no_programa_nada(monkeypatch):
    monkeypatch.setattr(ps, "deliver_push", lambda ids: pytest.fail("no debía enviar"))
    ps.schedule_push([])
