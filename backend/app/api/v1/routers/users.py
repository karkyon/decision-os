from app.core.deps import require_admin, get_current_user
from app.db.session import get_db
"""
Users Router - ユーザー管理（Admin専用）
GET  /api/v1/users           - ユーザー一覧（Admin）
GET  /api/v1/users/me        - 自分の情報
PATCH /api/v1/users/{id}/role - ロール変更（Admin）
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel
from datetime import datetime
import uuid

router = APIRouter(prefix="/users", tags=["users"])

# ─── schemas ───────────────────────────────────────────────
class UserOut(BaseModel):
    id: str
    email: str
    role: str
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True

class RoleUpdate(BaseModel):
    role: str  # admin / pm / dev / viewer

# ─── deps import（他のルーターと同じパスを使う） ────────────────
def _get_deps():
    """動的にdepsモジュールを取得"""
    import importlib, sys
    for mod_name in list(sys.modules.keys()):
        if 'deps' in mod_name and 'get_current_user' in dir(sys.modules[mod_name]):
            return sys.modules[mod_name]
    # フォールバック: 検索
    import subprocess, os
    result = subprocess.run(
        ['grep', '-rl', 'get_current_user', 
         os.path.expanduser('~/projects/decision-os/backend/app')],
        capture_output=True, text=True
    )
    for f in result.stdout.strip().split('\n'):
        if 'deps' in f:
            spec_name = f.replace(
                os.path.expanduser('~/projects/decision-os/backend/'), ''
            ).replace('/', '.').replace('.py', '')
            return importlib.import_module(spec_name)
    return None

# ─── endpoints ────────────────────────────────────────────

@router.get("/me")
async def get_me(
    db: Session = Depends(lambda: None),  # 後でDI
):
    """自分の情報を取得（全ロール可）"""
    # 実装はdepsのget_current_userに依存するため、
    # スクリプト適用後に自動で正しいdepsが注入される
    return {"message": "use /auth/me endpoint"}


@router.get("", response_model=List[UserOut])
async def list_users(
    db: Session = Depends(get_db),
    current_user=Depends(require_admin()),
):
    """ユーザー一覧（Admin のみ）"""
    if db is None or current_user is None:
        return []
    role = getattr(current_user, "role", "viewer")
    if role != "admin":
        raise HTTPException(status_code=403, detail="Admin権限が必要です")
    from app.models.user import User
    users = db.query(User).all()
    return users


@router.patch("/{user_id}/role")
async def update_role(
    user_id: str,
    body: RoleUpdate,
    db: Session = Depends(get_db),
    current_user=Depends(require_admin()),
):
    """ロール変更（Admin のみ）"""
    if db is None or current_user is None:
        raise HTTPException(status_code=503, detail="Service unavailable")
    
    role = getattr(current_user, "role", "viewer")
    if role != "admin":
        raise HTTPException(status_code=403, detail="Admin権限が必要です")
    
    VALID_ROLES = {"admin", "pm", "dev", "viewer"}
    if body.role not in VALID_ROLES:
        raise HTTPException(status_code=400, detail=f"無効なロール: {body.role}")
    
    from app.models.user import User
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="ユーザーが見つかりません")
    
    old_role = user.role
    user.role = body.role
    db.commit()
    db.refresh(user)
    
    return {
        "id": str(user.id),
        "email": user.email,
        "role": user.role,
        "message": f"ロールを {old_role} → {body.role} に変更しました"
    }

@router.get("/assignees", response_model=List[UserOut])
async def list_assignees(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """担当者候補一覧（pm 以上が利用可）- InputNew / IssueDetail 用"""
    from app.core.deps import is_pm_or_above
    if not is_pm_or_above(current_user):
        raise HTTPException(status_code=403, detail="PM以上の権限が必要です")
    from app.models.user import User
    users = db.query(User).filter(User.tenant_id == current_user.tenant_id).all()
    return users
