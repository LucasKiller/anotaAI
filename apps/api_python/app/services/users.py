from sqlalchemy.orm import Session

from app.core.secrets import SecretEncryptionError, encrypt_user_secret, mask_api_key
from app.integrations.llm.provider_config import ResolvedLlmConfig, normalize_base_url, normalize_provider_type, resolve_effective_llm_config
from app.models import User
from app.repositories import UserRepository


class UserService:
    def __init__(self, db: Session):
        self.db = db
        self.users = UserRepository(db)

    def update_name(self, *, user: User, name: str | None) -> User:
        clean_name = None
        if name is not None:
            stripped = name.strip()
            clean_name = stripped or None

        updated = self.users.update_name(user, clean_name)
        self.db.commit()
        self.db.refresh(updated)
        return updated

    def get_effective_ai_settings(self, *, user: User) -> ResolvedLlmConfig:
        return resolve_effective_llm_config(self.users.get_ai_settings(user.id))

    def update_ai_settings(
        self,
        *,
        user: User,
        provider_type: str,
        base_url: str | None,
        model: str,
        api_key: str | None,
    ) -> ResolvedLlmConfig:
        normalized_provider = normalize_provider_type(provider_type)
        normalized_model = model.strip()
        if not normalized_model:
            raise ValueError("model e obrigatorio.")

        normalized_base_url = normalize_base_url(normalized_provider, base_url)
        existing = self.users.get_ai_settings(user.id)
        existing_encrypted = existing.api_key_encrypted if existing else None
        existing_hint = existing.api_key_hint if existing else None

        cleaned_api_key = api_key.strip() if api_key else None
        if cleaned_api_key:
            try:
                api_key_encrypted = encrypt_user_secret(cleaned_api_key)
            except SecretEncryptionError as exc:
                raise ValueError(str(exc)) from exc
            api_key_hint = mask_api_key(cleaned_api_key)
        elif existing_encrypted:
            api_key_encrypted = existing_encrypted
            api_key_hint = existing_hint
        else:
            raise ValueError("api_key e obrigatoria na primeira configuracao de IA do usuario.")

        self.users.upsert_ai_settings(
            user_id=user.id,
            provider_type=normalized_provider,
            base_url=None if normalized_provider == "openai" else normalized_base_url,
            model_name=normalized_model,
            api_key_encrypted=api_key_encrypted,
            api_key_hint=api_key_hint,
        )
        self.db.commit()
        return self.get_effective_ai_settings(user=user)

    def clear_ai_settings(self, *, user: User) -> ResolvedLlmConfig:
        existing = self.users.get_ai_settings(user.id)
        if existing:
            self.users.delete_ai_settings(existing)
            self.db.commit()
        return self.get_effective_ai_settings(user=user)
