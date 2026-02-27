"""
辞書管理API
GET    /api/v1/dictionary          — 辞書一覧
POST   /api/v1/dictionary          — キーワード追加
DELETE /api/v1/dictionary/{id}     — キーワード削除
PATCH  /api/v1/dictionary/{id}     — 有効/無効切り替え
POST   /api/v1/dictionary/reload   — キャッシュクリア（即時反映）
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import Column, String, Float, Boolean, DateTime, text
from sqlalchemy.dialects.postgresql import UUID
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
import uuid

from app.db.session import Base, get_db
from app.core.deps import get_current_user
from app.models.user import User

router = APIRouter(prefix="/dictionary", tags=["dictionary"])


# ── モデル ───────────────────────────────────────────────────────────────────
class IntentKeyword(Base):
    __tablename__ = "intent_keywords"
    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    intent     = Column(String(10), nullable=False)
    keyword    = Column(String, nullable=False)
    match_type = Column(String(10), default="partial")
    weight     = Column(Float, default=1.0)
    enabled    = Column(Boolean, default=True)
    source     = Column(String(20), default="manual")
    created_at = Column(DateTime, default=datetime.utcnow)


# ── スキーマ ─────────────────────────────────────────────────────────────────
class KeywordCreate(BaseModel):
    intent:     str
    keyword:    str
    match_type: str = "partial"
    weight:     float = 1.0

class KeywordUpdate(BaseModel):
    enabled: Optional[bool] = None
    weight:  Optional[float] = None

class KeywordOut(BaseModel):
    id:         str
    intent:     str
    keyword:    str
    match_type: str
    weight:     float
    enabled:    bool
    source:     str
    created_at: datetime

    class Config:
        from_attributes = True


# ── エンドポイント ───────────────────────────────────────────────────────────
@router.get("", response_model=List[KeywordOut])
def list_keywords(
    intent: Optional[str] = None,
    enabled: Optional[bool] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    q = db.query(IntentKeyword)
    if intent:
        q = q.filter(IntentKeyword.intent == intent.upper())
    if enabled is not None:
        q = q.filter(IntentKeyword.enabled == enabled)
    return q.order_by(IntentKeyword.intent, IntentKeyword.weight.desc()).all()


@router.post("", response_model=KeywordOut, status_code=201)
def add_keyword(
    payload: KeywordCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    existing = db.query(IntentKeyword).filter(
        IntentKeyword.intent == payload.intent.upper(),
        IntentKeyword.keyword == payload.keyword,
    ).first()
    if existing:
        raise HTTPException(status_code=409, detail="既に登録済みです")

    kw = IntentKeyword(
        intent=payload.intent.upper(),
        keyword=payload.keyword,
        match_type=payload.match_type,
        weight=payload.weight,
        source="manual",
    )
    db.add(kw)
    db.commit()
    db.refresh(kw)

    # キャッシュクリア（即時反映）
    try:
        from engine.classifier import invalidate_cache
        invalidate_cache()
    except Exception:
        pass

    return kw


@router.patch("/{keyword_id}", response_model=KeywordOut)
def update_keyword(
    keyword_id: str,
    payload: KeywordUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    kw = db.query(IntentKeyword).filter(IntentKeyword.id == keyword_id).first()
    if not kw:
        raise HTTPException(status_code=404, detail="Not found")
    if payload.enabled is not None:
        kw.enabled = payload.enabled
    if payload.weight is not None:
        kw.weight = payload.weight
    db.commit()
    db.refresh(kw)

    try:
        from engine.classifier import invalidate_cache
        invalidate_cache()
    except Exception:
        pass

    return kw


@router.delete("/{keyword_id}", status_code=204)
def delete_keyword(
    keyword_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    kw = db.query(IntentKeyword).filter(IntentKeyword.id == keyword_id).first()
    if not kw:
        raise HTTPException(status_code=404, detail="Not found")
    db.delete(kw)
    db.commit()

    try:
        from engine.classifier import invalidate_cache
        invalidate_cache()
    except Exception:
        pass


@router.post("/reload", status_code=200)
def reload_cache(current_user: User = Depends(get_current_user)):
    """辞書キャッシュを強制クリア（DB更新後に即時反映させる）"""
    try:
        from engine.classifier import invalidate_cache
        invalidate_cache()
        return {"message": "キャッシュをクリアしました。次回リクエスト時にDBから再ロードします。"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
