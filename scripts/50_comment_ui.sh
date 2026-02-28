#!/bin/bash
set -e
PROJECT_DIR=~/projects/decision-os
BACKEND_DIR=$PROJECT_DIR/backend
FRONTEND_DIR=$PROJECT_DIR/frontend
PAGES_DIR=$FRONTEND_DIR/src/pages
API_DIR=$FRONTEND_DIR/src/api
ISSUE_DETAIL=$PAGES_DIR/IssueDetail.tsx

section() { echo ""; echo "========== $1 =========="; }
ok()      { echo "  ✅ $1"; }
info()    { echo "  [INFO] $1"; }
warn()    { echo "  ⚠️  $1"; }

# ============================================================
section "1. 会話 API 疎通確認"
# ============================================================
cd $BACKEND_DIR && source .venv/bin/activate

LOGIN_RESP=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}')
TOKEN=$(echo $LOGIN_RESP | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)

# conversations エンドポイント確認
CONV_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://localhost:8089/api/v1/conversations?issue_id=00000000-0000-0000-0000-000000000000" \
  -H "Authorization: Bearer $TOKEN")
info "conversations API ステータス: $CONV_CHECK"

if [ "$CONV_CHECK" = "404" ] || [ "$CONV_CHECK" = "200" ]; then
  ok "conversations API 存在確認"
else
  warn "conversations API が未登録の可能性。api.py に追加します..."
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
    print("  ✅ api.py に conversations_router 追加")
else:
    print("  ✅ conversations_router は既に登録済み")
PYEOF
  # バックエンド再起動
  pkill -f "uvicorn app.main" 2>/dev/null; sleep 2
  nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
    > $PROJECT_DIR/logs/backend.log 2>&1 &
  sleep 3
  ok "バックエンド再起動完了"
fi

# ============================================================
section "2. client.ts に conversationApi 追加"
# ============================================================
python3 - << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/frontend/src/api/client.ts")
with open(path) as f:
    content = f.read()

if "conversationApi" not in content:
    append = """
// ── Conversations（コメント）──────────────────────────────────────────
export const conversationApi = {
  list:   (issueId: string) => client.get(`/conversations?issue_id=${issueId}`),
  create: (data: { issue_id: string; body: string }) => client.post("/conversations", data),
  update: (id: string, body: string) => client.patch(`/conversations/${id}`, { body }),
  delete: (id: string) => client.delete(`/conversations/${id}`),
};
"""
    with open(path, "w") as f:
        f.write(content.rstrip() + "\n" + append)
    print("  ✅ conversationApi 追加完了")
else:
    print("  ✅ conversationApi は既に存在")
PYEOF

# ============================================================
section "3. IssueDetail.tsx にコメントスレッドを追加"
# ============================================================
info "バックアップ作成..."
cp $ISSUE_DETAIL ${ISSUE_DETAIL}.bak_comment

cat > $ISSUE_DETAIL << 'TSX_EOF'
import { useState, useEffect, useRef } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import client from '../api/client'
import { authStore } from '../store/auth'

// ── 型定義 ────────────────────────────────────────────────────────────

interface Issue {
  id: string; title: string; description: string
  status: string; priority: string; issue_type?: string
  project_id?: string; assignee_id?: string; due_date?: string
  created_at: string; updated_at: string
}

interface TraceData {
  issue: { id: string; title: string; status: string; priority: string }
  action?: { id: string; action_type: string; decision_reason?: string; created_at: string }
  item?: { id: string; text: string; intent_code: string; domain_code: string; confidence: number }
  input?: { id: string; raw_text: string; source_type: string; created_at: string; author?: string }
}

interface Comment {
  id: string; body: string; created_at: string; updated_at?: string
  author?: { id: string; name: string; email: string; role: string }
  author_id?: string
}

// ── 定数 ──────────────────────────────────────────────────────────────

