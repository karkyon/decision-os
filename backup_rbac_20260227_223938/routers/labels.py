"""
Labels router
GET  /labels          使用中ラベル一覧（使用回数・最終使用日付き）
GET  /labels/suggest  オートコンプリート候補（q= で前方一致）
POST /labels/merge    ラベル統合（from_label → to_label に一括置換）
DELETE /labels/{label} 未使用ラベルの削除
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import text
from typing import Optional
from pydantic import BaseModel

from app.db.session import get_db
from ....core.deps import get_current_user
from app.models.user import User

router = APIRouter(prefix="/labels", tags=["labels"])


def _parse_labels(raw: str | None) -> list[str]:
    """カンマ区切りのラベル文字列をリストに変換"""
    if not raw:
        return []
    return [l.strip() for l in raw.split(",") if l.strip()]


@router.get("")
def list_labels(
    project_id: Optional[str] = Query(None),
    q:          Optional[str] = Query(None, description="前方一致フィルター"),
    limit:      int           = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """使用中ラベル一覧を使用回数降順で返す"""
    # issues.labels は "tag1,tag2,tag3" 形式のテキスト
    # PostgreSQL で分割・集計
    sql = """
        SELECT
            trim(label) AS label,
            COUNT(*)    AS issue_count,
            MAX(created_at) AS last_used
        FROM issues,
             unnest(string_to_array(labels, ',')) AS label
        WHERE labels IS NOT NULL AND trim(label) != ''
        {project_filter}
        {q_filter}
        GROUP BY trim(label)
        ORDER BY issue_count DESC
        LIMIT :limit
    """.format(
        project_filter="AND project_id = :project_id" if project_id else "",
        q_filter="AND trim(label) ILIKE :q" if q else "",
    )

    params = {"limit": limit}
    if project_id:
        params["project_id"] = project_id
    if q:
        params["q"] = f"{q}%"

    rows = db.execute(text(sql), params).fetchall()
    return {
        "labels": [
            {
                "label":       row[0],
                "issue_count": row[1],
                "last_used":   row[2].isoformat() if row[2] else None,
            }
            for row in rows
        ],
        "total": len(rows),
    }


@router.get("/suggest")
def suggest_labels(
    q:          str           = Query(..., min_length=1),
    project_id: Optional[str] = Query(None),
    limit:      int           = Query(10, ge=1, le=50),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """入力途中のオートコンプリート候補を返す"""
    sql = """
        SELECT DISTINCT trim(label) AS label, COUNT(*) AS cnt
        FROM issues,
             unnest(string_to_array(labels, ',')) AS label
        WHERE labels IS NOT NULL
          AND trim(label) ILIKE :q
          {project_filter}
        GROUP BY trim(label)
        ORDER BY cnt DESC
        LIMIT :limit
    """.format(
        project_filter="AND project_id = :project_id" if project_id else ""
    )
    params = {"q": f"{q}%", "limit": limit}
    if project_id:
        params["project_id"] = project_id

    rows = db.execute(text(sql), params).fetchall()
    return {"suggestions": [row[0] for row in rows]}


class MergeRequest(BaseModel):
    from_label: str
    to_label:   str
    project_id: Optional[str] = None


@router.post("/merge")
def merge_labels(
    body: MergeRequest,
    db:   Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """from_label を to_label に一括置換（命名ゆれ統合）"""
    from app.models.issue import Issue
    import re

    query = db.query(Issue).filter(Issue.labels.ilike(f"%{body.from_label}%"))
    if body.project_id:
        query = query.filter(Issue.project_id == body.project_id)

    updated = 0
    for issue in query.all():
        labels = _parse_labels(issue.labels)
        new_labels = [
            body.to_label if l.lower() == body.from_label.lower() else l
            for l in labels
        ]
        # 重複排除
        seen = []
        for l in new_labels:
            if l not in seen:
                seen.append(l)
        issue.labels = ",".join(seen)
        updated += 1

    db.commit()
    return {"merged": updated, "from": body.from_label, "to": body.to_label}


@router.delete("/{label}")
def delete_label(
    label: str,
    project_id: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """指定ラベルを全課題から削除"""
    from app.models.issue import Issue

    query = db.query(Issue).filter(Issue.labels.ilike(f"%{label}%"))
    if project_id:
        query = query.filter(Issue.project_id == project_id)

    updated = 0
    for issue in query.all():
        labels = _parse_labels(issue.labels)
        new_labels = [l for l in labels if l.lower() != label.lower()]
        issue.labels = ",".join(new_labels)
        updated += 1

    db.commit()
    return {"deleted_from": updated, "label": label}
