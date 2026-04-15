from uuid import UUID

import re
from datetime import UTC, datetime

from sqlalchemy import asc, desc, select
from sqlalchemy.orm import Session

from app.models import Artifact, ChatMessage, ChatSession, Transcript, TranscriptSegment


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

    def list_sessions_for_recording(self, recording_id: UUID, user_id: UUID) -> list[ChatSession]:
        stmt = (
            select(ChatSession)
            .where(ChatSession.recording_id == recording_id, ChatSession.user_id == user_id)
            .order_by(desc(ChatSession.updated_at), desc(ChatSession.created_at))
        )
        return list(self.db.scalars(stmt).all())

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
        session = self.db.get(ChatSession, session_id)
        if session:
            session.updated_at = datetime.now(UTC)
            self.db.add(session)
        self.db.add(message)
        self.db.flush()
        return message

    def find_relevant_segments(self, recording_id: UUID, query: str, limit: int = 5) -> list[TranscriptSegment]:
        transcript_stmt = select(Transcript).where(Transcript.recording_id == recording_id).order_by(Transcript.created_at.desc()).limit(1)
        transcript = self.db.scalar(transcript_stmt)
        if not transcript:
            return []

        fallback_stmt = (
            select(TranscriptSegment)
            .where(TranscriptSegment.transcript_id == transcript.id)
            .order_by(TranscriptSegment.segment_index)
        )
        segments = list(self.db.scalars(fallback_stmt).all())
        if not segments:
            return []

        terms = [term for term in re.findall(r"\w+", query.lower()) if len(term) >= 3]
        if not terms:
            return segments[:limit]

        scored: list[tuple[int, int, TranscriptSegment]] = []
        for segment in segments:
            text = segment.text.lower()
            score = sum(text.count(term) for term in terms)
            if score > 0:
                scored.append((score, -segment.segment_index, segment))

        if not scored:
            return segments[:limit]

        scored.sort(reverse=True)
        top = [item[2] for item in scored[:limit]]
        top.sort(key=lambda item: item.segment_index)
        return top

    def latest_artifact(self, recording_id: UUID, artifact_type: str) -> Artifact | None:
        stmt = (
            select(Artifact)
            .where(Artifact.recording_id == recording_id, Artifact.artifact_type == artifact_type)
            .order_by(desc(Artifact.version), desc(Artifact.created_at))
            .limit(1)
        )
        return self.db.scalar(stmt)
