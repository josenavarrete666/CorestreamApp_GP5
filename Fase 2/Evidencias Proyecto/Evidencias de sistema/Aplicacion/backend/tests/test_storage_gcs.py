"""Cloud Storage signed URLs, checked offline with a throwaway service account key."""

from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import MagicMock
from urllib.parse import parse_qs, urlparse

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from google.cloud import storage as gcs
from google.oauth2 import service_account

from app.services.storage import GCSStorage, content_disposition

BUCKET = "corestream-file"
KEY = "pending/0b6f3c3e-5b7a-4c38-9f0e-2a1d7c9e8f10"


@pytest.fixture(scope="module")
def storage() -> GCSStorage:
    pem = rsa.generate_private_key(public_exponent=65537, key_size=2048).private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ).decode()
    creds = service_account.Credentials.from_service_account_info({
        "type": "service_account",
        "project_id": "corestream-project",
        "private_key_id": "test",
        "private_key": pem,
        "client_email": "corestream-api@corestream-project.iam.gserviceaccount.com",
        "client_id": "1",
        "token_uri": "https://oauth2.googleapis.com/token",
    })
    client = gcs.Client(project="corestream-project", credentials=creds)
    return GCSStorage(BUCKET, client=client)


def _qs(url: str) -> dict:
    return {k: v[0] for k, v in parse_qs(urlparse(url).query).items()}


async def test_url_de_subida_firma_tipo_y_limite_de_tamano(storage):
    signed = await storage.upload_url(KEY, "application/pdf", 25 * 1024 * 1024)
    url = urlparse(signed.url)
    qs = _qs(signed.url)

    assert url.netloc == "storage.googleapis.com"
    assert url.path == f"/{BUCKET}/{KEY}"
    assert qs["X-Goog-Algorithm"] == "GOOG4-RSA-SHA256"
    assert qs["X-Goog-Expires"] == "900"
    assert set(qs["X-Goog-SignedHeaders"].split(";")) == {
        "content-type", "host", "x-goog-content-length-range"
    }
    assert signed.headers == {
        "Content-Type": "application/pdf",
        "x-goog-content-length-range": f"0,{25 * 1024 * 1024}",
    }


async def test_url_de_descarga_fuerza_nombre_y_tipo(storage):
    url = await storage.download_url(
        KEY.replace("pending", "documents"), "diseño técnico.pdf", "application/pdf"
    )
    qs = _qs(url)
    assert qs["X-Goog-Expires"] == "300"
    assert qs["response-content-type"] == "application/pdf"
    assert qs["response-content-disposition"] == content_disposition("diseño técnico.pdf")


async def test_rechaza_claves_que_no_genero_el_servidor(storage):
    for malo in ("../secreto", "documents/../../x", "otra/0b6f3c3e-5b7a-4c38-9f0e-2a1d7c9e8f10", ""):
        with pytest.raises(ValueError):
            await storage.upload_url(malo, "text/plain", 10)


def test_content_disposition_ascii_y_utf8():
    cd = content_disposition('in"forme ñ.txt')
    assert cd.startswith('attachment; filename="informe _.txt"')
    assert "filename*=UTF-8''in%22forme%20%C3%B1.txt" in cd


def test_en_cloud_run_firma_via_iam():
    """Metadata-server credentials have no private key: sign through IAM signBlob."""
    creds = SimpleNamespace(
        valid=False,
        token=None,
        service_account_email="default",
    )

    def refresh(_request):
        creds.valid = True
        creds.token = "ya29.token"
        creds.service_account_email = "123-compute@developer.gserviceaccount.com"

    creds.refresh = refresh
    client = MagicMock()
    client._credentials = creds
    storage = GCSStorage(BUCKET, client=client)

    assert storage._signing_kwargs() == {
        "service_account_email": "123-compute@developer.gserviceaccount.com",
        "access_token": "ya29.token",
    }


async def test_borrar_un_objeto_inexistente_no_falla():
    from google.api_core.exceptions import NotFound

    client = MagicMock()
    client.bucket.return_value.blob.return_value.delete.side_effect = NotFound("x")
    await GCSStorage(BUCKET, client=client).delete(KEY)


async def test_mover_copia_y_borra_el_origen():
    client = MagicMock()
    bucket = client.bucket.return_value
    dst = KEY.replace("pending", "documents")
    await GCSStorage(BUCKET, client=client).move(KEY, dst)
    bucket.copy_blob.assert_called_once_with(bucket.blob.return_value, bucket, dst)
    bucket.blob.return_value.delete.assert_called_once()


def test_expiraciones():
    from app.services.storage import DOWNLOAD_URL_TTL, UPLOAD_URL_TTL

    assert UPLOAD_URL_TTL == timedelta(minutes=15)
    assert DOWNLOAD_URL_TTL == timedelta(minutes=5)


def test_produccion_exige_cloud_storage():
    from pydantic import ValidationError

    from app.config import Settings

    base = dict(
        ENVIRONMENT="production", DEBUG=False, SECRET_KEY="a" * 64,
        ALLOWED_ORIGINS="https://corestream.alloxentric.com",
    )
    with pytest.raises(ValidationError, match="Cloud Storage"):
        Settings(**base, STORAGE_BACKEND="local")
    with pytest.raises(ValidationError, match="Cloud Storage"):
        Settings(**base, STORAGE_BACKEND="gcs", GCS_BUCKET="")
    ok = Settings(**base, STORAGE_BACKEND="gcs", GCS_BUCKET="corestream-file")
    assert ok.GCS_BUCKET == "corestream-file"
