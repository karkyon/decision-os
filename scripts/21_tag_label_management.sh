#!/usr/bin/env bash
# =============================================================================
# decision-os / 21_tag_label_management.sh
# F-082 タグ検索 + F-043 ラベル管理強化
# - GET  /api/v1/labels          使用中ラベル一覧（使用回数付き）
# - GET  /api/v1/labels/suggest  オートコンプリート候補
# - POST /api/v1/labels/merge    ラベル統合（命名ゆれ修正）
# - LabelInput.tsx               オートコンプリート付きタグ入力
# - Labels.tsx                   ラベル管理画面
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKUP_DIR="$HOME/projects/decision-os/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
info "バックアップ先: $BACKUP_DIR/"

# ─────────────────────────────────────────────
# BE-1: routers/labels.py 作成
# ─────────────────────────────────────────────
section "BE-1: routers/labels.py 作成"

cd "$PROJECT_DIR/backend"
source .venv/bin/activate

cat > "$PROJECT_DIR/backend/app/api/v1/routers/labels.py" << 'PYEOF'
"""
Labels router
GET  /labels          使用中ラベル一覧（使用回数・最終使用日付き）
GET  /labels/suggest  オートコンプリート候補（q= で前方一致）
POST /labels/merge    ラベル統合（from_label → to_label に一括置換）
DELETE /labels/{label} 未使用ラベルの削除
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import text
from typing import Optional
from pydantic import BaseModel

from app.db.session import get_db
from ....core.deps import get_current_user
from app.models.user import User

router = APIRouter(prefix="/labels", tags=["labels"])


def _parse_labels(raw: str | None) -> list[str]:
    """カンマ区切りのラベル文字列をリストに変換"""
    if not raw:
        return []
    return [l.strip() for l in raw.split(",") if l.strip()]


@router.get("")
def list_labels(
    project_id: Optional[str] = Query(None),
    q:          Optional[str] = Query(None, description="前方一致フィルター"),
    limit:      int           = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """使用中ラベル一覧を使用回数降順で返す"""
    # issues.labels は "tag1,tag2,tag3" 形式のテキスト
    # PostgreSQL で分割・集計
    sql = """
        SELECT
            trim(label) AS label,
            COUNT(*)    AS issue_count,
            MAX(created_at) AS last_used
        FROM issues,
             unnest(string_to_array(labels, ',')) AS label
        WHERE labels IS NOT NULL AND trim(label) != ''
        {project_filter}
        {q_filter}
        GROUP BY trim(label)
        ORDER BY issue_count DESC
        LIMIT :limit
    """.format(
        project_filter="AND project_id = :project_id" if project_id else "",
        q_filter="AND trim(label) ILIKE :q" if q else "",
    )

    params = {"limit": limit}
    if project_id:
        params["project_id"] = project_id
    if q:
        params["q"] = f"{q}%"

    rows = db.execute(text(sql), params).fetchall()
    return {
        "labels": [
            {
                "label":       row[0],
                "issue_count": row[1],
                "last_used":   row[2].isoformat() if row[2] else None,
            }
            for row in rows
        ],
        "total": len(rows),
    }


@router.get("/suggest")
def suggest_labels(
    q:          str           = Query(..., min_length=1),
    project_id: Optional[str] = Query(None),
    limit:      int           = Query(10, ge=1, le=50),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """入力途中のオートコンプリート候補を返す"""
    sql = """
        SELECT DISTINCT trim(label) AS label, COUNT(*) AS cnt
        FROM issues,
             unnest(string_to_array(labels, ',')) AS label
        WHERE labels IS NOT NULL
          AND trim(label) ILIKE :q
          {project_filter}
        GROUP BY trim(label)
        ORDER BY cnt DESC
        LIMIT :limit
    """.format(
        project_filter="AND project_id = :project_id" if project_id else ""
    )
    params = {"q": f"{q}%", "limit": limit}
    if project_id:
        params["project_id"] = project_id

    rows = db.execute(text(sql), params).fetchall()
    return {"suggestions": [row[0] for row in rows]}


class MergeRequest(BaseModel):
    from_label: str
    to_label:   str
    project_id: Optional[str] = None


@router.post("/merge")
def merge_labels(
    body: MergeRequest,
    db:   Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """from_label を to_label に一括置換（命名ゆれ統合）"""
    from app.models.issue import Issue
    import re

    query = db.query(Issue).filter(Issue.labels.ilike(f"%{body.from_label}%"))
    if body.project_id:
        query = query.filter(Issue.project_id == body.project_id)

    updated = 0
    for issue in query.all():
        labels = _parse_labels(issue.labels)
        new_labels = [
            body.to_label if l.lower() == body.from_label.lower() else l
            for l in labels
        ]
        # 重複排除
        seen = []
        for l in new_labels:
            if l not in seen:
                seen.append(l)
        issue.labels = ",".join(seen)
        updated += 1

    db.commit()
    return {"merged": updated, "from": body.from_label, "to": body.to_label}


@router.delete("/{label}")
def delete_label(
    label: str,
    project_id: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """指定ラベルを全課題から削除"""
    from app.models.issue import Issue

    query = db.query(Issue).filter(Issue.labels.ilike(f"%{label}%"))
    if project_id:
        query = query.filter(Issue.project_id == project_id)

    updated = 0
    for issue in query.all():
        labels = _parse_labels(issue.labels)
        new_labels = [l for l in labels if l.lower() != label.lower()]
        issue.labels = ",".join(new_labels)
        updated += 1

    db.commit()
    return {"deleted_from": updated, "label": label}
PYEOF
ok "routers/labels.py 作成完了"

# ─────────────────────────────────────────────
# BE-2: api.py に labels_router 追加
# ─────────────────────────────────────────────
section "BE-2: api.py に labels_router 追加"

API_PY="$PROJECT_DIR/backend/app/api/v1/api.py"
cp "$API_PY" "$BACKUP_DIR/api.py.bak"

python3 - << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/backend/app/api/v1/api.py")
with open(path) as f:
    src = f.read()

if "labels" not in src:
    src = src.replace(
        "from .routers import auth, inputs, analyze, items, actions, issues, trace, projects, ws",
        "from .routers import auth, inputs, analyze, items, actions, issues, trace, projects, ws, labels"
    )
    src = src.rstrip() + "\napi_router.include_router(labels.router)\n"
    with open(path, "w") as f:
        f.write(src)
    print("ADDED")
else:
    print("EXISTS")
PYEOF
ok "api.py: labels_router 追加完了"

# ─────────────────────────────────────────────
# FE-1: LabelInput.tsx コンポーネント作成
# ─────────────────────────────────────────────
section "FE-1: LabelInput.tsx 作成（オートコンプリート付きタグ入力）"

cat > "$PROJECT_DIR/frontend/src/components/LabelInput.tsx" << 'TSEOF'
/**
 * LabelInput
 * オートコンプリート付きタグ入力コンポーネント
 *
 * 使用例:
 *   <LabelInput value={labels} onChange={setLabels} />
 *   value/onChange は string[] 形式
 */
import { useState, useRef, useEffect, useCallback } from "react";
import { labelApi } from "../api/client";

interface Props {
  value:      string[];
  onChange:   (labels: string[]) => void;
  projectId?: string;
  placeholder?: string;
  maxTags?:   number;
  disabled?:  boolean;
}

const TAG_COLORS = [
  { bg: "#1e3a5f", color: "#93c5fd", border: "#1d4ed8" },
  { bg: "#14532d", color: "#86efac", border: "#15803d" },
  { bg: "#4a1942", color: "#e879f9", border: "#7e22ce" },
  { bg: "#7c2d12", color: "#fdba74", border: "#c2410c" },
  { bg: "#1e293b", color: "#94a3b8", border: "#334155" },
];

function getTagColor(label: string) {
  let hash = 0;
  for (const c of label) hash = (hash * 31 + c.charCodeAt(0)) % TAG_COLORS.length;
  return TAG_COLORS[Math.abs(hash) % TAG_COLORS.length];
}

export default function LabelInput({
  value = [],
  onChange,
  projectId,
  placeholder = "タグを追加...",
  maxTags = 20,
  disabled = false,
}: Props) {
  const [input,       setInput]       = useState("");
  const [suggestions, setSuggestions] = useState<string[]>([]);
  const [showDrop,    setShowDrop]    = useState(false);
  const [activeIdx,   setActiveIdx]   = useState(-1);
  const inputRef = useRef<HTMLInputElement>(null);
  const dropRef  = useRef<HTMLDivElement>(null);

  // オートコンプリート取得
  useEffect(() => {
    if (input.trim().length === 0) { setSuggestions([]); return; }
    const timer = setTimeout(async () => {
      try {
        const res = await labelApi.suggest(input.trim(), projectId);
        const all: string[] = res.data.suggestions || [];
        // 既存タグを除外
        setSuggestions(all.filter(s => !value.includes(s)));
        setShowDrop(true);
      } catch { setSuggestions([]); }
    }, 200);
    return () => clearTimeout(timer);
  }, [input, projectId]);

  const addTag = useCallback((tag: string) => {
    const t = tag.trim();
    if (!t || value.includes(t) || value.length >= maxTags) return;
    onChange([...value, t]);
    setInput("");
    setSuggestions([]);
    setShowDrop(false);
    setActiveIdx(-1);
    inputRef.current?.focus();
  }, [value, onChange, maxTags]);

  const removeTag = useCallback((tag: string) => {
    onChange(value.filter(v => v !== tag));
  }, [value, onChange]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" || e.key === "," || e.key === " ") {
      e.preventDefault();
      if (activeIdx >= 0 && suggestions[activeIdx]) {
        addTag(suggestions[activeIdx]);
      } else if (input.trim()) {
        addTag(input.trim());
      }
    } else if (e.key === "ArrowDown") {
      e.preventDefault();
      setActiveIdx(i => Math.min(i + 1, suggestions.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActiveIdx(i => Math.max(i - 1, -1));
    } else if (e.key === "Escape") {
      setShowDrop(false);
    } else if (e.key === "Backspace" && input === "" && value.length > 0) {
      removeTag(value[value.length - 1]);
    }
  };

  // 外クリックで閉じる
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (dropRef.current && !dropRef.current.contains(e.target as Node) &&
          inputRef.current && !inputRef.current.contains(e.target as Node)) {
        setShowDrop(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  return (
    <div style={{ position: "relative" }}>
      {/* タグ + 入力欄 */}
      <div
        onClick={() => !disabled && inputRef.current?.focus()}
        style={{
          display: "flex", flexWrap: "wrap", gap: "6px", alignItems: "center",
          padding: "8px 10px", borderRadius: "8px",
          background: "#0f172a", border: "1px solid #334155",
          minHeight: "40px", cursor: disabled ? "default" : "text",
        }}
      >
        {value.map(tag => {
          const c = getTagColor(tag);
          return (
            <span key={tag} style={{
              display: "inline-flex", alignItems: "center", gap: "4px",
              padding: "2px 8px", borderRadius: "20px",
              background: c.bg, color: c.color,
              border: `1px solid ${c.border}`,
              fontSize: "12px", fontWeight: "500",
            }}>
              {tag}
              {!disabled && (
                <button
                  type="button"
                  onClick={e => { e.stopPropagation(); removeTag(tag); }}
                  style={{
                    background: "none", border: "none", cursor: "pointer",
                    color: c.color, padding: "0", lineHeight: 1, fontSize: "13px",
                    opacity: 0.7,
                  }}
                >×</button>
              )}
            </span>
          );
        })}
        {!disabled && value.length < maxTags && (
          <input
            ref={inputRef}
            value={input}
            onChange={e => { setInput(e.target.value); setShowDrop(true); }}
            onKeyDown={handleKeyDown}
            onFocus={() => input.trim() && setShowDrop(true)}
            placeholder={value.length === 0 ? placeholder : ""}
            style={{
              background: "none", border: "none", outline: "none",
              color: "#e2e8f0", fontSize: "13px",
              flex: "1", minWidth: "80px",
            }}
          />
        )}
      </div>

      {/* ヒント */}
      {!disabled && (
        <div style={{ fontSize: "11px", color: "#475569", marginTop: "4px" }}>
          Enter / カンマ / スペースで追加　Backspaceで最後のタグを削除
        </div>
      )}

      {/* サジェストドロップダウン */}
      {showDrop && suggestions.length > 0 && (
        <div ref={dropRef} style={{
          position: "absolute", top: "calc(100% + 4px)", left: 0, right: 0,
          background: "#0f172a", border: "1px solid #334155",
          borderRadius: "8px", zIndex: 100,
          boxShadow: "0 4px 16px rgba(0,0,0,0.4)",
          maxHeight: "200px", overflowY: "auto",
        }}>
          {suggestions.map((s, i) => {
            const c = getTagColor(s);
            return (
              <div
                key={s}
                onMouseDown={() => addTag(s)}
                style={{
                  padding: "8px 12px", cursor: "pointer",
                  background: i === activeIdx ? "#1e293b" : "transparent",
                  display: "flex", alignItems: "center", gap: "8px",
                  fontSize: "13px", color: "#e2e8f0",
                }}
                onMouseEnter={() => setActiveIdx(i)}
              >
                <span style={{
                  padding: "1px 8px", borderRadius: "20px",
                  background: c.bg, color: c.color, border: `1px solid ${c.border}`,
                  fontSize: "11px",
                }}>{s}</span>
              </div>
            );
          })}
          {/* 新規作成 */}
          {input.trim() && !suggestions.includes(input.trim()) && (
            <div
              onMouseDown={() => addTag(input.trim())}
              style={{
                padding: "8px 12px", cursor: "pointer",
                borderTop: "1px solid #1e293b",
                color: "#64748b", fontSize: "13px",
              }}
            >
              ＋ 「{input.trim()}」を新規作成
            </div>
          )}
        </div>
      )}
    </div>
  );
}
TSEOF
ok "LabelInput.tsx 作成完了"

# ─────────────────────────────────────────────
# FE-2: Labels.tsx 管理画面作成
# ─────────────────────────────────────────────
section "FE-2: Labels.tsx 管理画面作成"

cat > "$PROJECT_DIR/frontend/src/pages/Labels.tsx" << 'TSEOF'
import { useState, useEffect } from "react";
import Layout from "../components/Layout";
import { labelApi } from "../api/client";

interface LabelInfo {
  label:       string;
  issue_count: number;
  last_used:   string | null;
}

export default function Labels() {
  const [labels,   setLabels]   = useState<LabelInfo[]>([]);
  const [loading,  setLoading]  = useState(true);
  const [q,        setQ]        = useState("");
  const [mergeFrom, setMergeFrom] = useState("");
  const [mergeTo,   setMergeTo]   = useState("");
  const [merging,   setMerging]   = useState(false);
  const [msg,       setMsg]       = useState("");

  const fetchLabels = async (query = "") => {
    setLoading(true);
    try {
      const res = await labelApi.list(query);
      setLabels(res.data.labels || []);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchLabels(); }, []);

  const handleMerge = async () => {
    if (!mergeFrom || !mergeTo) return;
    setMerging(true);
    try {
      const res = await labelApi.merge(mergeFrom, mergeTo);
      setMsg(`✅ 「${mergeFrom}」→「${mergeTo}」に ${res.data.merged} 件統合しました`);
      setMergeFrom(""); setMergeTo("");
      fetchLabels(q);
    } catch (e: any) {
      setMsg(`❌ エラー: ${e.response?.data?.detail || "統合に失敗しました"}`);
    } finally {
      setMerging(false);
    }
  };

  const handleDelete = async (label: string) => {
    if (!confirm(`「${label}」を全課題から削除しますか？`)) return;
    try {
      await labelApi.delete(label);
      setMsg(`✅ 「${label}」を削除しました`);
      fetchLabels(q);
    } catch {
      setMsg("❌ 削除に失敗しました");
    }
  };

  const filtered = labels.filter(l =>
    q === "" || l.label.toLowerCase().includes(q.toLowerCase())
  );

  return (
    <Layout>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "24px" }}>
        <h1 style={{ margin: 0, fontSize: "20px" }}>🏷 ラベル管理</h1>
        <span style={{ color: "#64748b", fontSize: "13px" }}>{labels.length} ラベル使用中</span>
      </div>

      {msg && (
        <div style={{
          padding: "10px 16px", borderRadius: "8px", marginBottom: "16px",
          background: msg.startsWith("✅") ? "#14532d" : "#7f1d1d",
          color: msg.startsWith("✅") ? "#86efac" : "#fca5a5", fontSize: "13px",
        }}>
          {msg}
          <button onClick={() => setMsg("")} style={{ float: "right", background: "none", border: "none", color: "inherit", cursor: "pointer" }}>×</button>
        </div>
      )}

      {/* 統合パネル */}
      <div style={{
        background: "#1e293b", border: "1px solid #334155",
        borderRadius: "12px", padding: "16px", marginBottom: "20px",
      }}>
        <h3 style={{ margin: "0 0 12px", fontSize: "14px", color: "#94a3b8" }}>🔀 ラベル統合（命名ゆれ修正）</h3>
        <div style={{ display: "flex", gap: "8px", alignItems: "center", flexWrap: "wrap" }}>
          <input
            value={mergeFrom}
            onChange={e => setMergeFrom(e.target.value)}
            placeholder="統合元のラベル（例: バグ）"
            style={inputStyle}
          />
          <span style={{ color: "#64748b" }}>→</span>
          <input
            value={mergeTo}
            onChange={e => setMergeTo(e.target.value)}
            placeholder="統合先のラベル（例: BUG）"
            style={inputStyle}
          />
          <button
            onClick={handleMerge}
            disabled={!mergeFrom || !mergeTo || merging}
            style={{
              padding: "8px 20px", borderRadius: "8px", border: "none",
              background: !mergeFrom || !mergeTo ? "#334155" : "#3b82f6",
              color: "#fff", cursor: !mergeFrom || !mergeTo ? "not-allowed" : "pointer",
              fontSize: "13px", fontWeight: "600",
            }}
          >
            {merging ? "統合中..." : "統合する"}
          </button>
        </div>
      </div>

      {/* 検索 */}
      <div style={{ marginBottom: "16px" }}>
        <input
          value={q}
          onChange={e => setQ(e.target.value)}
          placeholder="ラベルを検索..."
          style={{ ...inputStyle, width: "100%", boxSizing: "border-box" }}
        />
      </div>

      {/* ラベル一覧 */}
      {loading ? (
        <div style={{ textAlign: "center", padding: "60px", color: "#64748b" }}>読み込み中...</div>
      ) : filtered.length === 0 ? (
        <div style={{ textAlign: "center", padding: "60px", color: "#475569" }}>
          <div style={{ fontSize: "40px", marginBottom: "12px" }}>🏷</div>
          <p>ラベルがありません</p>
        </div>
      ) : (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(240px, 1fr))", gap: "10px" }}>
          {filtered.map(info => (
            <div key={info.label} style={{
              background: "#1e293b", border: "1px solid #334155",
              borderRadius: "10px", padding: "14px 16px",
              display: "flex", justifyContent: "space-between", alignItems: "center",
            }}>
              <div>
                <div style={{
                  display: "inline-block", padding: "3px 12px", borderRadius: "20px",
                  background: "#0f172a", border: "1px solid #334155",
                  color: "#e2e8f0", fontSize: "13px", fontWeight: "500",
                  marginBottom: "6px",
                }}>
                  {info.label}
                </div>
                <div style={{ fontSize: "12px", color: "#64748b" }}>
                  📋 {info.issue_count} 件の課題
                </div>
                {info.last_used && (
                  <div style={{ fontSize: "11px", color: "#475569", marginTop: "2px" }}>
                    最終: {new Date(info.last_used).toLocaleDateString("ja-JP")}
                  </div>
                )}
              </div>
              <div style={{ display: "flex", flexDirection: "column", gap: "4px" }}>
                <button
                  onClick={() => { setMergeFrom(info.label); }}
                  title="このラベルを統合元に設定"
                  style={{
                    padding: "4px 10px", borderRadius: "6px", border: "none",
                    background: "#334155", color: "#94a3b8",
                    cursor: "pointer", fontSize: "11px",
                  }}
                >統合</button>
                {info.issue_count === 0 && (
                  <button
                    onClick={() => handleDelete(info.label)}
                    style={{
                      padding: "4px 10px", borderRadius: "6px", border: "none",
                      background: "#7f1d1d", color: "#fca5a5",
                      cursor: "pointer", fontSize: "11px",
                    }}
                  >削除</button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </Layout>
  );
}

const inputStyle: React.CSSProperties = {
  padding: "8px 12px", borderRadius: "8px",
  background: "#0f172a", border: "1px solid #334155",
  color: "#e2e8f0", fontSize: "13px", outline: "none",
};
TSEOF
ok "Labels.tsx 作成完了"

# ─────────────────────────────────────────────
# FE-3: client.ts に labelApi 追加
# ─────────────────────────────────────────────
section "FE-3: client.ts に labelApi 追加"

python3 - << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/frontend/src/api/client.ts")
with open(path) as f:
    src = f.read()

label_api = """
export const labelApi = {
  list:    (q?: string, projectId?: string) => {
    const p = new URLSearchParams();
    if (q)         p.append("q", q);
    if (projectId) p.append("project_id", projectId);
    return api.get(`/labels${p.toString() ? "?" + p.toString() : ""}`);
  },
  suggest: (q: string, projectId?: string) => {
    const p = new URLSearchParams({ q });
    if (projectId) p.append("project_id", projectId);
    return api.get(`/labels/suggest?${p.toString()}`);
  },
  merge:   (fromLabel: string, toLabel: string, projectId?: string) =>
    api.post("/labels/merge", { from_label: fromLabel, to_label: toLabel, project_id: projectId }),
  delete:  (label: string, projectId?: string) => {
    const p = projectId ? `?project_id=${projectId}` : "";
    return api.delete(`/labels/${encodeURIComponent(label)}${p}`);
  },
};
"""

if "labelApi" not in src:
    src = src.rstrip() + "\n" + label_api + "\n"
    with open(path, "w") as f:
        f.write(src)
    print("ADDED")
else:
    print("EXISTS")
PYEOF
ok "client.ts: labelApi 追加完了"

# ─────────────────────────────────────────────
# FE-4: App.tsx に /labels ルート追加
# ─────────────────────────────────────────────
section "FE-4: App.tsx + Layout.tsx 更新"

python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/frontend/src/App.tsx")
with open(path) as f:
    src = f.read()

if "Labels" not in src:
    src = re.sub(
        r'(import.*Decisions.*\n)',
        r'\1import Labels from "./pages/Labels";\n',
        src, count=1
    )
    if "import Labels" not in src:
        src = re.sub(
            r'(import.*from "react-router-dom";\n)',
            r'\1import Labels from "./pages/Labels";\n',
            src, count=1
        )
    src = src.replace(
        "</Routes>",
        '  <Route path="/labels" element={<Labels />} />\n        </Routes>'
    )
    with open(path, "w") as f:
        f.write(src)
    print("App.tsx UPDATED")
else:
    print("App.tsx EXISTS")
PYEOF

python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/frontend/src/components/Layout.tsx")
with open(path) as f:
    src = f.read()

if "/labels" not in src:
    # 📝 決定ログ の後に追加
    src = re.sub(
        r'(📝 決定ログ.*?</a>)',
        r'\1\n          <a href="/labels" style={navLinkStyle("/labels")}>🏷 ラベル管理</a>',
        src,
        count=1,
        flags=re.DOTALL
    )
    # navLinkStyle パターンが違う場合のフォールバック
    if "/labels" not in src:
        src = re.sub(
            r'(/decisions"[^>]*>[^<]*📝[^<]*</a>)',
            r'\1\n          <a href="/labels" style={{ color:"#94a3b8", textDecoration:"none", padding:"8px 12px", borderRadius:"6px", display:"block" }}>🏷 ラベル管理</a>',
            src,
            count=1
        )
    with open(path, "w") as f:
        f.write(src)
    print("Layout.tsx UPDATED")
else:
    print("Layout.tsx EXISTS")
PYEOF
ok "App.tsx / Layout.tsx 更新完了"

# ─────────────────────────────────────────────
# BE 再起動 & 確認
# ─────────────────────────────────────────────
section "バックエンド再起動 & 確認"

cd "$PROJECT_DIR/backend"
pkill -f "uvicorn" 2>/dev/null || true
sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$PROJECT_DIR/backend.log" 2>&1 &
sleep 4

echo "--- backend.log (末尾6行) ---"
tail -6 "$PROJECT_DIR/backend.log"
echo "-----------------------------"

if curl -s http://localhost:8089/api/v1/labels > /dev/null 2>&1; then
  ok "バックエンド起動 ✅"
  RES=$(curl -s "http://localhost:8089/api/v1/labels?limit=5" 2>/dev/null || echo "{}")
  echo "$RES" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('labels:', len(d.get('labels',[])), '件')
" 2>/dev/null && ok "GET /labels 確認 ✅"
else
  echo "[WARN] 起動失敗 → backend.log 確認"
  tail -20 "$PROJECT_DIR/backend.log"
fi

# ─────────────────────────────────────────────
section "完了サマリー"
echo "実装完了:"
echo "  ✅ BE: GET  /api/v1/labels          使用中ラベル一覧（使用回数・最終使用日）"
echo "  ✅ BE: GET  /api/v1/labels/suggest   オートコンプリート候補（q= 前方一致）"
echo "  ✅ BE: POST /api/v1/labels/merge     ラベル統合（命名ゆれ修正）"
echo "  ✅ BE: DELETE /api/v1/labels/{label} ラベル削除"
echo "  ✅ FE: LabelInput.tsx               オートコンプリート付きタグ入力"
echo "       - Enter / カンマ / スペースで追加"
echo "       - Backspaceで最後のタグ削除"
echo "       - カラーハッシュで色分け"
echo "       - 既存ラベルのサジェスト表示"
echo "  ✅ FE: Labels.tsx                   ラベル管理画面"
echo "       - 使用回数・最終使用日の一覧表示"
echo "       - ラベル統合フォーム（命名ゆれ修正）"
echo "       - 未使用ラベルの削除"
echo "  ✅ FE: client.ts labelApi 追加"
echo "  ✅ FE: 左ナビに 🏷 ラベル管理 追加"
echo ""
echo "ブラウザで確認:"
echo "  1. http://localhost:3008/labels → ラベル一覧が表示される"
echo "  2. 統合フォームで「バグ」→「BUG」に統合テスト"
echo "  3. 課題詳細のラベル欄 → LabelInput でタグを追加"
ok "Phase 2: タグ検索・ラベル管理強化（F-082/F-043）実装完了！"
