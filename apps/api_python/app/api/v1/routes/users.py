from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models import User
from app.schemas import MeResponse, MeUpdateRequest
from app.services import UserService

router = APIRouter(tags=["users"])


@router.get("/me", response_model=MeResponse)
def me(user: User = Depends(get_current_user)) -> MeResponse:
    return MeResponse.model_validate(user)


@router.patch("/me", response_model=MeResponse)
def update_me(
    payload: MeUpdateRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> MeResponse:
    updated = UserService(db).update_name(user=user, name=payload.name)
    return MeResponse.model_validate(updated)
