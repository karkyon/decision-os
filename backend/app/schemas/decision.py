from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class DecisionCreate(BaseModel):
    project_id: str
    decision_text: str
    reason: str
    related_request_id: Optional[str] = None
    related_issue_id: Optional[str] = None

class DeciderInfo(BaseModel):
    id: str
    name: str
    role: str
    class Config:
        from_attributes = True

class DecisionResponse(BaseModel):
    id: str
    project_id: str
    decision_text: str
    reason: str
    decided_by: Optional[str] = None
    related_request_id: Optional[str] = None
    related_issue_id: Optional[str] = None
    created_at: datetime
    decider: Optional[DeciderInfo] = None
    class Config:
        from_attributes = True
