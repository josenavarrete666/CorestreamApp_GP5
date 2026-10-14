"""Server-side idle backstop of the notifications WebSocket."""

import asyncio
import json

import pytest
from fastapi import WebSocketDisconnect

from app.routers.websocket import IDLE_SENTINEL, _listen_for_client


class FakeSocket:
    """receive_text() plays (delay_seconds, message) pairs, then blocks."""

    def __init__(self, script):
        self.script = list(script)

    async def receive_text(self):
        if not self.script:
            await asyncio.sleep(3600)
        delay, msg = self.script.pop(0)
        await asyncio.sleep(delay)
        if isinstance(msg, Exception):
            raise msg
        return msg


def _msg(kind):
    return json.dumps({"type": kind})


async def test_sin_actividad_cierra_al_vencer_el_plazo():
    loop = asyncio.get_event_loop()
    start = loop.time()
    result = await _listen_for_client(FakeSocket([]), "u1", idle_timeout=0.2)
    assert result == IDLE_SENTINEL
    assert 0.18 <= loop.time() - start < 0.5


async def test_ping_pong_automatico_no_cuenta_como_actividad():
    sock = FakeSocket([(0.05, _msg("pong")), (0.05, _msg("ping")), (0.05, _msg("pong"))])
    loop = asyncio.get_event_loop()
    start = loop.time()
    assert await _listen_for_client(sock, "u1", idle_timeout=0.25) == IDLE_SENTINEL
    assert loop.time() - start < 0.4


async def test_actividad_renueva_el_plazo():
    sock = FakeSocket([(0.15, _msg("activity")), (0.15, _msg("activity"))])
    loop = asyncio.get_event_loop()
    start = loop.time()
    assert await _listen_for_client(sock, "u1", idle_timeout=0.2) == IDLE_SENTINEL
    # 0.15 + 0.15 of activity, then a full 0.2 window: well past a single 0.2.
    assert loop.time() - start >= 0.45


async def test_mensajes_basura_no_rompen_ni_renuevan():
    sock = FakeSocket([(0.02, "no-json"), (0.02, "[1,2]"), (0.02, '"texto"')])
    assert await _listen_for_client(sock, "u1", idle_timeout=0.15) == IDLE_SENTINEL


async def test_desconexion_del_cliente_se_propaga():
    sock = FakeSocket([(0.01, WebSocketDisconnect(code=1001))])
    with pytest.raises(WebSocketDisconnect):
        await _listen_for_client(sock, "u1", idle_timeout=5)
