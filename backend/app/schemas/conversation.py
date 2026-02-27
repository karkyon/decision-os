from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class ConversationCreate(BaseModel):
    issue_id: str
    body: str

class ConversationUpdate(BaseModel):
    body: str

class AuthorInfo(BaseModel):
    id: str
    name: str
    role: str

    class Config:
        from_attributes = True

class ConversationResponse(BaseModel):
    id: str
    issue_id: str
    author_id: Optional[str] = None
    body: str
    created_at: datetime
    updated_at: Optional[datetime] = None
    author: Optional[AuthorInfo] = None

    class Config:
        from_attributes = True
