#!/usr/bin/env bash
# =============================================================================
# decision-os / 27: 要望履歴ページ実装
# INPUT一覧 + INPUT詳細（誰が・いつ・どのテキスト→どの課題が発生したか）
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

FRONTEND="$HOME/projects/decision-os/frontend/src"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use 20 2>/dev/null || true

# =============================================================================
section "1. InputHistory.tsx — 要望履歴一覧"
# =============================================================================
cat > "$FRONTEND/pages/InputHistory.tsx" << 'TSX'
import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import {
  FileText, Search, ChevronDown, Loader2, AlertCircle,
  Mail, Mic, Users, Bug, MoreHorizontal, ArrowRight,
} from 'lucide-react'
import apiClient from '@/api/client'

interface InputRecord {
  id: string
  source_type: 'email' | 'voice' | 'meeting' | 'bug' | 'other'
  raw_text: string
  author?: string
  author_name?: string
  created_at: string
  project_id?: string
  item_count?: number
  issue_count?: number
  status?: string
}

const SOURCE_META: Record<string, { icon: React.ElementType; label: string; color: string; bg: string }> = {
  email:   { icon: Mail,           label: 'メール',   color: '#60a5fa', bg: 'rgba(59,130,246,0.15)' },
  voice:   { icon: Mic,            label: '音声',     color: '#a78bfa', bg: 'rgba(139,92,246,0.15)' },
  meeting: { icon: Users,          label: '会議',     color: '#34d399', bg: 'rgba(52,211,153,0.15)' },
  bug:     { icon: Bug,            label: 'バグ報告', color: '#f87171', bg: 'rgba(239,68,68,0.15)'  },
  other:   { icon: MoreHorizontal, label: 'その他',   color: '#94a3b8', bg: 'rgba(100,116,139,0.15)'},
}

async function fetchInputs(params: Record<string, string>) {
  const q = new URLSearchParams(params).toString()
  const res = await apiClient.get(`/inputs?${q}`)
  const d = res.data
  if (Array.isArray(d)) return { items: d as InputRecord[], total: d.length }
  if (Array.isArray(d?.items)) return { items: d.items as InputRecord[], total: (d.total ?? d.items.length) as number }
  const arr = Object.values(d as Record<string, unknown>).find((v): v is InputRecord[] => Array.isArray(v))
  return { items: arr ?? [], total: arr?.length ?? 0 }
}

const SOURCE_FILTERS = [
  { value: '', label: 'すべて' },
  { value: 'email',   label: 'メール' },
  { value: 'voice',   label: '音声' },
  { value: 'meeting', label: '会議' },
  { value: 'bug',     label: 'バグ報告' },
  { value: 'other',   label: 'その他' },
]

