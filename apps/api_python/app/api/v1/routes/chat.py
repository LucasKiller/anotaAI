from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models import User
from app.repositories import ChatRepository
from app.schemas import (
    ChatMessageCreate,
    ChatMessageResponse,
    ChatReplyResponse,
    ChatSessionCreate,
    ChatSessionDetailResponse,
    ChatSessionResponse,
)
from app.services import ChatService, RecordingService

router = APIRouter(tags=["chat"])


@router.post("/recordings/{recording_id}/chat/sessions", response_model=ChatSessionResponse, status_code=201)
def create_chat_session(
    recording_id: UUID,
    payload: ChatSessionCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ChatSessionResponse:
    RecordingService(db).get_for_user(recording_id=recording_id, user_id=user.id)
    session = ChatService(db).create_session(recording_id=recording_id, user_id=user.id, title=payload.title)
    return ChatSessionResponse.model_validate(session)


@router.get("/chat/sessions/{session_id}", response_model=ChatSessionDetailResponse)
def get_chat_session(
    session_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ChatSessionDetailResponse:
    repo = ChatRepository(db)
    session = repo.get_session_for_user(session_id=session_id, user_id=user.id)
    if not session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Chat session not found")
    messages = repo.list_messages(session_id)
    return ChatSessionDetailResponse(
        session=ChatSessionResponse.model_validate(session),
        messages=[ChatMessageResponse.model_validate(m) for m in messages],
    )


@router.post("/chat/sessions/{session_id}/messages", response_model=ChatReplyResponse)
def send_chat_message(
    session_id: UUID,
    payload: ChatMessageCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ChatReplyResponse:
    repo = ChatRepository(db)
    session = repo.get_session_for_user(session_id=session_id, user_id=user.id)
    if not session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Chat session not found")

    user_message, assistant_message = ChatService(db).build_reply(session=session, user_content=payload.content)

    return ChatReplyResponse(
        user_message=ChatMessageResponse.model_validate(user_message),
        assistant_message=ChatMessageResponse.model_validate(assistant_message),
    )
