from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from .base import Base, gen_uuid

class LearningLog(Base):
    __tablename__ = "learning_logs"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    item_id = Column(UUID(as_uuid=False), ForeignKey("items.id"))
    predicted_intent = Column(String(10))
    corrected_intent = Column(String(10))
    predicted_domain = Column(String(10))
    corrected_domain = Column(String(10))
    reason = Column(Text)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
