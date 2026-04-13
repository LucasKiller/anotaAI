from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "anotaai-worker"
    database_url: str = "postgresql+psycopg://anotaai:anotaai@localhost:5432/anotaai"
    redis_url: str = "redis://localhost:6379/0"
    job_queue_key: str = "anotaai:jobs"

    llm_provider: str = "ollama"
    llm_base_url: str = "http://localhost:11434/api"

    transcription_provider: str = "local_whisper"
    embeddings_provider: str = "local"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
