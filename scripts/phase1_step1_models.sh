#!/bin/bash
# ============================================================
# Phase 1 MVP - Step 1: DBモデル定義 + Alembicマイグレーション
# 実行場所: omega-dev2 サーバー
# ============================================================
set -e

PROJECT="$HOME/projects/decision-os"
BACKEND="$PROJECT/backend"

echo "=== Step 1: SQLAlchemyモデル定義 ==="

# ---- Base モデル ----
cat > "$BACKEND/app/models/__init__.py" << 'EOF'
from .base import Base
from .user import User
from .project import Project
from .input import Input
from .interpretation import Interpretation
from .item import Item
from .action import Action
from .issue import Issue
from .decision import Decision
from .conversation import Conversation
from .learning_log import LearningLog
from .audit_log import AuditLog

__all__ = [
    "Base", "User", "Project", "Input", "Interpretation",
    "Item", "Action", "Issue", "Decision", "Conversation",
    "LearningLog", "AuditLog",
]
EOF

cat > "$BACKEND/app/models/base.py" << 'EOF'
from sqlalchemy.orm import DeclarativeBase
import uuid
from sqlalchemy import Column, String
from sqlalchemy.dialects.postgresql import UUID

class Base(DeclarativeBase):
    pass

def gen_uuid():
    return str(uuid.uuid4())
EOF

# ---- User ----
cat > "$BACKEND/app/models/user.py" << 'EOF'
from sqlalchemy import Column, String, DateTime, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    name = Column(String(100), nullable=False)
    email = Column(String(255), unique=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    role = Column(String(20), nullable=False, default="dev")  # admin/pm/dev/viewer
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    inputs = relationship("Input", back_populates="author")
    issues_assigned = relationship("Issue", back_populates="assignee", foreign_keys="Issue.assignee_id")
EOF

# ---- Project ----
cat > "$BACKEND/app/models/project.py" << 'EOF'
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
EOF

# ---- Input（原文・RAW_INPUT）----
cat > "$BACKEND/app/models/input.py" << 'EOF'
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

    project = relationship("Project", back_populates="inputs")
    author = relationship("User", back_populates="inputs")
    interpretation = relationship("Interpretation", back_populates="input", uselist=False)
    items = relationship("Item", back_populates="input", cascade="all, delete-orphan")
EOF

# ---- Interpretation（解釈）----
cat > "$BACKEND/app/models/interpretation.py" << 'EOF'
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
EOF

# ---- Item（意味単位）----
cat > "$BACKEND/app/models/item.py" << 'EOF'
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
EOF

# ---- Action（対応判断）----
cat > "$BACKEND/app/models/action.py" << 'EOF'
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
EOF

# ---- Issue（課題）----
cat > "$BACKEND/app/models/issue.py" << 'EOF'
from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class Issue(Base):
    __tablename__ = "issues"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    project_id = Column(UUID(as_uuid=False), ForeignKey("projects.id"), nullable=False)
    action_id = Column(UUID(as_uuid=False), ForeignKey("actions.id"))  # 生成元Action
    title = Column(String(500), nullable=False)
    description = Column(Text)
    status = Column(String(20), default="open")  # open/doing/review/done/hold
    priority = Column(String(10), default="medium")  # low/medium/high/critical
    assignee_id = Column(UUID(as_uuid=False), ForeignKey("users.id"))
    due_date = Column(DateTime(timezone=True))
    labels = Column(Text)  # JSON配列文字列
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    closed_at = Column(DateTime(timezone=True))

    project = relationship("Project", back_populates="issues")
    action = relationship("Action", back_populates="issue")
    assignee = relationship("User", back_populates="issues_assigned", foreign_keys=[assignee_id])
    decisions = relationship("Decision", back_populates="issue")
    conversations = relationship("Conversation", back_populates="issue")
EOF

# ---- Decision（意思決定ログ）----
cat > "$BACKEND/app/models/decision.py" << 'EOF'
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
EOF

# ---- Conversation（会話）----
cat > "$BACKEND/app/models/conversation.py" << 'EOF'
from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class Conversation(Base):
    __tablename__ = "conversations"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    issue_id = Column(UUID(as_uuid=False), ForeignKey("issues.id"))  # 紐づき必須（Phase1はIssueのみ）
    author_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    content = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    issue = relationship("Issue", back_populates="conversations")
    author = relationship("User", foreign_keys=[author_id])
EOF

# ---- LearningLog（学習ログ）----
cat > "$BACKEND/app/models/learning_log.py" << 'EOF'
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
EOF

# ---- AuditLog（監査ログ）----
cat > "$BACKEND/app/models/audit_log.py" << 'EOF'
from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from .base import Base, gen_uuid

class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    user_id = Column(UUID(as_uuid=False), ForeignKey("users.id"))
    action = Column(String(50), nullable=False)  # create/update/delete/login
    resource_type = Column(String(30))           # input/item/action/issue
    resource_id = Column(UUID(as_uuid=False))
    detail = Column(Text)
    ip_address = Column(String(45))
    created_at = Column(DateTime(timezone=True), server_default=func.now())
EOF

echo "✅ モデルファイル生成完了"

# ---- Alembic env.py 更新（モデル自動検出）----
cat > "$BACKEND/alembic/env.py" << 'EOF'
from logging.config import fileConfig
from sqlalchemy import engine_from_config, pool
from alembic import context
import sys, os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app.core.config import settings
from app.models import Base

config = context.config
config.set_main_option("sqlalchemy.url", settings.DATABASE_URL)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata

def run_migrations_offline():
    url = config.get_main_option("sqlalchemy.url")
    context.configure(url=url, target_metadata=target_metadata, literal_binds=True,
                      dialect_opts={"paramstyle": "named"})
    with context.begin_transaction():
        context.run_migrations()

def run_migrations_online():
    connectable = engine_from_config(config.get_section(config.config_ini_section, {}),
                                     prefix="sqlalchemy.", poolclass=pool.NullPool)
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()

if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
EOF

echo "✅ alembic/env.py 更新完了"

# ---- config.py に DATABASE_URL 追加確認 ----
cat > "$BACKEND/app/core/config.py" << 'EOF'
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    APP_NAME: str = "decision-os"
    API_V1_STR: str = "/api/v1"
    SECRET_KEY: str = "changeme-secret-key-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24  # 24時間

    DATABASE_URL: str = "postgresql://dev:devpassword@localhost:5439/decisionos"
    REDIS_URL: str = "redis://localhost:6380/0"
    BACKEND_PORT: int = 8089
    FRONTEND_PORT: int = 3008

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()
EOF

echo "✅ config.py 更新完了"

# ---- マイグレーション生成・適用 ----
echo ""
echo "=== Alembicマイグレーション実行 ==="
cd "$BACKEND"
source .venv/bin/activate

alembic revision --autogenerate -m "initial_schema"
alembic upgrade head

echo ""
echo "=== DBテーブル確認 ==="
docker compose -f "$PROJECT/docker-compose.yml" exec -T db \
    psql -U dev -d decisionos -c "\dt" 2>/dev/null || \
    docker exec decision-os-db-1 psql -U dev -d decisionos -c "\dt" 2>/dev/null || \
    echo "⚠️  docker exec確認は手動で: docker compose exec db psql -U dev -d decisionos -c '\dt'"

echo ""
echo "✅✅✅ Step 1 完了: DBモデル定義 + マイグレーション適用"
