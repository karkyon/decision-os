from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class ItemResponse(BaseModel):
    id: str
    input_id: str
    text: str
    intent_code: str
    domain_code: str
    confidence: Optional[float]
    position: int
    is_corrected: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True

class ItemUpdate(BaseModel):
    intent_code: Optional[str] = None
    domain_code: Optional[str] = None
    text: Optional[str] = None
