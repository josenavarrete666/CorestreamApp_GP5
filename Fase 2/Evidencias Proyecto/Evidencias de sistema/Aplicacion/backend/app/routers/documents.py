"""
Router de Gestión de Documentos.

Los bytes de los archivos no pasan por la API (migración a GCP, plan D10):

  Subida (3 pasos):
    1. POST /upload-url  → valida y devuelve una URL firmada de subida (15 min)
    2. PUT <url>          → el navegador sube el archivo directo al bucket
    3. POST /confirm      → la API verifica el objeto y crea el Document

  Descarga:
    GET /{id}/download-url → URL firmada de lectura (5 min), con el nombre
                              original como descarga

Así no aplica el límite de 32 MiB por request de Cloud Run y la instancia no
queda ocupada (ni facturando) mientras se transfiere el archivo. Ver
services/storage.py.
"""

import os
import re
import tempfile
from collections.abc import Sequence
from contextlib import asynccontextmanager, suppress
from datetime import datetime, timezone
from pathlib import Path as FilePath
from typing import AsyncIterator, List, Optional
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from fastapi.responses import FileResponse
from jose import JWTError, jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.config import get_settings
from app.database import get_db
from app.middleware.auth import get_current_user
from app.models import Document, Epic, Ticket, User
from app.schemas.document import (
    ConfirmUploadRequest,
    DocumentResponse,
    DownloadUrlResponse,
    TranslateRequest,
    TranslateResponse,
    UploadUrlRequest,
    UploadUrlResponse,
)
from app.services.storage import (
    KEY_RE,
    UPLOAD_URL_TTL,
    LocalStorage,
    content_disposition,
    get_storage,
)
from app.services.ticket_permissions import is_admin_or_leader
from app.services.translation_service import (
    create_translated_file,
    extract_text_from_file,
    translate_long_text,
)

router = APIRouter(tags=["Documentos"])

MAX_FILE_SIZE = 25 * 1024 * 1024  # 25 MB

ALLOWED_EXTENSIONS = {
    # Code
    ".py", ".js", ".ts", ".jsx", ".tsx", ".java", ".cpp", ".c", ".cs",
    ".rb", ".go", ".rs", ".php", ".swift", ".kt", ".scala",
    # Documentation
    ".md", ".pdf", ".docx", ".txt", ".rst", ".doc",
    # Data
    ".json", ".yaml", ".yml", ".xml", ".sql", ".csv", ".toml", ".env",
}

UPLOAD_TOKEN_TYPE = "doc-upload"
_CONTENT_TYPE_RE = re.compile(r"^[\w.+-]+/[\w.+-]+$")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _clean_filename(raw_name: str) -> tuple[str, str, str]:
    """
    Nombre visible del documento: solo el último componente de la ruta, sin
    dobles extensiones conocidas ni sufijos de copia del SO. Devuelve
    (nombre, stem, ext).
    """
    path_obj = FilePath(raw_name.replace("\\", "/") or "document")
    ext = path_obj.suffix.lower()   # Only the last extension (e.g. ".docx")
    stem = path_obj.stem            # Everything before the last dot

    # If the stem itself ends with a known extension (double-extension like
    # "report.docx.md"), strip that inner extension too.
    inner_ext = FilePath(stem).suffix.lower()
    if inner_ext and inner_ext in ALLOWED_EXTENSIONS:
        stem = FilePath(stem).stem

    # Strip OS copy-suffixes from the stem: " (1)", " (2)", " copy", etc.
    stem = re.sub(r'\s*\(\d+\)\s*$', '', stem).strip()
    stem = re.sub(r'\s+copy\s*$', '', stem, flags=re.IGNORECASE).strip()
    stem = (stem or "document")[:200]

    return (f"{stem}{ext}" if ext else stem), stem, ext


async def _dedupe_filename(
    db: AsyncSession, stem: str, ext: str, epic_id: Optional[UUID], ticket_id: Optional[UUID]
) -> str:
    """Evita nombres repetidos dentro de la misma épica/ticket: "x (1).ext"."""
    name_query = select(Document.filename)
    if epic_id:
        name_query = name_query.where(Document.epic_id == epic_id)
    elif ticket_id:
        name_query = name_query.where(Document.ticket_id == ticket_id)
    names_result = await db.execute(name_query)
    existing_names = {row[0] for row in names_result.fetchall()}

    name = f"{stem}{ext}"
    if name in existing_names:
        counter = 1
        while f"{stem} ({counter}){ext}" in existing_names:
            counter += 1
        name = f"{stem} ({counter}){ext}"
    return name


