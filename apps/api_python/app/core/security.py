from datetime import UTC, datetime, timedelta
from hashlib import sha256
from typing import Any

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.core.config import get_settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
settings = get_settings()


class TokenError(Exception):
    """Raised when a token is invalid or has unexpected shape."""


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def _token_payload(subject: str, expires_delta: timedelta, token_type: str) -> dict[str, Any]:
    expire = datetime.now(UTC) + expires_delta
    return {"sub": subject, "exp": expire, "type": token_type}


def create_access_token(subject: str) -> str:
    payload = _token_payload(
        subject=subject,
        expires_delta=timedelta(minutes=settings.access_token_expire_minutes),
        token_type="access",
    )
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_refresh_token(subject: str) -> str:
    payload = _token_payload(
        subject=subject,
        expires_delta=timedelta(days=settings.refresh_token_expire_days),
        token_type="refresh",
    )
    return jwt.encode(payload, settings.jwt_refresh_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> dict[str, Any]:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError as exc:
        raise TokenError("Invalid access token") from exc

    if payload.get("type") != "access" or "sub" not in payload:
        raise TokenError("Invalid access token payload")
    return payload


def decode_refresh_token(token: str) -> dict[str, Any]:
    try:
        payload = jwt.decode(token, settings.jwt_refresh_secret, algorithms=[settings.jwt_algorithm])
    except JWTError as exc:
        raise TokenError("Invalid refresh token") from exc

    if payload.get("type") != "refresh" or "sub" not in payload:
        raise TokenError("Invalid refresh token payload")
    return payload


def hash_token(token: str) -> str:
    return sha256(token.encode("utf-8")).hexdigest()
