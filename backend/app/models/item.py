from sqlalchemy import Column, String, Text, Float, Integer, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class Item(Base):
    __tablename__ = "items"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    input_id = Column(UUID(as_uuid=False), ForeignKey("inputs.id", ondelete="CASCADE"), nullable=False)
    text = Column(Text, nullable=False)
    intent_code = Column(String(10), nullable=False)   # BUG/REQ/IMP/QST/MIS/FBK/INF/TSK
    domain_code = Column(String(10), nullable=False, default="SPEC")  # UI/API/DB/AUTH/PERF/SEC/OPS/SPEC
    semantic_code = Column(String(20))
    confidence = Column(Float, default=0.0)
    position = Column(Integer, default=0)  # 原文中の順序
    is_corrected = Column(String(5), default="false")  # 人手修正済みフラグ
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    input = relationship("Input", back_populates="items")
    action = relationship("Action", back_populates="item", uselist=False)
    tenant_id = Column(UUID(as_uuid=False), ForeignKey("tenants.id"), nullable=True, index=True)