def _resolve_doc_type(doc_type: Optional[str]) -> str:
    resolved = (doc_type or "DOCUMENTATION").upper()
    return resolved if resolved in {"CODE", "DOCUMENTATION"} else "DOCUMENTATION"


def _object_key(document: Document) -> str:
    """
    file_path guarda la clave del objeto en el almacenamiento. Filas con una
    ruta de disco antigua (anteriores a la migración de archivos) no tienen
    archivo disponible.
    """
    if not KEY_RE.match(document.file_path or ""):
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail="Archivo no disponible: el documento no fue migrado al almacenamiento",
        )
    return document.file_path


async def _get_document(db: AsyncSession, doc_id: UUID) -> Document:
    result = await db.execute(select(Document).where(Document.id == doc_id))
    document = result.scalar_one_or_none()
    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Documento con ID {doc_id} no encontrado"
        )
    return document


@asynccontextmanager
async def _local_copy(document: Document) -> AsyncIterator[str]:
    """
    Copia temporal del archivo para las funciones de traducción, que leen
    desde disco. Se borra al salir (en Cloud Run el disco es memoria).
    """
    key = _object_key(document)
    storage = get_storage()
    if await storage.size(key) is None:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail="Archivo no encontrado en el almacenamiento"
        )
    suffix = os.path.splitext(document.filename or "")[1]
    fd, path = tempfile.mkstemp(prefix="cs-doc-", suffix=suffix)
    os.close(fd)
    try:
        await storage.download_to(key, path)
        yield path
    finally:
        with suppress(OSError):
            os.unlink(path)


# ---------------------------------------------------------------------------
# Listado
# ---------------------------------------------------------------------------

@router.get(
    "/",
    response_model=List[DocumentResponse],
    summary="Listar documentos",
    description="Obtiene documentos filtrados por épica o ticket"
)
async def list_documents(
    epic_id: Optional[UUID] = Query(None, alias="epicId"),
    ticket_id: Optional[UUID] = Query(None, alias="ticketId"),
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Sequence[Document]:
    query = select(Document).options(selectinload(Document.uploaded_by))
    if epic_id:
        query = query.where(Document.epic_id == epic_id)
    elif ticket_id:
        query = query.where(Document.ticket_id == ticket_id)
    query = query.order_by(Document.created_at.desc())
    result = await db.execute(query)
    return result.scalars().all()


# ---------------------------------------------------------------------------
# Subida
# ---------------------------------------------------------------------------

@router.post(
    "/upload-url",
    response_model=UploadUrlResponse,
    summary="Pedir URL de subida",
    description="Valida el archivo y devuelve una URL firmada para subirlo directo al almacenamiento"
)
async def request_upload_url(
    req: UploadUrlRequest,
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> UploadUrlResponse:
    if not req.epic_id and not req.ticket_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El documento debe asociarse a una épica o a un ticket",
        )
    if req.epic_id and not (await db.execute(select(Epic.id).where(Epic.id == req.epic_id))).first():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Épica con ID {req.epic_id} no encontrada"
        )
    if req.ticket_id and not (await db.execute(select(Ticket.id).where(Ticket.id == req.ticket_id))).first():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Ticket con ID {req.ticket_id} no encontrado"
        )

    name, _, ext = _clean_filename(req.filename)
    if ext and ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Extensión '{ext}' no permitida. Tipos soportados: código, documentación y datos."
        )
    if req.size > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="El archivo supera el límite de 25 MB"
        )

    content_type = (req.content_type or "").split(";")[0].strip().lower()
    if not _CONTENT_TYPE_RE.match(content_type):
        content_type = "application/octet-stream"

    key = f"pending/{uuid4()}"
    signed = await get_storage().upload_url(key, content_type, MAX_FILE_SIZE)

    settings = get_settings()
    token = jwt.encode(
        {
            "type": UPLOAD_TOKEN_TYPE,
            "uid": str(current_user.id),
            "key": key,
            "fn": name,
            "ct": content_type,
            "epic": str(req.epic_id) if req.epic_id else None,
            "ticket": str(req.ticket_id) if req.ticket_id else None,
            "dt": _resolve_doc_type(req.doc_type),
            "exp": datetime.now(timezone.utc) + UPLOAD_URL_TTL,
        },
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM,
    )

    return UploadUrlResponse(
        upload_token=token,
        url=signed.url,
        method="PUT",
        headers=signed.headers,
        expires_in=int(UPLOAD_URL_TTL.total_seconds()),
    )


