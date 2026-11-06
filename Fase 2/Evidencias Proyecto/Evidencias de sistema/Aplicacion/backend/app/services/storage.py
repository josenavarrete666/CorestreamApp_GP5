"""
Almacenamiento de archivos de documentos (migración a GCP, plan D10).

Los bytes de los archivos NUNCA pasan por la API: el navegador sube y
descarga directo contra el almacenamiento usando URLs firmadas de vida
corta. La API solo autoriza (emite la URL) y registra metadatos.

Dos implementaciones con la misma interfaz:
  - GCSStorage: Cloud Storage (producción). URLs firmadas V4.
  - LocalStorage: disco local bajo settings.UPLOAD_DIR, para desarrollo y
    tests sin GCP. Imita las URLs firmadas con un token JWT de vida corta que
    sirven los endpoints /api/documents/local-storage/{token} (desactivados
    cuando STORAGE_BACKEND=gcs).

Claves de objeto (siempre generadas por el servidor, nunca por el cliente):
  pending/<uuid>    subido pero aún no confirmado (el bucket los borra a las 24 h)
  documents/<uuid>  confirmado, referenciado por documents.file_path
"""

from __future__ import annotations

import asyncio
import os
import re
import shutil
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from pathlib import Path
from typing import Optional, Protocol
from urllib.parse import quote

from jose import JWTError, jwt

from app.config import get_settings

