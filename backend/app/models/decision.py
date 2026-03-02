from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class Decision(Base):
    __tablename__ = "decisions"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    project_id = Column(UUID(as_uuid=False), ForeignKey("projects.id"), nullable=False)
    decision_text = Column(Text, nullable=False)
    reason = Column(Text, nullable=False)
    decided_by = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    related_request_id = Column(UUID(as_uuid=False), ForeignKey("inputs.id"), nullable=True)
    related_issue_id = Column(UUID(as_uuid=False), ForeignKey("issues.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    issue = relationship("Issue", back_populates="decisions", foreign_keys=[related_issue_id])
    decider = relationship("User", foreign_keys=[decided_by])