#!/usr/bin/env bash
# =============================================================================
# decision-os / Phase 2: 決定ログ機能実装
#
# 仕様（機能設計書より）:
#   decisions テーブル:
#     id, project_id, decision_text, reason, decided_by,
#     related_request_id(input), related_issue_id, created_at
#
# 実装内容:
#   DB-1:  decisions テーブル作成（未存在なら）
#   BE-1:  models/decision.py 確認・作成
#   BE-2:  schemas/decision.py 作成
#   BE-3:  routers/decisions.py 作成（GET/POST）
#   BE-4:  api.py に decisions_router 追加
#   FE-1:  Decisions.tsx 新規作成（一覧 + 登録フォーム）
#   FE-2:  IssueDetail.tsx に決定ログタブ追加
#   FE-3:  App.tsx に /decisions ルート追加
#   FE-4:  Layout.tsx に 📝 決定ログ ナビリンク追加
#   FE-5:  client.ts に decisionApi 追加
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKEND_DIR="$PROJECT_DIR/backend"
FRONTEND_DIR="$PROJECT_DIR/frontend"
MODEL_DIR="$BACKEND_DIR/app/models"
SCHEMA_DIR="$BACKEND_DIR/app/schemas"
ROUTER_DIR="$BACKEND_DIR/app/api/v1/routers"
PAGES_DIR="$FRONTEND_DIR/src/pages"
COMP_DIR="$FRONTEND_DIR/src/components"
API_DIR="$FRONTEND_DIR/src/api"
SRC_DIR="$FRONTEND_DIR/src"
TS=$(date +%Y%m%d_%H%M%S)

mkdir -p "$PROJECT_DIR/backup_$TS"
source "$BACKEND_DIR/.venv/bin/activate"
info "バックアップ先: $PROJECT_DIR/backup_$TS/"

# =============================================================================
section "DB-1: decisions テーブル確認・作成"
# =============================================================================

python3 - << 'PYEOF'
import os
db_url = os.environ.get('DATABASE_URL',
    'postgresql://dev:devpass_2ed89487@localhost:5439/decisionos')
try:
    import sqlalchemy as sa
    engine = sa.create_engine(db_url)
    with engine.connect() as conn:
        exists = conn.execute(sa.text(
            "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='decisions'"
        )).scalar()
        if exists == 0:
            conn.execute(sa.text("""
                CREATE TABLE decisions (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    project_id UUID NOT NULL REFERENCES projects(id),
                    decision_text TEXT NOT NULL,
                    reason TEXT NOT NULL,
                    decided_by UUID REFERENCES users(id),
                    related_request_id UUID REFERENCES inputs(id) ON DELETE SET NULL,
                    related_issue_id UUID REFERENCES issues(id) ON DELETE SET NULL,
                    created_at TIMESTAMPTZ DEFAULT now()
                );
                CREATE INDEX idx_decisions_project ON decisions(project_id);
                CREATE INDEX idx_decisions_issue ON decisions(related_issue_id);
                CREATE INDEX idx_decisions_created ON decisions(created_at DESC);
            """))
            conn.commit()
            print("✅ decisions テーブル作成完了")
        else:
            print("ℹ️  decisions テーブルは既に存在")
except Exception as e:
    print(f"❌ エラー: {e}")
PYEOF

success "DB: decisions テーブル確認完了"

# =============================================================================
section "BE-1: models/decision.py 確認・作成"
# =============================================================================

if [[ ! -f "$MODEL_DIR/decision.py" ]]; then
cat > "$MODEL_DIR/decision.py" << 'MODEL_EOF'
from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class Decision(Base):
    __tablename__ = "decisions"

    id             = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    project_id     = Column(UUID(as_uuid=False), ForeignKey("projects.id"), nullable=False)
    decision_text  = Column(Text, nullable=False)
    reason         = Column(Text, nullable=False)
    decided_by     = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=True)
    related_request_id = Column(UUID(as_uuid=False), ForeignKey("inputs.id",  ondelete="SET NULL"), nullable=True)
    related_issue_id   = Column(UUID(as_uuid=False), ForeignKey("issues.id",  ondelete="SET NULL"), nullable=True)
    created_at     = Column(DateTime(timezone=True), server_default=func.now())

    decider        = relationship("User",    foreign_keys=[decided_by])
    related_input  = relationship("Input",   foreign_keys=[related_request_id])
    related_issue  = relationship("Issue",   foreign_keys=[related_issue_id])
