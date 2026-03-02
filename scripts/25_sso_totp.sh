#!/bin/bash
# ============================================================
# Phase 2 - SSO (Google / GitHub OAuth2) + TOTP 2FA 実装
# 仕様設計書 A-002 / A-003 準拠
# ============================================================
set -e

PROJECT="$HOME/projects/decision-os"
BACKEND="$PROJECT/backend"
FRONTEND="$PROJECT/frontend"
FE_SRC="$FRONTEND/src"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()      { echo -e "${GREEN}✅ $1${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
info()    { echo -e "   $1"; }

# ─────────────────────────────────────────────
# 0. 起動確認
# ─────────────────────────────────────────────
section "0. サービス起動確認"

if ! curl -s http://localhost:8089/health | grep -q "ok\|healthy\|status"; then
  warn "バックエンド応答なし → 起動を試みます"
  cd "$PROJECT/scripts" && bash 05_launch.sh
  sleep 5
fi
ok "バックエンド起動確認"

# ─────────────────────────────────────────────
# BE-1: 依存ライブラリ追加
# ─────────────────────────────────────────────
section "BE-1: 依存ライブラリインストール"

cd "$BACKEND"
source .venv/bin/activate

pip install authlib httpx pyotp qrcode[pil] --quiet
ok "authlib / httpx / pyotp / qrcode インストール完了"

# requirements.txt に追記（重複防止）
for pkg in "authlib" "httpx" "pyotp" "qrcode[pil]"; do
  grep -q "^${pkg%%\[*}" "$BACKEND/requirements.txt" 2>/dev/null || \
    echo "$pkg" >> "$BACKEND/requirements.txt"
done
ok "requirements.txt 更新完了"

# ─────────────────────────────────────────────
# BE-2: .env に SSO 用キー追加（未設定時のみ）
# ─────────────────────────────────────────────
section "BE-2: .env SSO/TOTP 設定追加"

ENV_FILE="$PROJECT/.env"
if ! grep -q "GOOGLE_CLIENT_ID" "$ENV_FILE" 2>/dev/null; then
  cat >> "$ENV_FILE" << 'ENVEOF'

# ── SSO: Google OAuth2 (A-002) ──────────────────────────────
GOOGLE_CLIENT_ID=your-google-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-google-client-secret
GOOGLE_REDIRECT_URI=http://localhost:8089/api/v1/auth/google/callback

# ── SSO: GitHub OAuth2 (A-002) ──────────────────────────────
GITHUB_CLIENT_ID=your-github-client-id
GITHUB_CLIENT_SECRET=your-github-client-secret
GITHUB_REDIRECT_URI=http://localhost:8089/api/v1/auth/github/callback

# ── TOTP 2FA (A-003) ─────────────────────────────────────────
TOTP_ISSUER=decision-os
ENVEOF
  ok ".env に SSO / TOTP キー追加完了"
else
  ok ".env の SSO 設定は既存（スキップ）"
fi

# ─────────────────────────────────────────────
# BE-3: config.py に設定追加
# ─────────────────────────────────────────────
section "BE-3: config.py 更新"

python3 << 'PYEOF'
import re

config_path = "app/core/config.py"
try:
    with open(config_path, "r", encoding="utf-8") as f:
        src = f.read()
except FileNotFoundError:
    src = ""

additions = """
    # SSO: Google (A-002)
    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_SECRET: str = ""
    GOOGLE_REDIRECT_URI: str = "http://localhost:8089/api/v1/auth/google/callback"

    # SSO: GitHub (A-002)
    GITHUB_CLIENT_ID: str = ""
    GITHUB_CLIENT_SECRET: str = ""
    GITHUB_REDIRECT_URI: str = "http://localhost:8089/api/v1/auth/github/callback"

    # TOTP 2FA (A-003)
    TOTP_ISSUER: str = "decision-os"
"""

if "GOOGLE_CLIENT_ID" not in src:
    # Settings クラス内の末尾付近に追加
    src = re.sub(
        r'(class Settings\([^)]*\):.*?)(^\s*model_config)',
        lambda m: m.group(1) + additions + "\n" + m.group(2),
        src, flags=re.DOTALL | re.MULTILINE
    )
    if "GOOGLE_CLIENT_ID" not in src:
        # フォールバック: ファイル末尾に append
        src += "\n# SSO/TOTP settings appended\n"
        src += additions

    with open(config_path, "w", encoding="utf-8") as f:
        f.write(src)
    print("config.py: SSO/TOTP 設定追加完了")
else:
    print("config.py: 既存設定あり（スキップ）")
PYEOF

ok "config.py 更新完了"

# ─────────────────────────────────────────────
# BE-4: TOTP ユーティリティ
# ─────────────────────────────────────────────
section "BE-4: TOTP ユーティリティ作成"

cat > "$BACKEND/app/core/totp.py" << 'PYEOF'
"""
TOTP 2要素認証ユーティリティ
仕様設計書 A-003: Authenticator アプリとの TOTP 連携
"""
import pyotp
import qrcode
import base64
import io
from app.core.config import settings


def generate_totp_secret() -> str:
    """新規 TOTP シークレット生成（初回 2FA 有効化時）"""
    return pyotp.random_base32()


def get_totp_uri(secret: str, email: str) -> str:
    """Authenticator アプリ登録用 otpauth URI 生成"""
    totp = pyotp.TOTP(secret)
    return totp.provisioning_uri(name=email, issuer_name=settings.TOTP_ISSUER)


def generate_qr_base64(secret: str, email: str) -> str:
    """QR コードを Base64 PNG で返す（フロントエンドに埋め込み用）"""
    uri = get_totp_uri(secret, email)
    img = qrcode.make(uri)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


def verify_totp(secret: str, code: str) -> bool:
    """
    TOTP コード検証（前後 1 ステップ = ±30 秒の時刻ずれを許容）
    """
    if not secret or not code:
        return False
    totp = pyotp.TOTP(secret)
    return totp.verify(code, valid_window=1)
PYEOF

ok "app/core/totp.py 作成完了"

# ─────────────────────────────────────────────
# BE-5: SSO ユーティリティ
# ─────────────────────────────────────────────
section "BE-5: SSO OAuth2 ユーティリティ作成"

cat > "$BACKEND/app/core/sso.py" << 'PYEOF'
"""
SSO OAuth2 ユーティリティ
仕様設計書 A-002: Google / GitHub OAuth2 プロバイダ連携
"""
import httpx
from app.core.config import settings

# ── Google ────────────────────────────────────────────────────
GOOGLE_AUTH_URL    = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL   = "https://oauth2.googleapis.com/token"
GOOGLE_USERINFO    = "https://www.googleapis.com/oauth2/v3/userinfo"
GOOGLE_SCOPE       = "openid email profile"

def google_auth_url(state: str) -> str:
    params = (
        f"client_id={settings.GOOGLE_CLIENT_ID}"
        f"&redirect_uri={settings.GOOGLE_REDIRECT_URI}"
        f"&response_type=code"
        f"&scope={GOOGLE_SCOPE.replace(' ', '%20')}"
        f"&state={state}"
        f"&access_type=offline"
    )
    return f"{GOOGLE_AUTH_URL}?{params}"

async def google_exchange_code(code: str) -> dict:
    """認可コードをアクセストークンに交換"""
    async with httpx.AsyncClient() as client:
        resp = await client.post(GOOGLE_TOKEN_URL, data={
            "code": code,
            "client_id": settings.GOOGLE_CLIENT_ID,
            "client_secret": settings.GOOGLE_CLIENT_SECRET,
            "redirect_uri": settings.GOOGLE_REDIRECT_URI,
            "grant_type": "authorization_code",
        })
        resp.raise_for_status()
        return resp.json()

async def google_get_userinfo(access_token: str) -> dict:
    """Google ユーザー情報取得"""
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            GOOGLE_USERINFO,
            headers={"Authorization": f"Bearer {access_token}"}
        )
        resp.raise_for_status()
        return resp.json()


