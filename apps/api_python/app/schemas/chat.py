from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ChatSessionCreate(BaseModel):
    title: str | None = Field(default=None, max_length=255)


class ChatSessionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    recording_id: UUID
    user_id: UUID
    title: str | None
    created_at: datetime
    updated_at: datetime


class ChatSessionListResponse(BaseModel):
    items: list[ChatSessionResponse]


class ChatMessageCreate(BaseModel):
    content: str = Field(min_length=1)


class ChatMessageResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    chat_session_id: UUID
    role: str
    content: str
    citations_json: dict | list | None
    created_at: datetime


class ChatSessionDetailResponse(BaseModel):
    session: ChatSessionResponse
    messages: list[ChatMessageResponse]


class ChatReplyResponse(BaseModel):
    user_message: ChatMessageResponse
    assistant_message: ChatMessageResponse
