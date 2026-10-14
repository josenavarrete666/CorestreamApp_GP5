# Archivo de configuración centralizado para la aplicación FastAPI
# Utiliza pydantic-settings para cargar variables desde .env y valores por defecto

from functools import lru_cache
from typing import Literal, Union

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """
    Clase de configuración que carga y valida variables de entorno.
    Proporciona valores por defecto seguros y permite sobrescribir desde .env.
    
    Atributos de base de datos:
        DATABASE_URL: URL de conexión a PostgreSQL con soporte async (asyncpg)
        
    Atributos de caché:
        REDIS_URL: URL de conexión al servidor Redis para caché y pubsub
        
    Atributos de autenticación:
        SECRET_KEY: Clave secreta para firmar tokens JWT (generada aleatoriamente si no se proporciona)
        ALGORITHM: Algoritmo criptográfico para tokens JWT (HS256)
        ACCESS_TOKEN_EXPIRE_MINUTES: Tiempo de expiración del token de acceso en minutos
        REFRESH_TOKEN_EXPIRE_DAYS: Tiempo de expiración del token de refresco en días
        
    Atributos de CORS:
        CORS_ORIGINS: Lista de orígenes permitidos para solicitudes CORS desde el frontend
        
    Atributos de la aplicación:
        APP_NAME: Nombre de la aplicación para documentación y metadatos
        DEBUG: Modo debug para desarrollo (desactivar en producción)
        
    Atributos de configuración de Pydantic:
        env_file: Ruta del archivo .env para cargar variables de entorno
    """
    
    # Configuración de Base de Datos
    # URL para conectarse a PostgreSQL con soporte para operaciones asincrónicas
    # Railway genera postgresql:// — el validator lo convierte a postgresql+asyncpg://
    DATABASE_URL: str = "postgresql+asyncpg://corestream:corestream@localhost:5432/corestream"

    @field_validator("DATABASE_URL", mode="before")
    @classmethod
    def fix_database_url(cls, v: str) -> str:
        if isinstance(v, str) and v.startswith("postgresql://"):
            return v.replace("postgresql://", "postgresql+asyncpg://", 1)
        return v

    # Opciones del pool de conexiones (solo aplican a PostgreSQL).
    # Per instance: max connections = DB_POOL_SIZE + DB_MAX_OVERFLOW.
    # Total = that x Cloud Run max-instances; keep it under Postgres
    # max_connections (see plan D7).
    DB_POOL_SIZE: int = 5
    DB_MAX_OVERFLOW: int = 5

    # Recicla conexiones más viejas que este umbral (segundos). Evita que un
    # proxy o el propio PostgreSQL cierre por su cuenta una conexión que el
    # pool sigue considerando válida.
    DB_POOL_RECYCLE: int = 1800

    # Volcado de cada sentencia SQL al log.
    # Deliberadamente independiente de DEBUG: antes era echo=DEBUG, y eso hacía
    # que cualquier entorno con DEBUG=True escribiera todas las consultas al
    # log por duplicado, llenando el disco y filtrando datos de negocio.
    SQL_ECHO: bool = False

    # Configuración de Redis
    # URL para conectarse al servidor Redis para caché y sistema de notificaciones
    REDIS_URL: str = "redis://localhost:6379/0"
    
    # Configuración de Autenticación y Seguridad
    # Clave secreta para firmar y verificar tokens JWT
    # En producción debe ser sobreescrita desde el archivo .env
    SECRET_KEY: str = "insecure-default-key-change-in-prod"
    
    # Algoritmo criptográfico utilizado para firmar tokens JWT
    # HS256 (HMAC SHA-256) es el estándar recomendado
    ALGORITHM: str = "HS256"
    
    # Tiempo de expiración del token de acceso en minutos (corta duración para seguridad)
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    
    # Tiempo de expiración del token de refresco en días (más largo para facilitar re-autenticación)
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    
    # Configuración de CORS
    # Acepta lista CSV, JSON array, o "*" para todos los orígenes.
    # En Railway: ALLOWED_ORIGINS=https://dominio-produccion.com,http://localhost:5173
    ALLOWED_ORIGINS: Union[list[str], str] = ["http://localhost:5173"]

    @field_validator("ALLOWED_ORIGINS", mode="before")
    @classmethod
    def parse_cors_origins(cls, v: Union[str, list]) -> list[str]:
        if isinstance(v, list):
            return v
        # Soporta "*", CSV, o JSON array como string
        stripped = v.strip()
        if stripped.startswith("["):
            import json
            return json.loads(stripped)
        return [origin.strip() for origin in stripped.split(",") if origin.strip()]

    # Entorno de ejecución
    ENVIRONMENT: str = "development"

    # Configuración de la Aplicación
    # Nombre de la aplicación utilizado en documentación OpenAPI y metadatos
    APP_NAME: str = "CoreStream API"

    # Modo debug - activa información detallada de errores y recarga automática
    # IMPORTANTE: Desactivar en producción por razones de seguridad
    DEBUG: bool = True

    # Nivel de log para la aplicación
    LOG_LEVEL: str = "info"

    # WebSocket idle backstop (seconds without user activity reported by the
    # client). The frontend already closes after 15 min; see routers/websocket.py.
    WS_IDLE_TIMEOUT_SECONDS: int = Field(default=1200, ge=60)

    # GCP project id. When set, logs carry logging.googleapis.com/trace so
    # Cloud Logging groups every log line of a request. Empty = no trace link.
    GCP_PROJECT_ID: str = ""

    # X-Forwarded-For entry (from the right) holding the real client IP, as
    # written by our own proxy. 0 = no proxy. See middleware/rate_limit.py.
    XFF_CLIENT_POSITION: int = Field(default=0, ge=0, le=5)

    # Google Cloud Translation (services/translation_service.py). Uses the
    # environment's Google credentials (Cloud Run service account); billed
    # to GCP_PROJECT_ID. No API keys.
    TRANSLATION_LOCATION: str = "global"

    # Configuración de envío de correo (SMTP) para las invitaciones (plan 3.7.1).
    # Vacío = feature desactivada: create_invitation sigue funcionando igual
    # que antes (el admin copia el link a mano), solo que sin intentar
    # mandar el correo.
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""
    # True -> SSL implícito (puerto 465). False -> STARTTLS (puerto 587).
    SMTP_USE_SSL: bool = False
    MAIL_FROM: str = ""
    MAIL_FROM_NAME: str = "CoreStream"

    # Raíz del almacenamiento local de documentos (solo STORAGE_BACKEND=local,
    # desarrollo y tests).
    UPLOAD_DIR: str = "/app/storage"

    # Document storage (see services/storage.py). "gcs" in GCP (required with
    # ENVIRONMENT=production); "local" keeps files under UPLOAD_DIR for
    # development and tests.
    STORAGE_BACKEND: Literal["gcs", "local"] = "local"
    GCS_BUCKET: str = ""
    
    # Configuración de Pydantic Settings
    class Config:
        """
        Configuración de Pydantic Settings para cargar variables de entorno.
        
        env_file: Especifica el archivo .env a cargar
        env_file_encoding: Codificación del archivo .env
        case_sensitive: Las variables de entorno son sensibles a mayúsculas
        """
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True

    @model_validator(mode="after")
    def validate_production_settings(self) -> "Settings":
        """
        Aborta el arranque si ENVIRONMENT=production trae configuración
        insegura (plan 3.4). Deliberadamente un model_validator(mode="after"),
        no field_validators individuales: con field_validator, el orden de
        declaración de los campos en la clase determina qué hay disponible en
        info.data, y ENVIRONMENT está declarado DESPUÉS de SECRET_KEY — un
        field_validator sobre SECRET_KEY nunca vería el ENVIRONMENT real. Aquí,
        al validar después de poblar todo el modelo, ese problema no existe.

        Antes, backend/.env traía literalmente
        SECRET_KEY=tu-clave-secreta-muy-segura-cambiar-en-produccion y nada
        impedía arrancar así contra el dominio público: con una clave
        conocida, cualquiera puede forjar un JWT con rol ADMIN.
        """
        if self.ENVIRONMENT != "production":
            return self

        placeholders = {
            "tu-clave-secreta-muy-segura-cambiar-en-produccion",
            "insecure-default-key-change-in-prod",
            "cambiar-esta-clave-por-una-generada",
            "",
        }
        # `openssl rand -hex 32` (lo que .env.example pide) produce 64
        # caracteres. El umbral queda bien por debajo de eso a propósito
        # (para no rechazar otros generadores válidos de menos entropía),
        # pero por encima de cualquier placeholder legible tecleado a mano
        # — la lista explícita de arriba ya cubre los conocidos, esto es
        # la red de seguridad para el próximo placeholder que alguien añada
        # y se olvide de registrar aquí.
        if self.SECRET_KEY in placeholders or len(self.SECRET_KEY) < 40:
            raise ValueError(
                "SECRET_KEY inválida para producción: falta, es un placeholder, o "
                "es demasiado corta. Generar una con: openssl rand -hex 32"
            )

        if self.DEBUG:
            raise ValueError("DEBUG no puede ser True con ENVIRONMENT=production")

        if "*" in self.ALLOWED_ORIGINS:
            raise ValueError(
                "ALLOWED_ORIGINS no puede ser '*' en producción — combinado con "
                "allow_credentials=True (cookies) es una combinación que los "
                "navegadores rechazan de todas formas, y expone la API a "
                "cualquier origen si algún día se relaja allow_credentials."
            )

        # Cloud Run's disk is ephemeral (and lives in RAM): local storage in
        # production would silently lose every uploaded document.
        if self.STORAGE_BACKEND != "gcs" or not self.GCS_BUCKET:
            raise ValueError(
                "En producción los documentos deben ir a Cloud Storage: "
                "STORAGE_BACKEND=gcs y GCS_BUCKET=<nombre del bucket>"
            )

        return self


@lru_cache()
def get_settings() -> Settings:
    """
    Obtiene la instancia singleton de configuración con caché.
    
    Esta función utiliza el decorador lru_cache para garantizar que solo se crea
    una instancia de Settings durante toda la vida de la aplicación, mejorando
    el rendimiento y evitando lecturas redundantes de variables de entorno.
    
    Returns:
        Settings: Instancia única de la clase Settings con configuración validada
        
    Ejemplo:
        settings = get_settings()
        db_url = settings.DATABASE_URL
        token_expiry = settings.ACCESS_TOKEN_EXPIRE_MINUTES
    """
    return Settings()
