from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models import User
from app.repositories import TranscriptRepository
from app.schemas import TranscriptResponse, TranscriptSegmentListResponse, TranscriptSegmentResponse
from app.services import RecordingService

router = APIRouter(prefix="/recordings", tags=["transcript"])


@router.get("/{recording_id}/transcript", response_model=TranscriptResponse)
def get_transcript(
    recording_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> TranscriptResponse:
    RecordingService(db).get_for_user(recording_id=recording_id, user_id=user.id)

    transcript = TranscriptRepository(db).latest_for_recording(recording_id=recording_id)
    if not transcript:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transcript not found")

    return TranscriptResponse.model_validate(transcript)


@router.get("/{recording_id}/segments", response_model=TranscriptSegmentListResponse)
def get_segments(
    recording_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> TranscriptSegmentListResponse:
    RecordingService(db).get_for_user(recording_id=recording_id, user_id=user.id)

    transcripts = TranscriptRepository(db)
    transcript = transcripts.latest_for_recording(recording_id=recording_id)
    if not transcript:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transcript not found")

    segments = transcripts.list_segments(transcript.id)
    return TranscriptSegmentListResponse(items=[TranscriptSegmentResponse.model_validate(seg) for seg in segments])
