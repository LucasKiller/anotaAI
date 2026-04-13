from uuid import UUID

from sqlalchemy.orm import Session

from app.models import ChatMessage, ChatSession
from app.repositories import ChatRepository


class ChatService:
    def __init__(self, db: Session):
        self.db = db
        self.chat = ChatRepository(db)

    def create_session(self, *, recording_id: UUID, user_id: UUID, title: str | None) -> ChatSession:
        session = self.chat.create_session(recording_id=recording_id, user_id=user_id, title=title)
        self.db.commit()
        self.db.refresh(session)
        return session

    def build_reply(self, *, session: ChatSession, user_content: str) -> tuple[ChatMessage, ChatMessage]:
        user_message = self.chat.create_message(session_id=session.id, role="user", content=user_content)

        relevant_segments = self.chat.find_relevant_segments(recording_id=session.recording_id, query=user_content)
        citations = [
            {
                "segment_id": str(seg.id),
                "start_ms": seg.start_ms,
                "end_ms": seg.end_ms,
            }
            for seg in relevant_segments
        ]

        if relevant_segments:
            context = "\n".join(f"- [{seg.start_ms}-{seg.end_ms}] {seg.text}" for seg in relevant_segments)
            answer = (
                "Resposta baseada na transcrição:\n"
                f"{context}\n\n"
                "Interpretação: o conteúdo acima indica os pontos mais relacionados à sua pergunta."
            )
        else:
            answer = "Ainda não há transcrição disponível para esta gravação."

        assistant_message = self.chat.create_message(
            session_id=session.id,
            role="assistant",
            content=answer,
            citations_json=citations or None,
        )

        self.db.commit()
        self.db.refresh(user_message)
        self.db.refresh(assistant_message)

        return user_message, assistant_message
