from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from .base import Base, gen_uuid

class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    user_id = Column(UUID(as_uuid=False), ForeignKey("users.id"))
    action = Column(String(50), nullable=False)  # create/update/delete/login
    resource_type = Column(String(30))           # input/item/action/issue
    resource_id = Column(UUID(as_uuid=False))
    detail = Column(Text)
    ip_address = Column(String(45))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
