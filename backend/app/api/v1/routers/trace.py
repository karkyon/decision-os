from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from ....core.deps import get_db, get_current_user
from ....models.issue import Issue
from ....models.action import Action
from ....models.item import Item
from ....models.input import Input
from ....models.user import User

router = APIRouter(prefix="/trace", tags=["trace"])


@router.get("/{issue_id}")
def get_trace(
    issue_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    指定した課題IDのトレーサビリティチェーンを返す。
    ISSUE → ACTION → ITEM → INPUT の順で逆引きする。
    issue.action_id が null の場合は items経由で逆引きを試みる。
    """
    issue = db.query(Issue).filter(Issue.id == issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")

    result = {
        "issue": {
            "id": issue.id,
            "title": issue.title,
            "status": issue.status,
            "priority": issue.priority,
            "created_at": str(issue.created_at),
        },
        "action": None,
        "item": None,
        "input": None,
    }

    # ACTION を取得
    # 1次: issue.action_id で直引き（正規ルート）
    # 2次: issue.action_id が null の場合、Actionの uselist=False リレーションから逆引き
    action = None
    if issue.action_id:
        action = db.query(Action).filter(Action.id == issue.action_id).first()

    # フォールバック: action_id=null の旧データ対策
    # Issue の action リレーション（Action.issue → Issue の逆向き）を利用
    if action is None and issue.action is not None:
        action = issue.action

    if action:
        result["action"] = {
            "id": action.id,
            "action_type": action.action_type,
            "decision_reason": action.decision_reason,
            "decided_at": str(action.decided_at),
        }

        item = db.query(Item).filter(Item.id == action.item_id).first()
        if item:
            result["item"] = {
                "id": item.id,
                "text": item.text,
                "intent_code": item.intent_code,
                "domain_code": item.domain_code,
                "confidence": item.confidence,
            }

            inp = db.query(Input).filter(Input.id == item.input_id).first()
            if inp:
                result["input"] = {
                    "id": inp.id,
                    "source_type": inp.source_type,
                    "raw_text": inp.raw_text,
                    "created_at": str(inp.created_at),
                }

    return result
