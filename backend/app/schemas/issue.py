from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class IssueCreate(BaseModel):
    project_id: str
    action_id: Optional[str] = None
    title: str
    description: Optional[str] = None
    priority: str = "medium"
    assignee_id: Optional[str] = None
    due_date: Optional[datetime] = None
    labels: Optional[str] = None  # JSON文字列

class IssueUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None
    priority: Optional[str] = None
    assignee_id: Optional[str] = None
    due_date: Optional[datetime] = None
    labels: Optional[str] = None

class IssueResponse(BaseModel):
    id: str
    project_id: str
    action_id: Optional[str]
    title: str
    description: Optional[str]
    status: str
    priority: str
    assignee_id: Optional[str]
    labels: Optional[str]
    created_at: datetime
    updated_at: Optional[datetime]

    class Config:
        from_attributes = True
