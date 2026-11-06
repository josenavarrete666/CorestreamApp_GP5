"""
Middleware de correlación de peticiones (plan fase 8).

Asigna un request_id por petición, lo propaga a través de un contextvar
(para que app/logging_config.py lo incluya en cada línea de log emitida
durante esa petición, sin tener que pasarlo explícitamente por cada
función) y lo devuelve en la cabecera X-Request-ID de la respuesta.

También captura el contexto de traza que pone Google Cloud (traceparent o
X-Cloud-Trace-Context), para que Cloud Logging agrupe todos los logs de una
petición bajo la misma traza.
"""

from __future__ import annotations

import re
import uuid
from contextvars import ContextVar
from typing import NamedTuple

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response


class TraceContext(NamedTuple):
    trace_id: str
    span_id: str | None
    sampled: bool


_request_id_ctx: ContextVar[str | None] = ContextVar("request_id", default=None)
_trace_ctx: ContextVar[TraceContext | None] = ContextVar("trace", default=None)

# Client-supplied X-Request-ID is only reused if it looks like an id;
# anything else (huge, multi-line, odd characters) gets a fresh one.
_REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
# W3C: 00-<32 hex trace>-<16 hex span>-<2 hex flags>
_TRACEPARENT_RE = re.compile(r"^[0-9a-f]{2}-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})$")
# Google legacy: <32 hex trace>/<decimal span>;o=<0|1>
_CLOUD_TRACE_RE = re.compile(r"^([0-9a-f]{32})(?:/(\d{1,20}))?(?:;o=([01]))?$")


def get_request_id() -> str | None:
    return _request_id_ctx.get()


def get_trace() -> TraceContext | None:
    return _trace_ctx.get()


def parse_trace_headers(traceparent: str | None, cloud_trace: str | None) -> TraceContext | None:
    if traceparent:
        m = _TRACEPARENT_RE.match(traceparent.strip().lower())
        if m and m.group(1) != "0" * 32:
            return TraceContext(m.group(1), m.group(2), int(m.group(3), 16) & 1 == 1)
    if cloud_trace:
        m = _CLOUD_TRACE_RE.match(cloud_trace.strip().lower())
        if m:
            span = m.group(2)
            span_hex = format(int(span), "016x") if span and int(span) < 2**64 else None
            return TraceContext(m.group(1), span_hex, m.group(3) == "1")
    return None


class RequestIDMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        incoming = request.headers.get("X-Request-ID", "")
        request_id = incoming if _REQUEST_ID_RE.match(incoming) else uuid.uuid4().hex

        # Not reset on purpose: each request runs in its own asyncio task, so
        # the values cannot leak to other requests, and keeping them lets the
        # global 500 handler (which runs outside this middleware) log them.
        _request_id_ctx.set(request_id)
        _trace_ctx.set(
            parse_trace_headers(
                request.headers.get("traceparent"),
                request.headers.get("X-Cloud-Trace-Context"),
            )
        )

        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response