@router.post(
    "/confirm",
    response_model=DocumentResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Confirmar subida",
    description="Verifica el archivo subido y crea el documento"
)
async def confirm_upload(
    req: ConfirmUploadRequest,
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Document:
    settings = get_settings()
    try:
        claims = jwt.decode(req.upload_token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except JWTError:
        claims = {}
    if (
        claims.get("type") != UPLOAD_TOKEN_TYPE
        or claims.get("uid") != str(current_user.id)
        or not str(claims.get("key", "")).startswith("pending/")
        or not KEY_RE.match(str(claims.get("key", "")))
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Subida inválida o expirada. Vuelve a intentarlo.",
        )

    storage = get_storage()
    pending_key = claims["key"]
    size = await storage.size(pending_key)
    if size is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El archivo no llegó al almacenamiento. Vuelve a intentarlo.",
        )
    if size > MAX_FILE_SIZE:
        await storage.delete(pending_key)
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="El archivo supera el límite de 25 MB"
        )

    epic_id = UUID(claims["epic"]) if claims.get("epic") else None
    ticket_id = UUID(claims["ticket"]) if claims.get("ticket") else None
    _, stem, ext = _clean_filename(claims["fn"])
    filename = await _dedupe_filename(db, stem, ext, epic_id, ticket_id)

    final_key = "documents/" + pending_key.split("/", 1)[1]
    await storage.move(pending_key, final_key)

    document = Document(
        epic_id=epic_id,
        ticket_id=ticket_id,
        filename=filename,
        file_path=final_key,
        file_size=size,
        mime_type=claims["ct"],
        doc_type=claims["dt"],
        uploaded_by_id=current_user.id,
    )
    db.add(document)
    try:
        await db.commit()
    except Exception:
        # Epic/ticket deleted meanwhile, or any DB failure: do not leave an
        # unreferenced object behind.
        await db.rollback()
        await storage.delete(final_key)
        raise
    await db.refresh(document)
    return document


# ---------------------------------------------------------------------------
# Descarga
# ---------------------------------------------------------------------------

@router.get(
    "/{doc_id}/download-url",
    response_model=DownloadUrlResponse,
    summary="Pedir URL de descarga",
    description="Devuelve una URL firmada de vida corta para descargar el archivo"
)
async def request_download_url(
    doc_id: UUID,
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> DownloadUrlResponse:
    document = await _get_document(db, doc_id)
    key = _object_key(document)
    url = await get_storage().download_url(key, document.filename, document.mime_type)
    return DownloadUrlResponse(url=url, filename=document.filename, expires_in=300)


# ---------------------------------------------------------------------------
# Almacenamiento local (solo STORAGE_BACKEND=local: desarrollo y tests)
# ---------------------------------------------------------------------------

def _local_storage() -> LocalStorage:
    storage = get_storage()
    if not isinstance(storage, LocalStorage):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not Found")
    return storage


@router.put("/local-storage/{token}", include_in_schema=False)
async def local_storage_put(token: str, request: Request) -> Response:
    storage = _local_storage()
    claims = LocalStorage.read_token(token, "storage-put")
    if not claims:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="URL inválida o expirada")

    path = storage.write_path(claims["key"])
    written = 0
    try:
        with open(path, "wb") as f:  # noqa: ASYNC230 — dev/test only
            async for chunk in request.stream():
                written += len(chunk)
                if written > int(claims["max"]):
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="El archivo supera el tamaño permitido",
                    )
                f.write(chunk)
    except HTTPException:
        path.unlink(missing_ok=True)
        raise
    return Response(status_code=status.HTTP_200_OK)


