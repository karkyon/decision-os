from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from uuid import UUID
from app.db.session import get_db
from app.core.deps import get_current_user
from app.models.project_member import ProjectMember
from app.models.project import Project
from app.schemas.project_member import ProjectMemberAdd, ProjectMemberUpdate, ProjectMemberResponse

router = APIRouter()

def _get_pj_or_404(project_id, tenant_id, db):
    pj = db.query(Project).filter(Project.id == project_id, Project.tenant_id == tenant_id).first()
    if not pj:
        raise HTTPException(404, "プロジェクトが見つかりません")
    return pj

def _require_pj_admin(project_id, current_user, db):
    if current_user.role == "admin":
        return
    mem = db.query(ProjectMember).filter(ProjectMember.project_id == project_id, ProjectMember.user_id == current_user.id).first()
    if not mem or mem.role != "admin":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "PJのadmin権限が必要です")

@router.get("/projects/{project_id}/members", response_model=list[ProjectMemberResponse])
def list_members(project_id: UUID, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    _get_pj_or_404(project_id, current_user.tenant_id, db)
    return db.query(ProjectMember).filter(ProjectMember.project_id == project_id).all()

@router.post("/projects/{project_id}/members", response_model=ProjectMemberResponse, status_code=201)
def add_member(project_id: UUID, data: ProjectMemberAdd, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    _get_pj_or_404(project_id, current_user.tenant_id, db)
    _require_pj_admin(project_id, current_user, db)
    if db.query(ProjectMember).filter(ProjectMember.project_id == project_id, ProjectMember.user_id == data.user_id).first():
        raise HTTPException(409, "既にメンバーです")
    if data.role not in ("admin","pm","dev","viewer"):
        raise HTTPException(422, "無効なロールです")
    m = ProjectMember(project_id=project_id, user_id=data.user_id, tenant_id=current_user.tenant_id, role=data.role, invited_by=current_user.id)
    db.add(m); db.commit(); db.refresh(m)
    return m

@router.patch("/projects/{project_id}/members/{user_id}", response_model=ProjectMemberResponse)
def update_role(project_id: UUID, user_id: UUID, data: ProjectMemberUpdate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    _get_pj_or_404(project_id, current_user.tenant_id, db)
    _require_pj_admin(project_id, current_user, db)
    m = db.query(ProjectMember).filter(ProjectMember.project_id == project_id, ProjectMember.user_id == user_id).first()
    if not m:
        raise HTTPException(404, "メンバーが見つかりません")
    if data.role not in ("admin","pm","dev","viewer"):
        raise HTTPException(422, "無効なロールです")
    m.role = data.role; db.commit(); db.refresh(m)
    return m

@router.delete("/projects/{project_id}/members/{user_id}", status_code=204)
def remove_member(project_id: UUID, user_id: UUID, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    _get_pj_or_404(project_id, current_user.tenant_id, db)
    _require_pj_admin(project_id, current_user, db)
    m = db.query(ProjectMember).filter(ProjectMember.project_id == project_id, ProjectMember.user_id == user_id).first()
    if not m:
        raise HTTPException(404, "メンバーが見つかりません")
    db.delete(m); db.commit()

@router.get("/projects/{project_id}/my-role")
def my_role(project_id: UUID, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    mem = db.query(ProjectMember).filter(ProjectMember.project_id == project_id, ProjectMember.user_id == current_user.id).first()
    pj_role = mem.role if mem else None
    return {"project_id": str(project_id), "tenant_role": current_user.role, "project_role": pj_role, "effective_role": pj_role or current_user.role}
