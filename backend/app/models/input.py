from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class Input(Base):
    __tablename__ = "inputs"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    project_id = Column(UUID(as_uuid=False), ForeignKey("projects.id"), nullable=False)
    author_id = Column(UUID(as_uuid=False), ForeignKey("users.id"))
    source_type = Column(String(20), nullable=False)  # email/voice/meeting/bug/other
    raw_text = Column(Text, nullable=False)
    summary = Column(Text)  # 手動要約（Phase1）
    importance = Column(String(1), default="3")  # 1-5
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    deleted_at = Column(DateTime(timezone=True))  # 論理削除
    tenant_id = Column(UUID(as_uuid=False), ForeignKey("tenants.id"), nullable=True, index=True)

    project = relationship("Project", back_populates="inputs")
    author = relationship("User", back_populates="inputs")
    interpretation = relationship("Interpretation", back_populates="input", uselist=False)
    items = relationship("Item", back_populates="input", cascade="all, delete-orphan")