from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class ProcessingJobResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    recording_id: UUID
    job_type: str
    status: str
    attempts: int
    payload_json: dict | list | None
    result_json: dict | list | None
    error_message: str | None
    queued_at: datetime
    started_at: datetime | None
    finished_at: datetime | None


class ProcessingJobListResponse(BaseModel):
    items: list[ProcessingJobResponse]