export default function InputHistory() {
  const [search, setSearch]           = useState('')
  const [sourceFilter, setSourceFilter] = useState('')
  const [page, setPage]               = useState(1)
  const limit = 20

  const params: Record<string, string> = {
    skip:  String((page - 1) * limit),
    limit: String(limit),
    ...(search       ? { q: search }              : {}),
    ...(sourceFilter ? { source_type: sourceFilter } : {}),
  }

  const { data, isLoading, isError } = useQuery({
    queryKey: ['inputs', params],
    queryFn: () => fetchInputs(params),
    placeholderData: prev => prev,
  })

  const inputs: InputRecord[] = data?.items ?? []
  const total  = data?.total ?? 0
  const totalPages = Math.ceil(total / limit)

  return (
    <div>
      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
        <div>
          <h1 style={{ margin: 0, fontSize: 22, fontWeight: 700, color: '#f1f5f9', letterSpacing: '-0.03em' }}>
            要望履歴
          </h1>
          <p style={{ margin: '4px 0 0', fontSize: 13, color: '#64748b' }}>
            登録済みの原文・解析履歴 — {total.toLocaleString()} 件
          </p>
        </div>
        <Link
          to="/inputs/new"
          style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '9px 16px', borderRadius: 8,
            background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
            color: '#fff', textDecoration: 'none', fontSize: 13, fontWeight: 600,
            boxShadow: '0 4px 12px rgba(99,102,241,0.3)',
          }}
        >
          <FileText size={14} />
          新規登録
        </Link>
      </div>

      {/* Filters */}
      <div className="card" style={{ padding: '14px 16px', marginBottom: 16, display: 'flex', gap: 10, alignItems: 'center', flexWrap: 'wrap' }}>
        <div style={{ position: 'relative', flex: 1, minWidth: 200 }}>
          <Search size={14} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: '#64748b' }} />
          <input
            value={search}
            onChange={e => { setSearch(e.target.value); setPage(1) }}
            placeholder="原文テキスト・著者で検索..."
            style={{
              width: '100%', padding: '8px 10px 8px 32px',
              background: '#0f1117', border: '1px solid #2d3548',
              borderRadius: 6, color: '#e2e8f0', fontSize: 13, outline: 'none',
            }}
          />
        </div>
        <div style={{ position: 'relative' }}>
          <select
            value={sourceFilter}
            onChange={e => { setSourceFilter(e.target.value); setPage(1) }}
            style={{
              padding: '8px 28px 8px 12px',
              background: '#0f1117', border: '1px solid #2d3548',
              borderRadius: 6, color: '#e2e8f0', fontSize: 13,
              outline: 'none', cursor: 'pointer', appearance: 'none',
            }}
          >
            {SOURCE_FILTERS.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
          </select>
          <ChevronDown size={12} style={{ position: 'absolute', right: 8, top: '50%', transform: 'translateY(-50%)', color: '#64748b', pointerEvents: 'none' }} />
        </div>
      </div>

      {/* List */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {isLoading ? (
          <div className="card" style={{ padding: '60px', textAlign: 'center', color: '#64748b' }}>
            <Loader2 size={24} style={{ margin: '0 auto 12px', display: 'block', animation: 'spin 1s linear infinite' }} />
            <style>{`@keyframes spin{to{transform:rotate(360deg)}}`}</style>
            読み込み中...
          </div>
        ) : isError ? (
          <div className="card" style={{ padding: '40px', textAlign: 'center', color: '#ef4444' }}>
            <AlertCircle size={20} style={{ marginBottom: 8, display: 'block', margin: '0 auto 8px' }} />
            データの取得に失敗しました
          </div>
        ) : inputs.length === 0 ? (
          <div className="card" style={{ padding: '60px', textAlign: 'center', color: '#64748b', fontSize: 14 }}>
            要望履歴がありません
          </div>
        ) : inputs.map(inp => {
          const src = SOURCE_META[inp.source_type] ?? SOURCE_META['other']
          const SrcIcon = src.icon
          const preview = inp.raw_text.length > 120
            ? inp.raw_text.slice(0, 120) + '…'
            : inp.raw_text

          return (
            <Link
              key={inp.id}
              to={`/inputs/${inp.id}`}
              style={{ textDecoration: 'none' }}
            >
              <div
                className="card"
                style={{ padding: '16px 20px', transition: 'border-color 0.15s, background 0.15s', cursor: 'pointer' }}
                onMouseEnter={e => {
                  const el = e.currentTarget as HTMLDivElement
                  el.style.borderColor = '#4f46e5'
                  el.style.background = 'rgba(99,102,241,0.04)'
                }}
                onMouseLeave={e => {
                  const el = e.currentTarget as HTMLDivElement
                  el.style.borderColor = '#2d3548'
                  el.style.background = '#1a1f2e'
                }}
              >
                <div style={{ display: 'flex', alignItems: 'flex-start', gap: 14 }}>
                  {/* Source icon */}
                  <div style={{
                    width: 36, height: 36, borderRadius: 8, flexShrink: 0,
                    background: src.bg, display: 'flex', alignItems: 'center', justifyContent: 'center',
                  }}>
                    <SrcIcon size={16} color={src.color} />
                  </div>

                  {/* Content */}
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6, flexWrap: 'wrap' }}>
                      <span className="badge" style={{ background: src.bg, color: src.color }}>{src.label}</span>
                      {inp.author_name || inp.author ? (
                        <span style={{ fontSize: 12, color: '#94a3b8' }}>
                          by {inp.author_name ?? inp.author}
                        </span>
                      ) : null}
                      <span style={{ fontSize: 11, color: '#475569', fontFamily: 'DM Mono, monospace', marginLeft: 'auto' }}>
                        {new Date(inp.created_at).toLocaleString('ja-JP', {
                          year: 'numeric', month: '2-digit', day: '2-digit',
                          hour: '2-digit', minute: '2-digit',
                        })}
                      </span>
                    </div>

                    <p style={{ margin: '0 0 8px', fontSize: 13, color: '#cbd5e1', lineHeight: 1.6, whiteSpace: 'pre-wrap' }}>
                      {preview}
                    </p>

                    {/* Stats */}
                    <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                      {inp.item_count != null && (
                        <span style={{ fontSize: 11, color: '#64748b' }}>
                          分解: <strong style={{ color: '#94a3b8' }}>{inp.item_count}</strong> ITEM
                        </span>
                      )}
                      {inp.issue_count != null && inp.issue_count > 0 && (
                        <span style={{ fontSize: 11, color: '#64748b' }}>
                          発生課題: <strong style={{ color: '#818cf8' }}>{inp.issue_count}</strong> 件
                        </span>
                      )}
                      <span style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 4, fontSize: 12, color: '#4f46e5' }}>
                        詳細を見る <ArrowRight size={12} />
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </Link>
          )
        })}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div style={{ display: 'flex', justifyContent: 'center', gap: 6, marginTop: 20 }}>
          <button
            onClick={() => setPage(p => Math.max(1, p - 1))}
            disabled={page === 1}
            style={{
              padding: '6px 14px', borderRadius: 6, fontSize: 13,
              background: '#1a1f2e', border: '1px solid #2d3548',
              color: page === 1 ? '#334155' : '#94a3b8', cursor: page === 1 ? 'not-allowed' : 'pointer',
            }}
          >←</button>
          <span style={{ padding: '6px 14px', fontSize: 13, color: '#64748b' }}>{page} / {totalPages}</span>
          <button
            onClick={() => setPage(p => Math.min(totalPages, p + 1))}
            disabled={page === totalPages}
            style={{
              padding: '6px 14px', borderRadius: 6, fontSize: 13,
              background: '#1a1f2e', border: '1px solid #2d3548',
              color: page === totalPages ? '#334155' : '#94a3b8', cursor: page === totalPages ? 'not-allowed' : 'pointer',
            }}
          >→</button>
        </div>
      )}
    </div>
  )
}
TSX
success "InputHistory.tsx 生成完了"

