#!/usr/bin/env bash
# =============================================================================
# decision-os / Phase 2: コメント機能（課題チャット）一括実装
# 
# 実装内容:
#   BE-1: Conversation モデル確認・存在しなければ作成
#   BE-2: schemas/conversation.py 作成
#   BE-3: routers/conversations.py 作成（GET/POST/DELETE）
#   BE-4: api.py に conversations_router 追加
#   BE-5: Alembic マイグレーション（conversations テーブルが未作成なら）
#   FE-1: client.ts に conversationApi 追加
#   FE-2: IssueDetail.tsx にコメントスレッドUI追加
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKEND_DIR="$PROJECT_DIR/backend"
FRONTEND_DIR="$PROJECT_DIR/frontend"
MODEL_DIR="$BACKEND_DIR/app/models"
SCHEMA_DIR="$BACKEND_DIR/app/schemas"
ROUTER_DIR="$BACKEND_DIR/app/api/v1/routers"
PAGES_DIR="$FRONTEND_DIR/src/pages"
API_DIR="$FRONTEND_DIR/src/api"
TS=$(date +%Y%m%d_%H%M%S)

mkdir -p "$PROJECT_DIR/backup_$TS"
info "バックアップ先: $PROJECT_DIR/backup_$TS/"

# =============================================================================
section "BE-1: conversations テーブル確認 & モデル作成"
# =============================================================================

# DBにテーブルが存在するか確認
source "$BACKEND_DIR/.venv/bin/activate"

TABLE_EXISTS=$(python3 - << 'PYEOF'
import os, sys
db_url = os.environ.get(
    'DATABASE_URL',
    'postgresql://dev:devpass_2ed89487@localhost:5439/decisionos'
)
try:
    import sqlalchemy as sa
    engine = sa.create_engine(db_url)
    with engine.connect() as conn:
        rows = conn.execute(sa.text(
            "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='conversations'"
        ))
        count = rows.scalar()
        print("YES" if count > 0 else "NO")
except Exception as e:
    print(f"ERR:{e}")
PYEOF
)

info "conversations テーブル存在: $TABLE_EXISTS"

# Conversation モデルファイル作成（存在しなければ）
if [[ ! -f "$MODEL_DIR/conversation.py" ]]; then
  cat > "$MODEL_DIR/conversation.py" << 'MODEL_EOF'
from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class Conversation(Base):
    __tablename__ = "conversations"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    issue_id = Column(UUID(as_uuid=False), ForeignKey("issues.id", ondelete="CASCADE"), nullable=False)
    author_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=True)
    body = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    issue = relationship("Issue", back_populates="conversations")
    author = relationship("User")
MODEL_EOF
  success "models/conversation.py 作成完了"
else
  success "models/conversation.py は既に存在"
fi

# Issue モデルに conversations リレーション追加（なければ）
if ! grep -q "conversations" "$MODEL_DIR/issue.py" 2>/dev/null; then
  python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/backend/app/models/issue.py")
with open(path) as f:
    content = f.read()

# relationship("Action") の後に conversations を追加
if "conversations" not in content:
    # back_populates がある最後の relationship の後に追記
    content = content.rstrip()
    # クラス末尾に追加
    if "relationship" in content:
        # 既存 relationship を探して後ろに追加
        content += '\n    conversations = relationship("Conversation", back_populates="issue", cascade="all, delete-orphan", order_by="Conversation.created_at")\n'
    with open(path, "w") as f:
        f.write(content)
    print("✅ Issue モデルに conversations relationship 追加")
else:
    print("ℹ️  Issue モデルに conversations は既に存在")
PYEOF
fi

# __init__.py に Conversation を追加
if ! grep -q "Conversation" "$MODEL_DIR/__init__.py" 2>/dev/null; then
  python3 - << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/backend/app/models/__init__.py")
with open(path) as f:
    content = f.read()
