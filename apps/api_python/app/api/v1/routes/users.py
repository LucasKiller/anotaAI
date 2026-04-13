from fastapi import APIRouter, Depends

from app.core.dependencies import get_current_user
from app.models import User
from app.schemas import MeResponse

router = APIRouter(tags=["users"])


@router.get("/me", response_model=MeResponse)
def me(user: User = Depends(get_current_user)) -> MeResponse:
    return MeResponse.model_validate(user)
