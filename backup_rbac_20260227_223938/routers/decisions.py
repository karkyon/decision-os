from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
from ....core.deps import get_db, get_current_user
from ....models.decision import Decision
from ....models.project import Project
from ....models.user import User
from ....schemas.decision import DecisionCreate, DecisionResponse

router = APIRouter(prefix="/decisions", tags=["decisions"])


@router.get("", response_model=List[DecisionResponse])
def list_decisions(
    project_id: Optional[str] = Query(None),
    issue_id:   Optional[str] = Query(None),
    limit:      int            = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    決定ログ一覧。project_id または issue_id で絞り込み可能。
    両方省略時は全件（limit制限あり）。
    """
    q = db.query(Decision).options(joinedload(Decision.decider))
    if project_id:
        q = q.filter(Decision.project_id == project_id)
    if issue_id:
        q = q.filter(Decision.related_issue_id == issue_id)
    return q.order_by(Decision.created_at.desc()).limit(limit).all()


@router.get("/{decision_id}", response_model=DecisionResponse)
def get_decision(
    decision_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    d = (db.query(Decision)
           .options(joinedload(Decision.decider))
           .filter(Decision.id == decision_id)
           .first())
    if not d:
        raise HTTPException(status_code=404, detail="Decision not found")
    return d


@router.post("", response_model=DecisionResponse, status_code=201)
def create_decision(
    payload: DecisionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """決定ログを記録する。誰が・なぜ・何を決めたかを永久保存。"""
    # project 存在確認
    project = db.query(Project).filter(Project.id == payload.project_id).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    if not payload.decision_text.strip():
        raise HTTPException(status_code=422, detail="decision_text が空です")
    if not payload.reason.strip():
        raise HTTPException(status_code=422, detail="reason が空です")

    decision = Decision(
        project_id          = payload.project_id,
        decision_text       = payload.decision_text.strip(),
        reason              = payload.reason.strip(),
        decided_by          = current_user.id,
        related_request_id  = payload.related_request_id,
        related_issue_id    = payload.related_issue_id,
    )
    db.add(decision)
    db.commit()
    db.refresh(decision)

    # decider をロード
    result = (db.query(Decision)
                .options(joinedload(Decision.decider))
                .filter(Decision.id == decision.id)
                .first())
    return result


@router.delete("/{decision_id}", status_code=204)
def delete_decision(
    decision_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """決定ログを削除（Admin のみ）。"""
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin のみ削除できます")
    d = db.query(Decision).filter(Decision.id == decision_id).first()
    if not d:
        raise HTTPException(status_code=404, detail="Decision not found")
    db.delete(d)
    db.commit()
    return None
