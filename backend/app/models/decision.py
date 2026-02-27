from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class Decision(Base):
    __tablename__ = "decisions"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    issue_id = Column(UUID(as_uuid=False), ForeignKey("issues.id"))
    decided_by = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    change_type = Column(String(30), nullable=False)  # spec_change/status_change/priority_change/etc
    before_value = Column(Text)
    after_value = Column(Text)
    reason = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    issue = relationship("Issue", back_populates="decisions")
    decider = relationship("User", foreign_keys=[decided_by])
