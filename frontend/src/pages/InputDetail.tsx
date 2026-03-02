import { useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import {
  ArrowLeft, Mail, Mic, Users, Bug, MoreHorizontal,
  ChevronDown, ChevronUp, ExternalLink, Loader2, AlertCircle,
} from 'lucide-react'
import apiClient from '@/api/client'

/* ── 型定義 ─────────────────────────────────────────────── */
interface InputRecord {
  id: string
  source_type: string
  raw_text: string
  author?: string
  author_name?: string
  created_at: string
  project_id?: string
}

interface ItemRecord {
  id: string
  text: string
  intent_code: string
  domain_code: string
  confidence: number
  position: number
  action?: ActionRecord
}

interface ActionRecord {
  id: string
  action_type: string
  decision_reason?: string
  issue_id?: string
  decided_at?: string
  created_at?: string
}

interface TraceResult {
  input: InputRecord
  items: ItemRecord[]
}

/* ── 定数 ────────────────────────────────────────────────── */
const SOURCE_META: Record<string, { icon: React.ElementType; label: string; color: string }> = {
  email:   { icon: Mail,           label: 'メール',   color: '#60a5fa' },
  voice:   { icon: Mic,            label: '音声',     color: '#a78bfa' },
  meeting: { icon: Users,          label: '会議',     color: '#34d399' },
  bug:     { icon: Bug,            label: 'バグ報告', color: '#f87171' },
  other:   { icon: MoreHorizontal, label: 'その他',   color: 'var(--text-muted)' },
}

const INTENT_LABEL: Record<string, { label: string; color: string }> = {
  REQ: { label: '要求',   color: '#818cf8' },
  BUG: { label: 'バグ',   color: '#f87171' },
  IMP: { label: '改善',   color: '#fbbf24' },
  QST: { label: '質問',   color: '#34d399' },
  FBK: { label: 'FBK',   color: 'var(--text-muted)' },
  INF: { label: '情報',   color: 'var(--text-secondary, #64748b)' },
  MIS: { label: '誤解',   color: '#f97316' },
  OTH: { label: 'その他', color: 'var(--text-secondary, #64748b)' },
}

const ACTION_LABEL: Record<string, { label: string; color: string; bg: string }> = {
  CREATE_ISSUE:  { label: '課題化',  color: '#818cf8', bg: 'rgba(99,102,241,0.15)' },
  ANSWER:        { label: '回答',    color: '#34d399', bg: 'rgba(52,211,153,0.15)' },
  STORE:         { label: '保存',    color: '#60a5fa', bg: 'rgba(59,130,246,0.15)' },
  REJECT:        { label: '却下',    color: '#f87171', bg: 'rgba(239,68,68,0.15)'  },
  HOLD:          { label: '保留',    color: '#fbbf24', bg: 'rgba(245,158,11,0.15)' },
  LINK_EXISTING: { label: '既存紐付', color: 'var(--text-muted)', bg: 'rgba(100,116,139,0.15)'},
}

/* ── データ取得 ──────────────────────────────────────────── */
async function fetchInputTrace(id: string): Promise<TraceResult> {
  // INPUT詳細 + そのINPUTから派生したITEM一覧を取得
  const [inpRes, itemsRes] = await Promise.all([
    apiClient.get(`/inputs/${id}`),
    apiClient.get(`/items?input_id=${id}`).catch(() => ({ data: [] })),
  ])

  const input: InputRecord = inpRes.data

  // items の正規化
  const rawItems = (() => {
    const d = itemsRes.data
    if (Array.isArray(d)) return d
    if (Array.isArray(d?.items)) return d.items
    return []
  })()

  // 各ITEMに紐づくACTIONを取得（並列）
  const items: ItemRecord[] = await Promise.all(
    rawItems.map(async (item: ItemRecord) => {
      try {
        const actRes = await apiClient.get(`/actions?item_id=${item.id}`)
        const actData = actRes.data
        const actions = Array.isArray(actData) ? actData
          : Array.isArray(actData?.items) ? actData.items : []
        return { ...item, action: actions[0] ?? undefined }
      } catch {
        return item
      }
    })
  )

  return { input, items: items.sort((a, b) => (a.position ?? 0) - (b.position ?? 0)) }
}

async function fetchIssue(issueId: string) {
  const res = await apiClient.get(`/issues/${issueId}`)
  return res.data
}

/* ── Issue インライン表示コンポーネント ─────────────────── */
function LinkedIssue({ issueId }: { issueId: string }) {
  const { data: issue, isLoading } = useQuery({
    queryKey: ['issue-mini', issueId],
    queryFn: () => fetchIssue(issueId),
  })

  if (isLoading) return (
    <span style={{ fontSize: 12, color: 'var(--text-secondary, #64748b)' }}>読み込み中...</span>
  )
  if (!issue) return null

  return (
    <Link
      to={`/issues/${issueId}`}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 6,
        padding: '4px 10px', borderRadius: 6,
        background: 'rgba(99,102,241,0.12)', border: '1px solid rgba(99,102,241,0.3)',
        color: '#818cf8', textDecoration: 'none', fontSize: 12, fontWeight: 500,
        marginTop: 6,
      }}
    >
      <ExternalLink size={11} />
      {issue.title ?? `ISSUE: ${issueId.slice(0, 8)}`}
    </Link>
  )
}

