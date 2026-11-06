"""
Servicio de traducción automática con Google Cloud Translation (API v3).

Migración a GCP (plan D15): reemplaza a Azure Translator. No usa claves: se
autentica con las credenciales de Google del entorno (Application Default
Credentials). En Cloud Run son las de la service account del servicio, que
necesita el rol roles/cloudtranslate.user y la API translate.googleapis.com
habilitada en el proyecto (ver docs/DEPLOYMENT.md). En desarrollo local:
`gcloud auth application-default login`.

Configuración:
  GCP_PROJECT_ID           — proyecto donde se factura la traducción
  TRANSLATION_LOCATION     — "global" (por defecto)
"""

import asyncio
import csv
import html as _html_lib
import io
import json
import logging
import os
import re
import threading
from typing import Any

import httpx
from fastapi import HTTPException, status

from app.config import get_settings

logger = logging.getLogger(__name__)

_TRANSLATE_SCOPE = "https://www.googleapis.com/auth/cloud-translation"
_TRANSLATE_ENDPOINT = "https://translation.googleapis.com/v3"

# Language codes the frontend sends (types/index.ts SUPPORTED_LANGUAGES) that
# Cloud Translation spells differently.
_LANGUAGE_ALIASES = {"zh": "zh-CN"}


def extract_text_from_file(file_path: str, mime_type: str, filename: str) -> str:
    """
    Extrae texto plano de un archivo según su tipo.

    Soporta: texto plano, Markdown, JSON, YAML, XML, HTML, CSV, PDF y DOCX.
    Retorna el contenido como string UTF-8 listo para enviar al traductor.
    """
    ext = os.path.splitext(filename)[1].lower()
    base_mime = mime_type.split(";")[0].strip().lower()

    # --- PDF ---
    if ext == ".pdf" or base_mime == "application/pdf":
        try:
            import PyPDF2
            with open(file_path, "rb") as f:
                reader = PyPDF2.PdfReader(f)
                pages = [page.extract_text() or "" for page in reader.pages]
            text = "\n\n".join(p for p in pages if p.strip())
            if not text.strip():
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="No se pudo extraer texto del PDF (puede ser un PDF escaneado o de solo imágenes).",
                )
            return text
        except ImportError:
            raise HTTPException(
                status_code=status.HTTP_501_NOT_IMPLEMENTED,
                detail="Soporte para PDF no disponible. Instale 'pypdf2'.",
            )

    # --- DOCX ---
    if ext in (".docx", ".doc") or base_mime in (
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/msword",
    ):
        try:
            import docx
            document = docx.Document(file_path)
            paragraphs = [p.text for p in document.paragraphs if p.text.strip()]
            text = "\n".join(paragraphs)
            if not text.strip():
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="No se pudo extraer texto del documento DOCX.",
                )
            return text
        except ImportError:
            raise HTTPException(
                status_code=status.HTTP_501_NOT_IMPLEMENTED,
                detail="Soporte para DOCX no disponible. Instale 'python-docx'.",
            )

    # --- CSV (convertir a texto tabular legible) ---
    if ext == ".csv" or base_mime in ("text/csv", "application/csv"):
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            raw = f.read()
        csv_reader = csv.reader(io.StringIO(raw))
        rows = ["\t".join(row) for row in csv_reader]
        return "\n".join(rows)

    # --- Texto plano / Markdown / JSON / YAML / XML / HTML / etc. ---
    with open(file_path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


# ---------------------------------------------------------------------------
# Core HTTP helper (usado por translate_text, _translate_batch y _translate_xml)
# ---------------------------------------------------------------------------

_credentials = None
_credentials_project: str | None = None
_credentials_lock = threading.Lock()


def _not_configured(reason: str) -> HTTPException:
    # Feature not configured: 503 with a clear message, not a 502 "server
    # broken" (plan fase 8).
    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail=f"La traducción de documentos no está configurada en este servidor ({reason}).",
    )


def _access_token_sync() -> tuple[str, str]:
    """Bearer token + project id from Application Default Credentials (blocking)."""
    global _credentials, _credentials_project
    import google.auth
    from google.auth.exceptions import DefaultCredentialsError, RefreshError
    from google.auth.transport.requests import Request

    with _credentials_lock:
        if _credentials is None:
            try:
                _credentials, _credentials_project = google.auth.default(scopes=[_TRANSLATE_SCOPE])
            except DefaultCredentialsError:
                raise _not_configured("sin credenciales de Google Cloud")
        if not _credentials.valid:
            try:
                _credentials.refresh(Request())
            except RefreshError:
                raise _not_configured("no se pudieron renovar las credenciales de Google Cloud")
        project = get_settings().GCP_PROJECT_ID or _credentials_project
        if not project:
            raise _not_configured("falta GCP_PROJECT_ID")
        return _credentials.token, project


