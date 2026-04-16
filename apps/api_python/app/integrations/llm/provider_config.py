from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from app.core.config import get_settings
from app.core.secrets import decrypt_user_secret
from app.models import UserAiSetting

settings = get_settings()

_OPENAI_BASE_URL = "https://api.openai.com/v1"
_OPENAI_PROVIDER_TYPES = {"openai"}
_COMPATIBLE_PROVIDER_TYPES = {"openai_compatible", "ai_gateway", "gateway"}


@dataclass
class ResolvedLlmConfig:
    source: str
    provider_type: str
    base_url: str
    model: str
    api_key: str | None
    has_api_key: bool
    api_key_hint: str | None = None
    updated_at: datetime | None = None


def resolve_system_llm_config() -> ResolvedLlmConfig:
    provider_type = _normalize_system_provider_type(settings.llm_provider)
    base_url = normalize_base_url(provider_type, settings.llm_base_url)
    api_key = settings.llm_api_key.strip() if settings.llm_api_key else None
    return ResolvedLlmConfig(
        source="system",
        provider_type=provider_type,
        base_url=base_url,
        model=settings.llm_model.strip(),
        api_key=api_key,
        has_api_key=bool(api_key),
        api_key_hint=None,
        updated_at=None,
    )


def resolve_effective_llm_config(user_setting: UserAiSetting | None) -> ResolvedLlmConfig:
    if not user_setting:
        return resolve_system_llm_config()

    api_key = decrypt_user_secret(user_setting.api_key_encrypted) if user_setting.api_key_encrypted else None
    return ResolvedLlmConfig(
        source="user",
        provider_type=normalize_provider_type(user_setting.provider_type),
        base_url=normalize_base_url(user_setting.provider_type, user_setting.base_url),
        model=user_setting.model_name,
        api_key=api_key,
        has_api_key=bool(api_key),
        api_key_hint=user_setting.api_key_hint,
        updated_at=user_setting.updated_at,
    )


def normalize_provider_type(value: str | None) -> str:
    normalized = (value or "openai").strip().lower()
    if normalized in _OPENAI_PROVIDER_TYPES:
        return "openai"
    if normalized in _COMPATIBLE_PROVIDER_TYPES:
        return "openai_compatible"
    raise ValueError("provider_type invalido. Use 'openai' ou 'openai_compatible'.")


def _normalize_system_provider_type(value: str | None) -> str:
    normalized = (value or "openai_compatible").strip().lower()
    if normalized in _OPENAI_PROVIDER_TYPES:
        return "openai"
    return "openai_compatible"


def normalize_base_url(provider_type: str | None, base_url: str | None) -> str:
    normalized_provider = normalize_provider_type(provider_type)
    if normalized_provider == "openai":
        return _OPENAI_BASE_URL

    normalized = (base_url or "").strip().rstrip("/")
    if not normalized:
        raise ValueError("base_url e obrigatoria para provider_type='openai_compatible'.")
    if not normalized.startswith("http://") and not normalized.startswith("https://"):
        raise ValueError("base_url deve comecar com http:// ou https://.")
    return normalized
