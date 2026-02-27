from sqlalchemy import Column, Text, Float, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class Interpretation(Base):
    __tablename__ = "interpretations"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    input_id = Column(UUID(as_uuid=False), ForeignKey("inputs.id", ondelete="CASCADE"), nullable=False, unique=True)
    summary = Column(Text)
    overall_intent = Column(Text)
    importance = Column(Float, default=3.0)
    confidence = Column(Float, default=0.0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    input = relationship("Input", back_populates="interpretation")