async def _call_translator(
    text: str, source_lang: str, target_lang: str, fmt: str = "text"
) -> str:
    """
    Llamada a Cloud Translation v3 (translateText). Maneja errores de red,
    timeout y respuesta del servicio. fmt="html" preserva etiquetas.
    """
    token, project = await asyncio.to_thread(_access_token_sync)
    location = get_settings().TRANSLATION_LOCATION

    body: dict[str, Any] = {
        "contents": [text],
        "targetLanguageCode": _LANGUAGE_ALIASES.get(target_lang, target_lang),
        "mimeType": "text/html" if fmt == "html" else "text/plain",
    }
    if source_lang != "auto":
        body["sourceLanguageCode"] = _LANGUAGE_ALIASES.get(source_lang, source_lang)

    url = f"{_TRANSLATE_ENDPOINT}/projects/{project}/locations/{location}:translateText"
    # No x-goog-user-project header: it would require an extra Service Usage
    # permission; the service account already bills to its own project.
    headers = {"Authorization": f"Bearer {token}"}

    try:
        async with httpx.AsyncClient(timeout=90.0) as client:
            response = await client.post(url, headers=headers, json=body)
    except httpx.TimeoutException:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail="Tiempo de espera agotado al contactar el servicio de traducción",
        )
    except httpx.RequestError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="El servicio de traducción no está disponible.",
        )

    if not response.is_success:
        # Full Google error goes to the log; the user gets a short message.
        logger.error(
            "Cloud Translation respondió %s: %s", response.status_code, response.text[:1000]
        )
    if response.status_code == 400:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El servicio de traducción rechazó la solicitud (¿idioma no soportado?).",
        )
    if response.status_code in (401, 403):
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Sin permiso para usar Cloud Translation: revisar que la API esté "
            "habilitada y que la cuenta de servicio tenga roles/cloudtranslate.user.",
        )
    if response.status_code == 429:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Límite de uso del servicio de traducción alcanzado. Intenta en un momento.",
        )
    if not response.is_success:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Error del servicio de traducción ({response.status_code}).",
        )

    try:
        return response.json()["translations"][0]["translatedText"]
    except (KeyError, IndexError, ValueError):
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="El servicio de traducción no devolvió texto traducido",
        )


# ---------------------------------------------------------------------------
# API pública de traducción de texto
# ---------------------------------------------------------------------------

async def translate_text(text: str, source_lang: str, target_lang: str) -> str:
    """
    Traduce un bloque de texto con Cloud Translation.
    Para textos largos (>4000 chars) usar translate_long_text.
    """
    if not text or not text.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El texto a traducir no puede estar vacío",
        )
    return await _call_translator(text, source_lang, target_lang)


async def translate_long_text(text: str, source_lang: str, target_lang: str) -> str:
    """
    Traduce texto de cualquier longitud dividiéndolo en fragmentos de ≤4000 chars.
    Respeta los saltos de línea como fronteras naturales para no cortar frases a la mitad.
    """
    CHUNK_SIZE = 4000

    if len(text) <= CHUNK_SIZE:
        return await translate_text(text, source_lang, target_lang)

    chunks: list[str] = []
    current = ""

    for line in text.splitlines(keepends=True):
        if len(current) + len(line) <= CHUNK_SIZE:
            current += line
        else:
            if current:
                chunks.append(current)
                current = ""
            # Línea individual que supera el límite: partir por caracteres
            while len(line) > CHUNK_SIZE:
                chunks.append(line[:CHUNK_SIZE])
                line = line[CHUNK_SIZE:]
            current = line

    if current:
        chunks.append(current)

    parts: list[str] = []
    for chunk in chunks:
        if chunk.strip():
            parts.append(await translate_text(chunk, source_lang, target_lang))
    return "".join(parts)


# ---------------------------------------------------------------------------
# Handlers de formato para create_translated_file
# ---------------------------------------------------------------------------

