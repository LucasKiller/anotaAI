from uuid import UUID

from sqlalchemy import asc, select
from sqlalchemy.orm import Session

from app.models import ProcessingJob


class JobRepository:
    def __init__(self, db: Session):
        self.db = db

    def create(self, recording_id: UUID, job_type: str, payload_json: dict | None = None) -> ProcessingJob:
        job = ProcessingJob(recording_id=recording_id, job_type=job_type, status="queued", payload_json=payload_json)
        self.db.add(job)
        self.db.flush()
        return job

    def list_by_recording(self, recording_id: UUID) -> list[ProcessingJob]:
        stmt = select(ProcessingJob).where(ProcessingJob.recording_id == recording_id).order_by(asc(ProcessingJob.queued_at))
        return list(self.db.scalars(stmt).all())