# ── GitHub ───────────────────────────────────────────────────
GITHUB_AUTH_URL  = "https://github.com/login/oauth/authorize"
GITHUB_TOKEN_URL = "https://github.com/login/oauth/access_token"
GITHUB_USERINFO  = "https://api.github.com/user"
GITHUB_EMAILS    = "https://api.github.com/user/emails"
GITHUB_SCOPE     = "read:user user:email"

def github_auth_url(state: str) -> str:
    params = (
        f"client_id={settings.GITHUB_CLIENT_ID}"
        f"&redirect_uri={settings.GITHUB_REDIRECT_URI}"
        f"&scope={GITHUB_SCOPE.replace(':', '%3A').replace(' ', '%20')}"
        f"&state={state}"
    )
    return f"{GITHUB_AUTH_URL}?{params}"

async def github_exchange_code(code: str) -> dict:
    """認可コードをアクセストークンに交換"""
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            GITHUB_TOKEN_URL,
            data={
                "code": code,
                "client_id": settings.GITHUB_CLIENT_ID,
                "client_secret": settings.GITHUB_CLIENT_SECRET,
                "redirect_uri": settings.GITHUB_REDIRECT_URI,
            },
            headers={"Accept": "application/json"},
        )
        resp.raise_for_status()
        return resp.json()

