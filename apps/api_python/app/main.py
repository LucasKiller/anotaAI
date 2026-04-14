from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.core.database import init_db
from app.core.logging import setup_logging

settings = get_settings()

setup_logging()
app = FastAPI(title=settings.app_name)

raw_origins = [item.strip() for item in settings.cors_origins.split(",") if item.strip()]
allow_origins = ["*"] if "*" in raw_origins else raw_origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins or ["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router)


@app.on_event("startup")
def startup() -> None:
    init_db()
