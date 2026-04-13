from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.models import Recording
from app.repositories import RecordingRepository


class RecordingService:
    def __init__(self, db: Session):
        self.db = db
        self.recordings = RecordingRepository(db)

    def create(
        self,
        *,
        user_id: UUID,
        title: str,
        description: str | None,
        language: str | None,
        source_type: str,
    ) -> Recording:
        recording = self.recordings.create(
            user_id=user_id,
            title=title,
            description=description,
            language=language,
            source_type=source_type,
        )
        self.db.commit()
        self.db.refresh(recording)
        return recording

    def list_for_user(self, user_id: UUID) -> list[Recording]:
        return self.recordings.list_by_user(user_id)

    def get_for_user(self, recording_id: UUID, user_id: UUID) -> Recording:
        recording = self.recordings.get_for_user(recording_id=recording_id, user_id=user_id)
        if not recording:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recording not found")
        return recording

    def update(
        self,
        *,
        recording: Recording,
        title: str | None,
        description: str | None,
        language: str | None,
    ) -> Recording:
        if title is not None:
            recording.title = title
        if description is not None:
            recording.description = description
        if language is not None:
            recording.language = language

        self.db.add(recording)
        self.db.commit()
        self.db.refresh(recording)
        return recording

    def delete(self, recording: Recording) -> None:
        self.recordings.delete(recording)
        self.db.commit()
