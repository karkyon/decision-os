from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .core.config import settings
from .api.v1.api import api_router

app = FastAPI(
    title="decision-os API",
    description="開発判断OS - 意思決定の透明化システム",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3008", "http://localhost:8888"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix=settings.API_V1_STR)

@app.get("/health")
def health():
    return {"status": "ok", "service": "decision-os"}

@app.get("/api/v1/ping")
def ping():
    return {"message": "pong", "version": "1.0.0"}