/* ── メインコンポーネント ────────────────────────────────── */
export default function InputDetail() {
  const { id } = useParams<{ id: string }>()
  const [textExpanded, setTextExpanded] = useState(false)

  const { data: trace, isLoading, isError } = useQuery({
    queryKey: ['input-trace', id],
    queryFn: () => fetchInputTrace(id!),
    enabled: !!id,
  })

  if (isLoading) return (
    <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-secondary, #64748b)' }}>
      <Loader2 size={24} style={{ margin: '0 auto 12px', display: 'block', animation: 'spin 1s linear infinite' }} />
      <style>{`@keyframes spin{to{transform:rotate(360deg)}}`}</style>
      解析連鎖を構築中...
    </div>
  )
  if (isError || !trace) return (
    <div style={{ padding: 40, textAlign: 'center', color: '#ef4444' }}>
      <AlertCircle size={20} style={{ marginBottom: 8, display: 'block', margin: '0 auto 8px' }} />
      データの取得に失敗しました
    </div>
  )

  const { input, items } = trace
  const src = SOURCE_META[input.source_type] ?? SOURCE_META['other']
  const SrcIcon = src.icon
  const issueCount = items.filter(it => it.action?.action_type === 'CREATE_ISSUE' && it.action?.issue_id).length

  return (
    <div style={{ maxWidth: 860 }}>
      {/* Back */}
      <Link
        to="/inputs"
        style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: 'var(--text-secondary, #64748b)', textDecoration: 'none', fontSize: 13, marginBottom: 20 }}
      >
        <ArrowLeft size={14} /> 要望履歴に戻る
      </Link>

      {/* ── INPUT カード ── */}
      <div className="card" style={{ padding: '20px 24px', marginBottom: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 14 }}>
          <div style={{
            width: 36, height: 36, borderRadius: 8, flexShrink: 0,
            background: `${src.color}22`, display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <SrcIcon size={18} color={src.color} />
          </div>
          <div>
            <div style={{ fontSize: 11, color: src.color, fontWeight: 700, letterSpacing: '0.06em', textTransform: 'uppercase' }}>
              📄 INPUT — {src.label}
            </div>
            <div style={{ fontSize: 11, color: 'var(--text-secondary, #64748b)', fontFamily: 'DM Mono, monospace', marginTop: 2 }}>
              {new Date(input.created_at).toLocaleString('ja-JP')}
              {input.author_name || input.author ? `  /  ${input.author_name ?? input.author}` : ''}
            </div>
          </div>
          <div style={{ marginLeft: 'auto', display: 'flex', gap: 10 }}>
            <div style={{ textAlign: 'right' }}>
              <div style={{ fontSize: 11, color: 'var(--text-secondary, #64748b)' }}>分解 ITEM</div>
              <div style={{ fontSize: 18, fontWeight: 700, color: 'var(--text-muted)' }}>{items.length}</div>
            </div>
            <div style={{ textAlign: 'right' }}>
              <div style={{ fontSize: 11, color: 'var(--text-secondary, #64748b)' }}>発生課題</div>
              <div style={{ fontSize: 18, fontWeight: 700, color: '#818cf8' }}>{issueCount}</div>
            </div>
          </div>
        </div>

        {/* Raw text */}
        <div style={{
          background: '#0f1117', borderRadius: 8, padding: '14px 16px',
          border: '1px solid #1e2535', position: 'relative',
        }}>
          <p style={{
            margin: 0, fontSize: 13, color: '#cbd5e1', lineHeight: 1.8,
            whiteSpace: 'pre-wrap',
            maxHeight: textExpanded ? 'none' : '120px',
            overflow: textExpanded ? 'visible' : 'hidden',
          }}>
            {input.raw_text}
          </p>
          {input.raw_text.length > 200 && (
            <button
              onClick={() => setTextExpanded(!textExpanded)}
              style={{
                marginTop: 8, background: 'none', border: 'none',
                color: '#6366f1', cursor: 'pointer', fontSize: 12,
                display: 'flex', alignItems: 'center', gap: 4, padding: 0,
              }}
            >
              {textExpanded ? <><ChevronUp size={13} /> 折りたたむ</> : <><ChevronDown size={13} /> 全文を表示</>}
            </button>
          )}
        </div>
      </div>

      {/* ── ITEM → ACTION → ISSUE 連鎖 ── */}
      <div style={{ marginBottom: 12 }}>
        <h2 style={{ margin: '0 0 12px', fontSize: 14, fontWeight: 700, color: 'var(--text-secondary, #64748b)', letterSpacing: '0.08em', textTransform: 'uppercase' }}>
          分解結果 — {items.length} ITEM
        </h2>

        {items.length === 0 ? (
          <div className="card" style={{ padding: '32px', textAlign: 'center', color: 'var(--text-secondary, #64748b)', fontSize: 13 }}>
            このINPUTはまだ解析されていません
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {items.map((item, idx) => {
              const intent = INTENT_LABEL[item.intent_code] ?? { label: item.intent_code, color: 'var(--text-muted)' }
              const act = item.action ? (ACTION_LABEL[item.action.action_type] ?? null) : null

              return (
                <div key={item.id} className="card" style={{ padding: '14px 18px' }}>
                  <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
                    {/* Position number */}
                    <div style={{
                      width: 22, height: 22, borderRadius: 6, flexShrink: 0,
                      background: '#2d3548',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      fontSize: 11, fontWeight: 700, color: 'var(--text-secondary, #64748b)',
                      fontFamily: 'DM Mono, monospace', marginTop: 1,
                    }}>
                      {idx + 1}
                    </div>

                    <div style={{ flex: 1 }}>
                      {/* Badges */}
                      <div style={{ display: 'flex', gap: 6, marginBottom: 6, flexWrap: 'wrap', alignItems: 'center' }}>
                        <span className="badge" style={{ background: `${intent.color}22`, color: intent.color }}>
                          {intent.label}
                        </span>
                        <span className="badge" style={{ background: 'rgba(100,116,139,0.15)', color: 'var(--text-muted)' }}>
                          {item.domain_code}
                        </span>
                        <span style={{ fontSize: 11, color: 'var(--text-secondary, #64748b)', fontFamily: 'DM Mono, monospace' }}>
                          信頼度 {Math.round(item.confidence * 100)}%
                        </span>
                      </div>

                      {/* Item text */}
                      <p style={{ margin: '0 0 8px', fontSize: 13, color: 'var(--text-primary)', lineHeight: 1.6 }}>
                        {item.text}
                      </p>

                      {/* Action */}
                      {item.action && act && (
                        <div style={{ borderTop: '1px solid #1e2535', paddingTop: 8, marginTop: 4 }}>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                            <span style={{ fontSize: 11, color: 'var(--text-secondary, #64748b)' }}>→ ACTION:</span>
                            <span className="badge" style={{ background: act.bg, color: act.color }}>
                              {act.label}
                            </span>
                            {item.action.decision_reason && (
                              <span style={{ fontSize: 12, color: 'var(--text-secondary, #64748b)', fontStyle: 'italic' }}>
                                "{item.action.decision_reason}"
                              </span>
                            )}
                          </div>

                          {/* 課題リンク */}
                          {item.action.action_type === 'CREATE_ISSUE' && item.action.issue_id && (
                            <LinkedIssue issueId={item.action.issue_id} />
                          )}
                        </div>
                      )}

                      {/* Action なし */}
                      {!item.action && (
                        <div style={{ borderTop: '1px solid #1e2535', paddingTop: 8, marginTop: 4 }}>
                          <span style={{ fontSize: 11, color: '#334155' }}>ACTION 未設定</span>
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}
