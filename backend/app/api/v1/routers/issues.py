"""
Issues router
GET    /issues  複合フィルター対応
POST   /issues  課題作成
GET    /issues/{id}
PATCH  /issues/{id}
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_
from typing import Optional, List
from datetime import datetime

from app.db.session import get_db
from app.models.issue import Issue
from app.models.action import Action
from app.models.item import Item
from ....core.deps import require_pm_or_above, require_dev_or_above, require_admin, get_db, get_current_user
from app.models.user import User
from app.core.notifier import manager

router = APIRouter(prefix="/issues", tags=["issues"])


@router.get("")
def list_issues(
    project_id:   Optional[str]       = Query(None),
    status:       Optional[str]       = Query(None, description="カンマ区切り複数指定可: open,in_progress"),
    priority:     Optional[str]       = Query(None, description="high,medium,low"),
    assignee_id:  Optional[str]       = Query(None),
    intent_code:  Optional[str]       = Query(None, description="BUG,REQ,IMP など"),
    label:        Optional[str]       = Query(None, description="部分一致"),
    date_from:    Optional[str]       = Query(None, description="YYYY-MM-DD"),
    date_to:      Optional[str]       = Query(None, description="YYYY-MM-DD"),
    q:            Optional[str]       = Query(None, description="タイトル・説明の全文検索"),
    sort:         Optional[str]       = Query("created_at_desc", description="created_at_desc|created_at_asc|priority_desc|due_date_asc"),
    limit:        int                 = Query(100, ge=1, le=500),
    offset:       int                 = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    q_obj = db.query(Issue)

    # tenant_id（テナント分離）
    if current_user.tenant_id:
        q_obj = q_obj.filter(Issue.tenant_id == str(current_user.tenant_id))
    # project_id
    if project_id:
        q_obj = q_obj.filter(Issue.project_id == project_id)

    # status (カンマ区切り OR)
    if status:
        statuses = [s.strip() for s in status.split(",") if s.strip()]
        q_obj = q_obj.filter(Issue.status.in_(statuses))

    # priority (カンマ区切り OR)
    if priority:
        priorities = [p.strip() for p in priority.split(",") if p.strip()]
        q_obj = q_obj.filter(Issue.priority.in_(priorities))

    # assignee_id
    if assignee_id:
        q_obj = q_obj.filter(Issue.assignee_id == assignee_id)

    # label (部分一致)
    if label:
        q_obj = q_obj.filter(Issue.labels.ilike(f"%{label}%"))

    # date_from / date_to (created_at)
    if date_from:
        try:
            dt = datetime.strptime(date_from, "%Y-%m-%d")
            q_obj = q_obj.filter(Issue.created_at >= dt)
        except ValueError:
            pass
    if date_to:
        try:
            dt = datetime.strptime(date_to, "%Y-%m-%d")
            # date_to は当日末尾まで含める
            from datetime import timedelta
            q_obj = q_obj.filter(Issue.created_at < dt + timedelta(days=1))
        except ValueError:
            pass

    # intent_code (Action → Item の intent で絞り込み)
    if intent_code:
        codes = [c.strip() for c in intent_code.split(",") if c.strip()]
        q_obj = (
            q_obj
            .join(Action, Action.issue_id == Issue.id, isouter=True)
            .join(Item,   Item.id == Action.item_id,   isouter=True)
            .filter(Item.intent_code.in_(codes))
        )

    # 全文検索 (title / description)
    if q:
        keywords = [k.strip() for k in q.strip().split() if k.strip()]
        for kw in keywords:
            pattern = f"%{kw}%"
            q_obj = q_obj.filter(
                or_(Issue.title.ilike(pattern), Issue.description.ilike(pattern))
            )

    # ソート
    if sort == "created_at_asc":
        q_obj = q_obj.order_by(Issue.created_at.asc())
    elif sort == "priority_desc":
        from sqlalchemy import case
        priority_order = case(
            {"high": 1, "medium": 2, "low": 3},
            value=Issue.priority,
            else_=9,
        )
        q_obj = q_obj.order_by(priority_order, Issue.created_at.desc())
    elif sort == "due_date_asc":
        q_obj = q_obj.order_by(Issue.due_date.asc().nulls_last(), Issue.created_at.desc())
    else:  # created_at_desc (default)
        q_obj = q_obj.order_by(Issue.created_at.desc())

    total = q_obj.count()
    issues = q_obj.offset(offset).limit(limit).all()

    return {
        "total": total,
        "offset": offset,
        "limit": limit,
        "issues": [_issue_dict(i) for i in issues],
    }


@router.post("")
def create_issue(
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    issue = Issue(
        project_id=body.get("project_id"),
        title=body.get("title", ""),
        description=body.get("description"),
        status=body.get("status", "open"),
        priority=body.get("priority", "medium"),
        assignee_id=body.get("assignee_id"),
        labels=body.get("labels"),
        due_date=body.get("due_date"),
        action_id=body.get("action_id"),
    )
    db.add(issue)
    db.commit()
    db.refresh(issue)
    # リアルタイム通知
    import asyncio
    try:
        asyncio.get_event_loop().create_task(
            manager.broadcast_notification(
                event_type="issue.created",
                title="新しい課題",
                body=issue.title[:50],
                url=f"/issues/{issue.id}",
                project_id=str(issue.project_id) if issue.project_id else None,
            )
        )
    except Exception:
        pass
    return _issue_dict(issue)


@router.get("/{issue_id}")
def get_issue(
    issue_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    issue = db.query(Issue).filter(Issue.id == issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")
    return _issue_dict(issue)


@router.patch("/{issue_id}")
def update_issue(
    issue_id: str,
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    issue = db.query(Issue).filter(Issue.id == issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")
    for k, v in body.items():
        if hasattr(issue, k):
            setattr(issue, k, v)
    db.commit()
    db.refresh(issue)
    import asyncio
    try:
        asyncio.get_event_loop().create_task(
            manager.broadcast_notification(
                event_type="issue.updated",
                title="課題が更新されました",
                body=issue.title[:50],
                url=f"/issues/{issue.id}",
                project_id=str(issue.project_id) if issue.project_id else None,
            )
        )
    except Exception:
        pass
    return _issue_dict(issue)


def _issue_dict(issue: Issue) -> dict:
    return {
        "id": issue.id,
        "project_id": issue.project_id,
        "title": issue.title,
        "description": issue.description,
        "status": issue.status,
        "priority": issue.priority,
        "assignee_id": issue.assignee_id,
        "labels": issue.labels,
        "due_date": str(issue.due_date) if issue.due_date else None,
        "action_id": issue.action_id,
        "created_at": issue.created_at.isoformat() if issue.created_at else None,
        "updated_at": issue.updated_at.isoformat() if issue.updated_at else None,
        "parent_id":  issue.parent_id  if hasattr(issue, "parent_id")  else None,
        "issue_type": issue.issue_type if hasattr(issue, "issue_type") else "task",
    }


@router.get("/{issue_id}/children")
def get_children(
    issue_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """直接の子課題一覧を返す"""
    children = db.query(Issue).filter(Issue.parent_id == issue_id).order_by(Issue.created_at).all()
    return {"children": [_issue_dict(c) for c in children]}


@router.get("/{issue_id}/tree")
def get_issue_tree(
    issue_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """再帰的に全子孫を返す（最大3階層）"""
    def build_tree(issue_id: str, depth: int = 0):
        if depth >= 3:
            return []
        children = db.query(Issue).filter(Issue.parent_id == issue_id).order_by(Issue.created_at).all()
        return [
            {**_issue_dict(c), "children": build_tree(c.id, depth + 1)}
            for c in children
        ]

    root = db.query(Issue).filter(Issue.id == issue_id).first()
    if not root:
        raise HTTPException(status_code=404, detail="Issue not found")
    return {**_issue_dict(root), "children": build_tree(issue_id)}

