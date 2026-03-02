import uuid
from sqlalchemy import Column, String, DateTime, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.sql import func
from .base import Base

class AuditLog(Base):
    __tablename__ = "audit_logs"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id   = Column(UUID(as_uuid=True), ForeignKey("tenants.id", ondelete="SET NULL"), nullable=True, index=True)
    user_id     = Column(UUID(as_uuid=True), ForeignKey("users.id",   ondelete="SET NULL"), nullable=True, index=True)
    action      = Column(String(64), nullable=False, index=True)  # LOGIN / LOGOUT / CREATE_INPUT 等
    entity_type = Column(String(64), nullable=True)               # input / issue / item / user 等
    entity_id   = Column(UUID(as_uuid=True), nullable=True)
    detail      = Column(JSONB, nullable=True)                    # 変更前後など任意の詳細
    ip_address  = Column(String(64), nullable=True)
    user_agent  = Column(Text, nullable=True)
    created_at  = Column(DateTime(timezone=True), server_default=func.now(), index=True)
