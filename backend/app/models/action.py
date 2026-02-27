from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class Action(Base):
    __tablename__ = "actions"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    item_id = Column(UUID(as_uuid=False), ForeignKey("items.id", ondelete="CASCADE"), nullable=False, unique=True)
    action_type = Column(String(20), nullable=False)
    # CREATE_ISSUE / ANSWER / STORE / REJECT / HOLD / LINK_EXISTING
    decided_by = Column(UUID(as_uuid=False), ForeignKey("users.id"))
    decision_reason = Column(Text)
    decided_at = Column(DateTime(timezone=True), server_default=func.now())

    item = relationship("Item", back_populates="action")
    issue = relationship("Issue", back_populates="action", uselist=False)
    decider = relationship("User", foreign_keys=[decided_by])