@router.get("/local-storage/{token}", include_in_schema=False)
async def local_storage_get(token: str) -> FileResponse:
    storage = _local_storage()
    claims = LocalStorage.read_token(token, "storage-get")
    if not claims:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="URL inválida o expirada")
    path = storage.read_path(claims["key"])
    if not path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Archivo no encontrado")
    return FileResponse(
        path=path,
        media_type=claims.get("ct") or "application/octet-stream",
        headers={"Content-Disposition": content_disposition(claims.get("fn") or "document")},
    )


# MIME types soportados para traducción.
# Incluye texto plano, formatos estructurados y binarios con extracción de texto.
TRANSLATABLE_MIME_TYPES = {
    # Texto plano / estructurado
    "text/plain",
    "text/markdown",
    "text/html",
    "text/xml",
    "text/yaml",
    "text/csv",
    "application/json",
    "application/xml",
    "application/yaml",
    # CSV variantes
    "application/csv",
    # PDF
    "application/pdf",
    # DOCX / DOC
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/msword",
}

# Extensiones que también se aceptan aunque el MIME no coincida exactamente
TRANSLATABLE_EXTENSIONS = {".pdf", ".docx", ".doc", ".csv", ".md", ".txt", ".rst",
                            ".json", ".yaml", ".yml", ".xml", ".html", ".toml", ".env"}


@router.post(
    "/{doc_id}/translate",
    response_model=TranslateResponse,
    summary="Traducir documento",
    description="Traduce el contenido de un documento de texto con Google Cloud Translation"
)
async def translate_document(
    doc_id: UUID,
    req: TranslateRequest,
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> TranslateResponse:
    document = await _get_document(db, doc_id)

    # Verificar que el tipo de archivo es traducible (por MIME o extensión)
    base_mime = document.mime_type.split(";")[0].strip().lower()
    ext = os.path.splitext(document.filename or "")[1].lower()
    if base_mime not in TRANSLATABLE_MIME_TYPES and ext not in TRANSLATABLE_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=(
                f"El tipo de archivo '{document.mime_type}' no es compatible con la traducción. "
                "Se admiten: texto plano, Markdown, JSON, HTML, XML, YAML, CSV, PDF y DOCX."
            ),
        )

    async with _local_copy(document) as path:
        content = extract_text_from_file(path, document.mime_type, document.filename or "")

    translated = await translate_long_text(content, "auto", req.target_language)

    return TranslateResponse(
        document_id=document.id,
        original_filename=document.filename,
        target_language=req.target_language,
        translated_text=translated,
    )


@router.post(
    "/{doc_id}/translate/download",
    summary="Descargar traducción",
    description="Traduce el archivo preservando su formato y lo devuelve como descarga"
)
async def translate_document_download(
    doc_id: UUID,
    req: TranslateRequest,
    current_user=Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Response:
    document = await _get_document(db, doc_id)

    base_mime = document.mime_type.split(";")[0].strip().lower()
    ext = os.path.splitext(document.filename or "")[1].lower()
    if base_mime not in TRANSLATABLE_MIME_TYPES and ext not in TRANSLATABLE_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=(
                f"El tipo de archivo '{document.mime_type}' no es compatible con la traducción. "
                "Se admiten: texto plano, Markdown, JSON, HTML, XML, YAML, CSV, PDF y DOCX."
            ),
        )

    async with _local_copy(document) as path:
        content_bytes, output_filename, media_type = await create_translated_file(
            path,
            document.mime_type,
            document.filename or "document",
            req.target_language,
        )

    return Response(
        content=content_bytes,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{output_filename}"'},
    )


@router.delete(
    "/{doc_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Eliminar documento",
    description="Elimina un documento y su archivo del almacenamiento"
)
async def delete_document(
    doc_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    document = await _get_document(db, doc_id)

    if document.uploaded_by_id != current_user.id and not is_admin_or_leader(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo quien subió el documento, ADMIN o TEAM_LEADER pueden eliminarlo",
        )

    await db.delete(document)
    await db.commit()

    # After the commit: if deleting the object fails, the row is already
    # gone and only an orphan object remains (harmless), never the reverse.
    if KEY_RE.match(document.file_path or ""):
        with suppress(Exception):
            await get_storage().delete(document.file_path)
