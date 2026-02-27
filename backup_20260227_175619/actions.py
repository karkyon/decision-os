from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from ....core.deps import get_db, get_current_user
from ....models.action import Action
from ....models.item import Item
from ....models.input import Input
from ....models.issue import Issue
from ....models.user import User
from ....schemas.action import ActionCreate, ActionResponse

router = APIRouter(prefix="/actions", tags=["actions"])


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
    )
    db.add(action)
    db.commit()
    db.refresh(action)

    # CREATE_ISSUE の場合、自動で課題生成
    # ※ item.input.project_id の遅延ロードを避け、Inputを明示的にクエリする
    if payload.action_type == "CREATE_ISSUE":
        input_obj = db.query(Input).filter(Input.id == item.input_id).first()
        if input_obj:
            issue = Issue(
                project_id=input_obj.project_id,
                action_id=action.id,        # ← トレーサビリティの核心
                title=f"[自動生成] {item.text[:100]}",
                description=item.text,
                priority="medium",
            )
            db.add(issue)
            db.commit()

    return action


@router.post("/{action_id}/convert")
def convert_action_to_issue(
    action_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    ACTION を ISSUE に変換する。
    action_id を Issue に紐づけてトレーサビリティチェーンを保証する。
    既にISSUEが存在する場合はそれを返す。
    """
    action = db.query(Action).filter(Action.id == action_id).first()
    if not action:
        raise HTTPException(status_code=404, detail="Action not found")

    # 既にこのACTIONから生成されたISSUEが存在するか確認
    existing_issue = db.query(Issue).filter(Issue.action_id == action_id).first()
    if existing_issue:
        return existing_issue

    # action → item → input → project_id を取得
    item = db.query(Item).filter(Item.id == action.item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found for this action")

    input_obj = db.query(Input).filter(Input.id == item.input_id).first()
    if not input_obj:
        raise HTTPException(status_code=404, detail="Input not found for this item")

    issue = Issue(
        project_id=input_obj.project_id,
        action_id=action_id,               # ← トレーサビリティの核心
        title=f"[{action.action_type}] {item.text[:100]}",
        description=item.text,
        priority="medium",
    )
    db.add(issue)
    db.commit()
    db.refresh(issue)

    return issue