KEY_RE = re.compile(r"^(pending|documents)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

UPLOAD_URL_TTL = timedelta(minutes=15)
DOWNLOAD_URL_TTL = timedelta(minutes=5)

# Signed header: GCS rejects the PUT if the body is outside this range, so
# the size limit is enforced by storage itself, not only by the client.
CONTENT_LENGTH_RANGE_HEADER = "x-goog-content-length-range"


@dataclass(frozen=True)
class SignedUpload:
    url: str
    headers: dict[str, str]


def content_disposition(filename: str) -> str:
    """attachment; with an ASCII fallback and the exact UTF-8 name (RFC 6266)."""
    ascii_name = filename.encode("ascii", "replace").decode().replace('"', "").replace("?", "_")
    return f"attachment; filename=\"{ascii_name}\"; filename*=UTF-8''{quote(filename)}"


def _check_key(key: str) -> None:
    if not KEY_RE.match(key):
        raise ValueError(f"Clave de objeto inválida: {key!r}")


class Storage(Protocol):
    async def upload_url(self, key: str, content_type: str, max_bytes: int) -> SignedUpload: ...
    async def download_url(self, key: str, filename: str, content_type: str) -> str: ...
    async def size(self, key: str) -> Optional[int]: ...
    async def move(self, src: str, dst: str) -> None: ...
    async def delete(self, key: str) -> None: ...
    async def download_to(self, key: str, path: str) -> None: ...
    async def upload_from(self, path: str, key: str, content_type: str) -> None: ...


# ---------------------------------------------------------------------------
# Cloud Storage
# ---------------------------------------------------------------------------

class GCSStorage:
    """
    En Cloud Run las credenciales son las de la service account del servicio,
    que no tiene clave privada: la firma se delega a IAM (signBlob). Requiere
    que esa service account tenga roles/iam.serviceAccountTokenCreator sobre
    sí misma y roles/storage.objectAdmin sobre el bucket.
    """

    def __init__(self, bucket_name: str, client=None) -> None:
        from google.cloud import storage as gcs

        self._client = client or gcs.Client()
        self._bucket = self._client.bucket(bucket_name)

    def _signing_kwargs(self) -> dict:
        from google.auth.transport.requests import Request

        creds = self._client._credentials
        # Key-file credentials (local dev with a downloaded key) sign locally.
        if getattr(creds, "signer", None) is not None and hasattr(creds, "service_account_email"):
            return {}
        # Metadata-server credentials (Cloud Run): sign through IAM.
        if not creds.valid:
            creds.refresh(Request())
        return {"service_account_email": creds.service_account_email, "access_token": creds.token}

    def _sign(self, key: str, **kwargs) -> str:
        _check_key(key)
        return self._bucket.blob(key).generate_signed_url(
            version="v4", **kwargs, **self._signing_kwargs()
        )

    async def upload_url(self, key: str, content_type: str, max_bytes: int) -> SignedUpload:
        headers = {CONTENT_LENGTH_RANGE_HEADER: f"0,{max_bytes}"}
        # A copy: the library adds "Host" to the dict it receives, and the
        # browser must not be told to send that one.
        url = await asyncio.to_thread(
            self._sign, key, method="PUT", expiration=UPLOAD_URL_TTL,
            content_type=content_type, headers=dict(headers),
        )
        return SignedUpload(url=url, headers={"Content-Type": content_type, **headers})

    async def download_url(self, key: str, filename: str, content_type: str) -> str:
        return await asyncio.to_thread(
            self._sign, key, method="GET", expiration=DOWNLOAD_URL_TTL,
            response_disposition=content_disposition(filename), response_type=content_type,
        )

    async def size(self, key: str) -> Optional[int]:
        _check_key(key)
        blob = await asyncio.to_thread(self._bucket.get_blob, key)
        return None if blob is None else blob.size

    async def move(self, src: str, dst: str) -> None:
        _check_key(src)
        _check_key(dst)
        blob = self._bucket.blob(src)
        await asyncio.to_thread(self._bucket.copy_blob, blob, self._bucket, dst)
        await asyncio.to_thread(blob.delete)

    async def delete(self, key: str) -> None:
        from google.api_core.exceptions import NotFound

        _check_key(key)
        try:
            await asyncio.to_thread(self._bucket.blob(key).delete)
        except NotFound:
            pass

    async def download_to(self, key: str, path: str) -> None:
        _check_key(key)
        await asyncio.to_thread(self._bucket.blob(key).download_to_filename, path)

    async def upload_from(self, path: str, key: str, content_type: str) -> None:
        _check_key(key)
        await asyncio.to_thread(
            self._bucket.blob(key).upload_from_filename, path, content_type=content_type
        )


# ---------------------------------------------------------------------------
# Local disk (desarrollo / tests)
# ---------------------------------------------------------------------------

LOCAL_TOKEN_PREFIX = "/api/documents/local-storage/"


class LocalStorage:
    def __init__(self, root: str) -> None:
        self.root = Path(root) / "objects"

    def _path(self, key: str) -> Path:
        _check_key(key)
        return self.root / key

    def _token(self, claims: dict, ttl: timedelta) -> str:
        s = get_settings()
        claims = {**claims, "exp": datetime.now(timezone.utc) + ttl}
        return jwt.encode(claims, s.SECRET_KEY, algorithm=s.ALGORITHM)

    @staticmethod
    def read_token(token: str, expected_type: str) -> Optional[dict]:
        s = get_settings()
        try:
            claims = jwt.decode(token, s.SECRET_KEY, algorithms=[s.ALGORITHM])
        except JWTError:
            return None
        if claims.get("type") != expected_type or not KEY_RE.match(str(claims.get("key", ""))):
            return None
        return claims

    async def upload_url(self, key: str, content_type: str, max_bytes: int) -> SignedUpload:
        _check_key(key)
        token = self._token(
            {"type": "storage-put", "key": key, "ct": content_type, "max": max_bytes}, UPLOAD_URL_TTL
        )
        return SignedUpload(url=LOCAL_TOKEN_PREFIX + token, headers={"Content-Type": content_type})

    async def download_url(self, key: str, filename: str, content_type: str) -> str:
        _check_key(key)
        token = self._token(
            {"type": "storage-get", "key": key, "fn": filename, "ct": content_type}, DOWNLOAD_URL_TTL
        )
        return LOCAL_TOKEN_PREFIX + token

    async def size(self, key: str) -> Optional[int]:
        p = self._path(key)
        return p.stat().st_size if p.is_file() else None

    async def move(self, src: str, dst: str) -> None:
        d = self._path(dst)
        d.parent.mkdir(parents=True, exist_ok=True)
        await asyncio.to_thread(os.replace, self._path(src), d)

    async def delete(self, key: str) -> None:
        self._path(key).unlink(missing_ok=True)

    async def download_to(self, key: str, path: str) -> None:
        await asyncio.to_thread(shutil.copyfile, self._path(key), path)

    async def upload_from(self, path: str, key: str, content_type: str) -> None:
        d = self._path(key)
        d.parent.mkdir(parents=True, exist_ok=True)
        await asyncio.to_thread(shutil.copyfile, path, d)

    def write_path(self, key: str) -> Path:
        p = self._path(key)
        p.parent.mkdir(parents=True, exist_ok=True)
        return p

    def read_path(self, key: str) -> Path:
        return self._path(key)


@lru_cache()
def get_storage() -> Storage:
    s = get_settings()
    if s.STORAGE_BACKEND == "gcs":
        return GCSStorage(s.GCS_BUCKET)
    return LocalStorage(s.UPLOAD_DIR)
