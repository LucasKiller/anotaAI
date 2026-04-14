from __future__ import annotations

import logging
from dataclasses import dataclass

from app.config import get_settings

settings = get_settings()
logger = logging.getLogger(__name__)


@dataclass
class TranscriptionResult:
    full_text: str
    model_name: str
    segments: list[dict]


def transcribe_audio_file(
    *,
    file_path: str,
    title: str,
    object_key: str | None,
    language: str | None,
) -> TranscriptionResult:
    if settings.transcription_provider != 'local_whisper':
        return _stub_result(title=title, object_key=object_key)

    try:
        from faster_whisper import WhisperModel

        model = WhisperModel(
            settings.whisper_model_size,
            device=settings.whisper_device,
            compute_type=settings.whisper_compute_type,
        )

        segment_iter, _ = model.transcribe(
            file_path,
            language=language,
            vad_filter=True,
            beam_size=5,
        )

        text_parts: list[str] = []
        segments: list[dict] = []

        for segment in segment_iter:
            text = segment.text.strip()
            if not text:
                continue

            index = len(segments)
            start_ms = max(0, int(segment.start * 1000))
            end_ms = max(start_ms + 1, int(segment.end * 1000))

            text_parts.append(text)
            segments.append(
                {
                    'segment_index': index,
                    'start_ms': start_ms,
                    'end_ms': end_ms,
                    'text': text,
                    'tokens_estimate': max(1, len(text.split()) * 2),
                }
            )

        full_text = ' '.join(text_parts).strip()
        if not full_text:
            return _stub_result(title=title, object_key=object_key)

        return TranscriptionResult(
            full_text=full_text,
            model_name=f'faster-whisper:{settings.whisper_model_size}',
            segments=segments,
        )
    except Exception:
        logger.exception('Falling back to stub transcription for file=%s', file_path)
        return _stub_result(title=title, object_key=object_key)


def _stub_result(*, title: str, object_key: str | None) -> TranscriptionResult:
    source = object_key or 'arquivo sem chave'
    text = (
        f"Transcricao automatica da gravacao '{title}'. "
        f'Arquivo de origem: {source}. '
        'Este texto e um stub inicial para validar o pipeline assincrono do MVP.'
    )
    return TranscriptionResult(
        full_text=text,
        model_name=f'{settings.transcription_provider}:stub',
        segments=[],
    )
