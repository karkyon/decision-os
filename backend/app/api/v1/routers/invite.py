from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from datetime import datetime, timedelta, timezone
from app.db.session import get_db
from app.models.invite_token import InviteToken
from app.models.user import User
from app.models.tenant import Tenant
from app.schemas.invite import InviteCreate, InviteAccept, InviteResponse, InviteAcceptResponse
from app.core.security import get_password_hash, create_access_token, create_refresh_token
from app.core.deps import get_current_user

router = APIRouter(prefix="/auth", tags=["invite"])

INVITE_EXPIRE_HOURS = 72
FRONTEND_URL = "http://localhost:3008"


@router.post("/invite", response_model=InviteResponse, status_code=201)
def create_invite(
    data: InviteCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # ロール確認（admin / pm のみ招待可能）
    if current_user.role not in ("admin", "pm"):
        raise HTTPException(status_code=403, detail="招待権限がありません（admin/pm のみ）")

    # テナント特定
    tenant_id = data.tenant_id or str(current_user.tenant_id)
    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    if not tenant:
        raise HTTPException(status_code=404, detail="tenant not found")

    # 既存の未使用招待があれば再利用
    existing = db.query(InviteToken).filter(
        InviteToken.email == data.email,
        InviteToken.tenant_id == tenant_id,
        InviteToken.used_at == None,
    ).first()
    if existing:
        db.delete(existing)
        db.commit()

    # 招待トークン作成
    expires_at = datetime.now(timezone.utc) + timedelta(hours=INVITE_EXPIRE_HOURS)
    invite = InviteToken(
        tenant_id=tenant_id,
        email=data.email,
        role=data.role,
        expires_at=expires_at,
        invited_by_id=current_user.id,
    )
    db.add(invite)
    db.commit()
    db.refresh(invite)

    invite_url = f"{FRONTEND_URL}/invite?token={invite.token}"

    # TODO: メール送信（SMTP設定後に有効化）
    # send_invite_email(data.email, invite_url, current_user.name, tenant.name)

    return InviteResponse(
        id=invite.id,
        email=invite.email,
        role=invite.role,
        token=invite.token,
        expires_at=invite.expires_at,
        invite_url=invite_url,
    )


@router.get("/invite/{token}")
def verify_invite(token: str, db: Session = Depends(get_db)):
    """招待トークンの有効性確認（フロント用）"""
    invite = db.query(InviteToken).filter(InviteToken.token == token).first()
    if not invite:
        raise HTTPException(status_code=404, detail="招待リンクが無効です")
    if invite.used_at:
        raise HTTPException(status_code=410, detail="この招待リンクは使用済みです")
    if invite.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=410, detail="招待リンクの有効期限が切れています")

    tenant = db.query(Tenant).filter(Tenant.id == invite.tenant_id).first()
    return {
        "email": invite.email,
        "role": invite.role,
        "tenant_name": tenant.name if tenant else "Unknown",
        "expires_at": invite.expires_at,
    }


@router.post("/invite/accept", response_model=InviteAcceptResponse)
def accept_invite(data: InviteAccept, db: Session = Depends(get_db)):
    """招待を受諾してアカウント作成"""
    invite = db.query(InviteToken).filter(InviteToken.token == data.token).first()
    if not invite:
        raise HTTPException(status_code=404, detail="招待リンクが無効です")
    if invite.used_at:
        raise HTTPException(status_code=410, detail="この招待リンクは使用済みです")
    if invite.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=410, detail="招待リンクの有効期限が切れています")

    # メールアドレス重複確認
    existing_user = db.query(User).filter(User.email == invite.email).first()
    if existing_user:
        raise HTTPException(status_code=409, detail="このメールアドレスは既に登録済みです")

    # ユーザ作成
    user = User(
        name=data.name,
        email=invite.email,
        hashed_password=get_password_hash(data.password),
        role=invite.role,
        tenant_id=invite.tenant_id,
        invited_by=invite.invited_by_id,
    )
    db.add(user)

    # トークン使用済みマーク
    invite.used_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(user)

    access_token = create_access_token({"sub": user.id})
    refresh_token = create_refresh_token({"sub": user.id})

    return InviteAcceptResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=user.id,
        name=user.name,
        role=user.role,
    )


@router.get("/invites")
def list_invites(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """招待一覧（admin/pm向け）"""
    if current_user.role not in ("admin", "pm"):
        raise HTTPException(status_code=403, detail="権限がありません")

    invites = db.query(InviteToken).filter(
        InviteToken.tenant_id == str(current_user.tenant_id)
    ).order_by(InviteToken.created_at.desc()).limit(50).all()

    return [
        {
            "id": i.id,
            "email": i.email,
            "role": i.role,
            "expires_at": i.expires_at,
            "used_at": i.used_at,
            "created_at": i.created_at,
            "status": "used" if i.used_at else
                      "expired" if i.expires_at < datetime.now(timezone.utc) else "pending",
        }
        for i in invites
    ]
