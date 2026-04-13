from uuid import UUID

from sqlalchemy import desc, select
from sqlalchemy.orm import Session

from app.models import Transcript, TranscriptSegment


class TranscriptRepository:
    def __init__(self, db: Session):
        self.db = db

    def latest_for_recording(self, recording_id: UUID) -> Transcript | None:
        stmt = (
            select(Transcript)
            .where(Transcript.recording_id == recording_id)
            .order_by(desc(Transcript.version), desc(Transcript.created_at))
            .limit(1)
        )
        return self.db.scalar(stmt)

    def list_segments(self, transcript_id: UUID) -> list[TranscriptSegment]:
        stmt = (
            select(TranscriptSegment)
            .where(TranscriptSegment.transcript_id == transcript_id)
            .order_by(TranscriptSegment.segment_index)
        )
        return list(self.db.scalars(stmt).all())
