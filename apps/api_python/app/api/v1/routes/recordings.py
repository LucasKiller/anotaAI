from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models import User
from app.schemas import MessageResponse, RecordingCreate, RecordingListResponse, RecordingResponse, RecordingUpdate
from app.services import RecordingService

router = APIRouter(prefix="/recordings", tags=["recordings"])


@router.post("", response_model=RecordingResponse, status_code=status.HTTP_201_CREATED)
def create_recording(
    payload: RecordingCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> RecordingResponse:
    service = RecordingService(db)
    recording = service.create(
        user_id=user.id,
        title=payload.title,
        description=payload.description,
        language=payload.language,
        source_type=payload.source_type,
    )
    return RecordingResponse.model_validate(recording)


@router.get("", response_model=RecordingListResponse)
def list_recordings(db: Session = Depends(get_db), user: User = Depends(get_current_user)) -> RecordingListResponse:
    service = RecordingService(db)
    items = service.list_for_user(user.id)
    return RecordingListResponse(items=[RecordingResponse.model_validate(item) for item in items])


@router.get("/{recording_id}", response_model=RecordingResponse)
def get_recording(
    recording_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> RecordingResponse:
    service = RecordingService(db)
    recording = service.get_for_user(recording_id=recording_id, user_id=user.id)
    return RecordingResponse.model_validate(recording)


@router.patch("/{recording_id}", response_model=RecordingResponse)
def patch_recording(
    recording_id: UUID,
    payload: RecordingUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> RecordingResponse:
    service = RecordingService(db)
    recording = service.get_for_user(recording_id=recording_id, user_id=user.id)
    update_data = payload.model_dump(exclude_unset=True)
    updated = service.update(
        recording=recording,
        update_data=update_data,
    )
    return RecordingResponse.model_validate(updated)


@router.delete("/{recording_id}", response_model=MessageResponse)
def delete_recording(
    recording_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> MessageResponse:
    service = RecordingService(db)
    recording = service.get_for_user(recording_id=recording_id, user_id=user.id)
    service.delete(recording)
    return MessageResponse(message="Recording deleted")