def _split_pdf_paragraphs(text: str) -> list[str]:
    """
    Une los saltos de línea físicos del PDF en párrafos lógicos.
    Los dobles marcan límite real de párrafo; los simples son line-wrap físico.
    """
    blocks = re.split(r'\n{2,}', text)
    result: list[str] = []
    for block in blocks:
        joined = ' '.join(ln.strip() for ln in block.split('\n') if ln.strip())
        if joined:
            result.append(joined)
    return result


async def _translate_batch(texts: list[str], target_lang: str) -> list[str]:
    """
    Traduce una lista de textos agrupándolos en bloques de ~3000 chars por request.

    Usa etiquetas <p> como separadores (preservadas en modo HTML por el traductor),
    convirtiendo N requests individuales en ceil(total_chars / 3000) requests.
    Fallback individual por ítem si el batch parse no produce resultados válidos.
    """
    CHUNK_CHARS = 3000
    results = list(texts)  # originales como fallback seguro

    # Agrupar índices de textos no vacíos en batches
    batches: list[list[tuple[int, str]]] = []
    current: list[tuple[int, str]] = []
    current_len = 0

    for i, text in enumerate(texts):
        if not text.strip():
            continue
        entry_len = len(text) + 7  # overhead de <p>…</p>
        if current and current_len + entry_len > CHUNK_CHARS:
            batches.append(current)
            current = []
            current_len = 0
        current.append((i, text))
        current_len += entry_len
    if current:
        batches.append(current)

    for batch in batches:
        html_content = ''.join(f'<p>{_html_lib.escape(t)}</p>' for _, t in batch)
        batch_applied = False
        try:
            translated_html = await _call_translator(
                html_content, "auto", target_lang, fmt="html"
            )
            # <p[^>]*> captura <p>, <p dir="ltr">, <p class="…">, etc.
            parts = re.findall(r'<p[^>]*>(.*?)</p>', translated_html, re.DOTALL | re.IGNORECASE)
            if len(parts) == len(batch):
                parsed = [
                    _html_lib.unescape(re.sub(r'<[^>]+>', '', p)).strip()
                    for p in parts
                ]
                # Seguridad: no sobreescribir texto original con resultado vacío.
                # Si algún ítem no vacío produce resultado vacío, el batch no es fiable.
                all_valid = all(
                    parsed[k]  # resultado no vacío
                    or not batch[k][1].strip()  # o el original también era vacío
                    for k in range(len(batch))
                )
                if all_valid:
                    for (orig_idx, _), translated_text in zip(batch, parsed, strict=True):
                        results[orig_idx] = translated_text
                    batch_applied = True
        except Exception:
            pass  # continuar al fallback individual

        if not batch_applied:
            # Fallback: un request por ítem — garantiza que nunca queda vacío
            for orig_idx, text in batch:
                if text.strip():
                    try:
                        results[orig_idx] = await translate_text(
                            text, "auto", target_lang
                        )
                    except Exception:
                        pass  # conservar texto original ante fallo de servicio

    return results