if "Conversation" not in content:
    content = content.replace(
        'from .learning_log import LearningLog',
        'from .conversation import Conversation\nfrom .learning_log import LearningLog'
    )
    # __all__ にも追加
    content = content.replace('"LearningLog"', '"Conversation", "LearningLog"')
    with open(path, "w") as f:
        f.write(content)
    print("✅ models/__init__.py に Conversation 追加")
else:
    print("ℹ️  models/__init__.py に Conversation は既に存在")
PYEOF
fi

# =============================================================================
section "BE-2: schemas/conversation.py 作成"
# =============================================================================

cat > "$SCHEMA_DIR/conversation.py" << 'SCHEMA_EOF'
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class ConversationCreate(BaseModel):
    issue_id: str
    body: str

class ConversationUpdate(BaseModel):
    body: str

class AuthorInfo(BaseModel):
    id: str
    name: str
    role: str

    class Config:
        from_attributes = True

class ConversationResponse(BaseModel):
    id: str
    issue_id: str
    author_id: Optional[str] = None
    body: str
    created_at: datetime
    updated_at: Optional[datetime] = None
    author: Optional[AuthorInfo] = None

    class Config:
        from_attributes = True
SCHEMA_EOF

success "schemas/conversation.py 作成完了"

# =============================================================================
section "BE-3: routers/conversations.py 作成"
# =============================================================================

cat > "$ROUTER_DIR/conversations.py" << 'ROUTER_EOF'
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
from ....core.deps import get_db, get_current_user
from ....models.conversation import Conversation
from ....models.issue import Issue
from ....models.user import User
from ....schemas.conversation import ConversationCreate, ConversationUpdate, ConversationResponse

router = APIRouter(prefix="/conversations", tags=["conversations"])


