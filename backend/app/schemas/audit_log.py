from pydantic import BaseModel
from typing import Optional, Any
from uuid import UUID
from datetime import datetime

class AuditLogResponse(BaseModel):
    id:          UUID
    tenant_id:   Optional[UUID] = None
    user_id:     Optional[UUID] = None
    action:      str
    entity_type: Optional[str] = None
    entity_id:   Optional[UUID] = None
    detail:      Optional[Any] = None
    ip_address:  Optional[str] = None
    created_at:  Optional[datetime] = None

    model_config = {"from_attributes": True}
