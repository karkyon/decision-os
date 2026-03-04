from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from ....core.deps import require_pm_or_above, require_dev_or_above, require_admin, get_db, get_current_user
from ....models.item import Item
from ....models.learning_log import LearningLog
from ....models.user import User
from ....schemas.item import ItemUpdate, ItemResponse

router = APIRouter(prefix="/items", tags=["items"])


@router.get("", response_model=List[ItemResponse])
def list_items(
    input_id: Optional[str] = Query(None, description="INPUT IDで絞り込み"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    q = db.query(Item)
    if current_user.tenant_id:
        q = q.filter(Item.tenant_id == str(current_user.tenant_id))
    if input_id:
        q = q.filter(Item.input_id == input_id)
    return q.order_by(Item.position).all()


@router.patch("/{item_id}", response_model=ItemResponse)
def update_item(
    item_id: str,
    payload: ItemUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = db.query(Item).filter(Item.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")

    if payload.intent_code and payload.intent_code != item.intent_code:
        log = LearningLog(
            item_id=item.id,
            predicted_intent=item.intent_code,
            corrected_intent=payload.intent_code,
            predicted_domain=item.domain_code,
            corrected_domain=payload.domain_code or item.domain_code,
        )
        db.add(log)
        item.is_corrected = "true"

    if payload.intent_code:
        item.intent_code = payload.intent_code
    if payload.domain_code:
        item.domain_code = payload.domain_code
    if payload.text is not None:
        item.text = payload.text

    db.commit()
    db.refresh(item)
    return item


@router.delete("/{item_id}", status_code=204)
def delete_item(
    item_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """ITEMを削除する（分解結果の不要な行を削除）"""
    from ....models.action import Action
    from ....models.issue import Issue
    item = db.query(Item).filter(Item.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    # 紐づくActionとIssueのaction_idをNULLにしてから削除
    action = db.query(Action).filter(Action.item_id == item_id).first()
    if action:
        # ActionにリンクしたIssueのaction_idを解除
        db.query(Issue).filter(Issue.action_id == str(action.id)).update({"action_id": None})
        db.commit()
        db.delete(action)
        db.commit()
    db.delete(item)
    db.commit()
    return None