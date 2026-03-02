"""
SSO / TOTP 認証エンドポイント
仕様設計書 A-002 (SSO) / A-003 (TOTP)
"""
import uuid
import secrets
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel

from app.db.session import get_db
from app.core.security import create_access_token, create_refresh_token, get_password_hash
from app.core.deps import get_current_user
from app.core.sso import (
    google_auth_url, google_exchange_code, google_get_userinfo,
    github_auth_url, github_exchange_code, github_get_userinfo,
)
from app.core.totp import (
    generate_totp_secret, get_totp_uri, generate_qr_base64, verify_totp
)
from app.models.user import User
from app.models.tenant import Tenant

router = APIRouter(tags=["sso", "totp"])

# ── SSO: 一時的な state 保管（本番は Redis に保存推奨）─────────
_sso_states: dict[str, str] = {}

# ── Pydantic スキーマ ─────────────────────────────────────────
class TOTPSetupResponse(BaseModel):
    secret: str
    otpauth_uri: str
    qr_base64: str

class TOTPVerifyRequest(BaseModel):
    code: str

class TOTPLoginRequest(BaseModel):
    email: str
    password: str
    totp_code: str

class SSOUserInfo(BaseModel):
    access_token: str
    refresh_token: str
    user_id: str
    name: str
    role: str
    totp_required: bool = False


# ══════════════════════════════════════════════════════════════
# Google SSO (A-002)
# ══════════════════════════════════════════════════════════════

@router.get("/auth/google", summary="Google OAuth2 ログイン開始")
def google_login():
    """Google の認証ページへリダイレクト"""
    state = secrets.token_urlsafe(16)
    _sso_states[state] = "google"
    return RedirectResponse(google_auth_url(state))


@router.get("/auth/google/callback", response_model=SSOUserInfo,
            summary="Google OAuth2 コールバック")
async def google_callback(
    code: str = Query(...),
    state: str = Query(...),
    db: Session = Depends(get_db),
):
    if state not in _sso_states:
        raise HTTPException(status_code=400, detail="Invalid OAuth state")
    _sso_states.pop(state, None)

    # トークン交換 → ユーザー情報取得
    try:
        token_data = await google_exchange_code(code)
        userinfo   = await google_get_userinfo(token_data["access_token"])
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Google OAuth error: {e}")

    email = userinfo.get("email")
    name  = userinfo.get("name", email)
    if not email:
        raise HTTPException(status_code=400, detail="Google account has no email")

    return await _sso_upsert_user(db, email=email, name=name, provider="google")


# ══════════════════════════════════════════════════════════════
# GitHub SSO (A-002)
# ══════════════════════════════════════════════════════════════

@router.get("/auth/github", summary="GitHub OAuth2 ログイン開始")
def github_login():
    """GitHub の認証ページへリダイレクト"""
    state = secrets.token_urlsafe(16)
    _sso_states[state] = "github"
    return RedirectResponse(github_auth_url(state))


@router.get("/auth/github/callback", response_model=SSOUserInfo,
            summary="GitHub OAuth2 コールバック")
async def github_callback(
    code: str = Query(...),
    state: str = Query(...),
    db: Session = Depends(get_db),
):
    if state not in _sso_states:
        raise HTTPException(status_code=400, detail="Invalid OAuth state")
    _sso_states.pop(state, None)

    try:
        token_data = await github_exchange_code(code)
        userinfo   = await github_get_userinfo(token_data["access_token"])
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"GitHub OAuth error: {e}")

    email = userinfo.get("email")
    name  = userinfo.get("name") or userinfo.get("login", "")
    if not email:
        raise HTTPException(status_code=400, detail="GitHub account email is private. Please make it public.")

    return await _sso_upsert_user(db, email=email, name=name, provider="github")


