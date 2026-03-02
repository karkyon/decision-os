from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class Conversation(Base):
    __tablename__ = "conversations"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    issue_id = Column(UUID(as_uuid=False), ForeignKey("issues.id"))
    author_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    body = Column(Text, nullable=False, default="")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    tenant_id = Column(UUID(as_uuid=False), ForeignKey("tenants.id"), nullable=True, index=True)

    issue = relationship("Issue", back_populates="conversations")
    author = relationship("User", foreign_keys=[author_id])