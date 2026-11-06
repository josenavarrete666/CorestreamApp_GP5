"""Archivo privado de contraseñas compartidas del equipo (scripts/dev_accounts)."""

import json

import pytest

from scripts import beta_content, dev_accounts
from scripts.beta_content import ContentError


@pytest.fixture
def local_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(beta_content, "LOCAL_DIRECTORY", tmp_path)
    return tmp_path


def _write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    return path


def test_lee_la_lista_y_normaliza_los_correos(local_dir):
    path = _write(local_dir / "credenciales-dev.json", [
        {"nombre": "Ana Torres", "rol": "ADMIN", "email": "A.Torres@Alloxentric.com", "password": "Mango.1234"},
        {"email": "d.ramos@alloxentric.com", "password": "Limon.5678"},
    ])
    assert dev_accounts.read_credentials(path) == {
        "a.torres@alloxentric.com": "Mango.1234",
        "d.ramos@alloxentric.com": "Limon.5678",
    }


def test_acepta_el_archivo_con_bom_que_escribe_powershell(local_dir):
    path = local_dir / "credenciales-dev.json"
    path.write_bytes(b"\xef\xbb\xbf" + json.dumps([{"email": "a@x.com", "password": "Clave.1234"}]).encode())
    assert dev_accounts.read_credentials(path) == {"a@x.com": "Clave.1234"}


@pytest.mark.parametrize("data", [
    [],
    {"otra": 1},
    [{"email": "sin-arroba", "password": "Clave.1234"}],
    [{"email": "a@x.com"}],
    [{"email": "a@x.com", "password": "corta"}],
])
def test_rechaza_archivos_invalidos_sin_mostrar_valores(local_dir, data):
    path = _write(local_dir / "credenciales-dev.json", data)
    with pytest.raises(ContentError) as error:
        dev_accounts.read_credentials(path)
    assert "corta" not in str(error.value)


def test_solo_lee_archivos_dentro_de_backend_local(local_dir, tmp_path_factory):
    outside = _write(tmp_path_factory.mktemp("fuera") / "credenciales-dev.json",
                     [{"email": "a@x.com", "password": "Clave.1234"}])
    with pytest.raises(ContentError):
        dev_accounts.read_credentials(outside)


def test_sincroniza_solo_los_correos_del_archivo(local_dir):
    manifest = _write(local_dir / "beta-content.json", {"dataset_id": "x", "users": {
        "admin": {"email": "a.torres@alloxentric.com", "password": "vieja-1"},
        "u2": {"email": "l.vega@alloxentric.com", "password": "vieja-2"},
        "u3": {"email": "otro@alloxentric.com", "password": "vieja-3"},
    }})
    changed = dev_accounts.sync_manifest(manifest, {
        "a.torres@alloxentric.com": "Mango.1234",
        "l.vega@alloxentric.com": "vieja-2",
    })
    users = json.loads(manifest.read_text(encoding="utf-8"))["users"]
    assert changed == 1
    assert users["admin"]["password"] == "Mango.1234"
    assert users["u2"]["password"] == "vieja-2"
    assert users["u3"]["password"] == "vieja-3"


def test_manifiesto_inexistente_no_falla(local_dir):
    assert dev_accounts.sync_manifest(local_dir / "beta-content.json", {"a@x.com": "Clave.1234"}) == 0