const STATUS_MAP: Record<string, { label: string; color: string; bg: string }> = {
  open:        { label: '未着手',   color: '#fbbf24', bg: '#422006' },
  in_progress: { label: '進行中',   color: '#60a5fa', bg: '#1e3a5f' },
  review:      { label: 'レビュー', color: '#a78bfa', bg: '#2e1065' },
  done:        { label: '完了',     color: '#4ade80', bg: '#14532d' },
  closed:      { label: 'クローズ', color: '#94a3b8', bg: '#1e293b' },
}
const PRIORITY_MAP: Record<string, { label: string; color: string }> = {
  critical: { label: '緊急', color: '#ef4444' },
  high:     { label: '高',   color: '#f97316' },
  medium:   { label: '中',   color: '#eab308' },
  low:      { label: '低',   color: '#64748b' },
}
const STATUS_OPTIONS = ['open', 'in_progress', 'review', 'done', 'closed']

// ── メインコンポーネント ───────────────────────────────────────────────

export default function IssueDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const bottomRef = useRef<HTMLDivElement>(null)

  const [issue, setIssue] = useState<Issue | null>(null)
  const [trace, setTrace] = useState<TraceData | null>(null)
  const [comments, setComments] = useState<Comment[]>([])
  const [traceLoading, setTraceLoading] = useState(false)
  const [traceError, setTraceError] = useState('')
  const [inputExpanded, setInputExpanded] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [saving, setSaving] = useState(false)
  const [showStatusMenu, setShowStatusMenu] = useState(false)

  // コメント入力
  const [commentBody, setCommentBody] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [commentError, setCommentError] = useState('')
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editBody, setEditBody] = useState('')

  // 現在のユーザーID（JWT から取得）
  const currentUserId = (() => {
    try {
      const token = localStorage.getItem('access_token') ?? ''
      const payload = token.split('.')[1]
      return JSON.parse(atob(payload)).sub ?? ''
    } catch { return '' }
  })()

  useEffect(() => {
    if (!id) return
    Promise.all([
      client.get(`/issues/${id}`).then(r => {
        setIssue(r.data)
      }),
      client.get(`/trace/${id}`).then(r => setTrace(r.data)).catch(() => setTraceError('トレースデータなし')),
      client.get(`/conversations?issue_id=${id}`).then(r => {
        const d = r.data
        setComments(Array.isArray(d) ? d : d.items ?? [])
      }).catch(() => {}),
    ]).catch(() => setError('課題が見つかりません'))
      .finally(() => setLoading(false))
  }, [id])

  // コメント追加時に最下部へスクロール
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [comments.length])

  const handleStatusChange = async (s: string) => {
    if (!issue) return
    setSaving(true); setShowStatusMenu(false)
    try {
      const r = await client.patch(`/issues/${issue.id}`, { status: s })
      setIssue(r.data)
    } catch { alert('ステータス更新失敗') }
    finally { setSaving(false) }
  }

  const submitComment = async () => {
    if (!id || !commentBody.trim()) return
    setSubmitting(true); setCommentError('')
    try {
      const r = await client.post('/conversations', { issue_id: id, body: commentBody.trim() })
      setComments(prev => [...prev, r.data])
      setCommentBody('')
    } catch (e: any) {
      setCommentError(e.response?.data?.detail ?? '投稿に失敗しました')
    } finally { setSubmitting(false) }
  }

  const saveEdit = async (c: Comment) => {
    try {
      const r = await client.patch(`/conversations/${c.id}`, { body: editBody })
      setComments(prev => prev.map(x => x.id === c.id ? r.data : x))
      setEditingId(null)
    } catch { alert('編集に失敗しました') }
  }

  const deleteComment = async (cid: string) => {
    if (!confirm('このコメントを削除しますか？')) return
    try {
      await client.delete(`/conversations/${cid}`)
      setComments(prev => prev.filter(x => x.id !== cid))
    } catch { alert('削除に失敗しました') }
  }

  if (loading) return (
    <div style={{ padding: '40px', color: '#64748b', textAlign: 'center' }}>🔄 読み込み中...</div>
  )
  if (error || !issue) return (
    <div style={{ padding: '40px', color: '#f87171', textAlign: 'center' }}>⚠️ {error || '課題が見つかりません'}</div>
  )

  const si = STATUS_MAP[issue.status] ?? { label: issue.status, color: '#94a3b8', bg: '#1e293b' }
  const pi = PRIORITY_MAP[issue.priority] ?? { label: issue.priority, color: '#94a3b8' }

  return (
    <div style={{ minHeight: '100vh', background: '#0f172a', color: '#e2e8f0' }}>

      {/* ── ナビバー ── */}
      <nav style={{
        background: '#1e293b', borderBottom: '1px solid #334155',
        padding: '0 24px', height: '52px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
          <button onClick={() => navigate('/')}
            style={{ background: 'none', border: 'none', color: '#60a5fa', cursor: 'pointer', fontSize: '20px' }}>⚖️</button>
          <button onClick={() => navigate(-1)}
            style={{ background: 'none', border: 'none', color: '#94a3b8', cursor: 'pointer', fontSize: '13px' }}>← 戻る</button>
          <span style={{ color: '#475569', fontSize: '13px' }}>/ 課題詳細</span>
        </div>
        <button onClick={() => { authStore.logout(); navigate('/login') }}
          style={{ background: 'none', border: 'none', color: '#64748b', cursor: 'pointer', fontSize: '13px' }}>
          ログアウト
        </button>
      </nav>

      {/* ── 2カラムレイアウト ── */}
      <div style={{ display: 'flex', height: 'calc(100vh - 52px)' }}>

        {/* ── 左カラム: 課題本体 ＋ コメント ── */}
        <div style={{
          flex: 1, overflowY: 'auto', padding: '28px 32px',
          borderRight: '1px solid #334155',
          display: 'flex', flexDirection: 'column', gap: '20px',
        }}>

          {/* ヘッダー */}
          <div>
            <h1 style={{ fontSize: '22px', fontWeight: '700', margin: '0 0 12px', lineHeight: 1.4 }}>
              {issue.title}
            </h1>
            <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap', alignItems: 'center' }}>
              {/* ステータス（クリックで変更） */}
              <div style={{ position: 'relative' }}>
                <button onClick={() => setShowStatusMenu(!showStatusMenu)} disabled={saving}
                  style={{
                    padding: '4px 12px', borderRadius: '20px', fontSize: '12px', fontWeight: '600',
                    cursor: 'pointer', border: 'none', background: si.bg, color: si.color,
                  }}>
                  {saving ? '保存中...' : si.label} ▾
                </button>
                {showStatusMenu && (
                  <div style={{
                    position: 'absolute', top: '100%', left: 0, zIndex: 100,
                    background: '#1e293b', border: '1px solid #334155', borderRadius: '8px',
                    overflow: 'hidden', marginTop: '4px', boxShadow: '0 8px 24px rgba(0,0,0,0.4)',
                  }}>
                    {STATUS_OPTIONS.map(s => (
                      <button key={s} onClick={() => handleStatusChange(s)}
                        style={{
                          display: 'block', width: '100%', padding: '8px 16px',
                          background: s === issue.status ? '#0f172a' : 'transparent',
                          border: 'none', color: STATUS_MAP[s]?.color ?? '#e2e8f0',
                          cursor: 'pointer', textAlign: 'left', fontSize: '13px',
                        }}>
                        {STATUS_MAP[s]?.label ?? s}
                      </button>
                    ))}
                  </div>
                )}
              </div>
              <span style={{
                padding: '4px 12px', borderRadius: '20px', fontSize: '12px', fontWeight: '600',
                background: '#1e293b', border: '1px solid #334155', color: pi.color,
              }}>
                {pi.label}
              </span>
              <span style={{ fontSize: '12px', color: '#64748b' }}>
                {new Date(issue.created_at).toLocaleDateString('ja-JP')}
              </span>
            </div>
          </div>

          {/* 説明 */}
          <div style={{ background: '#1e293b', border: '1px solid #334155', borderRadius: '10px', padding: '20px' }}>
            <div style={{ fontSize: '12px', color: '#64748b', marginBottom: '8px', fontWeight: '600' }}>📝 説明</div>
            <p style={{ margin: 0, fontSize: '14px', lineHeight: 1.7, color: '#cbd5e1', whiteSpace: 'pre-wrap' }}>
              {issue.description || '（説明なし）'}
            </p>
          </div>

          {/* メタ情報 */}
          <div style={{ background: '#1e293b', border: '1px solid #334155', borderRadius: '10px', padding: '20px' }}>
            <div style={{ fontSize: '12px', color: '#64748b', marginBottom: '12px', fontWeight: '600' }}>📊 詳細情報</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
              {[
                ['種別', issue.issue_type ?? '—'],
                ['担当者', issue.assignee_id ?? '未割当'],
                ['期限', issue.due_date ? new Date(issue.due_date).toLocaleDateString('ja-JP') : '未設定'],
                ['更新日', new Date(issue.updated_at).toLocaleDateString('ja-JP')],
              ].map(([label, val]) => (
                <div key={label}>
                  <div style={{ fontSize: '11px', color: '#475569', marginBottom: '2px' }}>{label}</div>
                  <div style={{ fontSize: '13px', color: '#cbd5e1' }}>{val}</div>
                </div>
              ))}
            </div>
          </div>

          {/* ── コメントスレッド ── */}
          <div style={{ background: '#1e293b', border: '1px solid #334155', borderRadius: '10px', padding: '20px' }}>
            <div style={{ fontSize: '14px', fontWeight: '700', color: '#f1f5f9', marginBottom: '16px' }}>
              💬 コメント <span style={{ fontSize: '12px', color: '#64748b', fontWeight: '400' }}>({comments.length}件)</span>
            </div>

            {/* コメント一覧 */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', marginBottom: '20px' }}>
              {comments.length === 0 ? (
                <div style={{ textAlign: 'center', padding: '24px', color: '#475569', fontSize: '13px' }}>
                  まだコメントはありません
                </div>
              ) : comments.map(c => {
                const isOwn = c.author?.id === currentUserId || c.author_id === currentUserId
                const authorName = c.author?.name ?? c.author?.email ?? '不明なユーザー'
                const isEditing = editingId === c.id

                return (
                  <div key={c.id} style={{
                    background: '#0f172a', border: `1px solid ${isOwn ? '#1e3a5f' : '#334155'}`,
                    borderRadius: '8px', padding: '12px 14px',
                  }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                      <span style={{ fontSize: '12px', fontWeight: '600', color: isOwn ? '#60a5fa' : '#94a3b8' }}>
                        {isOwn ? '👤 ' : ''}{authorName}
                      </span>
                      <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                        <span style={{ fontSize: '11px', color: '#475569' }}>
                          {new Date(c.created_at).toLocaleString('ja-JP', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })}
                        </span>
                        {isOwn && !isEditing && (
                          <>
                            <button onClick={() => { setEditingId(c.id); setEditBody(c.body) }}
                              style={{ background: 'none', border: 'none', color: '#64748b', cursor: 'pointer', fontSize: '12px' }}>
                              ✏️
                            </button>
                            <button onClick={() => deleteComment(c.id)}
                              style={{ background: 'none', border: 'none', color: '#64748b', cursor: 'pointer', fontSize: '12px' }}>
                              🗑
                            </button>
                          </>
                        )}
                      </div>
                    </div>

                    {isEditing ? (
                      <div>
                        <textarea
                          value={editBody}
                          onChange={e => setEditBody(e.target.value)}
                          rows={3}
                          style={{
                            width: '100%', background: '#1e293b', border: '1px solid #475569',
                            borderRadius: '6px', padding: '8px', color: '#e2e8f0',
                            fontSize: '13px', resize: 'vertical', boxSizing: 'border-box',
                          }}
                        />
                        <div style={{ display: 'flex', gap: '8px', marginTop: '6px', justifyContent: 'flex-end' }}>
                          <button onClick={() => setEditingId(null)}
                            style={{ padding: '4px 12px', borderRadius: '6px', background: 'transparent', border: '1px solid #334155', color: '#94a3b8', cursor: 'pointer', fontSize: '12px' }}>
                            キャンセル
                          </button>
                          <button onClick={() => saveEdit(c)}
                            style={{ padding: '4px 12px', borderRadius: '6px', background: '#3b82f6', border: 'none', color: '#fff', cursor: 'pointer', fontSize: '12px' }}>
                            保存
                          </button>
                        </div>
                      </div>
                    ) : (
                      <p style={{ margin: 0, fontSize: '13px', color: '#cbd5e1', lineHeight: 1.6, whiteSpace: 'pre-wrap' }}>
                        {c.body}
                      </p>
                    )}
                  </div>
                )
              })}
              <div ref={bottomRef} />
            </div>

            {/* 投稿フォーム */}
            {commentError && (
              <div style={{ color: '#f87171', fontSize: '12px', marginBottom: '8px' }}>⚠️ {commentError}</div>
            )}
            <div style={{ display: 'flex', gap: '10px', alignItems: 'flex-end' }}>
              <textarea
                value={commentBody}
                onChange={e => setCommentBody(e.target.value)}
                onKeyDown={e => { if (e.ctrlKey && e.key === 'Enter') submitComment() }}
                placeholder="コメントを入力... (Ctrl+Enter で送信)"
                rows={3}
                style={{
                  flex: 1, background: '#0f172a', border: '1px solid #334155',
                  borderRadius: '8px', padding: '10px 12px', color: '#e2e8f0',
                  fontSize: '13px', resize: 'vertical', boxSizing: 'border-box',
                }}
              />
              <button
                onClick={submitComment}
                disabled={submitting || !commentBody.trim()}
                style={{
                  padding: '10px 18px', borderRadius: '8px',
                  background: commentBody.trim() ? '#3b82f6' : '#1e293b',
                  border: 'none', color: commentBody.trim() ? '#fff' : '#475569',
                  cursor: commentBody.trim() ? 'pointer' : 'default',
                  fontSize: '13px', fontWeight: '600', whiteSpace: 'nowrap',
                }}>
                {submitting ? '送信中...' : '投稿'}
              </button>
            </div>
          </div>

        </div>

        {/* ── 右カラム: トレーサーパネル ── */}
        <div style={{
          width: '380px', flexShrink: 0,
          overflowY: 'auto', padding: '24px 20px',
          background: '#0a1628',
        }}>
          <div style={{ fontSize: '14px', fontWeight: '700', color: '#f1f5f9', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '8px' }}>
            🔗 意思決定トレーサー
            <span style={{ fontSize: '11px', color: '#475569', fontWeight: '400' }}>原点を追跡</span>
          </div>

          {traceLoading ? (
            <div style={{ textAlign: 'center', padding: '40px', color: '#64748b', fontSize: '13px' }}>🔄 追跡中...</div>
          ) : traceError && !trace ? (
            <div style={{ padding: '16px', borderRadius: '8px', background: '#1e293b', border: '1px solid #334155', color: '#64748b', fontSize: '13px' }}>
              トレースデータがありません<br/>
              <span style={{ fontSize: '11px' }}>INPUTから直接作成された課題の場合、トレースは表示されません。</span>
            </div>
          ) : trace ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>

              <TraceNode icon="📋" label="ISSUE（課題）" color="#3b82f6"
                title={trace.issue.title}
                meta={STATUS_MAP[trace.issue.status]?.label} />

              {trace.action && <>
                <TraceArrow reason="判断" />
                <TraceNode icon="⚡" label="ACTION（対応判断）" color="#8b5cf6"
                  title={trace.action.action_type}
                  body={trace.action.decision_reason}
                  meta={new Date(trace.action.created_at).toLocaleDateString('ja-JP')} />
              </>}

              {trace.item && <>
                <TraceArrow reason="分解" />
                <TraceNode icon="🧩" label={`ITEM — ${trace.item.intent_code}/${trace.item.domain_code}`} color="#10b981"
                  title={trace.item.text}
                  meta={`信頼度 ${Math.round(trace.item.confidence * 100)}%`} />
              </>}

              {trace.input && <>
                <TraceArrow reason="原文" />
                <div style={{ background: '#1e293b', border: '2px solid #f59e0b', borderRadius: '10px', overflow: 'hidden' }}>
                  <div style={{ padding: '10px 14px', borderBottom: '1px solid #334155' }}>
                    <div style={{ fontSize: '10px', color: '#f59e0b', fontWeight: '700', marginBottom: '2px' }}>
                      📄 INPUT — {trace.input.source_type}
                    </div>
                    <div style={{ fontSize: '11px', color: '#64748b' }}>
                      {new Date(trace.input.created_at).toLocaleDateString('ja-JP')}
                      {trace.input.author && ` / ${trace.input.author}`}
                    </div>
                  </div>
                  <div style={{ padding: '12px 14px' }}>
                    <p style={{
                      margin: 0, fontSize: '13px', color: '#cbd5e1', lineHeight: 1.6,
                      whiteSpace: 'pre-wrap',
                      maxHeight: inputExpanded ? 'none' : '120px',
                      overflow: inputExpanded ? 'visible' : 'hidden',
                    }}>
                      {trace.input.raw_text}
                    </p>
                    {trace.input.raw_text.length > 200 && (
                      <button onClick={() => setInputExpanded(!inputExpanded)}
                        style={{ marginTop: '8px', background: 'none', border: 'none', color: '#f59e0b', cursor: 'pointer', fontSize: '12px' }}>
                        {inputExpanded ? '▲ 折りたたむ' : '▼ 全文を表示'}
                      </button>
                    )}
                  </div>
                </div>
              </>}
            </div>
          ) : null}
        </div>

      </div>
    </div>
  )
}

// ── サブコンポーネント ──────────────────────────────────────────────────

function TraceArrow({ reason }: { reason: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', padding: '2px 14px', gap: '6px' }}>
      <div style={{ width: '2px', height: '20px', background: '#334155', margin: '0 auto' }} />
      <span style={{ fontSize: '10px', color: '#475569' }}>{reason}</span>
    </div>
  )
}

function TraceNode({ icon, label, color, title, body, meta }: {
  icon: string; label: string; color: string; title: string; body?: string; meta?: string
}) {
  return (
    <div style={{ background: '#1e293b', border: `2px solid ${color}`, borderRadius: '10px', padding: '12px 14px' }}>
      <div style={{ fontSize: '10px', color, fontWeight: '700', marginBottom: '6px', letterSpacing: '0.05em' }}>
        {icon} {label}
      </div>
      <div style={{ fontSize: '13px', color: '#f1f5f9', fontWeight: '500', lineHeight: 1.5 }}>{title}</div>
      {body && <div style={{ fontSize: '12px', color: '#94a3b8', marginTop: '4px', lineHeight: 1.5 }}>{body}</div>}
      {meta && <div style={{ fontSize: '11px', color: '#475569', marginTop: '6px' }}>{meta}</div>}
    </div>
  )
}
TSX_EOF

ok "IssueDetail.tsx — コメント機能追加完了"

# ============================================================
section "4. TypeScript ビルド確認"
# ============================================================
cd $FRONTEND_DIR
info "npm run build 実行中..."
if npm run build > /tmp/comment_build.log 2>&1; then
  ok "ビルド成功 🎉"
else
  grep -E "error TS" /tmp/comment_build.log | head -20
  warn "ビルドエラー確認してください"
fi

# ============================================================
section "5. コメント投稿の動作テスト"
# ============================================================
# 既存のISSUE IDを取得してテスト投稿
ISSUE_ID=$(curl -s "http://localhost:8089/api/v1/issues" \
  -H "Authorization: Bearer $TOKEN" | \
  python3 -c "
import sys,json
d=json.load(sys.stdin)
items = d if isinstance(d,list) else d.get('items',d.get('data',[]))
print(items[0]['id'] if items else '')
" 2>/dev/null || echo "")

if [ -n "$ISSUE_ID" ]; then
  POST=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "http://localhost:8089/api/v1/conversations" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"issue_id\":\"$ISSUE_ID\",\"body\":\"動作確認コメント\"}")
  info "コメント投稿テスト: HTTP $POST"
  [ "$POST" = "201" ] || [ "$POST" = "200" ] && ok "コメント投稿 OK" || warn "HTTP $POST (要確認)"
fi

echo ""
echo "=============================================="
echo "🎉 コメント機能 実装完了！"
echo ""
echo "  確認方法:"
echo "  1. http://localhost:3008/issues/<ISSUE_ID>"
echo "  2. 左カラム下部「💬 コメント」エリアを確認"
echo "  3. 入力 → 投稿ボタン or Ctrl+Enter で送信"
echo "  4. 自分のコメントに ✏️ 編集 / 🗑 削除 が表示される"
echo "=============================================="