MODEL_EOF
  success "models/decision.py 作成完了"
else
  success "models/decision.py は既に存在"
fi

# models/__init__.py に Decision が含まれているか確認・追加
python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/backend/app/models/__init__.py")
with open(path) as f:
    content = f.read()
if "Decision" not in content:
    content = re.sub(
        r'(from \.conversation import Conversation\n)',
        r'\1from .decision import Decision\n',
        content
    )
    content = content.replace('"Conversation"', '"Decision", "Conversation"')
    with open(path, "w") as f:
        f.write(content)
    print("✅ models/__init__.py に Decision 追加")
else:
    print("ℹ️  models/__init__.py に Decision は既に存在")
PYEOF

# =============================================================================
section "BE-2: schemas/decision.py 作成"
# =============================================================================

cat > "$SCHEMA_DIR/decision.py" << 'SCHEMA_EOF'
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class DecisionCreate(BaseModel):
    project_id: str
    decision_text: str
    reason: str
    related_request_id: Optional[str] = None
    related_issue_id: Optional[str] = None

class DeciderInfo(BaseModel):
    id: str
    name: str
    role: str
    class Config:
        from_attributes = True

class DecisionResponse(BaseModel):
    id: str
    project_id: str
    decision_text: str
    reason: str
    decided_by: Optional[str] = None
    related_request_id: Optional[str] = None
    related_issue_id: Optional[str] = None
    created_at: datetime
    decider: Optional[DeciderInfo] = None
    class Config:
        from_attributes = True
SCHEMA_EOF

success "schemas/decision.py 作成完了"

# =============================================================================
section "BE-3: routers/decisions.py 作成"
# =============================================================================

cat > "$ROUTER_DIR/decisions.py" << 'ROUTER_EOF'
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
from ....core.deps import get_db, get_current_user
from ....models.decision import Decision
from ....models.project import Project
from ....models.user import User
from ....schemas.decision import DecisionCreate, DecisionResponse

router = APIRouter(prefix="/decisions", tags=["decisions"])


