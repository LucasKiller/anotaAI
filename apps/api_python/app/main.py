from fastapi import FastAPI

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.core.database import init_db
from app.core.logging import setup_logging

settings = get_settings()

setup_logging()
app = FastAPI(title=settings.app_name)
app.include_router(api_router)


@app.on_event("startup")
def startup() -> None:
    init_db()
