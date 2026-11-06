import asyncio
import json

import pytest

from app.routers.websocket import IDLE_SENTINEL, _listen_for_client


class ActivitySocket:
    def __init__(self, activities):
        self.activities = activities
        self.delivered = []

    async def receive_text(self):
        await asyncio.sleep(0.075)
        kind = "activity" if len(self.delivered) < self.activities else "pong"
        self.delivered.append(kind)
        return json.dumps({"type": kind})


@pytest.mark.asyncio
async def test_pongs_do_not_keep_idle_socket_alive():
    socket = ActivitySocket(0)
    assert await _listen_for_client(socket, "test-user", 0.2) == IDLE_SENTINEL
    assert socket.delivered and set(socket.delivered) == {"pong"}


@pytest.mark.asyncio
async def test_real_activity_extends_idle_deadline_then_pongs_allow_expiry():
    socket = ActivitySocket(3)
    assert await _listen_for_client(socket, "test-user", 0.2) == IDLE_SENTINEL
    assert socket.delivered[:3] == ["activity"] * 3
    assert "pong" in socket.delivered
