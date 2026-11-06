"""
Rate limiting sencillo basado en Redis (plan 3.5).

No se usa slowapi ni ninguna dependencia nueva: un contador de ventana fija
por clave (IP, o IP+email) es suficiente para lo que hace falta aquí —
frenar fuerza bruta contra /auth/login — y Redis ya está disponible en toda
la aplicación.

Antes: 25 intentos de login fallidos consecutivos, todos respondidos con 401,
ninguno bloqueado. Verificado en la auditoría inicial.
"""

from __future__ import annotations

import ipaddress
import logging

from fastapi import HTTPException, Request, status

from app.config import get_settings
from app.redis_client import get_redis

logger = logging.getLogger(__name__)

_PREFIX = "corestream:ratelimit:"


async def _hit(key: str, *, max_attempts: int, window_seconds: int) -> None:
    """
    Incrementa el contador de `key` y lanza 429 si supera max_attempts
    dentro de la ventana. INCR + EXPIRE es atómico a efectos prácticos aquí:
    el único caso límite (perder el EXPIRE por un fallo entre medias) deja el
    contador sin caducar hasta el próximo reinicio de Redis, lo que en el
    peor caso es "demasiado estricto", nunca "permite más de la cuenta".
    """
    redis = await get_redis()
    full_key = f"{_PREFIX}{key}"

    count = await redis.incr(full_key)
    if count == 1:
        await redis.expire(full_key, window_seconds)

    if count > max_attempts:
        ttl = await redis.ttl(full_key)
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Demasiados intentos. Intenta de nuevo más tarde.",
            headers={"Retry-After": str(max(ttl, 1))},
        )


def _valid_ip(value: str) -> str | None:
    try:
        return str(ipaddress.ip_address(value.strip()))
    except ValueError:
        return None


def _client_ip(request: Request, xff_position: int | None = None) -> str:
    """
    Real client IP for rate limiting.

    XFF_CLIENT_POSITION tells which X-Forwarded-For entry, counted from the
    right, was written by our own proxy (entries to its left are
    client-controlled and must never be trusted):
      0 -> no proxy: use the socket peer
      1 -> single proxy that appends the peer (nginx $proxy_add_x_forwarded_for)
      2 -> GCP external Application LB ("<client>, <lb-ip>")
    Uvicorn's --forwarded-allow-ips="*" picks the LEFTMOST entry, which is
    spoofable, so request.client is not used when a position is configured.
    """
    if xff_position is None:
        xff_position = get_settings().XFF_CLIENT_POSITION

    peer = request.client.host if request.client else "unknown"
    if xff_position <= 0:
        return peer

    raw = request.headers.get("x-forwarded-for", "")
    hops = [h.strip() for h in raw.split(",") if h.strip()]
    logger.debug("rate_limit xff=%r position=%d", raw, xff_position)

    if len(hops) >= xff_position:
        ip = _valid_ip(hops[-xff_position])
        if ip:
            return ip

    # Header missing, too short or malformed: the request did not come
    # through the expected proxy chain. Fall back to the peer so the limit
    # still applies, and leave a trace to detect misconfiguration.
    logger.warning(
        "rate_limit: unexpected X-Forwarded-For %r for position %d; using peer",
        raw[:200], xff_position,
    )
    return peer


async def rate_limit_login(request: Request, email: str | None = None) -> None:
    """
    Límite combinado por IP y por cuenta sobre /auth/login.

    Por IP: una IP no puede intentar más de 20 logins/5min contra ninguna
    cuenta (frena el barrido de credenciales contra muchos emails).
    Por cuenta: una cuenta concreta no puede recibir más de 8 intentos/5min
    sin importar desde cuántas IPs distintas (frena el ataque distribuido
    contra una sola cuenta).
    """
    ip = _client_ip(request)
    await _hit(f"login:ip:{ip}", max_attempts=20, window_seconds=300)
    if email:
        await _hit(f"login:email:{email.lower().strip()}", max_attempts=8, window_seconds=300)


async def rate_limit_password_reset_request(request: Request, email: str) -> None:
    """
    Same criteria as rate_limit_login: by IP (sweeping many accounts) and
    by account (don't flood one person's inbox at someone else's request).
    """
    ip = _client_ip(request)
    await _hit(f"pwreset:ip:{ip}", max_attempts=10, window_seconds=300)
    await _hit(f"pwreset:email:{email.lower().strip()}", max_attempts=3, window_seconds=300)
