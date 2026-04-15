from uuid import UUID
import json

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.integrations.llm import AiGatewayClient, AiGatewayError
from app.models import ChatMessage, ChatSession
from app.repositories import ChatRepository

settings = get_settings()
_GATEWAY_PROVIDERS = {"ai_gateway", "gateway"}


class ChatService:
    def __init__(self, db: Session):
        self.db = db
        self.chat = ChatRepository(db)

    def create_session(self, *, recording_id: UUID, user_id: UUID, title: str | None) -> ChatSession:
        session = self.chat.create_session(recording_id=recording_id, user_id=user_id, title=title)
        self.db.commit()
        self.db.refresh(session)
        return session

    def list_sessions_for_recording(self, *, recording_id: UUID, user_id: UUID) -> list[ChatSession]:
        return self.chat.list_sessions_for_recording(recording_id=recording_id, user_id=user_id)

    def build_reply(self, *, session: ChatSession, user_content: str) -> tuple[ChatMessage, ChatMessage]:
        user_message = self.chat.create_message(session_id=session.id, role="user", content=user_content)
        relevant_segments = self.chat.find_relevant_segments(recording_id=session.recording_id, query=user_content)
        summary_artifact = self.chat.latest_artifact(recording_id=session.recording_id, artifact_type="summary")
        mindmap_artifact = self.chat.latest_artifact(recording_id=session.recording_id, artifact_type="mindmap")
        recent_messages = self.chat.list_messages(session.id)[-8:]
        citations = [
            {
                "segment_id": str(seg.id),
                "start_ms": seg.start_ms,
                "end_ms": seg.end_ms,
            }
            for seg in relevant_segments
        ]

        if not relevant_segments and not summary_artifact and not mindmap_artifact:
            answer = "Ainda nao ha transcricao ou artefatos suficientes para responder sobre esta gravacao."
        elif settings.llm_provider in _GATEWAY_PROVIDERS or settings.llm_api_key:
            client = AiGatewayClient()
            try:
                answer = client.create_chat_completion(
                    messages=self._build_messages(
                        session=session,
                        user_content=user_content,
                        recent_messages=recent_messages,
                        relevant_segments=relevant_segments,
                        summary_markdown=summary_artifact.content_md if summary_artifact else None,
                        mindmap_json=mindmap_artifact.content_json if mindmap_artifact else None,
                    ),
                    temperature=0.2,
                    max_completion_tokens=800,
                ).text
            except AiGatewayError as exc:
                raise ValueError(f"Falha ao consultar o AI Gateway: {exc}") from exc
        else:
            context = "\n".join(
                f"- [{self._format_ms(seg.start_ms)}-{self._format_ms(seg.end_ms)}] {seg.text}"
                for seg in relevant_segments
            )
            answer = (
                "Resposta baseada na transcricao atual:\n"
                f"{context}\n\n"
                "Configure o AI Gateway para respostas conversacionais mais elaboradas."
            )

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

    def _build_messages(
        self,
        *,
        session: ChatSession,
        user_content: str,
        recent_messages: list[ChatMessage],
        relevant_segments: list,
        summary_markdown: str | None,
        mindmap_json: dict | list | None,
    ) -> list[dict]:
        messages: list[dict] = [
            {
                "role": "system",
                "content": (
                    "Voce e o assistente do AnotaAi.\n"
                    "Responda somente com base na gravacao atual, no resumo, no mapa mental e no historico do chat.\n"
                    "Nao invente fatos ausentes.\n"
                    "Se a resposta nao estiver suficientemente suportada pelo contexto, diga isso com clareza.\n"
                    "Seja objetivo, util e use o mesmo idioma da pergunta do usuario.\n"
                    "Quando usar a transcricao, mencione referencias de tempo no formato [mm:ss-mm:ss] quando fizer sentido."
                ),
            }
        ]

        context_parts = [f"Gravacao: {session.title or str(session.recording_id)}"]
        if summary_markdown:
            context_parts.extend(["", "Resumo:", summary_markdown.strip()])
        if mindmap_json:
            context_parts.extend(["", "Mapa mental:", json.dumps(mindmap_json, ensure_ascii=False)])
        if relevant_segments:
            context_parts.append("")
            context_parts.append("Trechos relevantes da transcricao:")
            context_parts.extend(
                f"- [{self._format_ms(seg.start_ms)}-{self._format_ms(seg.end_ms)}] {seg.text}"
                for seg in relevant_segments
            )

        messages.append({"role": "system", "content": "\n".join(context_parts).strip()})

        history = recent_messages[:-1] if recent_messages else []
        for message in history:
            if message.role not in {"user", "assistant", "system"}:
                continue
            messages.append({"role": message.role, "content": message.content})

        messages.append({"role": "user", "content": user_content})
        return messages

    def _format_ms(self, value: int) -> str:
        total_seconds = max(0, value // 1000)
        minutes = total_seconds // 60
        seconds = total_seconds % 60
        return f"{minutes:02d}:{seconds:02d}"
