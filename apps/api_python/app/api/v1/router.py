from fastapi import APIRouter

from app.api.v1.routes import artifacts, auth, chat, health, processing, recordings, transcript, uploads, users

api_router = APIRouter(prefix="/v1")
api_router.include_router(health.router)
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(recordings.router)
api_router.include_router(uploads.router)
api_router.include_router(processing.router)
api_router.include_router(transcript.router)
api_router.include_router(artifacts.router)
api_router.include_router(chat.router)
