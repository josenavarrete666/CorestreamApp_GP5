"""
Dispositivos push (APP-06) y su desactivación en el logout (APP-03).

Contrato: CoreStream-Mobile-Especificacion-API §4.1–4.6. El envío a Firebase
se sustituye por un registro en memoria: lo que se prueba es a qué
dispositivos se dirige cada push y qué pasa con ellos, no FCM.
"""

import pytest

from app.services import push_service

from .conftest import DEV, DEV2

pytestmark = pytest.mark.asyncio(loop_scope="session")

TOKEN = "fcm-token-dispositivo-de-prueba-1"
DEVICE = {"fcm_token": TOKEN, "platform": "ANDROID", "device_name": "S20 de Diego", "app_version": "1.0.0"}


async def _fresh_session(client, user) -> dict:
    """Sesión propia: los headers de sesión de conftest no deben cerrarse."""
    res = await client.post(
        "/api/auth/login", json={"email": user["email"], "password": user["password"]}
    )
    assert res.status_code == 200, res.text[:200]
    return {"Authorization": f"Bearer {res.json()['access_token']}"}


async def _devices(client, headers) -> list:
    res = await client.get("/api/devices/", headers=headers)
    assert res.status_code == 200, res.text[:200]
    return res.json()


class _Calls(list):
    outcome: dict


@pytest.fixture
def push(monkeypatch):
    """Sustituye el envío FCM; registra (token, tipo) y permite fijar el resultado."""
    calls = _Calls()
    calls.outcome = {"result": "sent"}

    async def fake_send(token, notification):
        calls.append((token, notification.type.value))
        return calls.outcome["result"]

    monkeypatch.setattr(push_service, "send_to_device", fake_send)
    return calls


async def _assign_ticket_to_dev(client, leader_headers, epic, dev_id):
    res = await client.post(
        "/api/tickets/",
        json={"epic_id": epic["id"], "title": "Ticket con push", "assignee_id": dev_id,
              "priority": "HIGH"},
        headers=leader_headers,
    )
    assert res.status_code == 201, res.text[:300]
    await push_service.drain_pending_push()


# ---------------------------------------------------------------------------
# Registro y baja (§4.1–4.3)
# ---------------------------------------------------------------------------

async def test_registrar_dispositivo_nuevo_responde_201_sin_exponer_el_token(
    client, dev_headers, dev_id
):
    res = await client.post("/api/devices/", json=DEVICE, headers=dev_headers)
    assert res.status_code == 201, res.text[:200]
    body = res.json()
    assert body["is_active"] is True and body["platform"] == "ANDROID"
    assert body["user_id"] == dev_id
    assert body["device_name"] == "S20 de Diego" and body["app_version"] == "1.0.0"
    assert "fcm_token" not in body and "token" not in body
    assert [d["id"] for d in await _devices(client, dev_headers)] == [body["id"]]


async def test_registrar_dos_veces_responde_200_y_no_duplica(client, dev_headers):
    first = await client.post("/api/devices/", json=DEVICE, headers=dev_headers)
    second = await client.post("/api/devices/", json=DEVICE, headers=dev_headers)
    assert (first.status_code, second.status_code) == (201, 200)
    assert len(await _devices(client, dev_headers)) == 1


async def test_el_mismo_telefono_pasa_a_la_cuenta_que_inicia_sesion(client, dev_headers, dev2_headers):
    await client.post("/api/devices/", json=DEVICE, headers=dev_headers)
    res = await client.post("/api/devices/", json=DEVICE, headers=dev2_headers)
    assert res.status_code == 200
    assert await _devices(client, dev_headers) == []
    assert len(await _devices(client, dev2_headers)) == 1


async def test_token_vacio_usa_el_mensaje_del_contrato(client, dev_headers):
    res = await client.post("/api/devices/", json={**DEVICE, "fcm_token": "  "}, headers=dev_headers)
    assert res.status_code == 422
    assert res.json() == {"detail": "El token FCM no puede estar vacío"}


async def test_plataforma_fuera_del_enum_es_422(client, dev_headers):
    res = await client.post("/api/devices/", json={**DEVICE, "platform": "web"}, headers=dev_headers)
    assert res.status_code == 422


async def test_dar_de_baja_elimina_solo_un_dispositivo_propio(client, dev_headers, dev2_headers):
    device_id = (await client.post("/api/devices/", json=DEVICE, headers=dev_headers)).json()["id"]

    ajeno = await client.delete(f"/api/devices/{device_id}", headers=dev2_headers)
    assert ajeno.status_code == 403
    assert ajeno.json() == {"detail": "No puede eliminar dispositivos de otro usuario"}

    propio = await client.delete(f"/api/devices/{device_id}", headers=dev_headers)
    assert propio.status_code == 204
    assert await _devices(client, dev_headers) == []

    otra_vez = await client.delete(f"/api/devices/{device_id}", headers=dev_headers)
    assert otra_vez.status_code == 404
    assert otra_vez.json() == {"detail": "Dispositivo no encontrado"}