async def _sso_upsert_user(db: Session, email: str, name: str, provider: str) -> dict:
    """SSO 共通: メールでユーザを検索 → なければ作成。JWTを返す。"""
    user = db.query(User).filter(User.email == email).first()

    if not user:
        # default テナントに紐づけ
        default_tenant = db.query(Tenant).filter(Tenant.slug == "default").first()
        user = User(
            id=uuid.uuid4(),
            email=email,
            name=name,
            hashed_password=get_password_hash(secrets.token_urlsafe(32)),  # SSO はパスワードなし
            role="dev",
            tenant_id=default_tenant.id if default_tenant else None,
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    # TOTP 有効化済みなら totp_required フラグを立てる
    if user.totp_secret:
        return {
            "access_token": "",
            "refresh_token": "",
            "user_id": str(user.id),
            "name": user.name,
            "role": user.role,
            "totp_required": True,
        }

    access_token  = create_access_token({"sub": str(user.id)})
    refresh_token = create_refresh_token({"sub": str(user.id)})
    return {
        "access_token":  access_token,
        "refresh_token": refresh_token,
        "user_id":       str(user.id),
        "name":          user.name,
        "role":          user.role,
        "totp_required": False,
    }


# ══════════════════════════════════════════════════════════════
# TOTP 2FA (A-003)
# ══════════════════════════════════════════════════════════════

@router.post("/auth/totp/setup", response_model=TOTPSetupResponse,
             summary="TOTP 2FA セットアップ（QRコード発行）")
def totp_setup(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    ログイン済みユーザーの 2FA を有効化する。
    secret を保存し QRコードと otpauth URI を返す。
    フロントは QR を表示し、ユーザーに Authenticator でスキャンさせる。
    """
    if current_user.totp_secret:
        raise HTTPException(status_code=400, detail="TOTP is already enabled. Disable first.")

    secret = generate_totp_secret()
    current_user.totp_secret = secret
    db.commit()

    return {
        "secret":      secret,
        "otpauth_uri": get_totp_uri(secret, current_user.email),
        "qr_base64":   generate_qr_base64(secret, current_user.email),
    }


@router.post("/auth/totp/verify", summary="TOTP コード検証（有効化確認）")
def totp_verify(
    req: TOTPVerifyRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    セットアップ後、Authenticator のコードを入力して 2FA を確定する。
    """
    if not current_user.totp_secret:
        raise HTTPException(status_code=400, detail="TOTP is not set up")
    if not verify_totp(current_user.totp_secret, req.code):
        raise HTTPException(status_code=401, detail="Invalid TOTP code")
    return {"message": "TOTP verified. 2FA is now active."}


@router.delete("/auth/totp", summary="TOTP 2FA 無効化")
def totp_disable(
    req: TOTPVerifyRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """現在の TOTP コードを確認してから 2FA を無効化する"""
    if not current_user.totp_secret:
        raise HTTPException(status_code=400, detail="TOTP is not enabled")
    if not verify_totp(current_user.totp_secret, req.code):
        raise HTTPException(status_code=401, detail="Invalid TOTP code")

    current_user.totp_secret = None
    db.commit()
    return {"message": "TOTP disabled."}


@router.post("/auth/totp/login", response_model=SSOUserInfo,
             summary="TOTP コード付きログイン（通常ログイン後の 2FA ステップ）")
def totp_login(
    req: TOTPLoginRequest,
    db: Session = Depends(get_db),
):
    """
    2FA 有効ユーザーのログイン:
    1. メール+パスワードを検証
    2. TOTP コードを検証
    3. 両方 OK ならトークン発行
    """
    from app.core.security import verify_password
    user = db.query(User).filter(User.email == req.email).first()
    if not user or not verify_password(req.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    if not user.totp_secret:
        raise HTTPException(status_code=400, detail="TOTP is not enabled for this user")

    if not verify_totp(user.totp_secret, req.totp_code):
        raise HTTPException(status_code=401, detail="Invalid TOTP code")

    access_token  = create_access_token({"sub": str(user.id)})
    refresh_token = create_refresh_token({"sub": str(user.id)})
    return {
        "access_token":  access_token,
        "refresh_token": refresh_token,
        "user_id":       str(user.id),
        "name":          user.name,
        "role":          user.role,
        "totp_required": False,
    }