@router.get("", response_model=List[ConversationResponse])
def list_conversations(
    issue_id: str = Query(..., description="課題ID（必須）"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """課題に紐づくコメント一覧を取得（時系列昇順）"""
    issue = db.query(Issue).filter(Issue.id == issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")

    convs = (
        db.query(Conversation)
        .options(joinedload(Conversation.author))
        .filter(Conversation.issue_id == issue_id)
        .order_by(Conversation.created_at)
        .all()
    )
    return convs


@router.post("", response_model=ConversationResponse, status_code=201)
def create_conversation(
    payload: ConversationCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """コメントを投稿する"""
    issue = db.query(Issue).filter(Issue.id == payload.issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")

    if not payload.body.strip():
        raise HTTPException(status_code=422, detail="本文が空です")

    conv = Conversation(
        issue_id=payload.issue_id,
        author_id=current_user.id,
        body=payload.body.strip(),
    )
    db.add(conv)
    db.commit()
    db.refresh(conv)

    # author をロード
    db.refresh(conv)
    conv_with_author = (
        db.query(Conversation)
        .options(joinedload(Conversation.author))
        .filter(Conversation.id == conv.id)
        .first()
    )
    return conv_with_author


@router.patch("/{conv_id}", response_model=ConversationResponse)
def update_conversation(
    conv_id: str,
    payload: ConversationUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """自分のコメントを編集する"""
    conv = db.query(Conversation).filter(Conversation.id == conv_id).first()
    if not conv:
        raise HTTPException(status_code=404, detail="Comment not found")
    if conv.author_id != current_user.id:
        raise HTTPException(status_code=403, detail="自分のコメントのみ編集できます")

    conv.body = payload.body.strip()
    db.commit()
    db.refresh(conv)
    return conv


@router.delete("/{conv_id}", status_code=204)
def delete_conversation(
    conv_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """自分のコメントを削除する（Adminは全削除可）"""
    conv = db.query(Conversation).filter(Conversation.id == conv_id).first()
    if not conv:
        raise HTTPException(status_code=404, detail="Comment not found")
    if conv.author_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="自分のコメントのみ削除できます")

    db.delete(conv)
    db.commit()
    return None
ROUTER_EOF

success "routers/conversations.py 作成完了"

# =============================================================================
section "BE-4: api.py に conversations_router 追加"
# =============================================================================

cp "$BACKEND_DIR/app/api/v1/api.py" "$PROJECT_DIR/backup_$TS/api.py"

python3 - << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/backend/app/api/v1/api.py")
with open(path) as f:
    content = f.read()

if "conversations" not in content:
    content = content.replace(
        "from .routers.dashboard import router as dashboard_router",
        "from .routers.dashboard import router as dashboard_router\nfrom .routers.conversations import router as conversations_router"
    )
    content = content.replace(
        "api_router.include_router(dashboard_router)",
        "api_router.include_router(dashboard_router)\napi_router.include_router(conversations_router)"
    )
    with open(path, "w") as f:
        f.write(content)
    print("✅ api.py に conversations_router 追加")
else:
    print("ℹ️  api.py には既に conversations が存在")
PYEOF

success "api.py 更新完了"

# =============================================================================
section "BE-5: conversations テーブル作成（未存在なら Alembic or DDL直接）"
# =============================================================================

if [[ "$TABLE_EXISTS" == "NO" ]]; then
  info "conversations テーブルが存在しないため作成します"

  python3 - << 'PYEOF'
import os
db_url = os.environ.get(
    'DATABASE_URL',
    'postgresql://dev:devpass_2ed89487@localhost:5439/decisionos'
)
try:
    import sqlalchemy as sa
    engine = sa.create_engine(db_url)
    with engine.connect() as conn:
        conn.execute(sa.text("""
            CREATE TABLE IF NOT EXISTS conversations (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                issue_id UUID NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
                author_id UUID REFERENCES users(id),
                body TEXT NOT NULL CHECK(length(body) > 0),
                created_at TIMESTAMPTZ DEFAULT now(),
                updated_at TIMESTAMPTZ
            );
            CREATE INDEX IF NOT EXISTS idx_conversations_issue ON conversations(issue_id);
            CREATE INDEX IF NOT EXISTS idx_conversations_created ON conversations(created_at);
        """))
        conn.commit()
        print("✅ conversations テーブル作成完了")
except Exception as e:
    print(f"❌ エラー: {e}")
PYEOF

else
  info "conversations テーブルは既に存在 → スキップ"
fi

# =============================================================================
section "FE-1: client.ts に conversationApi 追加"
# =============================================================================

cp "$API_DIR/client.ts" "$PROJECT_DIR/backup_$TS/client.ts"

python3 - << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/frontend/src/api/client.ts")
with open(path) as f:
    content = f.read()

if "conversationApi" not in content:
    append = """
// Conversations (コメント)
export const conversationApi = {
  list: (issueId: string) => client.get(`/conversations?issue_id=${issueId}`),
  create: (data: { issue_id: string; body: string }) => client.post("/conversations", data),
  update: (id: string, body: string) => client.patch(`/conversations/${id}`, { body }),
  delete: (id: string) => client.delete(`/conversations/${id}`),
};
"""
    content = content.rstrip() + "\n" + append
    with open(path, "w") as f:
        f.write(content)
    print("✅ client.ts に conversationApi 追加")
else:
    print("ℹ️  client.ts に conversationApi は既に存在")
PYEOF

success "client.ts 更新完了"

# =============================================================================
section "FE-2: IssueDetail.tsx にコメントスレッドUI追加"
# =============================================================================

cp "$PAGES_DIR/IssueDetail.tsx" "$PROJECT_DIR/backup_$TS/IssueDetail.tsx"

cat > "$PAGES_DIR/IssueDetail.tsx" << 'TSX_EOF'
import { useState, useEffect, useRef } from "react";
import { useParams, useNavigate } from "react-router-dom";
import Layout from "../components/Layout";
import { issueApi, traceApi, conversationApi } from "../api/client";
import { STATUS_LABELS, PRIORITY_COLORS, type IssueStatus, type Priority } from "../types/index";

interface Issue {
  id: string; title: string; description?: string;
  status: IssueStatus; priority: Priority; labels?: string;
  created_at: string; updated_at?: string;
}

interface TraceData {
  issue?: any; action?: any; item?: any; input?: any;
}

interface Comment {
  id: string; body: string; created_at: string;
  author?: { id: string; name: string; role: string };
  author_id?: string;
}

type TabType = "detail" | "trace" | "comments";

export default function IssueDetail() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [issue, setIssue] = useState<Issue | null>(null);
  const [trace, setTrace] = useState<TraceData | null>(null);
  const [comments, setComments] = useState<Comment[]>([]);
  const [tab, setTab] = useState<TabType>("detail");
  const [loading, setLoading] = useState(true);
  const [commentBody, setCommentBody] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editBody, setEditBody] = useState("");
  const [error, setError] = useState("");
  const bottomRef = useRef<HTMLDivElement>(null);

  // 現在のユーザーID（JWTから簡易取得）
  const currentUserId = (() => {
    try {
      const token = localStorage.getItem("token") || "";
      const payload = token.split(".")[1];
      return JSON.parse(atob(payload)).sub || "";
    } catch { return ""; }
  })();

  useEffect(() => {
    if (!id) return;
    Promise.all([
      issueApi.get(id).then(r => setIssue(r.data)),
      traceApi.get(id).then(r => setTrace(r.data)).catch(() => {}),
      conversationApi.list(id).then(r => setComments(r.data)).catch(() => {}),
    ]).finally(() => setLoading(false));
  }, [id]);

  // コメントタブを開いた時に最下部にスクロール
  useEffect(() => {
    if (tab === "comments") {
      setTimeout(() => bottomRef.current?.scrollIntoView({ behavior: "smooth" }), 100);
    }
  }, [tab, comments.length]);

  const updateStatus = async (status: IssueStatus) => {
    if (!id) return;
    await issueApi.update(id, { status });
    setIssue(prev => prev ? { ...prev, status } : prev);
  };

  const submitComment = async () => {
    if (!id || !commentBody.trim()) return;
    setSubmitting(true); setError("");
    try {
      const res = await conversationApi.create({ issue_id: id, body: commentBody.trim() });
      setComments(prev => [...prev, res.data]);
      setCommentBody("");
    } catch (e: any) {
      setError(e.response?.data?.detail || "投稿に失敗しました");
    } finally { setSubmitting(false); }
  };

  const startEdit = (c: Comment) => {
    setEditingId(c.id); setEditBody(c.body);
  };

  const saveEdit = async (c: Comment) => {
    try {
      await conversationApi.update(c.id, editBody);
      setComments(prev => prev.map(x => x.id === c.id ? { ...x, body: editBody } : x));
      setEditingId(null);
    } catch { setError("更新に失敗しました"); }
  };

  const deleteComment = async (cid: string) => {
    if (!window.confirm("このコメントを削除しますか？")) return;
    try {
      await conversationApi.delete(cid);
      setComments(prev => prev.filter(x => x.id !== cid));
    } catch { setError("削除に失敗しました"); }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      submitComment();
    }
  };

  if (loading) return <Layout><div style={{ padding: "40px", textAlign: "center", color: "#64748b" }}>読み込み中...</div></Layout>;
  if (!issue) return <Layout><div style={{ padding: "40px", color: "#ef4444" }}>課題が見つかりません</div></Layout>;

  const STATUSES: IssueStatus[] = ["open", "doing", "review", "done", "hold"];

  return (
    <Layout>
      {/* ヘッダー */}
      <div style={{ marginBottom: "20px" }}>
        <button
          onClick={() => navigate("/issues")}
          style={{ background: "none", border: "none", color: "#64748b", cursor: "pointer", fontSize: "13px", padding: 0, marginBottom: "12px" }}
        >
          ← 課題一覧
        </button>
        <div style={{ display: "flex", alignItems: "flex-start", gap: "12px", flexWrap: "wrap" }}>
          <h1 style={{ flex: 1, margin: 0, fontSize: "20px", lineHeight: 1.4 }}>{issue.title}</h1>
          <span style={{
            padding: "4px 12px", borderRadius: "6px", fontSize: "12px",
            background: PRIORITY_COLORS[issue.priority] + "22",
            color: PRIORITY_COLORS[issue.priority], border: `1px solid ${PRIORITY_COLORS[issue.priority]}44`,
            flexShrink: 0,
          }}>
            {issue.priority}
          </span>
        </div>

        {/* ステータス切り替え */}
        <div style={{ display: "flex", gap: "6px", marginTop: "12px", flexWrap: "wrap" }}>
          {STATUSES.map(s => (
            <button
              key={s} onClick={() => updateStatus(s)}
              style={{
                padding: "6px 14px", borderRadius: "6px", border: "none",
                cursor: "pointer", fontSize: "13px", fontWeight: s === issue.status ? "700" : "400",
                background: s === issue.status ? "#3b82f6" : "#1e293b",
                color: s === issue.status ? "#fff" : "#64748b",
              }}
            >
              {STATUS_LABELS[s]}
            </button>
          ))}
        </div>
      </div>

      {error && (
        <div style={{
          background: "#fef2f2", border: "1px solid #fca5a5", borderRadius: "8px",
          padding: "10px 16px", marginBottom: "12px", color: "#dc2626", fontSize: "13px",
        }}>⚠️ {error}</div>
      )}

      {/* タブ */}
      <div style={{ display: "flex", gap: "4px", marginBottom: "20px", borderBottom: "1px solid #334155" }}>
        {([
          { key: "detail", label: "📋 詳細" },
          { key: "trace", label: "🔍 トレーサビリティ" },
          { key: "comments", label: `💬 コメント${comments.length > 0 ? ` (${comments.length})` : ""}` },
        ] as { key: TabType; label: string }[]).map(({ key, label }) => (
          <button
            key={key} onClick={() => setTab(key)}
            style={{
              padding: "10px 20px", border: "none", cursor: "pointer",
              background: "none", fontSize: "14px",
              color: tab === key ? "#3b82f6" : "#64748b",
              borderBottom: tab === key ? "2px solid #3b82f6" : "2px solid transparent",
              fontWeight: tab === key ? "600" : "400",
            }}
          >
            {label}
          </button>
        ))}
      </div>

      {/* 詳細タブ */}
      {tab === "detail" && (
        <div style={{ background: "#1e293b", borderRadius: "12px", padding: "24px" }}>
          <p style={{ color: "#64748b", margin: "0 0 8px", fontSize: "12px" }}>課題ID: {issue.id}</p>
          {issue.description && (
            <div style={{ marginTop: "16px" }}>
              <p style={{ color: "#94a3b8", fontSize: "13px", margin: "0 0 8px" }}>説明</p>
              <p style={{ color: "#e2e8f0", fontSize: "14px", lineHeight: 1.7, margin: 0 }}>{issue.description}</p>
            </div>
          )}
          {issue.labels && (
            <div style={{ marginTop: "16px" }}>
              <p style={{ color: "#94a3b8", fontSize: "13px", margin: "0 0 8px" }}>ラベル</p>
              <p style={{ color: "#e2e8f0", fontSize: "14px", margin: 0 }}>{issue.labels}</p>
            </div>
          )}
          <p style={{ color: "#475569", fontSize: "12px", margin: "20px 0 0" }}>
            作成: {new Date(issue.created_at).toLocaleString("ja-JP")}
            {issue.updated_at && ` ／ 更新: ${new Date(issue.updated_at).toLocaleString("ja-JP")}`}
          </p>
        </div>
      )}

      {/* トレーサビリティタブ */}
      {tab === "trace" && (
        <div style={{ background: "#1e293b", borderRadius: "12px", padding: "24px" }}>
          {trace ? (
            <>
              <h3 style={{ margin: "0 0 20px", fontSize: "16px" }}>🔍 意思決定トレーサー</h3>
              <div style={{ display: "flex", flexDirection: "column", gap: 0 }}>
                {[
                  { label: "📋 課題", data: trace.issue, fields: ["title", "status", "priority"] },
                  { label: "⚡ Action", data: trace.action, fields: ["action_type", "decision_reason", "decided_at"] },
                  { label: "🧩 分解ITEM", data: trace.item, fields: ["text", "intent_code", "domain_code", "confidence"] },
                  { label: "📥 原文（RAW_INPUT）", data: trace.input, fields: ["source_type", "raw_text", "created_at"] },
                ].map((layer, idx) => (
                  <div key={layer.label}>
                    <div style={{ background: "#0f172a", borderRadius: "8px", padding: "16px", borderLeft: "4px solid #3b82f6" }}>
                      <p style={{ margin: "0 0 10px", fontSize: "13px", color: "#60a5fa", fontWeight: "600" }}>{layer.label}</p>
                      {layer.data
                        ? layer.fields.map(f => (
                          <div key={f} style={{ marginBottom: "4px" }}>
                            <span style={{ color: "#64748b", fontSize: "12px" }}>{f}: </span>
                            <span style={{ color: "#e2e8f0", fontSize: "13px" }}>{String(layer.data[f] || "—").slice(0, 300)}</span>
                          </div>
                        ))
                        : <p style={{ margin: 0, color: "#475569", fontSize: "13px" }}>データなし</p>
                      }
                    </div>
                    {idx < 3 && (
                      <div style={{ display: "flex", justifyContent: "center", padding: "6px 0" }}>
                        <span style={{ color: "#3b82f6", fontSize: "20px" }}>↑</span>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </>
          ) : (
            <p style={{ color: "#64748b", textAlign: "center", padding: "40px 0" }}>
              トレースデータがありません（手動作成の課題）
            </p>
          )}
        </div>
      )}

      {/* コメントタブ */}
      {tab === "comments" && (
        <div style={{ display: "flex", flexDirection: "column", gap: "0" }}>
          {/* コメント一覧 */}
          <div style={{
            background: "#1e293b", borderRadius: "12px 12px 0 0",
            padding: "20px", minHeight: "200px",
            maxHeight: "480px", overflowY: "auto",
          }}>
            {comments.length === 0 ? (
              <div style={{ textAlign: "center", padding: "48px 0", color: "#475569" }}>
                <div style={{ fontSize: "32px", marginBottom: "12px" }}>💬</div>
                <p style={{ margin: 0, fontSize: "14px" }}>まだコメントがありません</p>
                <p style={{ margin: "4px 0 0", fontSize: "12px", color: "#334155" }}>最初のコメントを投稿してみましょう</p>
              </div>
            ) : (
              <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
                {comments.map(c => {
                  const isOwn = c.author_id === currentUserId;
                  const isEditing = editingId === c.id;
                  return (
                    <div key={c.id} style={{ display: "flex", gap: "10px", alignItems: "flex-start" }}>
                      {/* アバター */}
                      <div style={{
                        width: "32px", height: "32px", borderRadius: "50%", flexShrink: 0,
                        background: isOwn ? "#3b82f6" : "#475569",
                        display: "flex", alignItems: "center", justifyContent: "center",
                        fontSize: "13px", fontWeight: "700", color: "#fff",
                      }}>
                        {(c.author?.name || "?").slice(0, 1).toUpperCase()}
                      </div>

                      <div style={{ flex: 1 }}>
                        {/* 名前 + 時刻 */}
                        <div style={{ display: "flex", gap: "8px", alignItems: "center", marginBottom: "4px" }}>
                          <span style={{ fontSize: "13px", fontWeight: "600", color: "#e2e8f0" }}>
                            {c.author?.name || "ユーザー"}
                          </span>
                          <span style={{ fontSize: "11px", color: "#475569" }}>
                            {new Date(c.created_at).toLocaleString("ja-JP")}
                          </span>
                          {isOwn && !isEditing && (
                            <div style={{ marginLeft: "auto", display: "flex", gap: "4px" }}>
                              <button
                                onClick={() => startEdit(c)}
                                style={smallBtn("#334155", "#94a3b8")}
                              >✏️ 編集</button>
                              <button
                                onClick={() => deleteComment(c.id)}
                                style={smallBtn("#450a0a", "#ef4444")}
                              >🗑 削除</button>
                            </div>
                          )}
                        </div>

                        {/* 本文 / 編集フォーム */}
                        {isEditing ? (
                          <div>
                            <textarea
                              value={editBody}
                              onChange={e => setEditBody(e.target.value)}
                              style={{
                                width: "100%", padding: "8px 12px", borderRadius: "8px",
                                background: "#0f172a", border: "1px solid #3b82f6",
                                color: "#e2e8f0", fontSize: "14px", resize: "vertical",
                                minHeight: "64px", boxSizing: "border-box",
                              }}
                            />
                            <div style={{ display: "flex", gap: "6px", marginTop: "6px" }}>
                              <button onClick={() => saveEdit(c)} style={actionBtn("#3b82f6")}>保存</button>
                              <button onClick={() => setEditingId(null)} style={actionBtn("#475569")}>キャンセル</button>
                            </div>
                          </div>
                        ) : (
                          <div style={{
                            background: isOwn ? "#1e3a5f" : "#0f172a",
                            borderRadius: "0 8px 8px 8px", padding: "10px 14px",
                            color: "#e2e8f0", fontSize: "14px", lineHeight: 1.6,
                            border: `1px solid ${isOwn ? "#1d4ed8" : "#1e293b"}`,
                            whiteSpace: "pre-wrap",
                          }}>
                            {c.body}
                          </div>
                        )}
                      </div>
                    </div>
                  );
                })}
                <div ref={bottomRef} />
              </div>
            )}
          </div>

          {/* 投稿フォーム */}
          <div style={{
            background: "#162032", borderRadius: "0 0 12px 12px",
            padding: "16px", borderTop: "1px solid #334155",
          }}>
            <textarea
              value={commentBody}
              onChange={e => setCommentBody(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="コメントを入力... (Ctrl+Enter で投稿)"
              style={{
                width: "100%", padding: "10px 14px", borderRadius: "8px",
                background: "#0f172a", border: "1px solid #334155",
                color: "#e2e8f0", fontSize: "14px", resize: "none",
                minHeight: "72px", boxSizing: "border-box",
                outline: "none",
              }}
              onFocus={e => (e.target.style.borderColor = "#3b82f6")}
              onBlur={e => (e.target.style.borderColor = "#334155")}
            />
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: "8px" }}>
              <span style={{ fontSize: "11px", color: "#475569" }}>
                Ctrl+Enter で投稿 ／ {commentBody.length} 文字
              </span>
              <button
                onClick={submitComment}
                disabled={submitting || !commentBody.trim()}
                style={{
                  padding: "8px 20px", borderRadius: "8px", border: "none",
                  background: submitting || !commentBody.trim() ? "#334155" : "#3b82f6",
                  color: "#fff", cursor: submitting || !commentBody.trim() ? "not-allowed" : "pointer",
                  fontSize: "14px", fontWeight: "600",
                }}
              >
                {submitting ? "送信中..." : "💬 投稿"}
              </button>
            </div>
          </div>
        </div>
      )}
    </Layout>
  );
}

// スタイルヘルパー
const smallBtn = (bg: string, color: string): React.CSSProperties => ({
  padding: "2px 8px", borderRadius: "4px", border: "none",
  background: bg, color, cursor: "pointer", fontSize: "11px",
});

const actionBtn = (bg: string): React.CSSProperties => ({
  padding: "5px 14px", borderRadius: "6px", border: "none",
  background: bg, color: "#fff", cursor: "pointer", fontSize: "13px",
});
TSX_EOF

success "IssueDetail.tsx: コメントタブ追加完了"

# =============================================================================
section "バックエンド再起動 & 動作確認"
# =============================================================================

cd "$BACKEND_DIR"
pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 1

nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > ~/projects/decision-os/logs/backend.log 2>&1 &

echo "バックエンド起動中..."
sleep 4

HEALTH=$(curl -sf http://localhost:8089/health 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','NG'))" 2>/dev/null || echo "NG")

if [[ "$HEALTH" == "ok" ]]; then
  success "バックエンド起動確認 ✅"
else
  warn "起動確認失敗 → backend.log を確認: tail -30 ~/projects/decision-os/logs/backend.log"
fi

# conversations エンドポイント確認
CONV_FOUND=$(curl -sf http://localhost:8089/openapi.json 2>/dev/null | python3 -c "
import json,sys
spec=json.load(sys.stdin)
paths = spec.get('paths', {})
found = '/api/v1/conversations' in paths
print('YES' if found else 'NO')
" 2>/dev/null || echo "NO")

if [[ "$CONV_FOUND" == "YES" ]]; then
  success "GET/POST /api/v1/conversations 確認 ✅"
else
  warn "conversations エンドポイントが見つかりません → backend.log を確認"
  echo "tail -30 ~/projects/decision-os/logs/backend.log"
fi

# 実際にコメント投稿テスト
TOKEN=$(curl -sf -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token','ERR'))" 2>/dev/null || echo "ERR")

if [[ "$TOKEN" != "ERR" && -n "$TOKEN" ]]; then
  ISSUE_ID=$(curl -sf "http://localhost:8089/api/v1/issues" \
    -H "Authorization: Bearer $TOKEN" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else 'NONE')" 2>/dev/null || echo "NONE")

  if [[ "$ISSUE_ID" != "NONE" && -n "$ISSUE_ID" ]]; then
    POST_RES=$(curl -sf -X POST "http://localhost:8089/api/v1/conversations" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"issue_id\": \"$ISSUE_ID\", \"body\": \"テストコメントです。動作確認OK\"}" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','ERR'))" 2>/dev/null || echo "ERR")

    if [[ "$POST_RES" != "ERR" && -n "$POST_RES" ]]; then
      success "コメント投稿テスト OK (ID: ${POST_RES:0:8}...) ✅"
    else
      warn "コメント投稿失敗 → backend.log を確認"
    fi
  fi
fi

# =============================================================================
section "完了サマリー"
# =============================================================================
echo ""
echo -e "${BOLD}実装完了:${RESET}"
echo "  ✅ BE: conversations テーブル作成（未存在の場合）"
echo "  ✅ BE: models/conversation.py"
echo "  ✅ BE: schemas/conversation.py"
echo "  ✅ BE: routers/conversations.py（GET/POST/PATCH/DELETE）"
echo "  ✅ BE: api.py に conversations_router 追加"
echo "  ✅ FE: client.ts に conversationApi 追加"
echo "  ✅ FE: IssueDetail.tsx に 💬 コメントタブ追加"
echo ""
echo -e "${BOLD}ブラウザで確認:${RESET}"
echo "  1. http://localhost:3008 → 任意の課題を開く"
echo "  2. 💬 コメント タブをクリック"
echo "  3. コメントを入力 → 投稿ボタン or Ctrl+Enter"
echo "  4. 自分のコメントに ✏️ 編集・🗑 削除ボタンが表示される"
echo ""
success "Phase 2: コメント機能 実装完了！"
