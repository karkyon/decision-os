from pydantic import BaseModel
from typing import Optional
from uuid import UUID
from datetime import datetime

class ProjectMemberAdd(BaseModel):
    user_id: UUID
    role: str = "dev"

class ProjectMemberUpdate(BaseModel):
    role: str

class ProjectMemberResponse(BaseModel):
    id: UUID
    project_id: UUID
    user_id: UUID
    role: str
    invited_by: Optional[UUID] = None
    created_at: Optional[datetime] = None
    model_config = {"from_attributes": True}
