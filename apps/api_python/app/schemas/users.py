from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class UserAiSettingsUpdateRequest(BaseModel):
    provider_type: Literal["openai", "openai_compatible"]
    base_url: str | None = Field(default=None, max_length=1024)
    model: str = Field(min_length=1, max_length=255)
    api_key: str | None = Field(default=None, min_length=1, max_length=4096)


class UserAiSettingsResponse(BaseModel):
    source: Literal["system", "user"]
    provider_type: Literal["openai", "openai_compatible"]
    base_url: str
    model: str
    has_api_key: bool
    api_key_hint: str | None = None
    updated_at: datetime | None = None
