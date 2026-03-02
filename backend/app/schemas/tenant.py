from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class TenantCreate(BaseModel):
    slug: str
    name: str
    plan: Optional[str] = "free"

class TenantResponse(BaseModel):
    id: str
    slug: str
    name: str
    plan: str
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True
