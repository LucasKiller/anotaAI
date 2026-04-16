from __future__ import annotations

import base64
import hashlib

from cryptography.fernet import Fernet, InvalidToken

from app.config import get_settings

settings = get_settings()


class SecretEncryptionError(RuntimeError):
    """Raised when user secrets cannot be encrypted or decrypted."""


def decrypt_user_secret(value: str) -> str:
    try:
        decrypted = _fernet().decrypt(value.encode("utf-8"))
    except InvalidToken as exc:
        raise SecretEncryptionError("Nao foi possivel descriptografar o segredo salvo.") from exc
    return decrypted.decode("utf-8")


def _fernet() -> Fernet:
    secret = (settings.ai_settings_encryption_key or settings.jwt_secret).strip()
    if not secret:
        raise SecretEncryptionError("AI_SETTINGS_ENCRYPTION_KEY ou JWT_SECRET precisam estar configurados.")

    try:
        return Fernet(secret.encode("utf-8"))
    except (ValueError, TypeError):
        digest = hashlib.sha256(secret.encode("utf-8")).digest()
        return Fernet(base64.urlsafe_b64encode(digest))
