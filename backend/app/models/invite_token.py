import secrets
from sqlalchemy import Column, String, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from .base import Base, gen_uuid

class InviteToken(Base):
    __tablename__ = "invite_tokens"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    tenant_id = Column(UUID(as_uuid=False), ForeignKey("tenants.id"), nullable=False, index=True)
    email = Column(String(255), nullable=False)
    role = Column(String(20), nullable=False, default="dev")
    token = Column(String(64), unique=True, nullable=False,
                   default=lambda: secrets.token_urlsafe(48))
    expires_at = Column(DateTime(timezone=True), nullable=False)
    used_at = Column(DateTime(timezone=True), nullable=True)
    invited_by_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
