from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models import User
from app.repositories import ArtifactRepository
from app.schemas import ArtifactResponse, MessageResponse
from app.services import RecordingService

router = APIRouter(prefix="/recordings", tags=["artifacts"])


@router.get("/{recording_id}/summary", response_model=ArtifactResponse)
def get_summary(
    recording_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ArtifactResponse:
    RecordingService(db).get_for_user(recording_id=recording_id, user_id=user.id)
    artifact = ArtifactRepository(db).latest(recording_id=recording_id, artifact_type="summary")
    if not artifact:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Summary not found")
    return ArtifactResponse.model_validate(artifact)


@router.get("/{recording_id}/mindmap", response_model=ArtifactResponse)
def get_mindmap(
    recording_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ArtifactResponse:
    RecordingService(db).get_for_user(recording_id=recording_id, user_id=user.id)
    artifact = ArtifactRepository(db).latest(recording_id=recording_id, artifact_type="mindmap")
    if not artifact:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mindmap not found")
    return ArtifactResponse.model_validate(artifact)


@router.post("/{recording_id}/regenerate-summary", response_model=MessageResponse)
def regenerate_summary(
    recording_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> MessageResponse:
    RecordingService(db).get_for_user(recording_id=recording_id, user_id=user.id)
    return MessageResponse(message="Summary regeneration scheduled")


@router.post("/{recording_id}/regenerate-mindmap", response_model=MessageResponse)
def regenerate_mindmap(
    recording_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> MessageResponse:
    RecordingService(db).get_for_user(recording_id=recording_id, user_id=user.id)
    return MessageResponse(message="Mindmap regeneration scheduled")
