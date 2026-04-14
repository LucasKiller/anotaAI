from sqlalchemy.orm import Session

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
