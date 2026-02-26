from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str
    redis_url: str = "redis://localhost:6379/0"
    jwt_secret: str
    jwt_expire_minutes: int = 1440
    debug: bool = False
    backend_host: str = "0.0.0.0"
    backend_port: int = 8089
    ai_provider: str = "none"
    ai_confidence_threshold: float = 0.75

    class Config:
        env_file = "../.env"
        extra = "ignore"

settings = Settings()
