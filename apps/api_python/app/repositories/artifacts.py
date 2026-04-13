from uuid import UUID

from sqlalchemy import desc, select
from sqlalchemy.orm import Session

from app.models import Artifact


class ArtifactRepository:
    def __init__(self, db: Session):
        self.db = db

    def latest(self, recording_id: UUID, artifact_type: str) -> Artifact | None:
        stmt = (
            select(Artifact)
            .where(Artifact.recording_id == recording_id, Artifact.artifact_type == artifact_type)
            .order_by(desc(Artifact.version), desc(Artifact.created_at))
            .limit(1)
        )
        return self.db.scalar(stmt)
