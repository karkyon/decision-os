from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings

app = FastAPI(
    title="decision-os API",
    version="1.0.0",
    description="開発判断OS - 意思決定管理システム",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:80"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
def health():
    return {"status": "ok", "version": "1.0.0"}

@app.get("/api/v1/ping")
def ping():
    return {"message": "pong"}
