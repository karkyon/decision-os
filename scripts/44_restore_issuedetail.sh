#!/usr/bin/env bash
# =============================================================================
# decision-os / 44_restore_issuedetail.sh
# IssueDetail.tsx をバックアップから復元 → useAuthStore だけ除去 → ビルド確認
# =============================================================================
set -uo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

FRONTEND_DIR="$HOME/projects/decision-os/frontend"
SRC="$FRONTEND_DIR/src"
FILE="$SRC/pages/IssueDetail.tsx"
BACKUP_DIR="$HOME/projects/decision-os"

cd "$FRONTEND_DIR"
eval "$(~/.nvm/nvm.sh 2>/dev/null || true)"
nvm use --lts 2>/dev/null || true

# =============================================================================
section "1. バックアップから IssueDetail.tsx を復元"
# =============================================================================
# 最新バックアップを探す
LATEST_BACKUP=$(ls -dt "$BACKUP_DIR"/backup_ts_* 2>/dev/null | head -1)
info "最新バックアップ: $LATEST_BACKUP"

BACKUP_FILE="$LATEST_BACKUP/IssueDetail.tsx"
if [[ -f "$BACKUP_FILE" ]]; then
  LINE_COUNT=$(wc -l < "$BACKUP_FILE")
  info "バックアップ行数: $LINE_COUNT 行"
  if [[ "$LINE_COUNT" -gt 80 ]]; then
    cp "$BACKUP_FILE" "$FILE"
    success "バックアップから復元完了 ($LINE_COUNT 行)"
  else
    info "バックアップも短すぎる ($LINE_COUNT 行) → 全バックアップを確認"
    for d in $(ls -dt "$BACKUP_DIR"/backup_ts_* 2>/dev/null); do
      f="$d/IssueDetail.tsx"
      if [[ -f "$f" ]]; then
        lc=$(wc -l < "$f")
        info "  $d : $lc 行"
        if [[ "$lc" -gt 80 ]]; then
          cp "$f" "$FILE"
          success "復元: $d ($lc 行)"
          break
        fi
      fi
    done
  fi
else
  info "バックアップなし → 新規で完全版を作成"
fi

# 復元後の行数確認
CURRENT_LINES=$(wc -l < "$FILE" 2>/dev/null || echo 0)
info "現在の IssueDetail.tsx: $CURRENT_LINES 行"

# 行数が少ない場合は完全版で上書き
if [[ "$CURRENT_LINES" -lt 80 ]]; then
  info "ファイルが不完全 → 完全版で上書き"
  cat > "$FILE" << 'ISSUEDETAIL_EOF'
import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { issueApi, traceApi, conversationApi } from '../api/client'

interface Issue {
  id: string
  title: string
  description?: string
  status: string
  priority: string
  assignee_id?: string
  labels?: string[]
  created_at: string
  updated_at?: string
  project_id: string
}

interface TraceData {
  issue?: { id: string; title: string }
  action?: { id: string; action_type: string; decision_reason?: string }
  item?: { id: string; text: string; intent_code: string; domain_code: string }
  input?: { id: string; raw_text: string; source_type: string; created_at: string }
}

interface Comment {
  id: string
  body: string
  author_name?: string
  created_at: string
}

const STATUS_OPTIONS = ['open', 'in_progress', 'review', 'done', 'hold']
const PRIORITY_OPTIONS = ['low', 'medium', 'high', 'critical']
const PRIORITY_COLORS: Record<string, string> = {
  low: '#22c55e', medium: '#f59e0b', high: '#ef4444', critical: '#7c3aed',
}

