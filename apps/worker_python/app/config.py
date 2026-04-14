from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "anotaai-worker"
    database_url: str = "postgresql+psycopg://anotaai:anotaai@localhost:5432/anotaai"
    redis_url: str = "redis://localhost:6379/0"
    job_queue_key: str = "anotaai:jobs"

    s3_endpoint: str = "http://localhost:9000"
    s3_bucket: str = "anotaai-private"
    s3_region: str = "us-east-1"
    s3_access_key: str = "minioadmin"
    s3_secret_key: str = "minioadmin"
    s3_force_path_style: bool = True

    llm_provider: str = "ollama"
    llm_base_url: str = "http://localhost:11434/api"

    transcription_provider: str = "local_whisper"
    whisper_model_size: str = "base"
    whisper_compute_type: str = "int8"
    whisper_device: str = "cpu"
    embeddings_provider: str = "local"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
