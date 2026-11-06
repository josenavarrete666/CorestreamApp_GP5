"""
Migración única de los archivos de documentos desde el disco de la VM de
Azure al bucket de Cloud Storage (migración a GCP, plan D10, paso 7).

Antes, documents.file_path guardaba una ruta de disco
("/app/storage/documents/<timestamp>_<nombre>"). Ahora guarda la clave del
objeto en el bucket ("documents/<uuid>"). Este script, para cada documento
que todavía tenga una ruta de disco:
  1. busca el archivo por su nombre en --source-dir,
  2. lo sube al bucket como documents/<uuid nuevo>,
  3. actualiza file_path (y file_size con el tamaño real).

Es idempotente: los documentos ya migrados se saltan, así que se puede
volver a correr si se corta a la mitad.

Uso (desde backend/, con la base de GCP y el bucket configurados):
    STORAGE_BACKEND=gcs GCS_BUCKET=corestream-file DATABASE_URL=... \\
        python -m app.scripts.migrate_documents_to_gcs --source-dir ./azure-documents --dry-run

--source-dir es una copia local de /app/storage/documents de la VM de
Azure (volumen storage-data del contenedor backend). Las credenciales de
GCP salen de `gcloud auth application-default login`.
"""

from __future__ import annotations

import argparse
import asyncio
import os
from pathlib import Path
from uuid import uuid4

from sqlalchemy import select

from app.database import get_session_maker
from app.models import Document
from app.services.storage import KEY_RE, Storage, get_storage


async def migrate(source_dir: Path, storage: Storage, dry_run: bool = False) -> dict[str, int]:
    stats = {"migrados": 0, "ya_migrados": 0, "sin_archivo": 0}

    async with get_session_maker()() as db:
        documents = (await db.execute(select(Document).order_by(Document.created_at))).scalars().all()

        for doc in documents:
            if KEY_RE.match(doc.file_path or ""):
                stats["ya_migrados"] += 1
                continue

            local = source_dir / os.path.basename(doc.file_path or "")
            if not local.is_file():
                stats["sin_archivo"] += 1
                print(f"  FALTA  {doc.id}  {doc.filename!r}  (se esperaba {local.name})")
                continue

            key = f"documents/{uuid4()}"
            print(f"  {'(dry) ' if dry_run else ''}SUBE   {doc.id}  {doc.filename!r} -> {key}")
            if not dry_run:
                await storage.upload_from(str(local), key, doc.mime_type or "application/octet-stream")
                doc.file_path = key
                doc.file_size = local.stat().st_size
                # One commit per document: a cut halfway leaves consistent rows.
                await db.commit()
            stats["migrados"] += 1

    return stats


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--dry-run", action="store_true", help="Solo muestra qué haría")
    args = parser.parse_args()

    if not args.source_dir.is_dir():
        parser.error(f"No existe el directorio {args.source_dir}")

    stats = asyncio.run(migrate(args.source_dir, get_storage(), args.dry_run))
    print(
        f"\nMigrados: {stats['migrados']} · ya estaban: {stats['ya_migrados']} · "
        f"sin archivo en origen: {stats['sin_archivo']}"
    )


if __name__ == "__main__":
    main()
