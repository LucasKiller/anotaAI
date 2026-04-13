from uuid import UUID

from sqlalchemy import desc, select
from sqlalchemy.orm import Session

from app.models import Recording, RecordingFile


class RecordingRepository:
    def __init__(self, db: Session):
        self.db = db

    def create(self, user_id: UUID, title: str, description: str | None, language: str | None, source_type: str) -> Recording:
        recording = Recording(
            user_id=user_id,
            title=title,
            description=description,
            language=language,
            source_type=source_type,
        )
        self.db.add(recording)
        self.db.flush()
        return recording

    def list_by_user(self, user_id: UUID) -> list[Recording]:
        stmt = select(Recording).where(Recording.user_id == user_id).order_by(desc(Recording.created_at))
        return list(self.db.scalars(stmt).all())

    def get_for_user(self, recording_id: UUID, user_id: UUID) -> Recording | None:
        stmt = select(Recording).where(Recording.id == recording_id, Recording.user_id == user_id)
        return self.db.scalar(stmt)

    def delete(self, recording: Recording) -> None:
        self.db.delete(recording)


class RecordingFileRepository:
    def __init__(self, db: Session):
        self.db = db

    def create(
        self,
        recording_id: UUID,
        bucket: str,
        object_key: str,
        mime_type: str,
        size_bytes: int,
        checksum_sha256: str | None,
    ) -> RecordingFile:
        recording_file = RecordingFile(
            recording_id=recording_id,
            bucket=bucket,
            object_key=object_key,
            mime_type=mime_type,
            size_bytes=size_bytes,
            checksum_sha256=checksum_sha256,
        )
        self.db.add(recording_file)
        self.db.flush()
        return recording_file

    def latest_for_recording(self, recording_id: UUID) -> RecordingFile | None:
        stmt = (
            select(RecordingFile)
            .where(RecordingFile.recording_id == recording_id)
            .order_by(desc(RecordingFile.uploaded_at))
            .limit(1)
        )
        return self.db.scalar(stmt)
