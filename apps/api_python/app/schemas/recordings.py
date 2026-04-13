from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class RecordingCreate(BaseModel):
    title: str = Field(min_length=1, max_length=255)
    description: str | None = None
    language: str | None = Field(default=None, max_length=32)
    source_type: str = Field(default="upload", max_length=32)


class RecordingUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = None
    language: str | None = Field(default=None, max_length=32)


class RecordingResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    title: str
    description: str | None
    language: str | None
    source_type: str
    status: str
    duration_ms: int | None
    created_at: datetime
    updated_at: datetime
    processed_at: datetime | None
    failed_reason: str | None


class RecordingListResponse(BaseModel):
    items: list[RecordingResponse]
