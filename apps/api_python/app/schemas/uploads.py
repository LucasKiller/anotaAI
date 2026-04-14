from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class UploadResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    recording_id: UUID
    bucket: str
    object_key: str
    mime_type: str
    size_bytes: int
    uploaded_at: datetime


class CompleteUploadRequest(BaseModel):
    mark_as_processing: bool = False
