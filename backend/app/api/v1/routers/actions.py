from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from ....core.deps import get_db, get_current_user
from ....models.action import Action
from ....models.item import Item
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
    if payload.action_type == "CREATE_ISSUE":
        issue = Issue(
            project_id=item.input.project_id,
            action_id=action.id,
            title=f"[自動生成] {item.text[:100]}",
            description=item.text,
            priority="medium",
        )
        db.add(issue)
        db.commit()

    return action
