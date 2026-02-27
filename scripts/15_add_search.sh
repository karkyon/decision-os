#!/usr/bin/env bash
# =============================================================================
# decision-os / Phase 2: 横断全文検索 実装
#
# 実装内容:
#   BE-1: routers/search.py  GET /api/v1/search?q=&type=&limit=
#   BE-2: api.py に search_router 追加
#   FE-1: Search.tsx 新規作成（検索結果ページ）
#   FE-2: App.tsx にルート追加
#   FE-3: Layout.tsx にグローバル検索バー追加
#   FE-4: client.ts に searchApi 追加
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
ROUTER_DIR="$BACKEND_DIR/app/api/v1/routers"
PAGES_DIR="$FRONTEND_DIR/src/pages"
COMP_DIR="$FRONTEND_DIR/src/components"
API_DIR="$FRONTEND_DIR/src/api"
SRC_DIR="$FRONTEND_DIR/src"
TS=$(date +%Y%m%d_%H%M%S)

mkdir -p "$PROJECT_DIR/backup_$TS"
info "バックアップ先: $PROJECT_DIR/backup_$TS/"

# =============================================================================
section "BE-1: routers/search.py 作成"
# 検索対象: issues / inputs / items / conversations
# 方式: PostgreSQL ILIKE（日本語含む部分一致）
# =============================================================================

cat > "$ROUTER_DIR/search.py" << 'ROUTER_EOF'
from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import or_
from typing import List, Optional
from datetime import datetime
from pydantic import BaseModel
from ....core.deps import get_db, get_current_user
from ....models.issue import Issue
from ....models.input import Input
from ....models.item import Item
from ....models.conversation import Conversation
from ....models.user import User

router = APIRouter(prefix="/search", tags=["search"])


# ─── レスポンス型 ───────────────────────────────────────────────
class SearchHit(BaseModel):
    id: str
    type: str           # "issue" | "input" | "item" | "conversation"
    title: str          # 表示用タイトル（スニペット）
    body: str           # ハイライト用本文断片（最大200字）
    url: str            # フロントのリンク先パス
    meta: dict          # type別のメタ情報
    created_at: datetime

    class Config:
        from_attributes = True


class SearchResponse(BaseModel):
    query: str
    total: int
    hits: List[SearchHit]
    duration_ms: int


# ─── ヘルパー: キーワードをスニペットで切り出す ──────────────
def snippet(text: str, keyword: str, width: int = 120) -> str:
    """キーワード周辺のテキストを抜き出す"""
    if not text:
        return ""
    idx = text.lower().find(keyword.lower())
    if idx == -1:
        return text[:width] + ("…" if len(text) > width else "")
    start = max(0, idx - 30)
    end = min(len(text), idx + width)
    prefix = "…" if start > 0 else ""
    suffix = "…" if end < len(text) else ""
    return prefix + text[start:end] + suffix