# =============================================================================
section "2. InputDetail.tsx — 要望詳細（INPUT → ITEM → ACTION → ISSUE の全連鎖）"
# =============================================================================
cat > "$FRONTEND/pages/InputDetail.tsx" << 'TSX'
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
  other:   { icon: MoreHorizontal, label: 'その他',   color: '#94a3b8' },
}

const INTENT_LABEL: Record<string, { label: string; color: string }> = {
  REQ: { label: '要求',   color: '#818cf8' },
  BUG: { label: 'バグ',   color: '#f87171' },
  IMP: { label: '改善',   color: '#fbbf24' },
  QST: { label: '質問',   color: '#34d399' },
  FBK: { label: 'FBK',   color: '#94a3b8' },
  INF: { label: '情報',   color: '#64748b' },
  MIS: { label: '誤解',   color: '#f97316' },
  OTH: { label: 'その他', color: '#475569' },
}

const ACTION_LABEL: Record<string, { label: string; color: string; bg: string }> = {
  CREATE_ISSUE:  { label: '課題化',  color: '#818cf8', bg: 'rgba(99,102,241,0.15)' },
  ANSWER:        { label: '回答',    color: '#34d399', bg: 'rgba(52,211,153,0.15)' },
  STORE:         { label: '保存',    color: '#60a5fa', bg: 'rgba(59,130,246,0.15)' },
  REJECT:        { label: '却下',    color: '#f87171', bg: 'rgba(239,68,68,0.15)'  },
  HOLD:          { label: '保留',    color: '#fbbf24', bg: 'rgba(245,158,11,0.15)' },
  LINK_EXISTING: { label: '既存紐付', color: '#94a3b8', bg: 'rgba(100,116,139,0.15)'},
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
    <span style={{ fontSize: 12, color: '#64748b' }}>読み込み中...</span>
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
    <div style={{ padding: 40, textAlign: 'center', color: '#64748b' }}>
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
        style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: '#64748b', textDecoration: 'none', fontSize: 13, marginBottom: 20 }}
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
            <div style={{ fontSize: 11, color: '#64748b', fontFamily: 'DM Mono, monospace', marginTop: 2 }}>
              {new Date(input.created_at).toLocaleString('ja-JP')}
              {input.author_name || input.author ? `  /  ${input.author_name ?? input.author}` : ''}
            </div>
          </div>
          <div style={{ marginLeft: 'auto', display: 'flex', gap: 10 }}>
            <div style={{ textAlign: 'right' }}>
              <div style={{ fontSize: 11, color: '#64748b' }}>分解 ITEM</div>
              <div style={{ fontSize: 18, fontWeight: 700, color: '#94a3b8' }}>{items.length}</div>
            </div>
            <div style={{ textAlign: 'right' }}>
              <div style={{ fontSize: 11, color: '#64748b' }}>発生課題</div>
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
        <h2 style={{ margin: '0 0 12px', fontSize: 14, fontWeight: 700, color: '#64748b', letterSpacing: '0.08em', textTransform: 'uppercase' }}>
          分解結果 — {items.length} ITEM
        </h2>

        {items.length === 0 ? (
          <div className="card" style={{ padding: '32px', textAlign: 'center', color: '#64748b', fontSize: 13 }}>
            このINPUTはまだ解析されていません
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {items.map((item, idx) => {
              const intent = INTENT_LABEL[item.intent_code] ?? { label: item.intent_code, color: '#94a3b8' }
              const act = item.action ? (ACTION_LABEL[item.action.action_type] ?? null) : null

              return (
                <div key={item.id} className="card" style={{ padding: '14px 18px' }}>
                  <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
                    {/* Position number */}
                    <div style={{
                      width: 22, height: 22, borderRadius: 6, flexShrink: 0,
                      background: '#2d3548',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      fontSize: 11, fontWeight: 700, color: '#64748b',
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
                        <span className="badge" style={{ background: 'rgba(100,116,139,0.15)', color: '#94a3b8' }}>
                          {item.domain_code}
                        </span>
                        <span style={{ fontSize: 11, color: '#475569', fontFamily: 'DM Mono, monospace' }}>
                          信頼度 {Math.round(item.confidence * 100)}%
                        </span>
                      </div>

                      {/* Item text */}
                      <p style={{ margin: '0 0 8px', fontSize: 13, color: '#e2e8f0', lineHeight: 1.6 }}>
                        {item.text}
                      </p>

                      {/* Action */}
                      {item.action && act && (
                        <div style={{ borderTop: '1px solid #1e2535', paddingTop: 8, marginTop: 4 }}>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                            <span style={{ fontSize: 11, color: '#475569' }}>→ ACTION:</span>
                            <span className="badge" style={{ background: act.bg, color: act.color }}>
                              {act.label}
                            </span>
                            {item.action.decision_reason && (
                              <span style={{ fontSize: 12, color: '#64748b', fontStyle: 'italic' }}>
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
TSX
success "InputDetail.tsx 生成完了"

# =============================================================================
section "3. App.tsx にルート追加"
# =============================================================================
cat > "$FRONTEND/App.tsx" << 'TSX'
import { Routes, Route, Navigate } from 'react-router-dom'
import Layout from '@/components/Layout'
import Dashboard from '@/pages/Dashboard'
import IssueList from '@/pages/IssueList'
import IssueDetail from '@/pages/IssueDetail'
import InputNew from '@/pages/InputNew'
import InputHistory from '@/pages/InputHistory'
import InputDetail from '@/pages/InputDetail'
import Login from '@/pages/Login'
import UserManagement from '@/pages/UserManagement'

function PrivateRoute({ children }: { children: React.ReactNode }) {
  const token = localStorage.getItem('access_token')
  return token ? <>{children}</> : <Navigate to="/login" replace />
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        path="/"
        element={
          <PrivateRoute>
            <Layout />
          </PrivateRoute>
        }
      >
        <Route index element={<Dashboard />} />
        <Route path="issues" element={<IssueList />} />
        <Route path="issues/:id" element={<IssueDetail />} />
        <Route path="inputs/new" element={<InputNew />} />
        <Route path="inputs" element={<InputHistory />} />
        <Route path="inputs/:id" element={<InputDetail />} />
        <Route path="users" element={<UserManagement />} />
      </Route>
    </Routes>
  )
}
TSX
success "App.tsx 更新完了"

# =============================================================================
section "4. Layout.tsx にナビ追加（要望履歴）"
# =============================================================================
cat > "$FRONTEND/components/Layout.tsx" << 'TSX'
import { useState } from 'react'
import { Outlet, NavLink, useNavigate } from 'react-router-dom'
import {
  LayoutDashboard, ListChecks, PlusCircle, Users,
  LogOut, ChevronLeft, ChevronRight, Zap, Bell, History,
} from 'lucide-react'

const NAV = [
  { to: '/',        icon: LayoutDashboard, label: 'ダッシュボード', end: true },
  { to: '/issues',  icon: ListChecks,      label: '課題一覧' },
  { to: '/inputs',  icon: History,         label: '要望履歴' },
  { to: '/inputs/new', icon: PlusCircle,   label: '要望登録' },
  { to: '/users',   icon: Users,           label: 'ユーザー管理' },
]

export default function Layout() {
  const [collapsed, setCollapsed] = useState(false)
  const navigate = useNavigate()

  function logout() {
    localStorage.removeItem('access_token')
    navigate('/login')
  }

  return (
    <div style={{ display: 'flex', minHeight: '100vh', background: '#0f1117' }}>
      {/* Sidebar */}
      <aside
        className={`sidebar${collapsed ? ' collapsed' : ''}`}
        style={{
          position: 'fixed', top: 0, left: 0, height: '100vh',
          background: '#13171f', borderRight: '1px solid #1e2535',
          display: 'flex', flexDirection: 'column', zIndex: 50, overflow: 'hidden',
        }}
      >
        {/* Logo */}
        <div style={{ padding: '20px 16px 16px', display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{
            width: 32, height: 32, borderRadius: 8, flexShrink: 0,
            background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Zap size={16} color="#fff" />
          </div>
          <span className="sidebar-label" style={{ fontWeight: 700, fontSize: 15, color: '#f1f5f9', letterSpacing: '-0.02em' }}>
            decision-os
          </span>
        </div>

        {/* Nav */}
        <nav style={{ flex: 1, padding: '8px' }}>
          {NAV.map(({ to, icon: Icon, label, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              style={({ isActive }) => ({
                display: 'flex', alignItems: 'center', gap: 10,
                padding: '9px 12px', borderRadius: 8, marginBottom: 2,
                color: isActive ? '#818cf8' : '#94a3b8',
                background: isActive ? 'rgba(99,102,241,0.12)' : 'transparent',
                textDecoration: 'none', fontSize: 14,
                fontWeight: isActive ? 600 : 400, transition: 'all 0.15s',
              })}
              onMouseEnter={e => {
                const el = e.currentTarget as HTMLAnchorElement
                if (!el.style.color.includes('818')) {
                  el.style.background = 'rgba(255,255,255,0.04)'
                  el.style.color = '#e2e8f0'
                }
              }}
              onMouseLeave={e => {
                const el = e.currentTarget as HTMLAnchorElement
                if (!el.style.color.includes('818')) {
                  el.style.background = 'transparent'
                  el.style.color = '#94a3b8'
                }
              }}
            >
              <Icon size={18} style={{ flexShrink: 0 }} />
              <span className="sidebar-label">{label}</span>
            </NavLink>
          ))}
        </nav>

        {/* Bottom */}
        <div style={{ padding: '8px 8px 20px', borderTop: '1px solid #1e2535' }}>
          <button
            onClick={logout}
            style={{
              display: 'flex', alignItems: 'center', gap: 10, width: '100%',
              padding: '9px 12px', borderRadius: 8, background: 'transparent',
              border: 'none', color: '#64748b', cursor: 'pointer', fontSize: 14, transition: 'all 0.15s',
            }}
            onMouseEnter={e => { const el = e.currentTarget as HTMLButtonElement; el.style.background = 'rgba(239,68,68,0.1)'; el.style.color = '#ef4444' }}
            onMouseLeave={e => { const el = e.currentTarget as HTMLButtonElement; el.style.background = 'transparent'; el.style.color = '#64748b' }}
          >
            <LogOut size={18} style={{ flexShrink: 0 }} />
            <span className="sidebar-label">ログアウト</span>
          </button>
        </div>

        {/* Toggle */}
        <button
          onClick={() => setCollapsed(!collapsed)}
          style={{
            position: 'absolute', top: '50%', right: -12,
            transform: 'translateY(-50%)', width: 24, height: 24, borderRadius: '50%',
            background: '#1e2535', border: '1px solid #2d3548',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            cursor: 'pointer', color: '#64748b', zIndex: 10,
          }}
        >
          {collapsed ? <ChevronRight size={12} /> : <ChevronLeft size={12} />}
        </button>
      </aside>

      {/* Main */}
      <div style={{
        flex: 1,
        marginLeft: collapsed ? 'var(--sidebar-collapsed-w)' : 'var(--sidebar-w)',
        transition: 'margin-left 0.25s cubic-bezier(0.4,0,0.2,1)',
        display: 'flex', flexDirection: 'column', minHeight: '100vh',
      }}>
        {/* Top bar */}
        <header style={{
          height: 56, background: '#13171f', borderBottom: '1px solid #1e2535',
          display: 'flex', alignItems: 'center', justifyContent: 'flex-end',
          padding: '0 24px', gap: 12, position: 'sticky', top: 0, zIndex: 40,
        }}>
          <button style={{
            width: 36, height: 36, borderRadius: 8, background: 'transparent',
            border: '1px solid #2d3548', display: 'flex', alignItems: 'center',
            justifyContent: 'center', cursor: 'pointer', color: '#64748b',
          }}>
            <Bell size={16} />
          </button>
          <div style={{
            width: 32, height: 32, borderRadius: '50%',
            background: 'linear-gradient(135deg, #6366f1, #8b5cf6)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 13, fontWeight: 600, color: '#fff',
          }}>U</div>
        </header>

        <main style={{ flex: 1, padding: '28px 32px' }}>
          <Outlet />
        </main>
      </div>
    </div>
  )
}
TSX
success "Layout.tsx 更新完了"

# =============================================================================
section "5. 型チェック"
# =============================================================================
cd "$HOME/projects/decision-os/frontend"
npm run typecheck && echo -e "${GREEN}[OK]    型チェック PASS${RESET}" || echo "[WARN]  型警告あり（続行）"

# =============================================================================
section "6. フロントエンド再起動"
# =============================================================================
PID=$(lsof -ti :3008 2>/dev/null || true)
[ -n "$PID" ] && kill "$PID" 2>/dev/null && sleep 2

nohup npm run dev -- --host 0.0.0.0 --port 3008 \
  > "$HOME/projects/decision-os/logs/frontend.log" 2>&1 &
sleep 3

lsof -ti :3008 &>/dev/null \
  && echo -e "${GREEN}[OK]    http://localhost:3008 起動完了${RESET}" \
  || echo "[WARN]  ログ確認: tail -f ~/projects/decision-os/logs/frontend.log"

echo ""
echo -e "${GREEN}✔ 完了！${RESET}"
echo "  サイドバーに「要望履歴」が追加されました"
echo "  http://localhost:3008/inputs        — 一覧"
echo "  http://localhost:3008/inputs/{id}   — 詳細（INPUT→ITEM→ACTION→ISSUE の全連鎖）"
