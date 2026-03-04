from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from typing import List
from pydantic import BaseModel
from ....core.deps import get_db, get_current_user
from ....models.project import Project
from ....models.user import User

router = APIRouter(prefix="/projects", tags=["projects"])

class ProjectCreate(BaseModel):
    name: str
    description: str = ""

class ProjectResponse(BaseModel):
    id: str
    name: str
    description: str | None
    status: str | None

    class Config:
        from_attributes = True

@router.post("", response_model=ProjectResponse, status_code=201)
def create_project(payload: ProjectCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    p = Project(name=payload.name, description=payload.description)
    db.add(p)
    db.commit()
    db.refresh(p)
    return p

@router.get("", response_model=List[ProjectResponse])
def list_projects(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    q = db.query(Project).filter(Project.status == "active")
    if current_user.tenant_id:
        q = q.filter(Project.tenant_id == str(current_user.tenant_id))
    return q.all()
from fastapi import HTTPException
from datetime import datetime, timezone

@router.delete("/{project_id}", status_code=204)
def delete_project(
    project_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """プロジェクトをアーカイブ（ソフトデリート）する"""
    p = db.query(Project).filter(
        Project.id == project_id,
        Project.status == "active"
    ).first()
    if not p:
        raise HTTPException(status_code=404, detail="project not found")

    p.status = "archived"
    p.archived_at = datetime.now(timezone.utc)
    db.commit()
    return
