from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models import User
from app.schemas import MeResponse, MeUpdateRequest, UserAiSettingsResponse, UserAiSettingsUpdateRequest
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


@router.get("/me/ai-settings", response_model=UserAiSettingsResponse)
def get_my_ai_settings(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> UserAiSettingsResponse:
    resolved = UserService(db).get_effective_ai_settings(user=user)
    return UserAiSettingsResponse(
        source=resolved.source,
        provider_type=resolved.provider_type,
        base_url=resolved.base_url,
        model=resolved.model,
        has_api_key=resolved.has_api_key,
        api_key_hint=resolved.api_key_hint,
        updated_at=resolved.updated_at,
    )


@router.put("/me/ai-settings", response_model=UserAiSettingsResponse)
def update_my_ai_settings(
    payload: UserAiSettingsUpdateRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> UserAiSettingsResponse:
    try:
        resolved = UserService(db).update_ai_settings(
            user=user,
            provider_type=payload.provider_type,
            base_url=payload.base_url,
            model=payload.model,
            api_key=payload.api_key,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return UserAiSettingsResponse(
        source=resolved.source,
        provider_type=resolved.provider_type,
        base_url=resolved.base_url,
        model=resolved.model,
        has_api_key=resolved.has_api_key,
        api_key_hint=resolved.api_key_hint,
        updated_at=resolved.updated_at,
    )


@router.delete("/me/ai-settings", response_model=UserAiSettingsResponse)
def clear_my_ai_settings(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> UserAiSettingsResponse:
    resolved = UserService(db).clear_ai_settings(user=user)
    return UserAiSettingsResponse(
        source=resolved.source,
        provider_type=resolved.provider_type,
        base_url=resolved.base_url,
        model=resolved.model,
        has_api_key=resolved.has_api_key,
        api_key_hint=resolved.api_key_hint,
        updated_at=resolved.updated_at,
    )
