from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_env: str = "development"
    app_name: str = "anotaai"

    api_host: str = "0.0.0.0"
    api_port: int = 8000
    cors_origins: str = "*"

    database_url: str = "postgresql+psycopg://anotaai:anotaai@localhost:5432/anotaai"
    redis_url: str = "redis://localhost:6379/0"

    s3_endpoint: str = "http://localhost:9000"
    s3_bucket: str = "anotaai-private"
    s3_region: str = "us-east-1"
    s3_access_key: str = "minioadmin"
    s3_secret_key: str = "minioadmin"
    s3_force_path_style: bool = True
    s3_connect_timeout_seconds: int = 5
    s3_read_timeout_seconds: int = 120

    jwt_secret: str = "change-me-access"
    jwt_refresh_secret: str = "change-me-refresh"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 30
    ai_settings_encryption_key: str | None = None

    llm_provider: str = "ollama"
    llm_base_url: str = "http://localhost:11434/api"
    llm_api_key: str | None = None
    llm_model: str = "gemma3:4b"
    llm_timeout_seconds: int = 120

    transcription_provider: str = "local_whisper"
    embeddings_provider: str = "local"

    job_queue_key: str = "anotaai:jobs"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
