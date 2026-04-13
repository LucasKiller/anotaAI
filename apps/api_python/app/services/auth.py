from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.security import (
    TokenError,
    create_access_token,
    create_refresh_token,
    decode_refresh_token,
    hash_password,
    hash_token,
    verify_password,
)
from app.repositories import RefreshTokenRepository, UserRepository

settings = get_settings()


@dataclass
class TokenPair:
    access_token: str
    refresh_token: str


class AuthService:
    def __init__(self, db: Session):
        self.db = db
        self.users = UserRepository(db)
        self.refresh_tokens = RefreshTokenRepository(db)

    def register(self, *, email: str, password: str, name: str | None) -> TokenPair:
        existing = self.users.get_by_email(email)
        if existing:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already in use")

        user = self.users.create(email=email, password_hash=hash_password(password), name=name)
        tokens = self._issue_tokens(str(user.id))
        self.db.commit()
        return tokens

    def login(self, *, email: str, password: str) -> TokenPair:
        user = self.users.get_by_email(email)
        if not user or not verify_password(password, user.password_hash):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

        self.users.touch_last_login(user)
        tokens = self._issue_tokens(str(user.id))
        self.db.commit()
        return tokens

    def refresh(self, *, refresh_token: str) -> TokenPair:
        try:
            payload = decode_refresh_token(refresh_token)
        except TokenError as exc:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token") from exc

        current = self.refresh_tokens.get_valid(hash_token(refresh_token))
        if not current:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired or revoked")

        self.refresh_tokens.revoke(current)
        try:
            tokens = self._issue_tokens(payload["sub"])
        except ValueError as exc:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token subject") from exc
        self.db.commit()
        return tokens

    def logout(self, *, refresh_token: str) -> None:
        try:
            decode_refresh_token(refresh_token)
        except TokenError as exc:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token") from exc

        current = self.refresh_tokens.get_valid(hash_token(refresh_token))
        if current:
            self.refresh_tokens.revoke(current)
            self.db.commit()

    def _issue_tokens(self, user_id: str) -> TokenPair:
        user_uuid = UUID(user_id)
        access_token = create_access_token(subject=user_id)
        refresh_token = create_refresh_token(subject=user_id)

        self.refresh_tokens.create(
            user_id=user_uuid,
            token_hash=hash_token(refresh_token),
            expires_at=datetime.now(UTC) + timedelta(days=settings.refresh_token_expire_days),
        )
        return TokenPair(access_token=access_token, refresh_token=refresh_token)
