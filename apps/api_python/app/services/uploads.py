from fastapi import UploadFile
from sqlalchemy.orm import Session

from app.integrations.storage.s3_storage import S3Storage
from app.models import Recording, RecordingFile
from app.repositories import RecordingFileRepository


class UploadService:
    def __init__(self, db: Session):
        self.db = db
        self.files = RecordingFileRepository(db)
        self.storage = S3Storage()

    def upload_audio(self, *, recording: Recording, upload: UploadFile) -> RecordingFile:
        body = upload.file.read()
        if not body:
            raise ValueError("Uploaded file is empty")

        stored = self.storage.upload_recording_file(
            user_id=recording.user_id,
            recording_id=recording.id,
            filename=upload.filename or "audio.bin",
            content_type=upload.content_type or "application/octet-stream",
            content=body,
        )

        recording_file = self.files.create(
            recording_id=recording.id,
            bucket=stored.bucket,
            object_key=stored.object_key,
            mime_type=upload.content_type or "application/octet-stream",
            size_bytes=stored.size_bytes,
            checksum_sha256=stored.checksum_sha256,
        )
        self.db.commit()
        self.db.refresh(recording_file)
        return recording_file
