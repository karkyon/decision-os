import { useState, useEffect, useRef } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import client from '../api/client'

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
  open:        { label: '未着手',   color: '#fbbf24', bg: 'rgba(251,191,36,0.15)' },
  in_progress: { label: '進行中',   color: '#60a5fa', bg: 'rgba(96,165,250,0.15)' },
  review:      { label: 'レビュー', color: '#a78bfa', bg: 'rgba(167,139,250,0.15)' },
  done:        { label: '完了',     color: '#4ade80', bg: 'rgba(74,222,128,0.15)' },
  closed:      { label: 'クローズ', color: 'var(--text-muted)', bg: 'var(--bg-muted)' },
}
const PRIORITY_MAP: Record<string, { label: string; color: string }> = {
  critical: { label: '緊急', color: '#ef4444' },
  high:     { label: '高',   color: '#f97316' },
  medium:   { label: '中',   color: '#eab308' },
  low:      { label: '低',   color: 'var(--text-muted)' },
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
  const [_traceLoading, _setTraceLoading] = useState(false)
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
    <div style={{ padding: '40px', color: 'var(--text-muted)', textAlign: 'center' }}>🔄 読み込み中...</div>
  )
  if (error || !issue) return (
    <div style={{ padding: '40px', color: '#f87171', textAlign: 'center' }}>⚠️ {error || '課題が見つかりません'}</div>
  )

  const si = STATUS_MAP[issue.status] ?? { label: issue.status, color: 'var(--text-muted)', bg: 'var(--bg-muted)' }
  const pi = PRIORITY_MAP[issue.priority] ?? { label: issue.priority, color: 'var(--text-muted)' }

  return (
    <div style={{ minHeight: '100vh', background: 'var(--bg-base)', color: 'var(--text-primary)' }}>

      {/* ── ナビバー ── */}
      <nav style={{
        background: 'var(--bg-card)', borderBottom: '1px solid var(--border)',
        padding: '0 24px', height: '52px',
        display: 'flex', alignItems: 'center', gap: '16px',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
          <button onClick={() => navigate('/')}
            style={{ background: 'none', border: 'none', color: '#60a5fa', cursor: 'pointer', fontSize: '20px' }}>⚖️</button>
          <button onClick={() => navigate(-1)}
            style={{ background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', fontSize: '13px' }}>← 戻る</button>
          <span style={{ color: 'var(--text-muted)', fontSize: '13px' }}>/ 課題詳細</span>
        </div>
      </nav>

      {/* ── 2カラムレイアウト ── */}
      <div style={{ display: 'flex', height: 'calc(100vh - 52px)' }}>

        {/* ── 左カラム: 課題本体 ＋ コメント ── */}
        <div style={{
          flex: 1, overflowY: 'auto', padding: '28px 32px',
          borderRight: '1px solid var(--border)',
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
                    background: 'var(--bg-card)', border: '1px solid var(--border)', borderRadius: '8px',
                    overflow: 'hidden', marginTop: '4px', boxShadow: '0 8px 24px rgba(0,0,0,0.4)',
                  }}>
                    {STATUS_OPTIONS.map(s => (
                      <button key={s} onClick={() => handleStatusChange(s)}
                        style={{
                          display: 'block', width: '100%', padding: '8px 16px',
                          background: s === issue.status ? 'var(--accent-light)' : 'transparent',
                          border: 'none', color: STATUS_MAP[s]?.color ?? 'var(--text-primary)',
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
                background: 'var(--bg-card)', border: '1px solid var(--border)', color: pi.color,
              }}>
                {pi.label}
              </span>
              <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                {new Date(issue.created_at).toLocaleDateString('ja-JP')}
              </span>
            </div>
          </div>

          {/* 説明 */}
          <div style={{ background: 'var(--bg-card)', border: '1px solid var(--border)', borderRadius: '10px', padding: '20px' }}>
            <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '8px', fontWeight: '600' }}>📝 説明</div>
            <p style={{ margin: 0, fontSize: '14px', lineHeight: 1.7, color: 'var(--text-primary)', whiteSpace: 'pre-wrap' }}>
              {issue.description || '（説明なし）'}
            </p>
          </div>

          {/* メタ情報 */}
          <div style={{ background: 'var(--bg-card)', border: '1px solid var(--border)', borderRadius: '10px', padding: '20px' }}>
            <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '12px', fontWeight: '600' }}>📊 詳細情報</div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
              {[
                ['種別', issue.issue_type ?? '—'],
                ['担当者', issue.assignee_id ?? '未割当'],
                ['期限', issue.due_date ? new Date(issue.due_date).toLocaleDateString('ja-JP') : '未設定'],
                ['更新日', new Date(issue.updated_at).toLocaleDateString('ja-JP')],
              ].map(([label, val]) => (
                <div key={label}>
                  <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginBottom: '2px' }}>{label}</div>
                  <div style={{ fontSize: '13px', color: 'var(--text-primary)' }}>{val}</div>
                </div>
              ))}
            </div>
          </div>

          {/* ── コメントスレッド ── */}
          <div style={{ background: 'var(--bg-card)', border: '1px solid var(--border)', borderRadius: '10px', padding: '20px' }}>
            <div style={{ fontSize: '14px', fontWeight: '700', color: 'var(--text-primary)', marginBottom: '16px' }}>
              💬 コメント <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: '400' }}>({comments.length}件)</span>
            </div>

            {/* コメント一覧 */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', marginBottom: '20px' }}>
              {comments.length === 0 ? (
                <div style={{ textAlign: 'center', padding: '24px', color: 'var(--text-muted)', fontSize: '13px' }}>
                  まだコメントはありません
                </div>
              ) : comments.map(c => {
                const isOwn = c.author?.id === currentUserId || c.author_id === currentUserId
                const authorName = c.author?.name ?? c.author?.email ?? '不明なユーザー'
                const isEditing = editingId === c.id

                return (
                  <div key={c.id} style={{
                    background: 'var(--bg-base)', border: `1px solid ${isOwn ? '#1e3a5f' : '#334155'}`,
                    borderRadius: '8px', padding: '12px 14px',
                  }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                      <span style={{ fontSize: '12px', fontWeight: '600', color: isOwn ? '#60a5fa' : '#94a3b8' }}>
                        {isOwn ? '👤 ' : ''}{authorName}
                      </span>
                      <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                        <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                          {new Date(c.created_at).toLocaleString('ja-JP', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })}
                        </span>
                        {isOwn && !isEditing && (
                          <>
                            <button onClick={() => { setEditingId(c.id); setEditBody(c.body) }}
                              style={{ background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', fontSize: '12px' }}>
                              ✏️
                            </button>
                            <button onClick={() => deleteComment(c.id)}
                              style={{ background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', fontSize: '12px' }}>
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
                            width: '100%', background: 'var(--bg-card)', border: '1px solid #475569',
                            borderRadius: '6px', padding: '8px', color: 'var(--text-primary)',
                            fontSize: '13px', resize: 'vertical', boxSizing: 'border-box',
                          }}
                        />
                        <div style={{ display: 'flex', gap: '8px', marginTop: '6px', justifyContent: 'flex-end' }}>
                          <button onClick={() => setEditingId(null)}
                            style={{ padding: '4px 12px', borderRadius: '6px', background: 'transparent', border: '1px solid var(--border)', color: 'var(--text-muted)', cursor: 'pointer', fontSize: '12px' }}>
                            キャンセル
                          </button>
                          <button onClick={() => saveEdit(c)}
                            style={{ padding: '4px 12px', borderRadius: '6px', background: '#3b82f6', border: 'none', color: '#fff', cursor: 'pointer', fontSize: '12px' }}>
                            保存
                          </button>
                        </div>
                      </div>
                    ) : (
                      <p style={{ margin: 0, fontSize: '13px', color: 'var(--text-primary)', lineHeight: 1.6, whiteSpace: 'pre-wrap' }}>
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
                  flex: 1, background: 'var(--bg-base)', border: '1px solid var(--border)',
                  borderRadius: '8px', padding: '10px 12px', color: 'var(--text-primary)',
                  fontSize: '13px', resize: 'vertical', boxSizing: 'border-box',
                }}
              />
              <button
                onClick={submitComment}
                disabled={submitting || !commentBody.trim()}
                style={{
                  padding: '10px 18px', borderRadius: '8px',
                  background: commentBody.trim() ? '#3b82f6' : 'var(--bg-muted)',
                  border: 'none', color: commentBody.trim() ? '#fff' : 'var(--text-muted)',
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
          background: 'var(--bg-surface)',
        }}>
          <div style={{ fontSize: '14px', fontWeight: '700', color: 'var(--text-primary)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '8px' }}>
            🔗 意思決定トレーサー
            <span style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: '400' }}>原点を追跡</span>
          </div>

          {_traceLoading ? (
            <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)', fontSize: '13px' }}>🔄 追跡中...</div>
          ) : traceError && !trace ? (
            <div style={{ padding: '16px', borderRadius: '8px', background: 'var(--bg-card)', border: '1px solid var(--border)', color: 'var(--text-muted)', fontSize: '13px' }}>
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
                <div style={{ background: 'var(--bg-card)', border: '2px solid #f59e0b', borderRadius: '10px', overflow: 'hidden' }}>
                  <div style={{ padding: '10px 14px', borderBottom: '1px solid var(--border)' }}>
                    <div style={{ fontSize: '10px', color: '#f59e0b', fontWeight: '700', marginBottom: '2px' }}>
                      📄 INPUT — {trace.input.source_type}
                    </div>
                    <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                      {new Date(trace.input.created_at).toLocaleDateString('ja-JP')}
                      {trace.input.author && ` / ${trace.input.author}`}
                    </div>
                  </div>
                  <div style={{ padding: '12px 14px' }}>
                    <p style={{
                      margin: 0, fontSize: '13px', color: 'var(--text-primary)', lineHeight: 1.6,
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
      <span style={{ fontSize: '10px', color: 'var(--text-muted)' }}>{reason}</span>
    </div>
  )
}

function TraceNode({ icon, label, color, title, body, meta }: {
  icon: string; label: string; color: string; title: string; body?: string; meta?: string
}) {
  return (
    <div style={{ background: 'var(--bg-card)', border: `2px solid ${color}`, borderRadius: '10px', padding: '12px 14px' }}>
      <div style={{ fontSize: '10px', color, fontWeight: '700', marginBottom: '6px', letterSpacing: '0.05em' }}>
        {icon} {label}
      </div>
      <div style={{ fontSize: '13px', color: 'var(--text-primary)', fontWeight: '500', lineHeight: 1.5 }}>{title}</div>
      {body && <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '4px', lineHeight: 1.5 }}>{body}</div>}
      {meta && <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '6px' }}>{meta}</div>}
    </div>
  )
}