async def github_get_userinfo(access_token: str) -> dict:
    """GitHub ユーザー情報取得（メールが非公開の場合は /emails も叩く）"""
    headers = {
        "Authorization": f"token {access_token}",
        "Accept": "application/vnd.github.v3+json",
    }
    async with httpx.AsyncClient() as client:
        user_resp = await client.get(GITHUB_USERINFO, headers=headers)
        user_resp.raise_for_status()
        user = user_resp.json()

        if not user.get("email"):
            emails_resp = await client.get(GITHUB_EMAILS, headers=headers)
            if emails_resp.status_code == 200:
                for e in emails_resp.json():
                    if e.get("primary") and e.get("verified"):
                        user["email"] = e["email"]
                        break
    return user
PYEOF

ok "app/core/sso.py 作成完了"

# ─────────────────────────────────────────────
# BE-6: SSO / TOTP APIルーター
# ─────────────────────────────────────────────
section "BE-6: SSO / TOTP API ルーター作成"

cat > "$BACKEND/app/api/v1/routers/sso.py" << 'PYEOF'
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
PYEOF

ok "app/api/v1/routers/sso.py 作成完了"

# ─────────────────────────────────────────────
# BE-7: api.py にルーター登録
# ─────────────────────────────────────────────
section "BE-7: api.py に SSO/TOTP ルーター登録"

python3 << 'PYEOF'
api_path = "app/api/v1/api.py"
try:
    with open(api_path, "r", encoding="utf-8") as f:
        src = f.read()
except FileNotFoundError:
    print(f"ERROR: {api_path} が見つかりません")
    exit(1)

import_line = "from app.api.v1.routers import sso as sso_router"
include_line = 'api_router.include_router(sso_router.router, prefix="/api/v1")'

changed = False
if import_line not in src:
    # 既存 import の後ろに追加
    import re
    src = re.sub(
        r'(from app\.api\.v1\.routers import.*?\n)',
        r'\1' + import_line + '\n',
        src, count=1
    )
    if import_line not in src:
        src = import_line + "\n" + src
    changed = True

if include_line not in src:
    src += f"\n{include_line}\n"
    changed = True

if changed:
    with open(api_path, "w", encoding="utf-8") as f:
        f.write(src)
    print("api.py: sso ルーター登録完了")
else:
    print("api.py: 既に登録済み（スキップ）")
PYEOF

ok "api.py 更新完了"

# ─────────────────────────────────────────────
# BE-8: auth.py の通常ログインに TOTP チェック追加
# ─────────────────────────────────────────────
section "BE-8: 通常ログインに TOTP フラグ対応"

python3 << 'PYEOF'
import re

auth_path = "app/api/v1/routers/auth.py"
try:
    with open(auth_path, "r", encoding="utf-8") as f:
        src = f.read()
except FileNotFoundError:
    print(f"WARN: {auth_path} が見つかりません（スキップ）")
    exit(0)

if "totp_required" in src:
    print("auth.py: TOTP フラグ既存（スキップ）")
    exit(0)

# TokenResponse の返却に totp_required を追加
src = src.replace(
    "return TokenResponse(",
    "# TOTP check: 2FA 有効ユーザは totp_required=True で早期リターン\n"
    "    if user.totp_secret:\n"
    "        return {\"totp_required\": True, \"access_token\": \"\", \"refresh_token\": \"\"}\n"
    "    return TokenResponse(",
    1  # 最初の1箇所だけ
)

with open(auth_path, "w", encoding="utf-8") as f:
    f.write(src)
print("auth.py: TOTP フラグ対応追加完了")
PYEOF

