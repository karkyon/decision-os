from app.core.audit import log_action
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import Optional
from ....core.deps import require_pm_or_above, require_dev_or_above, require_admin, get_db, get_current_user
from ....models.action import Action
from ....models.item import Item
from ....models.input import Input
from ....models.issue import Issue
from ....models.user import User
from ....schemas.action import ActionCreate, ActionResponse

router = APIRouter(prefix="/actions", tags=["actions"])


@router.get("/{action_id}")
def get_action(
    action_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    ACTION の詳細を返す。
    紐づく Issue があれば issue 情報も含める（双方向リンク確認用）。
    """
    action = db.query(Action).filter(Action.id == action_id).first()
    if not action:
        raise HTTPException(status_code=404, detail="Action not found")

    # 紐づく Issue を取得（action_id 経由 or issue_id 経由）
    linked_issue = None
    if hasattr(action, "issue_id") and action.issue_id:
        linked_issue = db.query(Issue).filter(Issue.id == action.issue_id).first()
    else:
        # フォールバック: Issue.action_id から逆引き
        linked_issue = db.query(Issue).filter(Issue.action_id == action_id).first()

    result = {
        "id": action.id,
        "item_id": action.item_id,
        "action_type": action.action_type,
        "decision_reason": action.decision_reason,
        "decided_by": action.decided_by,
        "decided_at": action.decided_at,
        "issue_id": getattr(action, "issue_id", None),
        # 双方向リンク: 紐づく Issue のサマリー
        "linked_issue": {
            "id": linked_issue.id,
            "title": linked_issue.title,
            "status": linked_issue.status,
            "priority": linked_issue.priority,
        } if linked_issue else None,
    }
    return result


@router.post("", response_model=ActionResponse, status_code=201)
def create_action(
    payload: ActionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = db.query(Item).filter(Item.id == payload.item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")

    existing = db.query(Action).filter(Action.item_id == payload.item_id).first()
    if existing:
        raise HTTPException(status_code=409, detail="Action already exists for this item")

    action = Action(
        item_id=payload.item_id,
        action_type=payload.action_type,
        decided_by=current_user.id,
        decision_reason=payload.decision_reason,
        tenant_id=str(current_user.tenant_id) if current_user.tenant_id else None,
    )
    db.add(action)
    db.commit()
    db.refresh(action)

    # CREATE_ISSUE の場合、自動で課題生成 + 双方向リンクをセット
    if payload.action_type == "CREATE_ISSUE":
        input_obj = db.query(Input).filter(Input.id == item.input_id).first()
        if input_obj:
            issue = Issue(
                project_id=input_obj.project_id,
                action_id=action.id,          # Issue → Action（正引き）
                title=f"[自動生成] {item.text[:100]}",
                description=item.text,
                priority="medium",
                tenant_id=str(current_user.tenant_id) if current_user.tenant_id else None,
            )
            db.add(issue)
            db.commit()
            db.refresh(issue)

            # ★ 双方向リンク: Action → Issue をセット
            if hasattr(action, "issue_id"):
                action.issue_id = issue.id
                db.commit()

    return action


@router.post("/{action_id}/convert")
def convert_action_to_issue(
    action_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """ACTION を ISSUE に変換（既存なら返す）。双方向リンクも確立。"""
    action = db.query(Action).filter(Action.id == action_id).first()
    if not action:
        raise HTTPException(status_code=404, detail="Action not found")

    # 既存の ISSUE 確認（Issue.action_id or Action.issue_id）
    existing_issue = db.query(Issue).filter(Issue.action_id == action_id).first()
    if not existing_issue and hasattr(action, "issue_id") and action.issue_id:
        existing_issue = db.query(Issue).filter(Issue.id == action.issue_id).first()

    if existing_issue:
        # 双方向リンクが未設定なら補完
        if hasattr(action, "issue_id") and action.issue_id is None:
            action.issue_id = existing_issue.id
            db.commit()
        return existing_issue

    # 新規 ISSUE 生成
    item = db.query(Item).filter(Item.id == action.item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found for this action")

    input_obj = db.query(Input).filter(Input.id == item.input_id).first()
    if not input_obj:
        raise HTTPException(status_code=404, detail="Input not found for this item")

    issue = Issue(
        project_id=input_obj.project_id,
        action_id=action_id,                   # Issue → Action（正引き）
        title=f"[課題化] {item.text[:100]}",
        description=item.text,
        priority="medium",
        tenant_id=str(current_user.tenant_id) if current_user.tenant_id else None,
    )
    db.add(issue)
    db.commit()
    db.refresh(issue)

    # ★ 双方向リンク: Action → Issue
    if hasattr(action, "issue_id"):
        action.issue_id = issue.id
        db.commit()

    return issue

@router.get("", response_model=list)
async def list_actions(
    item_id: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """ACTION一覧取得（item_id でフィルタ可能）"""
    from app.models.action import Action
    q = db.query(Action).filter(Action.tenant_id == current_user.tenant_id)
    if item_id:
        q = q.filter(Action.item_id == item_id)
    actions = q.all()
    result = []
    for a in actions:
        result.append({
            "id": str(a.id),
            "item_id": str(a.item_id) if a.item_id else None,
            "action_type": getattr(a, "action_type", None),
            "status": getattr(a, "status", None),
            "decided_by": str(a.decided_by) if getattr(a, "decided_by", None) else None,
            "created_at": str(a.created_at) if getattr(a, "created_at", None) else None,
        })
    return result


@router.delete("/{action_id}", status_code=204)
def delete_action(
    action_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """ACTIONを削除する（ACTION変更時の既存削除用）"""
    action = db.query(Action).filter(Action.id == action_id).first()
    if not action:
        raise HTTPException(status_code=404, detail="Action not found")
    # issuesテーブルのaction_id参照をNULLクリア（FK違反回避）
    from app.models.issue import Issue as IssueModel
    db.query(IssueModel).filter(IssueModel.action_id == action_id).update(
        {"action_id": None}, synchronize_session=False
    )
    db.delete(action)
    db.commit()
    return