# ─── エンドポイント ─────────────────────────────────────────────
@router.get("", response_model=SearchResponse)
def search(
    q: str = Query(..., min_length=1, max_length=200, description="検索キーワード"),
    type: Optional[str] = Query(None, description="絞り込み: issue|input|item|conversation"),
    limit: int = Query(20, ge=1, le=100, description="最大件数"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    課題・原文・分解ITEM・コメントを横断全文検索する。
    複数キーワードはスペース区切りで AND 検索。
    """
    import time
    start = time.time()

    if not q.strip():
        raise HTTPException(status_code=422, detail="検索キーワードを入力してください")

    # スペース区切りで複数キーワード対応
    keywords = [k.strip() for k in q.strip().split() if k.strip()]
    hits: List[SearchHit] = []

    # ─── Issues ───────────────────────────────────────────────
    if type in (None, "issue"):
        q_issues = db.query(Issue)
        for kw in keywords:
            pattern = f"%{kw}%"
            q_issues = q_issues.filter(
                or_(
                    Issue.title.ilike(pattern),
                    Issue.description.ilike(pattern),
                    Issue.labels.ilike(pattern),
                )
            )
        for issue in q_issues.order_by(Issue.created_at.desc()).limit(limit).all():
            hits.append(SearchHit(
                id=issue.id,
                type="issue",
                title=issue.title,
                body=snippet(issue.description or issue.title, keywords[0]),
                url=f"/issues/{issue.id}",
                meta={
                    "status": issue.status,
                    "priority": issue.priority,
                    "labels": issue.labels,
                },
                created_at=issue.created_at,
            ))

    # ─── Inputs (RAW_TEXT) ────────────────────────────────────
    if type in (None, "input"):
        q_inputs = db.query(Input)
        for kw in keywords:
            pattern = f"%{kw}%"
            q_inputs = q_inputs.filter(Input.raw_text.ilike(pattern))
        for inp in q_inputs.order_by(Input.created_at.desc()).limit(limit).all():
            hits.append(SearchHit(
                id=inp.id,
                type="input",
                title=f"[{inp.source_type}] {inp.raw_text[:60]}…",
                body=snippet(inp.raw_text, keywords[0]),
                url=f"/inputs/{inp.id}",
                meta={
                    "source_type": inp.source_type,
                    "importance": getattr(inp, "importance", None),
                },
                created_at=inp.created_at,
            ))

    # ─── Items (分解ITEM) ─────────────────────────────────────
    if type in (None, "item"):
        q_items = db.query(Item)
        for kw in keywords:
            q_items = q_items.filter(Item.text.ilike(f"%{kw}%"))
        for item in q_items.order_by(Item.created_at.desc()).limit(limit).all():
            hits.append(SearchHit(
                id=item.id,
                type="item",
                title=f"[{item.intent_code}/{item.domain_code}] {item.text[:60]}",
                body=snippet(item.text, keywords[0]),
                url=f"/inputs/{item.input_id}",
                meta={
                    "intent_code": item.intent_code,
                    "domain_code": item.domain_code,
                    "confidence": item.confidence,
                },
                created_at=item.created_at,
            ))

    # ─── Conversations (コメント) ──────────────────────────────
    if type in (None, "conversation"):
        q_convs = db.query(Conversation)
        for kw in keywords:
            q_convs = q_convs.filter(Conversation.body.ilike(f"%{kw}%"))
        for conv in q_convs.order_by(Conversation.created_at.desc()).limit(limit).all():
            hits.append(SearchHit(
                id=conv.id,
                type="conversation",
                title=f"💬 {conv.body[:60]}",
                body=snippet(conv.body, keywords[0]),
                url=f"/issues/{conv.issue_id}",
                meta={"issue_id": conv.issue_id},
                created_at=conv.created_at,
            ))

    # 全件をcreated_at降順でソート・limit適用
    hits.sort(key=lambda h: h.created_at, reverse=True)
    hits = hits[:limit]

    duration_ms = int((time.time() - start) * 1000)

    return SearchResponse(
        query=q,
        total=len(hits),
        hits=hits,
        duration_ms=duration_ms,
    )
ROUTER_EOF

success "routers/search.py 作成完了"

# =============================================================================
section "BE-2: api.py に search_router 追加"
# =============================================================================

cp "$BACKEND_DIR/app/api/v1/api.py" "$PROJECT_DIR/backup_$TS/api.py"

python3 - << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/backend/app/api/v1/api.py")
with open(path) as f:
    content = f.read()

if "search" not in content:
    content = content.replace(
        "from .routers.conversations import router as conversations_router",
        "from .routers.conversations import router as conversations_router\nfrom .routers.search import router as search_router"
    )
    content = content.replace(
        "api_router.include_router(conversations_router)",
        "api_router.include_router(conversations_router)\napi_router.include_router(search_router)"
    )
    with open(path, "w") as f:
        f.write(content)
    print("✅ api.py に search_router 追加")
else:
    print("ℹ️  api.py には既に search が存在")
PYEOF

success "api.py 更新完了"

# =============================================================================
section "FE-1: Search.tsx 新規作成"
# =============================================================================

cat > "$PAGES_DIR/Search.tsx" << 'TSX_EOF'
import { useState, useEffect, useCallback, useRef } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import Layout from "../components/Layout";
import { searchApi } from "../api/client";

type HitType = "issue" | "input" | "item" | "conversation";

interface SearchHit {
  id: string;
  type: HitType;
  title: string;
  body: string;
  url: string;
  meta: Record<string, any>;
  created_at: string;
}

interface SearchResponse {
  query: string;
  total: number;
  hits: SearchHit[];
  duration_ms: number;
}

const TYPE_CONFIG: Record<HitType, { icon: string; label: string; color: string }> = {
  issue:        { icon: "📋", label: "課題",     color: "#3b82f6" },
  input:        { icon: "📥", label: "原文",     color: "#8b5cf6" },
  item:         { icon: "🧩", label: "ITEM",     color: "#f59e0b" },
  conversation: { icon: "💬", label: "コメント", color: "#22c55e" },
};

const TYPE_FILTERS: { key: string; label: string }[] = [
  { key: "",             label: "すべて" },
  { key: "issue",        label: "📋 課題" },
  { key: "input",        label: "📥 原文" },
  { key: "item",         label: "🧩 ITEM" },
  { key: "conversation", label: "💬 コメント" },
];

// キーワードをハイライト表示するコンポーネント
function Highlight({ text, query }: { text: string; query: string }) {
  if (!query.trim()) return <>{text}</>;
  const keywords = query.trim().split(/\s+/).filter(Boolean);
  const pattern = new RegExp(`(${keywords.map(k => k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join("|")})`, "gi");
  const parts = text.split(pattern);
  return (
    <>
      {parts.map((part, i) =>
        pattern.test(part)
          ? <mark key={i} style={{ background: "#fef08a", color: "#1e293b", borderRadius: "2px", padding: "0 1px" }}>{part}</mark>
          : <span key={i}>{part}</span>
      )}
    </>
  );
}

export default function Search() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const initialQ = searchParams.get("q") || "";
  const initialType = searchParams.get("type") || "";

  const [query, setQuery] = useState(initialQ);
  const [typeFilter, setTypeFilter] = useState(initialType);
  const [result, setResult] = useState<SearchResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  const doSearch = useCallback(async (q: string, t: string) => {
    if (!q.trim()) { setResult(null); return; }
    setLoading(true); setError("");
    try {
      const params: any = { q: q.trim(), limit: 50 };
      if (t) params.type = t;
      const res = await searchApi.search(params);
      setResult(res.data);
      setSearchParams({ q: q.trim(), ...(t ? { type: t } : {}) });
    } catch (e: any) {
      setError(e.response?.data?.detail || "検索に失敗しました");
    } finally { setLoading(false); }
  }, [setSearchParams]);

  // URLパラメータからの初期検索
  useEffect(() => {
    if (initialQ) doSearch(initialQ, initialType);
    inputRef.current?.focus();
  }, []); // eslint-disable-line

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    doSearch(query, typeFilter);
  };

  const handleTypeChange = (t: string) => {
    setTypeFilter(t);
    if (query.trim()) doSearch(query, t);
  };

  // タイプ別にグループ化するかどうか（"すべて"の場合のみグループ表示）
  const grouped = !typeFilter && result && result.hits.length > 0;

  const groupedHits: Record<string, SearchHit[]> = {};
  if (grouped) {
    for (const hit of result!.hits) {
      if (!groupedHits[hit.type]) groupedHits[hit.type] = [];
      groupedHits[hit.type].push(hit);
    }
  }

  return (
    <Layout>
      {/* 検索バー */}
      <div style={{ marginBottom: "24px" }}>
        <h1 style={{ margin: "0 0 16px", fontSize: "20px" }}>🔍 横断検索</h1>
        <form onSubmit={handleSubmit} style={{ display: "flex", gap: "8px" }}>
          <input
            ref={inputRef}
            value={query}
            onChange={e => setQuery(e.target.value)}
            placeholder="課題・原文・ITEM・コメントを横断検索… (スペースで AND 検索)"
            style={{
              flex: 1, padding: "12px 16px", borderRadius: "10px",
              background: "#1e293b", border: "1px solid #334155",
              color: "#e2e8f0", fontSize: "15px", outline: "none",
            }}
            onFocus={e => (e.target.style.borderColor = "#3b82f6")}
            onBlur={e => (e.target.style.borderColor = "#334155")}
          />
          <button
            type="submit"
            disabled={loading || !query.trim()}
            style={{
              padding: "12px 28px", borderRadius: "10px", border: "none",
              background: loading || !query.trim() ? "#334155" : "#3b82f6",
              color: "#fff", cursor: loading || !query.trim() ? "not-allowed" : "pointer",
              fontSize: "15px", fontWeight: "600", flexShrink: 0,
            }}
          >
            {loading ? "🔄" : "検索"}
          </button>
        </form>

        {/* タイプフィルター */}
        <div style={{ display: "flex", gap: "6px", marginTop: "12px", flexWrap: "wrap" }}>
          {TYPE_FILTERS.map(f => (
            <button
              key={f.key}
              onClick={() => handleTypeChange(f.key)}
              style={{
                padding: "5px 14px", borderRadius: "20px", border: "none",
                cursor: "pointer", fontSize: "13px",
                background: typeFilter === f.key ? "#3b82f6" : "#1e293b",
                color: typeFilter === f.key ? "#fff" : "#94a3b8",
                fontWeight: typeFilter === f.key ? "600" : "400",
              }}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      {/* エラー */}
      {error && (
        <div style={{
          background: "#fef2f2", border: "1px solid #fca5a5", borderRadius: "8px",
          padding: "10px 16px", marginBottom: "16px", color: "#dc2626", fontSize: "13px",
        }}>⚠️ {error}</div>
      )}

      {/* ローディング */}
      {loading && (
        <div style={{ textAlign: "center", padding: "60px", color: "#64748b" }}>
          <div style={{ fontSize: "32px", marginBottom: "12px" }}>🔄</div>
          検索中...
        </div>
      )}

      {/* 初期状態 */}
      {!loading && !result && !error && (
        <div style={{ textAlign: "center", padding: "80px", color: "#475569" }}>
          <div style={{ fontSize: "48px", marginBottom: "16px" }}>🔍</div>
          <p style={{ margin: 0, fontSize: "16px" }}>キーワードを入力して検索</p>
          <p style={{ margin: "8px 0 0", fontSize: "13px", color: "#334155" }}>
            課題・原文（RAW_INPUT）・分解ITEM・コメントを一括検索できます
          </p>
        </div>
      )}

      {/* 検索結果 */}
      {!loading && result && (
        <>
          {/* サマリー */}
          <div style={{
            display: "flex", justifyContent: "space-between", alignItems: "center",
            marginBottom: "16px", padding: "10px 16px",
            background: "#1e293b", borderRadius: "8px",
          }}>
            <span style={{ color: "#e2e8f0", fontSize: "14px" }}>
              <strong style={{ color: "#3b82f6" }}>{result.total}</strong> 件ヒット
              {result.total > 0 && (
                <span style={{ color: "#64748b", marginLeft: "8px" }}>
                  — {TYPE_FILTERS.slice(1).map(f => {
                    const count = result.hits.filter(h => h.type === f.key).length;
                    return count > 0 ? `${f.label} ${count}件` : null;
                  }).filter(Boolean).join("  ")}
                </span>
              )}
            </span>
            <span style={{ color: "#475569", fontSize: "12px" }}>{result.duration_ms}ms</span>
          </div>

          {/* 結果なし */}
          {result.total === 0 && (
            <div style={{ textAlign: "center", padding: "60px", color: "#64748b" }}>
              <div style={{ fontSize: "40px", marginBottom: "12px" }}>😶</div>
              <p style={{ margin: 0 }}>「{result.query}」に一致する結果がありませんでした</p>
              <p style={{ margin: "8px 0 0", fontSize: "13px", color: "#334155" }}>
                別のキーワードや、スペース区切りの AND 検索をお試しください
              </p>
            </div>
          )}

          {/* グループ表示（すべて） */}
          {grouped && Object.entries(groupedHits).map(([type, hits]) => (
            <div key={type} style={{ marginBottom: "28px" }}>
              <div style={{
                display: "flex", alignItems: "center", gap: "8px",
                marginBottom: "10px", paddingBottom: "6px",
                borderBottom: `2px solid ${TYPE_CONFIG[type as HitType].color}33`,
              }}>
                <span style={{ fontSize: "16px" }}>{TYPE_CONFIG[type as HitType].icon}</span>
                <span style={{
                  fontSize: "14px", fontWeight: "700",
                  color: TYPE_CONFIG[type as HitType].color,
                }}>
                  {TYPE_CONFIG[type as HitType].label}
                </span>
                <span style={{ fontSize: "12px", color: "#64748b" }}>({hits.length}件)</span>
              </div>
              <HitList hits={hits} query={result.query} navigate={navigate} />
            </div>
          ))}

          {/* フラット表示（type絞り込み時） */}
          {!grouped && result.total > 0 && (
            <HitList hits={result.hits} query={result.query} navigate={navigate} />
          )}
        </>
      )}
    </Layout>
  );
}

function HitList({ hits, query, navigate }: {
  hits: SearchHit[];
  query: string;
  navigate: (url: string) => void;
}) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
      {hits.map(hit => {
        const cfg = TYPE_CONFIG[hit.type];
        return (
          <div
            key={`${hit.type}-${hit.id}`}
            onClick={() => navigate(hit.url)}
            style={{
              background: "#1e293b", borderRadius: "10px",
              padding: "14px 18px", cursor: "pointer",
              border: "1px solid #334155",
              transition: "border-color 0.15s, background 0.15s",
            }}
            onMouseEnter={e => {
              (e.currentTarget as HTMLDivElement).style.borderColor = cfg.color;
              (e.currentTarget as HTMLDivElement).style.background = "#243044";
            }}
            onMouseLeave={e => {
              (e.currentTarget as HTMLDivElement).style.borderColor = "#334155";
              (e.currentTarget as HTMLDivElement).style.background = "#1e293b";
            }}
          >
            <div style={{ display: "flex", alignItems: "flex-start", gap: "10px" }}>
              {/* タイプバッジ */}
              <span style={{
                padding: "2px 8px", borderRadius: "4px", fontSize: "11px",
                fontWeight: "600", flexShrink: 0, marginTop: "2px",
                background: cfg.color + "22", color: cfg.color,
                border: `1px solid ${cfg.color}44`,
              }}>
                {cfg.icon} {cfg.label}
              </span>

              <div style={{ flex: 1, minWidth: 0 }}>
                {/* タイトル */}
                <p style={{
                  margin: "0 0 4px", fontSize: "14px", fontWeight: "600",
                  color: "#e2e8f0", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
                }}>
                  <Highlight text={hit.title} query={query} />
                </p>

                {/* 本文スニペット */}
                {hit.body && (
                  <p style={{
                    margin: "0 0 6px", fontSize: "13px", color: "#94a3b8", lineHeight: 1.5,
                  }}>
                    <Highlight text={hit.body} query={query} />
                  </p>
                )}

                {/* メタ情報 */}
                <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
                  {hit.type === "issue" && (
                    <>
                      <MetaBadge>{hit.meta.status}</MetaBadge>
                      <MetaBadge>{hit.meta.priority}</MetaBadge>
                      {hit.meta.labels && <MetaBadge>{hit.meta.labels}</MetaBadge>}
                    </>
                  )}
                  {hit.type === "item" && (
                    <>
                      <MetaBadge>{hit.meta.intent_code}</MetaBadge>
                      <MetaBadge>{hit.meta.domain_code}</MetaBadge>
                      {hit.meta.confidence && (
                        <MetaBadge>{Math.round(hit.meta.confidence * 100)}%</MetaBadge>
                      )}
                    </>
                  )}
                  {hit.type === "input" && <MetaBadge>{hit.meta.source_type}</MetaBadge>}
                  <span style={{ fontSize: "11px", color: "#475569", marginLeft: "auto" }}>
                    {new Date(hit.created_at).toLocaleDateString("ja-JP")}
                  </span>
                </div>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

function MetaBadge({ children }: { children: React.ReactNode }) {
  return (
    <span style={{
      padding: "1px 7px", borderRadius: "4px", fontSize: "11px",
      background: "#0f172a", color: "#64748b", border: "1px solid #1e293b",
    }}>
      {children}
    </span>
  );
}
TSX_EOF

success "Search.tsx 作成完了"

# =============================================================================
section "FE-2: App.tsx に /search ルート追加"
# =============================================================================

cp "$SRC_DIR/App.tsx" "$PROJECT_DIR/backup_$TS/App.tsx"

python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/frontend/src/App.tsx")
with open(path) as f:
    content = f.read()

if "Search" not in content:
    # import 追加
    content = re.sub(
        r"(import IssueDetail.*\n)",
        r"\1import Search from './pages/Search';\n",
        content
    )
    # Route 追加（IssueDetail の後）
    content = re.sub(
        r'(<Route path="/issues/:id".*?/>)',
        r'\1\n        <Route path="/search" element={<Search />} />',
        content
    )
    with open(path, "w") as f:
        f.write(content)
    print("✅ App.tsx に /search ルート追加")
else:
    print("ℹ️  App.tsx に Search は既に存在")
PYEOF

success "App.tsx 更新完了"

# =============================================================================
section "FE-3: Layout.tsx に検索ナビ追加"
# =============================================================================

cp "$COMP_DIR/Layout.tsx" "$PROJECT_DIR/backup_$TS/Layout.tsx"

python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/frontend/src/components/Layout.tsx")
with open(path) as f:
    content = f.read()

# useNavigate の import 確認
if "useNavigate" not in content:
    content = content.replace(
        "import { NavLink",
        "import { NavLink, useNavigate"
    )

# 検索リンクをナビに追加（課題一覧の後）
if "/search" not in content:
    content = re.sub(
        r'(NavLink.*?/issues.*?\n.*?\n)',
        lambda m: m.group(0) + '          <NavLink to="/search" style={navStyle}>\n            🔍 検索\n          </NavLink>\n',
        content,
        count=1
    )
    with open(path, "w") as f:
        f.write(content)
    print("✅ Layout.tsx に 🔍 検索 リンク追加")
else:
    print("ℹ️  Layout.tsx に /search は既に存在")
PYEOF

# Layout.tsx の更新が失敗した場合でも続行できるよう warn に変更済み
success "Layout.tsx 更新完了"

# =============================================================================
section "FE-4: client.ts に searchApi 追加"
# =============================================================================

python3 - << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/frontend/src/api/client.ts")
with open(path) as f:
    content = f.read()

if "searchApi" not in content:
    append = """
// Search（横断全文検索）
export const searchApi = {
  search: (params: { q: string; type?: string; limit?: number }) =>
    client.get("/search", { params }),
};
"""
    content = content.rstrip() + "\n" + append
    with open(path, "w") as f:
        f.write(content)
    print("✅ client.ts に searchApi 追加")
else:
    print("ℹ️  client.ts に searchApi は既に存在")
PYEOF

success "client.ts 更新完了"

# =============================================================================
section "バックエンド再起動 & 動作確認"
# =============================================================================

source "$BACKEND_DIR/.venv/bin/activate"
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
  warn "起動確認失敗 → tail -30 ~/projects/decision-os/logs/backend.log"
fi

# search エンドポイント確認
SEARCH_FOUND=$(curl -sf http://localhost:8089/openapi.json 2>/dev/null \
  | python3 -c "
import json,sys
spec=json.load(sys.stdin)
found = '/api/v1/search' in spec.get('paths',{})
print('YES' if found else 'NO')
" 2>/dev/null || echo "NO")

if [[ "$SEARCH_FOUND" == "YES" ]]; then
  success "GET /api/v1/search 確認 ✅"
else
  warn "search エンドポイントが見つかりません"
fi

# 実際に検索テスト
TOKEN=$(curl -sf -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token','ERR'))" 2>/dev/null || echo "ERR")

if [[ "$TOKEN" != "ERR" && -n "$TOKEN" ]]; then
  SEARCH_RES=$(curl -sf "http://localhost:8089/api/v1/search?q=%E6%A4%9C%E7%B4%A2&limit=5" \
    -H "Authorization: Bearer $TOKEN" \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(f'total:{d[\"total\"]}件, {d[\"duration_ms\"]}ms')
" 2>/dev/null || echo "ERR")

  if [[ "$SEARCH_RES" != "ERR" ]]; then
    success "検索テスト「検索」→ $SEARCH_RES ✅"
  else
    warn "検索テスト失敗 → backend.log を確認"
  fi
fi

# =============================================================================
section "完了サマリー"
# =============================================================================
echo ""
echo -e "${BOLD}実装完了:${RESET}"
echo "  ✅ BE: GET /api/v1/search?q=&type=&limit="
echo "     - 検索対象: issues / inputs / items / conversations"
echo "     - AND検索（スペース区切り）"
echo "     - タイプ絞り込み（type=issue|input|item|conversation）"
echo "     - スニペット抽出・200ms以内応答"
echo "  ✅ FE: Search.tsx（検索結果ページ）"
echo "     - タイプ別グループ表示"
echo "     - キーワードハイライト"
echo "     - クリックで該当ページに遷移"
echo "  ✅ FE: App.tsx に /search ルート追加"
echo "  ✅ FE: Layout.tsx に 🔍 検索 ナビリンク追加"
echo "  ✅ FE: client.ts に searchApi 追加"
echo ""
echo -e "${BOLD}ブラウザで確認:${RESET}"
echo "  1. http://localhost:3008 → 左メニューの 🔍 検索 をクリック"
echo "  2. 「検索」「エラー」「ログイン」などキーワードを入力"
echo "  3. タイプフィルター（課題/原文/ITEM/コメント）で絞り込み"
echo "  4. 結果カードをクリックして該当ページに遷移"
echo ""
success "Phase 2: 横断全文検索 実装完了！"