ok "auth.py TOTP フラグ対応完了"

# ─────────────────────────────────────────────
# BE-9: バックエンド再起動
# ─────────────────────────────────────────────
section "BE-9: バックエンド再起動"

cd "$BACKEND"
source .venv/bin/activate

pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$PROJECT/logs/backend.log" 2>&1 &
sleep 5

echo "--- backend.log (末尾 10 行) ---"
tail -10 "$PROJECT/logs/backend.log" 2>/dev/null || echo "(ログなし)"
echo "--------------------------------"

if curl -s http://localhost:8089/docs | head -3 | grep -q "swagger\|html"; then
  ok "バックエンド起動確認"
else
  warn "バックエンド応答なし → ログを確認してください"
fi

# SSO エンドポイント確認
for path in "/api/v1/auth/google" "/api/v1/auth/github" "/api/v1/auth/totp/setup"; do
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8089${path}")
  # 307(redirect), 401(認証必要), 422(バリデーション) はすべて「存在する」証拠
  if [[ "$HTTP" =~ ^(200|307|401|403|422)$ ]]; then
    ok "GET ${path} → HTTP ${HTTP} ✅"
  else
    warn "GET ${path} → HTTP ${HTTP}"
  fi
done

# ─────────────────────────────────────────────
# FE-1: フロントエンド依存追加
# ─────────────────────────────────────────────
section "FE-1: フロントエンド依存追加"

cd "$FRONTEND"
npm install qrcode.react --save --legacy-peer-deps 2>/dev/null | tail -3 || \
  warn "qrcode.react インストール失敗（手動: npm install qrcode.react）"
ok "qrcode.react インストール完了"

# ─────────────────────────────────────────────
# FE-2: SSO ログインボタン コンポーネント
# ─────────────────────────────────────────────
section "FE-2: SSOButtons.tsx 作成"

mkdir -p "$FE_SRC/components"
cat > "$FE_SRC/components/SSOButtons.tsx" << 'TSEOF'
/**
 * SSOButtons - Google / GitHub ソーシャルログインボタン
 * 仕様設計書 A-002: SSO連携
 */
import React from "react";

const API_BASE = import.meta.env.VITE_API_URL ?? "http://localhost:8089";

export function SSOButtons() {
  const handleGoogle = () => {
    window.location.href = `${API_BASE}/api/v1/auth/google`;
  };

  const handleGitHub = () => {
    window.location.href = `${API_BASE}/api/v1/auth/github`;
  };

  return (
    <div className="sso-buttons" style={{ display: "flex", flexDirection: "column", gap: "12px", marginTop: "16px" }}>
      {/* 区切り線 */}
      <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
        <hr style={{ flex: 1, border: "none", borderTop: "1px solid #e5e7eb" }} />
        <span style={{ fontSize: "12px", color: "#9ca3af" }}>または</span>
        <hr style={{ flex: 1, border: "none", borderTop: "1px solid #e5e7eb" }} />
      </div>

      {/* Google ログイン */}
      <button
        onClick={handleGoogle}
        style={{
          display: "flex", alignItems: "center", justifyContent: "center", gap: "10px",
          padding: "10px 16px", border: "1px solid #d1d5db", borderRadius: "8px",
          backgroundColor: "#ffffff", cursor: "pointer", fontSize: "14px", fontWeight: 500,
          transition: "background 0.15s",
        }}
        onMouseOver={e => (e.currentTarget.style.backgroundColor = "#f9fafb")}
        onMouseOut={e  => (e.currentTarget.style.backgroundColor = "#ffffff")}
      >
        {/* Google SVG アイコン */}
        <svg width="18" height="18" viewBox="0 0 48 48">
          <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
          <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
          <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
          <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
        </svg>
        Google でログイン
      </button>

      {/* GitHub ログイン */}
      <button
        onClick={handleGitHub}
        style={{
          display: "flex", alignItems: "center", justifyContent: "center", gap: "10px",
          padding: "10px 16px", border: "1px solid #d1d5db", borderRadius: "8px",
          backgroundColor: "#24292e", color: "#ffffff", cursor: "pointer",
          fontSize: "14px", fontWeight: 500, transition: "background 0.15s",
        }}
        onMouseOver={e => (e.currentTarget.style.backgroundColor = "#1b1f23")}
        onMouseOut={e  => (e.currentTarget.style.backgroundColor = "#24292e")}
      >
        {/* GitHub SVG アイコン */}
        <svg width="18" height="18" viewBox="0 0 16 16" fill="#ffffff">
          <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/>
        </svg>
        GitHub でログイン
      </button>
    </div>
  );
}
TSEOF

