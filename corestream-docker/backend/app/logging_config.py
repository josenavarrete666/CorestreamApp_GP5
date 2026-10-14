"""
Logging estructurado para CoreStream (plan fase 8).

Antes: print() repartido por todo app/, y el manejador global de
excepciones (main.py) registraba con logging.error(...) sin exc_info — los
500 no dejaban traza. Los tres bugs de MissingGreenlet de la fase 2 solo
salieron a la luz porque uvicorn los imprime por su cuenta, no porque
nuestro propio logging los hubiera capturado.

Este módulo configura el logger raíz una sola vez, en el arranque de la
aplicación (main.py lifespan), con salida JSON (una línea por evento) en el
formato que Cloud Logging entiende sin configuración extra:
  - "severity" y "time" → nivel y hora del log en la consola de GCP.
  - "logging.googleapis.com/trace" → agrupa los logs de una misma petición
    (requiere GCP_PROJECT_ID).
  - El traceback va dentro de "message" → Error Reporting lo detecta solo.
Incluye además el request_id de middleware.request_id cuando existe.
"""

from __future__ import annotations

import json
import logging
import sys
from datetime import datetime, timezone

from app.middleware.request_id import get_request_id, get_trace


class JSONFormatter(logging.Formatter):
    def __init__(self, project_id: str = "") -> None:
        super().__init__()
        self.project_id = project_id

    def format(self, record: logging.LogRecord) -> str:
        message = record.getMessage()
        if record.exc_info:
            message = f"{message}\n{self.formatException(record.exc_info)}"

        payload: dict[str, object] = {
            "time": datetime.fromtimestamp(record.created, timezone.utc).isoformat(),
            "severity": record.levelname,
            "message": message,
            "logger": record.name,
        }

        request_id = get_request_id()
        if request_id:
            payload["request_id"] = request_id

        trace = get_trace()
        if trace and self.project_id:
            payload["logging.googleapis.com/trace"] = (
                f"projects/{self.project_id}/traces/{trace.trace_id}"
            )
            if trace.span_id:
                payload["logging.googleapis.com/spanId"] = trace.span_id
            payload["logging.googleapis.com/trace_sampled"] = trace.sampled

        return json.dumps(payload, ensure_ascii=False, default=str)


def configure_logging(level: str = "info", project_id: str = "") -> None:
    """Reemplaza los handlers del logger raíz. Llamar una sola vez, al arrancar."""
    root = logging.getLogger()
    root.setLevel(level.upper())

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter(project_id))

    root.handlers.clear()
    root.addHandler(handler)

    # uvicorn.access ya imprime una línea por request en su propio formato;
    # dejarlo pasar por nuestro handler JSON en vez de duplicar salida.
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        uv_logger = logging.getLogger(name)
        if name == "uvicorn.access" and not uv_logger.handlers and not uv_logger.propagate:
            # Disabled with --no-access-log (Cloud Run already logs every
            # request with status, latency and trace): keep it off.
            continue
        uv_logger.handlers.clear()
        uv_logger.propagate = True
