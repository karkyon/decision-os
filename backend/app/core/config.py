from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    APP_NAME: str = "decision-os"
    API_V1_STR: str = "/api/v1"
    SECRET_KEY: str = "changeme-secret-key-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24

    DATABASE_URL: str = "postgresql://dev:devpass_2ed89487@localhost:5439/decisionos"
    REDIS_URL: str = "redis://localhost:6380/0"
    BACKEND_PORT: int = 8089
    FRONTEND_PORT: int = 3008

    class Config:
        env_file = ".env"
        extra = "ignore"

    # SSO: Google OAuth2 (A-002)
    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_SECRET: str = ""
    GOOGLE_REDIRECT_URI: str = "http://localhost:8089/api/v1/auth/google/callback"

    # SSO: GitHub OAuth2 (A-002)
    GITHUB_CLIENT_ID: str = ""
    GITHUB_CLIENT_SECRET: str = ""
    GITHUB_REDIRECT_URI: str = "http://localhost:8089/api/v1/auth/github/callback"

    # TOTP 2FA (A-003)
    TOTP_ISSUER: str = "decision-os"

settings = Settings()