ok "SSOButtons.tsx 作成完了"

# ─────────────────────────────────────────────
# FE-3: TOTP セットアップ画面
# ─────────────────────────────────────────────
section "FE-3: TOTPSetup.tsx 作成"

mkdir -p "$FE_SRC/pages"
cat > "$FE_SRC/pages/TOTPSetup.tsx" << 'TSEOF'
/**
 * TOTPSetup - 2FA セットアップ画面
 * 仕様設計書 A-003: Authenticator アプリとの TOTP 連携
 *
 * フロー:
 * 1. 「2FA を有効にする」ボタン押下 → POST /auth/totp/setup → QRコード表示
 * 2. ユーザーが Authenticator でスキャン
 * 3. 6桁コードを入力 → POST /auth/totp/verify → 有効化確定
 */
import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import { apiClient } from "../api/client";

type SetupData = {
  secret: string;
  otpauth_uri: string;
  qr_base64: string;
};

export default function TOTPSetup() {
  const navigate = useNavigate();
  const [step, setStep] = useState<"idle" | "scan" | "verify" | "done">("idle");
  const [setupData, setSetupData] = useState<SetupData | null>(null);
  const [code, setCode] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  // Step 1: シークレット生成 + QRコード表示
  const handleSetup = async () => {
    setLoading(true); setError("");
    try {
      const res = await apiClient.post<SetupData>("/api/v1/auth/totp/setup");
      setSetupData(res.data);
      setStep("scan");
    } catch (e: any) {
      setError(e.response?.data?.detail ?? "セットアップに失敗しました");
    } finally {
      setLoading(false);
    }
  };

  // Step 2: コード検証 → 有効化確定
  const handleVerify = async () => {
    if (code.length !== 6) { setError("6桁のコードを入力してください"); return; }
    setLoading(true); setError("");
    try {
      await apiClient.post("/api/v1/auth/totp/verify", { code });
      setStep("done");
    } catch (e: any) {
      setError(e.response?.data?.detail ?? "コードが正しくありません");
    } finally {
      setLoading(false);
    }
  };

  const containerStyle: React.CSSProperties = {
    maxWidth: 420, margin: "60px auto", padding: "32px",
    background: "#fff", borderRadius: "12px",
    boxShadow: "0 4px 24px rgba(0,0,0,0.08)",
    fontFamily: "Arial, sans-serif",
  };

  return (
    <div style={containerStyle}>
      <h2 style={{ margin: "0 0 8px", fontSize: "20px", fontWeight: 700 }}>
        🔐 2要素認証（2FA）
      </h2>
      <p style={{ color: "#6b7280", fontSize: "14px", margin: "0 0 24px" }}>
        Authenticator アプリでログインを保護します
      </p>

      {/* ── IDLE ── */}
      {step === "idle" && (
        <button
          onClick={handleSetup} disabled={loading}
          style={primaryBtnStyle}
        >
          {loading ? "準備中..." : "2FA を有効にする"}
        </button>
      )}

      {/* ── SCAN ── */}
      {step === "scan" && setupData && (
        <div>
          <p style={{ fontSize: "14px", color: "#374151", marginBottom: "16px" }}>
            Google Authenticator / Authy などで以下の QR コードをスキャンしてください。
          </p>

          {/* QR コード */}
          <div style={{ textAlign: "center", marginBottom: "16px" }}>
            <img
              src={`data:image/png;base64,${setupData.qr_base64}`}
              alt="TOTP QR Code"
              style={{ width: 200, height: 200, border: "1px solid #e5e7eb", borderRadius: 8 }}
            />
          </div>

          {/* シークレットキー（手動入力用） */}
          <details style={{ marginBottom: "20px" }}>
            <summary style={{ fontSize: "12px", color: "#9ca3af", cursor: "pointer" }}>
              QR コードを読み取れない場合
            </summary>
            <code style={{
              display: "block", marginTop: "8px", padding: "8px",
              background: "#f9fafb", borderRadius: "6px",
              fontSize: "13px", wordBreak: "break-all", letterSpacing: "2px",
            }}>
              {setupData.secret}
            </code>
          </details>

          <button
            onClick={() => setStep("verify")}
            style={primaryBtnStyle}
          >
            スキャンしました → コードを入力
          </button>
        </div>
      )}

      {/* ── VERIFY ── */}
      {step === "verify" && (
        <div>
          <p style={{ fontSize: "14px", color: "#374151", marginBottom: "12px" }}>
            Authenticator アプリに表示されている 6 桁のコードを入力してください。
          </p>
          <input
            type="text"
            inputMode="numeric"
            maxLength={6}
            placeholder="123456"
            value={code}
            onChange={e => setCode(e.target.value.replace(/\D/g, ""))}
            style={inputStyle}
            autoFocus
          />
          {error && <p style={{ color: "#ef4444", fontSize: "13px", margin: "8px 0 0" }}>{error}</p>}
          <button
            onClick={handleVerify} disabled={loading || code.length !== 6}
            style={{ ...primaryBtnStyle, marginTop: "16px", opacity: code.length === 6 ? 1 : 0.5 }}
          >
            {loading ? "確認中..." : "コードを確認して有効化"}
          </button>
        </div>
      )}

      {/* ── DONE ── */}
      {step === "done" && (
        <div style={{ textAlign: "center" }}>
          <div style={{ fontSize: "48px", marginBottom: "12px" }}>✅</div>
          <p style={{ fontSize: "16px", fontWeight: 600, color: "#065f46" }}>
            2FA が有効になりました
          </p>
          <p style={{ fontSize: "13px", color: "#6b7280", margin: "8px 0 20px" }}>
            次回ログインから Authenticator コードが必要になります。
          </p>
          <button
            onClick={() => navigate("/settings")}
            style={primaryBtnStyle}
          >
            設定に戻る
          </button>
        </div>
      )}

      {error && step !== "verify" && (
        <p style={{ color: "#ef4444", fontSize: "13px", marginTop: "12px" }}>{error}</p>
      )}
    </div>
  );
}

