from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class InputCreate(BaseModel):
    project_id: str
    source_type: str  # email/voice/meeting/bug/other
    raw_text: str
    summary: Optional[str] = None
    importance: Optional[str] = "3"

class InputResponse(BaseModel):
    id: str
    project_id: str
    source_type: str
    raw_text: str
    summary: Optional[str]
    importance: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True