async def _translate_to_docx(
    file_path: str, mime_type: str, filename: str, target_lang: str
) -> bytes:
    """
    Traduce DOCX (párrafos + tablas) o PDF (párrafos lógicos).

    Estrategia de dos fases:
      1. Escanear todo el documento y recolectar textos a traducir.
      2. Batch-traducir todos los párrafos juntos y todas las celdas juntas
         (minimiza requests HTTP al traductor).
      3. Escribir el DOCX de salida en el orden original.
    """
    try:
        import docx
        from docx.oxml.ns import qn
        from docx.table import Table as DocxTable
        from docx.text.paragraph import Paragraph as DocxParagraph
    except ImportError:
        raise HTTPException(
            status_code=status.HTTP_501_NOT_IMPLEMENTED,
            detail="Soporte para DOCX no disponible. Instale 'python-docx'.",
        )

    ext = os.path.splitext(filename)[1].lower()
    base_mime = mime_type.split(";")[0].strip().lower()
    output = docx.Document()

    # ------------------------------------------------------------------ PDF --
    if ext == ".pdf" or base_mime == "application/pdf":
        try:
            import PyPDF2
        except ImportError:
            raise HTTPException(
                status_code=status.HTTP_501_NOT_IMPLEMENTED,
                detail="Soporte para PDF no disponible. Instale 'pypdf2'.",
            )
        all_paras: list[str] = []
        with open(file_path, "rb") as f:  # noqa: ASYNC230 — deuda conocida: bloquea el event loop (plan fase 7.2)
            reader = PyPDF2.PdfReader(f)
            for page in reader.pages:
                all_paras.extend(_split_pdf_paragraphs(page.extract_text() or ""))

        translated_paras = await _translate_batch(all_paras, target_lang)
        for text in translated_paras:
            if text.strip():
                output.add_paragraph(text)

    # ----------------------------------------------------------------- DOCX --
    else:
        source = docx.Document(file_path)

        # Fase 1: escanear cuerpo del documento
        # Cada elemento es un dict con 'type': 'para' | 'table'
        body_elements: list[dict] = []

        for child in source.element.body:
            tag = child.tag
            if tag == qn('w:p'):
                para = DocxParagraph(child, source)
                style = 'Normal'
                try:
                    para_style = para.style
                    if para_style is not None:
                        style = para_style.name
                except Exception:
                    pass
                body_elements.append({
                    'type': 'para',
                    'text': para.text.strip(),
                    'style': style,
                })
            elif tag == qn('w:tbl'):
                tbl = DocxTable(child, source)
                if not tbl.rows:
                    continue
                n_rows = len(tbl.rows)
                n_cols = len(tbl.rows[0].cells)
                if n_cols == 0:
                    continue
                seen_ids: set[int] = set()
                cells: list[dict] = []
                for i, row in enumerate(tbl.rows):
                    for j, cell in enumerate(row.cells):
                        if j >= n_cols:
                            continue
                        cid = id(cell._tc)
                        if cid in seen_ids:
                            continue
                        seen_ids.add(cid)
                        cells.append({'row': i, 'col': j, 'text': cell.text.strip()})
                body_elements.append({
                    'type': 'table',
                    'n_rows': n_rows,
                    'n_cols': n_cols,
                    'cells': cells,
                })

        # Fase 2: batch-traducir párrafos (todos juntos)
        para_texts = [
            e['text'] for e in body_elements
            if e['type'] == 'para' and e['text']
        ]
        translated_paras_list = await _translate_batch(para_texts, target_lang)
        para_iter = iter(translated_paras_list)

        # Fase 2: batch-traducir celdas de todas las tablas juntas
        all_cell_refs: list[dict] = []
        for e in body_elements:
            if e['type'] == 'table':
                all_cell_refs.extend(e['cells'])
        all_cell_texts = [c['text'] for c in all_cell_refs]
        translated_cell_texts = await _translate_batch(all_cell_texts, target_lang)
        for cell_ref, translated in zip(all_cell_refs, translated_cell_texts, strict=True):
            cell_ref['_translated'] = translated

        # Fase 3: escribir el DOCX de salida en orden
        for e in body_elements:
            if e['type'] == 'para':
                if e['text']:
                    translated = next(para_iter, e['text'])
                    try:
                        output.add_paragraph(translated, style=e['style'])
                    except KeyError:
                        output.add_paragraph(translated)
                else:
                    output.add_paragraph()  # párrafo vacío como espaciador
            elif e['type'] == 'table':
                new_tbl = output.add_table(rows=e['n_rows'], cols=e['n_cols'])
                for c in e['cells']:
                    try:
                        # `or` garantiza que un _translated vacío no sobreescriba el original
                        new_tbl.cell(c['row'], c['col']).text = (
                            c.get('_translated') or c['text']
                        )
                    except Exception:
                        pass

    buf = io.BytesIO()
    output.save(buf)
    buf.seek(0)
    return buf.getvalue()


async def _translate_csv(file_path: str, target_lang: str) -> bytes:
    """
    Traduce celda a celda un archivo CSV.
    Omite celdas vacías y numéricas para no alterar datos estructurados.
    Retorna bytes UTF-8-BOM (compatible con Excel).
    """
    with open(file_path, "r", encoding="utf-8", errors="replace") as f:  # noqa: ASYNC230 — deuda conocida: bloquea el event loop (plan fase 7.2)
        raw = f.read()

    rows = list(csv.reader(io.StringIO(raw)))
    translated_rows: list[list[str]] = []

    for row in rows:
        translated_row: list[str] = []
        for cell in row:
            stripped = cell.strip()
            try:
                float(stripped)
                is_numeric = True
            except ValueError:
                is_numeric = False

            if not stripped or is_numeric:
                translated_row.append(cell)
            else:
                translated_row.append(await translate_text(stripped, "auto", target_lang))
        translated_rows.append(translated_row)

    out = io.StringIO()
    csv.writer(out).writerows(translated_rows)
    return out.getvalue().encode("utf-8-sig")


