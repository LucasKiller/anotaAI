from sqlalchemy.orm import Session

from app.integrations.queue.redis_queue import RedisQueue
from app.models import ProcessingJob, Recording
from app.repositories import JobRepository


class ProcessingService:
    def __init__(self, db: Session):
        self.db = db
        self.jobs = JobRepository(db)
        self.queue = RedisQueue()

    def enqueue_recording_pipeline(self, recording: Recording) -> ProcessingJob:
        payload = {"recording_id": str(recording.id), "user_id": str(recording.user_id)}
        job = self.jobs.create(recording_id=recording.id, job_type="pipeline", payload_json=payload)

        recording.status = "processing"
        self.db.add(recording)
        self.db.commit()
        self.db.refresh(job)

        self.queue.enqueue(
            {
                "job_id": str(job.id),
                "recording_id": str(recording.id),
                "user_id": str(recording.user_id),
                "job_type": "pipeline",
            }
        )
        return job
