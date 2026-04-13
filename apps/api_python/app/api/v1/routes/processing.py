from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models import User
from app.repositories import JobRepository
from app.schemas import ProcessingJobListResponse, ProcessingJobResponse
from app.services import ProcessingService, RecordingService

router = APIRouter(prefix="/recordings", tags=["processing"])


@router.post("/{recording_id}/process", response_model=ProcessingJobResponse)
def process_recording(
    recording_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ProcessingJobResponse:
    recordings = RecordingService(db)
    processing = ProcessingService(db)

    recording = recordings.get_for_user(recording_id=recording_id, user_id=user.id)
    job = processing.enqueue_recording_pipeline(recording)
    return ProcessingJobResponse.model_validate(job)


@router.get("/{recording_id}/jobs", response_model=ProcessingJobListResponse)
def list_jobs(
    recording_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ProcessingJobListResponse:
    recordings = RecordingService(db)
    recordings.get_for_user(recording_id=recording_id, user_id=user.id)

    jobs = JobRepository(db).list_by_recording(recording_id=recording_id)
    return ProcessingJobListResponse(items=[ProcessingJobResponse.model_validate(job) for job in jobs])