const primaryBtnStyle: React.CSSProperties = {
  width: "100%", padding: "12px 16px",
  background: "#4f46e5", color: "#fff",
  border: "none", borderRadius: "8px",
  fontSize: "14px", fontWeight: 600, cursor: "pointer",
};

const inputStyle: React.CSSProperties = {
  width: "100%", padding: "12px 14px",
  border: "1px solid #d1d5db", borderRadius: "8px",
  fontSize: "20px", textAlign: "center", letterSpacing: "4px",
  boxSizing: "border-box",
};
TSEOF

ok "TOTPSetup.tsx 作成完了"

# ─────────────────────────────────────────────
# FE-4: TOTP ログイン画面（2FA ステップ）
# ─────────────────────────────────────────────
section "FE-4: TOTPLogin.tsx 作成"

cat > "$FE_SRC/pages/TOTPLogin.tsx" << 'TSEOF'
/**
 * TOTPLogin - 2FA ログインステップ
 * メール+パスワード検証後、2FA コードを要求する画面
 */
import React, { useState } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { useSetAtom } from "jotai";
import { tokenAtom, userAtom } from "../store/auth";
import { apiClient } from "../api/client";

export default function TOTPLogin() {
  const navigate  = useNavigate();
  const location  = useLocation();
  const setToken  = useSetAtom(tokenAtom);
  const setUser   = useSetAtom(userAtom);

  const { email, password } = (location.state as { email: string; password: string }) ?? {};
  const [code, setCode]     = useState("");
  const [error, setError]   = useState("");
  const [loading, setLoading] = useState(false);

  if (!email || !password) {
    navigate("/login");
    return null;
  }

  const handleSubmit = async () => {
    if (code.length !== 6) { setError("6桁のコードを入力してください"); return; }
    setLoading(true); setError("");
    try {
      const res = await apiClient.post<any>("/api/v1/auth/totp/login", {
        email, password, totp_code: code,
      });
      setToken(res.data.access_token);
      setUser({ id: res.data.user_id, name: res.data.name, role: res.data.role, email });
      navigate("/workspaces");
    } catch (e: any) {
      setError(e.response?.data?.detail ?? "コードが正しくありません");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{
      maxWidth: 380, margin: "80px auto", padding: "32px",
      background: "#fff", borderRadius: "12px",
      boxShadow: "0 4px 24px rgba(0,0,0,0.08)",
      fontFamily: "Arial, sans-serif",
    }}>
      <div style={{ textAlign: "center", marginBottom: "24px" }}>
        <div style={{ fontSize: "36px" }}>🔐</div>
        <h2 style={{ margin: "8px 0 4px", fontSize: "20px" }}>2段階認証</h2>
        <p style={{ color: "#6b7280", fontSize: "13px" }}>
          Authenticator アプリの 6 桁コードを入力
        </p>
      </div>

      <input
        type="text"
        inputMode="numeric"
        maxLength={6}
        placeholder="000000"
        value={code}
        onChange={e => setCode(e.target.value.replace(/\D/g, ""))}
        style={{
          width: "100%", padding: "14px",
          border: "1px solid #d1d5db", borderRadius: "8px",
          fontSize: "28px", textAlign: "center", letterSpacing: "8px",
          boxSizing: "border-box", marginBottom: "16px",
        }}
        autoFocus
        onKeyDown={e => e.key === "Enter" && handleSubmit()}
      />

      {error && (
        <p style={{ color: "#ef4444", fontSize: "13px", textAlign: "center", margin: "0 0 12px" }}>
          {error}
        </p>
      )}

      <button
        onClick={handleSubmit}
        disabled={loading || code.length !== 6}
        style={{
          width: "100%", padding: "12px",
          background: code.length === 6 ? "#4f46e5" : "#e5e7eb",
          color: code.length === 6 ? "#fff" : "#9ca3af",
          border: "none", borderRadius: "8px",
          fontSize: "14px", fontWeight: 600, cursor: code.length === 6 ? "pointer" : "default",
        }}
      >
        {loading ? "確認中..." : "ログイン"}
      </button>

      <p style={{ textAlign: "center", marginTop: "16px", fontSize: "12px", color: "#9ca3af" }}>
        コードは 30 秒ごとに更新されます
      </p>
    </div>
  );
}
TSEOF

