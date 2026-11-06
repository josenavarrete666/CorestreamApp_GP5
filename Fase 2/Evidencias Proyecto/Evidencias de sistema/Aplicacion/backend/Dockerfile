# =====================================================================
# DOCKERFILE PARA BACKEND (FASTAPI) — imagen de producción
# =====================================================================
# Un solo servidor ASGI (uvicorn, 1 worker), sin --reload, sin
# bind mount del código (se copia a la imagen), y ejecutando como usuario
# sin privilegios.
# =====================================================================

FROM python:3.11-slim

WORKDIR /app

# PYTHONUNBUFFERED: los logs salen en tiempo real, no al cerrar el proceso.
# PYTHONDONTWRITEBYTECODE: no escribir .pyc, innecesario en un contenedor
# que se reconstruye desde la imagen en cada despliegue.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# gcc/python3-dev: hacen falta para compilar dependencias con extensiones C
# (p. ej. bcrypt) en la instalación de pip de más abajo.
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends gcc python3-dev && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt requirements-dev.txt ./
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# INSTALL_DEV_DEPS: pytest/ruff/mypy no van en la imagen de producción, pero
# el mismo Dockerfile sirve de imagen de desarrollo (docker-compose.dev.yml
# pasa este build arg en true) para poder correr la suite de integración y
# el lint dentro del contenedor, contra Postgres/Redis reales.
ARG INSTALL_DEV_DEPS=false
RUN if [ "$INSTALL_DEV_DEPS" = "true" ]; then pip install --no-cache-dir -r requirements-dev.txt; fi

COPY . .

# Usuario sin privilegios: si un endpoint tiene una vulnerabilidad de
# escritura de archivos (path traversal, etc.), no corre como root.
#
# Los directorios de storage se crean y se chown-ean AQUÍ, antes del
# volumen: cuando docker-compose monta un volumen nombrado sobre una ruta
# que ya existe en la imagen, copia el contenido Y los permisos de esa ruta
# al volumen la primera vez — si no existieran ya con dueño "app" en la
# imagen, el volumen se crearía con dueño root y el proceso (corriendo como
# "app") no podría escribir en él.
RUN useradd --create-home --shell /usr/sbin/nologin app && \
    mkdir -p /app/storage/documents /app/storage/uploads && \
    chown -R app:app /app
USER app

EXPOSE 8080

# Cloud Run injects PORT (8080 by default).
# One uvicorn worker per container: Cloud Run scales by adding instances,
# and DB connections stay at DB_POOL_SIZE + DB_MAX_OVERFLOW per instance.
# FORWARDED_ALLOW_IPS="*": only Google's front end can reach the service
# (ingress restricted to the load balancer), and trusting it is needed for
# X-Forwarded-Proto=https (correct scheme on redirects). The client IP for
# rate limiting is resolved separately via XFF_CLIENT_POSITION.
# --no-access-log: Cloud Run already logs every request (status, latency,
# trace); uvicorn's own access line would only duplicate it.
# --timeout-graceful-shutdown: Cloud Run allows 10 s after SIGTERM; open
# WebSockets would otherwise keep uvicorn waiting until it gets killed.
# Migrations do NOT run here: they run once per deploy as the Cloud Run Job
# "corestream-migrate" (same image, command: alembic upgrade head).
ENV PORT=8080 \
    UVICORN_WORKERS=1 \
    FORWARDED_ALLOW_IPS=*
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --workers ${UVICORN_WORKERS} --forwarded-allow-ips=${FORWARDED_ALLOW_IPS} --timeout-graceful-shutdown 8 --no-access-log"]
