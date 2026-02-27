from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from ....core.deps import get_db, get_current_user
from ....models.input import Input
from ....models.user import User
from ....schemas.input import InputCreate, InputResponse

router = APIRouter(prefix="/inputs", tags=["inputs"])

@router.post("", response_model=InputResponse, status_code=201)
def create_input(
    payload: InputCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    inp = Input(
        project_id=payload.project_id,
        author_id=current_user.id,
        source_type=payload.source_type,
        raw_text=payload.raw_text,
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
    inp = db.query(Input).filter(Input.id == input_id, Input.deleted_at == None).first()
    if not inp:
        raise HTTPException(status_code=404, detail="Input not found")
    return inp

@router.get("", response_model=List[InputResponse])
def list_inputs(
    project_id: str,
    skip: int = 0,
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return db.query(Input).filter(
        Input.project_id == project_id,
        Input.deleted_at == None
    ).order_by(Input.created_at.desc()).offset(skip).limit(limit).all()
