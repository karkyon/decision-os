from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from ....core.deps import get_db, get_current_user
from ....models.input import Input
from ....models.project import Project
from ....models.user import User
from ....schemas.input import InputCreate, InputResponse

router = APIRouter(prefix="/inputs", tags=["inputs"])


@router.post("", response_model=InputResponse, status_code=201)
def create_input(
    payload: InputCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    raw_text = payload.get_raw_text()
    if not raw_text:
        raise HTTPException(status_code=422, detail="raw_text または text が必要です")

    # project_id が未指定の場合、ユーザーの最初のプロジェクトを使用
    project_id = payload.project_id
    if not project_id:
        first_project = db.query(Project).first()
        if first_project:
            project_id = str(first_project.id)

    inp = Input(
        project_id=project_id,
        author_id=current_user.id,
        source_type=payload.source_type,
        raw_text=raw_text,
        summary=payload.summary,
        importance=payload.importance,
    )
    db.add(inp)
    db.commit()
    db.refresh(inp)
    return inp


@router.get("/{input_id}", response_model=InputResponse)
def get_input(
    input_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    inp = db.query(Input).filter(
        Input.id == input_id,
        Input.deleted_at == None
    ).first()
    if not inp:
        raise HTTPException(status_code=404, detail="Input not found")
    return inp


@router.get("", response_model=List[InputResponse])
def list_inputs(
    project_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Input).filter(Input.deleted_at == None)
    if project_id:
        query = query.filter(Input.project_id == project_id)
    return query.order_by(Input.created_at.desc()).offset(skip).limit(limit).all()