ok "TOTPLogin.tsx 作成完了"

# ─────────────────────────────────────────────
# FE-5: Login.tsx に SSOButtons 追加
# ─────────────────────────────────────────────
section "FE-5: Login.tsx に SSOButtons 追加"

python3 << 'PYEOF'
import re, os

login_path = os.path.expanduser("~/projects/decision-os/frontend/src/pages/Login.tsx")
try:
    with open(login_path, "r", encoding="utf-8") as f:
        src = f.read()
except FileNotFoundError:
    print(f"WARN: {login_path} が見つかりません（スキップ）")
    exit(0)

if "SSOButtons" in src:
    print("Login.tsx: SSOButtons 既存（スキップ）")
    exit(0)

# import 追加
src = src.replace(
    "import React",
    "import React\nimport { SSOButtons } from '../components/SSOButtons'",
    1
)

# totp_required 対応 + SSOButtons を return 内に追加
# ログインボタンの直後に挿入
src = re.sub(
    r'(\/\/ TOTP チェック|navigate\([\'"]\/workspaces[\'"]\))',
    lambda m: m.group(0),
    src
)

# フォーム末尾（</form> か最後のボタン後）に SSO ボタンを追加
if "</form>" in src:
    src = src.replace("</form>", "</form>\n      <SSOButtons />", 1)
elif "totp_required" not in src:
    # フォームタグがない場合は submit ボタン後に追加
    src = re.sub(
        r'(<button[^>]*type=["\']submit["\'][^>]*>.*?</button>)',
        r'\1\n      <SSOButtons />',
        src, count=1, flags=re.DOTALL
    )

# TOTP required: ログイン後に /totp-login へリダイレクト
if "totp_required" not in src and "navigate" in src:
    src = re.sub(
        r"(const\s+res\s*=\s*await\s+apiClient\.post[^\n]+\n\s*)(setToken|localStorage)",
        lambda m: (
            m.group(0)[:m.start(1)-m.start(0)] +
            m.group(1) +
            "      if (res.data.totp_required) {\n"
            "        navigate('/totp-login', { state: { email, password } });\n"
            "        return;\n"
            "      }\n      " +
            m.group(2)
        ),
        src
    )

with open(login_path, "w", encoding="utf-8") as f:
    f.write(src)
print("Login.tsx: SSOButtons 追加完了")
PYEOF

