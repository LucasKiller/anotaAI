from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class TranscriptResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    recording_id: UUID
    version: int
    full_text: str
    language: str | None
    model_name: str | None
    created_at: datetime


class TranscriptSegmentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    transcript_id: UUID
    segment_index: int
    start_ms: int
    end_ms: int
    speaker_label: str | None
    text: str
    tokens_estimate: int | None
    created_at: datetime


class TranscriptSegmentListResponse(BaseModel):
    items: list[TranscriptSegmentResponse]
