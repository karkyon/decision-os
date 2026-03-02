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
