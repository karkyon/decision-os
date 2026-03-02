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
