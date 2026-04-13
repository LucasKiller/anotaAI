from app.config import get_settings

settings = get_settings()


def transcribe_audio_stub(*, title: str, object_key: str | None) -> tuple[str, str]:
    """Placeholder para substituir por Whisper real no v0.2."""
    source = object_key or "arquivo sem chave"
    text = (
        f"Transcrição automática da gravação '{title}'. "
        f"Arquivo de origem: {source}. "
        "Este texto é um stub inicial para validar o pipeline assíncrono do MVP."
    )
    return text, settings.transcription_provider
