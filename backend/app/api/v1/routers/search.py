"""
search.py — W-003 テナント横断検索 (Phase 2)

GET /api/v1/search?q=<keyword>
  - テナント内の全PJを横断して全文検索
  - 検索対象: inputs / items / issues / decisions
  - オプション: type 絞り込み / project_id 絞り込み / limit / offset

レスポンス形式:
  {
    "total": 42,
    "results": [
      {
        "type": "input" | "item" | "issue" | "decision",
        "id": "<uuid>",
        "project_id": "<uuid>",
        "project_name": "<str>",
        "title": "<str>",        # 表示用タイトル
        "snippet": "<str>",      # マッチ周辺テキスト（最大200文字）
        "score": 1.0,            # 将来: 全文検索スコア
        "created_at": "<iso>"
      }
    ]
  }
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy import or_, func
from sqlalchemy.orm import Session
from typing import Optional, List
from uuid import UUID
from datetime import datetime
import re

from app.db.session import get_db
from app.core.deps import get_current_user

router = APIRouter()

# ── ヘルパー ──────────────────────────────────────────────────────────────

def _snippet(text: Optional[str], keyword: str, max_len: int = 200) -> str:
    """キーワード周辺のテキストを切り出す"""
    if not text:
        return ""
    text = text.strip()
    idx = text.lower().find(keyword.lower())
    if idx == -1:
        return text[:max_len]
    start = max(0, idx - 60)
    end = min(len(text), idx + 140)
    snippet = text[start:end]
    if start > 0:
        snippet = "…" + snippet
    if end < len(text):
        snippet = snippet + "…"
    return snippet


def _project_name_map(db: Session, tenant_id: UUID) -> dict:
    """tenant内の {project_id: project_name} マップを返す"""
    from app.models.project import Project
    rows = db.query(Project.id, Project.name).filter(Project.tenant_id == tenant_id).all()
    return {str(r.id): r.name for r in rows}


# ── メインエンドポイント ──────────────────────────────────────────────────

@router.get("/search")
def tenant_search(
    q:          str            = Query(..., min_length=1, max_length=200, description="検索キーワード"),
    type:       Optional[str]  = Query(None, description="絞り込み: input / item / issue / decision"),
    project_id: Optional[UUID] = Query(None, description="特定PJに絞り込む"),
    limit:      int            = Query(20, ge=1, le=100),
    offset:     int            = Query(0, ge=0),
    db:         Session        = Depends(get_db),
    current_user               = Depends(get_current_user),
):
    """
    W-003 テナント横断全文検索。
    テナント内の全PJにまたがって inputs / items / issues / decisions を検索する。
    """
    tenant_id   = current_user.tenant_id
    pj_map      = _project_name_map(db, tenant_id)
    keyword     = q.strip()
    results: List[dict] = []

    # ── inputs 検索 ────────────────────────────────────────────────────────
    if not type or type == "input":
        try:
            from app.models.input import RawInput
            iq = db.query(RawInput).filter(
                RawInput.tenant_id == tenant_id,
                or_(
                    func.lower(RawInput.raw_text).contains(keyword.lower()),
                    func.lower(RawInput.source).contains(keyword.lower()) if hasattr(RawInput, "source") else False,
                )
            )
            if project_id:
                iq = iq.filter(RawInput.project_id == project_id)
            for row in iq.order_by(RawInput.created_at.desc()).limit(limit).all():
                results.append({
                    "type":         "input",
                    "id":           str(row.id),
                    "project_id":   str(row.project_id) if row.project_id else None,
                    "project_name": pj_map.get(str(row.project_id), ""),
                    "title":        (row.raw_text or "")[:60],
                    "snippet":      _snippet(row.raw_text, keyword),
                    "score":        1.0,
                    "created_at":   row.created_at.isoformat() if row.created_at else None,
                })
        except Exception as e:
            pass  # モデル名が違う場合はスキップ

    # ── items 検索 ─────────────────────────────────────────────────────────
    if not type or type == "item":
        try:
            from app.models.item import Item
            iq = db.query(Item).filter(
                Item.tenant_id == tenant_id,
                or_(
                    func.lower(Item.content).contains(keyword.lower()),
                    func.lower(Item.intent).contains(keyword.lower()) if hasattr(Item, "intent") else False,
                    func.lower(Item.domain).contains(keyword.lower()) if hasattr(Item, "domain") else False,
                )
            )
            if project_id:
                iq = iq.filter(Item.project_id == project_id)
            for row in iq.order_by(Item.created_at.desc()).limit(limit).all():
                content = getattr(row, "content", "") or ""
                results.append({
                    "type":         "item",
                    "id":           str(row.id),
                    "project_id":   str(row.project_id) if getattr(row, "project_id", None) else None,
                    "project_name": pj_map.get(str(getattr(row, "project_id", "")), ""),
                    "title":        content[:60],
                    "snippet":      _snippet(content, keyword),
                    "score":        1.0,
                    "created_at":   row.created_at.isoformat() if getattr(row, "created_at", None) else None,
                })
        except Exception as e:
            pass

    # ── issues 検索 ────────────────────────────────────────────────────────
    if not type or type == "issue":
        try:
            from app.models.issue import Issue
            iq = db.query(Issue).filter(
                Issue.tenant_id == tenant_id,
                or_(
                    func.lower(Issue.title).contains(keyword.lower()),
                    func.lower(Issue.description).contains(keyword.lower()) if hasattr(Issue, "description") else False,
                )
            )
            if project_id:
                iq = iq.filter(Issue.project_id == project_id)
            for row in iq.order_by(Issue.created_at.desc()).limit(limit).all():
                desc = getattr(row, "description", "") or ""
                results.append({
                    "type":         "issue",
                    "id":           str(row.id),
                    "project_id":   str(row.project_id) if getattr(row, "project_id", None) else None,
                    "project_name": pj_map.get(str(getattr(row, "project_id", "")), ""),
                    "title":        row.title or "",
                    "snippet":      _snippet(desc or row.title, keyword),
                    "score":        1.0,
                    "created_at":   row.created_at.isoformat() if getattr(row, "created_at", None) else None,
                })
        except Exception as e:
            pass

    # ── decisions 検索 ─────────────────────────────────────────────────────
    if not type or type == "decision":
        try:
            from app.models.decision import Decision
            dq = db.query(Decision).filter(
                Decision.tenant_id == tenant_id,
                or_(
                    func.lower(Decision.title).contains(keyword.lower()) if hasattr(Decision, "title") else False,
                    func.lower(Decision.reason).contains(keyword.lower()) if hasattr(Decision, "reason") else False,
                    func.lower(Decision.content).contains(keyword.lower()) if hasattr(Decision, "content") else False,
                )
            )
            if project_id:
                dq = dq.filter(Decision.project_id == project_id)
            for row in dq.order_by(Decision.created_at.desc()).limit(limit).all():
                title   = getattr(row, "title", None) or getattr(row, "content", "")[:60] or ""
                body    = getattr(row, "reason", None) or getattr(row, "content", "") or ""
                results.append({
                    "type":         "decision",
                    "id":           str(row.id),
                    "project_id":   str(row.project_id) if getattr(row, "project_id", None) else None,
                    "project_name": pj_map.get(str(getattr(row, "project_id", "")), ""),
                    "title":        title[:60],
                    "snippet":      _snippet(body, keyword),
                    "score":        1.0,
                    "created_at":   row.created_at.isoformat() if getattr(row, "created_at", None) else None,
                })
        except Exception as e:
            pass

    # created_at 降順でソート、offset/limit 適用
    results.sort(key=lambda x: x.get("created_at") or "", reverse=True)
    paginated = results[offset: offset + limit]

    return {
        "total":    len(results),
        "keyword":  keyword,
        "results":  paginated,
    }
