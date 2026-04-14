from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import RefreshToken, User


class UserRepository:
    def __init__(self, db: Session):
        self.db = db

    def get_by_email(self, email: str) -> User | None:
        stmt = select(User).where(User.email == email)
        return self.db.scalar(stmt)

    def get_by_id(self, user_id: UUID) -> User | None:
        return self.db.get(User, user_id)

    def create(self, email: str, password_hash: str, name: str | None = None) -> User:
        user = User(email=email, password_hash=password_hash, name=name)
        self.db.add(user)
        self.db.flush()
        return user

    def touch_last_login(self, user: User) -> None:
        user.last_login_at = datetime.now(UTC)
        self.db.add(user)

    def update_name(self, user: User, name: str | None) -> User:
        user.name = name
        self.db.add(user)
        self.db.flush()
        return user


class RefreshTokenRepository:
    def __init__(self, db: Session):
        self.db = db

    def create(self, user_id: UUID, token_hash: str, expires_at: datetime) -> RefreshToken:
        token = RefreshToken(user_id=user_id, token_hash=token_hash, expires_at=expires_at)
        self.db.add(token)
        self.db.flush()
        return token

    def get_valid(self, token_hash: str) -> RefreshToken | None:
        stmt = select(RefreshToken).where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.revoked_at.is_(None),
            RefreshToken.expires_at > datetime.now(UTC),
        )
        return self.db.scalar(stmt)

    def revoke(self, token: RefreshToken) -> None:
        token.revoked_at = datetime.now(UTC)
        self.db.add(token)
