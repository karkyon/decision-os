from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from ....core.deps import get_db, get_current_user
from ....models.issue import Issue
from ....models.user import User
from ....schemas.issue import IssueCreate, IssueUpdate, IssueResponse

router = APIRouter(prefix="/issues", tags=["issues"])

@router.post("", response_model=IssueResponse, status_code=201)
def create_issue(
    payload: IssueCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    issue = Issue(**payload.model_dump())
    db.add(issue)
    db.commit()
    db.refresh(issue)
    return issue

@router.get("", response_model=List[IssueResponse])
def list_issues(
    project_id: str,
    status: Optional[str] = None,
    priority: Optional[str] = None,
    assignee_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    q = db.query(Issue).filter(Issue.project_id == project_id)
    if status:
        q = q.filter(Issue.status == status)
    if priority:
        q = q.filter(Issue.priority == priority)
    if assignee_id:
        q = q.filter(Issue.assignee_id == assignee_id)
    return q.order_by(Issue.created_at.desc()).offset(skip).limit(limit).all()

@router.get("/{issue_id}", response_model=IssueResponse)
def get_issue(
    issue_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    issue = db.query(Issue).filter(Issue.id == issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")
    return issue

@router.patch("/{issue_id}", response_model=IssueResponse)
def update_issue(
    issue_id: str,
    payload: IssueUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    issue = db.query(Issue).filter(Issue.id == issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(issue, field, value)
    db.commit()
    db.refresh(issue)
    return issue
