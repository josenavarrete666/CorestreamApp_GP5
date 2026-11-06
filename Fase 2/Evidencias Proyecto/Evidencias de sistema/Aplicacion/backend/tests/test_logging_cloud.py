"""Structured logs in the format Cloud Logging expects."""

import json
import logging

import httpx
from fastapi import FastAPI
from fastapi.responses import JSONResponse

from app.logging_config import JSONFormatter
from app.middleware.request_id import (
    RequestIDMiddleware,
    TraceContext,
    get_request_id,
    parse_trace_headers,
)

TRACE = "4bf92f3577b34da6a3ce929d0e0e4736"


def _record(msg="hola", level=logging.INFO, exc_info=None) -> logging.LogRecord:
    return logging.LogRecord("corestream.test", level, __file__, 1, msg, None, exc_info)


# ---------------------------------------------------------------------------
# Trace headers
# ---------------------------------------------------------------------------

def test_traceparent_w3c():
    t = parse_trace_headers(f"00-{TRACE}-00f067aa0ba902b7-01", None)
    assert t == TraceContext(TRACE, "00f067aa0ba902b7", True)


def test_x_cloud_trace_context_convierte_span_a_hex():
    t = parse_trace_headers(None, f"{TRACE}/1;o=1")
    assert t == TraceContext(TRACE, "0000000000000001", True)


def test_cabeceras_invalidas_se_ignoran():
    assert parse_trace_headers("basura", "tampoco/valida") is None
    assert parse_trace_headers(f"00-{'0' * 32}-00f067aa0ba902b7-01", None) is None


# ---------------------------------------------------------------------------
# Formatter
# ---------------------------------------------------------------------------

def test_campos_que_reconoce_cloud_logging():
    out = json.loads(JSONFormatter().format(_record(level=logging.WARNING)))
    assert out["severity"] == "WARNING"
    assert out["message"] == "hola"
    assert out["time"].endswith("+00:00")
    assert "level" not in out
    assert "logging.googleapis.com/trace" not in out


def test_traceback_va_dentro_del_mensaje():
    try:
        raise ValueError("explotó")
    except ValueError:
        import sys
        rec = _record("fallo", logging.ERROR, sys.exc_info())
    out = json.loads(JSONFormatter().format(rec))
    assert out["message"].startswith("fallo\nTraceback")
    assert "ValueError: explotó" in out["message"]


# ---------------------------------------------------------------------------
# Middleware + formatter on a real ASGI app
# ---------------------------------------------------------------------------

def _app(captured: list[str]) -> FastAPI:
    app = FastAPI()
    app.add_middleware(RequestIDMiddleware)
    fmt = JSONFormatter(project_id="mi-proyecto")
    log = logging.getLogger("corestream.test.app")

    @app.get("/ok")
    async def ok():
        captured.append(fmt.format(_record("dentro")))
        return {"ok": True}

    @app.get("/boom")
    async def boom():
        raise RuntimeError("fallo inesperado")

    @app.exception_handler(Exception)
    async def handler(request, exc):
        log.error("no manejado", exc_info=exc)
        captured.append(fmt.format(_record("no manejado", logging.ERROR)))
        return JSONResponse(status_code=500, content={"request_id": get_request_id()})

    return app


async def test_log_enlazado_a_la_traza_de_la_peticion():
    captured: list[str] = []
    transport = httpx.ASGITransport(app=_app(captured))
    async with httpx.AsyncClient(transport=transport, base_url="http://t") as c:
        res = await c.get("/ok", headers={"X-Cloud-Trace-Context": f"{TRACE}/1;o=1"})
    out = json.loads(captured[0])
    assert out["logging.googleapis.com/trace"] == f"projects/mi-proyecto/traces/{TRACE}"
    assert out["logging.googleapis.com/spanId"] == "0000000000000001"
    assert out["request_id"] == res.headers["X-Request-ID"]


async def test_request_id_del_cliente_se_valida():
    captured: list[str] = []
    transport = httpx.ASGITransport(app=_app(captured))
    async with httpx.AsyncClient(transport=transport, base_url="http://t") as c:
        good = await c.get("/ok", headers={"X-Request-ID": "abc-123"})
        bad = await c.get("/ok", headers={"X-Request-ID": "x" * 500})
    assert good.headers["X-Request-ID"] == "abc-123"
    assert len(bad.headers["X-Request-ID"]) == 32


async def test_el_error_500_conserva_request_id_y_traza():
    captured: list[str] = []
    transport = httpx.ASGITransport(app=_app(captured), raise_app_exceptions=False)
    async with httpx.AsyncClient(transport=transport, base_url="http://t") as c:
        res = await c.get(
            "/boom",
            headers={"X-Request-ID": "req-500", "X-Cloud-Trace-Context": f"{TRACE}/7"},
        )
    assert res.status_code == 500
    assert res.json()["request_id"] == "req-500"
    out = json.loads(captured[0])
    assert out["request_id"] == "req-500"
    assert out["logging.googleapis.com/trace"].endswith(TRACE)
