from typing import Generator, Optional
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from .security import decode_token
from ..db.session import SessionLocal
from ..models.user import User

bearer_scheme = HTTPBearer()

def get_db() -> Generator:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    token = credentials.credentials
    payload = decode_token(token)
    if not payload:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user_id: str = payload.get("sub")
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user

# ─── RBAC ヘルパー ───────────────────────────────────────────────────────────
ROLE_HIERARCHY = {"admin": 4, "pm": 3, "dev": 2, "viewer": 1}

def require_role(*allowed_roles: str):
    """指定ロールのみ許可する Dependency"""
    def _checker(current_user: User = Depends(get_current_user)):
        if current_user.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"この操作には {' または '.join(allowed_roles)} 権限が必要です（現在: {current_user.role}）"
            )
        return current_user
    return _checker

def require_admin():
    return require_role("admin")

def require_pm_or_above():
    return require_role("admin", "pm")

def require_dev_or_above():
    return require_role("admin", "pm", "dev")

def is_admin(user) -> bool:
    return getattr(user, "role", "") == "admin"

def is_pm_or_above(user) -> bool:
    return getattr(user, "role", "viewer") in ("admin", "pm")

def is_dev_or_above(user) -> bool:
    return getattr(user, "role", "viewer") in ("admin", "pm", "dev")