export default function IssueDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [issue, setIssue] = useState<Issue | null>(null)
  const [trace, setTrace] = useState<TraceData | null>(null)
  const [comments, setComments] = useState<Comment[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [activeTab, setActiveTab] = useState<'detail' | 'trace' | 'comments'>('detail')
  const [saving, setSaving] = useState(false)
  const [editStatus, setEditStatus] = useState('')
  const [editPriority, setEditPriority] = useState('')
  const [newComment, setNewComment] = useState('')
  const [posting, setPosting] = useState(false)

  useEffect(() => {
    if (!id) return
    Promise.all([
      issueApi.get(id),
      traceApi.get(id).catch(() => ({ data: null })),
      conversationApi.list(id).catch(() => ({ data: [] })),
    ]).then(([issueRes, traceRes, commentsRes]) => {
      setIssue(issueRes.data)
      setEditStatus(issueRes.data.status)
      setEditPriority(issueRes.data.priority)
      if (traceRes.data) setTrace(traceRes.data)
      setComments(commentsRes.data || [])
    }).catch(e => {
      setError(e?.response?.data?.detail || '課題の取得に失敗しました')
    }).finally(() => setLoading(false))
  }, [id])

  const handleSave = async () => {
    if (!issue) return
    setSaving(true)
    try {
      const res = await issueApi.update(issue.id, { status: editStatus, priority: editPriority })
      setIssue(res.data)
    } catch { alert('保存に失敗しました') }
    finally { setSaving(false) }
  }

  const handlePostComment = async () => {
    if (!issue || !newComment.trim()) return
    setPosting(true)
    try {
      const res = await conversationApi.create({ issue_id: issue.id, body: newComment })
      setComments(prev => [...prev, res.data])
      setNewComment('')
    } catch { alert('コメント投稿に失敗しました') }
    finally { setPosting(false) }
  }

  if (loading) return <div style={{ padding: 32, color: '#94a3b8' }}>読み込み中...</div>
  if (error)   return <div style={{ padding: 32, color: '#f87171' }}>{error}</div>
  if (!issue)  return <div style={{ padding: 32, color: '#94a3b8' }}>課題が見つかりません</div>

  const card: React.CSSProperties = {
    background: '#1e293b', borderRadius: 8, padding: '16px 20px', marginBottom: 12
  }
  const labelStyle: React.CSSProperties = {
    fontSize: 11, color: '#64748b', textTransform: 'uppercase', marginBottom: 4
  }
  const val: React.CSSProperties = { color: '#e2e8f0', fontSize: 14 }
  const selectStyle: React.CSSProperties = {
    background: '#0f172a', color: '#e2e8f0', border: '1px solid #334155',
    borderRadius: 4, padding: '4px 8px', fontSize: 13
  }

  return (
    <div style={{ padding: 24, maxWidth: 900, margin: '0 auto' }}>
      {/* ヘッダ */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 20 }}>
        <button
          onClick={() => navigate(-1)}
          style={{ background: 'none', border: 'none', color: '#60a5fa', cursor: 'pointer', fontSize: 13 }}
        >← 戻る</button>
        <span style={{
          background: PRIORITY_COLORS[issue.priority] + '22',
          color: PRIORITY_COLORS[issue.priority],
          borderRadius: 4, padding: '2px 8px', fontSize: 12
        }}>{issue.priority}</span>
        <h1 style={{ color: '#f1f5f9', fontSize: 20, fontWeight: 700, margin: 0 }}>
          #{issue.id.slice(0, 8)} {issue.title}
        </h1>
      </div>

      {/* タブ */}
      <div style={{ display: 'flex', gap: 4, marginBottom: 20, borderBottom: '1px solid #1e293b' }}>
        {(['detail', 'trace', 'comments'] as const).map(tab => (
          <button key={tab} onClick={() => setActiveTab(tab)} style={{
            padding: '8px 16px', border: 'none', cursor: 'pointer', fontSize: 13,
            borderBottom: activeTab === tab ? '2px solid #60a5fa' : '2px solid transparent',
            background: 'none', color: activeTab === tab ? '#60a5fa' : '#94a3b8'
          }}>
            {tab === 'detail' ? '詳細' : tab === 'trace' ? '🔍 トレース' : `💬 コメント(${comments.length})`}
          </button>
        ))}
      </div>

      {/* 詳細タブ */}
      {activeTab === 'detail' && (
        <div>
          <div style={{ ...card, display: 'flex', gap: 24, flexWrap: 'wrap' }}>
            <div>
              <div style={labelStyle}>ステータス</div>
              <select value={editStatus} onChange={e => setEditStatus(e.target.value)} style={selectStyle}>
                {STATUS_OPTIONS.map(s => <option key={s} value={s}>{s}</option>)}
              </select>
            </div>
            <div>
              <div style={labelStyle}>優先度</div>
              <select value={editPriority} onChange={e => setEditPriority(e.target.value)} style={selectStyle}>
                {PRIORITY_OPTIONS.map(p => <option key={p} value={p}>{p}</option>)}
              </select>
            </div>
            <div style={{ marginLeft: 'auto', alignSelf: 'flex-end' }}>
              <button onClick={handleSave} disabled={saving} style={{
                background: '#2563eb', color: '#fff', border: 'none',
                borderRadius: 6, padding: '6px 16px', cursor: 'pointer', fontSize: 13
              }}>{saving ? '保存中...' : '保存'}</button>
            </div>
          </div>
          <div style={card}>
            <div style={labelStyle}>説明</div>
            <div style={{ ...val, whiteSpace: 'pre-wrap' }}>{issue.description || '（説明なし）'}</div>
          </div>
          {issue.labels && issue.labels.length > 0 && (
            <div style={card}>
              <div style={labelStyle}>ラベル</div>
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                {issue.labels.map(l => (
                  <span key={l} style={{ background: '#334155', color: '#94a3b8', borderRadius: 4, padding: '2px 8px', fontSize: 12 }}>{l}</span>
                ))}
              </div>
            </div>
          )}
          <div style={card}>
            <div style={labelStyle}>作成日時</div>
            <div style={val}>{new Date(issue.created_at).toLocaleString('ja-JP')}</div>
          </div>
        </div>
      )}

      {/* トレーサビリティタブ */}
      {activeTab === 'trace' && (
        <div>
          {trace ? (
            <>
              <div style={{ ...card, borderLeft: '3px solid #60a5fa' }}>
                <div style={labelStyle}>📋 ISSUE（この課題）</div>
                <div style={val}>#{issue.id.slice(0, 8)} {issue.title}</div>
              </div>
              {trace.action && (
                <div style={{ ...card, borderLeft: '3px solid #a78bfa', marginLeft: 24 }}>
                  <div style={labelStyle}>⚡ ACTION（課題化の判断）</div>
                  <div style={val}>種別: {trace.action.action_type}</div>
                  {trace.action.decision_reason && (
                    <div style={{ color: '#94a3b8', fontSize: 12, marginTop: 4 }}>
                      理由: {trace.action.decision_reason}
                    </div>
                  )}
                </div>
              )}
              {trace.item && (
                <div style={{ ...card, borderLeft: '3px solid #34d399', marginLeft: 48 }}>
                  <div style={labelStyle}>🔹 ITEM（分解された意味単位）</div>
                  <div style={val}>"{trace.item.text}"</div>
                  <div style={{ color: '#94a3b8', fontSize: 12, marginTop: 4 }}>
                    intent: {trace.item.intent_code} / domain: {trace.item.domain_code}
                  </div>
                </div>
              )}
              {trace.input && (
                <div style={{ ...card, borderLeft: '3px solid #fbbf24', marginLeft: 72 }}>
                  <div style={labelStyle}>📥 INPUT（元の要望原文）</div>
                  <div style={{ color: '#e2e8f0', fontSize: 12, whiteSpace: 'pre-wrap', maxHeight: 120, overflow: 'auto' }}>
                    {trace.input.raw_text}
                  </div>
                  <div style={{ color: '#64748b', fontSize: 11, marginTop: 6 }}>
                    ソース: {trace.input.source_type} ／ {trace.input.created_at?.slice(0, 16)}
                  </div>
                </div>
              )}
            </>
          ) : (
            <div style={{ ...card, color: '#64748b' }}>
              トレース情報がありません（このIssueはACTIONから生成されていないか、データが未接続です）
            </div>
          )}
        </div>
      )}

      {/* コメントタブ */}
      {activeTab === 'comments' && (
        <div>
          {comments.map(c => (
            <div key={c.id} style={card}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6 }}>
                <span style={{ color: '#60a5fa', fontSize: 13 }}>{c.author_name || '匿名'}</span>
                <span style={{ color: '#64748b', fontSize: 11 }}>{new Date(c.created_at).toLocaleString('ja-JP')}</span>
              </div>
              <div style={val}>{c.body}</div>
            </div>
          ))}
          <div style={card}>
            <textarea
              value={newComment}
              onChange={e => setNewComment(e.target.value)}
              placeholder="コメントを入力..."
              style={{
                width: '100%', minHeight: 80, background: '#0f172a', color: '#e2e8f0',
                border: '1px solid #334155', borderRadius: 4, padding: 8, fontSize: 13,
                resize: 'vertical', boxSizing: 'border-box'
              }}
            />
            <button
              onClick={handlePostComment}
              disabled={posting || !newComment.trim()}
              style={{
                marginTop: 8, background: '#2563eb', color: '#fff', border: 'none',
                borderRadius: 6, padding: '6px 16px', cursor: 'pointer', fontSize: 13
              }}
            >{posting ? '投稿中...' : '投稿'}</button>
          </div>
        </div>
      )}
    </div>
  )
}
ISSUEDETAIL_EOF
  success "IssueDetail.tsx 完全版で上書き完了"