async def _translate_json_values(data: Any, target_lang: str) -> Any:
    """Recorre recursivamente la estructura JSON y traduce solo los valores string."""
    if isinstance(data, str):
        return await translate_text(data, "auto", target_lang) if data.strip() else data
    if isinstance(data, dict):
        return {k: await _translate_json_values(v, target_lang) for k, v in data.items()}
    if isinstance(data, list):
        return [await _translate_json_values(item, target_lang) for item in data]
    return data  # int, float, bool, None → sin cambios


async def _translate_json_file(file_path: str, target_lang: str) -> bytes:
    """
    Traduce solo los valores string de un JSON, dejando intactas las claves y estructura.
    """
    with open(file_path, "r", encoding="utf-8", errors="replace") as f:  # noqa: ASYNC230 — deuda conocida: bloquea el event loop (plan fase 7.2)
        data = json.loads(f.read())
    translated = await _translate_json_values(data, target_lang)
    return json.dumps(translated, indent=2, ensure_ascii=False).encode("utf-8")


async def _translate_xml(file_path: str, target_lang: str) -> bytes:
    """
    Traduce XML usando el modo HTML del traductor, que preserva los tags.
    """
    with open(file_path, "r", encoding="utf-8", errors="replace") as f:  # noqa: ASYNC230 — deuda conocida: bloquea el event loop (plan fase 7.2)
        content = f.read()
    if not content.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El archivo XML está vacío",
        )
    translated = await _call_translator(content, "auto", target_lang, fmt="html")
    return translated.encode("utf-8")


async def _translate_plaintext(file_path: str, target_lang: str) -> bytes:
    """
    Traduce un archivo de texto plano con chunking para documentos largos.
    Usado para: md, txt, rst, sql, yaml, yml, toml, env, y todos los archivos de código.
    """
    with open(file_path, "r", encoding="utf-8", errors="replace") as f:  # noqa: ASYNC230 — deuda conocida: bloquea el event loop (plan fase 7.2)
        content = f.read()
    translated = await translate_long_text(content, "auto", target_lang)
    return translated.encode("utf-8")


# ---------------------------------------------------------------------------
# Dispatcher principal
# ---------------------------------------------------------------------------

_DOCX_MIME = frozenset({
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/msword",
})
_DOCX_OUTPUT_MIME = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"


async def create_translated_file(
    file_path: str, mime_type: str, filename: str, target_lang: str
) -> tuple[bytes, str, str]:
    """
    Traduce un archivo preservando su formato cuando es posible.

    Retorna (content_bytes, output_filename, media_type).
    El output_filename sigue el patrón: {stem}_{target_lang}{ext}
    """
    stem, ext = os.path.splitext(filename)
    ext = ext.lower()
    base_mime = mime_type.split(";")[0].strip().lower()

    # DOCX / DOC
    if ext in (".docx", ".doc") or base_mime in _DOCX_MIME:
        content = await _translate_to_docx(file_path, mime_type, filename, target_lang)
        return content, f"{stem}_{target_lang}.docx", _DOCX_OUTPUT_MIME

    # PDF → DOCX (PDF no puede recrearse sin dependencias adicionales)
    if ext == ".pdf" or base_mime == "application/pdf":
        content = await _translate_to_docx(file_path, mime_type, filename, target_lang)
        return content, f"{stem}_{target_lang}.docx", _DOCX_OUTPUT_MIME

    # CSV
    if ext == ".csv" or base_mime in ("text/csv", "application/csv"):
        content = await _translate_csv(file_path, target_lang)
        return content, f"{stem}_{target_lang}.csv", "text/csv"

    # JSON
    if ext == ".json" or base_mime == "application/json":
        content = await _translate_json_file(file_path, target_lang)
        return content, f"{stem}_{target_lang}.json", "application/json"

    # XML
    if ext == ".xml" or base_mime in ("text/xml", "application/xml"):
        content = await _translate_xml(file_path, target_lang)
        return content, f"{stem}_{target_lang}.xml", "application/xml"

    # Todo lo demás: md, txt, rst, code files, yaml, sql, toml, env, etc.
    content = await _translate_plaintext(file_path, target_lang)
    out_ext = ext if ext else ".txt"
    return content, f"{stem}_{target_lang}{out_ext}", "text/plain"
