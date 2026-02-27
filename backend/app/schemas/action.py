from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class ActionCreate(BaseModel):
    item_id: str
    action_type: str  # CREATE_ISSUE/ANSWER/STORE/REJECT/HOLD/LINK_EXISTING
    decision_reason: Optional[str] = None

class ActionResponse(BaseModel):
    id: str
    item_id: str
    action_type: str
    decision_reason: Optional[str]
    decided_at: datetime

    class Config:
        from_attributes = True