fi

# React import 追加確認（CSSProperties用）
if ! grep -q "^import React" "$FILE"; then
  sed -i "1s/^/import React from 'react'\n/" "$FILE"
  success "React import 追加"
fi

# =============================================================================
section "2. ビルド最終確認"
# =============================================================================
info "npm run build 実行中..."
BUILD_OUT=$(npm run build 2>&1 || true)
TS_ERRORS=$(echo "$BUILD_OUT" | grep "error TS" || true)

if [[ -z "$TS_ERRORS" ]]; then
  success "🎉🎉🎉 TSビルドエラー 0件！ビルド完全成功！"
  echo "$BUILD_OUT" | grep -E "built|chunks|✓|vite|dist" | tail -6
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  次のステップ: テストカバレッジ80%"
  echo "  bash ~/projects/decision-os/scripts/34_final_80.sh"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  echo "$TS_ERRORS"
  info "残存エラーの詳細:"
  # エラーファイルを確認
  ERROR_FILES=$(echo "$TS_ERRORS" | grep -oP 'src/[^(]+' | sort -u)
  while IFS= read -r ef; do
    [[ -z "$ef" ]] && continue
    FULL_PATH="$FRONTEND_DIR/$ef"
    echo ""
    echo "=== $ef (全内容) ==="
    cat "$FULL_PATH" 2>/dev/null | head -30
  done <<< "$ERROR_FILES"
fi
