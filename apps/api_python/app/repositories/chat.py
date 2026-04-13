from uuid import UUID

from sqlalchemy import asc, select
from sqlalchemy.orm import Session

from app.models import ChatMessage, ChatSession, Transcript, TranscriptSegment


class ChatRepository:
    def __init__(self, db: Session):
        self.db = db

    def create_session(self, recording_id: UUID, user_id: UUID, title: str | None) -> ChatSession:
        session = ChatSession(recording_id=recording_id, user_id=user_id, title=title)
        self.db.add(session)
        self.db.flush()
        return session

    def get_session_for_user(self, session_id: UUID, user_id: UUID) -> ChatSession | None:
        stmt = select(ChatSession).where(ChatSession.id == session_id, ChatSession.user_id == user_id)
        return self.db.scalar(stmt)

    def list_messages(self, session_id: UUID) -> list[ChatMessage]:
        stmt = select(ChatMessage).where(ChatMessage.chat_session_id == session_id).order_by(asc(ChatMessage.created_at))
        return list(self.db.scalars(stmt).all())

    def create_message(
        self,
        session_id: UUID,
        role: str,
        content: str,
        citations_json: list[dict] | None = None,
    ) -> ChatMessage:
        message = ChatMessage(
            chat_session_id=session_id,
            role=role,
            content=content,
            citations_json=citations_json,
        )
        self.db.add(message)
        self.db.flush()
        return message

    def find_relevant_segments(self, recording_id: UUID, query: str, limit: int = 3) -> list[TranscriptSegment]:
        transcript_stmt = select(Transcript).where(Transcript.recording_id == recording_id).order_by(Transcript.created_at.desc()).limit(1)
        transcript = self.db.scalar(transcript_stmt)
        if not transcript:
            return []

        pattern = f"%{query[:64]}%"
        stmt = (
            select(TranscriptSegment)
            .where(TranscriptSegment.transcript_id == transcript.id, TranscriptSegment.text.ilike(pattern))
            .order_by(TranscriptSegment.segment_index)
            .limit(limit)
        )
        hits = list(self.db.scalars(stmt).all())
        if hits:
            return hits

        fallback_stmt = (
            select(TranscriptSegment)
            .where(TranscriptSegment.transcript_id == transcript.id)
            .order_by(TranscriptSegment.segment_index)
            .limit(limit)
        )
        return list(self.db.scalars(fallback_stmt).all())
