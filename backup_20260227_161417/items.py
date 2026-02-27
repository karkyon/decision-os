from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from ....core.deps import get_db, get_current_user
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
    """ITEM一覧を取得。input_id が指定された場合はそのINPUTに属するITEMのみ返す。"""
    q = db.query(Item)
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

    # 学習ログ記録（変更があれば）
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
    if payload.text:
        item.text = payload.text

    db.commit()
    db.refresh(item)
    return item
