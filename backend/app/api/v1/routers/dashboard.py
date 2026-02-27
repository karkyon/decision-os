from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import Optional
from ....core.deps import get_db, get_current_user
from ....models.input import Input
from ....models.item import Item
from ....models.issue import Issue
from ....models.user import User

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("/counts")
def get_dashboard_counts(
    project_id: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # INPUT カウント
    input_q = db.query(Input).filter(Input.deleted_at == None)
    if project_id:
        input_q = input_q.filter(Input.project_id == project_id)
    total_inputs = input_q.count()

    # 未処理INPUT（Itemが1件もないもの）
    from sqlalchemy import exists
    unprocessed_inputs = input_q.filter(
        ~exists().where(Item.input_id == Input.id)
    ).count()

    # ITEM カウント（action未設定 = Actionレコードが紐づいていない）
    item_q = db.query(Item)
    if project_id:
        item_q = item_q.join(Input, Item.input_id == Input.id).filter(
            Input.project_id == project_id
        )
    # action関連カラム名を動的に確認してフィルタ
    item_cols = [c.key for c in Item.__table__.columns]
    print(f"Item columns: {item_cols}")

    if "action_id" in item_cols:
        pending_items = item_q.filter(Item.action_id == None).count()
    else:
        # action_id カラムがない場合は全itemを「未対応」として扱う
        pending_items = item_q.count()

    # ISSUE カウント
    issue_q = db.query(Issue)
    if project_id:
        issue_q = issue_q.filter(Issue.project_id == project_id)
    open_issues = issue_q.filter(
        Issue.status.in_(["open", "in_progress", "review"])
    ).count()
    total_issues = issue_q.count()

    recent_issues = issue_q.filter(
        Issue.status.in_(["open", "in_progress"])
    ).order_by(Issue.updated_at.desc().nullslast()).limit(5).all()

    return {
        "inputs": {
            "total": total_inputs,
            "unprocessed": unprocessed_inputs,
        },
        "items": {
            "pending_action": pending_items,
        },
        "issues": {
            "open": open_issues,
            "total": total_issues,
            "recent": [
                {
                    "id": str(i.id),
                    "title": i.title,
                    "status": i.status,
                    "priority": i.priority,
                }
                for i in recent_issues
            ],
        },
    }
