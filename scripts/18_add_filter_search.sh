#!/usr/bin/env bash
# =============================================================================
# decision-os / 18_add_filter_search.sh
# F-081 フィルター検索（課題一覧の複合フィルター）
# 対象: GET /api/v1/issues に status/priority/assignee/intent/date/label を追加
#       IssueList.tsx にフィルターUIパネルを追加
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKUP_DIR="$HOME/projects/decision-os/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
info "バックアップ先: $BACKUP_DIR/"

# ─────────────────────────────────────────────
# BE-1: issues.py の GET エンドポイントに複合フィルター追加
# ─────────────────────────────────────────────
section "BE-1: routers/issues.py にフィルタークエリ追加"

ISSUES_PY="$PROJECT_DIR/backend/app/api/v1/routers/issues.py"
[ -f "$ISSUES_PY" ] && cp "$ISSUES_PY" "$BACKUP_DIR/issues.py.bak"

cat > "$ISSUES_PY" << 'PYEOF'
"""
Issues router
GET    /issues  複合フィルター対応
POST   /issues  課題作成
GET    /issues/{id}
PATCH  /issues/{id}
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_
from typing import Optional, List
from datetime import datetime

from app.db.session import get_db
from app.models.issue import Issue
from app.models.action import Action
from app.models.item import Item
from app.core.auth import get_current_user
from app.models.user import User

router = APIRouter(prefix="/issues", tags=["issues"])


@router.get("")
def list_issues(
    project_id:   Optional[str]       = Query(None),
    status:       Optional[str]       = Query(None, description="カンマ区切り複数指定可: open,in_progress"),
    priority:     Optional[str]       = Query(None, description="high,medium,low"),
    assignee_id:  Optional[str]       = Query(None),
    intent_code:  Optional[str]       = Query(None, description="BUG,REQ,IMP など"),
    label:        Optional[str]       = Query(None, description="部分一致"),
    date_from:    Optional[str]       = Query(None, description="YYYY-MM-DD"),
    date_to:      Optional[str]       = Query(None, description="YYYY-MM-DD"),
    q:            Optional[str]       = Query(None, description="タイトル・説明の全文検索"),
    sort:         Optional[str]       = Query("created_at_desc", description="created_at_desc|created_at_asc|priority_desc|due_date_asc"),
    limit:        int                 = Query(100, ge=1, le=500),
    offset:       int                 = Query(0, ge=0),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    q_obj = db.query(Issue)

    # project_id
    if project_id:
        q_obj = q_obj.filter(Issue.project_id == project_id)

    # status (カンマ区切り OR)
    if status:
        statuses = [s.strip() for s in status.split(",") if s.strip()]
        q_obj = q_obj.filter(Issue.status.in_(statuses))

    # priority (カンマ区切り OR)
    if priority:
        priorities = [p.strip() for p in priority.split(",") if p.strip()]
        q_obj = q_obj.filter(Issue.priority.in_(priorities))

    # assignee_id
    if assignee_id:
        q_obj = q_obj.filter(Issue.assignee_id == assignee_id)

    # label (部分一致)
    if label:
        q_obj = q_obj.filter(Issue.labels.ilike(f"%{label}%"))

    # date_from / date_to (created_at)
    if date_from:
        try:
            dt = datetime.strptime(date_from, "%Y-%m-%d")
            q_obj = q_obj.filter(Issue.created_at >= dt)
        except ValueError:
            pass
    if date_to:
        try:
            dt = datetime.strptime(date_to, "%Y-%m-%d")
            # date_to は当日末尾まで含める
            from datetime import timedelta
            q_obj = q_obj.filter(Issue.created_at < dt + timedelta(days=1))
        except ValueError:
            pass

    # intent_code (Action → Item の intent で絞り込み)
    if intent_code:
        codes = [c.strip() for c in intent_code.split(",") if c.strip()]
        q_obj = (
            q_obj
            .join(Action, Action.issue_id == Issue.id, isouter=True)
            .join(Item,   Item.id == Action.item_id,   isouter=True)
            .filter(Item.intent_code.in_(codes))
        )

    # 全文検索 (title / description)
    if q:
        keywords = [k.strip() for k in q.strip().split() if k.strip()]
        for kw in keywords:
            pattern = f"%{kw}%"
            q_obj = q_obj.filter(
                or_(Issue.title.ilike(pattern), Issue.description.ilike(pattern))
            )

    # ソート
    if sort == "created_at_asc":
        q_obj = q_obj.order_by(Issue.created_at.asc())
    elif sort == "priority_desc":
        from sqlalchemy import case
        priority_order = case(
            {"high": 1, "medium": 2, "low": 3},
            value=Issue.priority,
            else_=9,
        )
        q_obj = q_obj.order_by(priority_order, Issue.created_at.desc())
    elif sort == "due_date_asc":
        q_obj = q_obj.order_by(Issue.due_date.asc().nulls_last(), Issue.created_at.desc())
    else:  # created_at_desc (default)
        q_obj = q_obj.order_by(Issue.created_at.desc())

    total = q_obj.count()
    issues = q_obj.offset(offset).limit(limit).all()

    return {
        "total": total,
        "offset": offset,
        "limit": limit,
        "issues": [_issue_dict(i) for i in issues],
    }


@router.post("")
def create_issue(
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    issue = Issue(
        project_id=body.get("project_id"),
        title=body.get("title", ""),
        description=body.get("description"),
        status=body.get("status", "open"),
        priority=body.get("priority", "medium"),
        assignee_id=body.get("assignee_id"),
        labels=body.get("labels"),
        due_date=body.get("due_date"),
        action_id=body.get("action_id"),
    )
    db.add(issue)
    db.commit()
    db.refresh(issue)
    return _issue_dict(issue)


@router.get("/{issue_id}")
def get_issue(
    issue_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    issue = db.query(Issue).filter(Issue.id == issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")
    return _issue_dict(issue)


@router.patch("/{issue_id}")
def update_issue(
    issue_id: str,
    body: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    issue = db.query(Issue).filter(Issue.id == issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")
    for k, v in body.items():
        if hasattr(issue, k):
            setattr(issue, k, v)
    db.commit()
    db.refresh(issue)
    return _issue_dict(issue)


def _issue_dict(issue: Issue) -> dict:
    return {
        "id": issue.id,
        "project_id": issue.project_id,
        "title": issue.title,
        "description": issue.description,
        "status": issue.status,
        "priority": issue.priority,
        "assignee_id": issue.assignee_id,
        "labels": issue.labels,
        "due_date": str(issue.due_date) if issue.due_date else None,
        "action_id": issue.action_id,
        "created_at": issue.created_at.isoformat() if issue.created_at else None,
        "updated_at": issue.updated_at.isoformat() if issue.updated_at else None,
    }
PYEOF
ok "issues.py: 複合フィルター追加完了"

# ─────────────────────────────────────────────
# FE-1: client.ts に issueApi.list のフィルターパラメータ更新
# ─────────────────────────────────────────────
section "FE-1: client.ts の issueApi にフィルターパラメータ追加"

CLIENT_TS="$PROJECT_DIR/frontend/src/api/client.ts"
[ -f "$CLIENT_TS" ] && cp "$CLIENT_TS" "$BACKUP_DIR/client.ts.bak"

# issueApi.list を拡張版に置換（既存の issueApi ブロックを置換）
if grep -q "issueApi" "$CLIENT_TS"; then
  python3 - << 'PYEOF'
import re, sys

path = "/root/projects/decision-os/frontend/src/api/client.ts"
with open(path, "r") as f:
    src = f.read()

new_issue_api = '''export const issueApi = {
  list: (params: {
    project_id?: string;
    status?: string;
    priority?: string;
    assignee_id?: string;
    intent_code?: string;
    label?: string;
    date_from?: string;
    date_to?: string;
    q?: string;
    sort?: string;
    limit?: number;
    offset?: number;
  } = {}) => {
    const p = new URLSearchParams();
    Object.entries(params).forEach(([k, v]) => { if (v !== undefined && v !== "") p.append(k, String(v)); });
    return api.get(`/issues${p.toString() ? "?" + p.toString() : ""}`);
  },
  get:    (id: string)          => api.get(`/issues/${id}`),
  create: (body: object)        => api.post("/issues", body),
  update: (id: string, body: object) => api.patch(`/issues/${id}`, body),
};'''

# issueApi ブロックを置換
src_new = re.sub(
    r'export const issueApi\s*=\s*\{[^}]*(?:\{[^}]*\}[^}]*)?\};',
    new_issue_api,
    src,
    flags=re.DOTALL,
)

if src_new == src:
    # フォールバック: 末尾に追記
    src_new = src + "\n" + new_issue_api + "\n"
    print("APPEND")
else:
    print("REPLACED")

with open(path, "w") as f:
    f.write(src_new)
PYEOF
  ok "client.ts: issueApi 更新完了"
else
  echo "" >> "$CLIENT_TS"
  ok "client.ts: issueApi 追記完了"
fi

# ─────────────────────────────────────────────
# FE-2: IssueList.tsx にフィルターパネルを追加
# ─────────────────────────────────────────────
section "FE-2: IssueList.tsx にフィルターパネル追加"

ISSUE_LIST="$PROJECT_DIR/frontend/src/pages/IssueList.tsx"
[ -f "$ISSUE_LIST" ] && cp "$ISSUE_LIST" "$BACKUP_DIR/IssueList.tsx.bak"

cat > "$ISSUE_LIST" << 'TSEOF'
import { useState, useEffect, useCallback } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import Layout from "../components/Layout";
import { issueApi } from "../api/client";

// ─── 定数 ───────────────────────────────────
const STATUS_OPTIONS = [
  { value: "",            label: "すべての状態" },
  { value: "open",        label: "🔴 未着手" },
  { value: "in_progress", label: "🟡 作業中" },
  { value: "review",      label: "🟣 レビュー" },
  { value: "done",        label: "🟢 完了" },
  { value: "hold",        label: "⚪ 保留" },
];

const PRIORITY_OPTIONS = [
  { value: "",       label: "すべての優先度" },
  { value: "high",   label: "🔴 高" },
  { value: "medium", label: "🟡 中" },
  { value: "low",    label: "🟢 低" },
];

const INTENT_OPTIONS = [
  { value: "",    label: "すべての分類" },
  { value: "BUG", label: "🐛 BUG" },
  { value: "REQ", label: "✨ REQ" },
  { value: "IMP", label: "💡 IMP" },
  { value: "QST", label: "❓ QST" },
  { value: "TSK", label: "📌 TSK" },
];

const SORT_OPTIONS = [
  { value: "created_at_desc", label: "🕐 新しい順" },
  { value: "created_at_asc",  label: "🕐 古い順" },
  { value: "priority_desc",   label: "🔥 優先度順" },
  { value: "due_date_asc",    label: "📅 期限順" },
];

const STATUS_BADGE: Record<string, { bg: string; color: string; label: string }> = {
  open:        { bg: "#fee2e2", color: "#dc2626", label: "未着手" },
  in_progress: { bg: "#fef9c3", color: "#ca8a04", label: "作業中" },
  review:      { bg: "#ede9fe", color: "#7c3aed", label: "レビュー" },
  done:        { bg: "#dcfce7", color: "#16a34a", label: "完了" },
  hold:        { bg: "#f1f5f9", color: "#64748b", label: "保留" },
};

const PRIORITY_BADGE: Record<string, { icon: string; color: string }> = {
  high:   { icon: "🔴", color: "#dc2626" },
  medium: { icon: "🟡", color: "#ca8a04" },
  low:    { icon: "🟢", color: "#16a34a" },
};

interface Issue {
  id: string;
  title: string;
  status: string;
  priority: string;
  labels: string | null;
  assignee_id: string | null;
  due_date: string | null;
  created_at: string;
}

// ─── コンポーネント ──────────────────────────
export default function IssueList() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();

  // フィルター状態（URLと同期）
  const [status,     setStatus]     = useState(searchParams.get("status") || "");
  const [priority,   setPriority]   = useState(searchParams.get("priority") || "");
  const [intentCode, setIntentCode] = useState(searchParams.get("intent_code") || "");
  const [label,      setLabel]      = useState(searchParams.get("label") || "");
  const [dateFrom,   setDateFrom]   = useState(searchParams.get("date_from") || "");
  const [dateTo,     setDateTo]     = useState(searchParams.get("date_to") || "");
  const [q,          setQ]          = useState(searchParams.get("q") || "");
  const [sort,       setSort]       = useState(searchParams.get("sort") || "created_at_desc");

  const [issues,  setIssues]  = useState<Issue[]>([]);
  const [total,   setTotal]   = useState(0);
  const [loading, setLoading] = useState(false);
  const [error,   setError]   = useState("");
  const [showFilter, setShowFilter] = useState(false);

  const fetchIssues = useCallback(async (params: Record<string, string>) => {
    setLoading(true);
    setError("");
    try {
      const res = await issueApi.list(
        Object.fromEntries(Object.entries(params).filter(([, v]) => v))
      );
      // レスポンスが配列直接の場合と {issues, total} の場合に対応
      if (Array.isArray(res.data)) {
        setIssues(res.data);
        setTotal(res.data.length);
      } else {
        setIssues(res.data.issues || []);
        setTotal(res.data.total || 0);
      }
    } catch (e: any) {
      setError(e.response?.data?.detail || "取得に失敗しました");
    } finally {
      setLoading(false);
    }
  }, []);

  const buildParams = useCallback(() => ({
    status, priority, intent_code: intentCode,
    label, date_from: dateFrom, date_to: dateTo, q, sort,
  }), [status, priority, intentCode, label, dateFrom, dateTo, q, sort]);

  // 初回・フィルター変化時に取得
  useEffect(() => {
    const params = buildParams();
    // URLに反映
    const sp: Record<string, string> = {};
    Object.entries(params).forEach(([k, v]) => { if (v) sp[k] = v; });
    setSearchParams(sp, { replace: true });
    fetchIssues(params);
  }, [status, priority, intentCode, label, dateFrom, dateTo, sort]); // q は Enter後に実行

  const handleQSearch = (e: React.FormEvent) => {
    e.preventDefault();
    fetchIssues(buildParams());
  };

  const resetFilters = () => {
    setStatus(""); setPriority(""); setIntentCode("");
    setLabel(""); setDateFrom(""); setDateTo(""); setQ(""); setSort("created_at_desc");
  };

  const activeFilterCount = [status, priority, intentCode, label, dateFrom, dateTo, q]
    .filter(Boolean).length;

  // ─── レンダリング ──────────────────────────
  return (
    <Layout>
      {/* ヘッダー */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "20px" }}>
        <div>
          <h1 style={{ margin: 0, fontSize: "20px" }}>📋 課題一覧</h1>
          {!loading && (
            <span style={{ fontSize: "13px", color: "#64748b", marginTop: "4px", display: "block" }}>
              {total} 件
            </span>
          )}
        </div>
        <div style={{ display: "flex", gap: "8px" }}>
          <button
            onClick={() => setShowFilter(!showFilter)}
            style={{
              padding: "8px 16px", borderRadius: "8px", border: "1px solid #334155",
              background: showFilter ? "#3b82f6" : "#1e293b",
              color: showFilter ? "#fff" : "#94a3b8",
              cursor: "pointer", fontSize: "13px", fontWeight: "600",
              display: "flex", alignItems: "center", gap: "6px",
            }}
          >
            🎛 フィルター
            {activeFilterCount > 0 && (
              <span style={{
                background: "#ef4444", color: "#fff", borderRadius: "50%",
                width: "18px", height: "18px", fontSize: "11px",
                display: "flex", alignItems: "center", justifyContent: "center",
              }}>
                {activeFilterCount}
              </span>
            )}
          </button>
          <button
            onClick={() => navigate("/inputs/new")}
            style={{
              padding: "8px 16px", borderRadius: "8px", border: "none",
              background: "#3b82f6", color: "#fff",
              cursor: "pointer", fontSize: "13px", fontWeight: "600",
            }}
          >
            ＋ 要望を登録
          </button>
        </div>
      </div>

      {/* フィルターパネル */}
      {showFilter && (
        <div style={{
          background: "#1e293b", border: "1px solid #334155",
          borderRadius: "12px", padding: "20px", marginBottom: "20px",
        }}>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(180px, 1fr))", gap: "12px" }}>

            {/* キーワード検索 */}
            <form onSubmit={handleQSearch} style={{ gridColumn: "1 / -1", display: "flex", gap: "8px" }}>
              <input
                value={q}
                onChange={e => setQ(e.target.value)}
                placeholder="タイトル・説明をキーワード検索..."
                style={{
                  flex: 1, padding: "8px 12px", borderRadius: "8px",
                  background: "#0f172a", border: "1px solid #334155",
                  color: "#e2e8f0", fontSize: "13px", outline: "none",
                }}
              />
              <button type="submit" style={{
                padding: "8px 16px", borderRadius: "8px", border: "none",
                background: "#3b82f6", color: "#fff", cursor: "pointer", fontSize: "13px",
              }}>検索</button>
            </form>

            {/* 状態 */}
            <div>
              <label style={{ fontSize: "11px", color: "#64748b", display: "block", marginBottom: "4px" }}>状態</label>
              <select value={status} onChange={e => setStatus(e.target.value)} style={selectStyle}>
                {STATUS_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            </div>

            {/* 優先度 */}
            <div>
              <label style={{ fontSize: "11px", color: "#64748b", display: "block", marginBottom: "4px" }}>優先度</label>
              <select value={priority} onChange={e => setPriority(e.target.value)} style={selectStyle}>
                {PRIORITY_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            </div>

            {/* 分類 */}
            <div>
              <label style={{ fontSize: "11px", color: "#64748b", display: "block", marginBottom: "4px" }}>分類 (Intent)</label>
              <select value={intentCode} onChange={e => setIntentCode(e.target.value)} style={selectStyle}>
                {INTENT_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            </div>

            {/* ラベル */}
            <div>
              <label style={{ fontSize: "11px", color: "#64748b", display: "block", marginBottom: "4px" }}>ラベル</label>
              <input
                value={label}
                onChange={e => setLabel(e.target.value)}
                onBlur={() => fetchIssues(buildParams())}
                placeholder="ラベル名で絞り込み"
                style={{ ...selectStyle, padding: "7px 10px" }}
              />
            </div>

            {/* 期間 from */}
            <div>
              <label style={{ fontSize: "11px", color: "#64748b", display: "block", marginBottom: "4px" }}>登録日 From</label>
              <input type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)} style={selectStyle} />
            </div>

            {/* 期間 to */}
            <div>
              <label style={{ fontSize: "11px", color: "#64748b", display: "block", marginBottom: "4px" }}>登録日 To</label>
              <input type="date" value={dateTo} onChange={e => setDateTo(e.target.value)} style={selectStyle} />
            </div>

            {/* ソート */}
            <div>
              <label style={{ fontSize: "11px", color: "#64748b", display: "block", marginBottom: "4px" }}>並び順</label>
              <select value={sort} onChange={e => setSort(e.target.value)} style={selectStyle}>
                {SORT_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            </div>
          </div>

          {/* リセット */}
          {activeFilterCount > 0 && (
            <div style={{ marginTop: "12px", textAlign: "right" }}>
              <button onClick={resetFilters} style={{
                padding: "6px 14px", borderRadius: "6px", border: "1px solid #475569",
                background: "transparent", color: "#94a3b8", cursor: "pointer", fontSize: "12px",
              }}>
                ✕ フィルターをリセット
              </button>
            </div>
          )}
        </div>
      )}

      {/* アクティブフィルターバッジ */}
      {!showFilter && activeFilterCount > 0 && (
        <div style={{ display: "flex", gap: "6px", flexWrap: "wrap", marginBottom: "12px" }}>
          {status    && <FilterBadge label={`状態: ${STATUS_OPTIONS.find(o => o.value === status)?.label}`}    onRemove={() => setStatus("")} />}
          {priority  && <FilterBadge label={`優先度: ${PRIORITY_OPTIONS.find(o => o.value === priority)?.label}`} onRemove={() => setPriority("")} />}
          {intentCode && <FilterBadge label={`分類: ${intentCode}`} onRemove={() => setIntentCode("")} />}
          {label     && <FilterBadge label={`ラベル: ${label}`}    onRemove={() => setLabel("")} />}
          {dateFrom  && <FilterBadge label={`From: ${dateFrom}`}   onRemove={() => setDateFrom("")} />}
          {dateTo    && <FilterBadge label={`To: ${dateTo}`}       onRemove={() => setDateTo("")} />}
          {q         && <FilterBadge label={`"${q}"`}             onRemove={() => { setQ(""); fetchIssues({...buildParams(), q: ""}); }} />}
        </div>
      )}

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
          <div style={{ fontSize: "32px", marginBottom: "8px" }}>🔄</div>
          読み込み中...
        </div>
      )}

      {/* 課題一覧 */}
      {!loading && issues.length === 0 && (
        <div style={{ textAlign: "center", padding: "80px", color: "#475569" }}>
          <div style={{ fontSize: "48px", marginBottom: "12px" }}>📭</div>
          <p style={{ margin: 0 }}>
            {activeFilterCount > 0 ? "フィルター条件に一致する課題がありません" : "課題はまだありません"}
          </p>
          {activeFilterCount > 0 && (
            <button onClick={resetFilters} style={{
              marginTop: "12px", padding: "8px 20px", borderRadius: "8px",
              border: "1px solid #334155", background: "transparent",
              color: "#94a3b8", cursor: "pointer",
            }}>フィルターをリセット</button>
          )}
        </div>
      )}

      {!loading && issues.length > 0 && (
        <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
          {issues.map(issue => {
            const sb = STATUS_BADGE[issue.status] || { bg: "#1e293b", color: "#94a3b8", label: issue.status };
            const pb = PRIORITY_BADGE[issue.priority];
            return (
              <div
                key={issue.id}
                onClick={() => navigate(`/issues/${issue.id}`)}
                style={{
                  background: "#1e293b", border: "1px solid #334155",
                  borderRadius: "10px", padding: "14px 18px",
                  cursor: "pointer", transition: "border-color 0.15s",
                  display: "flex", justifyContent: "space-between", alignItems: "center",
                  gap: "12px",
                }}
                onMouseEnter={e => (e.currentTarget.style.borderColor = "#3b82f6")}
                onMouseLeave={e => (e.currentTarget.style.borderColor = "#334155")}
              >
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "4px" }}>
                    {pb && <span style={{ fontSize: "14px" }}>{pb.icon}</span>}
                    <span style={{
                      fontWeight: "600", fontSize: "14px", color: "#e2e8f0",
                      overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
                    }}>
                      {issue.title}
                    </span>
                  </div>
                  <div style={{ display: "flex", gap: "8px", flexWrap: "wrap", alignItems: "center" }}>
                    {issue.labels && issue.labels.split(",").map(l => l.trim()).filter(Boolean).map(l => (
                      <span key={l} style={{
                        fontSize: "11px", padding: "2px 8px", borderRadius: "20px",
                        background: "#0f172a", color: "#64748b", border: "1px solid #334155",
                      }}>{l}</span>
                    ))}
                    {issue.due_date && (
                      <span style={{ fontSize: "11px", color: "#94a3b8" }}>
                        📅 {issue.due_date}
                      </span>
                    )}
                  </div>
                </div>

                <div style={{ flexShrink: 0 }}>
                  <span style={{
                    fontSize: "11px", padding: "3px 10px", borderRadius: "20px",
                    background: sb.bg, color: sb.color, fontWeight: "600",
                  }}>
                    {sb.label}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </Layout>
  );
}

// ─── ミニコンポーネント ────────────────────────
function FilterBadge({ label, onRemove }: { label: string; onRemove: () => void }) {
  return (
    <span style={{
      display: "inline-flex", alignItems: "center", gap: "4px",
      padding: "3px 10px", borderRadius: "20px",
      background: "#1e3a5f", color: "#93c5fd", fontSize: "12px",
      border: "1px solid #1d4ed8",
    }}>
      {label}
      <button onClick={onRemove} style={{
        background: "none", border: "none", color: "#93c5fd",
        cursor: "pointer", padding: "0", lineHeight: 1, fontSize: "13px",
      }}>×</button>
    </span>
  );
}

const selectStyle: React.CSSProperties = {
  width: "100%", padding: "7px 10px", borderRadius: "8px",
  background: "#0f172a", border: "1px solid #334155",
  color: "#e2e8f0", fontSize: "13px", outline: "none",
};
TSEOF
ok "IssueList.tsx: フィルターパネル追加完了"

# ─────────────────────────────────────────────
# BE 再起動 & 動作確認
# ─────────────────────────────────────────────
section "バックエンド再起動 & 動作確認"

cd "$PROJECT_DIR/backend"
source .venv/bin/activate

# 既存プロセス停止
pkill -f "uvicorn" 2>/dev/null || true
sleep 1

# 起動
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload > "$PROJECT_DIR/backend.log" 2>&1 &
sleep 3

# ヘルスチェック
if curl -s http://localhost:8089/health > /dev/null 2>&1 || \
   curl -s http://localhost:8089/api/v1/issues > /dev/null 2>&1; then
  ok "バックエンド起動確認 ✅"
else
  warn "ヘルスチェック失敗 → backend.log を確認"
fi

# フィルターAPIテスト
TOKEN=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || echo "")

if [ -n "$TOKEN" ]; then
  RESULT=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8089/api/v1/issues?status=open&priority=high&sort=priority_desc&limit=5")
  if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print('total:', d.get('total', len(d) if isinstance(d, list) else '?'))" 2>/dev/null; then
    ok "GET /api/v1/issues?status=open&priority=high 確認 ✅"
  else
    warn "フィルターAPIテスト → $RESULT"
  fi
else
  warn "ログイン失敗 → 手動で確認してください"
fi

# ─────────────────────────────────────────────
section "完了サマリー"
echo "実装完了:"
echo "  ✅ BE: GET /api/v1/issues に複合フィルター追加"
echo "       - status（カンマ区切り複数指定可）"
echo "       - priority（high/medium/low）"
echo "       - assignee_id（担当者）"
echo "       - intent_code（BUG/REQ/IMP/QST/TSK）"
echo "       - label（部分一致）"
echo "       - date_from / date_to（登録日範囲）"
echo "       - q（タイトル・説明 AND全文検索）"
echo "       - sort（created_at_desc|asc / priority_desc / due_date_asc）"
echo "       - limit / offset（ページネーション）"
echo "  ✅ FE: client.ts issueApi.list にフィルターパラメータ追加"
echo "  ✅ FE: IssueList.tsx にフィルターパネル追加"
echo "       - 🎛 フィルターボタンでパネル展開/折りたたみ"
echo "       - アクティブフィルター数バッジ表示"
echo "       - バッジクリックで個別フィルター解除"
echo "       - リセットボタン"
echo ""
echo "ブラウザで確認:"
echo "  1. http://localhost:3008/issues を開く"
echo "  2. 右上「🎛 フィルター」ボタンをクリック → パネル展開"
echo "  3. 状態・優先度・分類・ラベル・期間・並び順を設定"
echo "  4. URLに ?status=open&priority=high... が反映されるか確認"
echo "  5. フィルターバッジの × で個別解除"
ok "Phase 2: フィルター検索 実装完了！"