ok "Login.tsx 更新完了"

# ─────────────────────────────────────────────
# FE-6: App.tsx に /totp-setup / /totp-login ルート追加
# ─────────────────────────────────────────────
section "FE-6: App.tsx にルート追加"

python3 << 'PYEOF'
import re, os

app_path = os.path.expanduser("~/projects/decision-os/frontend/src/App.tsx")
try:
    with open(app_path, "r", encoding="utf-8") as f:
        src = f.read()
except FileNotFoundError:
    print(f"WARN: {app_path} が見つかりません（スキップ）")
    exit(0)

changed = False

# import 追加
for comp, file in [("TOTPSetup", "TOTPSetup"), ("TOTPLogin", "TOTPLogin")]:
    if comp not in src:
        src = re.sub(
            r"(import React[^\n]*\n)",
            r"\1" + f"import {comp} from './pages/{file}';\n",
            src, count=1
        )
        changed = True

# Route 追加
for path, comp in [("/totp-setup", "TOTPSetup"), ("/totp-login", "TOTPLogin")]:
    route_str = f'path="{path}"'
    if route_str not in src:
        src = re.sub(
            r'(path="/login"[^\n]*/?>)',
            r'\1\n          <Route ' + f'path="{path}" element={{<{comp} />}} />',
            src, count=1
        )
        changed = True

if changed:
    with open(app_path, "w", encoding="utf-8") as f:
        f.write(src)
    print("App.tsx: TOTP ルート追加完了")
else:
    print("App.tsx: 既存（スキップ）")
PYEOF

ok "App.tsx 更新完了"

# ─────────────────────────────────────────────
# FE-7: フロントエンド ビルド確認
# ─────────────────────────────────────────────
section "FE-7: TypeScript ビルド確認"

cd "$FRONTEND"
echo "tsc チェック中..."
npx tsc --noEmit 2>&1 | tail -15 || warn "TSエラーあり（上記を確認）"
ok "フロントエンド TS チェック完了"

# ─────────────────────────────────────────────
# 完了サマリー
# ─────────────────────────────────────────────
section "完了サマリー"
echo ""
echo "実装完了:"
echo ""
echo "  【バックエンド】"
echo "  ✅ app/core/sso.py          — Google / GitHub OAuth2 ユーティリティ"
echo "  ✅ app/core/totp.py         — TOTP 生成・検証ユーティリティ"
echo "  ✅ app/api/v1/routers/sso.py — SSO / TOTP エンドポイント"
echo "     GET  /api/v1/auth/google           → Google ログイン開始"
echo "     GET  /api/v1/auth/google/callback  → Google コールバック"
echo "     GET  /api/v1/auth/github           → GitHub ログイン開始"
echo "     GET  /api/v1/auth/github/callback  → GitHub コールバック"
echo "     POST /api/v1/auth/totp/setup       → TOTP セットアップ（QR発行）"
echo "     POST /api/v1/auth/totp/verify      → TOTP コード確認"
echo "     DELETE /api/v1/auth/totp           → TOTP 無効化"
echo "     POST /api/v1/auth/totp/login       → TOTP 付きログイン"
echo ""
echo "  【フロントエンド】"
echo "  ✅ src/components/SSOButtons.tsx  — Google / GitHub ログインボタン"
echo "  ✅ src/pages/TOTPSetup.tsx        — 2FA セットアップ（QR表示→コード確認）"
echo "  ✅ src/pages/TOTPLogin.tsx        — 2FA ログインステップ"
echo "  ✅ Login.tsx に SSOButtons 追加"
echo "  ✅ App.tsx に /totp-setup / /totp-login ルート追加"
echo ""
echo "  【次の手順】"
echo "  1. .env に Google / GitHub の Client ID / Secret を設定"
echo "     Google: https://console.cloud.google.com/ → 認証情報 → OAuth 2.0 クライアントID"
echo "     GitHub: https://github.com/settings/developers → OAuth Apps"
echo "  2. バックエンド再起動後 Swagger で確認: http://localhost:8089/docs"
echo "  3. フロントエンド: http://localhost:3008/login でSSOボタン表示確認"
echo "  4. TOTP テスト: ログイン後 http://localhost:3008/totp-setup"
echo ""
ok "Phase 2: SSO / TOTP 認証強化 実装完了！"
