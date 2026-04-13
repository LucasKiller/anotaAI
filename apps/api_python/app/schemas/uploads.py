from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class UploadResponse(BaseModel):
    id: UUID
    recording_id: UUID
    bucket: str
    object_key: str
    mime_type: str
    size_bytes: int
    uploaded_at: datetime


class CompleteUploadRequest(BaseModel):
    mark_as_processing: bool = False
