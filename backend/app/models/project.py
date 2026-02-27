from sqlalchemy import Column, String, DateTime, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class Project(Base):
    __tablename__ = "projects"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    name = Column(String(200), nullable=False)
    description = Column(Text)
    status = Column(String(20), default="active")  # active/archived
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    inputs = relationship("Input", back_populates="project")
    issues = relationship("Issue", back_populates="project")
