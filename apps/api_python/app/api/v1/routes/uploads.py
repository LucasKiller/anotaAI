from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models import User
from app.schemas import CompleteUploadRequest, MessageResponse, UploadResponse
from app.services import RecordingService, UploadService

router = APIRouter(prefix="/recordings", tags=["uploads"])


@router.post("/{recording_id}/upload", response_model=UploadResponse)
def upload_recording(
    recording_id: UUID,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> UploadResponse:
    recording_service = RecordingService(db)
    upload_service = UploadService(db)
    recording = recording_service.get_for_user(recording_id=recording_id, user_id=user.id)

    try:
        uploaded = upload_service.upload_audio(recording=recording, upload=file)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return UploadResponse.model_validate(uploaded)


@router.post("/{recording_id}/complete-upload", response_model=MessageResponse)
def complete_upload(
    recording_id: UUID,
    payload: CompleteUploadRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> MessageResponse:
    recording_service = RecordingService(db)
    recording = recording_service.get_for_user(recording_id=recording_id, user_id=user.id)

    if payload.mark_as_processing:
        recording.status = "processing"
        db.add(recording)
        db.commit()

    return MessageResponse(message="Upload completed")