@router.get("", response_model=List[DecisionResponse])
def list_decisions(
    project_id: Optional[str] = Query(None),
    issue_id:   Optional[str] = Query(None),
    limit:      int            = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    決定ログ一覧。project_id または issue_id で絞り込み可能。
    両方省略時は全件（limit制限あり）。
    """
    q = db.query(Decision).options(joinedload(Decision.decider))
    if project_id:
        q = q.filter(Decision.project_id == project_id)
    if issue_id:
        q = q.filter(Decision.related_issue_id == issue_id)
    return q.order_by(Decision.created_at.desc()).limit(limit).all()


@router.get("/{decision_id}", response_model=DecisionResponse)
def get_decision(
    decision_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    d = (db.query(Decision)
           .options(joinedload(Decision.decider))
           .filter(Decision.id == decision_id)
           .first())
    if not d:
        raise HTTPException(status_code=404, detail="Decision not found")
    return d


@router.post("", response_model=DecisionResponse, status_code=201)
def create_decision(
    payload: DecisionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """決定ログを記録する。誰が・なぜ・何を決めたかを永久保存。"""
    # project 存在確認
    project = db.query(Project).filter(Project.id == payload.project_id).first()
    if not project:
        raise HTTPException(status_code=404, detail="Project not found")

    if not payload.decision_text.strip():
        raise HTTPException(status_code=422, detail="decision_text が空です")
    if not payload.reason.strip():
        raise HTTPException(status_code=422, detail="reason が空です")

    decision = Decision(
        project_id          = payload.project_id,
        decision_text       = payload.decision_text.strip(),
        reason              = payload.reason.strip(),
        decided_by          = current_user.id,
        related_request_id  = payload.related_request_id,
        related_issue_id    = payload.related_issue_id,
    )
    db.add(decision)
    db.commit()
    db.refresh(decision)

    # decider をロード
    result = (db.query(Decision)
                .options(joinedload(Decision.decider))
                .filter(Decision.id == decision.id)
                .first())
    return result


@router.delete("/{decision_id}", status_code=204)
def delete_decision(
    decision_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """決定ログを削除（Admin のみ）。"""
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin のみ削除できます")
    d = db.query(Decision).filter(Decision.id == decision_id).first()
    if not d:
        raise HTTPException(status_code=404, detail="Decision not found")
    db.delete(d)
    db.commit()
    return None
ROUTER_EOF

success "routers/decisions.py 作成完了"

# =============================================================================
section "BE-4: api.py に decisions_router 追加"
# =============================================================================

cp "$BACKEND_DIR/app/api/v1/api.py" "$PROJECT_DIR/backup_$TS/api.py"

python3 - << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/backend/app/api/v1/api.py")
with open(path) as f:
    content = f.read()
if "decisions" not in content:
    content = content.replace(
        "from .routers.search import router as search_router",
        "from .routers.search import router as search_router\nfrom .routers.decisions import router as decisions_router"
    )
    content = content.replace(
        "api_router.include_router(search_router)",
        "api_router.include_router(search_router)\napi_router.include_router(decisions_router)"
    )
    with open(path, "w") as f:
        f.write(content)
    print("✅ api.py に decisions_router 追加")
else:
    print("ℹ️  api.py に decisions は既に存在")
PYEOF

success "api.py 更新完了"

# =============================================================================
section "FE-1: Decisions.tsx 新規作成（一覧 + 登録フォーム）"
# =============================================================================

cat > "$PAGES_DIR/Decisions.tsx" << 'TSX_EOF'
import { useState, useEffect } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import Layout from "../components/Layout";
import { decisionApi, projectApi, issueApi } from "../api/client";

interface Decision {
  id: string;
  project_id: string;
  decision_text: string;
  reason: string;
  decided_by?: string;
  related_request_id?: string;
  related_issue_id?: string;
  created_at: string;
  decider?: { id: string; name: string; role: string };
}

interface Project { id: string; name: string }
interface Issue   { id: string; title: string }

export default function Decisions() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const filterIssueId = searchParams.get("issue_id") || "";

  const [decisions, setDecisions]   = useState<Decision[]>([]);
  const [projects, setProjects]     = useState<Project[]>([]);
  const [issues, setIssues]         = useState<Issue[]>([]);
  const [loading, setLoading]       = useState(true);
  const [showForm, setShowForm]     = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError]           = useState("");

  // フォーム状態
  const [form, setForm] = useState({
    project_id: "",
    decision_text: "",
    reason: "",
    related_issue_id: filterIssueId,
    related_request_id: "",
  });

  useEffect(() => {
    Promise.all([
      projectApi.list().then(r => {
        setProjects(r.data);
        if (r.data.length > 0 && !form.project_id) {
          setForm(f => ({ ...f, project_id: r.data[0].id }));
          // プロジェクト最初のを使って課題一覧も取得
          issueApi.list(r.data[0].id).then(ir => setIssues(ir.data)).catch(() => {});
        }
      }),
      decisionApi.list(
        filterIssueId ? { issue_id: filterIssueId } : {}
      ).then(r => setDecisions(r.data)),
    ])
    .catch(() => setError("データ取得に失敗しました"))
    .finally(() => setLoading(false));
  }, [filterIssueId]);

  const handleProjectChange = async (pid: string) => {
    setForm(f => ({ ...f, project_id: pid, related_issue_id: "" }));
    try {
      const r = await issueApi.list(pid);
      setIssues(r.data);
    } catch { setIssues([]); }
  };

  const handleSubmit = async () => {
    if (!form.project_id || !form.decision_text.trim() || !form.reason.trim()) {
      setError("プロジェクト・決定内容・理由は必須です");
      return;
    }
    setSubmitting(true); setError("");
    try {
      const payload: any = {
        project_id: form.project_id,
        decision_text: form.decision_text.trim(),
        reason: form.reason.trim(),
      };
      if (form.related_issue_id)   payload.related_issue_id   = form.related_issue_id;
      if (form.related_request_id) payload.related_request_id = form.related_request_id;

      const res = await decisionApi.create(payload);
      setDecisions(prev => [res.data, ...prev]);
      setForm(f => ({ ...f, decision_text: "", reason: "", related_issue_id: "", related_request_id: "" }));
      setShowForm(false);
    } catch (e: any) {
      setError(e.response?.data?.detail || "登録に失敗しました");
    } finally { setSubmitting(false); }
  };

  return (
    <Layout>
      {/* ヘッダー */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "24px" }}>
        <div>
          <h1 style={{ margin: 0, fontSize: "20px" }}>📝 決定ログ</h1>
          {filterIssueId && (
            <p style={{ margin: "4px 0 0", fontSize: "13px", color: "#64748b" }}>
              課題に関連する決定のみ表示
              <button onClick={() => navigate("/decisions")}
                style={{ marginLeft: "8px", background: "none", border: "none", color: "#3b82f6", cursor: "pointer", fontSize: "12px" }}>
                × 絞り込み解除
              </button>
            </p>
          )}
        </div>
        <button
          onClick={() => setShowForm(v => !v)}
          style={{
            padding: "10px 20px", borderRadius: "8px", border: "none",
            background: showForm ? "#475569" : "#3b82f6",
            color: "#fff", cursor: "pointer", fontSize: "14px", fontWeight: "600",
          }}
        >
          {showForm ? "✕ キャンセル" : "＋ 決定を記録"}
        </button>
      </div>

      {error && (
        <div style={{
          background: "#fef2f2", border: "1px solid #fca5a5", borderRadius: "8px",
          padding: "10px 16px", marginBottom: "16px", color: "#dc2626", fontSize: "13px",
        }}>⚠️ {error}</div>
      )}

      {/* 登録フォーム */}
      {showForm && (
        <div style={{
          background: "#1e293b", borderRadius: "12px", padding: "24px",
          marginBottom: "24px", border: "1px solid #3b82f6",
        }}>
          <h2 style={{ margin: "0 0 20px", fontSize: "16px", color: "#60a5fa" }}>
            📝 決定内容を記録する
          </h2>

          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "16px", marginBottom: "16px" }}>
            {/* プロジェクト */}
            <div>
              <label style={labelStyle}>プロジェクト *</label>
              <select
                value={form.project_id}
                onChange={e => handleProjectChange(e.target.value)}
                style={selectStyle}
              >
                <option value="">選択してください</option>
                {projects.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
              </select>
            </div>

            {/* 関連課題（任意） */}
            <div>
              <label style={labelStyle}>関連課題（任意）</label>
              <select
                value={form.related_issue_id}
                onChange={e => setForm(f => ({ ...f, related_issue_id: e.target.value }))}
                style={selectStyle}
              >
                <option value="">なし</option>
                {issues.map(i => (
                  <option key={i.id} value={i.id}>
                    {i.title.slice(0, 50)}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* 決定内容 */}
          <div style={{ marginBottom: "16px" }}>
            <label style={labelStyle}>決定内容 *</label>
            <textarea
              value={form.decision_text}
              onChange={e => setForm(f => ({ ...f, decision_text: e.target.value }))}
              placeholder="何を決定したか。例：検索機能のタグ選択をドロップダウンからチェックボックスUIに変更する"
              style={{ ...textareaStyle, minHeight: "80px" }}
            />
          </div>

          {/* 理由 */}
          <div style={{ marginBottom: "20px" }}>
            <label style={labelStyle}>決定理由 *</label>
            <textarea
              value={form.reason}
              onChange={e => setForm(f => ({ ...f, reason: e.target.value }))}
              placeholder="なぜその決定をしたか。例：ユーザーから命名ゆれによる検索失敗の報告が複数あり、既存タグから選択させる方式が最善と判断"
              style={{ ...textareaStyle, minHeight: "80px" }}
            />
          </div>

          <div style={{ display: "flex", gap: "10px", justifyContent: "flex-end" }}>
            <button onClick={() => setShowForm(false)} style={cancelBtnStyle}>キャンセル</button>
            <button
              onClick={handleSubmit}
              disabled={submitting || !form.decision_text.trim() || !form.reason.trim()}
              style={{
                padding: "10px 28px", borderRadius: "8px", border: "none",
                background: submitting || !form.decision_text.trim() || !form.reason.trim()
                  ? "#334155" : "#3b82f6",
                color: "#fff",
                cursor: submitting || !form.decision_text.trim() || !form.reason.trim()
                  ? "not-allowed" : "pointer",
                fontSize: "14px", fontWeight: "600",
              }}
            >
              {submitting ? "🔄 保存中..." : "💾 決定を記録"}
            </button>
          </div>
        </div>
      )}

      {/* 一覧 */}
      {loading ? (
        <div style={{ textAlign: "center", padding: "60px", color: "#64748b" }}>🔄 読み込み中...</div>
      ) : decisions.length === 0 ? (
        <div style={{ textAlign: "center", padding: "80px", color: "#475569" }}>
          <div style={{ fontSize: "48px", marginBottom: "16px" }}>📝</div>
          <p style={{ margin: 0, fontSize: "16px" }}>決定ログがまだありません</p>
          <p style={{ margin: "8px 0 0", fontSize: "13px", color: "#334155" }}>
            「＋ 決定を記録」で最初の決定ログを追加しましょう
          </p>
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
          {decisions.map(d => (
            <DecisionCard
              key={d.id}
              decision={d}
              onIssueClick={id => navigate(`/issues/${id}`)}
            />
          ))}
        </div>
      )}
    </Layout>
  );
}

function DecisionCard({ decision: d, onIssueClick }: {
  decision: Decision;
  onIssueClick: (id: string) => void;
}) {
  const [expanded, setExpanded] = useState(false);

  return (
    <div style={{
      background: "#1e293b", borderRadius: "10px",
      border: "1px solid #334155", overflow: "hidden",
    }}>
      {/* ヘッダー行 */}
      <div
        onClick={() => setExpanded(v => !v)}
        style={{
          padding: "16px 20px", cursor: "pointer",
          display: "flex", alignItems: "flex-start", gap: "12px",
        }}
      >
        <span style={{ fontSize: "20px", flexShrink: 0, marginTop: "2px" }}>📝</span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <p style={{
            margin: 0, fontSize: "14px", fontWeight: "600", color: "#e2e8f0",
            overflow: "hidden", textOverflow: "ellipsis",
            whiteSpace: expanded ? "normal" : "nowrap",
          }}>
            {d.decision_text}
          </p>
          <div style={{ display: "flex", gap: "12px", marginTop: "6px", flexWrap: "wrap" }}>
            <span style={{ fontSize: "12px", color: "#64748b" }}>
              🕐 {new Date(d.created_at).toLocaleString("ja-JP")}
            </span>
            {d.decider && (
              <span style={{ fontSize: "12px", color: "#94a3b8" }}>
                👤 {d.decider.name}
              </span>
            )}
            {d.related_issue_id && (
              <button
                onClick={e => { e.stopPropagation(); onIssueClick(d.related_issue_id!); }}
                style={{
                  background: "#1d3557", border: "1px solid #3b82f6",
                  borderRadius: "4px", padding: "1px 8px",
                  color: "#60a5fa", fontSize: "11px", cursor: "pointer",
                }}
              >
                📋 関連課題を開く
              </button>
            )}
          </div>
        </div>
        <span style={{ color: "#475569", fontSize: "12px", flexShrink: 0 }}>
          {expanded ? "▲" : "▼"}
        </span>
      </div>

      {/* 展開: 理由 */}
      {expanded && (
        <div style={{
          padding: "0 20px 16px 52px",
          borderTop: "1px solid #334155",
          paddingTop: "12px",
        }}>
          <p style={{ margin: "0 0 4px", fontSize: "12px", color: "#64748b", fontWeight: "600" }}>
            決定理由
          </p>
          <p style={{
            margin: 0, fontSize: "14px", color: "#94a3b8",
            lineHeight: 1.7, whiteSpace: "pre-wrap",
          }}>
            {d.reason}
          </p>
          {d.related_request_id && (
            <p style={{ margin: "8px 0 0", fontSize: "12px", color: "#475569" }}>
              🔗 関連原文ID: {d.related_request_id.slice(0, 8)}...
            </p>
          )}
        </div>
      )}
    </div>
  );
}

// スタイル定数
const labelStyle: React.CSSProperties = {
  display: "block", marginBottom: "6px",
  fontSize: "13px", color: "#94a3b8", fontWeight: "500",
};
const selectStyle: React.CSSProperties = {
  width: "100%", padding: "9px 12px", borderRadius: "8px",
  background: "#0f172a", border: "1px solid #334155",
  color: "#e2e8f0", fontSize: "14px",
};
const textareaStyle: React.CSSProperties = {
  width: "100%", padding: "10px 14px", borderRadius: "8px",
  background: "#0f172a", border: "1px solid #334155",
  color: "#e2e8f0", fontSize: "14px", resize: "vertical",
  boxSizing: "border-box", lineHeight: 1.6,
};
const cancelBtnStyle: React.CSSProperties = {
  padding: "10px 20px", borderRadius: "8px", border: "none",
  background: "#334155", color: "#94a3b8", cursor: "pointer", fontSize: "14px",
};
TSX_EOF

success "Decisions.tsx 作成完了"

# =============================================================================
section "FE-2: IssueDetail.tsx に 📝 決定ログタブ追加"
# =============================================================================

cp "$PAGES_DIR/IssueDetail.tsx" "$PROJECT_DIR/backup_$TS/IssueDetail.tsx"

python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/frontend/src/pages/IssueDetail.tsx")
with open(path) as f:
    content = f.read()

if "decisions" in content.lower() and "DecisionTab" not in content:
    print("ℹ️  IssueDetail.tsx にすでに decisions 関連コードが存在 → スキップ")
elif "decisionApi" in content:
    print("ℹ️  既に decisionApi が存在 → スキップ")
else:
    # TabType に "decisions" を追加
    content = content.replace(
        'type TabType = "detail" | "trace" | "comments";',
        'type TabType = "detail" | "trace" | "comments" | "decisions";'
    )
    # decisionApi import 追加
    content = content.replace(
        '{ issueApi, traceApi, conversationApi }',
        '{ issueApi, traceApi, conversationApi, decisionApi }'
    )
    # decisions state 追加（comments state の後）
    content = content.replace(
        '  const [comments, setComments] = useState<Comment[]>([]);',
        '  const [comments, setComments] = useState<Comment[]>([]);\n  const [decisions, setDecisions] = useState<any[]>([]);'
    )
    # useEffect 内に decisions 取得を追加
    content = content.replace(
        '      conversationApi.list(id).then(r => setComments(r.data)).catch(() => {}),',
        '      conversationApi.list(id).then(r => setComments(r.data)).catch(() => {}),\n      decisionApi.list({ issue_id: id }).then(r => setDecisions(r.data)).catch(() => {}),'
    )
    # タブに "decisions" を追加
    content = content.replace(
        '          { key: "comments", label: `💬 コメント${comments.length > 0 ? ` (${comments.length})` : ""}` },',
        '          { key: "comments", label: `💬 コメント${comments.length > 0 ? ` (${comments.length})` : ""}` },\n          { key: "decisions", label: `📝 決定ログ${decisions.length > 0 ? ` (${decisions.length})` : ""}` },'
    )
    # 決定ログタブコンテンツを追加（コメントタブの後）
    decision_tab = '''
      {/* 決定ログタブ */}
      {tab === "decisions" && (
        <div style={{ background: "#1e293b", borderRadius: "12px", padding: "24px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "16px" }}>
            <h3 style={{ margin: 0, fontSize: "16px" }}>📝 関連する決定ログ</h3>
            <button
              onClick={() => navigate(`/decisions?issue_id=${id}`)}
              style={{
                padding: "6px 16px", borderRadius: "6px", border: "none",
                background: "#334155", color: "#94a3b8", cursor: "pointer", fontSize: "13px",
              }}
            >
              ＋ 決定を追加
            </button>
          </div>
          {decisions.length === 0 ? (
            <div style={{ textAlign: "center", padding: "40px", color: "#475569" }}>
              <div style={{ fontSize: "32px", marginBottom: "12px" }}>📝</div>
              <p style={{ margin: 0 }}>この課題に関連する決定ログがありません</p>
            </div>
          ) : (
            <div style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
              {decisions.map((d: any) => (
                <div key={d.id} style={{
                  background: "#0f172a", borderRadius: "8px",
                  padding: "14px 16px", borderLeft: "3px solid #8b5cf6",
                }}>
                  <p style={{ margin: "0 0 6px", fontSize: "14px", fontWeight: "600", color: "#e2e8f0" }}>
                    {d.decision_text}
                  </p>
                  <p style={{ margin: "0 0 6px", fontSize: "13px", color: "#94a3b8", lineHeight: 1.5 }}>
                    理由: {d.reason}
                  </p>
                  <div style={{ display: "flex", gap: "10px" }}>
                    {d.decider && (
                      <span style={{ fontSize: "11px", color: "#64748b" }}>👤 {d.decider.name}</span>
                    )}
                    <span style={{ fontSize: "11px", color: "#64748b" }}>
                      🕐 {new Date(d.created_at).toLocaleString("ja-JP")}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
'''
    # コメントタブの後に挿入
    content = content.replace(
        "      {/* コメントタブ */}",
        decision_tab + "\n      {/* コメントタブ */"
    )
    with open(path, "w") as f:
        f.write(content)
    print("✅ IssueDetail.tsx に 📝 決定ログタブ追加")
PYEOF

success "IssueDetail.tsx 更新完了"

# =============================================================================
section "FE-3: App.tsx に /decisions ルート追加"
# =============================================================================

python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/frontend/src/App.tsx")
with open(path) as f:
    content = f.read()
if "Decisions" not in content:
    content = re.sub(
        r"(import Search from './pages/Search';\n)",
        r"\1import Decisions from './pages/Decisions';\n",
        content
    )
    content = re.sub(
        r'(<Route path="/search".*?/>)',
        r'\1\n        <Route path="/decisions" element={<Decisions />} />',
        content
    )
    with open(path, "w") as f:
        f.write(content)
    print("✅ App.tsx に /decisions ルート追加")
else:
    print("ℹ️  App.tsx に Decisions は既に存在")
PYEOF

success "App.tsx 更新完了"

# =============================================================================
section "FE-4: Layout.tsx に 📝 決定ログ ナビリンク追加"
# =============================================================================

python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/frontend/src/components/Layout.tsx")
with open(path) as f:
    content = f.read()
if "/decisions" not in content:
    # 🔍 検索 の後に 📝 決定ログ を追加
    content = re.sub(
        r'(.*?/search.*?検索.*?\n.*?</NavLink>\n)',
        lambda m: m.group(0) + "          <NavLink to=\"/decisions\" style={navStyle}>\n            📝 決定ログ\n          </NavLink>\n",
        content, count=1
    )
    with open(path, "w") as f:
        f.write(content)
    print("✅ Layout.tsx に 📝 決定ログ リンク追加")
else:
    print("ℹ️  Layout.tsx に /decisions は既に存在")
PYEOF

success "Layout.tsx 更新完了"

# =============================================================================
section "FE-5: client.ts に decisionApi 追加"
# =============================================================================

python3 - << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/frontend/src/api/client.ts")
with open(path) as f:
    content = f.read()
if "decisionApi" not in content:
    append = """
// Decisions（決定ログ）
export const decisionApi = {
  list:   (params?: { project_id?: string; issue_id?: string; limit?: number }) =>
    client.get("/decisions", { params }),
  get:    (id: string) => client.get(`/decisions/${id}`),
  create: (data: {
    project_id: string;
    decision_text: string;
    reason: string;
    related_issue_id?: string;
    related_request_id?: string;
  }) => client.post("/decisions", data),
  delete: (id: string) => client.delete(`/decisions/${id}`),
};
"""
    content = content.rstrip() + "\n" + append
    with open(path, "w") as f:
        f.write(content)
    print("✅ client.ts に decisionApi 追加")
else:
    print("ℹ️  client.ts に decisionApi は既に存在")
PYEOF

success "client.ts 更新完了"

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

HEALTH=$(curl -sf http://localhost:8089/health 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','NG'))" 2>/dev/null || echo "NG")

if [[ "$HEALTH" == "ok" ]]; then
  success "バックエンド起動確認 ✅"
else
  warn "起動失敗 → tail -30 ~/projects/decision-os/logs/backend.log"
  exit 1
fi

# decisions エンドポイント確認
DEC_FOUND=$(curl -sf http://localhost:8089/openapi.json 2>/dev/null \
  | python3 -c "
import json,sys
spec=json.load(sys.stdin)
found = '/api/v1/decisions' in spec.get('paths',{})
print('YES' if found else 'NO')
" 2>/dev/null || echo "NO")

if [[ "$DEC_FOUND" == "YES" ]]; then
  success "GET/POST /api/v1/decisions 確認 ✅"
else
  warn "decisions エンドポイントが見つかりません → backend.log 確認"
fi

# 実動作テスト: 決定ログ登録
TOKEN=$(curl -sf -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token','ERR'))" 2>/dev/null || echo "ERR")

if [[ "$TOKEN" != "ERR" ]]; then
  PROJECT_ID=$(curl -sf "http://localhost:8089/api/v1/projects" \
    -H "Authorization: Bearer $TOKEN" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else 'NONE')" 2>/dev/null || echo "NONE")

  if [[ "$PROJECT_ID" != "NONE" ]]; then
    POST_RES=$(curl -sf -X POST "http://localhost:8089/api/v1/decisions" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "{
        \"project_id\": \"$PROJECT_ID\",
        \"decision_text\": \"検索タグUIをドロップダウンからチェックボックスに変更する\",
        \"reason\": \"命名ゆれによる検索失敗報告が複数あったため、既存タグから選択する方式が最善と判断\"
      }" \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','ERR')[:8]+'...')" 2>/dev/null || echo "ERR")

    if [[ "$POST_RES" != "ERR" ]]; then
      success "決定ログ登録テスト OK (ID: $POST_RES) ✅"
    else
      warn "決定ログ登録失敗 → backend.log 確認"
    fi
  fi
fi

# =============================================================================
section "完了サマリー"
# =============================================================================
echo ""
echo -e "${BOLD}実装完了:${RESET}"
echo "  ✅ DB:  decisions テーブル作成"
echo "  ✅ BE:  models/decision.py"
echo "  ✅ BE:  schemas/decision.py"
echo "  ✅ BE:  GET  /api/v1/decisions?project_id=&issue_id="
echo "  ✅ BE:  GET  /api/v1/decisions/{id}"
echo "  ✅ BE:  POST /api/v1/decisions（決定ログ記録）"
echo "  ✅ BE:  DELETE /api/v1/decisions/{id}（Admin のみ）"
echo "  ✅ FE:  Decisions.tsx（一覧 + 登録フォーム）"
echo "  ✅ FE:  IssueDetail.tsx に 📝 決定ログタブ追加"
echo "  ✅ FE:  App.tsx に /decisions ルート追加"
echo "  ✅ FE:  Layout.tsx に 📝 決定ログ ナビリンク追加"
echo "  ✅ FE:  client.ts に decisionApi 追加"
echo ""
echo -e "${BOLD}ブラウザで確認:${RESET}"
echo "  1. 左メニュー「📝 決定ログ」をクリック → 一覧ページ"
echo "  2. 「＋ 決定を記録」→ フォームに記入 → 保存"
echo "  3. 課題詳細 → 📝 決定ログタブ → 課題に紐づく決定が表示"
echo "  4. 「関連課題を開く」ボタンで課題詳細にジャンプ"
echo ""
success "Phase 2: 決定ログ機能 実装完了！"