async def test_sin_autenticacion_no_se_registra(client):
    res = await client.post("/api/devices/", json=DEVICE)
    assert res.status_code in (401, 403)


# ---------------------------------------------------------------------------
# APP-03: logout (§4.6)
# ---------------------------------------------------------------------------

async def test_logout_revoca_la_sesion_y_desactiva_el_dispositivo(client):
    headers = await _fresh_session(client, DEV2)
    await client.post("/api/devices/", json=DEVICE, headers=headers)

    res = await client.post("/api/auth/logout", json={"fcm_token": TOKEN}, headers=headers)
    assert res.status_code == 200
    assert res.json()["device_deactivated"] is True

    # El access usado ya no sirve (revocación) y el refresh tampoco renueva.
    assert (await client.get("/api/auth/me", headers=headers)).status_code == 401
    assert (await client.post("/api/auth/refresh")).status_code == 401

    other = await _fresh_session(client, DEV2)
    [device] = await _devices(client, other)
    assert device["is_active"] is False
    client.cookies.clear()


async def test_logout_sin_dispositivo_sigue_funcionando(client):
    headers = await _fresh_session(client, DEV2)
    res = await client.post("/api/auth/logout", headers=headers)
    assert res.status_code == 200
    assert res.json()["device_deactivated"] is False
    client.cookies.clear()


async def test_logout_no_desactiva_el_telefono_de_otra_cuenta(client, dev_headers):
    await client.post("/api/devices/", json=DEVICE, headers=dev_headers)
    headers = await _fresh_session(client, DEV2)

    res = await client.post("/api/auth/logout", json={"fcm_token": TOKEN}, headers=headers)
    assert res.json()["device_deactivated"] is False
    [device] = await _devices(client, dev_headers)
    assert device["is_active"] is True
    client.cookies.clear()


# ---------------------------------------------------------------------------
# APP-06: envío
# ---------------------------------------------------------------------------

async def test_una_asignacion_envia_push_al_dispositivo_del_asignado(
    client, push, leader_headers, dev_headers, epic, dev_id
):
    await client.post("/api/devices/", json=DEVICE, headers=dev_headers)
    await _assign_ticket_to_dev(client, leader_headers, epic, dev_id)
    assert push == [(TOKEN, "TICKET_ASSIGNED")]


async def test_tras_el_logout_el_dispositivo_ya_no_recibe_push(
    client, push, leader_headers, epic, dev_id
):
    headers = await _fresh_session(client, DEV)
    await client.post("/api/devices/", json=DEVICE, headers=headers)
    await client.post("/api/auth/logout", json={"fcm_token": TOKEN}, headers=headers)
    client.cookies.clear()

    await _assign_ticket_to_dev(client, leader_headers, epic, dev_id)
    assert push == []


async def test_dispositivo_dado_de_baja_no_recibe_push(
    client, push, leader_headers, dev_headers, epic, dev_id
):
    device_id = (await client.post("/api/devices/", json=DEVICE, headers=dev_headers)).json()["id"]
    await client.delete(f"/api/devices/{device_id}", headers=dev_headers)

    await _assign_ticket_to_dev(client, leader_headers, epic, dev_id)
    assert push == []


async def test_token_invalido_desactiva_el_dispositivo(
    client, push, leader_headers, dev_headers, epic, dev_id
):
    await client.post("/api/devices/", json=DEVICE, headers=dev_headers)
    push.outcome["result"] = "invalid"

    await _assign_ticket_to_dev(client, leader_headers, epic, dev_id)

    [device] = await _devices(client, dev_headers)
    assert device["is_active"] is False


async def test_preferencias_silencian_el_tipo_elegido(
    client, push, leader_headers, dev_headers, epic, dev_id
):
    await client.post("/api/devices/", json=DEVICE, headers=dev_headers)
    res = await client.put(
        "/api/devices/preferences",
        json={"enabled": True, "muted_types": ["TICKET_ASSIGNED"]},
        headers=dev_headers,
    )
    assert res.status_code == 200
    assert (await client.get("/api/devices/preferences", headers=dev_headers)).json() == {
        "enabled": True, "muted_types": ["TICKET_ASSIGNED"]
    }

    await _assign_ticket_to_dev(client, leader_headers, epic, dev_id)
    assert push == []


async def test_las_preferencias_conservan_el_resto_del_perfil(client, dev_headers):
    await client.put("/api/devices/preferences", json={"enabled": False}, headers=dev_headers)
    me = (await client.get("/api/auth/me", headers=dev_headers)).json()
    assert me["preferences"]["push"] == {"enabled": False, "muted_types": []}
