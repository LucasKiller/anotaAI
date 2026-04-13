from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class ArtifactResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    recording_id: UUID
    artifact_type: str
    version: int
    content_md: str | None
    content_json: dict | list | None
    model_name: str | None
    created_at: datetime
