from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import or_
from typing import List, Optional
from datetime import datetime
from pydantic import BaseModel
from ....core.deps import get_db, get_current_user
from ....models.issue import Issue
from ....models.input import Input
from ....models.item import Item
from ....models.conversation import Conversation
from ....models.user import User

router = APIRouter(prefix="/search", tags=["search"])


# ─── レスポンス型 ───────────────────────────────────────────────
class SearchHit(BaseModel):
    id: str
    type: str           # "issue" | "input" | "item" | "conversation"
    title: str          # 表示用タイトル（スニペット）
    body: str           # ハイライト用本文断片（最大200字）
    url: str            # フロントのリンク先パス
    meta: dict          # type別のメタ情報
    created_at: datetime

    class Config:
        from_attributes = True


class SearchResponse(BaseModel):
    query: str
    total: int
    hits: List[SearchHit]
    duration_ms: int


# ─── ヘルパー: キーワードをスニペットで切り出す ──────────────
def snippet(text: str, keyword: str, width: int = 120) -> str:
    """キーワード周辺のテキストを抜き出す"""
    if not text:
        return ""
    idx = text.lower().find(keyword.lower())
    if idx == -1:
        return text[:width] + ("…" if len(text) > width else "")
    start = max(0, idx - 30)
    end = min(len(text), idx + width)
    prefix = "…" if start > 0 else ""
    suffix = "…" if end < len(text) else ""
    return prefix + text[start:end] + suffix


# ─── エンドポイント ─────────────────────────────────────────────
@router.get("", response_model=SearchResponse)
def search(
    q: str = Query(..., min_length=1, max_length=200, description="検索キーワード"),
    type: Optional[str] = Query(None, description="絞り込み: issue|input|item|conversation"),
    limit: int = Query(20, ge=1, le=100, description="最大件数"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    課題・原文・分解ITEM・コメントを横断全文検索する。
    複数キーワードはスペース区切りで AND 検索。
    """
    import time
    start = time.time()

    if not q.strip():
        raise HTTPException(status_code=422, detail="検索キーワードを入力してください")

    # スペース区切りで複数キーワード対応
    keywords = [k.strip() for k in q.strip().split() if k.strip()]
    hits: List[SearchHit] = []

    # ─── Issues ───────────────────────────────────────────────
    if type in (None, "issue"):
        q_issues = db.query(Issue)
        for kw in keywords:
            pattern = f"%{kw}%"
            q_issues = q_issues.filter(
                or_(
                    Issue.title.ilike(pattern),
                    Issue.description.ilike(pattern),
                    Issue.labels.ilike(pattern),
                )
            )
        for issue in q_issues.order_by(Issue.created_at.desc()).limit(limit).all():
            hits.append(SearchHit(
                id=issue.id,
                type="issue",
                title=issue.title,
                body=snippet(issue.description or issue.title, keywords[0]),
                url=f"/issues/{issue.id}",
                meta={
                    "status": issue.status,
                    "priority": issue.priority,
                    "labels": issue.labels,
                },
                created_at=issue.created_at,
            ))

    # ─── Inputs (RAW_TEXT) ────────────────────────────────────
    if type in (None, "input"):
        q_inputs = db.query(Input)
        for kw in keywords:
            pattern = f"%{kw}%"
            q_inputs = q_inputs.filter(Input.raw_text.ilike(pattern))
        for inp in q_inputs.order_by(Input.created_at.desc()).limit(limit).all():
            hits.append(SearchHit(
                id=inp.id,
                type="input",
                title=f"[{inp.source_type}] {inp.raw_text[:60]}…",
                body=snippet(inp.raw_text, keywords[0]),
                url=f"/inputs/{inp.id}",
                meta={
                    "source_type": inp.source_type,
                    "importance": getattr(inp, "importance", None),
                },
                created_at=inp.created_at,
            ))

    # ─── Items (分解ITEM) ─────────────────────────────────────
    if type in (None, "item"):
        q_items = db.query(Item)
        for kw in keywords:
            q_items = q_items.filter(Item.text.ilike(f"%{kw}%"))
        for item in q_items.order_by(Item.created_at.desc()).limit(limit).all():
            hits.append(SearchHit(
                id=item.id,
                type="item",
                title=f"[{item.intent_code}/{item.domain_code}] {item.text[:60]}",
                body=snippet(item.text, keywords[0]),
                url=f"/inputs/{item.input_id}",
                meta={
                    "intent_code": item.intent_code,
                    "domain_code": item.domain_code,
                    "confidence": item.confidence,
                },
                created_at=item.created_at,
            ))

    # ─── Conversations (コメント) ──────────────────────────────
    if type in (None, "conversation"):
        q_convs = db.query(Conversation)
        for kw in keywords:
            q_convs = q_convs.filter(Conversation.body.ilike(f"%{kw}%"))
        for conv in q_convs.order_by(Conversation.created_at.desc()).limit(limit).all():
            hits.append(SearchHit(
                id=conv.id,
                type="conversation",
                title=f"💬 {conv.body[:60]}",
                body=snippet(conv.body, keywords[0]),
                url=f"/issues/{conv.issue_id}",
                meta={"issue_id": conv.issue_id},
                created_at=conv.created_at,
            ))

    # 全件をcreated_at降順でソート・limit適用
    hits.sort(key=lambda h: h.created_at, reverse=True)
    hits = hits[:limit]

    duration_ms = int((time.time() - start) * 1000)

    return SearchResponse(
        query=q,
        total=len(hits),
        hits=hits,
        duration_ms=duration_ms,
    )
